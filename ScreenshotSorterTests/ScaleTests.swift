import Foundation
import Photos
import Testing
@testable import ScreenshotSorter

/// Libraries of 2,000–25,000 screenshots are normal. These tests build synthetic libraries at
/// that size and hold the hot paths to time budgets, so a change that makes something O(n) per
/// frame (or O(n²) per batch) fails here instead of as a janky phone.
///
/// Budgets are for the simulator on a Mac and leave ~3× headroom for a phone; timings are printed
/// (`swift test` / Xcode report) so regressions are visible before they fail.
@Suite(.serialized)
struct ScaleTests {
    static let librarySize = 25_000

    // MARK: Synthetic data

    private static let words = """
        receipt total order delivery flight gate boarding coffee latte recipe ingredients meeting \
        agenda invoice payment balance transfer weather forecast rain sunny tickets concert venue \
        message reply photo album playlist song artist movie episode season game level score team \
        password wifi network settings privacy update error failed connect server address street \
        avenue directions minutes miles restaurant menu dinner lunch breakfast shoes jacket dress
        """.split(separator: " ").map(String.init)

    private static let categories: [ScreenshotCategory] = ScreenshotCategory.assignable.filter { $0 != .other }

    static func text(_ seed: Int, words count: Int = 40) -> String {
        var generator = SeededGenerator(seed: UInt64(seed))
        return (0..<count).map { _ in words[Int.random(in: 0..<words.count, using: &generator)] }.joined(separator: " ")
    }

    static func summaries(count: Int, analyzed: Bool) -> [RecordSummary] {
        let now = Date()
        return (0..<count).map { index in
            let first = categories[index % categories.count]
            let second = categories[(index * 7 + 3) % categories.count]
            return RecordSummary(
                id: "asset-\(index)",
                creationDate: now.addingTimeInterval(-Double(index) * 600),
                tier: analyzed ? .fast : .none,
                categories: analyzed ? [ScoredCategory(category: first, score: 0.8, sources: .ocrRules),
                                        ScoredCategory(category: second, score: 0.6, sources: .visionClassifier)] : [],
                tags: analyzed ? ["tag\(index % 50)"] : [],
                app: nil, title: "Screenshot \(index)", isReviewed: false)
        }
    }

    @MainActor
    static func library(count: Int, analyzed: Bool) -> LibraryStore {
        let placeholder = PHAsset()
        let store = LibraryStore()
        store.reset(screenshots: summaries(count: count, analyzed: analyzed).map {
            Screenshot(id: $0.id, asset: placeholder, creationDate: $0.creationDate, summary: $0)
        })
        return store
    }

    static func record(_ index: Int, dimension: Int = 512) -> AnalysisRecord {
        var record = AnalysisRecord(id: "asset-\(index)", createdAt: Date().addingTimeInterval(-Double(index) * 600))
        record.tier = .deep
        record.visionVersion = PipelineVersion.vision
        record.rulesVersion = PipelineVersion.rules
        record.ocrText = text(index)
        record.title = "Screenshot \(index)"
        record.categories = [ScoredCategory(category: categories[index % categories.count], score: 0.8, sources: .ocrRules)]
        record.tags = [ScreenshotTag(value: "tag\(index % 50)", score: 0.7, sources: .ocrRules)]
        record.embedding = vector(index, dimension: dimension)
        record.embeddingModel = "scale-test"
        return record
    }

    static func vector(_ seed: Int, dimension: Int) -> [Float] {
        var generator = SeededGenerator(seed: UInt64(seed) &+ 99)
        var v = (0..<dimension).map { _ in Float.random(in: -1...1, using: &generator) }
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        for i in v.indices { v[i] /= norm }
        return v
    }

    static func measure(_ label: String, _ body: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        let elapsed = try clock.measure(body)
        print("⏱ \(label): \(elapsed.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 2))))")
        return elapsed
    }

    static func measure(_ label: String, _ body: () async throws -> Void) async rethrows -> Duration {
        let clock = ContinuousClock()
        let elapsed = try await clock.measure(body)
        print("⏱ \(label): \(elapsed.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 2))))")
        return elapsed
    }

    // MARK: Main-actor work per frame / per batch

