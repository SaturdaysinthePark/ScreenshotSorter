import CoreGraphics
import Foundation
import os

/// Turns a photo-library asset into an `AnalysisRecord`.
///
/// - Fast pass: small image, one Vision handler (classifier, fast OCR, barcodes, faces) → categories.
/// - Deep pass: larger image, accurate OCR + feature print, entities, on-device language model,
///   text embedding.
/// - Rescore: re-run rules/fusion from stored features (no pixels) after rule or feedback changes.
struct AnalysisPipeline: Sendable {
    static let fastMaxPixel: CGFloat = 1280
    static let deepMaxPixel: CGFloat = 2048
    static let fastTimeout: Double = 8
    static let deepTimeout: Double = 45
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

    /// One line per decision (debug level: free unless streamed, e.g. `log stream --level debug
    /// --predicate 'subsystem == "sabtain.ScreenshotSorter" AND category == "Pipeline"'`).
    private static func logDecision(_ pass: StaticString, id: String, _ result: ClassificationOutput) {
        logger.debug("\(pass) \(id, privacy: .public): \(result.categories.map { "\($0.category.key)=\(String(format: "%.2f", $0.score))" }.joined(separator: " "), privacy: .public) app=\(result.app?.appID ?? "-", privacy: .public)")
    }

    // MARK: Fast

    func runFast(id: String, createdAt: Date) async -> Result {
        let state = AnalysisPipeline.signposter.beginInterval("fastPass")
        defer { AnalysisPipeline.signposter.endInterval("fastPass", state) }

        var record = await store.record(id: id) ?? AnalysisRecord(id: id, createdAt: createdAt)
        record.createdAt = createdAt
        do {
            let image = try await withTimeout(seconds: AnalysisPipeline.fastTimeout) {
                try await PhotoImageLoader.loadCGImage(id: id, maxPixel: AnalysisPipeline.fastMaxPixel, allowNetwork: false)
            }
            let output = try await VisionExtractor.fast(image)
            let user = await learner.signals(for: id, vectors: vectors)
            let insight = record.fmVersion == PipelineVersion.fm ? record.insight : nil
            let result = ScreenshotClassifier.classify(features: output.features, insight: insight, user: user, includeEntities: false)

            let wasCurrentDeep = record.tier == .deep && record.visionVersion == PipelineVersion.vision
            apply(result, features: output.features, insight: insight, to: &record)
            AnalysisPipeline.logDecision("fast", id: id, result)
            record.tier = wasCurrentDeep ? .deep : .fast
            record.visionVersion = PipelineVersion.vision
            record.rulesVersion = PipelineVersion.rules
            record.needsNetwork = false
            record.failCount = 0
        } catch ImageLoaderError.needsNetwork {
            // iCloud-only original: the deep lane (network allowed) will pick it up
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

    // MARK: Deep

    /// - Returns: the record and whether the language-model step should be retried later.
    func runDeep(id: String, createdAt: Date, useLanguageModel: Bool) async -> (Result, retryModel: Bool) {
        let state = AnalysisPipeline.signposter.beginInterval("deepPass")
        defer { AnalysisPipeline.signposter.endInterval("deepPass", state) }

        var record = await store.record(id: id) ?? AnalysisRecord(id: id, createdAt: createdAt)
        record.createdAt = createdAt
        var retryModel = false
        do {
            let image = try await withTimeout(seconds: AnalysisPipeline.deepTimeout) {
                try await PhotoImageLoader.loadCGImage(id: id, maxPixel: AnalysisPipeline.deepMaxPixel, allowNetwork: true)
            }
            let output = try await VisionExtractor.deep(image)
            let features = output.features
            let entities = EntityExtractor.extract(from: features.fullText)

            // Language model: only where it adds something (text to read, or an uncertain result)
            var insight: ModelInsight? = record.fmVersion == PipelineVersion.fm ? record.insight : nil
            // True once the model question is settled for this pipeline version
            var modelDecided = insight != nil
            if insight == nil && useLanguageModel && FMClassifier.isAvailable {
                let preliminary = ScreenshotClassifier.classify(features: features, entities: entities)
                let topScore = preliminary.categories.first?.score ?? 0
                let worthIt = features.fullText.count >= 40 || topScore < 0.75 || preliminary.categories.first?.category == .other
                if !worthIt {
                    modelDecided = true
                } else {
                    let fmState = AnalysisPipeline.signposter.beginInterval("languageModel")
                    let outcome = await FMClassifier.shared.insight(for: features, appHint: preliminary.app?.displayName)
                    AnalysisPipeline.signposter.endInterval("languageModel", fmState)
                    switch outcome {
                    case .insight(let value):
                        insight = value
                        modelDecided = true
                    case .skipped:
                        modelDecided = true
                    case .retryLater:
                        retryModel = true
                    case .unavailable:
                        break
                    }
                }
            }

            try Task.checkCancellation()
            let user = await learner.signals(for: id, vectors: vectors)
            let result = ScreenshotClassifier.classify(features: features, insight: insight, user: user, entities: entities)
            apply(result, features: features, insight: insight, to: &record)
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

            let embedState = AnalysisPipeline.signposter.beginInterval("embed")
            record.embedding = await TextEmbedder.shared.embed(TextEmbedder.document(for: record))
            record.embeddingModel = record.embedding == nil ? nil : TextEmbedder.modelID
            AnalysisPipeline.signposter.endInterval("embed", embedState)

            await vectors.upsert(id: id, text: record.embedding, visual: record.featurePrint)
        } catch is CancellationError {
            return (.skipped, false)
        } catch ImageLoaderError.cancelled {
            return (.skipped, false)
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
        return (.finished(record), retryModel)
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
        record.app = result.app?.displayName ?? insight?.app
        record.appConfidence = result.app?.confidence ?? (insight?.app == nil ? 0 : 0.6)
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
