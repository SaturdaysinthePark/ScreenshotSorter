import CoreGraphics
import Foundation
import ImageIO

// Classification eval harness: runs the app's real VisionExtractor + ScreenshotClassifier on macOS
// (where Vision's image classifier works, unlike the iOS simulator) over a labelled corpus.
//
//   Tools/eval/run.sh --corpus build/corpus [--pass fast|deep|both] [--export Fixtures.json]
//
// Corpus layout: <corpus>/manifest.json = [{"file": "img/x.png", "expect": ["receipts"], "forbid": [], "app": null}]
// Writes <corpus>/report.md, <corpus>/results.jsonl (one explained prediction per image).

struct ManifestEntry: Codable {
    var file: String
    var expect: [String]
    var forbid: [String]?
    /// Acceptable extra labels: neither rewarded nor counted as false positives
    var allow: [String]?
    var app: String?
    var source: String?
}

struct Args {
    var corpus = URL(fileURLWithPath: "build/corpus")
    var passes: [Pass] = [.fast, .deep]
    var export: URL?
    var filter: String?
    /// Re-score a copy of a library database instead of running images (see rescore.swift)
    var database: String?
    var out: URL?
    var concurrency = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)

    init() {
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--corpus": corpus = URL(fileURLWithPath: it.next()!)
            case "--pass":
                switch it.next() {
                case "fast": passes = [.fast]
                case "deep": passes = [.deep]
                default: passes = [.fast, .deep]
                }
            case "--export": export = URL(fileURLWithPath: it.next()!)
            case "--filter": filter = it.next()
            case "--db": database = it.next()
            case "--out": out = URL(fileURLWithPath: it.next()!)
            case "--jobs": concurrency = Int(it.next()!) ?? concurrency
            default: fatalError("unknown argument \(arg)")
            }
        }
    }
}

enum Pass: String, Codable {
    case fast, deep
    /// Mirrors AnalysisPipeline.fastMaxPixel / deepMaxPixel.
    var maxPixel: Int { self == .fast ? 1280 : 2048 }
}

struct Prediction: Codable {
    var file: String
    var pass: Pass
    var expect: [String]
    var forbid: [String]
    var allow: [String]
    var predicted: [String: Double]
    var sources: [String: [String]]
    var ruleHits: [String: [String]]
    var visionLabels: [String: Double]
    var app: String?
    var expectedApp: String?
    var extractMs: Double
    var classifyMs: Double
    var ocrLines: Int
    var text: String
}

