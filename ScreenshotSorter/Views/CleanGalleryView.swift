import SwiftUI
import Photos
import UIKit

struct CleanGalleryView: View {
    let collection: ScreenshotCollection
    @StateObject private var viewModel: CollectionDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScreenshot: Screenshot?
    @State private var showingSortOptions = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false

    init(collection: ScreenshotCollection) {
        self.collection = collection
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
                HStack(alignment: .top) {
                    // Back button
                    Button(action: {
                        HapticManager.shared.lightTap()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular, in: .circle)
                    }
                    .accessibilityLabel("Back")
                    .accessibilityHint("Double-tap to go back to collections")

                    Spacer()

                    // Category pill
                    HStack(spacing: 6) {
                        Image(systemName: collection.category.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text(collection.category.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityLabel("\(collection.category.rawValue) collection")

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
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular, in: .circle)
                    }
                    .accessibilityLabel("Gallery options")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Bottom selection toolbar
                if viewModel.isSelectionMode && !viewModel.selectedScreenshots.isEmpty {
                    HStack(spacing: 16) {
                        Text("\(viewModel.selectedScreenshots.count) selected")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        Button(action: {
                            HapticManager.shared.lightTap()
                            showingShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
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
