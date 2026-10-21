import Foundation
import Observation
import Photos

/// In-memory, observable view of the screenshot library plus analysis results.
///
/// Updates are incremental: applying a batch only touches the categories that changed
/// (the old view model rebuilt every collection from every screenshot on each update).
@MainActor
@Observable
final class LibraryStore {
    private(set) var items: [String: Screenshot] = [:]
    /// Newest first
    private(set) var orderedIDs: [String] = []
    private(set) var membersByCategory: [ScreenshotCategory: Set<String>] = [:]
    private(set) var smartCollections: [SmartCollection] = []
    private(set) var entityTypes: [String: Set<EntityType>] = [:]
    /// Bumped on every change (cheap observation hook for derived caches)
    private(set) var revision = 0

    @ObservationIgnored private var sortedCache: [CollectionKind: [String]] = [:]

    var count: Int { orderedIDs.count }
    var isEmpty: Bool { orderedIDs.isEmpty }

    /// Screenshots with at least a fast pass. Maintained incrementally: views read it every frame.
    private(set) var analyzedCount = 0
    /// Not yet kept/tossed in review. Incremental for the same reason (home banner + toolbar).
    private(set) var unreviewedCount = 0
    @ObservationIgnored private var newestUnreviewedCache: (revision: Int, date: Date?)?

    /// Creation date of the newest unreviewed screenshot (cached per revision).
    var newestUnreviewedDate: Date? {
        if let cache = newestUnreviewedCache, cache.revision == revision { return cache.date }
        let date = orderedIDs.lazy.compactMap { self.items[$0] }.first { !$0.isReviewed }?.creationDate
        newestUnreviewedCache = (revision, date)
        return date
    }

    var allScreenshots: [Screenshot] {
        orderedIDs.compactMap { items[$0] }
    }

    func screenshot(id: String) -> Screenshot? { items[id] }

    func screenshots(ids: [String]) -> [Screenshot] {
        ids.compactMap { items[$0] }
    }

    /// Screenshots in a collection, newest first (cached until that collection changes).
    func screenshots(for kind: CollectionKind) -> [Screenshot] {
        sortedIDs(for: kind).compactMap { items[$0] }
    }

    /// The newest few screenshots plus the total, without materialising the whole collection —
    /// for cards and shelves, which re-render on every analysis batch.
    func preview(for kind: CollectionKind, limit: Int = 4) -> ScreenshotCollection {
        let ids = sortedIDs(for: kind)
        let screenshots = ids.prefix(limit).compactMap { items[$0] }
        return makeCollection(kind, screenshots: screenshots, count: ids.count)
    }

    private func sortedIDs(for kind: CollectionKind) -> [String] {
        _ = revision
        if let cached = sortedCache[kind] {
            return cached
        }
        let ids: [String]
        switch kind {
        case .all:
            ids = orderedIDs
        case .category(let category):
            let members = membersByCategory[category] ?? []
            ids = members.sorted { (items[$0]?.creationDate ?? .distantPast) > (items[$1]?.creationDate ?? .distantPast) }
        case .smart(let id):
            let members = smartCollections.first { $0.id == id }?.memberIDs ?? []
            ids = members
                .filter { items[$0] != nil }
                .sorted { (items[$0]?.creationDate ?? .distantPast) > (items[$1]?.creationDate ?? .distantPast) }
        }
        sortedCache[kind] = ids
        return ids
    }

    func collection(for kind: CollectionKind) -> ScreenshotCollection {
        makeCollection(kind, screenshots: screenshots(for: kind), count: nil)
    }

    private func makeCollection(_ kind: CollectionKind, screenshots: [Screenshot], count: Int?) -> ScreenshotCollection {
        switch kind {
        case .all:
            return ScreenshotCollection(kind: .all, title: "All Screenshots", icon: ScreenshotCategory.all.icon, screenshots: screenshots, count: count)
        case .category(let category):
            return ScreenshotCollection(kind: kind, title: category.displayName, icon: category.icon, screenshots: screenshots, count: count)
        case .smart(let id):
            let smart = smartCollections.first { $0.id == id }
            return ScreenshotCollection(kind: kind, title: smart?.name ?? "Collection", icon: smart?.symbol ?? "sparkles", screenshots: screenshots, count: count)
        }
    }

