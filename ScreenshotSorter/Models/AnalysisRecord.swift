import Foundation

// MARK: - Pipeline versions

/// Bump a version to selectively re-run part of the pipeline on existing records.
/// - `vision`: re-run image analysis (reloads images)
/// - `rules`: re-score from stored features only (no image work, seconds for the whole library)
/// - `fm`: re-run the Foundation Models lane
/// - `embedding`: re-embed stored text
enum PipelineVersion {
    static let vision = 2
    static let rules = 5
    static let fm = 2
    static let embedding = 1
}

// MARK: - Tier

enum AnalysisTier: Int, Codable, Sendable, Comparable {
    case failed = -1
    case none = 0
    /// Fast pass: classifier + fast OCR + barcodes + faces → categories
    case fast = 1
    /// Deep pass: accurate OCR, entities, Foundation Models, embedding, feature print
    case deep = 2

    static func < (lhs: AnalysisTier, rhs: AnalysisTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Labels

enum LabelKind: Int, Codable, Sendable {
    case category = 0
    case tag = 1
    case visionLabel = 2
}

/// Which signals contributed to a label (bitmask, persisted as Int)
struct LabelSource: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int

    static let visionClassifier = LabelSource(rawValue: 1 << 0)
    static let ocrRules = LabelSource(rawValue: 1 << 1)
    static let appDetector = LabelSource(rawValue: 1 << 2)
    static let barcode = LabelSource(rawValue: 1 << 3)
    static let faces = LabelSource(rawValue: 1 << 4)
    static let layout = LabelSource(rawValue: 1 << 5)
    static let foundationModel = LabelSource(rawValue: 1 << 6)
    static let dataDetector = LabelSource(rawValue: 1 << 7)
    static let user = LabelSource(rawValue: 1 << 8)
    static let userKNN = LabelSource(rawValue: 1 << 9)
    static let nameTagger = LabelSource(rawValue: 1 << 10)
}

struct ScoredCategory: Codable, Sendable, Hashable {
    let category: ScreenshotCategory
    let score: Double
    let sources: LabelSource
}

struct ScreenshotTag: Codable, Sendable, Hashable {
    let value: String
    let score: Double
    let sources: LabelSource

    /// Tags that only came from neighbour propagation are shown as suggestions
    var isSuggested: Bool { sources == .userKNN }
}

// MARK: - Entities

enum EntityType: String, Codable, Sendable, CaseIterable {
    case date
    case url
    case phone
    case address
    case email
    case flight
    case price
    case tracking
    case oneTimeCode
    case person
    case place
    case organization
}

struct ExtractedEntity: Codable, Sendable, Hashable {
    let type: EntityType
    let value: String
    /// Machine-friendly value (ISO date, absolute URL, E.164-ish phone…)
    let normalized: String?
}

// MARK: - Record

/// Everything we know about one screenshot. Persisted by `AnalysisStore`.
struct AnalysisRecord: Sendable {
    let id: String
    var createdAt: Date
    var tier: AnalysisTier
    var visionVersion: Int
    var rulesVersion: Int
    var fmVersion: Int
    var app: String?
    var appConfidence: Double
    var title: String?
    var summary: String?
    var ocrText: String
    var language: String?
    var features: ExtractedFeatures?
    /// Output of the on-device language model (kept so rules can be re-run without it)
    var insight: ModelInsight?
    var categories: [ScoredCategory]
    var tags: [ScreenshotTag]
    var entities: [ExtractedEntity]
    var embedding: [Float]?
    var embeddingModel: String?
    var featurePrint: [Float]?
    var isReviewed: Bool
    var needsNetwork: Bool
    var failCount: Int
    var analyzedAt: Date

    init(id: String, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
        self.tier = .none
        self.visionVersion = 0
        self.rulesVersion = 0
        self.fmVersion = 0
        self.app = nil
        self.appConfidence = 0
        self.title = nil
        self.summary = nil
        self.ocrText = ""
        self.language = nil
        self.features = nil
        self.insight = nil
        self.categories = []
        self.tags = []
        self.entities = []
        self.embedding = nil
        self.embeddingModel = nil
        self.featurePrint = nil
        self.isReviewed = false
        self.needsNetwork = false
        self.failCount = 0
        self.analyzedAt = Date()
    }

    var summaryValue: RecordSummary {
        RecordSummary(
            id: id,
            creationDate: createdAt,
            tier: tier,
            categories: categories,
            tags: tags.map(\.value),
            app: app,
            title: title,
            isReviewed: isReviewed
        )
    }
}

/// Lightweight projection used by the UI (loaded at launch for the whole library)
struct RecordSummary: Sendable, Hashable {
    let id: String
    let creationDate: Date
    let tier: AnalysisTier
    let categories: [ScoredCategory]
    let tags: [String]
    let app: String?
    let title: String?
    let isReviewed: Bool
}
