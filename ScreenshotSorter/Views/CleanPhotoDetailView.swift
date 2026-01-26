import SwiftUI
import Photos
import UIKit

// MARK: - Photo Detail View (Full Screen Cover)

struct PhotoDetailView: View {
    let initialScreenshot: Screenshot
    let screenshots: [Screenshot]
    let thumbnails: [String: UIImage]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var showControls = true

    init(initialScreenshot: Screenshot, screenshots: [Screenshot], thumbnails: [String: UIImage]) {
        self.initialScreenshot = initialScreenshot
        self.screenshots = screenshots
        self.thumbnails = thumbnails
        self._currentIndex = State(initialValue: screenshots.firstIndex(where: { $0.id == initialScreenshot.id }) ?? 0)
    }

    private var currentScreenshot: Screenshot {
        guard currentIndex >= 0 && currentIndex < screenshots.count else {
            return initialScreenshot
        }
        return screenshots[currentIndex]
    }

    private var backgroundOpacity: Double {
        let progress = min(abs(dragOffset) / 200, 1.0)
        return 1.0 - progress * 0.5
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            // Photo pager
            TabView(selection: $currentIndex) {
                ForEach(screenshots.indices, id: \.self) { index in
                    let screenshot = screenshots[index]
                    ZoomablePhotoView(
                        screenshot: screenshot,
                        thumbnail: thumbnails[screenshot.id],
                        isActive: index == currentIndex,
                        onDismiss: { dismiss() },
                        onDragChanged: { offset in
                            dragOffset = offset
                            isDragging = offset != 0
                        },
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)

            // Controls overlay
            if showControls {
                VStack {
                    // Top bar
                    HStack {
                        Button(action: {
                            HapticManager.shared.lightTap()
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular, in: .circle)
                        }
                        .accessibilityLabel("Close photo viewer")
                        .accessibilityHint("Double-tap to close")

                        Spacer()

                        EnhancedShareButton(
                            screenshot: currentScreenshot,
                            thumbnails: thumbnails
                        )
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular, in: .circle)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    // Bottom counter
                    Text("\(currentIndex + 1) of \(screenshots.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 16)
                        .accessibilityLabel("Photo \(currentIndex + 1) of \(screenshots.count)")
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(showControls ? .automatic : .hidden)
        .tooltip(.doubleTapToZoom, text: "Double-tap to zoom in", icon: "hand.tap", position: .bottom)
    }
}

// MARK: - Zoomable Photo View

struct ZoomablePhotoView: View {
    let screenshot: Screenshot
    let thumbnail: UIImage?
    let isActive: Bool
    let onDismiss: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onTap: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var fullImage: UIImage?
    @State private var dragOffset: CGFloat = 0
    @State private var showZoomIndicator = false
    @State private var loadError: Bool = false
    @State private var isLoadingFullImage = false
    @State private var showFullImage = false
    @State private var isFitToWidthZoomed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let photoService = PhotoLibraryService.shared
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    private var isZoomed: Bool {
        scale > 1.01
    }

    private var zoomPercentage: Int {
        Int(scale * 100)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Error state
                if loadError && fullImage == nil && thumbnail == nil {
                    PhotoErrorView(onRetry: {
                        loadError = false
                        loadFullImage()
                    })
                }
                // Image content
                else if fullImage != nil || thumbnail != nil {
                    if isZoomed {
                        imageContent(in: geometry)
                            .gesture(
                                SimultaneousGesture(
                                    magnificationGesture(in: geometry),
                                    panGesture(in: geometry)
                                )
                            )
                            .onTapGesture(count: 2) {
                                doubleTapZoom(in: geometry)
                            }
                            .onTapGesture(count: 1) {
                                handleSingleTap(in: geometry)
                            }
                    } else {
                        imageContent(in: geometry)
                            .simultaneousGesture(magnificationGesture(in: geometry))
                            .simultaneousGesture(dismissGesture())
                            .onTapGesture(count: 2) {
                                doubleTapZoom(in: geometry)
                            }
                            .onTapGesture(count: 1) {
                                handleSingleTap(in: geometry)
                            }
                    }
                } else {
                    // No image at all, loading
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                }

                // Zoom percentage indicator
                if showZoomIndicator && isZoomed {
                    VStack {
                        Spacer()
                        Text("\(zoomPercentage)%")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                            .padding(.bottom, 80)
                            .transition(.opacity)
                    }
                    .accessibilityLabel("Zoom level \(zoomPercentage) percent")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            if isActive {
                loadFullImage()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                loadFullImage()
            } else {
                resetZoom()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photo. \(isZoomed ? "Zoomed to \(zoomPercentage) percent." : "") Double-tap to zoom.")
        .accessibilityHint("Drag down to dismiss")
    }

    // MARK: - Image Content

    @ViewBuilder
    private func imageContent(in geometry: GeometryProxy) -> some View {
        ZStack {
            // Thumbnail with blur while loading full image
            if thumbnail != nil && fullImage == nil {
                Image(uiImage: thumbnail!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .blur(radius: isLoadingFullImage ? 3 : 0)
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height + dragOffset)

                if isLoadingFullImage {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            }

            // Full image with crossfade
            if let fullImage = fullImage {
                Image(uiImage: fullImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height + dragOffset)
                    .opacity(showFullImage ? 1 : 0)
            }

            // No thumbnail and still loading
            if thumbnail == nil && fullImage == nil && !loadError {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)

                    Text("Loading image...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Gestures

    private func magnificationGesture(in geometry: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                let newScale = scale * delta

                // Allow slight overscale for rubber-band effect
                scale = min(max(newScale, minScale * 0.5), maxScale * 1.2)

                // Show zoom indicator
                showZoomPercentage()

                // Haptic at zoom boundaries
                if newScale <= minScale * 0.55 || newScale >= maxScale * 1.15 {
                    HapticManager.shared.zoomBoundary()
                }
            }
            .onEnded { _ in
                lastScale = 1.0
                isFitToWidthZoomed = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    // Snap to min/max if overscaled
                    scale = min(max(scale, minScale), maxScale)
                    if scale <= minScale {
                        offset = .zero
                    }
                }

                // Haptic feedback when snapping back
                if scale == minScale || scale == maxScale {
                    HapticManager.shared.zoomBoundary()
                }

                hideZoomPercentageAfterDelay()
            }
    }

    private func panGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let newOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                let constrained = constrainOffset(newOffset, in: geometry)
                offset = constrained

                // Haptic at pan boundaries
                if constrained.width != newOffset.width || constrained.height != newOffset.height {
                    HapticManager.shared.panBoundary()
                }
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func dismissGesture() -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Only respond to primarily vertical drags
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
                onDragChanged(dragOffset)
            }
            .onEnded { value in
                // Only process if the gesture was primarily vertical
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    if dragOffset != 0 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            dragOffset = 0
                            onDragChanged(0)
                        }
                    }
                    return
                }

                let velocity = value.predictedEndTranslation.height - value.translation.height
                let shouldDismiss = abs(dragOffset) > 100 || abs(velocity) > 500

                if shouldDismiss {
                    HapticManager.shared.lightTap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = dragOffset > 0 ? 400 : -400
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDismiss()
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = 0
                        onDragChanged(0)
                    }
                }
            }
    }

    private func constrainOffset(_ offset: CGSize, in geometry: GeometryProxy) -> CGSize {
        let imageSize = geometry.size
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale

        let maxOffsetX = max(0, (scaledWidth - imageSize.width) / 2)
        let maxOffsetY = max(0, (scaledHeight - imageSize.height) / 2)

        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }

    // MARK: - Tap Handling

    private func handleSingleTap(in geometry: GeometryProxy) {
        if !imageNaturallyFillsWidth(in: geometry) && !isZoomed && !isFitToWidthZoomed {
            // Image doesn't fill width at default zoom — zoom to fit width
            let targetScale = calculateFitToWidthScale(in: geometry)
            HapticManager.shared.lightTap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                scale = targetScale
                offset = .zero
                lastOffset = .zero
            }
            isFitToWidthZoomed = true
            showZoomPercentage()
            hideZoomPercentageAfterDelay()
        } else if isFitToWidthZoomed {
            // Was single-tap-zoomed — zoom back out
            HapticManager.shared.lightTap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                scale = 1.0
                offset = .zero
                lastOffset = .zero
            }
            isFitToWidthZoomed = false
        } else {
            // Normal: toggle controls
            onTap()
        }
    }

    private func doubleTapZoom(in geometry: GeometryProxy) {
        HapticManager.shared.mediumTap()
        isFitToWidthZoomed = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            if scale > 1.1 {
                scale = 1.0
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
            }
        }
        showZoomPercentage()
        hideZoomPercentageAfterDelay()
    }

