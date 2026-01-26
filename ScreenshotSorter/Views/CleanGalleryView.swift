import SwiftUI
import Photos
import UIKit

struct CleanGalleryView: View {
    let collection: ScreenshotCollection
    @StateObject private var viewModel: CollectionDetailViewModel
    @State private var selectedScreenshot: Screenshot?

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

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.sortedScreenshots) { screenshot in
                    ThumbnailCell(
                        screenshot: screenshot,
                        thumbnail: viewModel.thumbnails[screenshot.id]
                    )
                    .onTapGesture {
                        selectedScreenshot = screenshot
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(collection.category.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemBackground))
        .fullScreenCover(item: $selectedScreenshot) { screenshot in
            PhotoDetailView(
                initialScreenshot: screenshot,
                screenshots: viewModel.sortedScreenshots,
                thumbnails: viewModel.thumbnails
            )
        }
    }
}

struct ThumbnailCell: View {
    let screenshot: Screenshot
    let thumbnail: UIImage?

    // Standard iPhone screenshot aspect ratio (roughly 9:19.5)
    private let aspectRatio: CGFloat = 9.0 / 19.5

    @State private var showImage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
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
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityLabel("Screenshot thumbnail")
    }
}
