import SwiftUI
import Photos
import UIKit

// MARK: - Screenshot Review View
/// Swipe deck: a real card stack (two cards peeking behind), velocity-aware flings,
/// KEEP / TOSS stamps that grow with drag progress, up-swipe to "Sort into…",
/// smooth undo (the card flies back in), and a confetti finish.

struct ScreenshotReviewView: View {
    @StateObject private var viewModel: ScreenshotReviewViewModel
    private let onSortInto: ((Screenshot, ScreenshotCategory) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Deck interaction
    @State private var drag: CGSize = .zero
    @State private var crossedEdge: DeckEdge?
    @State private var exiting: [ExitingCard] = []
    @State private var undoInsertion: UndoInsertion?
    @State private var deckSize: CGSize = CGSize(width: 390, height: 600)

    // Undo
    @State private var lastAction: ReviewAction?
    @State private var toast: ToastInfo?
    @State private var toastToken = UUID()
    @State private var showUndo = false
    @State private var undoTask: Task<Void, Never>?

    // Sort
    @State private var sortTarget: Screenshot?
    @State private var pendingSort: PendingSort?

    // Completion
    @State private var showCompletion = false
    @State private var completionTask: Task<Void, Never>?
    @State private var bytesToFree: Int64?
    @State private var isDeleting = false
    @State private var completionMessage: String?

    @FocusState private var isFocused: Bool

    private let visibleCardCount = 3

    init(
        viewModel: ScreenshotReviewViewModel,
        onSortInto: ((Screenshot, ScreenshotCategory) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSortInto = onSortInto
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            AmbientGlow(color: topTint, secondary: Palette.brand, intensity: 0.16)
                .id(viewModel.currentScreenshot?.id ?? "none")
                .transition(.opacity)

            content
        }
        .animation(Motion.animation(Motion.gentle, reduceMotion: reduceMotion), value: viewModel.isLoading)
        .animation(Motion.animation(Motion.gentle, reduceMotion: reduceMotion), value: viewModel.showResumePrompt)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sortTarget, onDismiss: handleSortSheetDismiss) { screenshot in
            SortIntoSheet(
                screenshot: screenshot,
                image: viewModel.getPreloadedImage(for: screenshot) ?? screenshot.thumbnail,
                onPick: { category in
                    pendingSort = PendingSort(screenshotID: screenshot.id, screenshot: screenshot, category: category)
                }
            )
        }
        .onAppear {
            if !viewModel.hasResumableSession && !viewModel.showResumePrompt {
                viewModel.startFresh()
            }
            showCompletion = viewModel.isCompleted
            isFocused = true
        }
        .onChange(of: viewModel.isCompleted) { _, completed in
            handleCompletionChange(completed)
        }
        .task(id: showCompletion) {
            guard showCompletion else { return }
            bytesToFree = nil
            let bytes: Int64 = await viewModel.bytesMarkedForDeletion()
            bytesToFree = bytes
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) {
            guard canInteractWithDeck else { return .ignored }
            commit(.toss)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard canInteractWithDeck else { return .ignored }
            commit(.keep)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard canInteractWithDeck, canSort else { return .ignored }
            openSort()
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "z")) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            performUndo()
            return .handled
        }
    }

    // MARK: - Content States

    @ViewBuilder
    private var content: some View {
        if viewModel.showResumePrompt {
            ResumePromptView(
                reviewed: viewModel.resumableReviewedCount,
                total: viewModel.totalCount,
                onResume: { viewModel.resumeSession() },
                onStartFresh: { viewModel.startFresh() },
                onClose: { dismiss() }
            )
            .transition(.opacity)
        } else if viewModel.totalCount == 0 {
            EmptyDeckView(onClose: { dismiss() })
                .transition(.opacity)
        } else if showCompletion {
            ReviewCompletionView(
                keptCount: viewModel.keptCount,
                tossedCount: viewModel.deletedCount,
                reviewedCount: viewModel.reviewedCount,
                bytesToFree: bytesToFree,
                isDeleting: isDeleting,
                message: completionMessage,
                onConfirm: confirmCompletion,
                onNotNow: { dismiss() },
                onGoBack: goBackAction
            )
            .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: reduceMotion ? 1 : 0.96)))
        } else if viewModel.isLoading {
            ReviewLoadingView()
                .transition(.opacity)
        } else {
            deckContent
                .transition(.opacity)
        }
    }

    private var goBackAction: (() -> Void)? {
        guard lastAction != nil else { return nil }
        return { performUndo() }
    }

    private var deckContent: some View {
        VStack(spacing: Space.md) {
            ReviewHeader(
                position: min(viewModel.currentIndex + 1, viewModel.totalCount),
                total: viewModel.totalCount,
                progress: viewModel.progressPercentage,
                onClose: closeReview
            )

            deck
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    deckSize = newSize
                }
                .overlay(alignment: .bottom) {
                    undoToastLayer
                }

            ReviewActionBar(
                canSort: canSort,
                canUndo: lastAction != nil,
                litEdge: crossedEdge,
                onToss: { commit(.toss) },
                onKeep: { commit(.keep) },
                onSort: { openSort() },
                onUndo: { performUndo() }
            )
            .padding(.bottom, Space.xs)
        }
    }

    // MARK: - Deck

    private var deck: some View {
        ZStack {
            ForEach(deckEntries) { entry in
                deckCard(entry)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.lg)
    }

    private var deckEntries: [DeckEntry] {
        let exitingIDs: Set<String> = Set(exiting.map { $0.screenshot.id })
        let stack: [Screenshot] = viewModel.upcomingScreenshots(count: visibleCardCount)
            .filter { !exitingIDs.contains($0.id) }

        var result: [DeckEntry] = []
        for (depth, screenshot) in stack.enumerated() {
            result.append(DeckEntry(screenshot: screenshot, depth: depth, exit: nil))
        }
        for card in exiting {
            result.append(DeckEntry(screenshot: card.screenshot, depth: 0, exit: card.pose))
        }
        return result
    }

    @ViewBuilder
    private func deckCard(_ entry: DeckEntry) -> some View {
        let isTop: Bool = entry.exit == nil && entry.depth == 0
        let size: CGSize = cardSize(for: entry.screenshot)
        let offset: CGSize = entry.exit?.offset ?? (isTop ? drag : .zero)
        let rotation: Double = entry.exit?.rotation ?? (isTop ? dragRotation : 0)

        DeckCard(
            screenshot: entry.screenshot,
            image: viewModel.getPreloadedImage(for: entry.screenshot) ?? entry.screenshot.thumbnail,
            size: size,
            isTop: isTop || entry.exit != nil,
            keepProgress: stampProgress(entry, isTop: isTop, kind: .keep),
            tossProgress: stampProgress(entry, isTop: isTop, kind: .toss),
            sortProgress: stampProgress(entry, isTop: isTop, kind: .sort)
        )
        .scaleEffect(stackScale(entry.depth))
        .offset(y: stackLift(entry.depth))
        .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: entry.depth)
        .rotationEffect(.degrees(rotation))
        .offset(offset)
        .opacity(entry.exit?.opacity ?? 1)
        .zIndex(zIndex(for: entry))
        .transition(transition(for: entry))
        .gesture(dragGesture, including: isTop ? .all : .subviews)
        .allowsHitTesting(isTop)
        .accessibilityHidden(!isTop)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: entry.screenshot))
        .accessibilityHint(Brand.Copy.Review.cardHint)
        .accessibilityAction(named: Text(Brand.Copy.Review.keep)) { commit(.keep) }
        .accessibilityAction(named: Text(Brand.Copy.Review.toss)) { commit(.toss) }
        .accessibilityAction(named: Text(Brand.Copy.Review.sortInto)) {
            if canSort { openSort() }
        }
    }

    private func cardSize(for screenshot: Screenshot) -> CGSize {
        let pixelWidth: CGFloat = CGFloat(max(screenshot.asset.pixelWidth, 1))
        let pixelHeight: CGFloat = CGFloat(max(screenshot.asset.pixelHeight, 1))
        let aspect: CGFloat = min(max(pixelWidth / pixelHeight, 0.4), 1.6)
        let availableWidth: CGFloat = max(deckSize.width - Space.gutter * 2, 120)
        let availableHeight: CGFloat = max(deckSize.height - Space.lg - Space.xs - 28, 160)
        let width: CGFloat = min(availableWidth, availableHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    private func stackScale(_ depth: Int) -> CGFloat {
        switch depth {
        case 0: return 1.0
        case 1: return 0.94
        default: return 0.88
        }
    }

    private func stackLift(_ depth: Int) -> CGFloat {
        CGFloat(min(depth, 2)) * 14
    }

    private func zIndex(for entry: DeckEntry) -> Double {
        if entry.exit != nil { return 100 }
        return Double(visibleCardCount - entry.depth)
    }

    private var dragRotation: Double {
        Double(drag.width / 18)
    }

    private func stampProgress(_ entry: DeckEntry, isTop: Bool, kind: ExitKind) -> Double {
        if let exit = entry.exit {
            return exit.kind == kind ? 1.0 : 0.0
        }
        guard isTop else { return 0 }
        switch kind {
        case .keep:
            return Double(drag.width / swipeThreshold)
        case .toss:
            return Double(-drag.width / swipeThreshold)
        case .sort:
            guard canSort, abs(drag.height) > abs(drag.width) else { return 0 }
            return Double(-drag.height / sortThreshold)
        }
    }

    private func transition(for entry: DeckEntry) -> AnyTransition {
        if let insertion = undoInsertion, insertion.id == entry.id, !reduceMotion {
            let active = DeckFlyModifier(offset: insertion.offset, rotation: insertion.rotation)
            let identity = DeckFlyModifier(offset: .zero, rotation: 0)
            return AnyTransition.asymmetric(
                insertion: AnyTransition.modifier(active: active, identity: identity),
                removal: AnyTransition.opacity
            )
        }
        let insertion: AnyTransition = reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.scale(scale: 0.85).combined(with: AnyTransition.opacity)
        return AnyTransition.asymmetric(insertion: insertion, removal: AnyTransition.opacity)
    }

    private var topTint: Color {
        guard let top = viewModel.currentScreenshot,
              let category = top.categoriesWithConfidence.first?.category ?? top.categories.first else {
            return Palette.brandSecondary
        }
        return category.color
    }

    // MARK: - Gesture

    private var swipeThreshold: CGFloat {
        max(100, deckSize.width * 0.28)
    }

    private var sortThreshold: CGFloat {
        max(110, deckSize.height * 0.2)
    }

    private var canSort: Bool {
        onSortInto != nil
    }

    private var canInteractWithDeck: Bool {
        !viewModel.showResumePrompt && !viewModel.isLoading && !showCompletion && viewModel.currentScreenshot != nil && sortTarget == nil
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if drag == .zero {
                    HapticManager.shared.prepareForSwipe()
                }
                drag = value.translation
                updateCrossedEdge(for: value.translation)
            }
            .onEnded { value in
                endDrag(value)
            }
    }

    private func edge(for translation: CGSize) -> DeckEdge? {
        if canSort && -translation.height > sortThreshold && abs(translation.height) > abs(translation.width) * 1.2 {
            return .sort
        }
        if translation.width > swipeThreshold {
            return .keep
        }
        if translation.width < -swipeThreshold {
            return .toss
        }
        return nil
    }

    /// Fires the threshold haptic exactly once per crossing (and a soft tick when backing out).
    private func updateCrossedEdge(for translation: CGSize) {
        let newEdge: DeckEdge? = edge(for: translation)
        guard newEdge != crossedEdge else { return }
        let previous: DeckEdge? = crossedEdge
        crossedEdge = newEdge
        if newEdge != nil {
            HapticManager.shared.swipeThresholdReached()
        } else if previous != nil {
            HapticManager.shared.swipeThresholdLeft()
        }
    }

    private func endDrag(_ value: DragGesture.Value) {
        let translation: CGSize = value.translation
        let predicted: CGSize = value.predictedEndTranslation
        let velocity: CGSize = value.velocity
        crossedEdge = nil

        // Up-swipe → sort sheet.
        let isVertical: Bool = abs(translation.height) > abs(translation.width)
        let flickedUp: Bool = -predicted.height > sortThreshold * 2 && -velocity.height > 600
        if canSort && isVertical && (-translation.height > sortThreshold || flickedUp) {
            snapBack(withHaptic: false)
            openSort()
            return
        }

        // Horizontal fling, velocity-aware.
        let pastThreshold: Bool = abs(translation.width) > swipeThreshold
        let flicked: Bool = abs(predicted.width) > swipeThreshold * 1.8 && abs(velocity.width) > 500
        if pastThreshold || flicked {
            let direction: CGFloat = abs(predicted.width) > abs(translation.width) ? predicted.width : translation.width
            commit(direction > 0 ? .keep : .toss, predicted: predicted)
        } else {
            snapBack(withHaptic: abs(translation.width) > 30 || abs(translation.height) > 30)
        }
    }

    private func snapBack(withHaptic: Bool) {
        if withHaptic {
            HapticManager.shared.cardReturn()
        }
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            drag = .zero
        }
    }

    // MARK: - Decisions

    private func commit(_ kind: ExitKind, predicted: CGSize = .zero, category: ScreenshotCategory? = nil) {
        guard let screenshot = viewModel.currentScreenshot else { return }
        let decision: ReviewDecision = kind == .toss ? .delete : .keep
        let pose: ExitPose = exitPose(for: kind, predicted: predicted)
        let token = UUID()

        switch kind {
        case .keep: HapticManager.shared.swipeKeep()
        case .toss: HapticManager.shared.swipeDelete()
        case .sort: HapticManager.shared.sortInto()
        }

        undoInsertion = nil
        Motion.perform(Motion.cardFling, reduceMotion: reduceMotion) {
            exiting.removeAll { $0.screenshot.id == screenshot.id }
            exiting.append(ExitingCard(token: token, screenshot: screenshot, pose: pose))
            drag = .zero
            crossedEdge = nil
            viewModel.makeDecision(decision)
            viewModel.nextScreenshot()
        }

        lastAction = ReviewAction(screenshot: screenshot, decision: decision)
        showToast(for: kind, category: category)

        // Remove the flown-away card once it's off screen (no animation → instant).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(480))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                exiting.removeAll { $0.token == token }
            }
        }
    }

    private func exitPose(for kind: ExitKind, predicted: CGSize) -> ExitPose {
        if reduceMotion {
            let nudge: CGSize
            switch kind {
            case .keep: nudge = CGSize(width: 40, height: 0)
            case .toss: nudge = CGSize(width: -40, height: 0)
            case .sort: nudge = CGSize(width: 0, height: -40)
            }
            return ExitPose(kind: kind, offset: nudge, rotation: 0, opacity: 0)
        }

        let width: CGFloat = max(deckSize.width, 320)
        let height: CGFloat = max(deckSize.height, 480)
        let verticalCarry: CGFloat = min(max(predicted.height * 0.35, -260), 260)

        switch kind {
        case .keep:
            return ExitPose(kind: kind, offset: CGSize(width: width * 1.3, height: drag.height + verticalCarry), rotation: 22, opacity: 1)
        case .toss:
            return ExitPose(kind: kind, offset: CGSize(width: -width * 1.3, height: drag.height + verticalCarry), rotation: -22, opacity: 1)
        case .sort:
            return ExitPose(kind: kind, offset: CGSize(width: drag.width * 0.3, height: -height * 1.3), rotation: 0, opacity: 1)
        }
    }

    // MARK: - Undo

    private func showToast(for kind: ExitKind, category: ScreenshotCategory?) {
        switch kind {
        case .keep:
            toast = ToastInfo(message: Brand.Copy.Review.kept, systemImage: "heart.fill", tint: Palette.keep)
        case .toss:
            toast = ToastInfo(message: Brand.Copy.Review.tossed, systemImage: "trash.fill", tint: Palette.toss)
        case .sort:
            let name: String = category?.rawValue ?? ""
            let message: String = name.isEmpty ? Brand.Copy.Review.sorted : "\(Brand.Copy.Review.sorted) · \(name)"
            toast = ToastInfo(message: message, systemImage: "tray.and.arrow.down.fill", tint: category?.color ?? Palette.brand)
        }
        toastToken = UUID()
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            showUndo = true
        }

        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
                showUndo = false
            }
        }
    }

    private func performUndo() {
        guard let action = lastAction, !isDeleting else { return }
        undoTask?.cancel()
        completionTask?.cancel()

        let id: String = action.screenshotId
        let isStillOnScreen: Bool = exiting.contains { $0.screenshot.id == id }
        if !isStillOnScreen {
            // Re-insert the card from the side it left, so it visibly flies back in.
            let width: CGFloat = max(deckSize.width, 320)
            let fromX: CGFloat = action.decision == .keep ? width * 1.1 : -width * 1.1
            undoInsertion = UndoInsertion(
                id: id,
                offset: CGSize(width: fromX, height: -40),
                rotation: action.decision == .keep ? 18 : -18
            )
        }

        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            exiting.removeAll { $0.screenshot.id == id }
            showUndo = false
            showCompletion = false
            completionMessage = nil
            drag = .zero
            viewModel.undoLastAction(action)
        }
        lastAction = nil
    }

    // MARK: - Sort

    private func openSort() {
        guard canSort, let screenshot = viewModel.currentScreenshot else { return }
        HapticManager.shared.lightTap()
        pendingSort = nil
        sortTarget = screenshot
    }

    private func handleSortSheetDismiss() {
        guard let pending = pendingSort else { return }
        pendingSort = nil
        onSortInto?(pending.screenshot, pending.category)
        // Filing it counts as a keep; fly the card up and out.
        if viewModel.currentScreenshot?.id == pending.screenshotID {
            commit(.sort, category: pending.category)
        }
    }

    // MARK: - Completion

    private func handleCompletionChange(_ completed: Bool) {
        completionTask?.cancel()
        guard completed else { return }
        completionTask = Task { @MainActor in
            // Let the last card finish flying before the finale.
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
                showUndo = false
                showCompletion = true
            }
        }
    }

    private func confirmCompletion() {
        guard !isDeleting else { return }
        isDeleting = true
        completionMessage = nil
        viewModel.confirmDeletions { success in
            isDeleting = false
            if success {
                dismiss()
            } else {
                completionMessage = Brand.Copy.Completion.deleteCancelled
            }
        }
    }

    private func closeReview() {
        undoTask?.cancel()
        viewModel.saveAndExit()
        dismiss()
    }

    // MARK: - Toast

    @ViewBuilder
    private var undoToastLayer: some View {
        if showUndo, let toast {
            UndoToastView(
                message: toast.message,
                systemImage: toast.systemImage,
                tint: toast.tint,
                onUndo: { performUndo() }
            )
            .id(toastToken)
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xs)
            .transition(
                reduceMotion
                    ? AnyTransition.opacity
                    : AnyTransition.move(edge: .bottom).combined(with: AnyTransition.opacity)
            )
            .zIndex(200)
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for screenshot: Screenshot) -> String {
        let categories: String = screenshot.categoriesWithConfidence.prefix(3)
            .map { "\($0.category.rawValue), \($0.confidence.rawValue.lowercased()) confidence" }
            .joined(separator: "; ")
        let position: Int = min(viewModel.currentIndex + 1, viewModel.totalCount)
        return Brand.Copy.Review.cardAccessibility(index: position, total: viewModel.totalCount, categories: categories)
    }
}

