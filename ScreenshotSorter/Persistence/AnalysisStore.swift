import Foundation
import os

/// Per-asset pipeline bookkeeping used to decide what to (re)analyze.
struct PipelineState: Sendable {
    let tier: AnalysisTier
    let visionVersion: Int
    let rulesVersion: Int
    let fmVersion: Int
    let failCount: Int
    let needsNetwork: Bool
}

struct FTSHit: Sendable {
    let id: String
    /// bm25 rank (lower is better)
    let rank: Double
    let snippet: String?
}

enum CorrectionKind: Int, Codable, Sendable {
    case category = 0
    case tag = 1
    case smartMember = 2
}

enum CorrectionAction: Int, Codable, Sendable {
    case add = 0
    case remove = 1
}

struct Correction: Sendable, Hashable {
    let assetID: String
    let kind: CorrectionKind
    let value: String
    let action: CorrectionAction
    /// Links the remove+add pair of a "move"
    let groupID: String?
    let createdAt: Date
}

enum SmartCollectionStatus: Int, Codable, Sendable {
    case suggested = 0
    case kept = 1
    case dismissed = 2
}

struct SmartCollection: Sendable, Identifiable, Hashable {
    let id: String
    var name: String
    var symbol: String
    var status: SmartCollectionStatus
    var centroid: [Float]
    var cohesion: Double
    var memberIDs: [String]
    /// Members the user removed — never re-added automatically
    var removedIDs: [String]
    var createdAt: Date
    var decidedAt: Date?
}

