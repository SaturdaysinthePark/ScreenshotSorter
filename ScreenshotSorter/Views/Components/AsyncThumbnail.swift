import Photos
import SwiftUI

/// Square-cropped (or fitted) thumbnail for a screenshot, loaded through `ThumbnailLoader`.
/// Shows a tinted placeholder, then fades the image in. Cancels its request when it disappears.
struct AsyncThumbnail: View {
    let asset: PHAsset
    /// Side length in points used to pick the pixel size
    var pointSize: CGFloat = 120
    var contentMode: ContentMode = .fill
    var placeholderTint: Color = Palette.brand

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        ZStack {
            Rectangle()
                .fill(placeholderTint.opacity(0.10))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.18), value: image != nil)
        .task(id: asset.localIdentifier) {
            load()
        }
        .onDisappear {
            ThumbnailLoader.shared.cancel(requestID)
            requestID = PHInvalidImageRequestID
        }
        .accessibilityHidden(true)
    }

    private func load() {
        let size = ThumbnailLoader.pixelSize(points: pointSize)
        if let cached = ThumbnailLoader.shared.cached(asset, size: size) {
            image = cached
            return
        }
        image = nil
        requestID = ThumbnailLoader.shared.request(asset, size: size) { loaded in
            image = loaded
        }
    }
}
