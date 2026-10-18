import Foundation
import NaturalLanguage

/// Tokenized, case/diacritic-folded view of OCR text with whole-word matching.
///
/// All matching is on token boundaries, so "cat" never matches "location" and
/// "file" never matches "profile". Multi-word terms match consecutive tokens.
struct NormalizedText: Sendable {
    let tokens: [String]
    let tokenSet: Set<String>
    let stems: Set<String>
    let zoneTokens: [ScreenZone: Set<String>]
    let priceCount: Int
    let handleCount: Int
    let hashtagCount: Int
    let timeCount: Int
    let subredditCount: Int
    let urlHosts: [String]
    let lineCount: Int
    let characterCount: Int

    /// " tok tok tok " — padded so phrase lookups can require boundaries
    private let joined: String
    private let zoneJoined: [ScreenZone: String]

    init(tokens: [String],
         zoneTokenLists: [ScreenZone: [String]],
         priceCount: Int,
         handleCount: Int,
         hashtagCount: Int,
         timeCount: Int,
         subredditCount: Int,
         urlHosts: [String],
         lineCount: Int,
         characterCount: Int) {
        self.tokens = tokens
        self.tokenSet = Set(tokens)
        var stems = Set<String>()
        for token in tokens { stems.insert(TextNormalizer.stem(token)) }
        self.stems = stems
        self.joined = " " + tokens.joined(separator: " ") + " "
        var zoneJoined: [ScreenZone: String] = [:]
        var zoneTokens: [ScreenZone: Set<String>] = [:]
        for (zone, list) in zoneTokenLists {
            zoneJoined[zone] = " " + list.joined(separator: " ") + " "
            zoneTokens[zone] = Set(list)
        }
        self.zoneJoined = zoneJoined
        self.zoneTokens = zoneTokens
        self.priceCount = priceCount
        self.handleCount = handleCount
        self.hashtagCount = hashtagCount
        self.timeCount = timeCount
        self.subredditCount = subredditCount
        self.urlHosts = urlHosts
        self.lineCount = lineCount
        self.characterCount = characterCount
    }

    var isEmpty: Bool { tokens.isEmpty }

    /// `term` must already be normalized with `TextNormalizer.normalizeTerm`.
    func contains(normalized term: String) -> Bool {
        guard !term.isEmpty else { return false }
        if !term.contains(" ") {
            return tokenSet.contains(term) || stems.contains(TextNormalizer.stem(term))
        }
        return joined.contains(" " + term + " ")
    }

    func contains(normalized term: String, in zone: ScreenZone) -> Bool {
        guard !term.isEmpty else { return false }
        if !term.contains(" ") {
            return zoneTokens[zone]?.contains(term) ?? false
        }
        return zoneJoined[zone]?.contains(" " + term + " ") ?? false
    }

    /// Convenience for un-normalized terms (normalizes on every call — prefer pre-normalized terms in hot paths)
    func contains(_ term: String) -> Bool {
        contains(normalized: TextNormalizer.normalizeTerm(term))
    }

    func contains(_ term: String, in zone: ScreenZone) -> Bool {
        contains(normalized: TextNormalizer.normalizeTerm(term), in: zone)
    }

    /// Number of occurrences of a single-token term
    func count(of token: String) -> Int {
        tokens.reduce(0) { $0 + ($1 == token ? 1 : 0) }
    }
}

enum TextNormalizer {