/// SQLite-backed persistence for analysis results, search index, corrections and smart collections.
actor AnalysisStore {
    static let schemaVersion = 1
    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "AnalysisStore")

    private let db: SQLiteDatabase
    nonisolated let isFTSAvailable: Bool
    nonisolated let isTrigramAvailable: Bool

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("ScreenshotSorter", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("analysis.sqlite")
    }

    /// Opens the default store, recreating it if the file is corrupt.
    static func openDefault() -> AnalysisStore {
        let url = defaultURL()
        if let store = try? AnalysisStore(path: url.path) {
            return store
        }
        logger.error("Analysis store unreadable — recreating")
        try? FileManager.default.removeItem(at: url)
        if let store = try? AnalysisStore(path: url.path) {
            return store
        }
        // Last resort: in-memory store so the app keeps working
        // swiftlint:disable:next force_try
        return try! AnalysisStore(path: ":memory:")
    }

    init(path: String) throws {
        let database = try SQLiteDatabase(path: path)
        let capabilities = try AnalysisStore.migrate(database)
        db = database
        isFTSAvailable = capabilities.fts
        isTrigramAvailable = capabilities.trigram
    }

    // MARK: - Schema

    private static func migrate(_ db: SQLiteDatabase) throws -> (fts: Bool, trigram: Bool) {
        var isFTSAvailable = false
        var isTrigramAvailable = false
        try db.execute("""
        CREATE TABLE IF NOT EXISTS assets(
            rid INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL,
            tier INTEGER NOT NULL DEFAULT 0,
            vision_version INTEGER NOT NULL DEFAULT 0,
            rules_version INTEGER NOT NULL DEFAULT 0,
            fm_version INTEGER NOT NULL DEFAULT 0,
            app TEXT,
            app_conf REAL NOT NULL DEFAULT 0,
            title TEXT,
            summary TEXT,
            ocr_text TEXT NOT NULL DEFAULT '',
            lang TEXT,
            features BLOB,
            insight BLOB,
            categories TEXT NOT NULL DEFAULT '',
            tags_text TEXT NOT NULL DEFAULT '',
            tags BLOB,
            entities BLOB,
            entity_types TEXT NOT NULL DEFAULT '',
            is_reviewed INTEGER NOT NULL DEFAULT 0,
            needs_network INTEGER NOT NULL DEFAULT 0,
            fail_count INTEGER NOT NULL DEFAULT 0,
            analyzed_at REAL
        );
        CREATE TABLE IF NOT EXISTS embeddings(id TEXT PRIMARY KEY, model TEXT NOT NULL, vec BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS featureprints(id TEXT PRIMARY KEY, vec BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS corrections(
            cid INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_id TEXT NOT NULL,
            kind INTEGER NOT NULL,
            value TEXT NOT NULL,
            action INTEGER NOT NULL,
            group_id TEXT,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS corrections_asset ON corrections(asset_id);
        CREATE TABLE IF NOT EXISTS learned_bias(category TEXT PRIMARY KEY, bias REAL NOT NULL, n INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS smart_collections(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            symbol TEXT NOT NULL,
            status INTEGER NOT NULL,
            centroid BLOB,
            cohesion REAL NOT NULL DEFAULT 0,
            members TEXT NOT NULL DEFAULT '',
            removed TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL,
            decided_at REAL
        );
        CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
        """)

        do {
            try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
                title, tags, app, entities, ocr,
                tokenize = 'porter unicode61 remove_diacritics 2'
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS search_vocab USING fts5vocab(search_fts, 'row');
            """)
            isFTSAvailable = true
        } catch {
            AnalysisStore.logger.error("FTS5 unavailable: \(String(describing: error), privacy: .public)")
        }
        if isFTSAvailable {
            do {
                try db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS search_tri USING fts5(body, tokenize = 'trigram');")
                isTrigramAvailable = true
            } catch {
                AnalysisStore.logger.info("Trigram tokenizer unavailable")
            }
        }
        if db.userVersion < AnalysisStore.schemaVersion {
            db.userVersion = AnalysisStore.schemaVersion
        }
        return (isFTSAvailable, isTrigramAvailable)
    }

    // MARK: - Encoding helpers

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// "key:score:sources,key:score:sources" — compact so loading 10k summaries is fast
    static func encodeCategories(_ categories: [ScoredCategory]) -> String {
        categories
            .map { "\($0.category.key):\(String(format: "%.3f", $0.score)):\($0.sources.rawValue)" }
            .joined(separator: ",")
    }

    static func decodeCategories(_ string: String) -> [ScoredCategory] {
        guard !string.isEmpty else { return [] }
        return string.split(separator: ",").compactMap { part in
            let fields = part.split(separator: ":")
            guard fields.count == 3,
                  let category = ScreenshotCategory(persisted: String(fields[0])),
                  let score = Double(fields[1]),
                  let sources = Int(fields[2]) else { return nil }
            return ScoredCategory(category: category, score: score, sources: LabelSource(rawValue: sources))
        }
    }

    private static let tagSeparator = "|"

    private static func encode<T: Encodable>(_ value: T?) -> SQLiteValue {
        guard let value, let data = try? encoder.encode(value) else { return .null }
        return .blob(data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }

    // MARK: - Records

    func upsert(_ records: [AnalysisRecord]) {
        guard !records.isEmpty else { return }
        do {
            try db.transaction {
                for record in records {
                    try upsertOne(record)
                }
            }
        } catch {
            AnalysisStore.logger.error("upsert failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func upsertOne(_ record: AnalysisRecord) throws {
        let tagsText = record.tags.map(\.value).joined(separator: AnalysisStore.tagSeparator)
        try db.run("""
        INSERT INTO assets(id, created_at, tier, vision_version, rules_version, fm_version, app, app_conf, title, summary,
                           ocr_text, lang, features, insight, categories, tags_text, tags, entities, entity_types,
                           is_reviewed, needs_network, fail_count, analyzed_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
            created_at = excluded.created_at, tier = excluded.tier, vision_version = excluded.vision_version,
            rules_version = excluded.rules_version, fm_version = excluded.fm_version, app = excluded.app,
            app_conf = excluded.app_conf, title = excluded.title, summary = excluded.summary,
            ocr_text = excluded.ocr_text, lang = excluded.lang, features = excluded.features,
            insight = excluded.insight, categories = excluded.categories, tags_text = excluded.tags_text,
            tags = excluded.tags, entities = excluded.entities, entity_types = excluded.entity_types,
            is_reviewed = excluded.is_reviewed,
            needs_network = excluded.needs_network, fail_count = excluded.fail_count, analyzed_at = excluded.analyzed_at
        """, [
            .text(record.id),
            .double(record.createdAt.timeIntervalSince1970),
            .int(record.tier.rawValue),
            .int(record.visionVersion),
            .int(record.rulesVersion),
            .int(record.fmVersion),
            record.app.map { .text($0) } ?? .null,
            .double(record.appConfidence),
            record.title.map { .text($0) } ?? .null,
            record.summary.map { .text($0) } ?? .null,
            .text(record.ocrText),
            record.language.map { .text($0) } ?? .null,
            AnalysisStore.encode(record.features),
            AnalysisStore.encode(record.insight),
            .text(AnalysisStore.encodeCategories(record.categories)),
            .text(tagsText),
            AnalysisStore.encode(record.tags),
            AnalysisStore.encode(record.entities),
            .text(Set(record.entities.map(\.type.rawValue)).sorted().joined(separator: ",")),
            .int(record.isReviewed ? 1 : 0),
            .int(record.needsNetwork ? 1 : 0),
            .int(record.failCount),
            .double(record.analyzedAt.timeIntervalSince1970)
        ])

        if let embedding = record.embedding, let model = record.embeddingModel {
            try db.run("INSERT OR REPLACE INTO embeddings(id, model, vec) VALUES(?,?,?)",
                       [.text(record.id), .text(model), .blob(embedding.sqliteData)])
        }
        if let print = record.featurePrint {
            try db.run("INSERT OR REPLACE INTO featureprints(id, vec) VALUES(?,?)",
                       [.text(record.id), .blob(print.sqliteData)])
        }
        try indexForSearch(record)
    }

    private func rowID(for id: String) throws -> Int? {
        var rid: Int?
        try db.query("SELECT rid FROM assets WHERE id = ?", [.text(id)]) { rid = $0.int(0) }
        return rid
    }

    private func indexForSearch(_ record: AnalysisRecord) throws {
        guard isFTSAvailable, let rid = try rowID(for: record.id) else { return }
        let categoryWords = record.categories.map(\.category.displayName).joined(separator: " ")
        let tags = (record.tags.map(\.value) + [categoryWords]).joined(separator: " ")
        let entities = record.entities.map(\.value).joined(separator: " ")
        let title = [record.title, record.summary].compactMap { $0 }.joined(separator: " — ")
        try db.run("DELETE FROM search_fts WHERE rowid = ?", [.int(rid)])
        try db.run("INSERT INTO search_fts(rowid, title, tags, app, entities, ocr) VALUES(?,?,?,?,?,?)", [
            .int(rid), .text(title), .text(tags), .text(record.app ?? ""), .text(entities), .text(record.ocrText)
        ])
        if isTrigramAvailable {
            try db.run("DELETE FROM search_tri WHERE rowid = ?", [.int(rid)])
            try db.run("INSERT INTO search_tri(rowid, body) VALUES(?,?)", [
                .int(rid), .text([title, tags, record.ocrText].joined(separator: "\n"))
            ])
        }
    }

    private static let recordColumns = """
    id, created_at, tier, vision_version, rules_version, fm_version, app, app_conf, title, summary, ocr_text, lang,
    features, insight, categories, tags, entities, is_reviewed, needs_network, fail_count, analyzed_at
    """

    private func readRecord(_ row: SQLiteStatement) -> AnalysisRecord {
        var record = AnalysisRecord(id: row.text(0) ?? "", createdAt: Date(timeIntervalSince1970: row.double(1)))
        record.tier = AnalysisTier(rawValue: row.int(2)) ?? .none
        record.visionVersion = row.int(3)
        record.rulesVersion = row.int(4)
        record.fmVersion = row.int(5)
        record.app = row.text(6)
        record.appConfidence = row.double(7)
        record.title = row.text(8)
        record.summary = row.text(9)
        record.ocrText = row.text(10) ?? ""
        record.language = row.text(11)
        record.features = AnalysisStore.decode(ExtractedFeatures.self, row.blob(12))
        record.insight = AnalysisStore.decode(ModelInsight.self, row.blob(13))
        record.categories = AnalysisStore.decodeCategories(row.text(14) ?? "")
        record.tags = AnalysisStore.decode([ScreenshotTag].self, row.blob(15)) ?? []
        record.entities = AnalysisStore.decode([ExtractedEntity].self, row.blob(16)) ?? []
        record.isReviewed = row.int(17) != 0
        record.needsNetwork = row.int(18) != 0
        record.failCount = row.int(19)
        record.analyzedAt = Date(timeIntervalSince1970: row.double(20))
        return record
    }

    func record(id: String) -> AnalysisRecord? {
        var result: AnalysisRecord?
        try? db.query("SELECT \(AnalysisStore.recordColumns) FROM assets WHERE id = ?", [.text(id)]) { row in
            result = readRecord(row)
        }
        if var found = result {
            try? db.query("SELECT model, vec FROM embeddings WHERE id = ?", [.text(id)]) { row in
                found.embeddingModel = row.text(0)
                found.embedding = row.blob(1).map { [Float](sqliteData: $0) }
            }
            try? db.query("SELECT vec FROM featureprints WHERE id = ?", [.text(id)]) { row in
                found.featurePrint = row.blob(0).map { [Float](sqliteData: $0) }
            }
            result = found
        }
        return result
    }

    func records(ids: [String]) -> [AnalysisRecord] {
        ids.compactMap { record(id: $0) }
    }

    /// Lightweight projection of every analyzed asset (used at launch).
    func loadSummaries() -> [RecordSummary] {
        var summaries: [RecordSummary] = []
        try? db.query("SELECT id, created_at, tier, categories, tags_text, app, title, is_reviewed FROM assets") { row in
            let tagsText = row.text(4) ?? ""
            summaries.append(RecordSummary(
                id: row.text(0) ?? "",
                creationDate: Date(timeIntervalSince1970: row.double(1)),
                tier: AnalysisTier(rawValue: row.int(2)) ?? .none,
                categories: AnalysisStore.decodeCategories(row.text(3) ?? ""),
                tags: tagsText.isEmpty ? [] : tagsText.components(separatedBy: AnalysisStore.tagSeparator),
                app: row.text(5),
                title: row.text(6),
                isReviewed: row.int(7) != 0
            ))
        }
        return summaries
    }

    /// Entity types per asset (for "with links" style search filters)
    func entityTypeMap() -> [String: Set<EntityType>] {
        var map: [String: Set<EntityType>] = [:]
        try? db.query("SELECT id, entity_types FROM assets WHERE entity_types != ''") { row in
            guard let id = row.text(0), let text = row.text(1) else { return }
            map[id] = Set(text.split(separator: ",").compactMap { EntityType(rawValue: String($0)) })
        }
        return map
    }

    func pipelineStates() -> [String: PipelineState] {
        var states: [String: PipelineState] = [:]
        try? db.query("SELECT id, tier, vision_version, rules_version, fm_version, fail_count, needs_network FROM assets") { row in
            states[row.text(0) ?? ""] = PipelineState(
                tier: AnalysisTier(rawValue: row.int(1)) ?? .none,
                visionVersion: row.int(2),
                rulesVersion: row.int(3),
                fmVersion: row.int(4),
                failCount: row.int(5),
                needsNetwork: row.int(6) != 0
            )
        }
        return states
    }

    func delete(ids: [String]) {
        guard !ids.isEmpty else { return }
        do {
            try db.transaction {
                for id in ids {
                    if isFTSAvailable, let rid = try rowID(for: id) {
                        try db.run("DELETE FROM search_fts WHERE rowid = ?", [.int(rid)])
                        if isTrigramAvailable {
                            try db.run("DELETE FROM search_tri WHERE rowid = ?", [.int(rid)])
                        }
                    }
                    try db.run("DELETE FROM assets WHERE id = ?", [.text(id)])
                    try db.run("DELETE FROM embeddings WHERE id = ?", [.text(id)])
                    try db.run("DELETE FROM featureprints WHERE id = ?", [.text(id)])
                    try db.run("DELETE FROM corrections WHERE asset_id = ?", [.text(id)])
                }
            }
        } catch {
            AnalysisStore.logger.error("delete failed: \(String(describing: error), privacy: .public)")
        }
    }

    func setReviewed(ids: [String], reviewed: Bool) {
        try? db.transaction {
            for id in ids {
                try db.run("UPDATE assets SET is_reviewed = ? WHERE id = ?", [.int(reviewed ? 1 : 0), .text(id)])
            }
        }
    }

    /// Marks records so the scheduler re-runs them (keeps existing labels visible meanwhile).
    func invalidate(ids: [String]?, resetVision: Bool) {
        let column = resetVision ? "vision_version" : "rules_version"
        if let ids {
            try? db.transaction {
                for id in ids {
                    try db.run("UPDATE assets SET \(column) = 0, fail_count = 0 WHERE id = ?", [.text(id)])
                }
            }
        } else {
            try? db.execute("UPDATE assets SET \(column) = 0, fail_count = 0")
        }
    }

    // MARK: - Vectors

    func embeddings(model: String) -> [(String, [Float])] {
        var result: [(String, [Float])] = []
        try? db.query("SELECT id, vec FROM embeddings WHERE model = ?", [.text(model)]) { row in
            if let id = row.text(0), let data = row.blob(1) {
                result.append((id, [Float](sqliteData: data)))
            }
        }
        return result
    }

    func featurePrints() -> [(String, [Float])] {
        var result: [(String, [Float])] = []
        try? db.query("SELECT id, vec FROM featureprints") { row in
            if let id = row.text(0), let data = row.blob(1) {
                result.append((id, [Float](sqliteData: data)))
            }
        }
        return result
    }

    // MARK: - Search

    /// `match` is an FTS5 MATCH expression built by `SearchService`.
    func ftsSearch(match: String, limit: Int) -> [FTSHit] {
        guard isFTSAvailable, !match.isEmpty else { return [] }
        var hits: [FTSHit] = []
        // Column weights: title, tags, app, entities, ocr
        let sql = """
        SELECT assets.id, bm25(search_fts, 4.0, 3.0, 2.0, 1.5, 1.0) AS rank,
               snippet(search_fts, 4, '[', ']', '…', 10)
        FROM search_fts JOIN assets ON assets.rid = search_fts.rowid
        WHERE search_fts MATCH ?
        ORDER BY rank LIMIT ?
        """
        do {
            try db.query(sql, [.text(match), .int(limit)]) { row in
                hits.append(FTSHit(id: row.text(0) ?? "", rank: row.double(1), snippet: row.text(2)))
            }
        } catch {
            AnalysisStore.logger.debug("FTS query failed: \(String(describing: error), privacy: .public)")
        }
        return hits
    }

    /// Substring search (good for codes, order numbers, partial words).
    func trigramSearch(_ text: String, limit: Int) -> [String] {
        guard isTrigramAvailable, text.count >= 3 else { return [] }
        var ids: [String] = []
        let escaped = "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        try? db.query("""
        SELECT assets.id FROM search_tri JOIN assets ON assets.rid = search_tri.rowid
        WHERE search_tri MATCH ? LIMIT ?
        """, [.text(escaped), .int(limit)]) { row in
            if let id = row.text(0) { ids.append(id) }
        }
        return ids
    }

    /// Fallback when FTS5 is unavailable.
    func likeSearch(_ text: String, limit: Int) -> [String] {
        var ids: [String] = []
        let pattern = "%" + text.replacingOccurrences(of: "%", with: "") + "%"
        try? db.query("""
        SELECT id FROM assets WHERE ocr_text LIKE ? OR tags_text LIKE ? OR title LIKE ? OR app LIKE ? LIMIT ?
        """, [.text(pattern), .text(pattern), .text(pattern), .text(pattern), .int(limit)]) { row in
            if let id = row.text(0) { ids.append(id) }
        }
        return ids
    }

    /// OCR text for a handful of ids (collection matching counts how often a word appears)
    func ocrTexts(ids: [String]) -> [String: String] {
        var texts: [String: String] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 200).map({ Array(ids[$0..<min($0 + 200, ids.count)]) }) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            try? db.query("SELECT id, ocr_text FROM assets WHERE id IN (\(placeholders))", chunk.map { .text($0) }) { row in
                if let id = row.text(0) { texts[id] = row.text(1) ?? "" }
            }
        }
        return texts
    }

    /// Indexed vocabulary (for typo correction)
    func vocabulary(minimumDocuments: Int = 1) -> [String] {
        guard isFTSAvailable else { return [] }
        var terms: [String] = []
        try? db.query("SELECT term FROM search_vocab WHERE doc >= ?", [.int(minimumDocuments)]) { row in
            if let term = row.text(0) { terms.append(term) }
        }
        return terms
    }

    // MARK: - Corrections & learning

    func addCorrections(_ corrections: [Correction]) {
        try? db.transaction {
            for correction in corrections {
                try db.run("""
                INSERT INTO corrections(asset_id, kind, value, action, group_id, created_at) VALUES(?,?,?,?,?,?)
                """, [
                    .text(correction.assetID), .int(correction.kind.rawValue), .text(correction.value),
                    .int(correction.action.rawValue), correction.groupID.map { .text($0) } ?? .null,
                    .double(correction.createdAt.timeIntervalSince1970)
                ])
            }
        }
    }

    func removeCorrections(groupID: String) {
        try? db.run("DELETE FROM corrections WHERE group_id = ?", [.text(groupID)])
    }

    func allCorrections() -> [Correction] {
        var result: [Correction] = []
        try? db.query("SELECT asset_id, kind, value, action, group_id, created_at FROM corrections ORDER BY cid") { row in
            guard let kind = CorrectionKind(rawValue: row.int(1)),
                  let action = CorrectionAction(rawValue: row.int(3)) else { return }
            result.append(Correction(
                assetID: row.text(0) ?? "",
                kind: kind,
                value: row.text(2) ?? "",
                action: action,
                groupID: row.text(4),
                createdAt: Date(timeIntervalSince1970: row.double(5))
            ))
        }
        return result
    }

    func learnedBias() -> [ScreenshotCategory: (bias: Double, count: Int)] {
        var result: [ScreenshotCategory: (bias: Double, count: Int)] = [:]
        try? db.query("SELECT category, bias, n FROM learned_bias") { row in
            if let category = row.text(0).flatMap({ ScreenshotCategory(persisted: $0) }) {
                result[category] = (row.double(1), row.int(2))
            }
        }
        return result
    }

    func setLearnedBias(_ category: ScreenshotCategory, bias: Double, count: Int) {
        try? db.run("INSERT OR REPLACE INTO learned_bias(category, bias, n) VALUES(?,?,?)",
                    [.text(category.key), .double(bias), .int(count)])
    }

    // MARK: - Smart collections

    func smartCollections() -> [SmartCollection] {
        var result: [SmartCollection] = []
        try? db.query("""
        SELECT id, name, symbol, status, centroid, cohesion, members, removed, created_at, decided_at FROM smart_collections
        """) { row in
            let members = row.text(6) ?? ""
            let removed = row.text(7) ?? ""
            result.append(SmartCollection(
                id: row.text(0) ?? "",
                name: row.text(1) ?? "",
                symbol: row.text(2) ?? "sparkles",
                status: SmartCollectionStatus(rawValue: row.int(3)) ?? .suggested,
                centroid: row.blob(4).map { [Float](sqliteData: $0) } ?? [],
                cohesion: row.double(5),
                memberIDs: members.isEmpty ? [] : members.components(separatedBy: AnalysisStore.tagSeparator),
                removedIDs: removed.isEmpty ? [] : removed.components(separatedBy: AnalysisStore.tagSeparator),
                createdAt: Date(timeIntervalSince1970: row.double(8)),
                decidedAt: row.isNull(9) ? nil : Date(timeIntervalSince1970: row.double(9))
            ))
        }
        return result
    }

    func saveSmartCollection(_ collection: SmartCollection) {
        try? db.run("""
        INSERT OR REPLACE INTO smart_collections(id, name, symbol, status, centroid, cohesion, members, removed, created_at, decided_at)
        VALUES(?,?,?,?,?,?,?,?,?,?)
        """, [
            .text(collection.id), .text(collection.name), .text(collection.symbol), .int(collection.status.rawValue),
            .blob(collection.centroid.sqliteData), .double(collection.cohesion),
            .text(collection.memberIDs.joined(separator: AnalysisStore.tagSeparator)),
            .text(collection.removedIDs.joined(separator: AnalysisStore.tagSeparator)),
            .double(collection.createdAt.timeIntervalSince1970),
            collection.decidedAt.map { .double($0.timeIntervalSince1970) } ?? .null
        ])
    }

    func deleteSmartCollection(id: String) {
        try? db.run("DELETE FROM smart_collections WHERE id = ?", [.text(id)])
    }

    // MARK: - Meta

    func meta(_ key: String) -> String? {
        var value: String?
        try? db.query("SELECT value FROM meta WHERE key = ?", [.text(key)]) { value = $0.text(0) }
        return value
    }

    func setMeta(_ key: String, _ value: String?) {
        if let value {
            try? db.run("INSERT OR REPLACE INTO meta(key, value) VALUES(?,?)", [.text(key), .text(value)])
        } else {
            try? db.run("DELETE FROM meta WHERE key = ?", [.text(key)])
        }
    }
}
