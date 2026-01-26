import Foundation

struct ScreenshotCollection: Identifiable {
    let id = UUID()
    let category: ScreenshotCategory
    var screenshots: [Screenshot]

    var count: Int {
        screenshots.count
    }

    func sorted(by option: SortOption) -> [Screenshot] {
        switch option {
        case .dateAscending:
            return screenshots.sorted { $0.creationDate < $1.creationDate }
        case .dateDescending:
            return screenshots.sorted { $0.creationDate > $1.creationDate }
        case .relevancy:
            // For now, sort by confidence (number of matching categories)
            // Later can be enhanced with ML confidence scores
            return screenshots.sorted { $0.categories.count > $1.categories.count }
        }
    }
}

enum SortOption: String, CaseIterable {
    case dateDescending = "Newest First"
    case dateAscending = "Oldest First"
    case relevancy = "Most Relevant"
}
