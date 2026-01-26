import Foundation
import Photos
import UIKit
import Combine

enum CollectionsSortOption: String, CaseIterable {
    case imageCount = "Image Count"
    case alphabetical = "Alphabetical"
    case mostRecent = "Most Recent"
    case oldest = "Oldest"
}

@MainActor
class CollectionsViewModel: ObservableObject {
    @Published var collections: [ScreenshotCollection] = []
    @Published var isLoading = false
    @Published var isProcessing = false
    @Published var isPaused = false
    @Published var processingProgress: String = ""
    @Published var hasPhotoAccess = false
    @Published var errorMessage: String?
    @Published var allScreenshots: [Screenshot] = []
    @Published var sortOption: CollectionsSortOption = .imageCount
    @Published var isGroupedView: Bool = true
    @Published var showEmptyCategories: Bool = false
    @Published private(set) var allScreenshotsCollection: ScreenshotCollection
    @Published var totalToProcess: Int = 0
    @Published var totalProcessed: Int = 0

    private let photoService = PhotoLibraryService.shared
    private let categorizationService = CategorizationService.shared
    private let cacheService = CategorizationCacheService.shared
    private var cancellables = Set<AnyCancellable>()
    private var processingTask: Task<Void, Never>?

    private let lastProcessedCountKey = "lastProcessedScreenshotCount"
    private let lastUnprocessedBannerDismissedDateKey = "lastUnprocessedBannerDismissedDate"

    // Incremental update properties
    private var lastUIUpdate: Date = Date.distantPast
    private var pendingProcessedScreenshots: [Screenshot] = []
    private let uiUpdateThrottle: TimeInterval = 0.5 // 500ms
    @Published var hasNewScreenshots = false
    @Published var newScreenshotCount = 0

    // Unprocessed photos feature
    @Published var hasUnprocessedPhotos = false
    @Published var unprocessedPhotoCount = 0
    @Published var showUnprocessedBanner = false
    @Published var showRefreshWithUnprocessedAlert = false

    // Review feature
    @Published var unreviewedScreenshots: [Screenshot] = []
    @Published var showReviewBanner: Bool = false
    @Published var reviewBannerDismissed: Bool = false

    var unreviewedCount: Int {
        unreviewedScreenshots.count
    }

    var sortedCollections: [ScreenshotCollection] {
        var allCollections: [ScreenshotCollection]

        if showEmptyCategories {
            // Create collections for all categories
            let existingCategories = Set(collections.map { $0.category })
            let emptyCollections = ScreenshotCategory.allCases
                .filter { $0 != .all && !existingCategories.contains($0) }
                .map { ScreenshotCollection(category: $0, screenshots: []) }
            allCollections = collections.filter { $0.category != .all } + emptyCollections
        } else {
            allCollections = collections.filter { $0.category != .all }
        }

        switch sortOption {
        case .imageCount:
            return allCollections.sorted { $0.count > $1.count }
        case .alphabetical:
            if isGroupedView {
                // Sort by group first, then alphabetically within group
                return allCollections.sorted { c1, c2 in
                    let g1 = c1.category.group.rawValue
                    let g2 = c2.category.group.rawValue
                    if g1 == g2 {
                        return c1.category.rawValue < c2.category.rawValue
                    }
                    return g1 < g2
                }
            } else {
                return allCollections.sorted { $0.category.rawValue < $1.category.rawValue }
            }
        case .mostRecent:
            return allCollections.sorted { c1, c2 in
                let date1 = c1.screenshots.max(by: { $0.creationDate < $1.creationDate })?.creationDate ?? Date.distantPast
                let date2 = c2.screenshots.max(by: { $0.creationDate < $1.creationDate })?.creationDate ?? Date.distantPast
                return date1 > date2
            }
        case .oldest:
            return allCollections.sorted { c1, c2 in
                let date1 = c1.screenshots.min(by: { $0.creationDate < $1.creationDate })?.creationDate ?? Date.distantFuture
                let date2 = c2.screenshots.min(by: { $0.creationDate < $1.creationDate })?.creationDate ?? Date.distantFuture
                return date1 < date2
            }
        }
    }

    init() {
        // Initialize with empty collection
        allScreenshotsCollection = ScreenshotCollection(category: .all, screenshots: [])
        // Check photo access but skip new screenshot check (will be done after splash)
        checkPhotoAccess(skipNewScreenshotCheck: true)
    }