// MARK: - Deck Models

private enum DeckEdge: Equatable {
    case keep
    case toss
    case sort
}

private enum ExitKind: Equatable {
    case keep
    case toss
    case sort
}

private struct ExitPose: Equatable {
    let kind: ExitKind
    let offset: CGSize
    let rotation: Double
    let opacity: Double
}

private struct ExitingCard {
    let token: UUID
    let screenshot: Screenshot
    let pose: ExitPose
}

private struct DeckEntry: Identifiable {
    let screenshot: Screenshot
    let depth: Int
    let exit: ExitPose?

    var id: String { screenshot.id }
}

private struct UndoInsertion {
    let id: String
    let offset: CGSize
    let rotation: Double
}

private struct PendingSort {
    let screenshotID: String
    let screenshot: Screenshot
    let category: ScreenshotCategory
}

private struct ToastInfo {
    let message: String
    let systemImage: String
    let tint: Color
}

/// Offset + rotation used for the "fly back in" undo transition.
private struct DeckFlyModifier: ViewModifier {
    let offset: CGSize
    let rotation: Double

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .offset(offset)
    }
}

// MARK: - Deck Card

private struct DeckCard: View {
    let screenshot: Screenshot
    let image: UIImage?
    let size: CGSize
    let isTop: Bool
    let keepProgress: Double
    let tossProgress: Double
    let sortProgress: Double

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(Palette.surface)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                SkeletonView(width: size.width, height: size.height, cornerRadius: Radius.xl)
            }

            // Decision tint wash.
            shape.fill(Palette.keep.opacity(clamp(keepProgress) * 0.22))
            shape.fill(Palette.toss.opacity(clamp(tossProgress) * 0.22))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            SwipeStamp(kind: .keep, progress: keepProgress)
                .padding(Space.lg)
        }
        .overlay(alignment: .topTrailing) {
            SwipeStamp(kind: .toss, progress: tossProgress)
                .padding(Space.lg)
        }
        .overlay(alignment: .center) {
            SwipeStamp(kind: .sort, progress: sortProgress)
        }
        .overlay(alignment: .bottomLeading) {
            if isTop {
                categoryChips
                    .padding(Space.md)
                    .opacity(1 - clamp(max(keepProgress, tossProgress, sortProgress)))
            }
        }
        .shadow(color: Color.black.opacity(isTop ? 0.22 : 0.1), radius: isTop ? 24 : 12, x: 0, y: isTop ? 14 : 6)
    }

    private var categoryChips: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(screenshot.categoriesWithConfidence.prefix(2)), id: \.category) { item in
                TagChip(
                    item.category.rawValue,
                    systemImage: item.category.icon,
                    tint: item.category.color,
                    isSuggested: item.confidence != .high
                )
                .background(Capsule(style: .continuous).fill(Palette.surface))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - Header

private struct ReviewHeader: View {
    let position: Int
    let total: Int
    let progress: Double
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel(Brand.Copy.Review.close)
            .accessibilityHint(Brand.Copy.Review.closeHint)

            VStack(spacing: Space.xs) {
                Text(Brand.Copy.Review.progress(position, total))
                    .font(.dsHeadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(position)))
                    .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: position)
                DSProgressBar(progress: progress, height: 8)
                    .frame(maxWidth: 220)
            }
            .frame(maxWidth: .infinity)

            Menu {
                Button(action: onClose) {
                    Label(Brand.Copy.Review.saveAndExit, systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel(Brand.Copy.Review.more)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xs)
    }
}

