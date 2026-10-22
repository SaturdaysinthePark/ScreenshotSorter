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
    /// Product types worth surfacing on a shopping page ("a sofa", not just "a store")
    static let productCategories: [ScreenshotCategory] = [.clothes, .shoes, .watches, .bags, .jewelry, .furniture, .electronics]
    /// Store-rule score above which a page counts as a product listing
    static let productPageThreshold = 0.75
    /// A photo saved full screen has a handful of OCR lines (clock, URL pill); a feed or article has dozens.
    /// Pictures inside text-heavy screens (a news photo, an avatar) are not what the screenshot is of,
    /// so visual evidence fades from 1 at `photoLineCount` lines to `textHeavyVisionScale` at `textHeavyLineCount`.
    static let photoLineCount = 8
    static let textHeavyLineCount = 30
    static let textHeavyVisionScale = 0.45
    /// People in a painting are art, not "People"
    static let artSuppressesPeople = 0.6
    /// The language model only sees OCR text and reports ~0.9 confidence whatever it decides. On a real
    /// 1,900-screenshot library its picks were wrong more often than right when nothing else agreed, so it
    /// corroborates other evidence but can't add a category by itself (primary alone ≈ 0.41 < threshold).
    /// A single product/food word on a screen with this many lines is damped by `singleMentionScale`
    static let singleMentionLineCount = 15
    static let singleMentionScale = 0.6
    static let modelPrimaryWeight = 0.5
    static let modelSecondaryWeight = 0.3

    static func visionScale(lineCount: Int) -> Double {
        guard lineCount > photoLineCount else { return 1 }
        let t = min(1, Double(lineCount - photoLineCount) / Double(textHeavyLineCount - photoLineCount))
        return 1 - t * (1 - textHeavyVisionScale)
    }

    static func classify(features: ExtractedFeatures,
                         insight: ModelInsight? = nil,
                         user: UserSignals = .none,
                         entities precomputedEntities: [ExtractedEntity]? = nil,
                         includeEntities: Bool = true,
                         config: FusionConfig = .default,
                         rules: RuleEngine = .shared,
                         apps appDetector: AppDetector = .shared) -> ClassificationOutput {
        let text = TextNormalizer.normalize(lines: features.lines)
        let contentLines = features.lines.filter { $0.zone != .statusBar }.count
        var ruleScores: [ScreenshotCategory: Double] = [:]
        for (category, hit) in rules.evaluateDetailed(text, features: features) {
            // One passing mention of a product or dish inside an article or feed ("a potent cocktail of…",
            // a bracelet in a history text) is not what the screenshot is of
            let passingMention = category.kind == .mixed && hit.matched.count == 1 && contentLines >= singleMentionLineCount
            ruleScores[category] = passingMention ? hit.score * singleMentionScale : hit.score
        }
        if (ruleScores[.stores] ?? 0) >= productPageThreshold {
            for category in productCategories {
                if let score = ruleScores[category] { ruleScores[category] = RuleEngine.noisyOr([score, 0.5]) }
            }
        }
        let appMatches = appDetector.detect(text, features: features)

        var input = FusionInput()
        var vision = VisionLabelMap.categoryScores(for: features.labels)
        let scale = visionScale(lineCount: contentLines)
        if scale < 1 {
            for (category, score) in vision where category.kind == .visual || category.kind == .mixed {
                vision[category] = score * scale
            }
        }
        var faces = features.faces
        if (vision[.art] ?? 0) >= artSuppressesPeople {
            vision[.people] = nil
            faces = FaceStats()
        }
        input.vision = vision
        input.rules = ruleScores
        input.apps = appMatches
        input.barcodes = features.barcodes
        input.faces = faces
        input.userKNN = user.knn
        input.userOverrides = user.overrides
        input.categoryBias = user.bias
        if let insight {
            var model: [ScreenshotCategory: Double] = [:]
            if let primary = insight.primary { model[primary] = insight.confidence * modelPrimaryWeight }
            for category in insight.secondary where model[category] == nil {
                model[category] = insight.confidence * modelSecondaryWeight
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

    /// The model's app guess, only when it names an app we know ("tokyo", "private_app" and category keys are not apps)
    static func knownApp(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let key = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !key.isEmpty else { return nil }
        return AppSignatures.all.first { signature in
            signature.appID == key || signature.displayName.lowercased().filter { $0.isLetter || $0.isNumber } == key
        }?.displayName
    }

    /// Words that only repeat a category or app ("books", "instagram") or say nothing ("promo", "private app")
    static let vagueModelTags: Set<String> = [
        "app", "private app", "screenshot", "image", "photo", "picture", "text", "post", "message", "promotional",
        "promo", "promotion", "product", "products", "order", "store", "discount", "recommendations", "content",
        "social media", "ad", "advertisement", "sale", "information", "screen"
    ]
    private static let categoryWords: Set<String> = Set(ScreenshotCategory.allCases.flatMap { category -> [String] in
        let words = [category.key.lowercased(), category.displayName.lowercased()]
        return words + words.map { $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
    })

    static func redundantModelTag(_ value: String) -> Bool {
        vagueModelTags.contains(value) || categoryWords.contains(value) || knownApp(value) != nil
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
        if let modelApp = knownApp(insight?.app) { add(modelApp, 0.6, .foundationModel) }
        let scale = visionScale(lineCount: features.lines.filter { $0.zone != .statusBar }.count)
        for (label, confidence) in VisionLabelMap.tags(for: features.labels, scale: scale) {
            add(label, confidence, .visionClassifier)
        }
        for tag in insight?.tags ?? [] where !redundantModelTag(normalizeTag(tag)) { add(tag, 0.8, .foundationModel) }
        // Names found in OCR text (people, places, organisations) stay searchable through the entity index but
        // are not shown as tags: on feeds and garbled text they read as nonsense ("bonus bet tokens").
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