    private func resetZoom() {
        isFitToWidthZoomed = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    // MARK: - Zoom Helpers

    private func imageNaturallyFillsWidth(in geometry: GeometryProxy) -> Bool {
        let viewWidth = geometry.size.width
        let viewHeight = geometry.size.height

        let imageWidth: CGFloat
        let imageHeight: CGFloat
        if let image = fullImage ?? thumbnail {
            imageWidth = image.size.width
            imageHeight = image.size.height
        } else {
            imageWidth = CGFloat(screenshot.asset.pixelWidth)
            imageHeight = CGFloat(screenshot.asset.pixelHeight)
        }

        guard imageWidth > 0 && imageHeight > 0 && viewWidth > 0 && viewHeight > 0 else { return true }

        let imageAspectRatio = imageWidth / imageHeight
        let viewAspectRatio = viewWidth / viewHeight

        // Image fills width at .fit if its aspect ratio >= view's aspect ratio
        // Small tolerance to avoid zoom for negligible differences
        return imageAspectRatio >= viewAspectRatio - 0.05
    }

    private func calculateFitToWidthScale(in geometry: GeometryProxy) -> CGFloat {
        let viewWidth = geometry.size.width
        let viewHeight = geometry.size.height

        let imageWidth: CGFloat
        let imageHeight: CGFloat
        if let image = fullImage ?? thumbnail {
            imageWidth = image.size.width
            imageHeight = image.size.height
        } else {
            imageWidth = CGFloat(screenshot.asset.pixelWidth)
            imageHeight = CGFloat(screenshot.asset.pixelHeight)
        }

        guard imageWidth > 0 && imageHeight > 0 && viewWidth > 0 && viewHeight > 0 else { return 2.5 }

        let imageAspectRatio = imageWidth / imageHeight
        let viewAspectRatio = viewWidth / viewHeight

        if imageAspectRatio < viewAspectRatio {
            // Portrait image, height-constrained at .fit
            // Displayed width at 1x = viewHeight * imageAspectRatio
            // To fill width: scale = viewWidth / displayedWidth
            let displayedWidth = viewHeight * imageAspectRatio
            let targetScale = viewWidth / displayedWidth
            return min(max(targetScale, 1.1), maxScale)
        } else {
            // Already fills width at 1x, use standard zoom level
            return min(2.5, maxScale)
        }
    }

    // MARK: - Zoom Indicator

    private func showZoomPercentage() {
        withAnimation(.easeIn(duration: 0.15)) {
            showZoomIndicator = true
        }
    }

    private func hideZoomPercentageAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showZoomIndicator = false
            }
        }
    }

    // MARK: - Image Loading

    private func loadFullImage() {
        guard fullImage == nil else { return }
        isLoadingFullImage = true

        photoService.loadFullSizeImage(for: screenshot.asset) { image in
            isLoadingFullImage = false

            if let image = image {
                fullImage = image

                // Crossfade animation
                if reduceMotion {
                    showFullImage = true
                } else {
                    withAnimation(.easeIn(duration: 0.25)) {
                        showFullImage = true
                    }
                }
            } else {
                loadError = true
            }
        }
    }
}

