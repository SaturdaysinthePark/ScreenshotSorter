import SwiftUI

// MARK: - Screenshot Review View

struct ScreenshotReviewView: View {
    @StateObject private var viewModel: ScreenshotReviewViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGSize = .zero
    @State private var showUndo = false
    @State private var lastAction: ReviewAction?
    @State private var showCompletionSheet = false
    @State private var undoTimer: DispatchWorkItem?
    @State private var showSwipeHints = true
    @State private var swipeHintOpacity: Double = 1.0
    @State private var hasShownInitialHint = false
    @FocusState private var isFocused: Bool

    init(viewModel: ScreenshotReviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Resume prompt
            if viewModel.showResumePrompt {
                ResumeSessionPrompt(
                    onResume: { viewModel.resumeSession() },
                    onStartFresh: { viewModel.startFresh() }
                )
            }
            // Loading state
            else if viewModel.isLoading {
                LoadingOverlay(
                    progress: viewModel.loadingProgress,
                    total: min(3, viewModel.totalCount)
                )
            }
            // Main review content
            else {
                reviewContent
            }

            // Undo Toast
            if showUndo, let action = lastAction {
                VStack {
                    Spacer()
                    UndoToastView(
                        message: "Screenshot \(action.decision == .delete ? "deleted" : "kept")",
                        onUndo: handleUndo
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: showUndo)
            }
        }
        .navigationBarHidden(true)
        .onChange(of: viewModel.isCompleted) { _, newValue in
            if newValue {
                showCompletionSheet = true
            }
        }
        .sheet(isPresented: $showCompletionSheet) {
            CompletionView(
                deletedCount: viewModel.getMarkedForDeletion().count,
                keptCount: viewModel.getMarkedToKeep().count,
                totalCount: viewModel.screenshots.count,
                onConfirm: {
                    viewModel.confirmDeletions { success in
                        if success {
                            showCompletionSheet = false
                            dismiss()
                        }
                    }
                },
                onCancel: {
                    showCompletionSheet = false
                    dismiss()
                }
            )
        }
        .onAppear {
            // Start fresh if no resumable session
            if !viewModel.hasResumableSession {
                viewModel.startFresh()
            }

            // Show initial swipe hint after a delay
            if !hasShownInitialHint {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showInitialHintAnimation()
                    hasShownInitialHint = true
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(.leftArrow) {
            handleKeyboardDelete()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            handleKeyboardKeep()
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "z"), modifiers: .command) { _ in
            handleUndo()
            return .handled
        }
    }

    // MARK: - Review Content

    private var reviewContent: some View {
        ZStack {
            // Side edge swipe indicators
            SwipeEdgeIndicators(
                offset: offset,
                showHints: showSwipeHints,
                hintOpacity: swipeHintOpacity
            )

            // Main Card
            if let currentScreenshot = viewModel.currentScreenshot {
                ScreenshotReviewCard(
                    screenshot: currentScreenshot,
                    preloadedImage: viewModel.getPreloadedImage(for: currentScreenshot)
                )
                .offset(offset)
                .rotationEffect(.degrees(Double(offset.width / 20)))
                .gesture(dragGesture)
                .overlay {
                    SwipeActionOverlay(offset: offset)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: currentScreenshot))
                .accessibilityHint("Swipe left to delete, swipe right to keep")
                .accessibilityAddTraits(.allowsDirectInteraction)
            }

            // Top bar with progress
            VStack {
                ReviewTopBar(
                    currentIndex: viewModel.currentIndex,
                    totalCount: viewModel.totalCount,
                    onClose: {
                        viewModel.saveAndExit()
                        dismiss()
                    },
                    onSaveExit: {
                        viewModel.saveAndExit()
                        dismiss()
                    }
                )
                Spacer()
            }

            // Swipe hints at top
            if showSwipeHints {
                VStack {
                    SwipeHintBar(opacity: swipeHintOpacity)
                        .padding(.top, 60)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Gestures

    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation

                // Hide hints when user starts swiping
                if abs(value.translation.width) > 20 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        swipeHintOpacity = 0
                    }
                }

                // Haptic when crossing threshold
                if abs(value.translation.width) > 150 && abs(value.translation.width) < 155 {
                    HapticManager.shared.swipeThresholdReached()
                }
            }
            .onEnded { value in
                handleSwipeEnd(value)
            }
    }