// MARK: - Action Bar

private struct ReviewActionBar: View {
    let canSort: Bool
    let canUndo: Bool
    let litEdge: DeckEdge?
    let onToss: () -> Void
    let onKeep: () -> Void
    let onSort: () -> Void
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: Space.lg) {
            HStack(spacing: Space.lg) {
                roundButton(
                    systemImage: "arrow.uturn.backward",
                    label: Brand.Copy.Review.undo,
                    tint: Palette.inkSecondary,
                    diameter: 48,
                    isLit: false,
                    action: onUndo
                )
                .disabled(!canUndo)
                .opacity(canUndo ? 1 : 0.4)

                roundButton(
                    systemImage: "xmark",
                    label: Brand.Copy.Review.toss,
                    tint: Palette.toss,
                    diameter: 68,
                    isLit: litEdge == .toss,
                    action: onToss
                )

                roundButton(
                    systemImage: "heart.fill",
                    label: Brand.Copy.Review.keep,
                    tint: Palette.keep,
                    diameter: 68,
                    isLit: litEdge == .keep,
                    action: onKeep
                )

                if canSort {
                    roundButton(
                        systemImage: "tray.and.arrow.down.fill",
                        label: Brand.Copy.Review.sortInto,
                        tint: Palette.brand,
                        diameter: 48,
                        isLit: litEdge == .sort,
                        action: onSort
                    )
                } else {
                    Color.clear.frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                }
            }
        }
        .animation(Motion.animation(Motion.bouncy, reduceMotion: reduceMotion), value: litEdge)
    }

    private func roundButton(
        systemImage: String,
        label: String,
        tint: Color,
        diameter: CGFloat,
        isLit: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(diameter > 56 ? Font.title2.weight(.black) : Font.headline.weight(.bold))
                .foregroundStyle(isLit ? Palette.onBrand : tint)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle()
                        .fill(tint)
                        .opacity(isLit ? 1 : 0)
                }
                .glassEffect(.regular.tint(tint.opacity(isLit ? 0.5 : 0.12)).interactive(), in: .circle)
                .scaleEffect(isLit && !reduceMotion ? 1.12 : 1)
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(label)
    }
}

