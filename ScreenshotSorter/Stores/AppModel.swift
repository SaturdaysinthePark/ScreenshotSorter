import Foundation
import Observation
import Photos
import SwiftUI
import os

/// A chip in the search field.
enum SearchToken: Identifiable, Hashable {
    case category(ScreenshotCategory)
    case app(String)
    case entity(EntityType)

    var id: String {
        switch self {
        case .category(let category): return "c:" + category.key
        case .app(let app): return "a:" + app
        case .entity(let type): return "e:" + type.rawValue
        }
    }

    var title: String {
        switch self {
        case .category(let category): return category.displayName
        case .app(let app): return app.capitalized
        case .entity(let type):
            switch type {
            case .url: return "Links"
            case .phone: return "Phone numbers"
            case .address: return "Addresses"
            case .date: return "Dates"
            case .price: return "Prices"
            case .tracking: return "Tracking numbers"
            case .flight: return "Flights"
            default: return type.rawValue.capitalized
            }
        }
    }

    var systemImage: String {
        switch self {
        case .category(let category): return category.icon
        case .app: return "app.fill"
        case .entity(let type):
            switch type {
            case .url: return "link"
            case .phone: return "phone.fill"
            case .address: return "mappin.and.ellipse"
            case .date: return "calendar"
            case .price: return "dollarsign.circle.fill"
            case .tracking: return "shippingbox.fill"
            default: return "text.magnifyingglass"
            }
        }
    }
}

/// "Add 5 similar screenshots to Receipts?" — offered after a correction.
struct PropagationSuggestion: Identifiable, Equatable {
    let id = UUID()
    let category: ScreenshotCategory
    let ids: [String]
    /// Correction group that prompted it; undoing that group withdraws the suggestion.
    var sourceGroup: String?
}

