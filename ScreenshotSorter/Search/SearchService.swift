import Foundation

struct SearchHit: Sendable, Identifiable, Hashable {
    let id: String
    let score: Double
    /// OCR excerpt with matches wrapped in [ ]
    let snippet: String?
}

/// Library metadata the search needs for filtering and boosting (snapshot from `LibraryStore`).
struct SearchContext: Sendable {
    var dates: [String: Date] = [:]
    var categories: [String: Set<ScreenshotCategory>] = [:]
    /// Lowercased app display names
    var apps: [String: String] = [:]
    var entityTypes: [String: Set<EntityType>] = [:]
}

/// What a query is matched against.
enum SearchScope: Sendable {
    /// Every word on screen too: finds an order number, a quote, a name in a chat
    case everything
    /// Only what a screenshot shows (title, tags, Vision labels, meaning), not every word in it: for filling a
    /// collection, where "girl" should mean pictures of girls, not every post that says "girl"
    case whatItShows
}

/// Hybrid search: FTS5 BM25 (prefix + typo tolerant) + trigram substrings + semantic embeddings,
/// combined with reciprocal rank fusion.
actor SearchService {
    static let rrfK = 60.0
    static let lexicalWeight = 1.0
    static let semanticWeight = 0.8
    static let trigramWeight = 0.6
    static let semanticFloor: Float = 0.45
    static let maxResults = 300

    private let store: AnalysisStore
    private let vectors: VectorIndex
    private let embedder: TextEmbedder

    private var vocabulary: [String] = []
    private var vocabularySet: Set<String> = []
    private var vocabularyLoadedAt = Date.distantPast

    init(store: AnalysisStore, vectors: VectorIndex, embedder: TextEmbedder = .shared) {
        self.store = store
        self.vectors = vectors
        self.embedder = embedder
    }

    /// Meaning matches must be this close when OCR text doesn't count
    static let whatItShowsSemanticFloor: Float = 0.55
    /// Times a name must appear in a screenshot's text for the text alone to put it in a collection
    static let mentionRepeats = 2

    /// Whole-word occurrences of any of the terms (singular or plural) in `text`
    static func occurrences(of terms: [String], in text: String) -> Int {
        let tokens = TextNormalizer.tokenize(text.lowercased())
        let forms = Set(terms.flatMap { term -> [String] in
            let lowered = term.lowercased()
            return [lowered, TextNormalizer.stem(lowered), lowered + "s"]
        })
        let singleWords = forms.filter { !$0.contains(" ") }
        let phrases = forms.filter { $0.contains(" ") }
        var count = tokens.filter { singleWords.contains($0) || singleWords.contains(TextNormalizer.stem($0)) }.count
        let joined = " " + tokens.joined(separator: " ") + " "
        for phrase in phrases { count += joined.components(separatedBy: " " + phrase + " ").count - 1 }
        return count
    }

    func search(_ query: ParsedQuery, context: SearchContext, scope: SearchScope = .everything, now: Date = Date()) async -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        let allowed = filterIDs(query, context: context)

        // Filters only ("receipts from last week") → newest first
        if !query.hasFreeText {
            let ids = (allowed ?? Set(context.dates.keys)).sorted {
                (context.dates[$0] ?? .distantPast) > (context.dates[$1] ?? .distantPast)
            }
            return ids.prefix(SearchService.maxResults).map { SearchHit(id: $0, score: 1, snippet: nil) }
        }

        await refreshVocabularyIfNeeded()

        // Lexical
        func expression(_ joiner: String) -> String {
            scope == .whatItShows
                ? "{title tags} : (" + wholeWordExpression(query, joiner: joiner) + ")"
                : matchExpression(query, joiner: joiner)
        }
        var lexical = await store.ftsSearch(match: expression(" "), limit: SearchService.maxResults)
        if lexical.isEmpty && query.terms.count > 1 {
            lexical = await store.ftsSearch(match: expression(" OR "), limit: SearchService.maxResults)
        }
        if !store.isFTSAvailable && scope == .everything {
            let ids = await store.likeSearch(query.freeText, limit: SearchService.maxResults)
            lexical = ids.enumerated().map { FTSHit(id: $0.element, rank: Double($0.offset), snippet: nil) }
        }

        // Substrings (order numbers, codes, partial words)
        var trigram: [String] = []
        if lexical.count < 20 && scope == .everything {
            trigram = await store.trigramSearch(query.freeText, limit: 100)
        }

        // Semantic
        var semantic: [(id: String, similarity: Float)] = []
        if let vector = await embedder.embed(query.freeText) {
            semantic = await vectors.textNearest(to: vector, k: 400, minimum: SearchService.semanticFloor)
        }

        // Collections: a word on screen counts when it's repeated (a caption and its hashtag, "best matcha… #matcha"),
        // not when it's said once in passing ("this girl is on fire" in a comment). Meaning alone can't decide:
        // the sentence embedding scores a one-word name against a whole screenshot near zero either way.
        if scope == .whatItShows {
            let mentions = await store.ftsSearch(match: "{ocr} : (" + wholeWordExpression(query, joiner: " ") + ")",
                                                 limit: SearchService.maxResults)
            let known = Set(lexical.map(\.id))
            let candidates = mentions.filter { !known.contains($0.id) }
            let texts = await store.ocrTexts(ids: candidates.map(\.id))
            lexical += candidates.filter { hit in
                SearchService.occurrences(of: query.terms + query.phrases, in: texts[hit.id] ?? "") >= SearchService.mentionRepeats
            }
        }

        // Reciprocal rank fusion
        var scores: [String: Double] = [:]
        var snippets: [String: String] = [:]
        for (rank, hit) in lexical.enumerated() {
            scores[hit.id, default: 0] += SearchService.lexicalWeight / (SearchService.rrfK + Double(rank + 1))
            if let snippet = hit.snippet, !snippet.isEmpty { snippets[hit.id] = snippet }
        }
        for (rank, id) in trigram.enumerated() {
            scores[id, default: 0] += SearchService.trigramWeight / (SearchService.rrfK + Double(rank + 1))
        }
        let rankedSemantic = scope == .whatItShows ? semantic.filter { $0.similarity >= SearchService.whatItShowsSemanticFloor } : semantic
        for (rank, hit) in rankedSemantic.prefix(200).enumerated() {
            scores[hit.id, default: 0] += SearchService.semanticWeight / (SearchService.rrfK + Double(rank + 1))
        }

        // Boosts
        for id in scores.keys {
            var boost = 0.0
            if !query.categories.isEmpty, let categories = context.categories[id], !categories.isDisjoint(with: query.categories) {
                boost += 0.03
            }
            if !query.apps.isEmpty, let app = context.apps[id], query.apps.contains(app) {
                boost += 0.03
            }
            if let date = context.dates[id] {
                let ageDays = max(0, now.timeIntervalSince(date) / 86_400)
                boost += 0.006 * exp(-ageDays / 180)
            }
            scores[id, default: 0] += boost
        }

        return scores
            .filter { allowed?.contains($0.key) ?? true }
            .filter { context.dates[$0.key] != nil }
            .sorted { $0.value > $1.value }
            .prefix(SearchService.maxResults)
            .map { SearchHit(id: $0.key, score: $0.value, snippet: snippets[$0.key]) }
    }

    /// Hard filters: dates and entity types always; categories/apps only when there's no free text
    /// (with free text they boost instead, so "nike receipts" still finds a Nike order confirmation).
    private func filterIDs(_ query: ParsedQuery, context: SearchContext) -> Set<String>? {
        var allowed: Set<String>?
        func intersect(_ ids: Set<String>) {
            allowed = allowed.map { $0.intersection(ids) } ?? ids
        }
        if let range = query.dateRange {
            intersect(Set(context.dates.filter { range.contains($0.value) }.keys))
        }
        if !query.entityTypes.isEmpty {
            intersect(Set(context.entityTypes.filter { !$0.value.isDisjoint(with: query.entityTypes) }.keys))
        }
        if !query.hasFreeText {
            if !query.categories.isEmpty || !query.apps.isEmpty {
                var matching = Set<String>()
                if !query.categories.isEmpty {
                    matching.formUnion(context.categories.filter { !$0.value.isDisjoint(with: query.categories) }.keys)
                }
                if !query.apps.isEmpty {
                    matching.formUnion(context.apps.filter { query.apps.contains($0.value) }.keys)
                }
                intersect(matching)
            }
        }
        return allowed
    }

    // MARK: - FTS expression

    func matchExpression(_ query: ParsedQuery, joiner: String) -> String {
        var clauses: [String] = query.phrases.map { SearchService.quote($0) }
        for term in query.terms {
            let corrections = typoCandidates(for: term)
            let base = SearchService.quote(term) + "*"
            if corrections.isEmpty {
                clauses.append(base)
            } else {
                clauses.append("(" + ([base] + corrections.map { SearchService.quote($0) }).joined(separator: " OR ") + ")")
            }
        }
        return clauses.joined(separator: joiner)
    }

    /// Whole words only, singular or plural, no typo guesses: a collection called "cars" must not fill up with
    /// cardholders, card games and pizza cartons (all `car*`)
    func wholeWordExpression(_ query: ParsedQuery, joiner: String) -> String {
        var clauses: [String] = query.phrases.map { SearchService.quote($0) }
        for term in query.terms {
            var forms: Set<String> = [term, TextNormalizer.stem(term)]
            if !term.hasSuffix("s") { forms.insert(term + "s") }
            clauses.append("(" + forms.sorted().map { SearchService.quote($0) }.joined(separator: " OR ") + ")")
        }
        return clauses.joined(separator: joiner)
    }

    static func quote(_ term: String) -> String {
        "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Typo tolerance

    private func refreshVocabularyIfNeeded() async {
        guard Date().timeIntervalSince(vocabularyLoadedAt) > 120 else { return }
        vocabulary = await store.vocabulary()
        vocabularySet = Set(vocabulary)
        vocabularyLoadedAt = Date()
    }

    /// Vocabulary words within edit distance 1 (2 for long words) of an unknown term.
    func typoCandidates(for term: String) -> [String] {
        guard term.count >= 4, !vocabularySet.contains(term), !vocabularySet.isEmpty,
              !vocabulary.contains(where: { $0.hasPrefix(term) }) else { return [] }
        let maxDistance = term.count >= 7 ? 2 : 1
        var found: [(String, Int)] = []
        for word in vocabulary where abs(word.count - term.count) <= maxDistance {
            let distance = SearchService.editDistance(term, word, limit: maxDistance)
            if distance <= maxDistance { found.append((word, distance)) }
        }
        return found.sorted { $0.1 < $1.1 }.prefix(5).map(\.0)
    }

    /// Levenshtein distance with an early exit once `limit` is exceeded.
    static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMinimum = min(rowMinimum, current[j])
            }
            if rowMinimum > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
