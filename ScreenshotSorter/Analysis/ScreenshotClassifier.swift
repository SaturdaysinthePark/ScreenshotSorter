import Foundation

/// Structured output of the on-device language model, persisted with the record.
struct ModelInsight: Codable, Sendable, Hashable {
    var primary: ScreenshotCategory?
    var secondary: [ScreenshotCategory]
    /// 0…1
    var confidence: Double
    var app: String?
    var title: String
    var summary: String
    var tags: [String]
}

/// User feedback relevant to one screenshot.
struct UserSignals: Sendable {
    var overrides: [ScreenshotCategory: Bool] = [:]
    var knn: [ScreenshotCategory: Double] = [:]
    var bias: [ScreenshotCategory: Double] = [:]
    var addedTags: [String] = []
    var removedTags: Set<String> = []

    static let none = UserSignals()
}

struct ClassificationOutput: Sendable {
    var categories: [ScoredCategory]
    var app: AppMatch?
    var tags: [ScreenshotTag]
    var entities: [ExtractedEntity]
}

/// Pure, deterministic classification from extracted features. No I/O, no Vision —
/// so it is unit-testable on the simulator and cheap enough to re-run for the whole
/// library when rules change.
enum ScreenshotClassifier {
    static let maxTags = 10

    static func classify(features: ExtractedFeatures,
                         insight: ModelInsight? = nil,
                         user: UserSignals = .none,
                         entities precomputedEntities: [ExtractedEntity]? = nil,
                         includeEntities: Bool = true,
                         config: FusionConfig = .default,
                         rules: RuleEngine = .shared,
                         apps appDetector: AppDetector = .shared) -> ClassificationOutput {
        let text = TextNormalizer.normalize(lines: features.lines)
        let ruleScores = rules.evaluate(text, features: features)
        let appMatches = appDetector.detect(text, features: features)

        var input = FusionInput()
        input.vision = VisionLabelMap.categoryScores(for: features.labels)
        input.rules = ruleScores
        input.apps = appMatches
        input.barcodes = features.barcodes
        input.faces = features.faces
        input.userKNN = user.knn
        input.userOverrides = user.overrides
        input.categoryBias = user.bias
        if let insight {
            var model: [ScreenshotCategory: Double] = [:]
            if let primary = insight.primary { model[primary] = insight.confidence }
            for category in insight.secondary where model[category] == nil {
                model[category] = insight.confidence * 0.65
            }
            input.model = model
        }

        let categories = SignalFusion.fuse(input, config: config)

        let entities: [ExtractedEntity]
        if let precomputedEntities {
            entities = precomputedEntities
        } else if includeEntities {
            entities = EntityExtractor.extract(from: features.fullText)
        } else {
            entities = []
        }

        let bestApp = appMatches.first
        let tags = buildTags(features: features, app: bestApp, insight: insight, entities: entities, user: user)
        return ClassificationOutput(categories: categories, app: bestApp, tags: tags, entities: entities)
    }

    static func normalizeTag(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
    }

    static func buildTags(features: ExtractedFeatures,
                          app: AppMatch?,
                          insight: ModelInsight?,
                          entities: [ExtractedEntity],
                          user: UserSignals) -> [ScreenshotTag] {
        var byValue: [String: ScreenshotTag] = [:]

        func add(_ raw: String, _ score: Double, _ source: LabelSource) {
            let value = normalizeTag(raw)
            guard value.count >= 2, value.count <= 32, !user.removedTags.contains(value) else { return }
            if let existing = byValue[value] {
                byValue[value] = ScreenshotTag(value: value,
                                               score: max(existing.score, score),
                                               sources: existing.sources.union(source))
            } else {
                byValue[value] = ScreenshotTag(value: value, score: score, sources: source)
            }
        }

        if let app { add(app.displayName, app.confidence, .appDetector) }
        if let modelApp = insight?.app, !modelApp.isEmpty { add(modelApp, 0.6, .foundationModel) }
        for (label, confidence) in VisionLabelMap.tags(for: features.labels) {
            add(label, confidence, .visionClassifier)
        }
        for tag in insight?.tags ?? [] { add(tag, 0.8, .foundationModel) }
        for entity in entities {
            switch entity.type {
            case .person, .place, .organization:
                add(entity.value, 0.55, .nameTagger)
            default:
                break
            }
        }
        for tag in user.addedTags { add(tag, 1.0, .user) }

        return byValue.values
            .sorted { lhs, rhs in
                if lhs.sources.contains(.user) != rhs.sources.contains(.user) { return lhs.sources.contains(.user) }
                return lhs.score > rhs.score
            }
            .prefix(maxTags)
            .map { $0 }
    }
}
