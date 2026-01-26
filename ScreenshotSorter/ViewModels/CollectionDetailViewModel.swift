import Foundation
import Photos
import UIKit

@MainActor
class CollectionDetailViewModel: ObservableObject {
    @Published var screenshots: [Screenshot]
    @Published var sortOption: SortOption = .dateDescending
    @Published var selectedScreenshots: Set<Screenshot> = []
    @Published var isSelectionMode = false
    @Published var thumbnails: [String: UIImage] = [:]

    let collection: ScreenshotCollection
    private let categoryToShow: ScreenshotCategory
    private let photoService = PhotoLibraryService.shared

    var sortedScreenshots: [Screenshot] {
        // Use the local screenshots array instead of collection.screenshots to maintain stability
        switch sortOption {
        case .dateAscending:
            return screenshots.sorted { $0.creationDate < $1.creationDate }
        case .dateDescending:
            return screenshots.sorted { $0.creationDate > $1.creationDate }
        case .relevancy:
            return screenshots.sorted { $0.categories.count > $1.categories.count }
        }
    }

    init(collection: ScreenshotCollection) {
        self.collection = collection
        self.categoryToShow = collection.category
        // Create a stable copy of screenshots at initialization
        self.screenshots = collection.screenshots
        loadThumbnails()
    }

    func loadThumbnails() {
        for screenshot in screenshots {
            photoService.loadImage(for: screenshot.asset, targetSize: CGSize(width: 300, height: 300)) { [weak self] image in
                if let image = image {
                    self?.thumbnails[screenshot.id] = image
                }
            }
        }
    }

    func toggleSelection(for screenshot: Screenshot) {
        if selectedScreenshots.contains(screenshot) {
            selectedScreenshots.remove(screenshot)
        } else {
            selectedScreenshots.insert(screenshot)
        }
    }

    func selectAll() {
        selectedScreenshots = Set(screenshots)
    }

    func deselectAll() {
        selectedScreenshots.removeAll()
        isSelectionMode = false
    }

    func deleteSelected(completion: @escaping (Bool) -> Void) {
        let assets = selectedScreenshots.map { $0.asset }

        photoService.deleteAssets(assets) { [weak self] success, error in
            if success {
                self?.screenshots.removeAll { self?.selectedScreenshots.contains($0) ?? false }
                self?.selectedScreenshots.removeAll()
                self?.isSelectionMode = false
            }
            completion(success)
        }
    }

    func getSelectedImages() -> [UIImage] {
        var images: [UIImage] = []

        // Get images from thumbnails cache first (fast)
        for screenshot in selectedScreenshots {
            if let thumbnail = thumbnails[screenshot.id] {
                images.append(thumbnail)
            }
        }

        return images
    }
}
