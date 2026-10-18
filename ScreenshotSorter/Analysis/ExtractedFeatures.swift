import CoreGraphics
import Foundation

/// Vertical region of the screen a piece of text was found in.
/// Used to recognise app chrome (tab bars, nav bars, composers).
enum ScreenZone: Int, Codable, Sendable, CaseIterable {
    case statusBar = 0
    case topBar = 1
    case body = 2
    case bottomBar = 3

    /// - Parameter midY: normalized vertical centre, 0 = top of screen, 1 = bottom
    static func zone(forMidY midY: Double) -> ScreenZone {
        if midY < 0.065 { return .statusBar }
        if midY < 0.17 { return .topBar }
        if midY > 0.87 { return .bottomBar }
        return .body
    }
}

struct OCRLine: Codable, Sendable, Hashable {
    let text: String
    let confidence: Float
    /// Normalized, top-left origin
    let box: CGRect
    let zone: ScreenZone
}

struct VisionLabel: Codable, Sendable, Hashable {
    let identifier: String
    let confidence: Double
}

struct BarcodeInfo: Codable, Sendable, Hashable {
    let payload: String?
    let symbology: String
}

struct FaceStats: Codable, Sendable, Hashable {
    var count: Int = 0
    /// Area of the largest face as a fraction of the image
    var largestAreaFraction: Double = 0
    var totalAreaFraction: Double = 0

    /// Faces large enough to be the subject (ignores chat avatars / tiny profile pics)
    var hasProminentFace: Bool { largestAreaFraction >= 0.02 }
}

/// Raw signals extracted from an image. Stored so rules/fusion can be re-run without touching pixels.
struct ExtractedFeatures: Codable, Sendable {
    var lines: [OCRLine] = []
    /// 0 = fast OCR, 1 = accurate OCR
    var ocrLevel: Int = 0
    var labels: [VisionLabel] = []
    var barcodes: [BarcodeInfo] = []
    var faces: FaceStats = FaceStats()
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    /// Fraction of the image covered by text boxes
    var textDensity: Double = 0
    var language: String?

    var fullText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    var aspectRatio: Double {
        guard pixelWidth > 0 else { return 0 }
        return Double(pixelHeight) / Double(pixelWidth)
    }

    func text(in zone: ScreenZone) -> String {
        lines.filter { $0.zone == zone }.map(\.text).joined(separator: " ")
    }
}
