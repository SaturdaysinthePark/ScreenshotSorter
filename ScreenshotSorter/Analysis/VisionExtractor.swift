import CoreGraphics
import Foundation
import NaturalLanguage
import os
@preconcurrency import Vision

/// Runs all Vision requests for one image through a single handler (the image is decoded once).
enum VisionExtractor {
    private static let fastQueue = DispatchQueue(label: "analysis.vision.fast", qos: .userInitiated, attributes: .concurrent)
    private static let deepQueue = DispatchQueue(label: "analysis.vision.deep", qos: .utility, attributes: .concurrent)
    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "Vision")
    /// Request types already reported as failing, so a 25k-screenshot library logs each once.
    private static let reportedFailures = OSAllocatedUnfairLock(initialState: Set<String>())

    struct Output: Sendable {
        var features: ExtractedFeatures
        var featurePrint: [Float]?
    }

    /// Fast pass: classifier + fast OCR + barcodes + faces.
    static func fast(_ image: CGImage) async throws -> Output {
        try await run(on: fastQueue) { try extract(image, accurate: false, featurePrint: false) }
    }

    /// Deep pass: everything, with accurate OCR and an image feature print for similarity.
    static func deep(_ image: CGImage) async throws -> Output {
        try await run(on: deepQueue) { try extract(image, accurate: true, featurePrint: true) }
    }

    private static func run(on queue: DispatchQueue, _ work: @escaping @Sendable () throws -> Output) async throws -> Output {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func reportFailure(of request: VNRequest, _ error: Error) {
        let name = String(describing: type(of: request))
        let isNew = reportedFailures.withLock { $0.insert(name).inserted }
        if isNew {
            logger.error("\(name, privacy: .public) unavailable, continuing without it: \(String(describing: error), privacy: .public)")
        }
    }

    private static func extract(_ image: CGImage, accurate: Bool, featurePrint wantsFeaturePrint: Bool) throws -> Output {
        let classify = VNClassifyImageRequest()

        let text = VNRecognizeTextRequest()
        text.recognitionLevel = accurate ? .accurate : .fast
        text.usesLanguageCorrection = accurate
        text.automaticallyDetectsLanguage = accurate
        text.minimumTextHeight = accurate ? 0 : 0.008

        let barcodes = VNDetectBarcodesRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let print = VNGenerateImageFeaturePrintRequest()

        var requests: [VNRequest] = [classify, text, barcodes, faces]
        if wantsFeaturePrint { requests.append(print) }

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            // One failing request fails the whole batch (the iOS 26 simulator has no inference
            // context for the classifier, faces or feature prints). Redo them one by one so the
            // rest still count; only OCR is required, the rules can work from text alone.
            for request in requests where request !== text {
                do {
                    try handler.perform([request])
                } catch {
                    reportFailure(of: request, error)
                }
            }
            try handler.perform([text])
        }

        var features = ExtractedFeatures()
        features.pixelWidth = image.width
        features.pixelHeight = image.height
        features.ocrLevel = accurate ? 1 : 0

        // Classifier labels
        let observations = (classify.results ?? [])
            .filter { $0.confidence >= Float(VisionLabelMap.minimumConfidence) }
            .prefix(25)
        features.labels = observations.map { VisionLabel(identifier: $0.identifier, confidence: Double($0.confidence)) }

        // OCR lines with zones (Vision boxes are normalized, lower-left origin)
        var textArea = 0.0
        var lines: [OCRLine] = []
        for observation in text.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox
            let topLeftBox = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            textArea += Double(box.width * box.height)
            lines.append(OCRLine(
                text: candidate.string,
                confidence: candidate.confidence,
                box: topLeftBox,
                zone: ScreenZone.zone(forMidY: Double(topLeftBox.midY))
            ))
        }
        lines.sort { lhs, rhs in
            abs(lhs.box.minY - rhs.box.minY) < 0.008 ? lhs.box.minX < rhs.box.minX : lhs.box.minY < rhs.box.minY
        }
        features.lines = lines
        features.textDensity = min(1, textArea)

        // Barcodes
        features.barcodes = (barcodes.results ?? []).map {
            BarcodeInfo(payload: $0.payloadStringValue, symbology: $0.symbology.rawValue)
        }

        // Faces
        var faceStats = FaceStats()
        for face in faces.results ?? [] {
            let area = Double(face.boundingBox.width * face.boundingBox.height)
            faceStats.count += 1
            faceStats.totalAreaFraction += area
            faceStats.largestAreaFraction = max(faceStats.largestAreaFraction, area)
        }
        features.faces = faceStats

        // Language
        if !lines.isEmpty {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(features.fullText)
            features.language = recognizer.dominantLanguage?.rawValue
        }

        var featurePrint: [Float]?
        if wantsFeaturePrint, let observation = print.results?.first {
            featurePrint = normalizedVector(from: observation)
        }
        return Output(features: features, featurePrint: featurePrint)
    }

    private static func normalizedVector(from observation: VNFeaturePrintObservation) -> [Float]? {
        let count = observation.elementCount
        guard count > 0 else { return nil }
        var vector: [Float]
        switch observation.elementType {
        case .float:
            vector = observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
        case .double:
            vector = observation.data.withUnsafeBytes { buffer in
                buffer.bindMemory(to: Double.self).prefix(count).map { Float($0) }
            }
        default:
            return nil
        }
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        for index in vector.indices { vector[index] /= norm }
        return vector
    }
}
