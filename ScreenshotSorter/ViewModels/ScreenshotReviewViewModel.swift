import Foundation
import Photos
import SwiftUI
import UIKit

// MARK: - Review Decision

enum ReviewDecision: String, Codable {
    case keep
    case delete
}

// MARK: - Review Action

struct ReviewAction: Codable {
    let screenshotId: String
    let decision: ReviewDecision

    init(screenshot: Screenshot, decision: ReviewDecision) {
        self.screenshotId = screenshot.id
        self.decision = decision
    }
}

// MARK: - Saved Session State

struct ReviewSessionState: Codable {
    let screenshotIds: [String]
    let currentIndex: Int
    let decisions: [String: ReviewDecision]
    let savedAt: Date

    var isValid: Bool {
        // Session is valid for 24 hours
        Date().timeIntervalSince(savedAt) < 86400
    }
}

// MARK: - Review Session Keys

private enum ReviewSessionKeys {
    static let savedSession = "reviewSessionState"
    static let lastReviewCompletionDate = "lastReviewCompletionDate"
    static let reviewedScreenshotIDs = "reviewedScreenshotIDs"
}

// MARK: - Screenshot Review View Model

@MainActor
class ScreenshotReviewViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var screenshots: [Screenshot]
    /// Index of the card on top of the deck. Equals `screenshots.count` once every card is decided.
    @Published var currentIndex: Int = 0
    @Published var decisions: [String: ReviewDecision] = [:]
    @Published var isCompleted: Bool = false
    @Published var isLoading: Bool = true
    @Published var loadingProgress: Int = 0
    @Published var hasResumableSession: Bool = false
    @Published var showResumePrompt: Bool = false
    /// Screen-sized images for the cards around the top of the deck.
    @Published private(set) var preloadedImages: [String: UIImage] = [:]

    // MARK: - Computed Properties

    var currentScreenshot: Screenshot? {
        guard currentIndex >= 0 && currentIndex < screenshots.count else { return nil }
        return screenshots[currentIndex]
    }

    var totalCount: Int {
        screenshots.count
    }

    var reviewedCount: Int {
        decisions.count
    }

    var progressPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(min(currentIndex, totalCount)) / Double(totalCount)
    }

    /// The top card plus up to `count - 1` cards peeking behind it.
    func upcomingScreenshots(count: Int) -> [Screenshot] {
        guard currentIndex >= 0, currentIndex < screenshots.count, count > 0 else { return [] }
        let end: Int = min(currentIndex + count, screenshots.count)
        return Array(screenshots[currentIndex..<end])
    }

    /// Saved session's progress, for the resume prompt.
    var resumableReviewedCount: Int {
        loadSavedSession()?.decisions.count ?? 0
    }

    // MARK: - Private Properties

    /// Cards to keep warm: the top card + the next two peeking behind it.
    private let preloadCount = 3
    private var imageRequests: [String: PHImageRequestID] = [:]
    private var pendingFirstLoad: Set<String> = []
    private let imageManager = PHCachingImageManager()
    private lazy var targetSize: CGSize = ScreenshotReviewViewModel.screenPixelSize()
    private var loadingTimeoutTask: Task<Void, Never>?

    // MARK: - Initialization

    init(screenshots: [Screenshot]) {
        self.screenshots = screenshots

        // Check for resumable session
        if let savedSession = loadSavedSession(),
           savedSession.isValid,
           Set(savedSession.screenshotIds) == Set(screenshots.map { $0.id }) {
            hasResumableSession = true
            showResumePrompt = true
        }
    }

    // MARK: - Session Management

    func resumeSession() {
        guard let savedSession = loadSavedSession() else {
            startFresh()
            return
        }

        currentIndex = max(0, min(savedSession.currentIndex, screenshots.count))
        decisions = savedSession.decisions
        showResumePrompt = false
        if currentIndex >= screenshots.count && !screenshots.isEmpty {
            isCompleted = true
        }
        beginInitialLoad()
    }

    func startFresh() {
        clearSavedSession()
        currentIndex = 0
        decisions = [:]
        isCompleted = false
        showResumePrompt = false
        beginInitialLoad()
    }

    func saveAndExit() {
        saveSession()
        cancelAllImageRequests()
        HapticManager.shared.success()
    }

    // MARK: - Decision Making

    func makeDecision(_ decision: ReviewDecision) {
        guard let screenshot = currentScreenshot else { return }
        decisions[screenshot.id] = decision

        // Auto-save after each decision
        saveSession()
    }

    func nextScreenshot() {
        guard currentIndex < screenshots.count else { return }
        currentIndex += 1

        if currentIndex >= screenshots.count {
            isCompleted = true
            clearSavedSession()
        } else {
            preloadWindow()
        }
    }

    func undoLastAction(_ action: ReviewAction) {
        // Remove the decision
        decisions.removeValue(forKey: action.screenshotId)

        // Find the index of the screenshot that was just acted upon
        if let index = screenshots.firstIndex(where: { $0.id == action.screenshotId }) {
            currentIndex = index
        }

        // Reset completion state if it was set
        isCompleted = false

        // Update saved session
        saveSession()
        preloadWindow()

        HapticManager.shared.undo()
    }

    // MARK: - Deletion Management

    func getMarkedForDeletion() -> [Screenshot] {
        screenshots.filter { decisions[$0.id] == .delete }
    }

    func getMarkedToKeep() -> [Screenshot] {
        screenshots.filter { decisions[$0.id] == .keep }
    }

    func confirmDeletions(completion: @escaping (Bool) -> Void) {
        let toDelete = getMarkedForDeletion()

        guard !toDelete.isEmpty else {
            markAllAsReviewed()
            clearSavedSession()
            completion(true)
            return
        }

        let assets = toDelete.map { $0.asset }
        PhotoLibraryService.shared.deleteAssets(assets) { success, _ in
            if success {
                self.markAllAsReviewed()
                self.clearSavedSession()
                HapticManager.shared.success()
                completion(true)
            } else {
                HapticManager.shared.warning()
                completion(false)
            }
        }
    }

    func markAllAsReviewed() {
        UserDefaults.standard.set(Date(), forKey: ReviewSessionKeys.lastReviewCompletionDate)

        let reviewedIDs = Set(screenshots.map { $0.id })
        UserDefaults.standard.set(Array(reviewedIDs), forKey: ReviewSessionKeys.reviewedScreenshotIDs)
    }

    // MARK: - Space Estimate

    /// Total on-disk size (bytes) of the screenshots marked for deletion. Runs off the main thread.
    func bytesMarkedForDeletion() async -> Int64 {
        let assets: [PHAsset] = getMarkedForDeletion().map { $0.asset }
        guard !assets.isEmpty else { return 0 }
        let task = Task.detached(priority: .utility) { () -> Int64 in
            ScreenshotReviewViewModel.totalFileSize(of: assets)
        }
        return await task.value
    }

    nonisolated static func totalFileSize(of assets: [PHAsset]) -> Int64 {
        var total: Int64 = 0
        for asset in assets {
            let resources: [PHAssetResource] = PHAssetResource.assetResources(for: asset)
            // Prefer the primary photo resource; fall back to summing everything.
            let primary: [PHAssetResource] = resources.filter { $0.type == .photo || $0.type == .fullSizePhoto }
            let counted: [PHAssetResource] = primary.isEmpty ? resources : primary
            for resource in counted {
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    total += size
                } else if let number = resource.value(forKey: "fileSize") as? NSNumber {
                    total += number.int64Value
                }
            }
        }
        return total
    }

    // MARK: - Image Preloading

    /// Legacy entry point: loads the first cards and flips `isLoading` off.
    func preloadImages() async {
        beginInitialLoad()
    }

    func getPreloadedImage(for screenshot: Screenshot) -> UIImage? {
        preloadedImages[screenshot.id]
    }

    /// Shows the loading state until the top card has an image (any quality), then warms the next cards.
    private func beginInitialLoad() {
        guard let first = currentScreenshot else {
            isLoading = false
            loadingProgress = 0
            return
        }

        if preloadedImages[first.id] != nil {
            isLoading = false
            preloadWindow()
            return
        }

        isLoading = true
        loadingProgress = 0
        pendingFirstLoad = Set(upcomingScreenshots(count: preloadCount).map { $0.id })
        preloadWindow()

        // Never trap the user on the loading screen (e.g. slow iCloud downloads).
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.isLoading = false
        }
    }

    /// Requests screen-sized images for the top `preloadCount` cards and cancels/evicts everything else.
    private func preloadWindow() {
        let window: [Screenshot] = upcomingScreenshots(count: preloadCount)
        let windowIDs: Set<String> = Set(window.map { $0.id })

        // Keep the previous card's image around for a snappy undo.
        var keepIDs: Set<String> = windowIDs
        if currentIndex - 1 >= 0 && currentIndex - 1 < screenshots.count {
            keepIDs.insert(screenshots[currentIndex - 1].id)
        }

        // Cancel requests that fell out of the window.
        for (id, requestID) in imageRequests where !windowIDs.contains(id) {
            imageManager.cancelImageRequest(requestID)
            imageRequests.removeValue(forKey: id)
        }

        // Evict images we no longer need (bounded memory).
        for id in preloadedImages.keys where !keepIDs.contains(id) {
            preloadedImages.removeValue(forKey: id)
        }

        for screenshot in window where preloadedImages[screenshot.id] == nil && imageRequests[screenshot.id] == nil {
            requestImage(for: screenshot)
        }
    }

    private func requestImage(for screenshot: Screenshot) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let id: String = screenshot.id
        let requestID: PHImageRequestID = imageManager.requestImage(
            for: screenshot.asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            let isDegraded: Bool = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isCancelled: Bool = (info?[PHImageCancelledKey] as? Bool) ?? false
            Task { @MainActor [weak self] in
                self?.handleImage(image, id: id, isDegraded: isDegraded, isCancelled: isCancelled)
            }
        }
        imageRequests[id] = requestID
    }

    private func handleImage(_ image: UIImage?, id: String, isDegraded: Bool, isCancelled: Bool) {
        guard !isCancelled else {
            imageRequests.removeValue(forKey: id)
            return
        }

        if let image {
            // Never replace a high-quality image with a degraded one.
            if !(isDegraded && preloadedImages[id] != nil) {
                preloadedImages[id] = image
            }
        }

        if !isDegraded {
            imageRequests.removeValue(forKey: id)
            if pendingFirstLoad.remove(id) != nil {
                loadingProgress += 1
            }
        }

        // The top card is showable → leave the loading state.
        if isLoading, let top = currentScreenshot, top.id == id, (image != nil || !isDegraded) {
            isLoading = false
            loadingTimeoutTask?.cancel()
        }
    }

    private func cancelAllImageRequests() {
        for (_, requestID) in imageRequests {
            imageManager.cancelImageRequest(requestID)
        }
        imageRequests.removeAll()
    }

    private static func screenPixelSize() -> CGSize {
        let scene: UIWindowScene? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        if let screen = scene?.screen {
            let bounds: CGSize = screen.bounds.size
            let scale: CGFloat = screen.scale
            return CGSize(width: bounds.width * scale, height: bounds.height * scale)
        }
        return CGSize(width: 1290, height: 2796)
    }

    // MARK: - Persistence

    private func saveSession() {
        let state = ReviewSessionState(
            screenshotIds: screenshots.map { $0.id },
            currentIndex: currentIndex,
            decisions: decisions,
            savedAt: Date()
        )

        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: ReviewSessionKeys.savedSession)
        }
    }

    private func loadSavedSession() -> ReviewSessionState? {
        guard let data = UserDefaults.standard.data(forKey: ReviewSessionKeys.savedSession),
              let state = try? JSONDecoder().decode(ReviewSessionState.self, from: data) else {
            return nil
        }
        return state
    }

    private func clearSavedSession() {
        UserDefaults.standard.removeObject(forKey: ReviewSessionKeys.savedSession)
        hasResumableSession = false
    }

    // MARK: - Statistics

    var deletedCount: Int {
        decisions.values.filter { $0 == .delete }.count
    }

    var keptCount: Int {
        decisions.values.filter { $0 == .keep }.count
    }
}

// MARK: - Legacy Support (for backward compatibility with ReviewAction using Screenshot)

extension ReviewAction {
    var screenshot: Screenshot? {
        // This is a computed property for backward compatibility
        // The actual screenshot should be looked up from the view model
        nil
    }
}
