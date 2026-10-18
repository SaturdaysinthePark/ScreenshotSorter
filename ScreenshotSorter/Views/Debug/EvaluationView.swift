#if DEBUG
import SwiftUI

/// DEBUG-only tool for tuning accuracy on real screenshots.
///
/// Shows what the pipeline extracted for recent screenshots and exports them in the
/// `golden_features.json` format (with current predictions as `expect`). Edit the
/// expectations, scrub personal text, and append to the test fixtures.
struct EvaluationView: View {
    @Environment(AppModel.self) private var model
    @State private var records: [AnalysisRecord] = []
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section("Pipeline") {
                LabeledContent("Screenshots", value: "\(model.library.count)")
                LabeledContent("Analyzed", value: "\(model.library.analyzedCount)")
                LabeledContent("Fast queue", value: "\(model.progress.fastRemaining)")
                LabeledContent("Deep queue", value: "\(model.progress.deepRemaining)")
                LabeledContent("Throughput", value: String(format: "%.1f / s", model.progress.itemsPerSecond))
                LabeledContent("Language model", value: FMClassifier.isAvailable ? "Available" : "Unavailable")
            }
            if let exportURL {
                Section {
                    ShareLink(item: exportURL) {
                        Label("Export \(records.count) as golden fixtures", systemImage: "square.and.arrow.up")
                    }
                }
            }
            Section("Recent") {
                ForEach(records, id: \.id) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title ?? record.id).font(.headline).lineLimit(1)
                        Text(record.categories.map { "\($0.category.key) \(String(format: "%.2f", $0.score))" }.joined(separator: ", "))
                            .font(.caption.monospaced())
                        if let app = record.app {
                            Text("app: \(app) (\(String(format: "%.2f", record.appConfidence)))").font(.caption)
                        }
                        Text(labelsLine(record))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("tags: " + record.tags.map(\.value).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Evaluation")
        .task { await load() }
    }

    private func load() async {
        let ids = Array(model.library.orderedIDs.prefix(60))
        records = await model.store.records(ids: ids).filter { $0.features != nil }
        exportURL = writeExport(records)
    }

    private func writeExport(_ records: [AnalysisRecord]) -> URL? {
        let cases: [[String: Any]] = records.compactMap { record in
            guard let features = record.features else { return nil }
            var item: [String: Any] = [
                "name": record.title ?? record.id,
                "lines": features.lines.map { [$0.text, zoneName($0.zone)] },
                "labels": features.labels.prefix(10).map { [$0.identifier, $0.confidence] as [Any] },
                "barcodes": features.barcodes.map(\.symbology),
                "expect": record.categories.map(\.category.key)
            ]
            if features.faces.largestAreaFraction > 0 { item["faceArea"] = features.faces.largestAreaFraction }
            if let app = record.app { item["appDisplayName"] = app }
            return item
        }
        guard let data = try? JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("golden_export.json")
        try? data.write(to: url)
        return url
    }

    private func labelsLine(_ record: AnalysisRecord) -> String {
        guard let labels = record.features?.labels, !labels.isEmpty else { return "labels: -" }
        let parts: [String] = labels.prefix(5).map { label in
            "\(label.identifier) \(Int(label.confidence * 100))%"
        }
        return "labels: " + parts.joined(separator: ", ")
    }

    private func zoneName(_ zone: ScreenZone) -> String {
        switch zone {
        case .statusBar: return "statusBar"
        case .topBar: return "topBar"
        case .body: return "body"
        case .bottomBar: return "bottomBar"
        }
    }
}
#endif
