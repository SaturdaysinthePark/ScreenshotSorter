import CoreGraphics
import Foundation
import os

/// Turns a photo-library asset into an `AnalysisRecord`.
///
/// - Fast pass: small image, one Vision handler (classifier, fast OCR, barcodes, faces) → categories.
///   iCloud-only originals are downloaded when `NetworkPolicy` allows it, else sorted from the local
///   preview and marked `needsNetwork`.
/// - Deep pass: larger image, accurate OCR + feature print, entities, text embedding. Decides whether
///   the language model is worth running but doesn't wait for it.
/// - Model pass: the on-device language model from stored features (no pixels). It handles one
///   request at a time system-wide (~2–3 s each on device), so it runs after text and search are done.
/// - Rescore: re-run rules/fusion from stored features (no pixels) after rule or feedback changes.
/// The three passes the scheduler runs (a seam so scheduling can be tested without PhotoKit).
protocol AnalysisPasses: Sendable {
    func runFast(id: String, createdAt: Date, allowDownloads: Bool) async -> AnalysisPipeline.Result
    func runDeep(id: String, createdAt: Date, allowDownloads: Bool) async -> AnalysisPipeline.DeepOutcome
    func runModel(id: String) async -> (AnalysisPipeline.Result, retryLater: Bool)
}

struct AnalysisPipeline: AnalysisPasses {
    static let fastMaxPixel: CGFloat = 1280
    static let deepMaxPixel: CGFloat = 2048
    static let fastTimeout: Double = 8
    /// Fast pass when it may download an iCloud original
    static let fastDownloadTimeout: Double = 25
    static let deepTimeout: Double = 45
    /// Local previews smaller than this (longest side) aren't worth running Vision on
    static let previewMinimumPixel = 480
    static let maxFailures = 3

    let store: AnalysisStore
    let vectors: VectorIndex
    let learner: UserFeedbackLearner

