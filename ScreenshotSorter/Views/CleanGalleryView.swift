import SwiftUI
import Photos
import UIKit

struct CleanGalleryView: View {
    let collection: ScreenshotCollection
    let allCollections: [ScreenshotCollection]?
    @Binding var navigationPath: NavigationPath
    @StateObject private var viewModel: CollectionDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScreenshot: Screenshot?
    @State private var showingSortOptions = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false
    @State private var showingCollections = false

    init(collection: ScreenshotCollection, allCollections: [ScreenshotCollection]? = nil, navigationPath: Binding<NavigationPath>) {
        self.collection = collection
        self.allCollections = allCollections
        self._navigationPath = navigationPath
        self._viewModel = StateObject(wrappedValue: CollectionDetailViewModel(collection: collection))
    }

    // 3-column grid with minimal spacing (iOS Photos pattern)
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var availableSortOptions: [SortOption] {
        if collection.category == .all {
            return [.dateDescending, .dateAscending]
        } else {
            return SortOption.allCases
        }
    }

    var body: some View {
        ZStack {
            // Gallery content
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(viewModel.sortedScreenshots) { screenshot in
                        ThumbnailCell(
                            screenshot: screenshot,
                            thumbnail: viewModel.thumbnails[screenshot.id],
                            isSelected: viewModel.selectedScreenshots.contains(screenshot),
                            isSelectionMode: viewModel.isSelectionMode,
                            onTap: {
                                if viewModel.isSelectionMode {
                                    HapticManager.shared.lightTap()
                                    viewModel.toggleSelection(for: screenshot)
                                } else {
                                    selectedScreenshot = screenshot
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 60) // Space for floating chrome
            }
            .background(Color(.systemBackground))

            // Floating glass navigation chrome
            VStack {
                GlassEffectContainer(spacing: 12) {
                    HStack(alignment: .top) {
                        // Back button
                        Button(action: {
                            HapticManager.shared.lightTap()
                            dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(.label))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.mini)
                        .accessibilityLabel("Back")
                        .accessibilityHint("Double-tap to go back to collections")

                        Spacer()

                        // Category pill
                        Button(action: {
                            HapticManager.shared.lightTap()
                            showingCollections = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: collection.category.icon)
                                    .font(.system(size: 12, weight: .medium))
                                Text(collection.category.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(Color(.label))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.mini)
                        .accessibilityLabel("\(collection.category.rawValue) collection")
                        .accessibilityHint("Double-tap to view all collections")

                        Spacer()

                        // Menu button
                        Menu {
                            Button(action: { showingSortOptions = true }) {
                                Label("Sort", systemImage: "arrow.up.arrow.down")
                            }

                            Divider()

                            Button(action: {
                                HapticManager.shared.lightTap()
                                viewModel.isSelectionMode.toggle()
                                if !viewModel.isSelectionMode {
                                    viewModel.deselectAll()
                                }
                            }) {
                                Label(
                                    viewModel.isSelectionMode ? "Cancel Selection" : "Select",
                                    systemImage: viewModel.isSelectionMode ? "xmark.circle" : "checkmark.circle"
                                )
                            }

                            if viewModel.isSelectionMode {
                                Divider()

                                Button(action: {
                                    HapticManager.shared.lightTap()
                                    viewModel.selectAll()
                                }) {
                                    Label("Select All", systemImage: "checkmark.circle.fill")
                                }

                                Button(action: {
                                    HapticManager.shared.lightTap()
                                    showingShareSheet = true
                                }) {
                                    Label("Share Selected", systemImage: "square.and.arrow.up")
                                }
                                .disabled(viewModel.selectedScreenshots.isEmpty)

                                Button(role: .destructive, action: {
                                    showingDeleteConfirmation = true
                                }) {
                                    Label("Delete Selected", systemImage: "trash")
                                }
                                .disabled(viewModel.selectedScreenshots.isEmpty)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(.label))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.mini)
                        .accessibilityLabel("Gallery options")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Bottom selection toolbar
                if viewModel.isSelectionMode && !viewModel.selectedScreenshots.isEmpty {
                    HStack(spacing: 16) {
                        Text("\(viewModel.selectedScreenshots.count) selected")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(.label))

                        Spacer()

                        Button(action: {
                            HapticManager.shared.lightTap()
                            showingShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(.label))
                        }
                        .accessibilityLabel("Share \(viewModel.selectedScreenshots.count) selected screenshots")

                        Button(action: {
                            HapticManager.shared.lightTap()
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(SemanticColor.danger.solidColor)
                        }
                        .accessibilityLabel("Delete \(viewModel.selectedScreenshots.count) selected screenshots")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Sort By", isPresented: $showingSortOptions) {
            ForEach(availableSortOptions, id: \.self) { option in
                Button(option.rawValue) {
                    HapticManager.shared.lightTap()
                    viewModel.sortOption = option
                }
            }
        }
        .alert("Delete Screenshots", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteSelected { success in
                    if success {
                        HapticManager.shared.success()
                        viewModel.isSelectionMode = false
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete \(viewModel.selectedScreenshots.count) screenshot\(viewModel.selectedScreenshots.count == 1 ? "" : "s")? This cannot be undone.")
        }
        .sheet(isPresented: $showingShareSheet) {
            if !viewModel.selectedScreenshots.isEmpty {
                GalleryShareSheet(items: viewModel.getSelectedImages())
            }
        }
        .fullScreenCover(item: $selectedScreenshot) { screenshot in
            PhotoDetailView(
                initialScreenshot: screenshot,
                screenshots: viewModel.sortedScreenshots,
                thumbnails: viewModel.thumbnails,
                currentCategory: collection.category
            )
        }
        .sheet(isPresented: $showingCollections) {
            CollectionsPickerView(
                currentCollection: collection,
                allCollections: getAllCollections(),
                onCollectionSelected: { selectedCollection in
                    showingCollections = false
                    // Navigate to selected collection programmatically
                    if selectedCollection.category != collection.category {
                        // Create a new NavigationPath with just the new category
                        // This ensures SwiftUI detects the change and recreates the view
                        Task { @MainActor in
                            var newPath = NavigationPath()
                            newPath.append(selectedCollection.category)
                            // Assign the new path - this should trigger navigation
                            navigationPath = newPath
                        }
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }
    
    // Helper to get all collections with counts
    private func getAllCollections() -> [ScreenshotCollection] {
        // If we have all collections passed in, use those with real counts
        if let allCollections = allCollections {
            // Create a dictionary for quick lookup
            var collectionsDict: [ScreenshotCategory: ScreenshotCollection] = [:]
            for coll in allCollections {
                collectionsDict[coll.category] = coll
            }
            
            // Build result with all categories, using real counts where available
            var result: [ScreenshotCollection] = []
            for category in ScreenshotCategory.allCases {
                if let existingCollection = collectionsDict[category] {
                    result.append(existingCollection)
                } else {
                    // Category doesn't exist in collections, create empty one
                    result.append(ScreenshotCollection(category: category, screenshots: []))
                }
            }
            return result
        }
        
        // Fallback: only have current collection, create empty ones for others
        var result: [ScreenshotCollection] = [collection]
        let existingCategory = collection.category
        for category in ScreenshotCategory.allCases where category != existingCategory {
            result.append(ScreenshotCollection(category: category, screenshots: []))
        }
        return result
    }
}

// MARK: - Thumbnail Cell

struct ThumbnailCell: View {
    let screenshot: Screenshot
    let thumbnail: UIImage?
    var isSelected: Bool = false
    var isSelectionMode: Bool = false
    var onTap: (() -> Void)? = nil

    // Standard iPhone screenshot aspect ratio (roughly 9:19.5)
    private let aspectRatio: CGFloat = 9.0 / 19.5

    @State private var showImage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                // Image or skeleton
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(showImage ? 1 : 0)
                        .onAppear {
                            if reduceMotion {
                                showImage = true
                            } else {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    showImage = true
                                }
                            }
                        }
                } else {
                    SkeletonView(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        cornerRadius: 0
                    )
                }

                // Selection checkmark overlay
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.blue : Color.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .padding(8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }
            // Blue border when selected
            .overlay(
                isSelected && isSelectionMode
                    ? Rectangle().stroke(Color.blue, lineWidth: 3)
                    : nil
            )
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityLabel(
            isSelectionMode
                ? "Screenshot thumbnail\(isSelected ? ", selected" : "")"
                : "Screenshot thumbnail"
        )
        .accessibilityAddTraits(isSelectionMode ? [.isButton] : [])
        .accessibilityHint(
            isSelectionMode
                ? (isSelected ? "Double-tap to deselect" : "Double-tap to select")
                : "Double-tap to view full size"
        )
    }
}

// MARK: - Gallery Share Sheet

private struct GalleryShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Collections Picker View

struct CollectionsPickerView: View {
    let currentCollection: ScreenshotCollection
    let allCollections: [ScreenshotCollection]
    let onCollectionSelected: (ScreenshotCollection) -> Void
    @Environment(\.dismiss) var dismiss
    
    // Helper to get collection for a category (with count) or create empty one
    private func collection(for category: ScreenshotCategory) -> ScreenshotCollection {
        allCollections.first { $0.category == category } 
            ?? ScreenshotCollection(category: category, screenshots: [])
    }
    
    // Group collections by CategoryGroup
    private var groupedCollections: [(group: CategoryGroup, collections: [ScreenshotCollection])] {
        // Get all categories (excluding .all for the picker)
        let categories = ScreenshotCategory.allCases.filter { $0 != .all }
        
        // Create collections for all categories with their counts
        let collectionsWithCounts = categories.map { category in
            collection(for: category)
        }
        
        // Group by category group
        let grouped = Dictionary(grouping: collectionsWithCounts) { $0.category.group }
        return grouped
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (group: $0.key, collections: $0.value.sorted { $0.category.rawValue < $1.category.rawValue }) }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(groupedCollections, id: \.group) { groupItem in
                    Section {
                        ForEach(groupItem.collections) { collection in
                            Button(action: {
                                HapticManager.shared.lightTap()
                                if collection.category != currentCollection.category {
                                    onCollectionSelected(collection)
                                    dismiss()
                                }
                            }) {
                                HStack {
                                    Image(systemName: collection.category.icon)
                                        .font(.title3)
                                        .foregroundColor(collection.category == currentCollection.category ? .blue : .primary)
                                        .frame(width: 40)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Text(collection.category.rawValue)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            
                                            Text("(\(collection.count))")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        if collection.category == currentCollection.category {
                                            Text("Current Collection")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if collection.category == currentCollection.category {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: groupItem.group.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(groupItem.group.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(SemanticColor.primary.gradient)
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