// MARK: - Photo Error View

struct PhotoErrorView: View {
    let onRetry: () -> Void

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(SemanticColor.warning.gradient)
                .symbolEffect(.pulse, options: .repeating.speed(0.5), value: isAnimating)

            VStack(spacing: 8) {
                Text("Unable to Load Image")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("The image could not be loaded from your photo library.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                HapticManager.shared.lightTap()
                onRetry()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Retry")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(SemanticColor.primary.gradient)
                .cornerRadius(12)
            }
            .accessibilityLabel("Retry loading image")
        }
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}

// MARK: - Enhanced Share Button

struct EnhancedShareButton: View {
    let screenshot: Screenshot
    let thumbnails: [String: UIImage]

    @State private var isLoadingShare = false
    @State private var showShareError = false

    private let photoService = PhotoLibraryService.shared

    var body: some View {
        Group {
            if isLoadingShare {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
            } else {
                Button(action: shareImage) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Share photo")
                .accessibilityHint("Double-tap to share this photo")
            }
        }
        .alert("Share Failed", isPresented: $showShareError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The image could not be prepared for sharing. Please try again.")
        }
    }

    private func shareImage() {
        HapticManager.shared.lightTap()

        // If we have a cached thumbnail, try full-size first
        if let thumbnail = thumbnails[screenshot.id] {
            // Try to load full-size for better share quality
            isLoadingShare = true
            photoService.loadFullSizeImage(for: screenshot.asset) { fullImage in
                isLoadingShare = false

                if let image = fullImage ?? thumbnails[screenshot.id] {
                    presentShareSheet(with: image)
                } else {
                    // Fallback to thumbnail
                    presentShareSheet(with: thumbnail)
                }
            }
        } else {
            // No thumbnail, load full image
            isLoadingShare = true
            photoService.loadFullSizeImage(for: screenshot.asset) { image in
                isLoadingShare = false

                if let image = image {
                    presentShareSheet(with: image)
                } else {
                    HapticManager.shared.error()
                    showShareError = true
                }
            }
        }
    }

    private func presentShareSheet(with image: UIImage) {
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            // Find the topmost presented view controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Legacy Support

struct CleanPhotoDetailView: View {
    let screenshot: Screenshot
    let allScreenshots: [Screenshot]
    let thumbnails: [String: UIImage]

    var body: some View {
        PhotoDetailView(
            initialScreenshot: screenshot,
            screenshots: allScreenshots,
            thumbnails: thumbnails
        )
    }
}

struct SinglePhotoView: View {
    let screenshot: Screenshot
    let thumbnail: UIImage?
    let isActive: Bool

    var body: some View {
        ZoomablePhotoView(
            screenshot: screenshot,
            thumbnail: thumbnail,
            isActive: isActive,
            onDismiss: {},
            onDragChanged: { _ in },
            onTap: {}
        )
    }
}
