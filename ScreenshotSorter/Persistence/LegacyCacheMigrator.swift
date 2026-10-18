import Foundation

/// One-time import of the pre-2026 caches (UserDefaults JSON blob + snapshot file) so
/// existing users see their collections instantly; everything is then re-analyzed in
/// the background by the new pipeline (records are imported with `visionVersion = 0`).
enum LegacyCacheMigrator {
    static let migratedKey = "legacy_migrated_v1"
    static let legacyCacheKey = "screenshot_categories_cache"
    static let legacyCountKey = "lastProcessedScreenshotCount"
    static let reviewedKey = "reviewedScreenshotIDs"

    private struct LegacyCached: Decodable {
        let assetIdentifier: String
        let categories: [String]
    }

    private struct LegacySnapshotItem: Decodable {
        let assetIdentifier: String
        let categories: [String]
        let creationDate: Date
        let isReviewed: Bool
    }

    private struct LegacySnapshot: Decodable {
        let screenshots: [LegacySnapshotItem]
    }

    static var snapshotURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ScreenshotSorter", isDirectory: true)
            .appendingPathComponent("app_state_snapshot.json")
    }

    static func migrateIfNeeded(into store: AnalysisStore, defaults: UserDefaults = .standard) async {
        guard await store.meta(migratedKey) == nil else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reviewed = Set(defaults.array(forKey: reviewedKey) as? [String] ?? [])

        var records: [String: AnalysisRecord] = [:]

        if let url = snapshotURL,
           let data = try? Data(contentsOf: url),
           let snapshot = try? decoder.decode(LegacySnapshot.self, from: data) {
            for item in snapshot.screenshots {
                records[item.assetIdentifier] = makeRecord(
                    id: item.assetIdentifier,
                    createdAt: item.creationDate,
                    categories: item.categories,
                    reviewed: item.isReviewed || reviewed.contains(item.assetIdentifier)
                )
            }
        }

        if let data = defaults.data(forKey: legacyCacheKey),
           let cache = try? decoder.decode([String: LegacyCached].self, from: data) {
            for (id, cached) in cache where records[id] == nil {
                records[id] = makeRecord(id: id, createdAt: Date(), categories: cached.categories, reviewed: reviewed.contains(id))
            }
        }

        if !records.isEmpty {
            await store.upsert(Array(records.values))
        }
        await store.setMeta(migratedKey, ISO8601DateFormatter().string(from: Date()))

        // The big blob slowed down every launch (UserDefaults loads it eagerly)
        defaults.removeObject(forKey: legacyCacheKey)
        defaults.removeObject(forKey: legacyCountKey)
        if let url = snapshotURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func makeRecord(id: String, createdAt: Date, categories: [String], reviewed: Bool) -> AnalysisRecord {
        var record = AnalysisRecord(id: id, createdAt: createdAt)
        record.tier = .fast
        record.visionVersion = 0
        record.rulesVersion = 0
        record.categories = categories
            .compactMap { ScreenshotCategory(persisted: $0) }
            .filter { $0 != .all }
            .map { ScoredCategory(category: $0, score: 0.6, sources: []) }
        record.isReviewed = reviewed
        return record
    }
}