func loadImage(_ url: URL, maxPixel: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

func sourceNames(_ sources: LabelSource) -> [String] {
    var names: [String] = []
    if sources.contains(.visionClassifier) { names.append("vision") }
    if sources.contains(.ocrRules) { names.append("rules") }
    if sources.contains(.appDetector) { names.append("app") }
    if sources.contains(.barcode) { names.append("barcode") }
    if sources.contains(.faces) { names.append("faces") }
    if sources.contains(.foundationModel) { names.append("model") }
    return names
}

func evaluate(_ entry: ManifestEntry, root: URL, pass: Pass) async -> (Prediction, ExtractedFeatures)? {
    let url = root.appendingPathComponent(entry.file)
    let clock = ContinuousClock()
    guard let image = loadImage(url, maxPixel: pass.maxPixel) else {
        FileHandle.standardError.write("cannot load \(entry.file)\n".data(using: .utf8)!)
        return nil
    }
    let start = clock.now
    let output: VisionExtractor.Output
    do {
        output = pass == .fast ? try await VisionExtractor.fast(image) : try await VisionExtractor.deep(image)
    } catch {
        FileHandle.standardError.write("extract failed \(entry.file): \(error)\n".data(using: .utf8)!)
        return nil
    }
    let extracted = clock.now
    let result = ScreenshotClassifier.classify(features: output.features, includeEntities: pass == .deep)
    let classified = clock.now

    let text = TextNormalizer.normalize(lines: output.features.lines)
    var ruleHits: [String: [String]] = [:]
    for (category, hit) in RuleEngine.shared.evaluateDetailed(text, features: output.features) {
        ruleHits["\(category.key)=\(String(format: "%.2f", hit.score))"] = hit.matched
    }
    var vision: [String: Double] = [:]
    for label in output.features.labels.prefix(8) { vision[label.identifier] = (label.confidence * 100).rounded() / 100 }
    var predicted: [String: Double] = [:]
    var sources: [String: [String]] = [:]
    for scored in result.categories {
        predicted[scored.category.key] = (scored.score * 100).rounded() / 100
        sources[scored.category.key] = sourceNames(scored.sources)
    }
    let ms = { (d: Duration) -> Double in Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000 }
    let prediction = Prediction(
        file: entry.file, pass: pass, expect: entry.expect, forbid: entry.forbid ?? [], allow: entry.allow ?? [],
        predicted: predicted, sources: sources, ruleHits: ruleHits, visionLabels: vision,
        app: result.app?.appID, expectedApp: entry.app,
        extractMs: ms(extracted - start), classifyMs: ms(classified - extracted),
        ocrLines: output.features.lines.count,
        text: String(output.features.fullText.prefix(400))
    )
    return (prediction, output.features)
}

struct Metrics {
    var tp: [String: Int] = [:], fp: [String: Int] = [:], fn: [String: Int] = [:]
    var exact = 0, total = 0, forbiddenHits = 0
    var confusions: [String: Int] = [:]

    mutating func add(_ p: Prediction) {
        let expected = Set(p.expect), allowed = Set(p.allow)
        let predicted = Set(p.predicted.keys).subtracting(allowed.subtracting(expected))
        total += 1
        if expected == predicted.subtracting(["other"]) || (expected.isEmpty && predicted.subtracting(["other"]).isEmpty) { exact += 1 }
        for c in predicted where c != "other" {
            if expected.contains(c) { tp[c, default: 0] += 1 } else { fp[c, default: 0] += 1 }
        }
        for c in expected.subtracting(predicted) {
            fn[c, default: 0] += 1
            for wrong in predicted.subtracting(expected) { confusions["\(c) → \(wrong)", default: 0] += 1 }
            if predicted.subtracting(expected).isEmpty { confusions["\(c) → (nothing)", default: 0] += 1 }
        }
        forbiddenHits += Set(p.forbid).intersection(predicted).count
    }

    func f1(_ c: String) -> (p: Double, r: Double, f: Double, support: Int) {
        let t = Double(tp[c, default: 0]), fpos = Double(fp[c, default: 0]), fneg = Double(fn[c, default: 0])
        let p = t / max(1, t + fpos), r = t / max(1, t + fneg)
        return (p, r, p + r == 0 ? 0 : 2 * p * r / (p + r), Int(t + fneg))
    }

    var categories: [String] { Array(Set(tp.keys).union(fn.keys).union(fp.keys)).sorted() }
    var supported: [String] { categories.filter { f1($0).support > 0 } }
    var macroF1: Double {
        let s = supported
        return s.map { f1($0).f }.reduce(0, +) / Double(max(1, s.count))
    }
    var microF1: Double {
        let t = Double(tp.values.reduce(0, +)), fpos = Double(fp.values.reduce(0, +)), fneg = Double(fn.values.reduce(0, +))
        let p = t / max(1, t + fpos), r = t / max(1, t + fneg)
        return p + r == 0 ? 0 : 2 * p * r / (p + r)
    }
}

func percentile(_ values: [Double], _ q: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * q))]
}

