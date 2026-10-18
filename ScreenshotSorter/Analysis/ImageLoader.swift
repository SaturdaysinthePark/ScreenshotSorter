import Photos
import UIKit

enum ImageLoaderError: Error {
    case assetNotFound
    case noImage
    case needsNetwork
    case cancelled
    case timedOut
}

/// Loads screenshots for analysis at a bounded size without cropping.
enum PhotoImageLoader {

    static func asset(id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Thread-safe holder so the cancellation handler can reach the PhotoKit request id.
    private final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var requestID: PHImageRequestID = PHInvalidImageRequestID
        private var finished = false

        func set(_ id: PHImageRequestID) {
            lock.lock(); defer { lock.unlock() }
            requestID = id
        }

        func cancel() {
            lock.lock(); let id = requestID; lock.unlock()
            if id != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(id)
            }
        }

        /// Returns true the first time only (guards double-resume)
        func finish() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }
    }

    /// - Parameters:
    ///   - maxPixel: longest side in pixels (aspect ratio preserved)
    ///   - allowNetwork: download from iCloud if needed
    static func loadCGImage(id: String, maxPixel: CGFloat, allowNetwork: Bool) async throws -> CGImage {
        guard let asset = asset(id: id) else { throw ImageLoaderError.assetNotFound }
        let box = RequestBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = allowNetwork
                options.isSynchronous = false
                options.version = .current

                let target = CGSize(width: maxPixel, height: maxPixel)
                let requestID = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: target,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    // highQualityFormat delivers once, but be defensive about degraded callbacks
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    guard box.finish() else { return }
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: ImageLoaderError.cancelled)
                    } else if let cgImage = image?.cgImage {
                        continuation.resume(returning: cgImage)
                    } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                        continuation.resume(throwing: ImageLoaderError.needsNetwork)
                    } else {
                        continuation.resume(throwing: ImageLoaderError.noImage)
                    }
                }
                box.set(requestID)
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Runs `operation`, throwing `ImageLoaderError.timedOut` if it takes longer than `seconds`.
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ImageLoaderError.timedOut
        }
        guard let result = try await group.next() else { throw ImageLoaderError.timedOut }
        group.cancelAll()
        return result
    }
}
