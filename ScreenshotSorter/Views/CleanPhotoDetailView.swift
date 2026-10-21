import Photos
import SwiftUI
import UIKit

// MARK: - Photo Detail View
/// Full-screen pager for screenshots: pinch / double-tap zoom with rubber-banding, swipe down to
/// close (swipe up for details), a crossfade from the grid thumbnail to the full image, glass chrome
/// and an "Insight" drawer with everything we read from the screenshot.

struct PhotoDetailView: View {
    let screenshots: [Screenshot]
    let initialID: String
    let context: CollectionKind?
    let onCurrentChange: ((String) -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentID: String
    @State private var scrollID: String?
    @State private var deletedIDs: Set<String> = []
    @State private var showChrome: Bool = true
    @State private var isZoomed: Bool = false
    @State private var dismissOffset: CGSize = .zero
    @State private var isDragDismissing: Bool = false
    @State private var isDismissing: Bool = false
    @State private var drawerExpanded: Bool = false
    @State private var drawerDrag: CGFloat = 0
    @State private var peekHeight: CGFloat = 132
    @State private var showDeleteConfirm: Bool = false
    @State private var editTarget: DetailEditTarget?
    @State private var sharePayload: ScreenshotSharePayload?
    @State private var isPreparingShare: Bool = false
    @State private var toast: DetailToast?

    init(
        screenshots: [Screenshot],
        initialID: String,
        context: CollectionKind? = nil,
        onCurrentChange: ((String) -> Void)? = nil
    ) {
        self.screenshots = screenshots
        self.initialID = initialID
        self.context = context
        self.onCurrentChange = onCurrentChange
        _currentID = State(initialValue: initialID)
        _scrollID = State(initialValue: initialID)
    }

    // MARK: Body

    var body: some View {
        let pages: [Screenshot] = livePages
        let current: Screenshot? = pages.first { $0.id == currentID }

        GeometryReader { proxy in
            let metrics: DrawerMetrics = DrawerMetrics(containerHeight: proxy.size.height, peekHeight: peekHeight)
            let visible: CGFloat = drawerVisibleHeight(metrics)
            let progress: CGFloat = metrics.progress(forVisibleHeight: visible)

            ZStack(alignment: .top) {
                backgroundLayer

                pager(pages: pages, progress: progress, topInset: proxy.safeAreaInsets.top)

                if drawerExpanded {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            setDrawer(expanded: false)
                        }
                        .accessibilityHidden(true)
                }

                chromeLayer(current: current, pages: pages, metrics: metrics, visible: visible, progress: progress)
            }
        }
        .statusBarHidden(!showChrome)
        .persistentSystemOverlays(showChrome ? .automatic : .hidden)
        .presentationBackground(.clear)
        .interactiveDismissDisabled()
        .onAppear {
            onCurrentChange?(currentID)
        }
        .onChange(of: scrollID) { _, newValue in
            guard let newValue, newValue != currentID else { return }
            currentID = newValue
        }
        .onChange(of: currentID) { _, newValue in
            isZoomed = false
            onCurrentChange?(newValue)
        }
        .onChange(of: pages.count) { _, _ in
            ensureValidCurrent()
        }
        .confirmationDialog(
            Text(Brand.Copy.Detail.deleteTitle),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(Brand.Copy.Detail.delete, role: .destructive) {
                deleteCurrent()
            }
            Button(Brand.Copy.Completion.goBack, role: .cancel) {}
        } message: {
            Text(Brand.Copy.Completion.deleteWarning)
        }
        .sheet(item: $editTarget) { target in
            EditLabelsSheet(screenshotIDs: [target.id])
        }
        .sheet(item: $sharePayload) { payload in
            ScreenshotShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    // MARK: Derived

    /// The snapshot passed in, minus deletions, with fresh analysis data from the library.
    private var livePages: [Screenshot] {
        var result: [Screenshot] = []
        result.reserveCapacity(screenshots.count)
        for screenshot in screenshots where !deletedIDs.contains(screenshot.id) {
            if let live = model.library.screenshot(id: screenshot.id) {
                result.append(live)
            }
        }
        return result
    }

    private var backgroundOpacity: Double {
        if isDismissing { return 0 }
        let distance: Double = Double(max(0, dismissOffset.height))
        return max(0, 1 - distance / 320)
    }

    private func drawerVisibleHeight(_ metrics: DrawerMetrics) -> CGFloat {
        let base: CGFloat = drawerExpanded ? metrics.expanded : metrics.peek
        let raw: CGFloat = base - drawerDrag
        if raw > metrics.expanded {
            return metrics.expanded + (raw - metrics.expanded) * 0.2
        }
        if raw < metrics.peek {
            return max(0, metrics.peek - (metrics.peek - raw) * 0.2)
        }
        return raw
    }

    // MARK: Layers

    private var backgroundLayer: some View {
        // Canvas with chrome (great contrast for glass in both appearances); black when immersive.
        let base: Color = showChrome ? Palette.canvas : Color.black
        return base
            .opacity(backgroundOpacity)
            .ignoresSafeArea()
            .dsAnimation(Motion.gentle, value: showChrome)
    }

    private func pager(pages: [Screenshot], progress: CGFloat, topInset: CGFloat) -> some View {
        let dragY: CGFloat = dismissOffset.height
        let downward: CGFloat = max(0, dragY)
        let dragProgress: CGFloat = min(1, downward / 320)
        let yOffset: CGFloat = dragY >= 0 ? dragY : dragY * 0.25
        let dismissScale: CGFloat = 1 - 0.22 * dragProgress
        let drawerScale: CGFloat = 1 - 0.38 * progress
        let drawerLift: CGFloat = progress * (topInset + Space.xxl)

        return ScrollViewReader { reader in
            pagerScrollView(pages: pages)
                .onAppear {
                    // Belt and braces: make sure the first frame shows the tapped screenshot.
                    reader.scrollTo(initialID)
                }
        }
        .scaleEffect(drawerScale, anchor: .top)
        .offset(y: drawerLift)
        .scaleEffect(dismissScale)
        .offset(x: dismissOffset.width * 0.5, y: yOffset)
    }

    private func pagerScrollView(pages: [Screenshot]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages) { screenshot in
                    ZoomablePhotoPage(
                        screenshot: screenshot,
                        isActive: screenshot.id == currentID,
                        onSingleTap: { handleSingleTap() },
                        onZoomChange: { zoomed in
                            if isZoomed != zoomed {
                                isZoomed = zoomed
                            }
                        },
                        onDismissDrag: { translation in
                            handleDismissDrag(translation)
                        },
                        onDismissEnd: { translation, velocity in
                            handleDismissEnd(translation: translation, velocity: velocity)
                        },
                        onPinchDismiss: { dismissViewer() }
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollID)
        .scrollIndicators(.hidden)
        .scrollDisabled(isZoomed || isDragDismissing || drawerExpanded)
        .ignoresSafeArea()
    }

    private func chromeLayer(
        current: Screenshot?,
        pages: [Screenshot],
        metrics: DrawerMetrics,
        visible: CGFloat,
        progress: CGFloat
    ) -> some View {
        let dragFade: Double = 1 - min(1, Double(abs(dismissOffset.height)) / 140)
        let chromeOpacity: Double = (showChrome && !isDismissing) ? dragFade : 0
        let interactive: Bool = showChrome && !isDismissing && !isDragDismissing

        return VStack(spacing: Space.sm) {
            topBar(current: current, pages: pages)
                .padding(.horizontal, Space.md)
                .padding(.top, Space.xs)
                .offset(y: showChrome ? 0 : -Space.xxl)

            if let toast {
                DetailToastView(toast: toast)
                    .transition(toastTransition)
                    .task(id: toast.id) {
                        await autoHideToast(toast.id)
                    }
            }

            Spacer(minLength: 0)

            if let current {
                InsightDrawer(
                    screenshot: current,
                    isExpanded: drawerExpanded,
                    progress: progress,
                    visibleHeight: visible,
                    expandedHeight: metrics.expanded,
                    canJump: { id in pages.contains { $0.id == id } },
                    onPeekHeight: { height in
                        if abs(peekHeight - height) > 0.5 {
                            peekHeight = height
                        }
                    },
                    onToggle: { setDrawer(expanded: !drawerExpanded) },
                    onDragChanged: { translation in
                        drawerDrag = translation
                    },
                    onDragEnded: { translation, velocity in
                        finishDrawerDrag(translation: translation, velocity: velocity, metrics: metrics)
                    },
                    onEdit: {
                        HapticManager.shared.lightTap()
                        editTarget = DetailEditTarget(id: current.id)
                    },
                    onJump: { id in jump(to: id) },
                    onToast: { message, systemImage in
                        showToast(message, systemImage: systemImage, tint: Palette.brand)
                    }
                )
                .padding(.horizontal, Space.xs)
                .offset(y: showChrome ? 0 : metrics.expanded + Space.xxl)
            }
        }
        .opacity(chromeOpacity)
        .allowsHitTesting(interactive)
    }

    private var toastTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity)
    }

