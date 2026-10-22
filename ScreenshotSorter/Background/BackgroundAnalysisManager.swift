import BackgroundTasks
import Foundation
import os

/// Keeps analysis going when the user leaves the app.
///
/// - Continued processing (iOS 26): big jobs started in the foreground (first import,
///   re-analyze all) keep running with a system progress UI after the app is backgrounded.
/// - Overnight processing: while charging, finish the deep pass and language-model lane.
enum BackgroundAnalysisManager {
    static let continuedIdentifier = "sabtain.ScreenshotSorter.analysis.continued"
    static let overnightIdentifier = "sabtain.ScreenshotSorter.analysis.overnight"
    /// Don't bother the user with a system progress UI for small backlogs
    static let continuedThreshold = 150

    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "Background")

    /// Provided by the app once the analysis stack exists.
    @MainActor static var schedulerProvider: (() -> AnalysisScheduler?)?

    /// Must be called before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: continuedIdentifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleContinued(task)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: overnightIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleOvernight(task)
        }
    }

    /// Submit while the app is still in the foreground (required for continued processing).
    static func submitContinuedIfNeeded(remaining: Int) {
        guard remaining >= continuedThreshold else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: continuedIdentifier,
            title: Brand.Copy.Background.sortingTitle,
            subtitle: Brand.Copy.Background.toGo(remaining)
        )
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.info("Continued task not submitted: \(String(describing: error), privacy: .public)")
        }
    }

    static func scheduleOvernight() {
        let request = BGProcessingTaskRequest(identifier: overnightIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.info("Overnight task not scheduled: \(String(describing: error), privacy: .public)")
        }
    }

    /// Sorting only (fast + deep passes). The language model can't use the Neural Engine in the background
    /// without an extra entitlement on iOS 27, so counting it left the progress stuck and iOS expired the task,
    /// which the system UI shows as "Task failed" while sorting was fine.
    private static func handleContinued(_ task: BGContinuedProcessingTask) {
        // Read by the expiration handler, which can't await the scheduler
        let state = OSAllocatedUnfairLock(initialState: (remaining: 0, finished: false))
        /// The task completes once, from whichever side gets here first
        let claimCompletion = { state.withLock { value -> Bool in
            defer { value.finished = true }
            return !value.finished
        } }
        let work = Task { @MainActor in
            guard let scheduler = schedulerProvider?() else {
                task.setTaskCompleted(success: false)
                return
            }
            await scheduler.setInBackground(true)
            let start = await scheduler.currentProgress()
            let total = max(1, start.fastRemaining + start.deepRemaining)
            task.progress.totalUnitCount = Int64(total)
            var shown = -1
            while !Task.isCancelled {
                let current = await scheduler.currentProgress()
                let remaining = current.fastRemaining + current.deepRemaining
                state.withLock { $0.remaining = remaining }
                if remaining == 0 { break }
                if remaining != shown {
                    shown = remaining
                    task.progress.completedUnitCount = Int64(max(0, total - remaining))
                    task.updateTitle(Brand.Copy.Background.sortingTitle, subtitle: Brand.Copy.Background.toGo(remaining))
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            guard claimCompletion() else { return }
            task.progress.completedUnitCount = Int64(total)
            task.updateTitle(Brand.Copy.Background.doneTitle, subtitle: Brand.screenshots(total))
            task.setTaskCompleted(success: true)
            if !(await scheduler.currentProgress()).isIdle { scheduleOvernight() }
        }
        task.expirationHandler = {
            work.cancel()
            scheduleOvernight()
            let left = state.withLock { $0.remaining }
            guard claimCompletion() else { return }
            // Nothing was lost: everything sorted so far is saved and the rest continues next launch
            task.updateTitle(Brand.Copy.Background.pausedTitle, subtitle: Brand.Copy.Background.paused(left))
            task.setTaskCompleted(success: true)
        }
    }

    private static func handleOvernight(_ task: BGProcessingTask) {
        let work = Task { @MainActor in
            guard let scheduler = schedulerProvider?() else {
                task.setTaskCompleted(success: false)
                return
            }
            await scheduler.setInBackground(true)
            await scheduler.waitUntilDrained()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            scheduleOvernight()
            task.setTaskCompleted(success: false)
        }
    }
}
