import Photos
import UIKit

/// Thin PhotoKit wrapper: authorization, fetching, full-size loading and deletion.
/// Analysis image loading lives in `PhotoImageLoader`; grid thumbnails in `ThumbnailLoader`.
final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private init() {}

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var hasAccess: Bool {
        let status = authorizationStatus
        return status == .authorized || status == .limited
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                completion(status == .authorized || status == .limited)
            }
        }
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Fetch options for every screenshot, newest first.
    static func screenshotFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }

    func fetchScreenshotResult() -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(with: .image, options: PhotoLibraryService.screenshotFetchOptions())
    }

    /// All screenshots, newest first (enumerated off the main thread).
    func fetchScreenshots() async -> [PHAsset] {
        guard hasAccess else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.fetchScreenshotResult()
                var assets: [PHAsset] = []
                assets.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in assets.append(asset) }
                continuation.resume(returning: assets)
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

    /// Full-resolution image for the zoomable detail view.
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

    /// Deletes assets (the system shows its own confirmation). Store cleanup happens via
    /// `PhotoLibraryObserver` when PhotoKit reports the removal.
    func deleteAssets(_ assets: [PHAsset], completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    func deleteAssets(_ assets: [PHAsset]) async -> Bool {
        await withCheckedContinuation { continuation in
            deleteAssets(assets) { success, _ in continuation.resume(returning: success) }
        }
    }
}
