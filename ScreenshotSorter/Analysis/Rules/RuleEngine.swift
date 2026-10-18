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
        let terms: [String]

        init(_ pattern: RulePattern) {
            self.pattern = pattern
            self.terms = RuleEngine.terms(of: pattern)
        }

        func weight(in text: NormalizedText, features: ExtractedFeatures?) -> Double? {
            RuleEngine.match(self, in: text, features: features)
        }
    }

    private struct CompiledRule: Sendable {
        let category: ScreenshotCategory
        let strong: [(String, Double)]
        let weak: [(String, Double)]
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
                strong: rule.strong.map { (TextNormalizer.normalizeTerm($0.key), $0.value) },
                weak: rule.weak.map { (TextNormalizer.normalizeTerm($0.key), $0.value) },
                patterns: rule.patterns.map { CompiledPattern($0) },
                negative: rule.negative.map { TextNormalizer.normalizeTerm($0) },
                minEvidence: rule.minEvidence,
                minWeakHits: rule.minWeakHits
            )
        }
    }

    private static func terms(of pattern: RulePattern) -> [String] {
        switch pattern {
        case .zone(_, let terms, _), .zoneAllOf(_, let terms, _), .allOf(let terms, _), .countOf(let terms, _, _):
            return terms.map { TextNormalizer.normalizeTerm($0) }
        case .host(let hosts, _):
            return hosts.map { $0.lowercased() }
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

        for rule in rules {
            var weights: [Double] = []
            var matched: [String] = []

            for (term, weight) in rule.strong where text.contains(normalized: term) {
                weights.append(weight)
                matched.append(term)
            }

            for compiled in rule.patterns {
                if let weight = compiled.weight(in: text, features: features) {
                    weights.append(weight)
                    matched.append("<pattern>")
                }
            }

            var weakWeights: [Double] = []
            var weakMatched: [String] = []
            for (term, weight) in rule.weak where text.contains(normalized: term) {
                weakWeights.append(weight)
                weakMatched.append(term)
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
            if score > 0 {
                result[rule.category] = RuleHit(score: score, matched: matched)
            }
        }
        return result
    }

    static func noisyOr(_ weights: [Double]) -> Double {
        1 - weights.reduce(1) { $0 * (1 - min(max($1, 0), 1)) }
    }

    fileprivate static func match(_ compiled: CompiledPattern, in text: NormalizedText, features: ExtractedFeatures?) -> Double? {
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
            return compiled.terms.contains(where: { text.contains(normalized: $0, in: zone) }) ? weight : nil
        case .zoneAllOf(let zone, _, let weight):
            return compiled.terms.allSatisfy({ text.contains(normalized: $0, in: zone) }) ? weight : nil
        case .allOf(_, let weight):
            return compiled.terms.allSatisfy({ text.contains(normalized: $0) }) ? weight : nil
        case .countOf(_, let minimum, let weight):
            let count = compiled.terms.reduce(0) { $0 + (text.contains(normalized: $1) ? 1 : 0) }
            return count >= minimum ? weight : nil
        case .host(_, let weight):
            let hit = text.urlHosts.contains { host in
                compiled.terms.contains { host == $0 || host.hasSuffix("." + $0) }
            }
            return hit ? weight : nil
        case .textDensity(let minimum, let weight):
            guard let features else { return nil }
            return features.textDensity >= minimum ? weight : nil
        case .lineCount(let minimum, let weight):
            return text.lineCount >= minimum ? weight : nil
        }
    }
}