    /// What the home screen reads on every render while sorting (progress card, "All Screenshots" row,
    /// the collection grid in frozen shelf order, and "+N new" per tile since a visit a day ago).
    @MainActor
    static func homeRender(_ library: LibraryStore, ranking: ShelfRanking = ShelfRanking()) {
        _ = library.analyzedCount
        _ = library.analyzedCount
        _ = library.preview(for: .all).screenshots
        let tiles = ranking.shelves(library.categoryCollections(sort: .imageCount)).flatMap(\.collections)
        let visit = Date().addingTimeInterval(-86_400)
        for tile in tiles {
            _ = tile.screenshots.prefix(3); _ = tile.count
            for id in library.ids(for: tile.kind) {
                guard let date = library.screenshot(id: id)?.creationDate, date > visit else { break }
            }
        }
    }

    @Test @MainActor func homeRenderStaysFlatAtLargeLibrarySizes() {
        let library = ScaleTests.library(count: ScaleTests.librarySize, analyzed: true)
        let ranking = ShelfRanking(library.categoryCollections(sort: .imageCount))
        ScaleTests.homeRender(library, ranking: ranking) // warm caches
        let renders = 30
        let total = ScaleTests.measure("home render ×\(renders) at \(ScaleTests.librarySize)") {
            for _ in 0..<renders { ScaleTests.homeRender(library, ranking: ranking) }
        }
        let perRender = total / renders
        print("⏱ per home render: \(perRender)")
        // One 120 Hz frame is 8.3 ms; the home body must stay well inside it on a phone.
        #expect(perRender < .milliseconds(2), "home render takes \(perRender) at \(ScaleTests.librarySize) screenshots")
    }

    @Test @MainActor func analysisBatchesStayCheapWhileSorting() {
        let library = ScaleTests.library(count: ScaleTests.librarySize, analyzed: false)
        let updates = ScaleTests.summaries(count: ScaleTests.librarySize, analyzed: true)
        let batch = AnalysisScheduler.flushBatchSize
        var worst: Duration = .zero
        let clock = ContinuousClock()
        let total = ScaleTests.measure("apply \(ScaleTests.librarySize) results in batches of \(batch) + home render each") {
            var index = 0
            while index < updates.count {
                let slice = Array(updates[index..<min(index + batch, updates.count)])
                index += batch
                let elapsed = clock.measure {
                    library.apply(slice)
                    ScaleTests.homeRender(library)
                }
                worst = max(worst, elapsed)
            }
        }
        let batches = (updates.count + batch - 1) / batch
        print("⏱ per batch: \(total / batches) · worst \(worst)")
        #expect(library.analyzedCount == ScaleTests.librarySize)
        #expect(total / batches < .milliseconds(3), "each flush costs \(total / batches) on the main actor")
    }

    /// The All Screenshots grid is open during a first sort and re-reads its items on every flush.
    @Test @MainActor func galleryReadsStayCheapWhileSorting() {
        let library = ScaleTests.library(count: ScaleTests.librarySize, analyzed: false)
        let updates = ScaleTests.summaries(count: 2_500, analyzed: true)
        let batch = AnalysisScheduler.flushBatchSize
        let batches = updates.count / batch
        let total = ScaleTests.measure("apply + gallery read ×\(batches) at \(ScaleTests.librarySize)") {
            let version = library.orderVersion(for: .all)
            let visible = library.ids(for: .all).prefix(40)
            for index in 0..<batches {
                library.apply(Array(updates[index * batch..<(index + 1) * batch]))
                // What the gallery does per batch: layout cache hit, visible cells re-read, header count
                #expect(library.orderVersion(for: .all) == version)
                for id in visible { _ = library.screenshot(id: id)?.tier }
                _ = library.count - library.analyzedCount
            }
        }
        print("⏱ per batch with gallery open: \(total / batches)")
        #expect(total / batches < .milliseconds(1), "gallery refresh costs \(total / batches) per flush")
    }

