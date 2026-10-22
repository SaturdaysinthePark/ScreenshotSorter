import Foundation
import Testing
@testable import ScreenshotSorter

/// Scheduling rules found on a real device: most screenshots of an "Optimize iPhone Storage"
/// library are iCloud-only, and the language model takes ~2–3 s per request, one at a time.
@Suite(.serialized)
struct SchedulerLaneTests {

    /// Scriptable stand-in for `AnalysisPipeline`.
    actor FakePasses: AnalysisPasses {
        enum Event: Equatable { case fast(String), deep(String), modelStart(String), modelEnd(String) }

        var events: [Event] = []
        var runningModels = 0
        var maxConcurrentModels = 0
        /// ids whose originals are only in iCloud, and which of those have a usable local preview
        var iCloudOnly: Set<String> = []
        var hasPreview: Set<String> = []

        func configure(iCloudOnly: Set<String>, hasPreview: Set<String> = []) {
            self.iCloudOnly = iCloudOnly
            self.hasPreview = hasPreview
        }

        private func record(_ id: String, tier: AnalysisTier, needsNetwork: Bool = false) -> AnalysisRecord {
            var record = AnalysisRecord(id: id, createdAt: Date())
            record.tier = tier
            record.needsNetwork = needsNetwork
            record.visionVersion = PipelineVersion.vision
            return record
        }

        nonisolated func runFast(id: String, createdAt: Date, allowDownloads: Bool) async -> AnalysisPipeline.Result {
            await fast(id, allowDownloads)
        }
        private func fast(_ id: String, _ allowDownloads: Bool) -> AnalysisPipeline.Result {
            events.append(.fast(id))
            if iCloudOnly.contains(id) && !allowDownloads {
                return .finished(record(id, tier: hasPreview.contains(id) ? .fast : .none, needsNetwork: true))
            }
            return .finished(record(id, tier: .fast))
        }

        nonisolated func runDeep(id: String, createdAt: Date, allowDownloads: Bool) async -> AnalysisPipeline.DeepOutcome {
            await deep(id, allowDownloads)
        }
        private func deep(_ id: String, _ allowDownloads: Bool) -> AnalysisPipeline.DeepOutcome {
            events.append(.deep(id))
            if iCloudOnly.contains(id) && !allowDownloads {
                return AnalysisPipeline.DeepOutcome(result: .finished(record(id, tier: .fast, needsNetwork: true)), waitingForNetwork: true)
            }
            return AnalysisPipeline.DeepOutcome(result: .finished(record(id, tier: .deep)), needsModel: true)
        }

        nonisolated func runModel(id: String) async -> (AnalysisPipeline.Result, retryLater: Bool) {
            await modelStart(id)
            try? await Task.sleep(for: .milliseconds(5))
            return await modelEnd(id)
        }
        private func modelStart(_ id: String) {
            events.append(.modelStart(id))
            runningModels += 1
            maxConcurrentModels = max(maxConcurrentModels, runningModels)
        }
        private func modelEnd(_ id: String) -> (AnalysisPipeline.Result, retryLater: Bool) {
            runningModels -= 1
            events.append(.modelEnd(id))
            return (.finished(record(id, tier: .deep)), false)
        }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool
        init(_ value: Bool) { self.value = value }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ newValue: Bool) { lock.lock(); value = newValue; lock.unlock() }
    }

    private func makeScheduler(_ passes: FakePasses, downloads: Flag) throws -> AnalysisScheduler {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("sched-\(UUID().uuidString).sqlite").path
        return AnalysisScheduler(pipeline: passes, store: try AnalysisStore(path: path), downloadsAllowed: { downloads.get() })
    }

    private func items(_ count: Int) -> [(id: String, date: Date)] {
        (0..<count).map { (id: "a\($0)", date: Date().addingTimeInterval(-Double($0))) }
    }

    @Test func languageModelRunsOnlyAfterDeepWorkAndOneAtATime() async throws {
        if !ResourceGovernor.budget(inBackground: false).useLanguageModel { return }
        let passes = FakePasses()
        let scheduler = try makeScheduler(passes, downloads: Flag(true))
        await scheduler.enqueueFast(items(30))
        await scheduler.waitUntilDrained()

        let events = await passes.events
        let lastDeep = events.lastIndex { if case .deep = $0 { return true }; return false } ?? -1
        let firstModel = events.firstIndex { if case .modelStart = $0 { return true }; return false } ?? Int.max
        #expect(events.filter { if case .modelEnd = $0 { return true }; return false }.count == 30)
        #expect(firstModel > lastDeep, "language model started before text and search were done")
        #expect(await passes.maxConcurrentModels == 1)
        let progress = await scheduler.currentProgress()
        #expect(progress.isIdle && progress.modelCompleted == 30 && progress.deepCompleted == 30)
    }

    @Test func screenshotsWithoutATopicReachTheModelFirst() async throws {
        if !ResourceGovernor.budget(inBackground: false).useLanguageModel { return }
        let passes = FakePasses()
        let scheduler = try makeScheduler(passes, downloads: Flag(true))
        let plain = (0..<6).map { (id: "plain\($0)", date: Date().addingTimeInterval(Double($0))) }
        let topicless = (0..<3).map { (id: "feed\($0)", date: Date().addingTimeInterval(-1000 - Double($0))) }
        // Older and queued later, but they have nothing but an app label
        await scheduler.enqueueModel(plain)
        await scheduler.enqueueModel(topicless, first: true)
        await scheduler.waitUntilDrained()
        let order = await passes.events.compactMap { event -> String? in
            if case .modelStart(let id) = event { return id }
            return nil
        }
        #expect(order.count == 9)
        // The first request may already have started before the topic-less batch arrived
        #expect(order.dropFirst().prefix(3).allSatisfy { $0.hasPrefix("feed") } || order.prefix(3).allSatisfy { $0.hasPrefix("feed") })
    }

    @Test func iCloudScreenshotsWaitForWiFiThenResume() async throws {
        let passes = FakePasses()
        let downloads = Flag(false)
        let scheduler = try makeScheduler(passes, downloads: downloads)
        let all = items(20)
        // 15 iCloud-only (5 of them with a usable local preview), 5 local
        let cloud = Set(all.prefix(15).map(\.id))
        await passes.configure(iCloudOnly: cloud, hasPreview: Set(all.prefix(5).map(\.id)))
        await scheduler.enqueueFast(all)
        await scheduler.waitUntilDrained()

        var progress = await scheduler.currentProgress()
        #expect(progress.isIdle, "parked items must not keep the queue busy")
        #expect(progress.waitingForNetwork == 15)
        // Parking is not failing: nothing should have been tried more than once per lane
        let deepTries = await passes.events.filter { if case .deep(let id) = $0 { return cloud.contains(id) }; return false }.count
        #expect(deepTries == 5, "only preview-sorted items reach the deep lane before Wi-Fi")

        downloads.set(true)
        await scheduler.networkChanged(allowsDownloads: true)
        await scheduler.waitUntilDrained()
        progress = await scheduler.currentProgress()
        #expect(progress.waitingForNetwork == 0)
        let deepDone = await passes.events.filter { if case .deep(let id) = $0 { return cloud.contains(id) }; return false }.count
        #expect(deepDone == 5 + 15, "every iCloud screenshot gets its full-resolution pass on Wi-Fi")
    }
}