    // MARK: Top bar

    private func topBar(current: Screenshot?, pages: [Screenshot]) -> some View {
        GlassEffectContainer(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Button {
                    dismissViewer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Brand.Copy.Detail.close)

                Spacer(minLength: 0)

                if let current {
                    titleCapsule(current: current, pages: pages)
                }

                Spacer(minLength: 0)

                Button {
                    if let current {
                        share(current)
                    }
                } label: {
                    ZStack {
                        Image(systemName: "square.and.arrow.up")
                            .opacity(isPreparingShare ? 0 : 1)
                        if isPreparingShare {
                            ProgressView()
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(current == nil || isPreparingShare)
                .accessibilityLabel(Brand.Copy.Detail.share)

                Menu {
                    Button {
                        if let current {
                            editTarget = DetailEditTarget(id: current.id)
                        }
                    } label: {
                        Label(Brand.Copy.Detail.editLabels, systemImage: "tag")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(Brand.Copy.Detail.delete, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(current == nil)
                .accessibilityLabel(Brand.Copy.Detail.more)
            }
        }
    }

    private func titleCapsule(current: Screenshot, pages: [Screenshot]) -> some View {
        let index: Int = (pages.firstIndex { $0.id == current.id } ?? 0) + 1
        let dayText: String = DetailDates.dayTitle(current.creationDate)
        let timeText: String = current.creationDate.formatted(date: .omitted, time: .shortened)
        return VStack(spacing: 0) {
            Text(dayText + " · " + timeText)
                .font(.dsCaption.weight(.heavy))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if pages.count > 1 {
                Text(Brand.Copy.Detail.position(index, pages.count))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(index)))
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs - 1)
        .glassEffect(.regular, in: .capsule)
        .dsAnimation(Motion.snappy, value: index)
        .accessibilityElement(children: .combine)
    }

    // MARK: Interaction

    private func handleSingleTap() {
        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
            showChrome.toggle()
            if !showChrome {
                drawerExpanded = false
                drawerDrag = 0
            }
        }
    }

    private func setDrawer(expanded: Bool) {
        guard drawerExpanded != expanded || drawerDrag != 0 else { return }
        HapticManager.shared.selectionChanged()
        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
            drawerExpanded = expanded
            drawerDrag = 0
            if expanded {
                showChrome = true
            }
        }
    }

    private func finishDrawerDrag(translation: CGFloat, velocity: CGFloat, metrics: DrawerMetrics) {
        let base: CGFloat = drawerExpanded ? metrics.expanded : metrics.peek
        let projected: CGFloat = base - translation - velocity * 0.18
        let expand: Bool = projected > metrics.peek + metrics.range * 0.5
        if expand != drawerExpanded {
            HapticManager.shared.selectionChanged()
        }
        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
            drawerExpanded = expand
            drawerDrag = 0
        }
    }

    private func handleDismissDrag(_ translation: CGSize) {
        if !isDragDismissing {
            isDragDismissing = true
        }
        dismissOffset = translation
    }

    private func handleDismissEnd(translation: CGSize, velocity: CGSize) {
        isDragDismissing = false
        let dy: CGFloat = translation.height
        let vy: CGFloat = velocity.height
        if dy > 110 || (dy > 24 && vy > 900) {
            dismissViewer()
            return
        }
        let expand: Bool = dy < -60 || (dy < -16 && vy < -700)
        if expand {
            HapticManager.shared.selectionChanged()
        }
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            dismissOffset = .zero
            if expand {
                showChrome = true
                drawerExpanded = true
            }
        }
    }

