import Foundation

/// Stable identity of something the gallery can show.
enum CollectionKind: Hashable, Sendable {
    case all
    case category(ScreenshotCategory)
    case smart(id: String)

    var id: String {
        switch self {
        case .all: return "all"
        case .category(let category): return "category:\(category.key)"
        case .smart(let id): return "smart:\(id)"
        }
    }

    var category: ScreenshotCategory? {
        if case .category(let category) = self { return category }
        if case .all = self { return .all }
        return nil
    }
}

struct ScreenshotCollection: Identifiable, Hashable {
    let kind: CollectionKind
    let title: String
    let icon: String
    /// All members, or only the first few for a preview (see `count`)
    var screenshots: [Screenshot]
    /// Members in the whole collection; differs from `screenshots.count` for previews
    private let totalCount: Int?

    var id: String { kind.id }
    var count: Int { totalCount ?? screenshots.count }

    /// Category for category collections (`.all` for the all-screenshots collection)
    var category: ScreenshotCategory {
        kind.category ?? .other
    }

    init(kind: CollectionKind, title: String, icon: String, screenshots: [Screenshot], count: Int? = nil) {
        self.kind = kind
        self.title = title
        self.icon = icon
        self.screenshots = screenshots
        self.totalCount = count
    }

    init(category: ScreenshotCategory, screenshots: [Screenshot]) {
        self.init(
            kind: category == .all ? .all : .category(category),
            title: category.displayName,
            icon: category.icon,
            screenshots: screenshots
        )
    }

    func sorted(by option: SortOption) -> [Screenshot] {
        switch option {
        case .dateAscending:
            return screenshots.sorted { $0.creationDate < $1.creationDate }
        case .dateDescending:
            return screenshots.sorted { $0.creationDate > $1.creationDate }
        case .relevancy:
            guard let category = kind.category, category != .all else {
                return screenshots.sorted { $0.creationDate > $1.creationDate }
            }
            func score(_ screenshot: Screenshot) -> Double {
                screenshot.categoriesWithConfidence.first { $0.category == category }?.score ?? 0
            }
            return screenshots.sorted { score($0) > score($1) }
        }
    }

    static func == (lhs: ScreenshotCollection, rhs: ScreenshotCollection) -> Bool {
        lhs.id == rhs.id && lhs.count == rhs.count
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum SortOption: String, CaseIterable {
    case dateDescending = "Newest First"
    case dateAscending = "Oldest First"
    case relevancy = "Most Relevant"
}

enum CollectionsSortOption: String, CaseIterable {
    case imageCount = "Most Screenshots"
    case alphabetical = "A–Z"
    case mostRecent = "Recently Added"
}

/// A frozen order for home shelves (category groups) and the category cards inside them.
struct ShelfRanking: Equatable {
    private var groups: [CategoryGroup: Int] = [:]
    private var categories: [ScreenshotCategory: Int] = [:]

    init() {}

    /// `collections` in the order they should appear inside their shelves; shelves rank by total size, "Other" last.
    init(_ collections: [ScreenshotCollection]) {
        var totals: [CategoryGroup: Int] = [:]
        for (index, collection) in collections.enumerated() {
            categories[collection.category] = index
            totals[collection.category.group, default: 0] += collection.count
        }
        let ordered = totals.keys.sorted { lhs, rhs in
            if (lhs == .other) != (rhs == .other) { return rhs == .other }
            return totals[lhs]! == totals[rhs]! ? lhs.rawValue < rhs.rawValue : totals[lhs]! > totals[rhs]!
        }
        for (index, group) in ordered.enumerated() { groups[group] = index }
    }

    /// Groups `collections` into shelves in the frozen order. Groups and categories that appeared since the
    /// ranking was taken go after the known ones, keeping their incoming order.
    func shelves(_ collections: [ScreenshotCollection]) -> [(group: CategoryGroup, collections: [ScreenshotCollection])] {
        var byGroup: [CategoryGroup: [(offset: Int, element: ScreenshotCollection)]] = [:]
        for item in collections.enumerated() {
            byGroup[item.element.category.group, default: []].append(item)
        }
        func rank(_ category: ScreenshotCategory) -> Int { categories[category] ?? Int.max }
        let firstSeen = Dictionary(uniqueKeysWithValues: byGroup.map { ($0.key, $0.value.map(\.offset).min() ?? 0) })
        return byGroup.keys
            .sorted { lhs, rhs in
                if (lhs == .other) != (rhs == .other) { return rhs == .other }
                let l = groups[lhs] ?? Int.max, r = groups[rhs] ?? Int.max
                return l == r ? firstSeen[lhs]! < firstSeen[rhs]! : l < r
            }
            .map { group in
                let items = byGroup[group]!.sorted { lhs, rhs in
                    let l = rank(lhs.element.category), r = rank(rhs.element.category)
                    return l == r ? lhs.offset < rhs.offset : l < r
                }
                return (group, items.map(\.element))
            }
    }
}