    /// Previews (newest 4 + count) of every non-empty category, "Other" last.
    func categoryCollections(sort: CollectionsSortOption) -> [ScreenshotCollection] {
        let categories = membersByCategory.filter { !$0.value.isEmpty && $0.key != .all }.map(\.key)
        var collections = categories.map { preview(for: .category($0)) }
        switch sort {
        case .imageCount:
            collections.sort { $0.count == $1.count ? $0.title < $1.title : $0.count > $1.count }
        case .alphabetical:
            collections.sort { $0.title < $1.title }
        case .mostRecent:
            collections.sort { ($0.screenshots.first?.creationDate ?? .distantPast) > ($1.screenshots.first?.creationDate ?? .distantPast) }
        }
        if let index = collections.firstIndex(where: { $0.category == .other }) {
            collections.append(collections.remove(at: index))
        }
        return collections
    }

    var keptSmartCollections: [SmartCollection] {
        smartCollections.filter { $0.status == .kept }
    }

    var suggestedSmartCollections: [SmartCollection] {
        smartCollections.filter { $0.status == .suggested }
    }

    var unreviewed: [Screenshot] {
        allScreenshots.filter { !$0.isReviewed }
    }

    // MARK: - Mutations

    func reset(assets: [PHAsset], summaries: [String: RecordSummary]) {
        reset(screenshots: assets.map { Screenshot(asset: $0, summary: summaries[$0.localIdentifier]) })
    }

    /// `screenshots` must be newest first.
    func reset(screenshots: [Screenshot]) {
        var newItems: [String: Screenshot] = [:]
        newItems.reserveCapacity(screenshots.count)
        var members: [ScreenshotCategory: Set<String>] = [:]
        for screenshot in screenshots {
            newItems[screenshot.id] = screenshot
            for category in screenshot.categories {
                members[category, default: []].insert(screenshot.id)
            }
        }
        items = newItems
        orderedIDs = screenshots.map(\.id)
        membersByCategory = members
        analyzedCount = screenshots.reduce(0) { $0 + ($1.tier >= .fast ? 1 : 0) }
        unreviewedCount = screenshots.reduce(0) { $0 + ($1.isReviewed ? 0 : 1) }
        sortedCache.removeAll()
        revision += 1
    }

    func insert(assets: [PHAsset]) {
        let fresh = assets.filter { items[$0.localIdentifier] == nil }
        guard !fresh.isEmpty else { return }
        for asset in fresh {
            items[asset.localIdentifier] = Screenshot(asset: asset, summary: nil)
        }
        unreviewedCount += fresh.count
        orderedIDs = items.values
            .sorted { $0.creationDate > $1.creationDate }
            .map(\.id)
        sortedCache[.all] = nil
        revision += 1
    }

    func remove(ids: [String]) {
        let removed = Set(ids)
        guard removed.contains(where: { items[$0] != nil }) else { return }
        for id in removed {
            guard let screenshot = items.removeValue(forKey: id) else { continue }
            if screenshot.tier >= .fast { analyzedCount -= 1 }
            if !screenshot.isReviewed { unreviewedCount -= 1 }
            for category in screenshot.categories {
                membersByCategory[category]?.remove(id)
                sortedCache[.category(category)] = nil
            }
            entityTypes[id] = nil
        }
        orderedIDs.removeAll { removed.contains($0) }
        sortedCache[.all] = nil
        for collection in smartCollections { sortedCache[.smart(id: collection.id)] = nil }
        revision += 1
    }