    private func dismissViewer() {
        guard !isDismissing else { return }
        HapticManager.shared.lightTap()
        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
            isDismissing = true
            dismissOffset = .zero
            drawerExpanded = false
            drawerDrag = 0
        }
        dismiss()
    }

    private func jump(to id: String) {
        guard livePages.contains(where: { $0.id == id }) else { return }
        HapticManager.shared.pageTurn()
        Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
            drawerExpanded = false
            drawerDrag = 0
            scrollID = id
            currentID = id
        }
    }

    private func ensureValidCurrent() {
        let pages: [Screenshot] = livePages
        guard !pages.contains(where: { $0.id == currentID }) else { return }
        guard let first = pages.first else {
            dismissViewer()
            return
        }
        currentID = first.id
        scrollID = first.id
    }

    // MARK: Actions

    private func share(_ screenshot: Screenshot) {
        guard !isPreparingShare else { return }
        HapticManager.shared.lightTap()
        isPreparingShare = true
        let asset: PHAsset = screenshot.asset
        Task {
            let images: [UIImage] = await ScreenshotExporter.images(for: [asset])
            isPreparingShare = false
            guard !images.isEmpty else {
                HapticManager.shared.error()
                showToast(Brand.Copy.Gallery.shareFailed, systemImage: "exclamationmark.triangle.fill", tint: Palette.toss)
                return
            }
            sharePayload = ScreenshotSharePayload(items: images)
        }
    }

    private func deleteCurrent() {
        let id: String = currentID
        let pagesBefore: [Screenshot] = livePages
        let index: Int = pagesBefore.firstIndex { $0.id == id } ?? 0
        Task {
            let success: Bool = await model.delete([id])
            guard success else {
                showToast(Brand.Copy.Completion.deleteCancelled, systemImage: "hand.raised.fill", tint: Palette.inkSecondary)
                return
            }
            let remaining: [Screenshot] = pagesBefore.filter { $0.id != id }
            guard !remaining.isEmpty else {
                deletedIDs.insert(id)
                dismissViewer()
                return
            }
            let nextIndex: Int = min(index, remaining.count - 1)
            let nextID: String = remaining[nextIndex].id
            Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
                deletedIDs.insert(id)
                currentID = nextID
                scrollID = nextID
            }
        }
    }

    private func showToast(_ message: String, systemImage: String, tint: Color) {
        let next: DetailToast = DetailToast(message: message, systemImage: systemImage, tint: tint)
        UIAccessibility.post(notification: .announcement, argument: message)
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            toast = next
        }
    }

    private func autoHideToast(_ id: UUID) async {
        try? await Task.sleep(for: .seconds(1.8))
        guard !Task.isCancelled, toast?.id == id else { return }
        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
            toast = nil
        }
    }
}

// MARK: - Supporting Types

private struct DetailEditTarget: Identifiable {
    let id: String
}

private struct DetailToast: Identifiable {
    let id: UUID
    let message: String
    let systemImage: String
    let tint: Color

    init(message: String, systemImage: String, tint: Color) {
        self.id = UUID()
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
    }
}

private struct DrawerMetrics {
    let peek: CGFloat
    let expanded: CGFloat

    init(containerHeight: CGFloat, peekHeight: CGFloat) {
        let resolvedPeek: CGFloat = max(peekHeight, 60)
        peek = resolvedPeek
        let target: CGFloat = min(containerHeight * 0.66, containerHeight - 72)
        expanded = max(resolvedPeek + 120, target)
    }

    var range: CGFloat {
        max(1, expanded - peek)
    }

    func progress(forVisibleHeight visible: CGFloat) -> CGFloat {
        min(1, max(0, (visible - peek) / range))
    }
}

