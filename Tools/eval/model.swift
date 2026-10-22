import Foundation

// `--model`: runs the app's FMClassifier (Apple's on-device language model, text only on macOS 26) on every
// deep-pass result, fuses it like the app does and reports how much the model helps — and how often its own
// picks are right. Requests run one at a time, as on device.

struct ModelLine: Codable {
    var file: String
    var expect: [String]
    var primary: String?
    var secondary: [String]
    var confidence: Double
    var title: String
    var tags: [String]
    var app: String?
    var ms: Double
    var fused: [String: Double]
}

func runModelPass(_ items: [(ManifestEntry, ExtractedFeatures)], corpus: URL) async throws -> (predictions: [Prediction], summary: String) {
    let out = corpus.appendingPathComponent("model.jsonl")
    FileManager.default.createFile(atPath: out.path, contents: nil)
    let handle = try FileHandle(forWritingTo: out)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var predictions: [Prediction] = []
    var primaryRight = 0, primaryTotal = 0, secondaryRight = 0, secondaryTotal = 0, unavailable = 0
    var latencies: [Double] = []
    let clock = ContinuousClock()

    for (index, (entry, features)) in items.enumerated() {
        let rulesOnly = ScreenshotClassifier.classify(features: features)
        let start = clock.now
        let outcome = await FMClassifier.shared.insight(for: features, appHint: rulesOnly.app?.displayName)
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        guard case .insight(let insight) = outcome else {
            unavailable += 1
            continue
        }
        latencies.append(ms)
        let fused = ScreenshotClassifier.classify(features: features, insight: insight)
        let accepted = Set(entry.expect + (entry.allow ?? []))
        // The model picks topics, never apps: only screenshots with a topic to find count
        let hasTopic = entry.expect.contains { ScreenshotCategory(key: $0).map { $0.kind != .app } ?? false }
        if hasTopic, let primary = insight.primary {
            primaryTotal += 1
            if accepted.contains(primary.key) { primaryRight += 1 }
        }
        for category in insight.secondary {
            secondaryTotal += 1
            if accepted.contains(category.key) { secondaryRight += 1 }
        }
        var predicted: [String: Double] = [:]
        var sources: [String: [String]] = [:]
        for scored in fused.categories {
            predicted[scored.category.key] = (scored.score * 100).rounded() / 100
            sources[scored.category.key] = sourceNames(scored.sources)
        }
        predictions.append(Prediction(
            file: entry.file, pass: .deep, expect: entry.expect, forbid: entry.forbid ?? [], allow: entry.allow ?? [],
            predicted: predicted, sources: sources, ruleHits: [:], visionLabels: [:],
            app: fused.app?.appID, expectedApp: entry.app, extractMs: 0, classifyMs: ms,
            ocrLines: features.lines.count, text: ""))
        let line = ModelLine(file: entry.file, expect: entry.expect, primary: insight.primary?.key,
                             secondary: insight.secondary.map(\.key), confidence: insight.confidence,
                             title: insight.title, tags: insight.tags, app: insight.app, ms: ms.rounded(), fused: predicted)
        try handle.write(contentsOf: encoder.encode(line) + Data("\n".utf8))
        if index % 25 == 24 { print("  model \(index + 1)/\(items.count)") }
    }
    let summary = String(format: "model topic right %d/%d (%.0f%%) · secondary right %d/%d (%.0f%%) · p50 %.0f ms · p95 %.0f ms · not answered %d",
                         primaryRight, primaryTotal, 100 * Double(primaryRight) / Double(max(1, primaryTotal)),
                         secondaryRight, secondaryTotal, 100 * Double(secondaryRight) / Double(max(1, secondaryTotal)),
                         percentile(latencies, 0.5), percentile(latencies, 0.95), unavailable)
    return (predictions, summary)
}