// MARK: - Loading

private struct ReviewLoadingView: View {
    var body: some View {
        VStack(spacing: Space.xl) {
            ZStack {
                SkeletonView(width: 170, height: 300, cornerRadius: Radius.xl)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -26, y: 10)
                SkeletonView(width: 170, height: 300, cornerRadius: Radius.xl)
                    .rotationEffect(.degrees(7))
                    .offset(x: 26, y: 10)
                SkeletonView(width: 180, height: 320, cornerRadius: Radius.xl)
                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
            }
            .accessibilityHidden(true)

            VStack(spacing: Space.xs) {
                Text(Brand.Copy.Review.loadingTitle)
                    .font(.dsTitle2)
                    .foregroundStyle(Palette.ink)
                Text(Brand.Copy.Review.loadingBody)
                    .font(.dsCallout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
        .padding(Space.gutter)
    }
}

// MARK: - Resume Prompt

private struct ResumePromptView: View {
    let reviewed: Int
    let total: Int
    let onResume: () -> Void
    let onStartFresh: () -> Void
    let onClose: () -> Void

    @State private var isSettled = false

    var body: some View {
        VStack(spacing: Space.lg) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel(Brand.Copy.Review.close)
            }

            Spacer(minLength: 0)

            BrandMark(size: 120, isSettled: isSettled)

            VStack(spacing: Space.sm) {
                Text(Brand.Copy.Review.resumeTitle)
                    .font(.dsTitle)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(Brand.Copy.Review.resumeBody(reviewed: reviewed, total: total))
                    .font(.dsBody)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                DSProgressBar(progress: total > 0 ? Double(reviewed) / Double(total) : 0, height: 10)
                    .frame(maxWidth: 240)
                    .padding(.top, Space.xs)
            }

            Spacer(minLength: 0)

            VStack(spacing: Space.sm) {
                Button(action: onResume) {
                    Label(Brand.Copy.Review.resume, systemImage: "play.fill")
                }
                .buttonStyle(.brand())

                Button(Brand.Copy.Review.startOver, action: onStartFresh)
                    .buttonStyle(.brand(.secondary))
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.md)
        .onAppear {
            isSettled = true
        }
    }
}

// MARK: - Empty

private struct EmptyDeckView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: Space.lg) {
            Spacer()
            BrandMark(size: 110)
            VStack(spacing: Space.xs) {
                Text(Brand.Copy.Empty.nothingToReviewTitle)
                    .font(.dsTitle)
                    .foregroundStyle(Palette.ink)
                Text(Brand.Copy.Empty.nothingToReviewBody)
                    .font(.dsBody)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .multilineTextAlignment(.center)
            Spacer()
            Button(Brand.Copy.Completion.done, action: onClose)
                .buttonStyle(.brand())
        }
        .padding(Space.gutter)
    }
}