    /// Cached orderings are patched in place on every batch; they must equal a fresh sort.
    @Test @MainActor func incrementalOrderingMatchesFullSort() {
        let count = 2_000
        let library = ScaleTests.library(count: count, analyzed: true)
        for category in ScaleTests.categories { _ = library.preview(for: .category(category)) } // populate caches
        var generator = SeededGenerator(seed: 42)
        let now = Date()
        for round in 0..<40 {
            let batch: [RecordSummary] = (0..<25).map { _ in
                let index = Int.random(in: 0..<count, using: &generator)
                let category = ScaleTests.categories[Int.random(in: 0..<ScaleTests.categories.count, using: &generator)]
                return RecordSummary(id: "asset-\(index)", creationDate: now.addingTimeInterval(-Double(index) * 600), tier: .deep,
                                     categories: [ScoredCategory(category: category, score: 0.9, sources: .ocrRules)],
                                     tags: [], app: nil, title: "r\(round)", isReviewed: false)
            }
            library.apply(batch)
        }
        let placeholder = PHAsset()
        let fresh = LibraryStore()
        fresh.reset(screenshots: library.allScreenshots.map {
            Screenshot(id: $0.id, asset: placeholder, creationDate: $0.creationDate,
                       summary: RecordSummary(id: $0.id, creationDate: $0.creationDate, tier: $0.tier,
                                              categories: $0.categoriesWithConfidence.map { ScoredCategory(category: $0.category, score: $0.score, sources: .ocrRules) },
                                              tags: [], app: nil, title: nil, isReviewed: false))
        })
        for category in ScaleTests.categories {
            #expect(library.screenshots(for: .category(category)).map(\.id) == fresh.screenshots(for: .category(category)).map(\.id), "\(category.key)")
        }
        #expect(library.analyzedCount == fresh.analyzedCount)
    }

    /// Sorting changes what screenshots are *about*, not which exist or their order, so the All
    /// Screenshots grid must not rebuild its layout during a first sort.
    @Test @MainActor func gridLayoutVersionIsStableWhileSorting() {
        let library = ScaleTests.library(count: ScaleTests.librarySize, analyzed: false)
        let all = library.orderVersion(for: .all)
        let category = ScaleTests.categories[0]
        let categoryBefore = library.orderVersion(for: .category(category))
        let updates = ScaleTests.summaries(count: 2_000, analyzed: true)
        for start in stride(from: 0, to: updates.count, by: AnalysisScheduler.flushBatchSize) {
            library.apply(Array(updates[start..<min(start + AnalysisScheduler.flushBatchSize, updates.count)]))
        }
        #expect(library.orderVersion(for: .all) == all)
        #expect(library.orderVersion(for: .category(category)) != categoryBefore)
    }

    /// Month sections are computed once per boundary; they must match per-item calendar math.
    @Test func gallerySectionsMatchReferenceAndScale() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        // Newest first, every 37 minutes back over ~2 years, crossing today/yesterday/week/month/year
        let dates: [String: Date] = Dictionary(uniqueKeysWithValues: (0..<ScaleTests.librarySize).map {
            ("asset-\($0)", now.addingTimeInterval(-Double($0) * 37 * 60))
        })
        let ids = (0..<ScaleTests.librarySize).map { "asset-\($0)" }
        var sections: [GallerySection] = []
        let elapsed = ScaleTests.measure("GallerySection.make \(ids.count)") {
            sections = GallerySection.make(ids: ids, date: { dates[$0]! }, groupByDate: true, now: now, calendar: calendar)
        }
        #expect(sections.flatMap(\.ids) == ids)
        #expect(elapsed < .milliseconds(60), "sectioning takes \(elapsed)")