enum DetailDates {
    static func dayTitle(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return Brand.Copy.Gallery.today
        }
        if calendar.isDateInYesterday(date) {
            return Brand.Copy.Gallery.yesterday
        }
        let sameYear: Bool = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        if sameYear {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private struct DetailToastView: View {
    let toast: DetailToast

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: toast.systemImage)
                .font(.dsCaption.weight(.heavy))
                .foregroundStyle(toast.tint)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(.dsCaption.weight(.heavy))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Zoomable Photo Page

private struct ZoomablePhotoPage: View {
    let screenshot: Screenshot
    let isActive: Bool
    let onSingleTap: () -> Void
    let onZoomChange: (Bool) -> Void
    let onDismissDrag: (CGSize) -> Void
    let onDismissEnd: (CGSize, CGSize) -> Void
    let onPinchDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Images
    @State private var thumbnail: UIImage?
    @State private var fullImage: UIImage?
    @State private var loadFailed: Bool = false
    @State private var reloadToken: Int = 0

    // Transform
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    // Pinch
    @State private var pinchStartScale: CGFloat?
    @State private var pinchStartOffset: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @State private var didHitScaleEdge: Bool = false
    @GestureState private var isMagnifying: Bool = false

    // Pan (zoomed)
    @State private var panStartOffset: CGSize?
    @State private var lastPanVelocity: CGSize = .zero
    @State private var didHitPanEdge: Bool = false
    @GestureState private var isPanning: Bool = false

    // Drag to dismiss (not zoomed)
    @State private var dismissTracking: Bool = false
    @State private var lastDismissTranslation: CGSize = .zero
    @State private var lastDismissVelocity: CGSize = .zero

    private var maxScale: CGFloat { 4 }
    private var doubleTapScale: CGFloat { 2.5 }

    private var isZoomed: Bool { scale > 1.01 }

    private var loadKey: String {
        screenshot.id + "#" + String(reloadToken) + (isActive ? "#a" : "#i")
    }

    private var showsError: Bool {
        loadFailed && thumbnail == nil && fullImage == nil
    }

    var body: some View {
        ZStack {
            photoContent

            if showsError {
                PhotoLoadErrorView {
                    loadFailed = false
                    reloadToken += 1
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            containerSize = size
        }
        .task(id: loadKey) {
            await loadImages()
        }
        .onChange(of: isActive) { _, active in
            if !active {
                resetZoom()
                // Free the full-resolution bitmap; the thumbnail stays for an instant return.
                fullImage = nil
            }
        }
        .onDisappear {
            fullImage = nil
        }
    }

    private var photoContent: some View {
        ZStack {
            imageLayer

            if thumbnail == nil && fullImage == nil && !loadFailed {
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.brand)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(panGesture, including: isZoomed ? .all : .subviews)
        .gesture(dismissGesture)
        .simultaneousGesture(magnifyGesture)
        .onTapGesture(count: 2, coordinateSpace: .local) { location in
            toggleZoom(at: location)
        }
        .onTapGesture(count: 1) {
            onSingleTap()
        }
        .onChange(of: isMagnifying) { _, active in
            if !active {
                finishPinch(magnification: lastMagnification)
            }
        }
        .onChange(of: isPanning) { _, active in
            if !active {
                finishPan(velocity: lastPanVelocity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(Brand.Copy.Detail.photoHint)
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: Text(isZoomed ? Brand.Copy.Detail.zoomOut : Brand.Copy.Detail.zoomIn)) {
            toggleZoom(at: CGPoint(x: containerSize.width / 2, y: containerSize.height / 2))
        }
    }

    private var accessibilityText: String {
        let base: String = screenshot.title ?? Brand.Copy.Detail.fallbackTitle
        if isZoomed {
            return base + ". " + Brand.Copy.Detail.zoomLevel(Int((scale * 100).rounded()))
        }
        return base
    }

    private var imageLayer: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            if let fullImage {
                Image(uiImage: fullImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .transition(AnyTransition.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(scale)
        .offset(offset)
    }

    // MARK: Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .updating($isMagnifying) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale = scale
                    pinchStartOffset = offset
                    panStartOffset = nil
                    // Stop the pager from paging under a two-finger gesture.
                    onZoomChange(true)
                    if dismissTracking {
                        // A second finger landed mid swipe-down: treat it as a pinch instead.
                        dismissTracking = false
                        onDismissEnd(.zero, .zero)
                    }
                }
                lastMagnification = value.magnification
                let startScale: CGFloat = pinchStartScale ?? 1
                let raw: CGFloat = startScale * value.magnification
                let next: CGFloat = rubberBandScale(raw)
                let size: CGSize = containerSize
                let anchorX: CGFloat = value.startAnchor.x * size.width - size.width / 2
                let anchorY: CGFloat = value.startAnchor.y * size.height - size.height / 2
                let ratio: CGFloat = next / max(startScale, 0.01)
                // Keep the content under the pinch anchor fixed while scaling.
                offset = CGSize(
                    width: anchorX - (anchorX - pinchStartOffset.width) * ratio,
                    height: anchorY - (anchorY - pinchStartOffset.height) * ratio
                )
                scale = next
                let outOfBounds: Bool = raw > maxScale || raw < 1
                if outOfBounds && !didHitScaleEdge {
                    didHitScaleEdge = true
                    HapticManager.shared.zoomBoundary()
                } else if !outOfBounds {
                    didHitScaleEdge = false
                }
            }
            .onEnded { value in
                finishPinch(magnification: value.magnification)
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($isPanning) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard pinchStartScale == nil else {
                    panStartOffset = nil
                    return
                }
                if panStartOffset == nil {
                    panStartOffset = CGSize(
                        width: offset.width - value.translation.width,
                        height: offset.height - value.translation.height
                    )
                }
                let start: CGSize = panStartOffset ?? .zero
                let proposed: CGSize = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
                let banded: CGSize = rubberBandOffset(proposed)
                if banded != proposed && !didHitPanEdge {
                    didHitPanEdge = true
                    HapticManager.shared.panBoundary()
                }
                offset = banded
                lastPanVelocity = value.velocity
            }
            .onEnded { value in
                finishPan(velocity: value.velocity)
            }
    }

    /// UIKit-backed so it only begins for mostly-vertical drags: a SwiftUI `DragGesture` on the
    /// pager's content claims every pan and stops the horizontal paging scroll view.
    private var dismissGesture: VerticalPanGesture {
        VerticalPanGesture(
            isEnabled: !isZoomed,
            onChanged: { translation, velocity in
                guard pinchStartScale == nil, !isZoomed else { return }
                dismissTracking = true
                lastDismissTranslation = translation
                lastDismissVelocity = velocity
                onDismissDrag(translation)
            },
            onEnded: { translation, velocity in
                finishDismiss(translation: translation, velocity: velocity)
            }
        )
    }

    // MARK: Gesture completion (idempotent; also called if a gesture is cancelled)

    private func finishPinch(magnification: CGFloat) {
        guard let startScale = pinchStartScale else { return }
        pinchStartScale = nil
        lastMagnification = 1
        didHitScaleEdge = false
        let raw: CGFloat = startScale * magnification
        if startScale <= 1.01 && raw < 0.7 {
            // Pinch-in from fit closes the viewer, like Photos.
            Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
                scale = 1
                offset = .zero
            }
            onPinchDismiss()
            return
        }
        settle()
    }

    private func finishPan(velocity: CGSize) {
        guard panStartOffset != nil else { return }
        panStartOffset = nil
        didHitPanEdge = false
        lastPanVelocity = .zero
        guard pinchStartScale == nil else { return }
        let projected: CGSize = CGSize(
            width: offset.width + velocity.width * 0.18,
            height: offset.height + velocity.height * 0.18
        )
        let target: CGSize = clampedOffset(projected, scale: scale)
        Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
            offset = target
        }
    }

    private func finishDismiss(translation: CGSize, velocity: CGSize) {
        guard dismissTracking else { return }
        dismissTracking = false
        lastDismissTranslation = .zero
        lastDismissVelocity = .zero
        onDismissEnd(translation, velocity)
    }

    private func settle() {
        let target: CGFloat = min(max(scale, 1), maxScale)
        let finalScale: CGFloat = target <= 1.01 ? 1 : target
        let targetOffset: CGSize = finalScale <= 1 ? .zero : clampedOffset(offset, scale: finalScale)
        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
            scale = finalScale
            offset = targetOffset
        }
        onZoomChange(finalScale > 1)
    }

    private func toggleZoom(at location: CGPoint) {
        HapticManager.shared.softTap()
        if isZoomed {
            Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
                scale = 1
                offset = .zero
            }
            onZoomChange(false)
            return
        }
        let size: CGSize = containerSize
        let target: CGFloat = doubleTapScale
        // Zoom so the tapped point stays under the finger.
        let proposed: CGSize = CGSize(
            width: (size.width / 2 - location.x) * (target - 1),
            height: (size.height / 2 - location.y) * (target - 1)
        )
        let clamped: CGSize = clampedOffset(proposed, scale: target)
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            scale = target
            offset = clamped
        }
        onZoomChange(true)
    }

    private func resetZoom() {
        guard isZoomed || offset != .zero else { return }
        scale = 1
        offset = .zero
        pinchStartScale = nil
        panStartOffset = nil
    }

    // MARK: Geometry

    private func fittedSize() -> CGSize {
        let size: CGSize = containerSize
        guard size.width > 0, size.height > 0 else { return .zero }
        let pixelWidth: CGFloat = CGFloat(max(screenshot.asset.pixelWidth, 1))
        let pixelHeight: CGFloat = CGFloat(max(screenshot.asset.pixelHeight, 1))
        let imageAspect: CGFloat = pixelWidth / pixelHeight
        let containerAspect: CGFloat = size.width / size.height
        if imageAspect > containerAspect {
            return CGSize(width: size.width, height: size.width / imageAspect)
        }
        return CGSize(width: size.height * imageAspect, height: size.height)
    }

    private func limits(forScale value: CGFloat) -> CGSize {
        let fitted: CGSize = fittedSize()
        let maxX: CGFloat = max(0, (fitted.width * value - containerSize.width) / 2)
        let maxY: CGFloat = max(0, (fitted.height * value - containerSize.height) / 2)
        return CGSize(width: maxX, height: maxY)
    }

    private func clampedOffset(_ proposed: CGSize, scale value: CGFloat) -> CGSize {
        let limit: CGSize = limits(forScale: value)
        let x: CGFloat = min(max(proposed.width, -limit.width), limit.width)
        let y: CGFloat = min(max(proposed.height, -limit.height), limit.height)
        return CGSize(width: x, height: y)
    }

    private func rubberBandOffset(_ proposed: CGSize) -> CGSize {
        let limit: CGSize = limits(forScale: scale)
        let x: CGFloat = ZoomablePhotoPage.rubberBand(proposed.width, limit: limit.width)
        let y: CGFloat = ZoomablePhotoPage.rubberBand(proposed.height, limit: limit.height)
        return CGSize(width: x, height: y)
    }

    private static func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        if value > limit {
            return limit + (value - limit) * 0.3
        }
        if value < -limit {
            return -limit + (value + limit) * 0.3
        }
        return value
    }

