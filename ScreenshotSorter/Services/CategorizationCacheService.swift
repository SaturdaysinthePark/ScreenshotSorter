import Foundation

/// Manages persistent storage of screenshot categorization results
class CategorizationCacheService {
    static let shared = CategorizationCacheService()

    private let userDefaults = UserDefaults.standard
    private let cacheKey = "screenshot_categories_cache"
    private let cacheVersion = 1
    private let expirationDays = 30

    private init() {}

    // MARK: - Public Methods

    /// Retrieve cached categories for a screenshot
    func getCachedCategories(for assetIdentifier: String) -> [ScreenshotCategory]? {
        guard let cache = loadCache() else { return nil }
        guard let cached = cache[assetIdentifier] else { return nil }

        // Check if expired
        if cached.isExpired(days: expirationDays) {
            print("⏰ Cache expired for asset: \(assetIdentifier)")
            return nil
        }

        // Check version compatibility
        if cached.version != cacheVersion {
            print("⚠️ Cache version mismatch for asset: \(assetIdentifier)")
            return nil
        }

        print("✅ Cache hit for asset: \(assetIdentifier) - \(cached.categories.map { $0.rawValue })")
        return cached.categories
    }

    /// Save categories for a screenshot
    func saveCategories(_ categories: [ScreenshotCategory], for assetIdentifier: String) {
        var cache = loadCache() ?? [:]

        let cached = CachedCategorization(
            assetIdentifier: assetIdentifier,
            categories: categories,
            timestamp: Date(),
            version: cacheVersion
        )

        cache[assetIdentifier] = cached
        saveCache(cache)

        print("💾 Saved to cache: \(assetIdentifier) - \(categories.map { $0.rawValue })")
    }

    /// Remove cached categories for a specific screenshot
    func removeCachedCategories(for assetIdentifier: String) {
        var cache = loadCache() ?? [:]
        cache.removeValue(forKey: assetIdentifier)
        saveCache(cache)
        print("🗑️ Removed from cache: \(assetIdentifier)")
    }

    /// Clear all cached categories
    func clearAllCache() {
        userDefaults.removeObject(forKey: cacheKey)
        print("🗑️ Cleared entire cache")
    }

    /// Get cache statistics
    func getCacheStats() -> CacheStats {
        guard let cache = loadCache() else {
            return CacheStats(totalEntries: 0, expiredEntries: 0, validEntries: 0)
        }

        let total = cache.count
        let expired = cache.values.filter { $0.isExpired(days: expirationDays) }.count
        let valid = total - expired

        return CacheStats(totalEntries: total, expiredEntries: expired, validEntries: valid)
    }

    /// Remove expired entries from cache
    func cleanupExpiredEntries() {
        guard var cache = loadCache() else { return }

        let beforeCount = cache.count
        cache = cache.filter { !$0.value.isExpired(days: expirationDays) }
        let afterCount = cache.count

        if beforeCount != afterCount {
            saveCache(cache)
            print("🧹 Cleaned up \(beforeCount - afterCount) expired cache entries")
        }
    }

    // MARK: - Private Methods

    private func loadCache() -> [String: CachedCategorization]? {
        guard let data = userDefaults.data(forKey: cacheKey) else { return nil }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode([String: CachedCategorization].self, from: data)
            return cache
        } catch {
            print("❌ Failed to decode cache: \(error)")
            return nil
        }
    }

    private func saveCache(_ cache: [String: CachedCategorization]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            userDefaults.set(data, forKey: cacheKey)
            print("💾 Cache saved with \(cache.count) entries")
        } catch {
            print("❌ Failed to encode cache: \(error)")
        }
    }
}

// MARK: - Supporting Types

struct CachedCategorization: Codable {
    let assetIdentifier: String
    let categories: [ScreenshotCategory]
    let timestamp: Date
    let version: Int

    func isExpired(days: Int) -> Bool {
        let expirationInterval = TimeInterval(days * 24 * 60 * 60)
        return Date().timeIntervalSince(timestamp) > expirationInterval
    }
}

struct CacheStats {
    let totalEntries: Int
    let expiredEntries: Int
    let validEntries: Int
}

// MARK: - ScreenshotCategory Codable Conformance

extension ScreenshotCategory: Codable {
    enum CodingKeys: String, CodingKey {
        case rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ScreenshotCategory(rawValue: rawValue) ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}
