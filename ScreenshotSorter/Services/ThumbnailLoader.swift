import Photos
import UIKit

/// Grid thumbnails through `PHCachingImageManager` with prefetching for visible ranges.
@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let manager = PHCachingImageManager()
    private let memory = NSCache<NSString, UIImage>()

    private init() {
        manager.allowsCachingHighQualityImages = false
        memory.countLimit = 600
    }

    static func pixelSize(points: CGFloat) -> CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: points * scale, height: points * scale)
    }

    private static func options() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }

    private func key(_ asset: PHAsset, _ size: CGSize) -> NSString {
        "\(asset.localIdentifier)|\(Int(size.width))" as NSString
    }

    func cached(_ asset: PHAsset, size: CGSize) -> UIImage? {
        memory.object(forKey: key(asset, size))
    }

    /// Delivers a fast degraded image first (if available), then the final one.
    /// The returned request id can be cancelled.
    @discardableResult
    func request(_ asset: PHAsset, size: CGSize, contentMode: PHImageContentMode = .aspectFill, update: @escaping (UIImage) -> Void) -> PHImageRequestID {
        let cacheKey = key(asset, size)
        if let image = memory.object(forKey: cacheKey) {
            update(image)
            return PHInvalidImageRequestID
        }
        return manager.requestImage(for: asset, targetSize: size, contentMode: contentMode, options: ThumbnailLoader.options()) { [weak self] image, info in
            guard let image else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            Task { @MainActor in
                if !degraded { self?.memory.setObject(image, forKey: cacheKey) }
                update(image)
            }
        }
    }

    /// Async variant returning the final (non-degraded) image.
    func image(for asset: PHAsset, size: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        if let cached = cached(asset, size: size) { return cached }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let cacheKey = key(asset, size)
            manager.requestImage(for: asset, targetSize: size, contentMode: contentMode, options: options) { [weak self] image, _ in
                Task { @MainActor in
                    if let image { self?.memory.setObject(image, forKey: cacheKey) }
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func cancel(_ requestID: PHImageRequestID) {
        guard requestID != PHInvalidImageRequestID else { return }
        manager.cancelImageRequest(requestID)
    }

    func startCaching(_ assets: [PHAsset], size: CGSize) {
        guard !assets.isEmpty else { return }
        manager.startCachingImages(for: assets, targetSize: size, contentMode: .aspectFill, options: ThumbnailLoader.options())
    }

    func stopCaching(_ assets: [PHAsset], size: CGSize) {
        guard !assets.isEmpty else { return }
        manager.stopCachingImages(for: assets, targetSize: size, contentMode: .aspectFill, options: ThumbnailLoader.options())
    }

    func reset() {
        manager.stopCachingImagesForAllAssets()
        memory.removeAllObjects()
    }
}
