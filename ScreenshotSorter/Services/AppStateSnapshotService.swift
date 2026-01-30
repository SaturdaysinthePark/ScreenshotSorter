import Foundation
import Photos

/// Manages persistent storage of complete app state for instant restoration
class AppStateSnapshotService {
    static let shared = AppStateSnapshotService()

    private let snapshotVersion = 1
    private let snapshotFileName = "app_state_snapshot.json"

    private init() {}

    // MARK: - Public Methods

    /// Check if a valid snapshot exists
    func hasValidSnapshot() -> Bool {
        guard let snapshot = loadSnapshot() else { return false }
        // Snapshot is valid if version matches and not too old (7 days)
        return snapshot.version == snapshotVersion && !snapshot.isExpired(days: 7)
    }

    /// Save current app state snapshot
    func saveSnapshot(screenshots: [Screenshot]) {
        let cachedScreenshots = screenshots.map { screenshot in
            CachedScreenshotData(
                assetIdentifier: screenshot.id,
                categories: screenshot.categories,
                categoriesWithConfidence: screenshot.categoriesWithConfidence.map {
                    CachedCategoryWithConfidence(
                        category: $0.category,
                        score: $0.score
                    )
                },
                creationDate: screenshot.creationDate,
                isProcessed: screenshot.processingStatus == .processed,
                isReviewed: screenshot.isReviewed
            )
        }

        let snapshot = AppStateSnapshot(
            screenshots: cachedScreenshots,
            lastKnownCount: screenshots.count,
            savedAt: Date(),
            version: snapshotVersion
        )

        saveSnapshotToFile(snapshot)
        #if DEBUG
        print("📸 Snapshot saved with \(screenshots.count) screenshots")
        #endif
    }

    /// Load app state snapshot
    func loadSnapshot() -> AppStateSnapshot? {
        return loadSnapshotFromFile()
    }

    /// Clear the snapshot
    func clearSnapshot() {
        let fileURL = getSnapshotFileURL()
        try? FileManager.default.removeItem(at: fileURL)
        #if DEBUG
        print("🗑️ Snapshot cleared")
        #endif
    }

    // MARK: - Private Methods

    private func getSnapshotFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("ScreenshotSorter", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        return appFolder.appendingPathComponent(snapshotFileName)
    }

    private func saveSnapshotToFile(_ snapshot: AppStateSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: getSnapshotFileURL())
        } catch {
            #if DEBUG
            print("❌ Failed to save snapshot: \(error)")
            #endif
        }
    }

    private func loadSnapshotFromFile() -> AppStateSnapshot? {
        let fileURL = getSnapshotFileURL()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(AppStateSnapshot.self, from: data)
            return snapshot
        } catch {
            #if DEBUG
            print("❌ Failed to load snapshot: \(error)")
            #endif
            return nil
        }
    }
}

// MARK: - Data Models

struct CachedCategoryWithConfidence: Codable {
    let category: ScreenshotCategory
    let score: Double
}

struct CachedScreenshotData: Codable {
    let assetIdentifier: String
    let categories: [ScreenshotCategory]
    let categoriesWithConfidence: [CachedCategoryWithConfidence]
    let creationDate: Date
    let isProcessed: Bool
    let isReviewed: Bool
}

struct AppStateSnapshot: Codable {
    let screenshots: [CachedScreenshotData]
    let lastKnownCount: Int
    let savedAt: Date
    let version: Int

    func isExpired(days: Int) -> Bool {
        let expirationInterval = TimeInterval(days * 24 * 60 * 60)
        return Date().timeIntervalSince(savedAt) > expirationInterval
    }
}
