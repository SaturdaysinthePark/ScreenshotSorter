import Foundation

/// What kind of evidence a category usually needs.
enum CategoryKind: Sendable, CaseIterable {
    /// Recognised from pixels (animals, beaches…)
    case visual
    /// Recognised equally from pixels or words (food, clothes…)
    case mixed
    /// Recognised from words (receipts, news…)
    case textual
    /// Identified by the app it was taken in
    case app
    /// Identified by layout/structure (QR codes)
    case structural
}

extension ScreenshotCategory {
    var kind: CategoryKind {
        switch self {
        case .animals, .people, .nature, .landscapes, .beaches, .mountains, .flowers, .plants, .sunset,
             .sitesOfInterest, .storefronts, .watches, .bags, .jewelry, .furniture:
            return .visual
        case .food, .drinks, .clothes, .shoes, .homes, .vehicles, .electronics, .books, .art, .cooking, .sports, .exercise:
            return .mixed
        case .imessage, .whatsapp, .signal, .telegram, .discord, .slack, .email, .gmail,
             .instagram, .tiktok, .twitter, .facebook, .linkedin, .reddit, .youtube:
            return .app
        case .codes:
            return .structural
        default:
            return .textual
        }
    }
}

enum FusionSource: Sendable, CaseIterable {
    case vision
    case rules
    case app
    case barcode
    case faces
    case model

    var labelSource: LabelSource {
        switch self {
        case .vision: return .visionClassifier
        case .rules: return .ocrRules
        case .app: return .appDetector
        case .barcode: return .barcode
        case .faces: return .faces
        case .model: return .foundationModel
        }
    }
}

/// Tunable fusion parameters (tuned against the golden set).
struct FusionConfig: Sendable {
    /// How much to trust each source for each kind of category (0…1)
    var reliability: [FusionSource: [CategoryKind: Double]] = [
        .vision: [.visual: 0.95, .mixed: 0.85, .textual: 0.45, .app: 0.0, .structural: 0.4],
        .rules: [.visual: 0.55, .mixed: 0.85, .textual: 0.95, .app: 0.75, .structural: 0.8],
        .app: [.visual: 0.6, .mixed: 0.8, .textual: 0.9, .app: 0.97, .structural: 0.6],
        .barcode: [.visual: 0, .mixed: 0, .textual: 0.6, .app: 0, .structural: 0.97],
        .faces: [.visual: 0.85, .mixed: 0, .textual: 0, .app: 0, .structural: 0],
        .model: [.visual: 0.7, .mixed: 0.85, .textual: 0.9, .app: 0.85, .structural: 0.6]
    ]
    var threshold: Double = 0.5
    var perCategoryThreshold: [ScreenshotCategory: Double] = [:]
    var maxCategories: Int = 6
    /// When nothing passes the threshold, keep the best category if it is at least this likely
    var fallbackMinimum: Double = 0.3
    /// Reliability of neighbour-propagated user corrections
    var knnReliability: Double = 0.9
    /// How strongly negative neighbour evidence suppresses a category
    var knnSuppression: Double = 0.8

    static let `default` = FusionConfig()

    func threshold(for category: ScreenshotCategory) -> Double {
        perCategoryThreshold[category] ?? threshold
    }
}

/// All evidence about one screenshot.
struct FusionInput: Sendable {
    var vision: [ScreenshotCategory: Double] = [:]
    var rules: [ScreenshotCategory: Double] = [:]
    var apps: [AppMatch] = []
    var barcodes: [BarcodeInfo] = []
    var faces: FaceStats = FaceStats()
    var model: [ScreenshotCategory: Double] = [:]
    /// Neighbour-propagated user evidence in −1…1 (negative = users removed it from similar items)
    var userKNN: [ScreenshotCategory: Double] = [:]
    /// Direct user corrections on this item: true = added, false = removed
    var userOverrides: [ScreenshotCategory: Bool] = [:]
    /// Learned per-category calibration offsets
    var categoryBias: [ScreenshotCategory: Double] = [:]
}

enum SignalFusion {

    /// Per-source probabilities for every category with any evidence.
    static func evidence(_ input: FusionInput) -> [ScreenshotCategory: [FusionSource: Double]] {
        var evidence: [ScreenshotCategory: [FusionSource: Double]] = [:]
        for (category, p) in input.vision { evidence[category, default: [:]][.vision] = p }
        for (category, p) in input.rules { evidence[category, default: [:]][.rules] = p }
        for (category, p) in input.model { evidence[category, default: [:]][.model] = p }
        for match in input.apps {
            guard let category = match.category else { continue }
            let current = evidence[category]?[.app] ?? 0
            evidence[category, default: [:]][.app] = max(current, match.confidence)
        }
        let symbologies = input.barcodes.map { $0.symbology.lowercased() }
        // Boarding passes / event tickets use Aztec & PDF417; everything else counts as a scannable code
        let ticketCodes = symbologies.filter { $0.contains("aztec") || $0.contains("pdf417") }
        if symbologies.contains(where: { $0.contains("qr") }) {
            evidence[.codes, default: [:]][.barcode] = 0.95
        } else if symbologies.count > ticketCodes.count {
            evidence[.codes, default: [:]][.barcode] = 0.75
        }
        if !ticketCodes.isEmpty {
            evidence[.tickets, default: [:]][.barcode] = 0.8
        }
        if input.faces.hasProminentFace {
            evidence[.people, default: [:]][.faces] = min(1, 0.55 + input.faces.largestAreaFraction * 3)
        }
        return evidence
    }

    static func fuse(_ input: FusionInput, config: FusionConfig = .default) -> [ScoredCategory] {
        var scored: [ScoredCategory] = []
        let perSource = evidence(input)
        var allCategories = Set(perSource.keys)
        allCategories.formUnion(input.userKNN.keys)

        for category in allCategories where category != .all && category != .other {
            if input.userOverrides[category] == false { continue }
            let kind = category.kind
            var miss = 1.0
            var sources: LabelSource = []
            for (source, p) in perSource[category] ?? [:] {
                let reliability = config.reliability[source]?[kind] ?? 0
                let contribution = reliability * min(max(p, 0), 1)
                miss *= (1 - contribution)
                if contribution > 0.05 { sources.insert(source.labelSource) }
            }
            if let knn = input.userKNN[category], knn > 0 {
                miss *= (1 - config.knnReliability * min(knn, 1))
                sources.insert(.userKNN)
            }
            var probability = 1 - miss
            if let knn = input.userKNN[category], knn < 0 {
                probability *= (1 + config.knnSuppression * max(knn, -1))
            }
            probability += input.categoryBias[category] ?? 0
            probability = min(max(probability, 0), 1)
            scored.append(ScoredCategory(category: category, score: probability, sources: sources))
        }

        // Direct user additions always win
        for (category, added) in input.userOverrides where added {
            scored.removeAll { $0.category == category }
            scored.append(ScoredCategory(category: category, score: 1.0, sources: .user))
        }

        scored.sort { $0.score > $1.score }
        var selected = scored.filter { $0.score >= config.threshold(for: $0.category) || $0.sources.contains(.user) }
        if selected.count > config.maxCategories {
            selected = Array(selected.prefix(config.maxCategories))
        }
        if selected.isEmpty {
            if let best = scored.first, best.score >= config.fallbackMinimum {
                selected = [best]
            } else {
                let bestScore = scored.first?.score ?? 0
                selected = [ScoredCategory(category: .other, score: max(0.5, 1 - bestScore), sources: [])]
            }
        }
        return selected
    }
}