    /// Apply analysis results. Cost is proportional to the batch, not the library.
    func apply(_ summaries: [RecordSummary], records: [AnalysisRecord] = []) {
        guard !summaries.isEmpty else { return }
        for summary in summaries {
            guard let existing = items[summary.id] else { continue }
            let updated = Screenshot(id: existing.id, asset: existing.asset, creationDate: existing.creationDate, summary: summary)
            analyzedCount += (updated.tier >= .fast ? 1 : 0) - (existing.tier >= .fast ? 1 : 0)
            unreviewedCount += (updated.isReviewed ? 0 : 1) - (existing.isReviewed ? 0 : 1)
            let oldCategories = Set(existing.categories)
            let newCategories = Set(updated.categories)
            // Keep cached orderings sorted in place: re-sorting every touched category on the
            // next render cost ~100 ms per batch at 25k screenshots (see ScaleTests).
            for category in oldCategories.subtracting(newCategories) {
                membersByCategory[category]?.remove(summary.id)
                removeSorted(summary.id, date: existing.creationDate, from: .category(category))
            }
            for category in newCategories.subtracting(oldCategories) {
                membersByCategory[category, default: []].insert(summary.id)
                insertSorted(summary.id, date: existing.creationDate, into: .category(category))
            }
            items[summary.id] = updated
        }
        for record in records where items[record.id] != nil {
            entityTypes[record.id] = Set(record.entities.map(\.type))
        }
        revision += 1
    }

    /// Index of the first id (newest first) older than `date`.
    private func insertionIndex(for date: Date, in ids: [String]) -> Int {
        var low = 0
        var high = ids.count
        while low < high {
            let mid = (low + high) / 2
            if (items[ids[mid]]?.creationDate ?? .distantPast) >= date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func insertSorted(_ id: String, date: Date, into kind: CollectionKind) {
        guard var ids = sortedCache.removeValue(forKey: kind) else { return }
        ids.insert(id, at: insertionIndex(for: date, in: ids))
        sortedCache[kind] = ids
    }

    private func removeSorted(_ id: String, date: Date, from kind: CollectionKind) {
        guard var ids = sortedCache.removeValue(forKey: kind) else { return }
        // Equal dates sit just before the insertion point; scan back over them for the id
        var index = insertionIndex(for: date, in: ids) - 1
        while index >= 0, ids[index] != id, (items[ids[index]]?.creationDate ?? .distantPast) == date { index -= 1 }
        if index >= 0, ids[index] == id {
            ids.remove(at: index)
        } else if let fallback = ids.firstIndex(of: id) {
            ids.remove(at: fallback)
        }
        sortedCache[kind] = ids
    }

    func loadEntityTypes(_ map: [String: Set<EntityType>]) {
        entityTypes = map
    }

    func setReviewed(ids: [String], reviewed: Bool = true) {
        for id in ids {
            guard let screenshot = items[id], screenshot.isReviewed != reviewed else { continue }
            items[id]?.isReviewed = reviewed
            unreviewedCount += reviewed ? -1 : 1
        }
        revision += 1
    }

    func setSmartCollections(_ collections: [SmartCollection]) {
        smartCollections = collections
        for kind in sortedCache.keys {
            if case .smart = kind { sortedCache[kind] = nil }
        }
        revision += 1
    }

    // MARK: - Search support

    func searchContext() -> SearchContext {
        var context = SearchContext()
        context.dates.reserveCapacity(items.count)
        for (id, screenshot) in items {
            context.dates[id] = screenshot.creationDate
            context.categories[id] = Set(screenshot.categories)
            if let app = screenshot.app { context.apps[id] = app.lowercased() }
        }
        context.entityTypes = entityTypes
        return context
    }

    func clusterContext() -> ClusterContext {
        var context = ClusterContext()
        context.libraryCount = items.count
        context.candidateIDs = orderedIDs.filter { items[$0]?.tier == .deep }
        for (id, screenshot) in items {
            context.tags[id] = screenshot.tags
            context.topCategory[id] = screenshot.categories.first
            if let app = screenshot.app { context.apps[id] = app }
            if let title = screenshot.title { context.titles[id] = title }
            for tag in Set(screenshot.tags) { context.tagDocumentFrequency[tag, default: 0] += 1 }
        }
        return context
    }
}
