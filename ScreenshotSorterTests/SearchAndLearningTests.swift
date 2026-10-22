import Foundation
import Testing
@testable import ScreenshotSorter

struct SearchAndLearningTests {

    /// A collection named "girl" should gather screenshots of girls, not every post that says "girl"
    @Test func collectionSearchIgnoresWordsOnScreen() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("scope-\(UUID().uuidString).sqlite").path
        let store = try AnalysisStore(path: path)
        guard store.isFTSAvailable else { return }
        var shows = AnalysisRecord(id: "shows", createdAt: Date())
        shows.tags = [ScreenshotTag(value: "girl", score: 0.8, sources: .visionClassifier)]
        shows.ocrText = "Saturday in the park"
        var mentions = AnalysisRecord(id: "mentions", createdAt: Date())
        mentions.ocrText = "This girl is on fire, says the review"
        await store.upsert([shows, mentions])
        let search = SearchService(store: store, vectors: VectorIndex())
        var context = SearchContext()
        context.dates = ["shows": Date(), "mentions": Date()]
        let everything = await search.search(QueryParser.parse("girl"), context: context).map(\.id)
        #expect(Set(everything) == ["shows", "mentions"])
        let collection = await search.search(QueryParser.parse("girl"), context: context, scope: .whatItShows).map(\.id)
        #expect(collection == ["shows"])
    }

    /// "cars" is cars, not `car*` (cardholders, card games, pizza cartons); a caption counts when it repeats the
    /// word (caption + hashtag), not when a comment says it once.
    @Test func collectionMatchingIsWholeWordAndNeedsRepeats() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("coll-\(UUID().uuidString).sqlite").path
        let store = try AnalysisStore(path: path)
        guard store.isFTSAvailable else { return }
        func record(_ id: String, tags: [String] = [], ocr: String = "") -> AnalysisRecord {
            var record = AnalysisRecord(id: id, createdAt: Date())
            record.tags = tags.map { ScreenshotTag(value: $0, score: 0.8, sources: .visionClassifier) }
            record.ocrText = ocr
            return record
        }
        await store.upsert([record("car", tags: ["car"]), record("card", tags: ["cardholder"]),
                            record("matcha", ocr: "best matcha in kyoto #matcha #tokyo"),
                            record("once", ocr: "great post, reminds me of matcha"),
                            record("men", tags: ["men's fashion"]), record("man", tags: ["man", "portrait"])])
        let search = SearchService(store: store, vectors: VectorIndex())
        var context = SearchContext()
        for id in ["car", "card", "matcha", "once", "men", "man"] { context.dates[id] = Date() }
        // "man" and "men" are one collection
        for name in ["man", "men"] {
            let found = await search.search(QueryParser.parse(name), context: context, scope: .whatItShows).map(\.id)
            #expect(Set(found) == ["men", "man"])
        }
        #expect(Set(SearchService.wordForms("woman")).isSuperset(of: ["women", "womans"]))
        #expect(SearchService.wordForms("businessmen").contains("businessman"))
        #expect(SearchService.wordForms("dress").contains("dresses"))
        #expect(SearchService.wordForms("party").contains("parties"))
        #expect(SearchService.occurrences(of: ["child"], in: "the children's menu, kids and children") == 2)
        let cars = await search.search(QueryParser.parse("cars"), context: context, scope: .whatItShows).map(\.id)
        #expect(cars == ["car"])
        let matcha = await search.search(QueryParser.parse("matcha"), context: context, scope: .whatItShows).map(\.id)
        #expect(matcha == ["matcha"])
        #expect(SearchService.occurrences(of: ["matcha"], in: "Best Matcha… #matcha") == 2)
    }

    @Test func searchFindsCollectionsByName() {
        func collection(_ kind: CollectionKind, _ title: String, _ count: Int) -> ScreenshotCollection {
            ScreenshotCollection(kind: kind, title: title, icon: "", screenshots: [], count: count)
        }
        let all = [collection(.category(.drinks), ScreenshotCategory.drinks.displayName, 35),
                   collection(.category(.directions), ScreenshotCategory.directions.displayName, 31),
                   collection(.smart(id: "trip"), "Japan Trip", 40),
                   collection(.category(.twitter), ScreenshotCategory.twitter.displayName, 2)]
        let typed = String(ScreenshotCategory.drinks.displayName.lowercased().prefix(3))
        #expect(ScreenshotCollection.matching(typed, in: all).first?.kind == .category(.drinks))
        // A word inside the name, and a category named by a synonym
        #expect(ScreenshotCollection.matching("trip", in: all).map(\.kind) == [.smart(id: "trip")])
        let tweets = QueryParser.parse("tweets").categories
        #expect(ScreenshotCollection.matching("tweets", in: all, categories: tweets).map(\.kind) == [.category(.twitter)])
        #expect(ScreenshotCollection.matching("d", in: all).isEmpty)
    }

    @Test func editDistance() {
        #expect(SearchService.editDistance("recipt", "receipt", limit: 2) == 1)
        #expect(SearchService.editDistance("kitten", "sitting", limit: 3) == 3)
        #expect(SearchService.editDistance("abc", "xyz123", limit: 1) == 2)
    }

    @Test func vectorMatrixNearest() {
        let matrix = VectorMatrix([("a", [1, 0]), ("b", [0, 1]), ("c", [0.8, 0.6])])
        let nearest = matrix.nearest(to: [1, 0], k: 2)
        #expect(nearest.map(\.id) == ["a", "c"])
        var mutable = matrix
        mutable.remove(ids: ["a"])
        #expect(mutable.nearest(to: [1, 0], k: 1).first?.id == "c")
    }

    @Test func singleCorrectionDoesNotPropagate() {
        let neighbours: [(id: String, similarity: Float)] = [("n1", 0.9)]
        let overrides: [String: [ScreenshotCategory: Bool]] = ["n1": [.receipts: true]]
        #expect(UserFeedbackLearner.propagate(neighbours: neighbours, overrides: overrides).isEmpty)
    }

    @Test func agreeingCorrectionsPropagate() {
        let neighbours: [(id: String, similarity: Float)] = [("n1", 0.9), ("n2", 0.85), ("n3", 0.8)]
        let overrides: [String: [ScreenshotCategory: Bool]] = [
            "n1": [.receipts: true, .documents: false],
            "n2": [.receipts: true, .documents: false],
            "n3": [.receipts: true]
        ]
        let result = UserFeedbackLearner.propagate(neighbours: neighbours, overrides: overrides)
        #expect((result[.receipts] ?? 0) > 0.5)
        #expect((result[.documents] ?? 0) < 0)
    }

    @Test func clustererRequiresMinimumSize() {
        // 7 near-identical vectors: below the 8-member minimum → no suggestion
        let small = (0..<7).map { ("s\($0)", [Float(1), Float($0) * 0.001]) }
        #expect(Clusterer.cluster(small).isEmpty)
    }

    @Test func clustererFindsCohesiveGroup() {
        var entries: [(String, [Float])] = []
        for index in 0..<10 {
            let jitter = Float(index) * 0.002
            entries.append(("a\(index)", normalized([1, jitter, 0])))
        }
        for index in 0..<10 {
            let jitter = Float(index) * 0.002
            entries.append(("b\(index)", normalized([0, 1, jitter])))
        }
        let clusters = Clusterer.cluster(entries)
        #expect(clusters.count == 2)
        #expect(clusters.allSatisfy { $0.memberIDs.count >= Clusterer.Parameters().minimumSize })
    }

    /// A real library's TikTok feed formed one 556-screenshot "cluster" (same layout, same tab bar): that's
    /// not a pattern worth suggesting. A shared topic is.
    @Test func smartSuggestionsMustShareATopic() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("smart-\(UUID().uuidString).sqlite").path
        let engine = SmartCollectionEngine(store: try AnalysisStore(path: path), vectors: VectorIndex())
        var context = ClusterContext()
        context.libraryCount = 1_000
        let feed = (0..<30).map { "feed\($0)" }
        for id in feed { context.tags[id] = ["tiktok"]; context.tagDocumentFrequency["tiktok", default: 0] += 1 }
        let sneakers = (0..<20).map { "shoe\($0)" }
        for id in sneakers { context.topic[id] = .shoes; context.tags[id] = ["tiktok"] }
        #expect(await !engine.isCoherent(feed, context: context))
        #expect(await engine.isCoherent(sneakers, context: context))
        let huge = (0..<400).map { "big\($0)" }
        for id in huge { context.topic[id] = .food }
        #expect(await !engine.isCoherent(huge, context: context), "too broad to be a pattern")
    }

    @Test func sameConceptDetection() {
        #expect(SmartCollectionEngine.isSameConcept("Receipts", "Receipts"))
        #expect(!SmartCollectionEngine.isSameConcept("Japan Trip", "Receipts"))
    }

    private func normalized(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return vector.map { $0 / norm }
    }
}