// MARK: - Completion

private struct ReviewCompletionView: View {
    let keptCount: Int
    let tossedCount: Int
    let reviewedCount: Int
    let bytesToFree: Int64?
    let isDeleting: Bool
    let message: String?
    let onConfirm: () -> Void
    let onNotNow: () -> Void
    let onGoBack: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confettiTrigger = 0
    @State private var displayedKept = 0
    @State private var displayedTossed = 0
    @State private var isSettled = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Space.lg) {
                    BrandMark(size: 120, isSettled: isSettled)
                        .padding(.top, Space.xl)

                    VStack(spacing: Space.xs) {
                        Text(Brand.Copy.Completion.title)
                            .font(.dsDisplay)
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text(Brand.Copy.Completion.subtitle(reviewed: reviewedCount))
                            .font(.dsBody)
                            .foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: Space.sm) {
                        StatPill(value: displayedKept, label: Brand.Copy.Completion.keptLabel, systemImage: "heart.fill", tint: Palette.keep)
                        StatPill(value: displayedTossed, label: Brand.Copy.Completion.tossedLabel, systemImage: "trash.fill", tint: Palette.toss)
                    }

                    if tossedCount > 0 {
                        spaceCard
                    } else {
                        Text(Brand.Copy.Completion.nothingTossed)
                            .font(.dsCallout)
                            .foregroundStyle(Palette.inkSecondary)
                    }

                    if let message {
                        Label(message, systemImage: "info.circle.fill")
                            .font(.dsCallout)
                            .foregroundStyle(Palette.ink)
                            .padding(Space.sm)
                            .dsCard(tint: Palette.warning, radius: Radius.md)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                actions
            }

            ConfettiBurst(trigger: confettiTrigger)
                .ignoresSafeArea()
        }
        .task {
            isSettled = true
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            confettiTrigger += 1
            HapticManager.shared.celebrate()
            Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
                displayedKept = keptCount
                displayedTossed = tossedCount
            }
        }
        .onChange(of: keptCount) { _, newValue in
            displayedKept = newValue
        }
        .onChange(of: tossedCount) { _, newValue in
            displayedTossed = newValue
        }
    }

    private var spaceCard: some View {
        VStack(spacing: Space.xxs) {
            Text(Brand.Copy.Completion.spaceLabel)
                .font(.dsCaption)
                .foregroundStyle(Palette.inkSecondary)
            Text(formattedBytes)
                .font(.dsTitle)
                .monospacedDigit()
                .foregroundStyle(Palette.brandGradient)
                .contentTransition(.numericText())
                .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: formattedBytes)
            Text(Brand.Copy.Completion.deleteWarning)
                .font(.dsCaption)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.md)
        .dsSurface(radius: Radius.lg, tint: Palette.brand)
        .accessibilityElement(children: .combine)
    }

    private var formattedBytes: String {
        guard let bytesToFree else { return Brand.Copy.Completion.spaceCalculating }
        return ByteCountFormatter.string(fromByteCount: bytesToFree, countStyle: .file)
    }

    private var actions: some View {
        VStack(spacing: Space.xs) {
            Button(action: onConfirm) {
                HStack(spacing: Space.xs) {
                    if isDeleting {
                        ProgressView()
                            .tint(Palette.onBrand)
                    }
                    Text(tossedCount > 0 ? Brand.Copy.Completion.confirmDelete(tossedCount) : Brand.Copy.Completion.done)
                }
            }
            .buttonStyle(.brand(tossedCount > 0 ? .destructive : .primary))
            .disabled(isDeleting)

            HStack(spacing: Space.xs) {
                if let onGoBack {
                    Button(Brand.Copy.Completion.goBack, action: onGoBack)
                        .buttonStyle(.brand(.ghost))
                }
                if tossedCount > 0 {
                    Button(Brand.Copy.Completion.notNow, action: onNotNow)
                        .buttonStyle(.brand(.ghost))
                }
            }
            .disabled(isDeleting)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.xs)
        .background(Palette.canvas.opacity(0.94).ignoresSafeArea())
    }
}

