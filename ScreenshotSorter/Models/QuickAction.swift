import Foundation

/// The one thing you most likely want to do with a screenshot, shown as a button in the viewer
/// ("Copy code", "Open in Maps", "Open link"). Chosen from what the screenshot is about and what was read
/// from it; nothing is looked up online until the button is tapped.
struct QuickAction: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case open(URL)
        case copy(String)
    }

    let title: String
    let systemImage: String
    let kind: Kind

    private static let placeCategories: Set<ScreenshotCategory> = [.places, .directions, .food, .drinks, .events, .flights]
    private static let linkCategories: Set<ScreenshotCategory> = [.stores, .clothes, .shoes, .bags, .watches, .jewelry,
                                                                   .furniture, .electronics, .news, .books,
                                                                   .recipes, .programming, .events, .tickets, .music,
                                                                   .movies, .orders]

    static func suggest(categories: [ScreenshotCategory], entities: [ExtractedEntity]) -> QuickAction? {
        let topics = Set(categories)
        func first(_ type: EntityType) -> ExtractedEntity? { entities.first { $0.type == type } }

        // A code you have seconds to type matters most
        if let code = first(.oneTimeCode) {
            let value = code.normalized ?? code.value
            return QuickAction(title: Brand.Copy.Detail.copyCode(value), systemImage: "number", kind: .copy(value))
        }
        if let tracking = first(.tracking), topics.contains(.orders) || topics.contains(.receipts) {
            let value = tracking.normalized ?? tracking.value
            return QuickAction(title: Brand.Copy.Detail.copyTracking, systemImage: "shippingbox.fill", kind: .copy(value))
        }
        if !topics.isDisjoint(with: placeCategories),
           let place = first(.address) ?? first(.place), let url = mapsURL(for: place.value) {
            return QuickAction(title: Brand.Copy.Detail.openInMaps, systemImage: "map.fill", kind: .open(url))
        }
        if let link = entities.first(where: { $0.type == .url }), let url = webURL(for: link),
           !topics.isDisjoint(with: linkCategories), let host = url.host() {
            let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return QuickAction(title: Brand.Copy.Detail.openSite(site), systemImage: "safari.fill", kind: .open(url))
        }
        if let phone = first(.phone), topics.contains(.places) {
            let digits = (phone.normalized ?? phone.value).filter { $0.isNumber || $0 == "+" }
            if !digits.isEmpty, let url = URL(string: "tel:" + digits) {
                return QuickAction(title: Brand.Copy.Detail.call, systemImage: "phone.fill", kind: .open(url))
            }
        }
        return nil
    }

    static func webURL(for entity: ExtractedEntity) -> URL? {
        let raw = (entity.normalized ?? entity.value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(" ") else { return nil }
        let lowered = raw.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") { return URL(string: raw) }
        return URL(string: "https://" + raw)
    }

    static func mapsURL(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed), !encoded.isEmpty else { return nil }
        return URL(string: "http://maps.apple.com/?q=" + encoded)
    }
}