        // Reference: classify each date on its own
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday)!
        func key(_ date: Date) -> String {
            if date >= startOfToday { return "today" }
            if date >= startOfYesterday { return "yesterday" }
            if date >= startOfWeek { return "week" }
            let c = calendar.dateComponents([.year, .month], from: date)
            return "m-\(c.year!)-\(c.month!)"
        }
        var expected: [(String, Int)] = []
        for id in ids {
            let k = key(dates[id]!)
            if expected.last?.0 == k { expected[expected.count - 1].1 += 1 } else { expected.append((k, 1)) }
        }
        #expect(sections.map(\.id) == expected.map(\.0))
        #expect(sections.map(\.ids.count) == expected.map(\.1))
    }

    @Test @MainActor func resetLoadsLargeLibraryQuickly() {
        let summaries = ScaleTests.summaries(count: ScaleTests.librarySize, analyzed: true)
        let placeholder = PHAsset()
        let screenshots = summaries.map { Screenshot(id: $0.id, asset: placeholder, creationDate: $0.creationDate, summary: $0) }
        let library = LibraryStore()
        let elapsed = ScaleTests.measure("LibraryStore.reset \(ScaleTests.librarySize)") {
            library.reset(screenshots: screenshots)
        }
        #expect(library.count == ScaleTests.librarySize)
        #expect(elapsed < .milliseconds(400))
    }

    // MARK: Persistence and search

    @Test func storeAndSearchScale() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("scale-\(UUID().uuidString).sqlite").path
        let store = try AnalysisStore(path: path)
        let records = (0..<ScaleTests.librarySize).map { ScaleTests.record($0, dimension: 64) }

        // Flush-sized writes, like the scheduler during a first sort
        let batch = AnalysisScheduler.flushBatchSize
        let writes = await ScaleTests.measure("upsert \(records.count) in batches of \(batch)") {
            var index = 0
            while index < records.count {
                await store.upsert(Array(records[index..<min(index + batch, records.count)]))
                index += batch
            }
        }
        #expect(writes < .seconds(30))

        var summaries: [RecordSummary] = []
        let load = await ScaleTests.measure("loadSummaries \(records.count)") { summaries = await store.loadSummaries() }
        #expect(summaries.count == records.count)
        #expect(load < .seconds(2))

        var states: [String: PipelineState] = [:]
        let reconcile = await ScaleTests.measure("pipelineStates \(records.count)") { states = await store.pipelineStates() }
        #expect(states.count == records.count)
        #expect(reconcile < .seconds(1))

        guard store.isFTSAvailable else { return }
        let queries = ["\"receipt\"*", "\"flight\"* \"gate\"*", "\"wifi\"* \"password\"*", "\"concert\"*"]
        var hits = 0
        let fts = await ScaleTests.measure("FTS ×\(queries.count) at \(records.count)") {
            for query in queries { hits += await store.ftsSearch(match: query, limit: 200).count }
        }
        #expect(hits > 0)
        #expect(fts / queries.count < .milliseconds(50), "full-text query takes \(fts / queries.count)")
    }

    @Test func vectorNeighboursScale() {
        let dimension = 512
        let matrix = VectorMatrix((0..<ScaleTests.librarySize).map { ("asset-\($0)", ScaleTests.vector($0, dimension: dimension)) })
        let query = ScaleTests.vector(7, dimension: dimension)
        var result: [(id: String, similarity: Float)] = []
        let elapsed = ScaleTests.measure("nearest(k: 20) over \(ScaleTests.librarySize)×\(dimension)") {
            for _ in 0..<10 { result = matrix.nearest(to: query, k: 20) }
        }
        #expect(result.first?.id == "asset-7")
        #expect(elapsed / 10 < .milliseconds(40), "vector search takes \(elapsed / 10)")
    }

    // MARK: Classification throughput (re-scoring the library after a rules change)

    @Test func rescoreThroughput() {
        let samples = 2_000
        let features: [ExtractedFeatures] = (0..<samples).map { index in
            let lines = ScaleTests.text(index, words: 60).split(separator: " ").chunked(8).enumerated().map { offset, chunk in
                (chunk.joined(separator: " "), offset == 0 ? ScreenZone.topBar : ScreenZone.body)
            }
            return TestSupport.features(lines: lines, labels: [("document", 0.8), ("screenshot", 0.8)])
        }
        let elapsed = ScaleTests.measure("classify \(samples) screenshots (no entities)") {
            for feature in features { _ = ScreenshotClassifier.classify(features: feature, includeEntities: false) }
        }
        let perRecord = elapsed / samples
        let library = Double(ScaleTests.librarySize) * Double(perRecord.components.attoseconds) / 1e18
        print("⏱ per record: \(perRecord) → whole \(ScaleTests.librarySize) library ≈ \(String(format: "%.1f", library)) s")
        // Debug build on the simulator; the optimised eval harness runs ~3× faster
        #expect(perRecord < .milliseconds(2), "classification takes \(perRecord) per screenshot")
    }
}

private extension ArraySlice where Element == Substring {
    func chunked(_ size: Int) -> [[Substring]] {
        stride(from: startIndex, to: endIndex, by: size).map { Array(self[$0..<Swift.min($0 + size, endIndex)]) }
    }
}

private extension Array where Element == Substring {
    func chunked(_ size: Int) -> [[Substring]] { self[...].chunked(size) }
}

/// Deterministic RNG so synthetic libraries are identical across runs.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