    func handleSwipeEnd(_ value: DragGesture.Value) {
        let threshold: CGFloat = 150

        if abs(value.translation.width) > threshold {
            let decision: ReviewDecision = value.translation.width > 0 ? .keep : .delete

            // Haptic feedback based on action
            if decision == .delete {
                HapticManager.shared.swipeDelete()
            } else {
                HapticManager.shared.swipeKeep()
            }

            // Record action
            lastAction = ReviewAction(
                screenshot: viewModel.currentScreenshot!,
                decision: decision
            )

            // Cancel any existing undo timer
            undoTimer?.cancel()

            // Animate off screen
            withAnimation(.easeOut(duration: 0.3)) {
                offset = CGSize(
                    width: value.translation.width > 0 ? 1000 : -1000,
                    height: 0
                )
            }

            // Process decision
            viewModel.makeDecision(decision)

            // Show undo toast immediately and start 5-second timer
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) {
                showUndo = true
            }

            let timer = DispatchWorkItem {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                    showUndo = false
                }
            }
            undoTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timer)

            // Reset after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                offset = .zero
                viewModel.nextScreenshot()

                // Restore hint opacity
                withAnimation(.easeIn(duration: 0.3)) {
                    swipeHintOpacity = 1.0
                }
            }
        } else {
            // Return to center
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                offset = .zero
            }

            // Restore hint opacity
            withAnimation(.easeIn(duration: 0.3)) {
                swipeHintOpacity = 1.0
            }
        }
    }

    // MARK: - Keyboard Navigation

    func handleKeyboardDelete() {
        guard viewModel.currentScreenshot != nil else { return }
        simulateSwipe(direction: .delete)
    }

    func handleKeyboardKeep() {
        guard viewModel.currentScreenshot != nil else { return }
        simulateSwipe(direction: .keep)
    }

    private func simulateSwipe(direction: ReviewDecision) {
        let targetOffset: CGFloat = direction == .delete ? -200 : 200

        withAnimation(.easeOut(duration: 0.2)) {
            offset = CGSize(width: targetOffset, height: 0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            handleSwipeCompletion(decision: direction)
        }
    }

    private func handleSwipeCompletion(decision: ReviewDecision) {
        if decision == .delete {
            HapticManager.shared.swipeDelete()
        } else {
            HapticManager.shared.swipeKeep()
        }

        lastAction = ReviewAction(
            screenshot: viewModel.currentScreenshot!,
            decision: decision
        )

        undoTimer?.cancel()

        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: decision == .delete ? -1000 : 1000, height: 0)
        }

        viewModel.makeDecision(decision)

        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) {
            showUndo = true
        }

        let timer = DispatchWorkItem {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                showUndo = false
            }
        }
        undoTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timer)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            offset = .zero
            viewModel.nextScreenshot()
        }
    }

    // MARK: - Undo

    func handleUndo() {
        guard let action = lastAction else { return }

        undoTimer?.cancel()

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            showUndo = false
        }

        offset = .zero
        viewModel.undoLastAction(action)
    }

    // MARK: - Hint Animation

    private func showInitialHintAnimation() {
        guard !reduceMotion else { return }

        withAnimation(.easeInOut(duration: 0.8).repeatCount(2, autoreverses: true)) {
            swipeHintOpacity = 0.5
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.3)) {
                swipeHintOpacity = 1.0
            }
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for screenshot: Screenshot) -> String {
        let categories = screenshot.categoriesWithConfidence.prefix(3)
            .map { "\($0.category.rawValue), \($0.confidence.rawValue) confidence" }
            .joined(separator: "; ")

        return "Screenshot \(viewModel.currentIndex + 1) of \(viewModel.totalCount). Categories: \(categories)"
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let progress: Int
    let total: Int

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: CGFloat(progress) / CGFloat(total))
                    .stroke(
                        SemanticColor.primary.gradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "photo.stack")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse, options: .repeating, value: isAnimating)
            }

            VStack(spacing: 8) {
                Text("Preparing Review")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)

                Text("\(progress) of \(total) loaded")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}

// MARK: - Resume Session Prompt

struct ResumeSessionPrompt: View {
    let onResume: () -> Void
    let onStartFresh: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 50))
                .foregroundStyle(SemanticColor.primary.gradient)

            VStack(spacing: 8) {
                Text("Resume Previous Session?")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)

                Text("You have an unfinished review session")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }

            VStack(spacing: 12) {
                Button(action: onResume) {
                    Text("Resume")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(SemanticColor.primary.gradient)
                        .cornerRadius(12)
                }

                Button(action: onStartFresh) {
                    Text("Start Fresh")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Swipe Edge Indicators

struct SwipeEdgeIndicators: View {
    let offset: CGSize
    let showHints: Bool
    let hintOpacity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var leftIndicatorOpacity: Double {
        if offset.width < 0 {
            return min(abs(offset.width) / 150, 1.0)
        }
        return showHints ? hintOpacity * 0.3 : 0
    }

    private var rightIndicatorOpacity: Double {
        if offset.width > 0 {
            return min(offset.width / 150, 1.0)
        }
        return showHints ? hintOpacity * 0.3 : 0
    }

    var body: some View {
        HStack {
            // Left edge (delete)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.red.opacity(leftIndicatorOpacity), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 60)
                .overlay(alignment: .center) {
                    if leftIndicatorOpacity > 0.3 {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(leftIndicatorOpacity))
                    }
                }

            Spacer()

            // Right edge (keep)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .green.opacity(rightIndicatorOpacity)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 60)
                .overlay(alignment: .center) {
                    if rightIndicatorOpacity > 0.3 {
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white.opacity(rightIndicatorOpacity))
                    }
                }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: offset.width)
    }
}

