import Foundation
import SQLite3

// Re-scores a copy of a real library database with the current rules — the same thing the app does
// when `PipelineVersion.rules` changes — and shows what would change.
//
//   Tools/eval/run.sh --db snap.sqlite [--out rescore.jsonl]
//
// Prints before/after counts per category and writes one JSON line per screenshot (old and new labels
// with sources, tags, rule hits, model insight, first OCR lines) for review with jq or Python.
// The output contains the library's own text: keep it on this machine.

struct RescoreLine: Codable {
    var id: String
    var before: [String]
    var after: [String]
    var tagsBefore: [String]
    var tagsAfter: [String]
    var ruleHits: [String: [String]]
    var vision: [String: Double]
    var model: String?
    /// Current FMClassifier's answer, when this screenshot was in the --model sample
    var modelNow: String?
    var afterWithModel: [String]?
    var app: String?
    var lines: Int
    var text: String
}

private func column(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
    guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
}

private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    sqlite3_column_text(statement, index).map { String(cString: $0) }
}

private func sourceLetters(_ sources: LabelSource) -> String {
    let letters: [(LabelSource, Character)] = [(.visionClassifier, "V"), (.ocrRules, "R"), (.appDetector, "A"), (.barcode, "B"),
                                                (.faces, "F"), (.layout, "L"), (.foundationModel, "M"), (.dataDetector, "D"),
                                                (.user, "U"), (.userKNN, "K"), (.nameTagger, "N")]
    return String(letters.filter { sources.contains($0.0) }.map(\.1))
}

/// "key:score:sources" pairs as stored in `assets.categories`
private func storedLabels(_ raw: String) -> [String] {
    raw.split(separator: ",").compactMap { pair in
        let parts = pair.split(separator: ":")
        guard parts.count >= 2, let score = Double(parts[1]) else { return nil }
        let sources = parts.count > 2 ? LabelSource(rawValue: Int(parts[2]) ?? 0) : []
        return String(format: "%@=%.2f[%@]", String(parts[0]), score, sourceLetters(sources))
    }
}

func runRescore(database: String, out: URL, modelSample: Int = 0) async throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(database, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { fatalError("cannot open \(database)") }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    let sql = "SELECT id, categories, tags, features, insight, entities FROM assets WHERE features IS NOT NULL ORDER BY created_at DESC"
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { fatalError(String(cString: sqlite3_errmsg(db))) }
    defer { sqlite3_finalize(statement) }

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    FileManager.default.createFile(atPath: out.path, contents: nil)
    let handle = try FileHandle(forWritingTo: out)
    var countsBefore: [String: Int] = [:], countsAfter: [String: Int] = [:]
    var total = 0, changed = 0, tagsBefore = 0, tagsAfter = 0
    var countStatement: OpaquePointer?
    var libraryCount = 1
    if sqlite3_prepare_v2(db, "SELECT count(*) FROM assets WHERE features IS NOT NULL", -1, &countStatement, nil) == SQLITE_OK,
       sqlite3_step(countStatement) == SQLITE_ROW {
        libraryCount = max(1, Int(sqlite3_column_int(countStatement, 0)))
    }
    sqlite3_finalize(countStatement)
    let stride = modelSample > 0 ? max(1, libraryCount / modelSample) : Int.max

    while sqlite3_step(statement) == SQLITE_ROW {
        guard let id = columnText(statement, 0),
              let featureData = column(statement, 3),
              let features = try? decoder.decode(ExtractedFeatures.self, from: featureData) else { continue }
        let insight = column(statement, 4).flatMap { try? decoder.decode(ModelInsight.self, from: $0) }
        let entities = column(statement, 5).flatMap { try? decoder.decode([ExtractedEntity].self, from: $0) } ?? []
        let oldTags = column(statement, 2).flatMap { try? decoder.decode([ScreenshotTag].self, from: $0) } ?? []

        let output = ScreenshotClassifier.classify(features: features, insight: insight, entities: entities)
        let before = storedLabels(columnText(statement, 1) ?? "")
        let after = output.categories.map { String(format: "%@=%.2f[%@]", $0.category.key, $0.score, sourceLetters($0.sources)) }
        func keys(_ labels: [String]) -> [String] { labels.map { String($0.prefix { $0 != "=" }) } }
        total += 1
        if keys(before) != keys(after) { changed += 1 }
        for key in keys(before) { countsBefore[key, default: 0] += 1 }
        for key in keys(after) { countsAfter[key, default: 0] += 1 }
        tagsBefore += oldTags.count
        tagsAfter += output.tags.count

        var hits: [String: [String]] = [:]
        for (category, hit) in RuleEngine.shared.evaluateDetailed(TextNormalizer.normalize(lines: features.lines), features: features) {
            hits[String(format: "%@=%.2f", category.key, hit.score)] = hit.matched
        }
        var vision: [String: Double] = [:]
        for label in features.labels.sorted(by: { $0.confidence > $1.confidence }).prefix(5) { vision[label.identifier] = label.confidence }
        let model = insight.map { insight in
            String(format: "%@ +%@ %.2f app=%@", insight.primary?.key ?? "-", insight.secondary.map(\.key).joined(separator: "/"),
                   insight.confidence, insight.app ?? "-")
        }
        var modelNow: String?
        var afterWithModel: [String]?
        if total % stride == 0, FMClassifier.isWorthAsking(features) {
            if case .insight(let fresh) = await FMClassifier.shared.insight(for: features, appHint: output.app?.displayName) {
                modelNow = String(format: "%@ +%@ %.1f \"%@\" tags=%@", fresh.primary?.key ?? "-",
                                  fresh.secondary.map(\.key).joined(separator: "/"), fresh.confidence, fresh.title,
                                  fresh.tags.joined(separator: ","))
                afterWithModel = ScreenshotClassifier.classify(features: features, insight: fresh, entities: entities).categories
                    .map { String(format: "%@=%.2f[%@]", $0.category.key, $0.score, sourceLetters($0.sources)) }
            }
            if total / stride % 20 == 19 { print("  model sample \(total / stride + 1)") }
        }
        let content = features.lines.filter { $0.zone != .statusBar }
        let line = RescoreLine(id: String(id.prefix(8)), before: before, after: after,
                               tagsBefore: oldTags.map { "\($0.value)[\(sourceLetters($0.sources))]" },
                               tagsAfter: output.tags.map { "\($0.value)[\(sourceLetters($0.sources))]" },
                               ruleHits: hits, vision: vision, model: model, modelNow: modelNow, afterWithModel: afterWithModel,
                               app: output.app?.displayName,
                               lines: content.count, text: String(content.map(\.text).joined(separator: " | ").prefix(400)))
        try handle.write(contentsOf: encoder.encode(line) + Data("\n".utf8))
    }

    print("\(total) screenshots · labels changed on \(changed) · tags \(tagsBefore) → \(tagsAfter)")
    print("category        before  after")
    for key in Set(countsBefore.keys).union(countsAfter.keys).sorted(by: { countsAfter[$0, default: 0] > countsAfter[$1, default: 0] }) {
        let b = countsBefore[key, default: 0], a = countsAfter[key, default: 0]
        print(key.padding(toLength: 16, withPad: " ", startingAt: 0) + String(format: "%6d %6d %@", b, a, a == b ? "" : String(format: "(%+d)", a - b)))
    }
    print("details: \(out.path)")
}