    private static let signposter = OSSignposter(subsystem: "sabtain.ScreenshotSorter", category: .pointsOfInterest)
    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "Pipeline")

    enum Result: Sendable {
        case finished(AnalysisRecord)
        /// Cancelled or nothing to save
        case skipped
    }

    struct DeepOutcome: Sendable {
        var result: Result
        /// The language model is worth running on this one (queue a model pass)
        var needsModel: Bool = false
        /// …and ahead of the others: nothing says what it is about yet (`ScreenshotClassifier.needsTopic`)
        var modelFirst: Bool = false
        /// iCloud-only and downloads aren't allowed right now: park until they are
        var waitingForNetwork: Bool = false
    }

    /// One line per decision (debug level: free unless streamed, e.g. `log stream --level debug
    /// --predicate 'subsystem == "sabtain.ScreenshotSorter" AND category == "Pipeline"'`).
    private static func logDecision(_ pass: StaticString, id: String, _ result: ClassificationOutput) {
        logger.debug("\(pass) \(id, privacy: .public): \(result.categories.map { "\($0.category.key)=\(String(format: "%.2f", $0.score))" }.joined(separator: " "), privacy: .public) app=\(result.app?.appID ?? "-", privacy: .public)")
    }

    // MARK: Fast

    func runFast(id: String, createdAt: Date, allowDownloads: Bool) async -> Result {
        let state = AnalysisPipeline.signposter.beginInterval("fastPass", id: AnalysisPipeline.signposter.makeSignpostID())
        defer { AnalysisPipeline.signposter.endInterval("fastPass", state) }

        var record = await store.record(id: id) ?? AnalysisRecord(id: id, createdAt: createdAt)
        record.createdAt = createdAt
        do {
            let (image, fromPreview) = try await loadFastImage(id: id, allowDownloads: allowDownloads)
            let visionState = AnalysisPipeline.signposter.beginInterval("fastVision", id: AnalysisPipeline.signposter.makeSignpostID())
            let output = try await VisionExtractor.fast(image)
            AnalysisPipeline.signposter.endInterval("fastVision", visionState)
            let user = await learner.signals(for: id, vectors: vectors)
            let insight = record.fmVersion == PipelineVersion.fm ? record.insight : nil
            let result = ScreenshotClassifier.classify(features: output.features, insight: insight, user: user, includeEntities: false)

            let wasCurrentDeep = record.tier == .deep && record.visionVersion == PipelineVersion.vision
            apply(result, features: output.features, insight: insight, to: &record)
            AnalysisPipeline.logDecision("fast", id: id, result)
            record.tier = wasCurrentDeep ? .deep : .fast
            record.visionVersion = PipelineVersion.vision
            record.rulesVersion = PipelineVersion.rules
            // From a preview: the full-resolution pass still needs the original
            record.needsNetwork = fromPreview
            record.failCount = 0
        } catch ImageLoaderError.needsNetwork {
            // iCloud-only, no usable preview and no downloads right now: parked until Wi-Fi
            record.needsNetwork = true
        } catch is CancellationError {
            return .skipped
        } catch ImageLoaderError.cancelled {
            return .skipped
        } catch {
            AnalysisPipeline.logger.error("Fast pass failed for \(id, privacy: .public) (attempt \(record.failCount + 1)): \(String(describing: error), privacy: .public)")
            record.failCount += 1
            if record.failCount >= AnalysisPipeline.maxFailures && (record.tier == .none || record.tier == .failed) {
                record.tier = .failed
                // Stamped so a later extraction change (`PipelineVersion.vision`) retries it.
                record.visionVersion = PipelineVersion.vision
            }
        }
        record.analyzedAt = Date()
        return .finished(record)
    }

    /// The fast-pass image: the original (downloaded if allowed), else the on-device preview.
    private func loadFastImage(id: String, allowDownloads: Bool) async throws -> (CGImage, fromPreview: Bool) {
        let state = AnalysisPipeline.signposter.beginInterval("fastLoad", id: AnalysisPipeline.signposter.makeSignpostID())
        defer { AnalysisPipeline.signposter.endInterval("fastLoad", state) }
        do {
            let image = try await withTimeout(seconds: allowDownloads ? AnalysisPipeline.fastDownloadTimeout : AnalysisPipeline.fastTimeout) {
                try await PhotoImageLoader.loadCGImage(id: id, maxPixel: AnalysisPipeline.fastMaxPixel, allowNetwork: allowDownloads)
            }
            return (image, false)
        } catch ImageLoaderError.needsNetwork {
            // Off Wi-Fi: a rough first sort from the on-device preview beats waiting for hours
            let preview = try? await withTimeout(seconds: 5) {
                await PhotoImageLoader.loadLocalPreview(id: id, maxPixel: AnalysisPipeline.fastMaxPixel,
                                                        minimumPixel: AnalysisPipeline.previewMinimumPixel)
            }
            guard let preview = preview ?? nil else { throw ImageLoaderError.needsNetwork }
            return (preview, true)
        }
    }

    // MARK: Deep

    func runDeep(id: String, createdAt: Date, allowDownloads: Bool) async -> DeepOutcome {
        let state = AnalysisPipeline.signposter.beginInterval("deepPass", id: AnalysisPipeline.signposter.makeSignpostID())
        defer { AnalysisPipeline.signposter.endInterval("deepPass", state) }

        var record = await store.record(id: id) ?? AnalysisRecord(id: id, createdAt: createdAt)
        record.createdAt = createdAt
        var needsModel = false
        var modelFirst = false
        do {
            let image = try await withTimeout(seconds: AnalysisPipeline.deepTimeout) {
                try await PhotoImageLoader.loadCGImage(id: id, maxPixel: AnalysisPipeline.deepMaxPixel, allowNetwork: allowDownloads)
            }
            let output = try await VisionExtractor.deep(image)
            let features = output.features
            let entities = EntityExtractor.extract(from: features.fullText)

            // Language model: only where it adds something (text to read, or an uncertain result).
            // Decided here, run later in the model lane so text and search aren't held up by it.
            let insight: ModelInsight? = record.fmVersion == PipelineVersion.fm ? record.insight : nil
            var modelDecided = insight != nil
            if insight == nil {
                let preliminary = ScreenshotClassifier.classify(features: features, entities: entities)
                let topScore = preliminary.categories.first?.score ?? 0
                let worthIt = FMClassifier.isWorthAsking(features)
                    && (features.fullText.count >= 40 || topScore < 0.75 || preliminary.categories.first?.category == .other)
                if worthIt && FMClassifier.isAvailable {
                    needsModel = true
                } else if !worthIt {
                    modelDecided = true
                }
            }

            try Task.checkCancellation()
            let user = await learner.signals(for: id, vectors: vectors)
            let result = ScreenshotClassifier.classify(features: features, insight: insight, user: user, entities: entities)
            apply(result, features: features, insight: insight, to: &record)
            modelFirst = needsModel && ScreenshotClassifier.needsTopic(result.categories.map(\.category))
            AnalysisPipeline.logDecision("deep", id: id, result)
            record.entities = entities
            record.featurePrint = output.featurePrint
            record.tier = .deep
            record.visionVersion = PipelineVersion.vision
            record.rulesVersion = PipelineVersion.rules
            if modelDecided {
                record.fmVersion = PipelineVersion.fm
            }
            record.needsNetwork = false
            record.failCount = 0

            let embedState = AnalysisPipeline.signposter.beginInterval("embed", id: AnalysisPipeline.signposter.makeSignpostID())
            record.embedding = await TextEmbedder.shared.embed(TextEmbedder.document(for: record))
            record.embeddingModel = record.embedding == nil ? nil : TextEmbedder.modelID
            AnalysisPipeline.signposter.endInterval("embed", embedState)

            await vectors.upsert(id: id, text: record.embedding, visual: record.featurePrint)
        } catch ImageLoaderError.needsNetwork {
            // Not a failure: the original is in iCloud and downloads are paused (cellular / Low Data Mode)
            record.needsNetwork = true
            return DeepOutcome(result: .finished(record), waitingForNetwork: true)
        } catch is CancellationError {
            return DeepOutcome(result: .skipped)
        } catch ImageLoaderError.cancelled {
            return DeepOutcome(result: .skipped)
        } catch {
            AnalysisPipeline.logger.error("Deep pass failed for \(id, privacy: .public) (attempt \(record.failCount + 1)): \(String(describing: error), privacy: .public)")
            record.failCount += 1
            if record.failCount >= AnalysisPipeline.maxFailures && (record.tier == .none || record.tier == .failed) {
                record.tier = .failed
                // Stamped so a later extraction change (`PipelineVersion.vision`) retries it.
                record.visionVersion = PipelineVersion.vision
            }
        }
        record.analyzedAt = Date()
        return DeepOutcome(result: .finished(record), needsModel: needsModel, modelFirst: modelFirst)
    }

    // MARK: Model

    /// The language-model step from stored features. - Returns: the updated record, or whether to
    /// retry later (model busy / rate limited).
    func runModel(id: String) async -> (Result, retryLater: Bool) {
        guard var record = await store.record(id: id), let features = record.features,
              record.fmVersion < PipelineVersion.fm else { return (.skipped, false) }
        let image = FMClassifier.canSeeImages ? await modelImage(id: id) : nil
        let state = AnalysisPipeline.signposter.beginInterval("languageModel", id: AnalysisPipeline.signposter.makeSignpostID())
        let outcome = await FMClassifier.shared.insight(for: features, appHint: record.app, image: image)
        AnalysisPipeline.signposter.endInterval("languageModel", state)
        let insight: ModelInsight?
        switch outcome {
        case .insight(let value):
            insight = value
        case .skipped:
            insight = nil
        case .retryLater:
            return (.skipped, true)
        case .unavailable:
            return (.skipped, false)
        }
        guard !Task.isCancelled else { return (.skipped, false) }
        let user = await learner.signals(for: id, vectors: vectors)
        let result = ScreenshotClassifier.classify(features: features, insight: insight, user: user, entities: record.entities)
        apply(result, features: features, insight: insight, to: &record)
        AnalysisPipeline.logDecision("model", id: id, result)
        record.fmVersion = PipelineVersion.fm
        record.rulesVersion = PipelineVersion.rules
        // Title, summary and tags feed the search embedding
        record.embedding = await TextEmbedder.shared.embed(TextEmbedder.document(for: record))
        record.embeddingModel = record.embedding == nil ? nil : TextEmbedder.modelID
        await vectors.upsert(id: id, text: record.embedding, visual: record.featurePrint)
        record.analyzedAt = Date()
        return (.finished(record), false)
    }

    /// A small copy for the language model: the on-device preview, or a download when Wi-Fi allows.
    /// Missing is fine — the model then works from the stored text alone.
    private func modelImage(id: String) async -> CGImage? {
        let local = await PhotoImageLoader.loadLocalPreview(id: id, maxPixel: FMClassifier.imageMaxPixel,
                                                            minimumPixel: Int(FMClassifier.imageMaxPixel / 2))
        if let local { return local }
        guard NetworkPolicy.shared.allowsICloudDownloads else { return nil }
        return try? await withTimeout(seconds: AnalysisPipeline.fastDownloadTimeout) {
            try await PhotoImageLoader.loadCGImage(id: id, maxPixel: FMClassifier.imageMaxPixel, allowNetwork: true)
        }
    }

    // MARK: Rescore

    /// Re-run rules + fusion from stored features (used after rule updates or user feedback).
    func rescore(_ record: AnalysisRecord) async -> AnalysisRecord {
        guard let features = record.features else { return record }
        var updated = record
        let user = await learner.signals(for: record.id, vectors: vectors)
        let result = ScreenshotClassifier.classify(
            features: features,
            insight: record.insight,
            user: user,
            entities: record.entities,
            includeEntities: false
        )
        apply(result, features: features, insight: record.insight, to: &updated)
        updated.rulesVersion = PipelineVersion.rules
        return updated
    }

    // MARK: Helpers

    private func apply(_ result: ClassificationOutput, features: ExtractedFeatures, insight: ModelInsight?, to record: inout AnalysisRecord) {
        record.features = features
        record.insight = insight
        record.categories = result.categories
        record.tags = result.tags
        let modelApp = ScreenshotClassifier.knownApp(insight?.app)
        record.app = result.app?.displayName ?? modelApp
        record.appConfidence = result.app?.confidence ?? (modelApp == nil ? 0 : 0.6)
        record.ocrText = features.fullText
        record.language = features.language
        record.title = insight?.title ?? AnalysisPipeline.fallbackTitle(features: features, app: record.app)
        record.summary = insight?.summary
    }

    /// A readable title without the language model: app + first meaningful line.
    static func fallbackTitle(features: ExtractedFeatures, app: String?) -> String? {
        let candidate = features.lines
            .filter { $0.zone == .body || $0.zone == .topBar }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                line.split(separator: " ").count >= 3 && line.count <= 90
            }
        switch (app, candidate) {
        case let (app?, line?): return "\(app) · \(String(line.prefix(60)))"
        case let (nil, line?): return String(line.prefix(70))
        case let (app?, nil): return app
        default: return nil
        }
    }
}