    func checkPhotoAccess(skipNewScreenshotCheck: Bool = false) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        hasPhotoAccess = status == .authorized || status == .limited

        if hasPhotoAccess && !skipNewScreenshotCheck {
            checkForNewScreenshots()
        }
    }

    func checkForNewScreenshots() {
        isLoading = true

        photoService.fetchScreenshots { [weak self] assets in
            guard let self = self else { return }

            Task { @MainActor in
                let currentCount = assets.count
                let lastCount = UserDefaults.standard.integer(forKey: self.lastProcessedCountKey)

                print("📸 checkForNewScreenshots - Current: \(currentCount), Last: \(lastCount)")

                if lastCount == 0 {
                    // First time - process all
                    print("📸 First time - loading screenshots")
                    self.loadScreenshots()
                } else if currentCount > lastCount {
                    // New screenshots detected
                    print("📸 New screenshots detected: \(currentCount - lastCount)")
                    self.newScreenshotCount = currentCount - lastCount
                    self.hasNewScreenshots = true
                    self.isLoading = false
                } else if currentCount == lastCount {
                    // No changes - load photos but skip processing
                    print("📸 No changes detected - loading photos without processing")
                    self.loadPhotosOnly(assets, shouldStopLoading: true)
                } else {
                    // Count decreased (screenshots deleted) - show alert to reprocess
                    print("📸 Screenshots deleted - new count: \(currentCount)")
                    self.newScreenshotCount = currentCount
                    self.hasNewScreenshots = true
                    self.isLoading = false
                }
            }
        }
    }

    func processNewScreenshots() {
        hasNewScreenshots = false
        loadScreenshots()
    }

    func loadExistingPhotosWithoutProcessing() {
        // User chose "Later" for new screenshots - load existing processed photos
        hasNewScreenshots = false
        isLoading = true

        photoService.fetchScreenshots { [weak self] assets in
            guard let self = self else { return }

            Task { @MainActor in
                // Update the count to acknowledge we've seen these screenshots
                UserDefaults.standard.set(assets.count, forKey: self.lastProcessedCountKey)

                // Load all photos from cache (don't process new ones)
                self.loadPhotosOnly(assets, shouldStopLoading: true)
            }
        }
    }

    func processLaterPhotos() {
        // User chose "Later" - dismiss alert and show banner
        hasUnprocessedPhotos = false
        showUnprocessedBanner = true

        // Save dismissal date
        UserDefaults.standard.set(
            Date(),
            forKey: lastUnprocessedBannerDismissedDateKey
        )
    }

    func dismissUnprocessedBanner() {
        showUnprocessedBanner = false

        // Save dismissal date to UserDefaults
        UserDefaults.standard.set(
            Date(),
            forKey: lastUnprocessedBannerDismissedDateKey
        )
    }

    func reanalyzeAll() {
        // Explicit reprocess of all screenshots
        loadScreenshots()
    }

    func requestPhotoAccess() {
        photoService.requestAuthorization { [weak self] granted in
            Task { @MainActor in
                self?.hasPhotoAccess = granted
                if granted {
                    self?.loadScreenshots()
                }
            }
        }
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            processingProgress = "Resuming... (\(totalProcessed)/\(totalToProcess))"
        } else {
            processingProgress = "Paused at \(totalProcessed)/\(totalToProcess)"
        }
    }

    func loadPhotosOnly(_ assets: [PHAsset], shouldStopLoading: Bool = false) {
        print("📸 loadPhotosOnly() called - loading \(assets.count) photos and restoring from cache")

        Task { @MainActor in
            var cachedCount = 0
            var uncachedCount = 0

            // Restore screenshots from cache or mark as unprocessed
            let screenshots = assets.map { asset -> Screenshot in
                // Try to load from cache
                if let cachedCategories = self.cacheService.getCachedCategories(for: asset.localIdentifier) {
                    cachedCount += 1
                    let categoriesWithConfidence = cachedCategories.map {
                        CategoryWithConfidence(category: $0, confidence: .high, score: 0.8)
                    }
                    var screenshot = Screenshot(asset: asset, categoriesWithConfidence: categoriesWithConfidence)
                    screenshot.processingStatus = .processed
                    return screenshot
                } else {
                    uncachedCount += 1
                    var screenshot = Screenshot(asset: asset, categories: [.other])
                    screenshot.processingStatus = .unprocessed
                    return screenshot
                }
            }.sorted { $0.creationDate > $1.creationDate }

            // Populate screenshots
            self.allScreenshots = screenshots
            self.allScreenshotsCollection = ScreenshotCollection(
                category: .all,
                screenshots: screenshots
            )

            // Rebuild collections from cached screenshots
            self.rebuildCollections(from: screenshots.filter { $0.processingStatus == .processed })

            print("📸 Restored \(cachedCount) from cache, \(uncachedCount) need processing")

            // Check for unprocessed photos and trigger alert/banner
            self.checkForUnprocessedPhotos()

            // Check if there are unreviewed photos and show banner
            self.checkForUnreviewedScreenshotsProgressive()

            // Stop loading if requested
            if shouldStopLoading {
                self.isLoading = false
            }
        }
    }

    func checkForUnprocessedPhotos() {
        // Count screenshots with .unprocessed status
        let unprocessedScreenshots = allScreenshots.filter {
            $0.processingStatus == .unprocessed
        }

        unprocessedPhotoCount = unprocessedScreenshots.count

        if unprocessedPhotoCount > 0 {
            print("📸 Found \(unprocessedPhotoCount) unprocessed photos")

            // Check if banner was recently dismissed
            let lastDismissedDate = UserDefaults.standard.object(
                forKey: lastUnprocessedBannerDismissedDateKey
            ) as? Date ?? Date.distantPast

            // Get the newest unprocessed photo date
            let newestUnprocessedDate = unprocessedScreenshots
                .map { $0.creationDate }
                .max() ?? Date.distantPast

            // Show alert if new unprocessed photos since last dismissal
            if newestUnprocessedDate > lastDismissedDate {
                hasUnprocessedPhotos = true
            } else {
                // Alert dismissed, but show banner instead
                showUnprocessedBanner = true
            }
        } else {
            hasUnprocessedPhotos = false
            showUnprocessedBanner = false
        }
    }

    func processUnprocessedOnly() {
        print("📸 processUnprocessedOnly() called")

        // Cancel any existing processing task
        processingTask?.cancel()

        // Get only unprocessed screenshots
        let unprocessedScreenshots = allScreenshots.filter {
            $0.processingStatus == .unprocessed
        }

        guard !unprocessedScreenshots.isEmpty else {
            print("⚠️ No unprocessed screenshots to process")
            return
        }

        isProcessing = true
        isPaused = false
        errorMessage = nil

        let unprocessedAssets = unprocessedScreenshots.map { $0.asset }

        processingTask = Task { @MainActor in
            // Update progress tracking
            self.totalToProcess = unprocessedAssets.count
            self.totalProcessed = 0
            self.processingProgress = "Analyzing \(self.totalToProcess) unprocessed screenshot\(self.totalToProcess == 1 ? "" : "s")..."

            // Process only unprocessed assets
            await self.processScreenshots(unprocessedAssets)

            // Only update state if task wasn't cancelled
            guard !Task.isCancelled else {
                print("⚠️ Processing task was cancelled")
                return
            }

            self.isProcessing = false
            self.isPaused = false
            self.processingProgress = ""

            // Update the count for new screenshot detection
            // Use total screenshot count (processed + unprocessed)
            UserDefaults.standard.set(
                self.allScreenshots.count,
                forKey: self.lastProcessedCountKey
            )

            // Clear unprocessed state
            self.hasUnprocessedPhotos = false
            self.showUnprocessedBanner = false
            self.unprocessedPhotoCount = 0
        }
    }

    func loadScreenshots() {
        print("📸 loadScreenshots() called")

        // Cancel any existing processing task
        processingTask?.cancel()

        isLoading = false
        isProcessing = true
        isPaused = false
        errorMessage = nil
        processingProgress = "Loading screenshots..."

        photoService.fetchScreenshots { [weak self] assets in
            guard let self = self else { return }

            print("📸 Fetched \(assets.count) screenshots")

            self.processingTask = Task { @MainActor in
                // IMMEDIATE DISPLAY: Create unprocessed screenshots
                let unprocessedScreenshots = assets.map { asset in
                    var screenshot = Screenshot(asset: asset, categories: [.other])
                    screenshot.processingStatus = .unprocessed
                    return screenshot
                }.sorted { $0.creationDate > $1.creationDate }

                print("📸 Created \(unprocessedScreenshots.count) unprocessed screenshots")

                // Populate immediately - ALL PHOTOS NOW VISIBLE
                self.allScreenshots = unprocessedScreenshots
                self.allScreenshotsCollection = ScreenshotCollection(
                    category: .all,
                    screenshots: unprocessedScreenshots
                )

                print("📸 allScreenshots count: \(self.allScreenshots.count)")

                // Update UI state
                self.totalToProcess = assets.count
                self.totalProcessed = 0
                self.processingProgress = "Analyzing 0/\(assets.count)..."

                // NOW start background processing
                await self.processScreenshots(assets)

                // Only update state if task wasn't cancelled
                guard !Task.isCancelled else {
                    print("⚠️ Processing task was cancelled")
                    return
                }

                self.isProcessing = false
                self.isPaused = false
                self.processingProgress = ""

                // Save the count for new screenshot detection
                UserDefaults.standard.set(assets.count, forKey: self.lastProcessedCountKey)
            }
        }
    }

    private func processScreenshots(_ assets: [PHAsset]) async {
        // Process screenshots in batches to avoid overwhelming the system
        let batchSize = 10
        var processedCount = 0

        // Reset incremental update state
        pendingProcessedScreenshots.removeAll()
        lastUIUpdate = Date.distantPast

        for batch in stride(from: 0, to: assets.count, by: batchSize) {
            // Check if task was cancelled
            guard !Task.isCancelled else {
                print("⚠️ Processing cancelled at \(processedCount)/\(assets.count)")
                return
            }

            // Wait while paused
            while isPaused {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }

            let endIndex = min(batch + batchSize, assets.count)
            let batchAssets = Array(assets[batch..<endIndex])

            // Update progress with clearer messaging
            processedCount = min(endIndex, assets.count)
            totalProcessed = processedCount
            processingProgress = "Analyzing \(processedCount)/\(assets.count)..."

            await withTaskGroup(of: Screenshot?.self) { group in
                for asset in batchAssets {
                    group.addTask {
                        await self.categorizeAsset(asset)
                    }
                }

                for await screenshot in group {
                    if let screenshot = screenshot {
                        // INCREMENTAL UPDATE instead of batching
                        self.updateUIIncremental(screenshot)
                    }
                }
            }
        }

        // Final flush of any remaining pending screenshots
        if !pendingProcessedScreenshots.isEmpty {
            updateUIIncremental(pendingProcessedScreenshots.first!) // Trigger final update
        }

        processingProgress = "Done! Organized \(assets.count)"

        // Final review check (updates banner text to remove "processing...")
        checkForUnreviewedScreenshotsProgressive()
    }

    private func updateUIIncremental(_ processedScreenshot: Screenshot) {
        // Skip if photo was deleted
        guard allScreenshots.contains(where: { $0.id == processedScreenshot.id }) else {
            return
        }

        // Add to pending buffer
        pendingProcessedScreenshots.append(processedScreenshot)

        let now = Date()
        let shouldUpdate = pendingProcessedScreenshots.count >= 5 ||
                          now.timeIntervalSince(lastUIUpdate) >= uiUpdateThrottle

        guard shouldUpdate else { return }

        // Update allScreenshots with processed versions
        for processed in pendingProcessedScreenshots {
            if let index = allScreenshots.firstIndex(where: { $0.id == processed.id }) {
                var updated = processed
                updated.processingStatus = .processed
                allScreenshots[index] = updated
            }
        }

        // Update category collections
        var screenshotsByCategory: [ScreenshotCategory: [Screenshot]] = [:]
        for screenshot in allScreenshots where screenshot.processingStatus == .processed {
            for category in screenshot.categories {
                screenshotsByCategory[category, default: []].append(screenshot)
            }
        }

        collections = screenshotsByCategory
            .filter { !$0.value.isEmpty && $0.key != .other }
            .map { ScreenshotCollection(category: $0.key, screenshots: $0.value) }
            .sorted { $0.category.rawValue < $1.category.rawValue }

        // Update all screenshots collection
        allScreenshotsCollection = ScreenshotCollection(
            category: .all,
            screenshots: allScreenshots
        )

        // Check for review availability - show if we have any processed photos
        if totalProcessed > 0 && !showReviewBanner {
            checkForUnreviewedScreenshotsProgressive()
        }

        // Clear buffer and update timestamp
        pendingProcessedScreenshots.removeAll()
        lastUIUpdate = now
    }

    private func categorizeAsset(_ asset: PHAsset) async -> Screenshot? {
        let assetId = asset.localIdentifier

        // Check cache first
        if let cachedCategories = cacheService.getCachedCategories(for: assetId) {
            print("📦 Using cached categories for asset: \(assetId)")
            let categoriesWithConfidence = cachedCategories.map {
                CategoryWithConfidence(category: $0, confidence: .high, score: 0.8)
            }
            return Screenshot(asset: asset, categoriesWithConfidence: categoriesWithConfidence)
        }

        // Categorize using async APIs
        do {
            let image = try await photoService.loadImageAsync(for: asset)
            let categoriesWithConfidence = try await categorizationService.categorizeAsync(image: image)

            // Save to cache
            let categories = categoriesWithConfidence.map { $0.category }
            cacheService.saveCategories(categories, for: assetId)

            return Screenshot(asset: asset, categoriesWithConfidence: categoriesWithConfidence)
        } catch {
            print("❌ Failed to categorize asset \(assetId): \(error.localizedDescription)")
            // Return with .other category on failure
            return Screenshot(asset: asset, categoriesWithConfidence: [CategoryWithConfidence(category: .other, confidence: .medium, score: 0.5)])
        }
    }

    func refreshCollections() {
        // Check if there are unprocessed photos
        let unprocessedCount = allScreenshots.filter {
            $0.processingStatus == .unprocessed
        }.count

        if unprocessedCount > 0 {
            // Show special alert with 3 options
            unprocessedPhotoCount = unprocessedCount
            showRefreshWithUnprocessedAlert = true
        } else {
            // No unprocessed - proceed with normal refresh (reprocess all)
            loadScreenshots()
        }
    }

    func updateReviewState() {
        // Just update the review state, don't reprocess
        checkForUnreviewedScreenshots()
    }

    // MARK: - Cache Restoration

    private func rebuildCollections(from screenshots: [Screenshot]) {
        print("🔄 Rebuilding collections from \(screenshots.count) cached screenshots")

        var collectionDict: [ScreenshotCategory: [Screenshot]] = [:]

        for screenshot in screenshots {
            for categoryWithConfidence in screenshot.categoriesWithConfidence {
                let category = categoryWithConfidence.category
                if category != .all {
                    collectionDict[category, default: []].append(screenshot)
                }
            }
        }

        // Convert to ScreenshotCollection array
        self.collections = collectionDict.map { category, screenshots in
            ScreenshotCollection(category: category, screenshots: screenshots)
        }

        print("📊 Rebuilt \(self.collections.count) collections from cache")
    }

    func checkForUnreviewedScreenshots() {
        // Get set of reviewed photo IDs
        let reviewedIDs = Set(
            UserDefaults.standard.array(forKey: "reviewedScreenshotIDs") as? [String] ?? []
        )

        // Filter: NOT in reviewed set = unreviewed
        unreviewedScreenshots = allScreenshots.filter { screenshot in
            !reviewedIDs.contains(screenshot.id)
        }

        // Show banner if there are unreviewed screenshots
        if unreviewedCount > 0 {
            let lastDismissedDate = UserDefaults.standard.object(forKey: "lastBannerDismissedDate") as? Date ?? Date.distantPast
            let newestUnreviewedDate = unreviewedScreenshots.map { $0.creationDate }.max() ?? Date.distantPast
            showReviewBanner = newestUnreviewedDate > lastDismissedDate
            reviewBannerDismissed = !showReviewBanner
        } else {
            showReviewBanner = false
            reviewBannerDismissed = false
        }
    }

    func checkForUnreviewedScreenshotsProgressive() {
        // Same logic as above
        let reviewedIDs = Set(
            UserDefaults.standard.array(forKey: "reviewedScreenshotIDs") as? [String] ?? []
        )

        unreviewedScreenshots = allScreenshots.filter { screenshot in
            !reviewedIDs.contains(screenshot.id)
        }

        // Show banner if we have any unreviewed photos
        if unreviewedCount > 0 {
            let lastDismissedDate = UserDefaults.standard.object(forKey: "lastBannerDismissedDate") as? Date ?? Date.distantPast
            let newestUnreviewedDate = unreviewedScreenshots.map { $0.creationDate }.max() ?? Date.distantPast

            // Only show if not recently dismissed
            if newestUnreviewedDate > lastDismissedDate {
                showReviewBanner = true
                reviewBannerDismissed = false
            }
        }
    }

    func dismissReviewBanner() {
        reviewBannerDismissed = true
        showReviewBanner = false

        // Save dismissal date to UserDefaults
        UserDefaults.standard.set(Date(), forKey: "lastBannerDismissedDate")
    }
}