/// App-wide state and the single entry point for views.
@MainActor
@Observable
final class AppModel {
    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "AppModel")
    private static let sortKey = "collectionsSort"
    private static let reviewDismissedKey = "lastBannerDismissedDate"
    private static let reviewedIDsKey = "reviewedScreenshotIDs"
    /// Smart collections are only proposed once most of the library is deeply analyzed
    private static let clusterCoverage = 0.8
    private static let clusterEvery = 200

    let library = LibraryStore()

    // MARK: State

    private(set) var hasPhotoAccess = PhotoLibraryService.shared.hasAccess
    private(set) var authorizationDenied = false
    private(set) var isLibraryLoaded = false
    private(set) var progress = AnalysisProgress()
    var collectionsSort: CollectionsSortOption = CollectionsSortOption(rawValue: UserDefaults.standard.string(forKey: AppModel.sortKey) ?? "") ?? .imageCount {
        didSet { UserDefaults.standard.set(collectionsSort.rawValue, forKey: AppModel.sortKey) }
    }
    private(set) var reviewBannerDismissedAt: Date? = UserDefaults.standard.object(forKey: AppModel.reviewDismissedKey) as? Date
    var propagationSuggestion: PropagationSuggestion?
    /// Undone correction groups, so a suggestion still being computed for one never appears.
    private var undoneGroups: Set<String> = []

    // Search
    var searchText = "" {
        didSet { if searchText != oldValue { scheduleSearch() } }
    }
    var searchTokens: [SearchToken] = [] {
        didSet { if searchTokens != oldValue { scheduleSearch() } }
    }
    private(set) var searchResults: [SearchHit] = []
    private(set) var isSearchRunning = false
    private(set) var parsedQuery = ParsedQuery()
    var isSearchActive: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty || !searchTokens.isEmpty }

    // MARK: Services

    let store: AnalysisStore
    let vectors: VectorIndex
    let learner: UserFeedbackLearner
    let pipeline: AnalysisPipeline
    let scheduler: AnalysisScheduler
    let searchService: SearchService
    let smartEngine: SmartCollectionEngine
    @ObservationIgnored private var observer: PhotoLibraryObserver?
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var deepSinceCluster = 0
    @ObservationIgnored private var isClustering = false
    @ObservationIgnored private var searchContextCache: (revision: Int, context: SearchContext)?
    /// Read by `.searchable` on every home render; scanning 25k items per frame showed up in ScaleTests.
    @ObservationIgnored private var suggestedTokensCache: (revision: Int, tokens: [SearchToken])?

    init() {
        let store = AnalysisStore.openDefault()
        let vectors = VectorIndex()
        let learner = UserFeedbackLearner(store: store)
        let pipeline = AnalysisPipeline(store: store, vectors: vectors, learner: learner)
        self.store = store
        self.vectors = vectors
        self.learner = learner
        self.pipeline = pipeline
        self.scheduler = AnalysisScheduler(pipeline: pipeline, store: store)
        self.searchService = SearchService(store: store, vectors: vectors)
        self.smartEngine = SmartCollectionEngine(store: store, vectors: vectors)
    }

    // MARK: - Lifecycle

    func start() async {
        guard !didStart else { return }
        didStart = true
        BackgroundAnalysisManager.schedulerProvider = { [weak self] in self?.scheduler }
        listenToScheduler()

        await LegacyCacheMigrator.migrateIfNeeded(into: store)
        let textVectors = await store.embeddings(model: TextEmbedder.modelID)
        let visualVectors = await store.featurePrints()
        await vectors.load(text: textVectors, visual: visualVectors)
        library.setSmartCollections(await smartEngine.all())

        hasPhotoAccess = PhotoLibraryService.shared.hasAccess
        if hasPhotoAccess {
            await loadLibrary()
        }
        Task { await FMClassifier.shared.prewarm() }
        #if DEBUG
        // QA: start paused so UI timing isn't skewed by analysis (`-QAPauseAnalysis YES`)
        if UserDefaults.standard.bool(forKey: "QAPauseAnalysis") && !progress.isPaused { togglePause() }
        #endif
    }

    func requestPhotoAccess() {
        Task {
            let granted = await PhotoLibraryService.shared.requestAuthorization()
            hasPhotoAccess = granted
            authorizationDenied = !granted
            if granted {
                await loadLibrary()
            }
        }
    }

    private func loadLibrary() async {
        var summaries: [String: RecordSummary] = [:]
        for summary in await store.loadSummaries() { summaries[summary.id] = summary }
        let assets = await PhotoLibraryService.shared.fetchScreenshots()
        library.reset(assets: assets, summaries: summaries)
        library.loadEntityTypes(await store.entityTypeMap())
        syncReviewedFromDefaults()
        isLibraryLoaded = true
        startObserver()
        await reconcile(assets: assets)
    }

    /// Decide what needs (re)analysis by comparing the library with stored pipeline state.
    private func reconcile(assets: [PHAsset]) async {
        let states = await store.pipelineStates()
        let assetIDs = Set(assets.map(\.localIdentifier))
        let stale = states.keys.filter { !assetIDs.contains($0) }
        if !stale.isEmpty {
            await store.delete(ids: stale)
            await vectors.remove(ids: Set(stale))
        }

        var fast: [(id: String, date: Date)] = []
        var deep: [(id: String, date: Date)] = []
        var rescore: [String] = []
        let modelAvailable = FMClassifier.isAvailable
        for asset in assets {
            let item = (id: asset.localIdentifier, date: asset.creationDate ?? .distantPast)
            guard let state = states[item.id] else {
                fast.append(item)
                continue
            }
            if state.tier == .failed && state.visionVersion >= PipelineVersion.vision { continue }
            if state.tier == .none || state.visionVersion < PipelineVersion.vision {
                fast.append(item)
            } else if state.tier == .fast || state.needsNetwork {
                deep.append(item)
            } else if modelAvailable && state.fmVersion < PipelineVersion.fm {
                deep.append(item)
            } else if state.rulesVersion < PipelineVersion.rules {
                rescore.append(item.id)
            }
        }
        await scheduler.enqueueFast(fast)
        await scheduler.enqueueDeep(deep)
        if !rescore.isEmpty {
            await rescoreRecords(ids: rescore)
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task { await scheduler.setInBackground(false) }
            syncReviewedFromDefaults()
        case .inactive:
            let remaining = progress.fastRemaining + progress.deepRemaining
            BackgroundAnalysisManager.submitContinuedIfNeeded(remaining: remaining)
        case .background:
            Task { await scheduler.setInBackground(true) }
            if progress.deepRemaining > 0 || progress.fastRemaining > 0 {
                BackgroundAnalysisManager.scheduleOvernight()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Event streams

    private func listenToScheduler() {
        let events = scheduler.events
        listeners.append(Task { [weak self] in
            for await event in events {
                guard let self else { break }
                switch event {
                case .records(let summaries, let records):
                    self.library.apply(summaries, records: records)
                    self.deepSinceCluster += records.filter { $0.tier == .deep }.count
                    let newDeep = records.filter { $0.tier == .deep }.map(\.id)
                    if !newDeep.isEmpty && !self.library.keptSmartCollections.isEmpty {
                        self.library.setSmartCollections(await self.smartEngine.absorb(newIDs: newDeep))
                    }
                    self.maybeRefreshSmartCollections()
                    if self.isSearchActive { self.scheduleSearch(debounce: 0.8) }
                case .progress(let progress):
                    self.progress = progress
                    if progress.isIdle { self.maybeRefreshSmartCollections(force: true) }
                }
            }
        })
    }

    private func startObserver() {
        guard observer == nil else { return }
        let observer = PhotoLibraryObserver()
        self.observer = observer
        observer.start()
        let deltas = observer.deltas
        listeners.append(Task { [weak self] in
            for await delta in deltas {
                guard let self else { break }
                await self.handle(delta)
            }
        })
    }

    private func handle(_ delta: LibraryDelta) async {
        if delta.needsFullReconcile {
            await loadLibrary()
            return
        }
        if !delta.removed.isEmpty {
            library.remove(ids: delta.removed)
            await scheduler.remove(delta.removed)
            await store.delete(ids: delta.removed)
            await vectors.remove(ids: Set(delta.removed))
        }
        let touched = delta.inserted + delta.changed
        guard !touched.isEmpty else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: touched, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) { assets.append(asset) }
        }
        library.insert(assets: assets)
        if !delta.changed.isEmpty {
            await store.invalidate(ids: delta.changed, resetVision: true)
        }
        await scheduler.enqueueFast(assets.map { (id: $0.localIdentifier, date: $0.creationDate ?? Date()) }, urgent: true)
    }

    // MARK: - Analysis controls

    func togglePause() {
        let paused = !progress.isPaused
        progress.isPaused = paused
        Task { await scheduler.setPaused(paused) }
    }

    func reanalyzeAll() {
        Task {
            await store.invalidate(ids: nil, resetVision: true)
            await reconcile(assets: library.allScreenshots.map(\.asset))
            BackgroundAnalysisManager.submitContinuedIfNeeded(remaining: library.count)
        }
    }

    /// Prioritise screenshots the user is looking at.
    func boost(_ ids: [String]) {
        let pending = ids.filter { (library.screenshot(id: $0)?.tier ?? .none) < .fast }
        guard !pending.isEmpty else { return }
        Task { await scheduler.boost(pending) }
    }

    var analysisFraction: Double {
        guard library.count > 0 else { return 1 }
        return Double(library.analyzedCount) / Double(library.count)
    }

    // MARK: - Details

    func record(for id: String) async -> AnalysisRecord? {
        await store.record(id: id)
    }

    func similar(to id: String, limit: Int = 12) async -> [Screenshot] {
        let neighbours = await vectors.neighbours(of: id, k: limit, minimum: 0.6)
        return library.screenshots(ids: neighbours.map(\.id))
    }

    func delete(_ ids: [String]) async -> Bool {
        let assets = library.screenshots(ids: ids).map(\.asset)
        guard !assets.isEmpty else { return false }
        let success = await PhotoLibraryService.shared.deleteAssets(assets)
        if success {
            library.remove(ids: ids)
            await scheduler.remove(ids)
            await store.delete(ids: ids)
            await vectors.remove(ids: Set(ids))
            HapticManager.shared.swipeDelete()
        }
        return success
    }

    // MARK: - Review

    /// Materialises the whole review queue; only for opening the deck (views use `unreviewedCount`).
    var unreviewedScreenshots: [Screenshot] { library.unreviewed }
    var unreviewedCount: Int { library.unreviewedCount }

    var showReviewBanner: Bool {
        guard library.unreviewedCount > 0, library.analyzedCount > 0 else { return false }
        guard let dismissed = reviewBannerDismissedAt else { return true }
        return (library.newestUnreviewedDate ?? .distantPast) > dismissed
    }

    func dismissReviewBanner() {
        let now = Date()
        reviewBannerDismissedAt = now
        UserDefaults.standard.set(now, forKey: AppModel.reviewDismissedKey)
    }

    /// The review deck persists reviewed ids in UserDefaults; mirror them into the store.
    func syncReviewedFromDefaults() {
        let reviewed = UserDefaults.standard.array(forKey: AppModel.reviewedIDsKey) as? [String] ?? []
        let newlyReviewed = reviewed.filter { library.screenshot(id: $0)?.isReviewed == false }
        guard !newlyReviewed.isEmpty else { return }
        library.setReviewed(ids: newlyReviewed)
        Task { await store.setReviewed(ids: newlyReviewed, reviewed: true) }
    }

    // MARK: - Corrections

    /// Move screenshots into `category` (removing `from`, if given). Returns an undo token.
    @discardableResult
    func move(_ ids: [String], from source: ScreenshotCategory?, to destination: ScreenshotCategory) -> String {
        let group = UUID().uuidString
        var corrections: [Correction] = []
        for id in ids {
            if let source, source != destination, source != .all {
                corrections.append(Correction(assetID: id, kind: .category, value: source.key, action: .remove, groupID: group, createdAt: Date()))
            }
            corrections.append(Correction(assetID: id, kind: .category, value: destination.key, action: .add, groupID: group, createdAt: Date()))
        }
        apply(corrections, suggestFor: destination)
        return group
    }

    @discardableResult
    func setCategory(_ category: ScreenshotCategory, included: Bool, for ids: [String]) -> String {
        let group = UUID().uuidString
        let corrections = ids.map {
            Correction(assetID: $0, kind: .category, value: category.key, action: included ? .add : .remove, groupID: group, createdAt: Date())
        }
        apply(corrections, suggestFor: included ? category : nil)
        return group
    }

    @discardableResult
    func setTag(_ tag: String, included: Bool, for ids: [String]) -> String {
        let group = UUID().uuidString
        let normalized = ScreenshotClassifier.normalizeTag(tag)
        guard !normalized.isEmpty else { return group }
        let corrections = ids.map {
            Correction(assetID: $0, kind: .tag, value: normalized, action: included ? .add : .remove, groupID: group, createdAt: Date())
        }
        apply(corrections, suggestFor: nil)
        return group
    }

    func undoCorrection(group: String, ids: [String]) {
        undoneGroups.insert(group)
        if propagationSuggestion?.sourceGroup == group {
            propagationSuggestion = nil
        }
        Task {
            await learner.undo(groupID: group)
            await rescoreRecords(ids: ids)
        }
    }

    func acceptPropagation(_ suggestion: PropagationSuggestion) {
        propagationSuggestion = nil
        setCategory(suggestion.category, included: true, for: suggestion.ids)
    }

    private func apply(_ corrections: [Correction], suggestFor category: ScreenshotCategory?) {
        guard !corrections.isEmpty else { return }
        var previous: [String: [ScreenshotCategory: Double]] = [:]
        for correction in corrections {
            guard let screenshot = library.screenshot(id: correction.assetID) else { continue }
            var scores: [ScreenshotCategory: Double] = [:]
            for scored in screenshot.categoriesWithConfidence { scores[scored.category] = scored.score }
            previous[correction.assetID] = scores
        }
        let ids = Array(Set(corrections.map(\.assetID)))
        HapticManager.shared.mediumTap()
        Task {
            await learner.record(corrections, previousScores: previous)
            await rescoreRecords(ids: ids)

            // Neighbours of corrected items may now move too (needs ≥2 agreeing corrections)
            var neighbours = Set<String>()
            for id in ids.prefix(10) {
                neighbours.formUnion(await learner.affectedNeighbours(of: id, vectors: vectors))
            }
            neighbours.subtract(ids)
            if !neighbours.isEmpty {
                await rescoreRecords(ids: Array(neighbours))
            }
            if let category, let group = corrections.first?.groupID {
                await offerPropagation(for: ids, category: category, group: group)
            }
        }
    }

    /// After adding a category, offer to file very similar screenshots the same way.
    private func offerPropagation(for ids: [String], category: ScreenshotCategory, group: String) async {
        var candidates: [String: Float] = [:]
        for id in ids.prefix(10) {
            for neighbour in await vectors.neighbours(of: id, k: 20, minimum: 0.82) {
                guard !ids.contains(neighbour.id),
                      let screenshot = library.screenshot(id: neighbour.id),
                      !screenshot.categories.contains(category) else { continue }
                candidates[neighbour.id] = max(candidates[neighbour.id] ?? 0, neighbour.similarity)
            }
        }
        let ranked = candidates.sorted { $0.value > $1.value }.map(\.key)
        if ranked.count >= 3 && !undoneGroups.contains(group) {
            propagationSuggestion = PropagationSuggestion(category: category, ids: Array(ranked.prefix(24)), sourceGroup: group)
        }
    }

    /// Re-run rules + fusion from stored features (no pixels) and publish the results.
    func rescoreRecords(ids: [String]) async {
        let chunkSize = 200
        var index = 0
        while index < ids.count {
            let chunk = Array(ids[index..<min(index + chunkSize, ids.count)])
            index += chunkSize
            var updated: [AnalysisRecord] = []
            for record in await store.records(ids: chunk) {
                var rescored = await pipeline.rescore(record)
                if record.features == nil {
                    // Not analyzed yet: still honour the user's direct corrections
                    let signals = await learner.signals(for: record.id, vectors: vectors)
                    rescored = AppModel.applyOverrides(signals, to: rescored)
                }
                updated.append(rescored)
            }
            let missing = Set(chunk).subtracting(updated.map(\.id))
            for id in missing {
                guard let screenshot = library.screenshot(id: id) else { continue }
                let signals = await learner.signals(for: id, vectors: vectors)
                var record = AnalysisRecord(id: id, createdAt: screenshot.creationDate)
                record = AppModel.applyOverrides(signals, to: record)
                updated.append(record)
            }
            await store.upsert(updated)
            library.apply(updated.map(\.summaryValue), records: updated)
        }
    }

    private static func applyOverrides(_ signals: UserSignals, to record: AnalysisRecord) -> AnalysisRecord {
        var record = record
        var categories = record.categories.filter { signals.overrides[$0.category] != false }
        for (category, added) in signals.overrides where added && !categories.contains(where: { $0.category == category }) {
            categories.insert(ScoredCategory(category: category, score: 1, sources: .user), at: 0)
        }
        record.categories = categories
        var tags = record.tags.filter { !signals.removedTags.contains($0.value) }
        for tag in signals.addedTags where !tags.contains(where: { $0.value == tag }) {
            tags.insert(ScreenshotTag(value: tag, score: 1, sources: .user), at: 0)
        }
        record.tags = tags
        if record.tier == .none && !categories.isEmpty { record.tier = .fast }
        return record
    }

    // MARK: - Smart collections

    private func maybeRefreshSmartCollections(force: Bool = false) {
        guard !isClustering, library.count >= SmartCollectionEngine.minimumMembers else { return }
        let deepCount = library.items.values.reduce(0) { $0 + ($1.tier == .deep ? 1 : 0) }
        guard Double(deepCount) / Double(max(1, library.count)) >= AppModel.clusterCoverage else { return }
        guard force || deepSinceCluster >= AppModel.clusterEvery else { return }
        guard library.suggestedSmartCollections.count < SmartCollectionEngine.maxVisibleSuggestions else { return }
        isClustering = true
        deepSinceCluster = 0
        let context = library.clusterContext()
        Task {
            let collections = await smartEngine.refresh(context: context)
            library.setSmartCollections(collections)
            isClustering = false
        }
    }

    func keepSuggestion(_ id: String, name: String? = nil) {
        Task {
            library.setSmartCollections(await smartEngine.keep(id: id, name: name))
            HapticManager.shared.processingComplete()
        }
    }

    func dismissSuggestion(_ id: String) {
        Task { library.setSmartCollections(await smartEngine.dismiss(id: id)) }
    }

    func renameSmartCollection(_ id: String, to name: String) {
        Task { library.setSmartCollections(await smartEngine.rename(id: id, to: name)) }
    }

    func deleteSmartCollection(_ id: String) {
        Task { library.setSmartCollections(await smartEngine.delete(id: id)) }
    }

    func removeFromSmartCollection(_ assetIDs: [String], collectionID: String) {
        Task {
            var collections = library.smartCollections
            for assetID in assetIDs {
                collections = await smartEngine.removeMember(assetID, from: collectionID)
            }
            library.setSmartCollections(collections)
        }
    }

    // MARK: - Search

    private func scheduleSearch(debounce: Double = 0.15) {
        searchTask?.cancel()
        guard isSearchActive else {
            searchResults = []
            parsedQuery = ParsedQuery()
            isSearchRunning = false
            return
        }
        isSearchRunning = true
        let text = searchText
        let tokens = searchTokens
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            var query = QueryParser.parse(text)
            for token in tokens {
                switch token {
                case .category(let category): query.categories.insert(category)
                case .app(let app): query.apps.insert(app.lowercased())
                case .entity(let type): query.entityTypes.insert(type)
                }
            }
            let context = self.currentSearchContext()
            let results = await self.searchService.search(query, context: context)
            guard !Task.isCancelled else { return }
            self.parsedQuery = query
            self.searchResults = results
            self.isSearchRunning = false
        }
    }

    private func currentSearchContext() -> SearchContext {
        if let cache = searchContextCache, cache.revision == library.revision {
            return cache.context
        }
        let context = library.searchContext()
        searchContextCache = (library.revision, context)
        return context
    }

    /// Category / app / entity chips to suggest under the search field.
    var suggestedSearchTokens: [SearchToken] {
        _ = library.revision
        if let cache = suggestedTokensCache, cache.revision == library.revision {
            return cache.tokens.filter { !searchTokens.contains($0) }
        }
        let categories = library.categoryCollections(sort: .imageCount)
            .prefix(6)
            .compactMap { $0.kind.category }
            .filter { $0 != .other && $0 != .all }
            .map { SearchToken.category($0) }
        var appCounts: [String: Int] = [:]
        for screenshot in library.items.values {
            if let app = screenshot.app { appCounts[app, default: 0] += 1 }
        }
        let apps = appCounts.sorted { $0.value > $1.value }.prefix(4).map { SearchToken.app($0.key) }
        let entities: [SearchToken] = [.entity(.url), .entity(.phone), .entity(.tracking)]
        let tokens = Array(categories) + apps + entities
        suggestedTokensCache = (library.revision, tokens)
        return tokens.filter { !searchTokens.contains($0) }
    }
}