func exportGolden(_ items: [(ManifestEntry, ExtractedFeatures)], to url: URL) throws {
    var cases: [[String: Any]] = []
    for (entry, features) in items {
        var c: [String: Any] = ["name": entry.file]
        c["lines"] = features.lines.map { [$0.text, "\($0.zone)"] }
        // Geometry matters for layout cues (caption spread, lock-screen date); rounded to keep the fixture small
        c["boxes"] = features.lines.map { line in [line.box.minX, line.box.minY, line.box.width, line.box.height].map { ($0 * 1000).rounded() / 1000 } }
        c["textDensity"] = (features.textDensity * 1000).rounded() / 1000
        if !features.labels.isEmpty { c["labels"] = features.labels.prefix(12).map { [$0.identifier, ($0.confidence * 1000).rounded() / 1000] } }
        if !features.barcodes.isEmpty { c["barcodes"] = features.barcodes.map(\.symbology) }
        if features.faces.largestAreaFraction > 0 { c["faceArea"] = (features.faces.largestAreaFraction * 1000).rounded() / 1000 }
        c["expect"] = entry.expect
        if let forbid = entry.forbid, !forbid.isEmpty { c["forbid"] = forbid }
        if let app = entry.app { c["app"] = app }
        cases.append(c)
    }
    let data = try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

@main
struct EvalMain {
    static func main() async throws {
        let args = Args()
        if let database = args.database {
            try runRescore(database: database, out: args.out ?? URL(fileURLWithPath: "build/eval/rescore.jsonl"))
            return
        }
        let manifestURL = args.corpus.appendingPathComponent("manifest.json")
        var entries = try JSONDecoder().decode([ManifestEntry].self, from: Data(contentsOf: manifestURL))
        if let filter = args.filter { entries = entries.filter { $0.file.contains(filter) || $0.expect.contains(filter) } }
        let unknown = Set(entries.flatMap { $0.expect + ($0.forbid ?? []) + ($0.allow ?? []) }).filter { ScreenshotCategory(key: $0) == nil }
        precondition(unknown.isEmpty, "Unknown category keys in manifest: \(unknown.sorted())")

        var report = "# Classification eval\n\n\(entries.count) images · \(Date().formatted())\n\n"
        let resultsURL = args.corpus.appendingPathComponent("results.jsonl")
        FileManager.default.createFile(atPath: resultsURL.path, contents: nil)
        let results = try FileHandle(forWritingTo: resultsURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for pass in args.passes {
            let wall = ContinuousClock.now
            var predictions: [Prediction] = []
            var featuresForExport: [(ManifestEntry, ExtractedFeatures)] = []
            try await withThrowingTaskGroup(of: (ManifestEntry, Prediction, ExtractedFeatures)?.self) { group in
                var iterator = entries.makeIterator()
                for _ in 0..<args.concurrency {
                    guard let entry = iterator.next() else { break }
                    group.addTask { await evaluate(entry, root: args.corpus, pass: pass).map { (entry, $0.0, $0.1) } }
                }
                while let next = try await group.next() {
                    if let (entry, prediction, features) = next {
                        predictions.append(prediction)
                        featuresForExport.append((entry, features))
                        try results.write(contentsOf: encoder.encode(prediction) + Data("\n".utf8))
                    }
                    if let entry = iterator.next() {
                        group.addTask { await evaluate(entry, root: args.corpus, pass: pass).map { (entry, $0.0, $0.1) } }
                    }
                }
            }
            let seconds = Double((ContinuousClock.now - wall).components.seconds) + Double((ContinuousClock.now - wall).components.attoseconds) / 1e18

            var metrics = Metrics()
            var appRight = 0, appTotal = 0
            for p in predictions {
                metrics.add(p)
                if let expectedApp = p.expectedApp { appTotal += 1; if p.app == expectedApp { appRight += 1 } }
            }
            report += "## \(pass.rawValue) pass (\(pass.maxPixel)px)\n\n"
            report += String(format: "- macro-F1 **%.3f** over %d categories · micro-F1 %.3f\n", metrics.macroF1, metrics.supported.count, metrics.microF1)
            report += String(format: "- exact label-set match %.1f%% · forbidden hits %d\n", 100 * Double(metrics.exact) / Double(max(1, metrics.total)), metrics.forbiddenHits)
            if appTotal > 0 { report += String(format: "- app detection %d/%d\n", appRight, appTotal) }
            report += String(format: "- extract p50 %.0f ms · p95 %.0f ms · classify p50 %.2f ms · %.1f img/s with %d jobs\n\n",
                             percentile(predictions.map(\.extractMs), 0.5), percentile(predictions.map(\.extractMs), 0.95),
                             percentile(predictions.map(\.classifyMs), 0.5), Double(predictions.count) / max(seconds, 0.001), args.concurrency)
            report += "| category | P | R | F1 | support | FP |\n|---|---|---|---|---|---|\n"
            for c in metrics.categories.sorted(by: { metrics.f1($0).f < metrics.f1($1).f }) {
                let m = metrics.f1(c)
                report += String(format: "| %@ | %.2f | %.2f | %.2f | %d | %d |\n", c, m.p, m.r, m.f, m.support, metrics.fp[c, default: 0])
            }
            report += "\n**Top confusions** (expected → predicted instead)\n\n"
            for (pair, count) in metrics.confusions.sorted(by: { $0.value > $1.value }).prefix(25) {
                report += "- \(pair): \(count)\n"
            }
            report += "\n"
            print(String(format: "[%@] macro-F1 %.3f micro-F1 %.3f exact %.1f%% over %d images in %.1fs",
                         pass.rawValue, metrics.macroF1, metrics.microF1, 100 * Double(metrics.exact) / Double(max(1, metrics.total)), predictions.count, seconds))
            if let export = args.export, pass == .deep || args.passes == [.fast] {
                try exportGolden(featuresForExport.sorted { $0.0.file < $1.0.file }, to: export)
                print("exported \(featuresForExport.count) cases to \(export.path)")
            }
        }
        try report.write(to: args.corpus.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        print("report: \(args.corpus.appendingPathComponent("report.md").path)")
    }
}
