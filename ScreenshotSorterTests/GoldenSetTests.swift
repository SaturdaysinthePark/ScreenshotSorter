import Foundation
import Testing
@testable import ScreenshotSorter

/// Accuracy regression suite over hand-labelled feature fixtures.
///
/// To grow it: export features from the DEBUG evaluation screen on device, scrub personal
/// text, and append cases to `Fixtures/golden_features.json`. Raise `macroF1Floor` as accuracy improves.
struct GoldenSetTests {
    static let macroF1Floor = 0.95

    @Test func everyCaseClassifiesCorrectly() throws {
        var failures: [String] = []
        for golden in try GoldenCase.loadAll() {
            let output = ScreenshotClassifier.classify(features: golden.features, includeEntities: false)
            let predicted = Set(output.categories.map(\.category))
            let missing = golden.expected.subtracting(predicted)
            let wrong = golden.forbidden.intersection(predicted)
            if !missing.isEmpty || !wrong.isEmpty {
                failures.append("\(golden.name): missing \(missing.map(\.key)) forbidden \(wrong.map(\.key)) got \(output.categories.map { "\($0.category.key)=\(String(format: "%.2f", $0.score))" })")
            }
            if let app = golden.app, output.app?.appID != app {
                failures.append("\(golden.name): expected app \(app) got \(output.app?.appID ?? "nil")")
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func macroF1MeetsFloor() throws {
        var truePositives: [ScreenshotCategory: Int] = [:]
        var falsePositives: [ScreenshotCategory: Int] = [:]
        var falseNegatives: [ScreenshotCategory: Int] = [:]

        for golden in try GoldenCase.loadAll() where !golden.expected.isEmpty {
            let predicted = Set(ScreenshotClassifier.classify(features: golden.features, includeEntities: false).categories.map(\.category))
            for category in predicted {
                if golden.expected.contains(category) {
                    truePositives[category, default: 0] += 1
                } else {
                    falsePositives[category, default: 0] += 1
                }
            }
            for category in golden.expected.subtracting(predicted) {
                falseNegatives[category, default: 0] += 1
            }
        }

        let categories = Set(truePositives.keys).union(falseNegatives.keys)
        var f1Scores: [Double] = []
        for category in categories {
            let tp = Double(truePositives[category, default: 0])
            let precision = tp / max(1, tp + Double(falsePositives[category, default: 0]))
            let recall = tp / max(1, tp + Double(falseNegatives[category, default: 0]))
            f1Scores.append(precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall))
        }
        let macroF1 = f1Scores.reduce(0, +) / Double(max(1, f1Scores.count))
        print("Golden set macro-F1: \(String(format: "%.3f", macroF1)) over \(categories.count) categories")
        #expect(macroF1 >= GoldenSetTests.macroF1Floor)
    }

    /// Guards against the old bug where weighting made a dozen categories impossible to assign.
    @Test func everyCategoryIsReachable() throws {
        var reached = Set<ScreenshotCategory>()
        for golden in try GoldenCase.loadAll() {
            let predicted = ScreenshotClassifier.classify(features: golden.features, includeEntities: false).categories.map(\.category)
            reached.formUnion(predicted)
        }
        let unreachable = ScreenshotCategory.assignable.filter { $0 != .other && !reached.contains($0) }
        #expect(unreachable.isEmpty, "Unreachable: \(unreachable.map(\.key))")
    }

    @Test func categoryKeysRoundTrip() {
        for category in ScreenshotCategory.allCases {
            #expect(ScreenshotCategory(key: category.key) == category)
            #expect(ScreenshotCategory(persisted: category.rawValue) == category)
        }
        #expect(ScreenshotCategory(persisted: "Code & QR") == .codes)
    }
}
