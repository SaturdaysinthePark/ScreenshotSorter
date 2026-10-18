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

    var analyzedCount: Int {
        items.values.reduce(0) { $0 + ($1.tier >= .fast ? 1 : 0) }
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
        _ = revision
        if let cached = sortedCache[kind] {
            return cached.compactMap { items[$0] }
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
        return ids.compactMap { items[$0] }
    }

    func collection(for kind: CollectionKind) -> ScreenshotCollection {
        let screenshots = screenshots(for: kind)
        switch kind {
        case .all:
            return ScreenshotCollection(kind: .all, title: "All Screenshots", icon: ScreenshotCategory.all.icon, screenshots: screenshots)
        case .category(let category):
            return ScreenshotCollection(kind: kind, title: category.displayName, icon: category.icon, screenshots: screenshots)
        case .smart(let id):
            let smart = smartCollections.first { $0.id == id }
            return ScreenshotCollection(kind: kind, title: smart?.name ?? "Collection", icon: smart?.symbol ?? "sparkles", screenshots: screenshots)
        }
    }

    /// Non-empty category collections (unsorted "Other" last).
    func categoryCollections(sort: CollectionsSortOption) -> [ScreenshotCollection] {
        let categories = membersByCategory.filter { !$0.value.isEmpty && $0.key != .all }.map(\.key)
        var collections = categories.map { collection(for: .category($0)) }
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
        var newItems: [String: Screenshot] = [:]
        newItems.reserveCapacity(assets.count)
        var members: [ScreenshotCategory: Set<String>] = [:]
        for asset in assets {
            let screenshot = Screenshot(asset: asset, summary: summaries[asset.localIdentifier])
            newItems[screenshot.id] = screenshot
            for category in screenshot.categories {
                members[category, default: []].insert(screenshot.id)
            }
        }
        items = newItems
        orderedIDs = assets.map(\.localIdentifier)
        membersByCategory = members
        sortedCache.removeAll()
        revision += 1
    }

    func insert(assets: [PHAsset]) {
        let fresh = assets.filter { items[$0.localIdentifier] == nil }
        guard !fresh.isEmpty else { return }
        for asset in fresh {
            items[asset.localIdentifier] = Screenshot(asset: asset, summary: nil)
        }
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
            let updated = Screenshot(asset: existing.asset, summary: summary)
            let oldCategories = Set(existing.categories)
            let newCategories = Set(updated.categories)
            for category in oldCategories.subtracting(newCategories) {
                membersByCategory[category]?.remove(summary.id)
                sortedCache[.category(category)] = nil
            }
            for category in newCategories.subtracting(oldCategories) {
                membersByCategory[category, default: []].insert(summary.id)
                sortedCache[.category(category)] = nil
            }
            items[summary.id] = updated
        }
        for record in records where items[record.id] != nil {
            entityTypes[record.id] = Set(record.entities.map(\.type))
        }
        revision += 1
    }

    func loadEntityTypes(_ map: [String: Set<EntityType>]) {
        entityTypes = map
    }

    func setReviewed(ids: [String], reviewed: Bool = true) {
        for id in ids {
            items[id]?.isReviewed = reviewed
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
