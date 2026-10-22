import Foundation

/// Structural patterns a rule can match besides plain terms.
enum RulePattern: Sendable {
    case priceCount(min: Int, weight: Double)
    case handleCount(min: Int, weight: Double)
    case hashtagCount(min: Int, weight: Double)
    case timeCount(min: Int, weight: Double)
    case subredditCount(min: Int, weight: Double)
    /// Any of the terms appears inside the given screen zone
    case zone(ScreenZone, anyOf: [String], weight: Double)
    /// All of the terms appear inside the given screen zone (e.g. a tab bar)
    case zoneAllOf(ScreenZone, [String], weight: Double)
    /// All of the terms appear anywhere
    case allOf([String], weight: Double)
    /// At least `min` of the terms appear anywhere
    case countOf([String], min: Int, weight: Double)
    /// A detected URL host ends with one of these
    case host([String], weight: Double)
    case textDensity(min: Double, weight: Double)
    case lineCount(min: Int, weight: Double)
    /// Layout cues computed from the raw OCR lines (see `LayoutSignals`)
    case capsCaption(minLines: Int, weight: Double)
    case quoteAttribution(weight: Double)
    case timeRangeCount(min: Int, weight: Double)
    case relativeTimeCount(min: Int, weight: Double)
    case lockScreenDate(weight: Double)
}

/// Layout cues that keywords can't express, read once per screenshot from the raw OCR lines.
struct LayoutSignals: Sendable {
    /// Lines of ≥3 words written in capitals with no prices, codes or links (meme captions)
    var capsCaptionLines = 0
    /// A price anywhere on screen ("$150", "¥98,000"): ad banners and shop pages shout in capitals too
    var hasPrice = false
    /// Vertical distance between the highest and lowest caps line (top + bottom captions, not a sign)
    var capsCaptionSpread = 0.0
    var lineCount = 0
    /// An opening quote mark plus a short "— Name" line
    var hasQuoteAttribution = false
    /// "10:00 – 11:00 AM" style ranges (calendars, event listings)
    var timeRanges = 0
    /// "now", "2m ago", "1h ago", "5 min ago" (notification stacks)
    var relativeTimes = 0
    /// "Monday, October 20" on its own line near the top (lock screen)
    var hasLockScreenDate = false

