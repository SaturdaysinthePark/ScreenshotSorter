import SwiftUI

struct CollectionsView: View {
    @ObservedObject var viewModel: CollectionsViewModel
    @State private var showReviewMode = false
    @State private var showActionsMenu = false

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Empty state
                if viewModel.collections.isEmpty && !viewModel.isProcessing && !viewModel.isLoading && viewModel.allScreenshots.isEmpty {
                    EnhancedEmptyStateView()
                        .padding(.top, 100)
                } else {
                    // Review banner
                    if viewModel.showReviewBanner {
                        ReviewBannerView(
                            unreviewedCount: viewModel.unreviewedCount,
                            isProcessing: viewModel.isProcessing,
                            onReviewTapped: {
                                HapticManager.shared.lightTap()
                                showReviewMode = true
                            },
                            onDismiss: {
                                viewModel.dismissReviewBanner()
                            }
                        )
                    }

                    // Unprocessed banner
                    if viewModel.showUnprocessedBanner && !viewModel.isProcessing {
                        UnprocessedBannerView(
                            unprocessedCount: viewModel.unprocessedPhotoCount,
                            onProcessTapped: {
                                HapticManager.shared.lightTap()
                                viewModel.processUnprocessedOnly()
                            },
                            onDismiss: {
                                viewModel.dismissUnprocessedBanner()
                            }
                        )
                    }

                    // Processing indicator with progress bar
                    if viewModel.isProcessing {
                        EnhancedProcessingIndicatorView(
                            progress: viewModel.processingProgress,
                            totalProcessed: viewModel.totalProcessed,
                            totalToProcess: viewModel.totalToProcess,
                            isPaused: viewModel.isPaused,
                            onPauseToggle: {
                                HapticManager.shared.lightTap()
                                viewModel.togglePause()
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, viewModel.allScreenshots.isEmpty ? 100 : 0)
                    }

                    // All Screenshots card
                    if !viewModel.allScreenshots.isEmpty {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Collections")
                                    .font(.title2.bold())
                                Spacer()
                            }
                            .padding(.horizontal, 16)

                            NavigationLink(destination: CleanGalleryView(collection: viewModel.allScreenshotsCollection).id(ScreenshotCategory.all)) {
                                AllScreenshotsCard(
                                    screenshots: viewModel.allScreenshots,
                                    totalCount: totalScreenshotCount
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 16)
                        }
                    }

                    // Collections - grouped or flat
                    if !viewModel.collections.isEmpty {
                        if viewModel.isGroupedView {
                            GroupedCollectionsView(
                                collections: viewModel.sortedCollections,
                                columns: columns
                            )
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(viewModel.sortedCollections) { collection in
                                    NavigationLink(destination: CleanGalleryView(collection: collection).id(collection.category)) {
                                        CollectionCard(collection: collection)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Sort/filter menu
                    Menu {
                        Picker("Sort By", selection: $viewModel.sortOption) {
                            ForEach(CollectionsSortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }

                        Divider()

                        Toggle(isOn: $viewModel.isGroupedView) {
                            Label("Group by Category", systemImage: "square.grid.2x2")
                        }

                        Toggle(isOn: $viewModel.showEmptyCategories) {
                            Label("Show Empty Categories", systemImage: "eye")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(SemanticColor.primary.gradient)
                    }
                    .accessibilityLabel("Sort and filter options")

                    // Review button
                    if viewModel.unreviewedCount > 0 {
                        Button(action: {
                            HapticManager.shared.lightTap()
                            showReviewMode = true
                        }) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(SemanticColor.primary.gradient)
                        }
                        .accessibilityLabel("Review \(viewModel.unreviewedCount) screenshots")
                        .accessibilityHint("Double-tap to start reviewing unreviewed screenshots")
                    }

                    // Actions menu (replaces ambiguous refresh button)
                    Menu {
                        Button(action: {
                            HapticManager.shared.lightTap()
                            viewModel.processUnprocessedOnly()
                        }) {
                            Label("Process New Screenshots", systemImage: "wand.and.stars")
                        }

                        Button(role: .destructive, action: {
                            showActionsMenu = true
                        }) {
                            Label("Re-analyze All", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(SemanticColor.primary.gradient)
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        // Consolidated confirmation dialog (replaces separate re-analyze alert)
        .confirmationDialog(
            "Re-analyze All Screenshots?",
            isPresented: $showActionsMenu,
            titleVisibility: .visible
        ) {
            if viewModel.unprocessedPhotoCount > 0 {
                Button("Process Unprocessed Only (\(viewModel.unprocessedPhotoCount))") {
                    viewModel.processUnprocessedOnly()
                }

                Button("Re-analyze All (\(viewModel.allScreenshots.count))", role: .destructive) {
                    viewModel.reanalyzeAll()
                }
            } else {
                Button("Re-analyze All \(viewModel.allScreenshots.count) Screenshots", role: .destructive) {
                    viewModel.refreshCollections()
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            if viewModel.isProcessing {
                Text("Analysis is currently in progress. Re-analyzing will restart from the beginning.")
            } else if viewModel.unprocessedPhotoCount > 0 {
                Text("You have \(viewModel.unprocessedPhotoCount) unprocessed screenshots. Choose an action below.")
            } else {
                Text("This will re-analyze all screenshots and may take several minutes.")
            }
        }
        .alert("New Screenshots Detected", isPresented: $viewModel.hasNewScreenshots) {
            Button("Process Now") {
                HapticManager.shared.lightTap()
                viewModel.processNewScreenshots()
            }
            Button("Later", role: .cancel) {
                viewModel.loadExistingPhotosWithoutProcessing()
            }
        } message: {
            Text("Found \(viewModel.newScreenshotCount) new screenshot\(viewModel.newScreenshotCount == 1 ? "" : "s"). Would you like to process them now?")
        }
        .alert("Unprocessed Screenshots", isPresented: $viewModel.hasUnprocessedPhotos) {
            Button("Process Now") {
                HapticManager.shared.lightTap()
                viewModel.processUnprocessedOnly()
            }
            Button("Later", role: .cancel) {
                viewModel.processLaterPhotos()
            }
        } message: {
            Text("You have \(viewModel.unprocessedPhotoCount) unprocessed screenshot\(viewModel.unprocessedPhotoCount == 1 ? "" : "s"). Would you like to process them now?")
        }
        .fullScreenCover(isPresented: $showReviewMode, onDismiss: {
            viewModel.updateReviewState()
        }) {
            ScreenshotReviewView(
                viewModel: ScreenshotReviewViewModel(
                    screenshots: viewModel.unreviewedScreenshots
                )
            )
        }
    }

    private var totalScreenshotCount: Int {
        viewModel.allScreenshots.count
    }
}

// MARK: - Collection Card

struct CollectionCard: View {
    let collection: ScreenshotCollection

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(SemanticColor.primary.lightBackground)
                    .frame(width: 60, height: 60)

                Image(systemName: collection.category.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(SemanticColor.primary.gradient)
            }

            // Category info
            VStack(spacing: 4) {
                Text(collection.category.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("\(collection.count) screenshot\(collection.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .primaryCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collection.category.rawValue), \(collection.count) screenshots")
        .accessibilityHint("Double-tap to view collection")
    }
}

// MARK: - Grouped Collections View

struct GroupedCollectionsView: View {
    let collections: [ScreenshotCollection]
    let columns: [GridItem]

    var groupedCollections: [(group: CategoryGroup, collections: [ScreenshotCollection])] {
        let grouped = Dictionary(grouping: collections) { $0.category.group }
        return grouped
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (group: $0.key, collections: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(groupedCollections, id: \.group) { item in
                VStack(alignment: .leading, spacing: 12) {
                    // Section header
                    HStack {
                        Image(systemName: item.group.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(item.group.rawValue)
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundStyle(SemanticColor.primary.gradient)
                    .padding(.horizontal, 16)

                    // Grid
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(item.collections) { collection in
                            NavigationLink(destination: CleanGalleryView(collection: collection).id(collection.category)) {
                                CollectionCard(collection: collection)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical)
    }
}

// MARK: - All Screenshots Card

struct AllScreenshotsCard: View {
    let screenshots: [Screenshot]
    let totalCount: Int

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(SemanticColor.primary.lightBackground)
                    .frame(width: 60, height: 60)

                Image(systemName: "photo.stack")
                    .font(.system(size: 28))
                    .foregroundStyle(SemanticColor.primary.gradient)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text("All Screenshots")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)

                Text("\(totalCount) screenshot\(totalCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .primaryCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All screenshots, \(totalCount) total")
        .accessibilityHint("Double-tap to view all screenshots")
    }
}

// MARK: - Enhanced Processing Indicator

struct EnhancedProcessingIndicatorView: View {
    let progress: String
    let totalProcessed: Int
    let totalToProcess: Int
    let isPaused: Bool
    let onPauseToggle: () -> Void

    @State private var animatingDots = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var percentComplete: Double {
        guard totalToProcess > 0 else { return 0 }
        return Double(totalProcessed) / Double(totalToProcess)
    }

    private var percentText: String {
        "\(Int(percentComplete * 100))%"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if !isPaused {
                    // Animated processing indicator
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 20))
                        .foregroundStyle(SemanticColor.primary.gradient)
                        .symbolEffect(.variableColor, options: .repeating, value: animatingDots)
                } else {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SemanticColor.warning.gradient)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(isPaused ? "Paused" : "Processing Screenshots")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer()

                        Text(percentText)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SemanticColor.primary.gradient)
                    }

                    Text("\(totalProcessed) of \(totalToProcess)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Pause/Resume button with distinct colors
                Button(action: onPauseToggle) {
                    HStack(spacing: 6) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(isPaused ? "Resume" : "Pause")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.glass)
                .tint(isPaused ? .green : .orange)
                .fixedSize()
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    Capsule()
                        .fill(isPaused ? SemanticColor.warning.gradient : SemanticColor.primary.gradient)
                        .frame(width: geometry.size.width * percentComplete, height: 6)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: percentComplete)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .secondaryCard()
        .onAppear {
            if !reduceMotion {
                animatingDots = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPaused ? "Processing paused at \(totalProcessed) of \(totalToProcess)" : "Processing \(totalProcessed) of \(totalToProcess) screenshots, \(percentText) complete")
        .accessibilityHint("Double-tap to \(isPaused ? "resume" : "pause") processing")
    }
}

// MARK: - Enhanced Empty State

struct EnhancedEmptyStateView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            // Animated icon
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 70))
                .foregroundStyle(SemanticColor.primary.gradient)
                .symbolEffect(.bounce, options: .repeating.speed(0.3), value: isAnimating)

            VStack(spacing: 8) {
                Text("No Screenshots Found")
                    .font(.title2.bold())

                Text("Take some screenshots and they'll appear here organized into smart collections.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Open Photos button
            Button(action: {
                HapticManager.shared.lightTap()
                openPhotosApp()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Open Photos")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(SemanticColor.primary.gradient)
                .cornerRadius(12)
            }
            .accessibilityLabel("Open Photos app")
            .accessibilityHint("Opens the Photos app where you can take screenshots")
        }
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }

    private func openPhotosApp() {
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Legacy Empty State (kept for backward compatibility)

struct EmptyStateView: View {
    var body: some View {
        EnhancedEmptyStateView()
    }
}

// MARK: - Legacy Processing Indicator

struct ProcessingIndicatorView: View {
    let progress: String
    let isPaused: Bool
    let onPauseToggle: () -> Void

    var body: some View {
        EnhancedProcessingIndicatorView(
            progress: progress,
            totalProcessed: 0,
            totalToProcess: 0,
            isPaused: isPaused,
            onPauseToggle: onPauseToggle
        )
    }
}