    // MARK: Regexes (compiled once)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are static literals; an invalid one is a programmer error caught by unit tests.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    static let priceRegex = regex(#"([$€£¥₹]\s?\d[\d,]*(\.\d{1,2})?)|(\d[\d,]*\.\d{2}\s?(usd|eur|gbp|cad|aud))"#)
    static let handleRegex = regex(#"(?<![\w.])@[A-Za-z0-9_]{2,30}"#)
    static let hashtagRegex = regex(#"(?<![\w&])#[A-Za-z][A-Za-z0-9_]{1,40}"#)
    static let timeRegex = regex(#"\b([01]?\d|2[0-3]):[0-5]\d(\s?[AaPp]\.?[Mm]\.?)?\b"#)
    static let subredditRegex = regex(#"(?<![\w])[ru]/[A-Za-z0-9_]{2,30}"#)
    static let hostRegex = regex(#"\b((?:[a-z0-9-]+\.)+(?:com|org|net|io|co|app|dev|edu|gov|ai|me|tv|ly|us|uk|ca|de|fr|news|shop|store))\b"#)

    // MARK: Folding & tokenizing

    static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    static func tokenize(_ string: String) -> [String] {
        let folded = fold(string)
        guard !folded.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = folded
        var result: [String] = []
        tokenizer.enumerateTokens(in: folded.startIndex..<folded.endIndex) { range, _ in
            let token = String(folded[range])
            if !token.isEmpty { result.append(token) }
            return true
        }
        return result
    }

    /// Normalize a dictionary term the same way OCR text is normalized.
    static func normalizeTerm(_ term: String) -> String {
        tokenize(term).joined(separator: " ")
    }

    /// Very light English stemmer: enough to match plurals and simple verb forms.
    static func stem(_ token: String) -> String {
        guard token.count > 4 else {
            if token.count > 3 && token.hasSuffix("s") && !token.hasSuffix("ss") {
                return String(token.dropLast())
            }
            return token
        }
        if token.hasSuffix("ies") { return String(token.dropLast(3)) + "y" }
        if token.hasSuffix("ing") && token.count > 5 { return String(token.dropLast(3)) }
        if token.hasSuffix("es") && (token.hasSuffix("ches") || token.hasSuffix("shes") || token.hasSuffix("xes")) {
            return String(token.dropLast(2))
        }
        if token.hasSuffix("ed") && token.count > 5 { return String(token.dropLast(2)) }
        if token.hasSuffix("s") && !token.hasSuffix("ss") && !token.hasSuffix("us") { return String(token.dropLast()) }
        return token
    }

    // MARK: Normalization

    static func normalize(lines: [OCRLine]) -> NormalizedText {
        var allTokens: [String] = []
        var zoneLists: [ScreenZone: [String]] = [:]
        var nonStatusText = ""
        var fullText = ""

        for line in lines {
            let lineTokens = tokenize(line.text)
            allTokens.append(contentsOf: lineTokens)
            zoneLists[line.zone, default: []].append(contentsOf: lineTokens)
            fullText += line.text + "\n"
            if line.zone != .statusBar {
                nonStatusText += line.text + "\n"
            }
        }

        let ns = fullText as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let nonStatusNS = nonStatusText as NSString
        let nonStatusRange = NSRange(location: 0, length: nonStatusNS.length)

        let foldedFull = fold(fullText)
        let foldedNS = foldedFull as NSString
        var hosts: [String] = []
        hostRegex.enumerateMatches(in: foldedFull, options: [], range: NSRange(location: 0, length: foldedNS.length)) { match, _, _ in
            guard let match else { return }
            let host = foldedNS.substring(with: match.range(at: 1))
            if !hosts.contains(host) { hosts.append(host) }
        }

        return NormalizedText(
            tokens: allTokens,
            zoneTokenLists: zoneLists,
            priceCount: priceRegex.numberOfMatches(in: fullText, options: [], range: fullRange),
            handleCount: handleRegex.numberOfMatches(in: fullText, options: [], range: fullRange),
            hashtagCount: hashtagRegex.numberOfMatches(in: fullText, options: [], range: fullRange),
            timeCount: timeRegex.numberOfMatches(in: nonStatusText, options: [], range: nonStatusRange),
            subredditCount: subredditRegex.numberOfMatches(in: fullText, options: [], range: fullRange),
            urlHosts: hosts,
            lineCount: lines.count,
            characterCount: fullText.count
        )
    }

    /// Normalize free text (e.g. a search query or test fixture) as if it were all body text.
    static func normalize(text: String) -> NormalizedText {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { OCRLine(text: String($0), confidence: 1, box: .zero, zone: .body) }
        return normalize(lines: lines)
    }
}
