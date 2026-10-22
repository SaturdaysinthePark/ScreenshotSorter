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
            title: "Sorting screenshots",
            subtitle: "\(remaining) to go"
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

    private static func handleContinued(_ task: BGContinuedProcessingTask) {
        let work = Task { @MainActor in
            guard let scheduler = schedulerProvider?() else {
                task.setTaskCompleted(success: false)
                return
            }
            await scheduler.setInBackground(true)
            let start = await scheduler.currentProgress()
            let total = max(1, start.fastRemaining + start.deepRemaining + start.modelRemaining)
            task.progress.totalUnitCount = Int64(total)

            let reporter = Task { @MainActor in
                while !Task.isCancelled {
                    let current = await scheduler.currentProgress()
                    let remaining = current.fastRemaining + current.deepRemaining + current.modelRemaining
                    task.progress.completedUnitCount = Int64(max(0, total - remaining))
                    task.updateTitle("Sorting screenshots", subtitle: "\(remaining) to go")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            await scheduler.waitUntilDrained()
            reporter.cancel()
            task.progress.completedUnitCount = Int64(total)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            // Whatever is left continues next launch or in the overnight window
            work.cancel()
            scheduleOvernight()
            task.setTaskCompleted(success: false)
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
