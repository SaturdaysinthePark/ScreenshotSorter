import Foundation
import SwiftUI

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
    @Published var currentIndex: Int = 0
    @Published var decisions: [String: ReviewDecision] = [:]
    @Published var isCompleted: Bool = false
    @Published var isLoading: Bool = true
    @Published var loadingProgress: Int = 0
    @Published var hasResumableSession: Bool = false
    @Published var showResumePrompt: Bool = false

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
        return Double(currentIndex) / Double(totalCount)
    }

    // MARK: - Private Properties

    private let preloadCount = 3
    private var preloadedImages: [String: UIImage] = [:]

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
        guard let savedSession = loadSavedSession() else { return }

        currentIndex = min(savedSession.currentIndex, screenshots.count - 1)
        decisions = savedSession.decisions
        showResumePrompt = false

        // Start preloading
        Task {
            await preloadImages()
        }
    }

    func startFresh() {
        clearSavedSession()
        currentIndex = 0
        decisions = [:]
        showResumePrompt = false

        // Start preloading
        Task {
            await preloadImages()
        }
    }

    func saveAndExit() {
        saveSession()
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
        if currentIndex < screenshots.count - 1 {
            currentIndex += 1

            // Preload upcoming images
            Task {
                await preloadUpcomingImages()
            }
        } else {
            isCompleted = true
            clearSavedSession()
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
        PhotoLibraryService.shared.deleteAssets(assets) { success, error in
            if success {
                self.markAllAsReviewed()
                self.clearSavedSession()
                HapticManager.shared.success()
                completion(true)
            } else {
                HapticManager.shared.error()
                completion(false)
            }
        }
    }

    func markAllAsReviewed() {
        UserDefaults.standard.set(Date(), forKey: ReviewSessionKeys.lastReviewCompletionDate)

        let reviewedIDs = Set(screenshots.map { $0.id })
        UserDefaults.standard.set(Array(reviewedIDs), forKey: ReviewSessionKeys.reviewedScreenshotIDs)
    }

    // MARK: - Image Preloading

    func preloadImages() async {
        isLoading = true
        loadingProgress = 0

        let toPreload = Array(screenshots.prefix(preloadCount))

        for (index, screenshot) in toPreload.enumerated() {
            await withCheckedContinuation { continuation in
                PhotoLibraryService.shared.loadFullSizeImage(for: screenshot.asset) { [weak self] image in
                    if let image = image {
                        self?.preloadedImages[screenshot.id] = image
                    }
                    continuation.resume()
                }
            }

            loadingProgress = index + 1
        }

        isLoading = false
    }

    private func preloadUpcomingImages() async {
        let startIndex = currentIndex + 1
        let endIndex = min(currentIndex + preloadCount, screenshots.count)

        guard startIndex < endIndex else { return }

        for index in startIndex..<endIndex {
            let screenshot = screenshots[index]

            // Skip if already preloaded
            guard preloadedImages[screenshot.id] == nil else { continue }

            await withCheckedContinuation { continuation in
                PhotoLibraryService.shared.loadFullSizeImage(for: screenshot.asset) { [weak self] image in
                    if let image = image {
                        self?.preloadedImages[screenshot.id] = image
                    }
                    continuation.resume()
                }
            }
        }
    }

    func getPreloadedImage(for screenshot: Screenshot) -> UIImage? {
        preloadedImages[screenshot.id]
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
