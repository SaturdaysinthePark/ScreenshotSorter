import Foundation
import os

struct AnalysisProgress: Sendable, Equatable {
    var fastRemaining: Int = 0
    var deepRemaining: Int = 0
    var fastCompleted: Int = 0
    var deepCompleted: Int = 0
    var isPaused: Bool = false
    var isRunning: Bool = false
    var itemsPerSecond: Double = 0

    var isIdle: Bool { fastRemaining == 0 && deepRemaining == 0 }
}

enum SchedulerEvent: Sendable {
    case records([RecordSummary], full: [AnalysisRecord])
    case progress(AnalysisProgress)
}

/// Bounded-concurrency work queue for the analysis pipeline.
///
/// - Sliding window: a new item starts as soon as any finishes (no batch barriers).
/// - Priorities: urgent (visible / opened / new) → fast backlog (newest first) → deep backlog.
/// - Deep work only runs once fast coverage is nearly complete, so the whole library gets
///   categories quickly.
/// - Results are written to the store in batches and published as events.
actor AnalysisScheduler {
    private enum Lane: Sendable { case fast, deep }

    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "Scheduler")
    static let flushInterval: TimeInterval = 0.25
    static let flushBatchSize = 25
    /// Deep work starts once fewer than this many fast items remain
    static let deepStartThreshold = 12

    private let pipeline: AnalysisPipeline
    private let store: AnalysisStore

    private var urgent: [String] = []
    private var fastQueue: [String] = []
    private var fastIndex = 0
    private var deepQueue: [String] = []
    private var deepIndex = 0
    private var queuedFast = Set<String>()
    private var queuedDeep = Set<String>()
    private var inFlight = Set<String>()
    private var dates: [String: Date] = [:]
    private var removed = Set<String>()

    private var paused = false
    private var inBackground = false
    private var runTask: Task<Void, Never>?
    private var wakeContinuation: CheckedContinuation<Void, Never>?
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    private var pending: [AnalysisRecord] = []
    /// Flushes are chained so batches reach the store and UI in order
    private var flushTask: Task<Void, Never>?
    private var lastFlush = Date.distantPast
    private var progress = AnalysisProgress()
    private var lastProgressEmit = Date.distantPast
    private var completionTimes: [Date] = []
    private var modelRetryIDs: [String] = []

    nonisolated let events: AsyncStream<SchedulerEvent>
    private let eventContinuation: AsyncStream<SchedulerEvent>.Continuation

    init(pipeline: AnalysisPipeline, store: AnalysisStore) {
        self.pipeline = pipeline
        self.store = store
        var continuation: AsyncStream<SchedulerEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation = $0 }
        self.eventContinuation = continuation
    }

    // MARK: - Public API

    /// Queue items for the fast pass (newest first unless `urgent`).
    func enqueueFast(_ items: [(id: String, date: Date)], urgent isUrgent: Bool = false) {
        for item in items {
            dates[item.id] = item.date
            removed.remove(item.id)
        }
        let fresh = items.filter { !queuedFast.contains($0.id) }.sorted { $0.date > $1.date }
        for item in fresh { queuedFast.insert(item.id) }
        if isUrgent {
            urgent.insert(contentsOf: fresh.map(\.id), at: 0)
        } else {
            fastQueue.append(contentsOf: fresh.map(\.id))
        }
        updateCounts()
        wake()
        start()
    }

    func enqueueDeep(_ items: [(id: String, date: Date)]) {
        for item in items {
            dates[item.id] = item.date
            removed.remove(item.id)
        }
        let fresh = items.filter { !queuedDeep.contains($0.id) }.sorted { $0.date > $1.date }
        for item in fresh { queuedDeep.insert(item.id) }
        deepQueue.append(contentsOf: fresh.map(\.id))
        updateCounts()
        wake()
        start()
    }

    /// Move queued items to the front (e.g. cells scrolled into view).
    func boost(_ ids: [String]) {
        let boostable = ids.filter { queuedFast.contains($0) && !inFlight.contains($0) && !urgent.contains($0) }
        guard !boostable.isEmpty else { return }
        urgent.append(contentsOf: boostable)
        wake()
    }

    func remove(_ ids: [String]) {
        removed.formUnion(ids)
        for id in ids {
            queuedFast.remove(id)
            queuedDeep.remove(id)
        }
        updateCounts()
    }

    func setPaused(_ value: Bool) {
        paused = value
        progress.isPaused = value
        emitProgress(force: true)
        if !value { wake() }
    }

    func setInBackground(_ value: Bool) {
        inBackground = value
        wake()
    }

    func currentProgress() -> AnalysisProgress { progress }

    /// Suspends until both queues are empty (used by background tasks).
    func waitUntilDrained() async {
        if progress.isIdle && inFlight.isEmpty { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    func cancelAll() {
        runTask?.cancel()
        runTask = nil
        progress.isRunning = false
        wake()
    }

    // MARK: - Run loop

    private func start() {
        guard runTask == nil else { return }
        progress.isRunning = true
        runTask = Task(priority: .utility) { [weak self] in
            await self?.run()
        }
    }

    private func wake() {
        if let continuation = wakeContinuation {
            wakeContinuation = nil
            continuation.resume()
        }
    }

    private func waitForWork() async {
        await withCheckedContinuation { continuation in
            wakeContinuation = continuation
        }
    }

    private func nextFast() -> String? {
        while let id = urgent.first {
            urgent.removeFirst()
            if queuedFast.contains(id) && !inFlight.contains(id) && !removed.contains(id) { return id }
        }
        while fastIndex < fastQueue.count {
            let id = fastQueue[fastIndex]
            fastIndex += 1
            if queuedFast.contains(id) && !inFlight.contains(id) && !removed.contains(id) { return id }
        }
        if fastIndex > 0 && fastIndex >= fastQueue.count {
            fastQueue.removeAll(keepingCapacity: true)
            fastIndex = 0
        }
        return nil
    }

    private func nextDeep() -> String? {
        while deepIndex < deepQueue.count {
            let id = deepQueue[deepIndex]
            deepIndex += 1
            // Never deep-analyze something still waiting for its fast pass
            if queuedDeep.contains(id) && !queuedFast.contains(id) && !inFlight.contains(id) && !removed.contains(id) { return id }
        }
        if deepIndex > 0 && deepIndex >= deepQueue.count {
            deepQueue.removeAll(keepingCapacity: true)
            deepIndex = 0
        }
        return nil
    }

    private func run() async {
        await withTaskGroup(of: Lane.self) { group in
            var runningFast = 0
            var runningDeep = 0

            while !Task.isCancelled {
                if paused {
                    if runningFast + runningDeep == 0 {
                        flush(force: true)
                        await waitForWork()
                        continue
                    }
                } else {
                    let budget = ResourceGovernor.budget(inBackground: inBackground)
                    while runningFast < budget.fastConcurrency, let id = nextFast() {
                        runningFast += 1
                        inFlight.insert(id)
                        let date = dates[id] ?? Date()
                        let pipeline = self.pipeline
                        group.addTask {
                            let result = await pipeline.runFast(id: id, createdAt: date)
                            await self.completeFast(id: id, result: result)
                            return .fast
                        }
                    }
                    let fastBacklog = queuedFast.count
                    while runningDeep < budget.deepConcurrency, fastBacklog < AnalysisScheduler.deepStartThreshold, let id = nextDeep() {
                        runningDeep += 1
                        inFlight.insert(id)
                        let date = dates[id] ?? Date()
                        let pipeline = self.pipeline
                        let useModel = budget.useLanguageModel
                        group.addTask {
                            let (result, retryModel) = await pipeline.runDeep(id: id, createdAt: date, useLanguageModel: useModel)
                            await self.completeDeep(id: id, result: result, retryModel: retryModel)
                            return .deep
                        }
                    }
                }

                if runningFast + runningDeep == 0 {
                    flush(force: true)
                    notifyDrainedIfIdle()
                    await waitForWork()
                    continue
                }

                if let lane = await group.next() {
                    switch lane {
                    case .fast: runningFast -= 1
                    case .deep: runningDeep -= 1
                    }
                }
            }
            group.cancelAll()
        }
        flush(force: true)
        runTask = nil
        progress.isRunning = false
        emitProgress(force: true)
    }

    // MARK: - Completion

    private func completeFast(id: String, result: AnalysisPipeline.Result) {
        inFlight.remove(id)
        guard !removed.contains(id) else { return }
        queuedFast.remove(id)
        // Already deep-queued items were skipped by `nextDeep` while their fast pass was pending,
        // so they must be re-appended or they'd stay in `queuedDeep` forever (never idle).
        var continueToDeep = queuedDeep.contains(id)
        if case .finished(let record) = result {
            pending.append(record)
            progress.fastCompleted += 1
            completionTimes.append(Date())
            // Every successfully seen item continues to the deep lane
            if record.tier != .failed && record.tier != .deep {
                continueToDeep = true
            }
        }
        if continueToDeep {
            queuedDeep.insert(id)
            deepQueue.append(id)
        }
        afterCompletion()
    }

    private func completeDeep(id: String, result: AnalysisPipeline.Result, retryModel: Bool) {
        inFlight.remove(id)
        guard !removed.contains(id) else { return }
        queuedDeep.remove(id)
        if case .finished(let record) = result {
            pending.append(record)
            progress.deepCompleted += 1
            completionTimes.append(Date())
        }
        if retryModel { modelRetryIDs.append(id) }
        // Re-queued for a fast pass while in flight (e.g. edited): `nextFast` skipped it then
        if queuedFast.contains(id) { urgent.append(id) }
        afterCompletion()
    }

    private func afterCompletion() {
        updateCounts()
        flush(force: false)
        emitProgress(force: false)
    }

    private func updateCounts() {
        progress.fastRemaining = queuedFast.count
        progress.deepRemaining = queuedDeep.count
        let cutoff = Date().addingTimeInterval(-10)
        completionTimes.removeAll { $0 < cutoff }
        progress.itemsPerSecond = Double(completionTimes.count) / 10
    }

    private func flush(force: Bool) {
        guard !pending.isEmpty else { return }
        let due = force || pending.count >= AnalysisScheduler.flushBatchSize ||
            Date().timeIntervalSince(lastFlush) >= AnalysisScheduler.flushInterval
        guard due else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        lastFlush = Date()
        let store = self.store
        let continuation = self.eventContinuation
        let previous = flushTask
        flushTask = Task(priority: .utility) {
            await previous?.value
            await store.upsert(batch)
            continuation.yield(.records(batch.map(\.summaryValue), full: batch))
        }
    }

    private func emitProgress(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastProgressEmit) >= 0.3 else { return }
        lastProgressEmit = now
        eventContinuation.yield(.progress(progress))
    }

    private func notifyDrainedIfIdle() {
        updateCounts()
        emitProgress(force: true)
        guard progress.isIdle else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        // Language-model retries are picked up by the next deep run (e.g. overnight task)
        if !modelRetryIDs.isEmpty {
            AnalysisScheduler.logger.info("\(self.modelRetryIDs.count) items deferred for the language model")
            modelRetryIDs.removeAll()
        }
    }
}