// MARK: - Sort Into Sheet

private struct SortIntoSheet: View {
    let screenshot: Screenshot
    let image: UIImage?
    let onPick: (ScreenshotCategory) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: Space.sm)]

    private var suggestions: [ScreenshotCategory] {
        let picks: [ScreenshotCategory] = screenshot.categoriesWithConfidence
            .map { $0.category }
            .filter { $0 != .all && $0 != .other }
        return Array(picks.prefix(3))
    }

    private var groups: [CategoryGroup] {
        CategoryGroup.allCases
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header

                    if !suggestions.isEmpty {
                        section(title: Brand.Copy.Review.suggested, systemImage: "sparkles", tint: Palette.brand) {
                            LazyVGrid(columns: columns, spacing: Space.sm) {
                                ForEach(suggestions, id: \.self) { category in
                                    tile(category, suggested: true)
                                }
                            }
                        }
                    }

                    ForEach(groups, id: \.self) { group in
                        let members: [ScreenshotCategory] = categories(in: group)
                        if !members.isEmpty {
                            section(title: group.rawValue, systemImage: group.icon, tint: group.color) {
                                LazyVGrid(columns: columns, spacing: Space.sm) {
                                    ForEach(members, id: \.self) { category in
                                        tile(category, suggested: false)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xl)
            }
            .background(Palette.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Brand.Copy.Review.close)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            CollageThumbnailStack(images: [image], tint: Palette.brand, cardWidth: 44, maxCards: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(Brand.Copy.Review.sortInto)
                    .font(.dsTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(Brand.Copy.Review.sortIntoSubtitle)
                    .font(.dsCallout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Space.xs)
    }

    private func categories(in group: CategoryGroup) -> [ScreenshotCategory] {
        ScreenshotCategory.allCases.filter { $0 != .all && $0.group == group }
    }

    private func section<Content: View>(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.onBrand)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(tint))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.dsHeadline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
    }

    private func tile(_ category: ScreenshotCategory, suggested: Bool) -> some View {
        Button {
            HapticManager.shared.selectionChanged()
            onPick(category)
            dismiss()
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: category.icon)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Palette.onBrand)
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(category.gradient)
                    }
                Text(category.rawValue)
                    .font(.dsCallout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if suggested {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(category.color)
                }
            }
            .padding(Space.xs)
            .padding(.trailing, Space.xxs)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .dsSurface(radius: Radius.md, tint: category.color)
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(suggested ? "Suggested: \(category.rawValue)" : category.rawValue)
    }
}
