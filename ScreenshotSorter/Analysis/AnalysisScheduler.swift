import Foundation
import os

struct AnalysisProgress: Sendable, Equatable {
    var fastRemaining: Int = 0
    var deepRemaining: Int = 0
    var fastCompleted: Int = 0
    var deepCompleted: Int = 0
    /// Language-model passes (titles, summaries, tags) that run after text and search are done
    var modelRemaining: Int = 0
    var modelCompleted: Int = 0
    /// iCloud-only screenshots parked until downloads are allowed (Wi-Fi, no Low Data Mode)
    var waitingForNetwork: Int = 0
    var isPaused: Bool = false
    var isRunning: Bool = false
    var itemsPerSecond: Double = 0

    /// Nothing runnable is left (items waiting for Wi-Fi don't count: they can't run yet)
    var isIdle: Bool { fastRemaining == 0 && deepRemaining == 0 && modelRemaining == 0 }
}

enum SchedulerEvent: Sendable {
    case records([RecordSummary], full: [AnalysisRecord])
    case progress(AnalysisProgress)
}

/// Bounded-concurrency work queue for the analysis pipeline.
///
/// - Sliding window: a new item starts as soon as any finishes (no batch barriers).
/// - Priorities: urgent (visible / opened / new) → fast backlog (newest first) → deep backlog →
///   language model.
/// - Deep work only runs once fast coverage is nearly complete, so the whole library gets
///   categories quickly; the language model only once deep work is done (it handles one request
///   at a time system-wide and would otherwise hold text and search back by hours).
/// - iCloud-only items are parked while `NetworkPolicy` disallows downloads and re-queued when it
///   allows them again (`networkChanged`).
/// - Results are written to the store in batches and published as events.
actor AnalysisScheduler {
    private enum Lane: Sendable { case fast, deep, model }

    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "Scheduler")
    static let flushInterval: TimeInterval = 0.25
    static let flushBatchSize = 25
    /// Deep work starts once fewer than this many fast items remain
    static let deepStartThreshold = 12

    private let pipeline: any AnalysisPasses
    private let store: AnalysisStore
    private let downloadsAllowed: @Sendable () -> Bool

    private var urgent: [String] = []
    private var fastQueue: [String] = []
    private var fastIndex = 0
    private var deepQueue: [String] = []
    private var deepIndex = 0
    private var modelQueue: [String] = []
    private var modelIndex = 0
    private var queuedFast = Set<String>()
    private var queuedDeep = Set<String>()
    private var queuedModel = Set<String>()
    /// Parked until downloads are allowed: no usable local preview yet / full-resolution pass pending
    private var parkedFast = Set<String>()
    private var parkedDeep = Set<String>()
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
    // Throughput logging (Console: subsystem sabtain.ScreenshotSorter, category Scheduler)
    private var lastThroughputLog = Date.distantPast
    private var runStartedAt: Date?
    private var lastBudget: AnalysisBudget?
    private var failedCount = 0
    private var completionTimes: [Date] = []
    private var modelRetryIDs: [String] = []

    nonisolated let events: AsyncStream<SchedulerEvent>
    private let eventContinuation: AsyncStream<SchedulerEvent>.Continuation

    init(pipeline: any AnalysisPasses, store: AnalysisStore,
         downloadsAllowed: @escaping @Sendable () -> Bool = { NetworkPolicy.shared.allowsICloudDownloads }) {
        self.pipeline = pipeline
        self.store = store
        self.downloadsAllowed = downloadsAllowed
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

    /// Queue language-model passes (records that already have deep features).
    func enqueueModel(_ items: [(id: String, date: Date)]) {
        for item in items {
            dates[item.id] = item.date
            removed.remove(item.id)
        }
        let fresh = items.filter { !queuedModel.contains($0.id) }.sorted { $0.date > $1.date }
        for item in fresh { queuedModel.insert(item.id) }
        modelQueue.append(contentsOf: fresh.map(\.id))
        updateCounts()
        wake()
        start()
    }

    /// Downloads became allowed (or disallowed). Parked items go back to their lanes when allowed.
    func networkChanged(allowsDownloads: Bool) {
        guard allowsDownloads, !(parkedFast.isEmpty && parkedDeep.isEmpty) else { return }
        let fast = parkedFast.map { (id: $0, date: dates[$0] ?? .distantPast) }
        let deep = parkedDeep.map { (id: $0, date: dates[$0] ?? .distantPast) }
        AnalysisScheduler.logger.notice("Wi-Fi back: resuming \(fast.count + deep.count) iCloud screenshots")
        parkedFast.removeAll()
        parkedDeep.removeAll()
        if !fast.isEmpty { enqueueFast(fast) }
        if !deep.isEmpty { enqueueDeep(deep) }
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
            queuedModel.remove(id)
            parkedFast.remove(id)
            parkedDeep.remove(id)
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

    private func nextModel() -> String? {
        while modelIndex < modelQueue.count {
            let id = modelQueue[modelIndex]
            modelIndex += 1
            if queuedModel.contains(id) && !inFlight.contains(id) && !removed.contains(id) { return id }
        }
        if modelIndex > 0 && modelIndex >= modelQueue.count {
            modelQueue.removeAll(keepingCapacity: true)
            modelIndex = 0
        }
        return nil
    }

    private func run() async {
        await withTaskGroup(of: Lane.self) { group in
            var runningFast = 0
            var runningDeep = 0
            var runningModel = 0

            while !Task.isCancelled {
                if paused {
                    if runningFast + runningDeep + runningModel == 0 {
                        flush(force: true)
                        await waitForWork()
                        continue
                    }
                } else {
                    let budget = ResourceGovernor.budget(inBackground: inBackground)
                    if budget != lastBudget {
                        AnalysisScheduler.logger.notice("Budget fast×\(budget.fastConcurrency) (×\(budget.fastDownloadConcurrency) downloading) deep×\(budget.deepConcurrency) model=\(budget.useLanguageModel) background=\(self.inBackground) thermal=\(ProcessInfo.processInfo.thermalState.rawValue) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
                        lastBudget = budget
                    }
                    let allowDownloads = downloadsAllowed()
                    while runningFast < budget.fastLimit(downloading: allowDownloads), let id = nextFast() {
                        runningFast += 1
                        inFlight.insert(id)
                        let date = dates[id] ?? Date()
                        let pipeline = self.pipeline
                        group.addTask {
                            let result = await pipeline.runFast(id: id, createdAt: date, allowDownloads: allowDownloads)
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
                        group.addTask {
                            let outcome = await pipeline.runDeep(id: id, createdAt: date, allowDownloads: allowDownloads)
                            await self.completeDeep(id: id, outcome: outcome)
                            return .deep
                        }
                    }
                    // One at a time (the model serialises requests anyway), after text and search are done
                    if budget.useLanguageModel, runningModel == 0, fastBacklog < AnalysisScheduler.deepStartThreshold,
                       queuedDeep.isEmpty, let id = nextModel() {
                        runningModel += 1
                        inFlight.insert(id)
                        let pipeline = self.pipeline
                        group.addTask {
                            let (result, retryLater) = await pipeline.runModel(id: id)
                            await self.completeModel(id: id, result: result, retryLater: retryLater)
                            return .model
                        }
                    }
                }

                if runningFast + runningDeep + runningModel == 0 {
                    flush(force: true)
                    notifyDrainedIfIdle()
                    await waitForWork()
                    continue
                }

                if let lane = await group.next() {
                    switch lane {
                    case .fast: runningFast -= 1
                    case .deep: runningDeep -= 1
                    case .model: runningModel -= 1
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
            if record.tier == .failed { failedCount += 1 }
            progress.fastCompleted += 1
            completionTimes.append(Date())
            if record.needsNetwork && record.tier == .none {
                // iCloud-only without a usable preview: wait for Wi-Fi instead of retrying
                queuedDeep.remove(id)
                continueToDeep = false
                park(id, fast: true)
            } else if record.tier != .failed && record.tier != .deep {
                // Every successfully seen item continues to the deep lane
                continueToDeep = true
            }
        }
        if continueToDeep {
            queuedDeep.insert(id)
            deepQueue.append(id)
        }
        afterCompletion()
    }

    private func completeDeep(id: String, outcome: AnalysisPipeline.DeepOutcome) {
        inFlight.remove(id)
        guard !removed.contains(id) else { return }
        queuedDeep.remove(id)
        if outcome.waitingForNetwork {
            park(id, fast: false)
        } else if case .finished(let record) = outcome.result {
            pending.append(record)
            progress.deepCompleted += 1
            completionTimes.append(Date())
            if outcome.needsModel, !queuedModel.contains(id) {
                queuedModel.insert(id)
                modelQueue.append(id)
            }
        }
        // Re-queued for a fast pass while in flight (e.g. edited): `nextFast` skipped it then
        if queuedFast.contains(id) { urgent.append(id) }
        afterCompletion()
    }

    private func completeModel(id: String, result: AnalysisPipeline.Result, retryLater: Bool) {
        inFlight.remove(id)
        guard !removed.contains(id) else { return }
        queuedModel.remove(id)
        if case .finished(let record) = result {
            pending.append(record)
            progress.modelCompleted += 1
            completionTimes.append(Date())
        }
        if retryLater { modelRetryIDs.append(id) }
        if queuedFast.contains(id) { urgent.append(id) }
        afterCompletion()
    }

    /// Wait for downloads — unless Wi-Fi came back while this item was in flight.
    private func park(_ id: String, fast: Bool) {
        if downloadsAllowed() {
            let item = [(id: id, date: dates[id] ?? .distantPast)]
            if fast { enqueueFast(item) } else { enqueueDeep(item) }
        } else if fast {
            parkedFast.insert(id)
        } else {
            parkedDeep.insert(id)
        }
    }

    private func afterCompletion() {
        updateCounts()
        flush(force: false)
        emitProgress(force: false)
    }

    private func updateCounts() {
        progress.fastRemaining = queuedFast.count
        progress.deepRemaining = queuedDeep.count
        progress.modelRemaining = queuedModel.count
        progress.waitingForNetwork = parkedFast.count + parkedDeep.count
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
        logThroughputIfDue(now)
        guard force || now.timeIntervalSince(lastProgressEmit) >= 0.3 else { return }
        lastProgressEmit = now
        eventContinuation.yield(.progress(progress))
    }

    private func logThroughputIfDue(_ now: Date) {
        if progress.isIdle {
            if let started = runStartedAt {
                let p = progress
                AnalysisScheduler.logger.notice("Sorting idle after \(Int(now.timeIntervalSince(started)))s: fast \(p.fastCompleted) deep \(p.deepCompleted) model \(p.modelCompleted) failed \(self.failedCount) waiting for Wi-Fi \(p.waitingForNetwork)")
                runStartedAt = nil
            }
            return
        }
        if runStartedAt == nil { runStartedAt = now }
        guard now.timeIntervalSince(lastThroughputLog) >= 10 else { return }
        lastThroughputLog = now
        let p = progress
        // Strings need `.public` or Console shows <private>
        AnalysisScheduler.logger.notice("Sorting: fast \(p.fastCompleted) done / \(p.fastRemaining) left, deep \(p.deepCompleted) / \(p.deepRemaining), model \(p.modelCompleted) / \(p.modelRemaining), \(String(format: "%.1f", p.itemsPerSecond), privacy: .public)/s, waiting for Wi-Fi \(p.waitingForNetwork), failed \(self.failedCount), paused \(p.isPaused)")
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