    private func rubberBandScale(_ raw: CGFloat) -> CGFloat {
        if raw < 1 {
            return max(0.5, 1 - (1 - raw) * 0.5)
        }
        if raw > maxScale {
            return maxScale + (raw - maxScale) * 0.25
        }
        return raw
    }

    // MARK: Loading

    private func loadImages() async {
        let asset: PHAsset = screenshot.asset
        if thumbnail == nil {
            thumbnail = DetailImageLoader.cachedThumbnail(for: asset)
        }
        if thumbnail == nil {
            let size: CGSize = ThumbnailLoader.pixelSize(points: GalleryMetrics.compactThumbnailPoints)
            ThumbnailLoader.shared.request(asset, size: size) { image in
                thumbnail = image
            }
        }
        // Full resolution only for the page on screen (keeps memory flat while paging).
        guard isActive, fullImage == nil else { return }
        let image: UIImage? = await DetailImageLoader.fullImage(for: asset)
        guard !Task.isCancelled, isActive else { return }
        if let image {
            Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
                fullImage = image
            }
        } else if thumbnail == nil {
            loadFailed = true
        }
    }
}

// MARK: - Error

private struct PhotoLoadErrorView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
            Text(Brand.Copy.Errors.imageFailed)
                .font(.dsHeadline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Button(Brand.Copy.Errors.tryAgain) {
                HapticManager.shared.lightTap()
                onRetry()
            }
            .buttonStyle(.brand(.primary, size: .compact))
        }
        .padding(Space.lg)
        .dsCard(radius: Radius.lg)
        .padding(Space.xl)
    }
}

