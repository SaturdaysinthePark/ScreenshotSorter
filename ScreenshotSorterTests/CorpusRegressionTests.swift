import Foundation
import Testing
@testable import ScreenshotSorter

/// Accuracy floor over real extracted features from the eval corpus (`Tools/eval`): mock app screens
/// rendered at iPhone resolution plus full-screen photos, run through macOS Vision (classifier + accurate OCR).
///
/// Regenerate after re-running the corpus:
///   Tools/eval/run.sh --corpus build/corpus --pass deep --export build/corpus/export.json
/// then keep the mock/ and photo cases (see Tools/eval/README.md). Raise the floor as accuracy improves.
struct CorpusRegressionTests {
    static let macroF1Floor = 0.86

    @Test func corpusMacroF1MeetsFloor() throws {
        let cases = try GoldenCase.loadAll("corpus_features")
        #expect(cases.count >= 200)
        var tp: [ScreenshotCategory: Int] = [:], fp: [ScreenshotCategory: Int] = [:], fn: [ScreenshotCategory: Int] = [:]
        for golden in cases {
            let predicted = Set(ScreenshotClassifier.classify(features: golden.features, includeEntities: false).categories.map(\.category))
                .subtracting(golden.allowed.subtracting(golden.expected))
                .subtracting([.other])
            for category in predicted {
                if golden.expected.contains(category) { tp[category, default: 0] += 1 } else { fp[category, default: 0] += 1 }
            }
            for category in golden.expected.subtracting(predicted) { fn[category, default: 0] += 1 }
        }
        let supported = Set(tp.keys).union(fn.keys)
        var report: [(String, Double)] = []
        for category in supported {
            let t = Double(tp[category, default: 0])
            let precision = t / max(1, t + Double(fp[category, default: 0]))
            let recall = t / max(1, t + Double(fn[category, default: 0]))
            report.append((category.key, precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)))
        }
        let macroF1 = report.map(\.1).reduce(0, +) / Double(max(1, report.count))
        print("Corpus macro-F1: \(String(format: "%.3f", macroF1)) over \(report.count) categories, \(cases.count) cases")
        for (key, f1) in report.sorted(by: { $0.1 < $1.1 }).prefix(10) {
            print("  weakest \(key): \(String(format: "%.2f", f1))")
        }
        #expect(macroF1 >= CorpusRegressionTests.macroF1Floor)
    }
}
