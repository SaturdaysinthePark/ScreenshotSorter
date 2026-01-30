import Photos
import UIKit

class PhotoLibraryService: ObservableObject {
    static let shared = PhotoLibraryService()

    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private init() {
        checkAuthorizationStatus()
    }

    func checkAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                completion(status == .authorized || status == .limited)
            }
        }
    }

    func fetchScreenshots(completion: @escaping ([PHAsset]) -> Void) {
        // Always check current authorization status
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        #if DEBUG
        print("📸 PhotoLibraryService.fetchScreenshots() - Authorization: \(currentStatus.rawValue)")
        #endif

        guard currentStatus == .authorized || currentStatus == .limited else {
            #if DEBUG
            print("📸 Authorization denied, returning empty array")
            #endif
            completion([])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %d", PHAssetMediaSubtype.photoScreenshot.rawValue)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var screenshots: [PHAsset] = []

            results.enumerateObjects { asset, _, _ in
                screenshots.append(asset)
            }

            #if DEBUG
            print("📸 PhotoLibraryService found \(screenshots.count) screenshots")
            #endif

            DispatchQueue.main.async {
                completion(screenshots)
            }
        }
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize = CGSize(width: 300, height: 300), completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func loadFullSizeImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func deleteAssets(_ assets: [PHAsset], completion: @escaping (Bool, Error?) -> Void) {
        // Store asset IDs for cache cleanup
        let assetIds = assets.map { $0.localIdentifier }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, error in
            // Clean up cache on successful deletion
            if success {
                let cacheService = CategorizationCacheService.shared
                for assetId in assetIds {
                    cacheService.removeCachedCategories(for: assetId)
                }
                #if DEBUG
                print("🗑️ Cleaned up cache for \(assetIds.count) deleted assets")
                #endif
            }

            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    // MARK: - Async/Await Variants

    /// Load image for categorization with async/await
    func loadImageAsync(for asset: PHAsset, targetSize: CGSize = CGSize(width: 1024, height: 1024)) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            var hasResumed = false
            let lock = NSLock()

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                lock.lock()
                defer { lock.unlock() }

                if !hasResumed {
                    hasResumed = true
                    #if DEBUG
                    print("⏱️ Image load timeout for asset: \(asset.localIdentifier)")
                    #endif
                    continuation.resume(throwing: PhotoLibraryError.timeout)
                }
            }

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                lock.lock()
                defer { lock.unlock() }

                guard !hasResumed else { return }
                hasResumed = true

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.imageNotFound)
                }
            }
        }
    }
}

// MARK: - Error Types

enum PhotoLibraryError: Error {
    case timeout
    case imageNotFound
    case unauthorized
    case unknown

    var localizedDescription: String {
        switch self {
        case .timeout:
            return "Image loading timed out"
        case .imageNotFound:
            return "Image not found or unavailable"
        case .unauthorized:
            return "Photo library access not authorized"
        case .unknown:
            return "Unknown error occurred"
        }
    }
}
