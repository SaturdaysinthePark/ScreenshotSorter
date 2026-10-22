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
        case .animals, .people, .nature, .plants:
            return .visual
        // Products are named on the listing as reliably as they are seen in the photo
        // Places absorbed landmarks and storefronts (photos) as well as place cards (text)
        case .places, .food, .drinks, .clothes, .shoes, .homes, .vehicles, .electronics, .books, .art, .sports,
             .watches, .bags, .jewelry, .furniture:
            return .mixed
        case .messages, .email,
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
    /// (agreeing sources) or `singleSourceFallbackMinimum` (one source). The language model alone never
    /// labels: on a real library its lone guesses were mostly wrong.
    var fallbackMinimum: Double = 0.3
    var singleSourceFallbackMinimum: Double = 0.35
    /// A second, object-type topic seen only by the image classifier needs more than the threshold: clothes,
    /// furniture or art at ~0.52 next to a selfie were wrong far more often than right on a real library.
    /// Scene labels (beaches + nature) still pair freely.
    var visionOnlySecondaryThreshold: Double = 0.6
    /// "People" without a detected face (someone in a TikTok video, an ad model, diners behind a restaurant card)
    /// needs this much when it is not the screenshot's only subject: as a second topic or inside an app.
    var visionOnlyPeopleThreshold: Double = 0.75
    /// A second topic backed by one source only (a word in a caption or an ad, an object in the background, the
    /// model's guess) was right 10 times in 45 on a judged real library; corroborated ones were right ~9 in 10
    var singleSourceSecondaryThreshold: Double = 0.8
    /// Plants and landscapes seen only by the image classifier inside an app's post are mostly the background of a
    /// café, a street or a book photo (1 right in 12 on a judged library)
    var visionOnlySceneInAppThreshold: Double = 0.7
    /// Reliability of neighbour-propagated user corrections
    var knnReliability: Double = 0.9
    /// How strongly negative neighbour evidence suppresses a category
    var knnSuppression: Double = 0.8
    /// Inside a chat, topics people mention ("my flight lands at 6") are not what the screenshot is of:
    /// text-rule evidence for topical categories is scaled by this when a messaging app is identified.
    var messagingTopicDamping: Double = 0.6
    var messagingAppConfidence: Double = 0.8
    static let messagingCategories: Set<ScreenshotCategory> = [.messages]

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
        // A book's ISBN or a product's UPC is printed on the thing, not a code anyone saves a screenshot for
        let productCodes = symbologies.filter { $0.contains("ean") || $0.contains("upc") }
        if symbologies.contains(where: { $0.contains("qr") }) {
            evidence[.codes, default: [:]][.barcode] = 0.95
        } else if symbologies.count > ticketCodes.count + productCodes.count {
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
        let inChat = input.apps.contains {
            guard let category = $0.category else { return false }
            return FusionConfig.messagingCategories.contains(category) && $0.confidence >= config.messagingAppConfidence
        }

        for category in allCategories where category != .all && category != .other {
            if input.userOverrides[category] == false { continue }
            let kind = category.kind
            var miss = 1.0
            var sources: LabelSource = []
            for (source, p) in perSource[category] ?? [:] {
                var reliability = config.reliability[source]?[kind] ?? 0
                if inChat && source == .rules && (kind == .textual || kind == .mixed) {
                    reliability *= config.messagingTopicDamping
                }
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
        if let firstTopic = selected.firstIndex(where: { $0.category.kind != .app }) {
            let inApp = selected.contains { $0.category.kind == .app }
            selected = selected.enumerated().filter { index, item in
                guard item.sources == .visionClassifier else { return true }
                if item.category == .people {
                    return (index == firstTopic && !inApp) || item.score >= config.visionOnlyPeopleThreshold
                }
                return index <= firstTopic || item.category.kind != .mixed || item.score >= config.visionOnlySecondaryThreshold
            }.map(\.element)
        }
        if selected.contains(where: { $0.category.kind == .app }) {
            selected.removeAll { item in
                (item.category == .plants || item.category == .nature) && item.sources == .visionClassifier
                    && item.score < config.visionOnlySceneInAppThreshold
            }
        }
        // Someone in the picture isn't what it's about (a creator talking, a model in an ad, an artist on a song
        // page): inside an app People needs a face and no other topic; elsewhere a topic the text names wins.
        if let people = selected.first(where: { $0.category == .people }), !people.sources.contains(.user) {
            let inApp = selected.contains { $0.category.kind == .app }
            let topics = selected.filter { $0.category.kind != .app && $0.category != .people }
            let named = topics.contains { !$0.sources.isDisjoint(with: [.ocrRules, .foundationModel, .appDetector, .barcode]) }
            if inApp ? (!people.sources.contains(.faces) || !topics.isEmpty) : named {
                selected.removeAll { $0.category == .people }
            }
        }
        // Clothes worn by the person a photo is of don't make it a fashion post
        if let people = selected.first(where: { $0.category == .people }),
           let clothes = selected.first(where: { $0.category == .clothes }),
           clothes.sources == .visionClassifier, people.score >= clothes.score {
            selected.removeAll { $0.category == .clothes }
        }
        if let firstTopic = selected.first(where: { $0.category.kind != .app })?.category {
            let evidenceSources: [LabelSource] = [.visionClassifier, .ocrRules, .barcode, .faces, .foundationModel]
            selected.removeAll { item in
                guard item.category != firstTopic, item.category.kind != .app,
                      item.sources.isDisjoint(with: [.user, .userKNN, .appDetector]) else { return false }
                // A shop's product page is both: the shop read from the page, the product seen in the photo
                let pair: Set<ScreenshotCategory> = [item.category, firstTopic]
                if pair.contains(.stores), !pair.isDisjoint(with: ScreenshotClassifier.productCategories) { return false }
                return evidenceSources.filter(item.sources.contains).count == 1 && item.score < config.singleSourceSecondaryThreshold
            }
        }
        if selected.count > config.maxCategories {
            selected = Array(selected.prefix(config.maxCategories))
        }
        if selected.isEmpty {
            let singleSource = scored.first.map { [LabelSource.visionClassifier, .ocrRules, .appDetector, .barcode, .faces]
                .filter($0.sources.contains).count <= 1 } ?? true
            if let best = scored.first, best.sources != .foundationModel,
               best.score >= (singleSource ? config.singleSourceFallbackMinimum : config.fallbackMinimum) {
                selected = [best]
            } else {
                let bestScore = scored.first?.score ?? 0
                selected = [ScoredCategory(category: .other, score: max(0.5, 1 - bestScore), sources: [])]
            }
        }
        return selected
    }
}
