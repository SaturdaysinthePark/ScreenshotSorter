import BackgroundTasks
import Foundation
import os

/// Keeps analysis going when the user leaves the app.
///
/// - Continued processing (iOS 26): big jobs someone starts with a tap (allowing photo access, "Re-sort everything",
///   resuming) keep running with a system progress UI (a Live Activity) after the app is backgrounded. Apple: these
///   start only from a person's action, never automatically, and tasks that don't report progress are expired, which
///   the system shows as "Task failed".
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

    /// Call right after the tap that started a big job, while the app is in the foreground. `remaining` is screenshots
    /// still waiting for their first sort (the fast pass).
    static func submitContinuedIfNeeded(remaining: Int) {
        guard remaining >= continuedThreshold else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: continuedIdentifier,
            title: Brand.Copy.Background.sortingTitle,
            subtitle: Brand.Copy.Background.progress(percent: 0, left: remaining)
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

    /// The first sort only (the fast pass: every screenshot gets its collections, ~2 a second). iOS shows this task
    /// as a banner apps can't shrink, so it should end soon: the slower deep pass (accurate text) and the language
    /// model carry on in the app and overnight. The subtitle follows the percentage, so it changes at most 100 times.
    private static func handleContinued(_ task: BGContinuedProcessingTask) {
        // Read by the expiration handler, which can't await the scheduler
        let state = OSAllocatedUnfairLock(initialState: false)
        /// The task completes once, from whichever side gets here first
        let claimCompletion = { state.withLock { finished -> Bool in
            defer { finished = true }
            return !finished
        } }
        let work = Task { @MainActor in
            guard let scheduler = schedulerProvider?() else {
                if claimCompletion() { task.setTaskCompleted(success: false) }
                return
            }
            var total = max(1, await scheduler.currentProgress().fastRemaining)
            var completed = 0
            var shownPercent = -1
            task.progress.totalUnitCount = Int64(total)
            while !Task.isCancelled {
                let left = await scheduler.currentProgress().fastRemaining
                if left == 0 { break }
                // New screenshots arrived: the job grows, what's done stays done
                if left > total - completed { total = completed + left }
                completed = max(completed, total - left)
                task.progress.totalUnitCount = Int64(total)
                task.progress.completedUnitCount = Int64(completed)
                let percent = completed * 100 / total
                if percent != shownPercent {
                    shownPercent = percent
                    task.updateTitle(Brand.Copy.Background.sortingTitle,
                                     subtitle: Brand.Copy.Background.progress(percent: percent, left: left))
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled, claimCompletion() else { return }
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.updateTitle(Brand.Copy.Background.doneTitle, subtitle: Brand.Copy.Background.doneSubtitle)
            task.setTaskCompleted(success: true)
            if !(await scheduler.currentProgress()).isIdle { scheduleOvernight() }
        }
        task.expirationHandler = {
            work.cancel()
            scheduleOvernight()
            // Cancelled from the banner, or iOS needed the resources: what's sorted is saved, the rest continues next
            // launch or overnight. iOS shows "Task failed" here whatever the app says.
            if claimCompletion() { task.setTaskCompleted(success: false) }
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
