import CoreGraphics
import Foundation
@testable import ScreenshotSorter

/// Locates resources copied into the test bundle.
final class TestBundleToken {}

enum TestSupport {
    static var bundle: Bundle { Bundle(for: TestBundleToken.self) }

    static func features(lines: [(String, ScreenZone)] = [],
                         labels: [(String, Double)] = [],
                         barcodes: [String] = [],
                         faceArea: Double = 0) -> ExtractedFeatures {
        var features = ExtractedFeatures()
        features.lines = lines.map { OCRLine(text: $0.0, confidence: 1, box: .zero, zone: $0.1) }
        features.labels = labels.map { VisionLabel(identifier: $0.0, confidence: $0.1) }
        features.barcodes = barcodes.map { BarcodeInfo(payload: nil, symbology: $0) }
        if faceArea > 0 {
            features.faces = FaceStats(count: 1, largestAreaFraction: faceArea, totalAreaFraction: faceArea)
        }
        features.pixelWidth = 1179
        features.pixelHeight = 2556
        return features
    }
}

/// One labelled example from `Fixtures/golden_features.json`.
struct GoldenCase: Decodable {
    let name: String
    let lines: [[String]]?
    let labels: [GoldenLabel]?
    let barcodes: [String]?
    let faceArea: Double?
    let expect: [String]?
    let forbid: [String]?
    let app: String?

    struct GoldenLabel: Decodable {
        let identifier: String
        let confidence: Double

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            identifier = try container.decode(String.self)
            confidence = try container.decode(Double.self)
        }
    }

    var features: ExtractedFeatures {
        let parsedLines: [(String, ScreenZone)] = (lines ?? []).compactMap { pair in
            guard pair.count == 2 else { return nil }
            let zone: ScreenZone
            switch pair[1] {
            case "statusBar": zone = .statusBar
            case "topBar": zone = .topBar
            case "bottomBar": zone = .bottomBar
            default: zone = .body
            }
            return (pair[0], zone)
        }
        return TestSupport.features(
            lines: parsedLines,
            labels: (labels ?? []).map { ($0.identifier, $0.confidence) },
            barcodes: barcodes ?? [],
            faceArea: faceArea ?? 0
        )
    }

    var expected: Set<ScreenshotCategory> { Set((expect ?? []).compactMap { ScreenshotCategory(key: $0) }) }
    var forbidden: Set<ScreenshotCategory> { Set((forbid ?? []).compactMap { ScreenshotCategory(key: $0) }) }

    static func loadAll() throws -> [GoldenCase] {
        let bundle = TestSupport.bundle
        guard let url = bundle.url(forResource: "golden_features", withExtension: "json")
                ?? bundle.url(forResource: "golden_features", withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([GoldenCase].self, from: Data(contentsOf: url))
    }
}