// MARK: - Insight Drawer
/// Floating card pinned to the bottom. Collapsed it "peeks" (title + stacks); drag or tap to reveal
/// tags, text, quick actions and similar screenshots. Height changes are mask/offset only.

private struct InsightDrawer: View {
    let screenshot: Screenshot
    let isExpanded: Bool
    let progress: CGFloat
    let visibleHeight: CGFloat
    let expandedHeight: CGFloat
    let canJump: (String) -> Bool
    let onPeekHeight: (CGFloat) -> Void
    let onToggle: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat) -> Void
    let onEdit: () -> Void
    let onJump: (String) -> Void
    let onToast: (String, String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var record: AnalysisRecord?
    @State private var similar: [Screenshot] = []
    @State private var jumpable: Set<String> = []
    @State private var loadedID: String?
    @State private var isTextExpanded: Bool = false

    @State private var dragTracking: Bool = false
    @State private var lastDrag: CGSize = .zero
    @State private var lastVelocity: CGSize = .zero
    @GestureState private var dragActive: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    onPeekHeight(height)
                }

            details
        }
        .frame(height: expandedHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .mask(alignment: .top) {
            shape.frame(height: max(visibleHeight, 0))
        }
        .background(alignment: .top) {
            drawerBackground
        }
        .offset(y: expandedHeight - visibleHeight)
        .task(id: loadKey) {
            await load()
        }
    }

    private var drawerBackground: some View {
        ZStack {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.xl))
            shape
                .fill(Palette.surface.opacity(0.55 + 0.45 * Double(progress)))
            shape
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
        .frame(height: max(visibleHeight, 0))
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 8)
    }

    // MARK: Data

    private var displayCategories: [ScreenshotCategory] {
        screenshot.categories.filter { $0 != .all }
    }

    private var title: String {
        if let title = record?.title, !title.isEmpty { return title }
        if let title = screenshot.title, !title.isEmpty { return title }
        return Brand.Copy.Detail.fallbackTitle
    }

    private var subtitle: String {
        let date: String = DetailDates.dayTitle(screenshot.creationDate) + ", "
            + screenshot.creationDate.formatted(date: .omitted, time: .shortened)
        if let app = record?.app ?? screenshot.app, !app.isEmpty {
            return Brand.Copy.Detail.fromApp(app.capitalized) + " · " + date
        }
        if screenshot.tier == .none {
            return Brand.Copy.Detail.reading
        }
        return date
    }

    private var summaryText: String? {
        let raw: String? = record?.summary ?? screenshot.summary
        guard let raw else { return nil }
        let trimmed: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var tagModels: [ScreenshotTag] {
        if let record, !record.tags.isEmpty {
            return record.tags
        }
        return screenshot.tags.map { ScreenshotTag(value: $0, score: 1, sources: []) }
    }

    private var entities: [ExtractedEntity] {
        guard let record else { return [] }
        var seen: Set<String> = []
        var result: [ExtractedEntity] = []
        for entity in record.entities {
            let key: String = entity.type.rawValue + ":" + entity.value.lowercased()
            if seen.insert(key).inserted {
                result.append(entity)
            }
        }
        return Array(result.prefix(16))
    }

    private var ocrText: String {
        record?.ocrText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var loadKey: String {
        let tags: String = screenshot.tags.joined(separator: ",")
        let categories: String = screenshot.categories.map { $0.key }.joined(separator: ",")
        return screenshot.id + "|" + String(screenshot.tier.rawValue) + "|" + tags + "|" + categories
    }

    private func load() async {
        let id: String = screenshot.id
        if loadedID != id {
            record = nil
            similar = []
            jumpable = []
            isTextExpanded = false
            // Debounce while flicking through pages.
            try? await Task.sleep(for: .milliseconds(140))
            if Task.isCancelled { return }
        }
        let loadedRecord: AnalysisRecord? = await model.record(for: id)
        if Task.isCancelled { return }
        let neighbours: [Screenshot] = await model.similar(to: id)
        if Task.isCancelled { return }
        let filtered: [Screenshot] = neighbours.filter { $0.id != id }
        var allowed: Set<String> = []
        for item in filtered where canJump(item.id) {
            allowed.insert(item.id)
        }
        Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
            record = loadedRecord
            similar = filtered
            jumpable = allowed
            loadedID = id
        }
    }

    // MARK: Header (peek)

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Capsule(style: .continuous)
                .fill(Palette.inkSecondary.opacity(0.4))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.xs)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: Space.sm) {
                headerIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dsHeadline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.dsCaption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                Button {
                    onEdit()
                } label: {
                    Label(Brand.Copy.Detail.edit, systemImage: "pencil")
                }
                .buttonStyle(.brand(.secondary, size: .compact))
                .accessibilityLabel(Brand.Copy.Detail.editLabels)

                Button {
                    onToggle()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Palette.inkSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Palette.inkSecondary.opacity(0.12)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel(isExpanded ? Brand.Copy.Detail.collapse : Brand.Copy.Detail.expand)
                .accessibilityHint(Brand.Copy.Detail.insightsHint)
            }

            categoryRow
        }
        .padding(.horizontal, Space.md)
        .padding(.bottom, Space.sm)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .simultaneousGesture(dragGesture)
        .onChange(of: dragActive) { _, active in
            if !active {
                finishDrag(translation: lastDrag, velocity: lastVelocity)
            }
        }
    }

    private var headerIcon: some View {
        let first: ScreenshotCategory? = displayCategories.first
        return Image(systemName: first?.icon ?? "sparkles")
            .font(.callout.weight(.bold))
            .foregroundStyle(Palette.onBrand)
            .frame(width: 40, height: 40)
            .background {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(first?.gradient ?? Palette.brandGradient)
            }
            .rotationEffect(.degrees(-6))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var categoryRow: some View {
        let categories: [ScreenshotCategory] = displayCategories
        if categories.isEmpty {
            TagChip(
                screenshot.tier == .none ? Brand.Copy.Detail.reading : Brand.Copy.Detail.notSorted,
                tint: Palette.brand,
                isSuggested: true
            )
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: Space.xs) {
                    ForEach(categories, id: \.self) { category in
                        TagChip(category.displayName, systemImage: category.icon, tint: category.color)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($dragActive) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if !dragTracking {
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    dragTracking = true
                }
                lastDrag = value.translation
                lastVelocity = value.velocity
                onDragChanged(value.translation.height)
            }
            .onEnded { value in
                finishDrag(translation: value.translation, velocity: value.velocity)
            }
    }

    private func finishDrag(translation: CGSize, velocity: CGSize) {
        guard dragTracking else { return }
        dragTracking = false
        lastDrag = .zero
        lastVelocity = .zero
        onDragEnded(translation.height, velocity.height)
    }

    // MARK: Details (expanded)

    private var details: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Space.lg) {
                if let summaryText {
                    Text(summaryText)
                        .font(.dsBody)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                categoriesSection
                tagsSection
                entitiesSection
                textSection
                similarSection
            }
            .padding(.horizontal, Space.md)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(!isExpanded)
        .opacity(Double(min(1, progress * 1.4)))
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                LabelsSectionHeader(title: Brand.Copy.Detail.categories, systemImage: "square.stack.3d.up.fill", tint: Palette.brand)
                Spacer(minLength: 0)
                Button {
                    onEdit()
                } label: {
                    Label(Brand.Copy.Detail.edit, systemImage: "pencil")
                }
                .buttonStyle(.brand(.ghost, size: .compact))
                .accessibilityLabel(Brand.Copy.Detail.editLabels)
            }
            if displayCategories.isEmpty {
                Text(Brand.Copy.Detail.notSorted)
                    .font(.dsCallout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ChipFlowLayout(spacing: Space.xs, lineSpacing: Space.xs) {
                    ForEach(displayCategories, id: \.self) { category in
                        TagChip(category.displayName, systemImage: category.icon, tint: category.color)
                    }
                }
            }
        }
    }

    private var tagsSection: some View {
        let tags: [ScreenshotTag] = tagModels
        return VStack(alignment: .leading, spacing: Space.sm) {
            LabelsSectionHeader(title: Brand.Copy.Detail.tags, systemImage: "number", tint: Palette.info)
            if tags.isEmpty {
                Text(Brand.Copy.Detail.noTags)
                    .font(.dsCallout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ChipFlowLayout(spacing: Space.xs, lineSpacing: Space.xs) {
                    ForEach(tags, id: \.value) { tag in
                        TagChip(tag.value, systemImage: "number", tint: Palette.info, isSuggested: tag.isSuggested)
                            .opacity(tag.isSuggested ? 0.7 : 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var entitiesSection: some View {
        let items: [ExtractedEntity] = entities
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                LabelsSectionHeader(title: Brand.Copy.Detail.actions, systemImage: "bolt.fill", tint: Palette.warning)
                ChipFlowLayout(spacing: Space.xs, lineSpacing: Space.xs) {
                    ForEach(items, id: \.self) { entity in
                        EntityChip(entity: entity) {
                            perform(entity)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var textSection: some View {
        let text: String = ocrText
        if !text.isEmpty {
            let isLong: Bool = text.count > 240 || text.filter { $0 == "\n" }.count > 5
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    LabelsSectionHeader(title: Brand.Copy.Detail.text, systemImage: "text.viewfinder", tint: CategoryGroup.workProductivity.color)
                    Spacer(minLength: 0)
                    Button {
                        copyText(text)
                    } label: {
                        Label(Brand.Copy.Detail.copy, systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.brand(.ghost, size: .compact))
                    .accessibilityLabel(Brand.Copy.Detail.copyText)
                }

                Text(text)
                    .font(.dsBody)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .lineLimit(isTextExpanded ? nil : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.sm)
                    .dsSurface(radius: Radius.md)

                if isLong {
                    Button(isTextExpanded ? Brand.Copy.Detail.showLess : Brand.Copy.Detail.showMore) {
                        HapticManager.shared.lightTap()
                        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
                            isTextExpanded.toggle()
                        }
                    }
                    .buttonStyle(.brand(.ghost, size: .compact))
                }
            }
        }
    }

    @ViewBuilder
    private var similarSection: some View {
        if !similar.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                LabelsSectionHeader(title: Brand.Copy.Detail.similar, systemImage: "square.on.square", tint: Palette.brandSecondary)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Space.xs) {
                        ForEach(similar) { item in
                            SimilarThumb(screenshot: item, isEnabled: jumpable.contains(item.id)) {
                                onJump(item.id)
                            }
                        }
                    }
                    .padding(.vertical, Space.xxs)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    // MARK: Actions

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        HapticManager.shared.success()
        onToast(Brand.Copy.Detail.textCopied, "doc.on.doc.fill")
    }

    private func perform(_ entity: ExtractedEntity) {
        switch entity.type {
        case .url:
            if let url = EntityStyle.webURL(for: entity) {
                open(url)
            } else {
                copy(entity)
            }
        case .phone:
            let raw: String = entity.normalized ?? entity.value
            let digits: String = raw.filter { $0.isNumber || $0 == "+" }
            if !digits.isEmpty, let url = URL(string: "tel:" + digits) {
                open(url)
            } else {
                copy(entity)
            }
        case .email:
            let raw: String = (entity.normalized ?? entity.value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty, let url = URL(string: "mailto:" + raw) {
                open(url)
            } else {
                copy(entity)
            }
        case .address, .place:
            if let url = EntityStyle.mapsURL(for: entity.value) {
                open(url)
            } else {
                copy(entity)
            }
        default:
            copy(entity)
        }
    }

    private func open(_ url: URL) {
        HapticManager.shared.lightTap()
        openURL(url)
    }

    private func copy(_ entity: ExtractedEntity) {
        let value: String
        switch entity.type {
        case .oneTimeCode, .tracking:
            value = entity.normalized ?? entity.value
        default:
            value = entity.value
        }
        UIPasteboard.general.string = value
        HapticManager.shared.success()
        onToast(Brand.Copy.Detail.copied, "doc.on.doc.fill")
    }
}

// MARK: - Entity Chip

private struct EntityChip: View {
    let entity: ExtractedEntity
    let action: () -> Void

    var body: some View {
        let tint: Color = EntityStyle.tint(entity.type)
        let opens: Bool = EntityStyle.opensExternally(entity.type)
        Button(action: action) {
            HStack(spacing: Space.xxs + 2) {
                Image(systemName: EntityStyle.icon(entity.type))
                    .imageScale(.small)
                    .foregroundStyle(tint)
                Text(entity.value)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: opens ? "arrow.up.right" : "doc.on.doc")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(tint.opacity(0.3), lineWidth: 1)
                    }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(entity.value)
        .accessibilityHint(opens ? Brand.Copy.Detail.openHint : Brand.Copy.Detail.copyHint)
    }
}

private enum EntityStyle {
    static func icon(_ type: EntityType) -> String {
        switch type {
        case .date: return "calendar"
        case .url: return "link"
        case .phone: return "phone.fill"
        case .address: return "mappin.and.ellipse"
        case .email: return "envelope.fill"
        case .flight: return "airplane"
        case .price: return "dollarsign.circle.fill"
        case .tracking: return "shippingbox.fill"
        case .oneTimeCode: return "key.fill"
        case .person: return "person.fill"
        case .place: return "map.fill"
        case .organization: return "building.2.fill"
        }
    }

    static func tint(_ type: EntityType) -> Color {
        switch type {
        case .date, .flight: return CategoryGroup.eventsPlanning.color
        case .url, .email: return CategoryGroup.communication.color
        case .phone: return CategoryGroup.lifestyleWellness.color
        case .address, .place: return CategoryGroup.placesTravel.color
        case .price: return CategoryGroup.foodDrink.color
        case .tracking: return CategoryGroup.productsTech.color
        case .oneTimeCode, .organization: return CategoryGroup.workProductivity.color
        case .person: return CategoryGroup.socialMedia.color
        }
    }

    static func opensExternally(_ type: EntityType) -> Bool {
        switch type {
        case .url, .phone, .email, .address, .place:
            return true
        default:
            return false
        }
    }

    static func webURL(for entity: ExtractedEntity) -> URL? {
        let raw: String = (entity.normalized ?? entity.value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let lowered: String = raw.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return URL(string: raw)
        }
        return URL(string: "https://" + raw)
    }

    static func mapsURL(for query: String) -> URL? {
        var allowed: CharacterSet = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed), !encoded.isEmpty else {
            return nil
        }
        return URL(string: "http://maps.apple.com/?q=" + encoded)
    }
}

// MARK: - Similar Thumbnail

private struct SimilarThumb: View {
    let screenshot: Screenshot
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AsyncThumbnail(
                asset: screenshot.asset,
                pointSize: 90,
                placeholderTint: screenshot.categories.first?.color ?? Palette.brand
            )
            .frame(width: 66, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.pressableCard)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(screenshot.title ?? Brand.Copy.Detail.fallbackTitle)
        .accessibilityHint(isEnabled ? Brand.Copy.Detail.similarHint : "")
    }
}

// MARK: - Image Loading

@MainActor
enum DetailImageLoader {
    /// Any grid/search thumbnail already in memory, for an instant first frame.
    static func cachedThumbnail(for asset: PHAsset) -> UIImage? {
        let candidates: [CGFloat] = [
            GalleryMetrics.compactThumbnailPoints,
            GalleryMetrics.regularThumbnailPoints,
            90,
            120
        ]
        for points in candidates {
            if let image = ThumbnailLoader.shared.cached(asset, size: ThumbnailLoader.pixelSize(points: points)) {
                return image
            }
        }
        return nil
    }

    static func fullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            PhotoLibraryService.shared.loadFullSizeImage(for: asset) { image in
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - Sharing

struct ScreenshotSharePayload: Identifiable {
    let id: UUID = UUID()
    let items: [Any]
}

/// `UIActivityViewController` for sharing loaded images.
struct ScreenshotShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Loads original image data for sharing (no full-size decode kept in the thumbnail cache).
@MainActor
enum ScreenshotExporter {
    static func image(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options: PHImageRequestOptions = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                if let data, let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func images(for assets: [PHAsset]) async -> [UIImage] {
        var result: [UIImage] = []
        result.reserveCapacity(assets.count)
        for asset in assets {
            if let image = await image(for: asset) {
                result.append(image)
            }
        }
        return result
    }
}

// MARK: - Vertical pan

/// Single-finger pan that fails unless the drag starts mostly vertical, leaving horizontal swipes
/// to the enclosing scroll view. Runs alongside pinch and the scroll view's own pan.
struct VerticalPanGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    let onChanged: (CGSize, CGSize) -> Void
    let onEnded: (CGSize, CGSize) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        let velocity = recognizer.velocity(in: recognizer.view)
        let t = CGSize(width: translation.x, height: translation.y)
        let v = CGSize(width: velocity.x, height: velocity.y)
        switch recognizer.state {
        case .began, .changed:
            onChanged(t, v)
        case .ended, .cancelled, .failed:
            onEnded(t, v)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x) * 1.4
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