    /// Not caption text: prices, percentages, handles, links and multi-digit numbers ("30-DAY RETURNS", "USE CODE 150")
    private static let notCaption = try! NSRegularExpression(
        pattern: #"[$€£¥₩%@]|\d{2}|\w\.(com|co|net|org|io|shop|store)\b"#, options: [.caseInsensitive])
    private static let price = try! NSRegularExpression(pattern: #"[$€£¥₩]\s?\d|\d\s?[$€£¥₩]"#)
    private static let timeRange = try! NSRegularExpression(
        pattern: #"\b\d{1,2}(:\d{2})?\s*(am|pm)?\s*[–—-]\s*\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: [.caseInsensitive])
    private static let relative = try! NSRegularExpression(
        pattern: #"^(now|\d{1,2}\s?(m|min|h|hr|d)\s?ago|\d{1,2}\s?(minutes?|hours?)\s?ago)$"#, options: [.caseInsensitive])
    private static let weekdayDate = try! NSRegularExpression(
        pattern: #"^(monday|tuesday|wednesday|thursday|friday|saturday|sunday),?\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}$"#,
        options: [.caseInsensitive])

    init() {}

    init(lines: [OCRLine]) {
        lineCount = lines.count
        var sawQuoteOpen = false
        var capsTop = 1.0
        var capsBottom = 0.0
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let range = NSRange(text.startIndex..., in: text)
            let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            if LayoutSignals.price.firstMatch(in: text, options: [], range: range) != nil { hasPrice = true }
            if letters.count >= 8, text.split(separator: " ").count >= 3,
               LayoutSignals.notCaption.firstMatch(in: text, options: [], range: range) == nil {
                let upper = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
                if Double(upper) / Double(letters.count) > 0.85 {
                    capsCaptionLines += 1
                    capsTop = min(capsTop, Double(line.box.minY))
                    capsBottom = max(capsBottom, Double(line.box.maxY))
                }
            }
            if let first = text.first, "“\"«„".contains(first), text.count > 12 { sawQuoteOpen = true }
            if sawQuoteOpen, let first = text.first, "—–-~".contains(first), text.count < 40,
               text.dropFirst().trimmingCharacters(in: .whitespaces).first?.isUppercase == true {
                hasQuoteAttribution = true
            }
            timeRanges += LayoutSignals.timeRange.numberOfMatches(in: text, options: [], range: range)
            if LayoutSignals.relative.firstMatch(in: text, options: [], range: range) != nil { relativeTimes += 1 }
            if line.box.minY < 0.25, LayoutSignals.weekdayDate.firstMatch(in: text, options: [], range: range) != nil {
                hasLockScreenDate = true
            }
        }
        capsCaptionSpread = max(0, capsBottom - capsTop)
    }
}

/// Declarative keyword/pattern rule for one category.
///
/// Weights read as "how likely is this category given this evidence"; evidence is
/// combined with noisy-OR so several weak hints can add up to a confident result.
struct CategoryRule: Sendable {
    let category: ScreenshotCategory
    var strong: [String: Double] = [:]
    var weak: [String: Double] = [:]
    var patterns: [RulePattern] = []
    /// Terms that make this category unlikely (each subtracts `negativePenalty`)
    var negative: [String] = []
    /// Minimum number of evidence hits before the rule fires at all
    var minEvidence: Int = 1
    /// Weak terms only count when at least this many matched (or a strong/pattern hit exists)
    var minWeakHits: Int = 2
}

struct RuleHit: Sendable {
    let score: Double
    let matched: [String]
}

/// Evaluates `CategoryRules` against normalized OCR text.
struct RuleEngine: Sendable {
    static let negativePenalty = 0.3

    struct CompiledPattern: Sendable {
        let pattern: RulePattern
        let terms: [MatchTerm]

        init(_ pattern: RulePattern) {
            self.pattern = pattern
            self.terms = RuleEngine.terms(of: pattern)
        }

        func weight(in text: NormalizedText, features: ExtractedFeatures?, layout: LayoutSignals = LayoutSignals()) -> Double? {
            RuleEngine.match(self, in: text, features: features, layout: layout)
        }
    }

    private struct CompiledRule: Sendable {
        let category: ScreenshotCategory
        let strong: [(MatchTerm, Double)]
        let weak: [(MatchTerm, Double)]
        let patterns: [CompiledPattern]
        let negative: [String]
        let minEvidence: Int
        let minWeakHits: Int
    }

    private let rules: [CompiledRule]

    static let shared = RuleEngine(rules: CategoryRules.all)

    init(rules: [CategoryRule]) {
        self.rules = rules.map { rule in
            CompiledRule(
                category: rule.category,
                // Strongest first, so a word listed twice ("check in" / "check-in", "sofa" strong and weak) counts once at its best weight
                strong: rule.strong.map { (MatchTerm(TextNormalizer.normalizeTerm($0.key)), $0.value) }.sorted { $0.1 > $1.1 },
                weak: rule.weak.map { (MatchTerm(TextNormalizer.normalizeTerm($0.key)), $0.value) }.sorted { $0.1 > $1.1 },
                patterns: rule.patterns.map { CompiledPattern($0) },
                negative: rule.negative.map { TextNormalizer.normalizeTerm($0) },
                minEvidence: rule.minEvidence,
                minWeakHits: rule.minWeakHits
            )
        }
    }

    private static func terms(of pattern: RulePattern) -> [MatchTerm] {
        switch pattern {
        case .zone(_, let terms, _), .zoneAllOf(_, let terms, _), .allOf(let terms, _), .countOf(let terms, _, _):
            return terms.map { MatchTerm(TextNormalizer.normalizeTerm($0)) }
        case .host(let hosts, _):
            return hosts.map { MatchTerm($0.lowercased()) }
        default:
            return []
        }
    }

    /// Scores every category with at least one hit.
    func evaluate(_ text: NormalizedText, features: ExtractedFeatures? = nil) -> [ScreenshotCategory: Double] {
        var result: [ScreenshotCategory: Double] = [:]
        for (category, hit) in evaluateDetailed(text, features: features) {
            result[category] = hit.score
        }
        return result
    }

    func evaluateDetailed(_ text: NormalizedText, features: ExtractedFeatures? = nil) -> [ScreenshotCategory: RuleHit] {
        guard !text.isEmpty else { return [:] }
        var result: [ScreenshotCategory: RuleHit] = [:]
        let layout = features.map { LayoutSignals(lines: $0.lines) } ?? LayoutSignals()

        for rule in rules {
            var weights: [Double] = []
            var matched: [String] = []
            // "drink" and "drinks", "shoe" and "shoes" are one piece of evidence
            var stems: Set<String> = []

            for (term, weight) in rule.strong where text.contains(term) && stems.insert(term.stem).inserted {
                weights.append(weight)
                matched.append(term.text)
            }

            for compiled in rule.patterns {
                if let weight = compiled.weight(in: text, features: features, layout: layout) {
                    weights.append(weight)
                    matched.append("<pattern>")
                }
            }

            var weakWeights: [Double] = []
            var weakMatched: [String] = []
            for (term, weight) in rule.weak where text.contains(term) && stems.insert(term.stem).inserted {
                weakWeights.append(weight)
                weakMatched.append(term.text)
            }
            if !weakWeights.isEmpty && (weakWeights.count >= rule.minWeakHits || !weights.isEmpty) {
                weights.append(contentsOf: weakWeights)
                matched.append(contentsOf: weakMatched)
            }

            guard weights.count >= rule.minEvidence, !weights.isEmpty else { continue }

            var score = RuleEngine.noisyOr(weights)
            for term in rule.negative where text.contains(normalized: term) {
                score -= RuleEngine.negativePenalty
            }
            score = min(max(score, 0), 1)
            // A category may have several rules (e.g. layout vs. wording); keep the strongest.
            if score > 0, score > (result[rule.category]?.score ?? 0) {
                result[rule.category] = RuleHit(score: score, matched: matched)
            }
        }
        return result
    }

    /// Categories a rule's negative terms rule out on this screen ("film simulation" for recipes): other sources,
    /// the language model above all, mustn't add them back
    func ruledOut(_ text: NormalizedText) -> Set<ScreenshotCategory> {
        Set(rules.filter { rule in rule.negative.contains { text.contains(normalized: $0) } }.map(\.category))
    }

    static func noisyOr(_ weights: [Double]) -> Double {
        1 - weights.reduce(1) { $0 * (1 - min(max($1, 0), 1)) }
    }

    fileprivate static func match(_ compiled: CompiledPattern, in text: NormalizedText, features: ExtractedFeatures?, layout: LayoutSignals) -> Double? {
        switch compiled.pattern {
        case .priceCount(let minimum, let weight):
            return text.priceCount >= minimum ? weight : nil
        case .handleCount(let minimum, let weight):
            return text.handleCount >= minimum ? weight : nil
        case .hashtagCount(let minimum, let weight):
            return text.hashtagCount >= minimum ? weight : nil
        case .timeCount(let minimum, let weight):
            return text.timeCount >= minimum ? weight : nil
        case .subredditCount(let minimum, let weight):
            return text.subredditCount >= minimum ? weight : nil
        case .zone(let zone, _, let weight):
            return compiled.terms.contains(where: { text.contains(normalized: $0.text, in: zone) }) ? weight : nil
        case .zoneAllOf(let zone, _, let weight):
            return compiled.terms.allSatisfy({ text.contains(normalized: $0.text, in: zone) }) ? weight : nil
        case .allOf(_, let weight):
            return compiled.terms.allSatisfy({ text.contains($0) }) ? weight : nil
        case .countOf(_, let minimum, let weight):
            let count = compiled.terms.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            return count >= minimum ? weight : nil
        case .host(_, let weight):
            let hit = text.urlHosts.contains { host in
                compiled.terms.contains { host == $0.text || host.hasSuffix("." + $0.text) }
            }
            return hit ? weight : nil
        case .textDensity(let minimum, let weight):
            guard let features else { return nil }
            return features.textDensity >= minimum ? weight : nil
        case .lineCount(let minimum, let weight):
            return text.lineCount >= minimum ? weight : nil
        case .capsCaption(let minLines, let weight):
            // Few lines overall: a feed, menu or article full of headings is not a meme, nor is anything with a price
            return layout.capsCaptionLines >= minLines && layout.lineCount <= 10 && !layout.hasPrice
                && layout.capsCaptionSpread >= 0.25 ? weight : nil
        case .quoteAttribution(let weight):
            return layout.hasQuoteAttribution && layout.lineCount <= 14 ? weight : nil
        case .timeRangeCount(let minimum, let weight):
            return layout.timeRanges >= minimum ? weight : nil
        case .relativeTimeCount(let minimum, let weight):
            return layout.relativeTimes >= minimum ? weight : nil
        case .lockScreenDate(let weight):
            return layout.hasLockScreenDate ? weight : nil
        }
    }
}