// MARK: - Swipe Action Overlay

struct SwipeActionOverlay: View {
    let offset: CGSize

    var body: some View {
        ZStack {
            if offset.width < -50 {
                Color.red.opacity(Double(abs(offset.width) / 300))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                            .opacity(min(abs(offset.width) / 150, 1.0))
                    }
            } else if offset.width > 50 {
                Color.green.opacity(Double(offset.width / 300))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(min(offset.width / 150, 1.0))
                    }
            }
        }
    }
}

// MARK: - Swipe Hint Bar

struct SwipeHintBar: View {
    let opacity: Double

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .semibold))
                Text("Delete")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.red)

            Spacer()

            HStack(spacing: 6) {
                Text("Keep")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.green)
        }
        .padding(.horizontal, 24)
        .opacity(opacity)
    }
}

// MARK: - Review Top Bar

struct ReviewTopBar: View {
    let currentIndex: Int
    let totalCount: Int
    let onClose: () -> Void
    let onSaveExit: () -> Void

    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Close review")
            .accessibilityHint("Saves progress and closes review mode")

            Spacer()

            // Progress indicator
            VStack(spacing: 2) {
                Text("\(currentIndex + 1) of \(totalCount)")
                    .font(.headline)
                    .foregroundColor(.white)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 4)

                        Capsule()
                            .fill(SemanticColor.primary.gradient)
                            .frame(width: geometry.size.width * CGFloat(currentIndex + 1) / CGFloat(totalCount), height: 4)
                    }
                }
                .frame(width: 100, height: 4)
            }

            Spacer()

            Menu {
                Button(action: onSaveExit) {
                    Label("Save & Exit", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .accessibilityLabel("More options")
        }
        .padding()
    }
}

// MARK: - Screenshot Review Card

struct ScreenshotReviewCard: View {
    let screenshot: Screenshot
    let preloadedImage: UIImage?

    @State private var fullImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Image with category badges overlay
            ZStack(alignment: .topLeading) {
                // Image
                if let image = fullImage ?? preloadedImage ?? screenshot.thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.7)
                } else {
                    // Loading skeleton
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.7)
                        .overlay {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text("Loading image...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                }

                // Confidence badges overlay (top-left)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(screenshot.categoriesWithConfidence.prefix(3), id: \.category) { cat in
                        EnhancedCategoryBadge(category: cat.category, confidence: cat.confidence)
                    }
                }
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 20)
        .padding(40)
        .onAppear {
            loadFullImage()
        }
    }

    private func loadFullImage() {
        // If we have a preloaded image, use it
        if let preloaded = preloadedImage {
            fullImage = preloaded
            isLoading = false
            return
        }

        // If we already have a thumbnail, use it immediately
        if screenshot.thumbnail != nil {
            isLoading = false
        }

        // Load full resolution in background
        PhotoLibraryService.shared.loadFullSizeImage(for: screenshot.asset) { image in
            fullImage = image
            isLoading = false
        }
    }
}

// MARK: - Enhanced Category Badge

struct EnhancedCategoryBadge: View {
    let category: ScreenshotCategory
    let confidence: ConfidenceLevel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(.caption2)

            Text(category.rawValue)
                .font(.caption2.weight(.medium))

            // Confidence dots
            HStack(spacing: 2) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index < confidenceDotCount ? badgeColor : Color.white.opacity(0.3))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundColor(.white)
        .glassEffect(.regular.tint(badgeColor.opacity(0.4)), in: .capsule)
    }

    private var confidenceDotCount: Int {
        switch confidence {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }

    private var badgeColor: Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .gray
        }
    }
}

// MARK: - Completion View

struct CompletionView: View {
    let deletedCount: Int
    let keptCount: Int
    let totalCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(SemanticColor.success.gradient)
                .symbolEffect(.bounce, value: isAnimating)

            VStack(spacing: 8) {
                Text("Review Complete!")
                    .font(.title.weight(.bold))

                Text("You reviewed \(totalCount) screenshot\(totalCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Summary stats
            HStack(spacing: 24) {
                StatBadge(
                    icon: "checkmark",
                    count: keptCount,
                    label: "Kept",
                    color: .green
                )

                StatBadge(
                    icon: "trash.fill",
                    count: deletedCount,
                    label: "Deleted",
                    color: .red
                )
            }

            if deletedCount > 0 {
                VStack(spacing: 8) {
                    Text("\(deletedCount) screenshot\(deletedCount == 1 ? "" : "s") will be deleted")
                        .font(.subheadline.weight(.medium))

                    Text("This action cannot be undone")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .tintedGlass(color: .red, cornerRadius: 12)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button(action: onConfirm) {
                    Text(deletedCount > 0 ? "Delete \(deletedCount) Screenshot\(deletedCount == 1 ? "" : "s")" : "Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(deletedCount > 0 ? .red : .blue)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(24)
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.title2.weight(.bold))

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

