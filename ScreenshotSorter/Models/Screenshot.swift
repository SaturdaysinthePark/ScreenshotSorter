import Foundation
import Photos
import UIKit

enum ConfidenceLevel: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    init(score: Double) {
        if score >= 0.7 {
            self = .high
        } else if score >= 0.4 {
            self = .medium
        } else {
            self = .low
        }
    }
}

struct CategoryWithConfidence: Hashable {
    let category: ScreenshotCategory
    let confidence: ConfidenceLevel
    let score: Double
}

enum ScreenshotStatus {
    case unprocessed
    case processing
    case processed
    case reviewed
}

struct Screenshot: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let categories: [ScreenshotCategory] // For backward compatibility
    let categoriesWithConfidence: [CategoryWithConfidence]
    let creationDate: Date
    var thumbnail: UIImage?
    var isReviewed: Bool = false
    var markedForDeletion: Bool = false
    var lastReviewedDate: Date?
    var processingStatus: ScreenshotStatus = .unprocessed

    // Rich analysis (populated by the analysis pipeline)
    var app: String?
    var tags: [String] = []
    var title: String?
    var summary: String?
    var tier: AnalysisTier = .none

    init(asset: PHAsset, categories: [ScreenshotCategory]) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.categories = categories
        self.categoriesWithConfidence = categories.map {
            CategoryWithConfidence(category: $0, confidence: .medium, score: 0.5)
        }
        self.creationDate = asset.creationDate ?? Date()
    }

    init(asset: PHAsset, categoriesWithConfidence: [CategoryWithConfidence]) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.categoriesWithConfidence = categoriesWithConfidence
        self.categories = categoriesWithConfidence.map { $0.category }
        self.creationDate = asset.creationDate ?? Date()
    }

    /// Build from a PHAsset plus (optional) persisted analysis summary
    init(asset: PHAsset, summary: RecordSummary?) {
        self.init(id: asset.localIdentifier, asset: asset,
                  creationDate: asset.creationDate ?? summary?.creationDate ?? Date(), summary: summary)
    }

    /// Designated initializer: identity and date are passed in, so updates don't re-read the asset
    /// (and tests can build large libraries with a placeholder asset).
    init(id: String, asset: PHAsset, creationDate: Date, summary: RecordSummary?) {
        self.id = id
        self.asset = asset
        self.creationDate = creationDate
        if let summary, summary.tier != .none {
            let scored = summary.categories.map {
                CategoryWithConfidence(category: $0.category, confidence: ConfidenceLevel(score: $0.score), score: $0.score)
            }
            self.categoriesWithConfidence = scored
            self.categories = scored.map { $0.category }
            self.processingStatus = .processed
        } else {
            self.categoriesWithConfidence = []
            self.categories = []
            self.processingStatus = .unprocessed
        }
        self.app = summary?.app
        self.tags = summary?.tags ?? []
        self.title = summary?.title
        self.tier = summary?.tier ?? .none
        self.isReviewed = summary?.isReviewed ?? false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Screenshot, rhs: Screenshot) -> Bool {
        lhs.id == rhs.id
    }
}
