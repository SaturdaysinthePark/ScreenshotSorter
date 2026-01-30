import Foundation
import Photos

/// Service for efficient PHAsset lookup by identifier
class PHAssetLookupService {
    static let shared = PHAssetLookupService()

    private var assetCache: [String: PHAsset] = [:]
    private let cacheQueue = DispatchQueue(label: "com.screenshotsorter.assetcache")

    private init() {}

    // MARK: - Public Methods

    /// Get a single PHAsset by identifier (checks cache first)
    func getAsset(for identifier: String) -> PHAsset? {
        // Check cache first
        if let cached = cacheQueue.sync(execute: { assetCache[identifier] }) {
            return cached
        }

        // Fetch from Photo Library
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else {
            return nil
        }

        // Cache it
        cacheQueue.sync {
            assetCache[identifier] = asset
        }

        return asset
    }

    /// Batch fetch multiple PHAssets by identifiers (more efficient than individual lookups)
    func fetchAssets(identifiers: [String]) -> [String: PHAsset] {
        guard !identifiers.isEmpty else { return [:] }

        // Find which ones we need to fetch
        var needed: [String] = []
        var result: [String: PHAsset] = [:]

        cacheQueue.sync {
            for id in identifiers {
                if let cached = assetCache[id] {
                    result[id] = cached
                } else {
                    needed.append(id)
                }
            }
        }

        // Batch fetch the ones we don't have
        if !needed.isEmpty {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: needed, options: nil)
            fetchResult.enumerateObjects { asset, _, _ in
                result[asset.localIdentifier] = asset
            }

            // Update cache
            cacheQueue.sync {
                for (id, asset) in result where !assetCache.keys.contains(id) {
                    assetCache[id] = asset
                }
            }
        }

        return result
    }

    /// Get count of screenshots in Photo Library (efficient count-only query)
    func fetchScreenshotCount() -> Int {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaSubtype == %d",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let result = PHAsset.fetchAssets(with: .image, options: options)
        return result.count
    }

    /// Clear the cache
    func clearCache() {
        cacheQueue.sync {
            assetCache.removeAll()
        }
    }

    /// Remove specific asset from cache (e.g., when deleted)
    func removeFromCache(identifier: String) {
        _ = cacheQueue.sync {
            assetCache.removeValue(forKey: identifier)
        }
    }
}
