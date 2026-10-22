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
    /// What it was made from, so the details list doesn't repeat it
    var source: ExtractedEntity? = nil

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
            return QuickAction(title: Brand.Copy.Detail.copyCode(value), systemImage: "number", kind: .copy(value), source: code)
        }
        if let tracking = first(.tracking), topics.contains(.orders) || topics.contains(.receipts) {
            let value = tracking.normalized ?? tracking.value
            return QuickAction(title: Brand.Copy.Detail.copyTracking, systemImage: "shippingbox.fill", kind: .copy(value),
                               source: tracking)
        }
        if !topics.isDisjoint(with: placeCategories),
           let place = first(.address) ?? first(.place), let url = mapsURL(for: place.value) {
            return QuickAction(title: Brand.Copy.Detail.openInMaps, systemImage: "map.fill", kind: .open(url), source: place)
        }
        if let link = entities.first(where: { $0.type == .url }), let url = webURL(for: link),
           !topics.isDisjoint(with: linkCategories), let host = url.host() {
            let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return QuickAction(title: Brand.Copy.Detail.openSite(site), systemImage: "safari.fill", kind: .open(url), source: link)
        }
        if let phone = first(.phone), topics.contains(.places), looksLikePhone(phone) {
            let digits = (phone.normalized ?? phone.value).filter { $0.isNumber || $0 == "+" }
            if !digits.isEmpty, let url = URL(string: "tel:" + digits) {
                return QuickAction(title: Brand.Copy.Detail.call, systemImage: "phone.fill", kind: .open(url), source: phone)
            }
        }
        return nil
    }

    /// The few details worth a row in the viewer, most useful first. A closing time, a price on a place card or
    /// a person's name are noise; an address you'll paste somewhere, a link, a number or a code aren't. Prices
    /// only matter on receipts and orders, dates on events, tickets and trips. The button's own detail isn't
    /// repeated, except an address, which is as often copied as opened.
    static func details(categories: [ScreenshotCategory], entities: [ExtractedEntity], primary: QuickAction?,
                        limit: Int = 4) -> [ExtractedEntity] {
        let topics = Set(categories)
        let dated = !topics.isDisjoint(with: [.events, .tickets, .flights])
        let billed = !topics.isDisjoint(with: [.receipts, .orders])
        let rank: [EntityType: Int] = [.oneTimeCode: 0, .tracking: 1, .flight: 2, .address: 3, .url: 4, .phone: 5,
                                       .email: 6, .date: 7, .price: 8, .place: 9]
        let hasAddress = entities.contains { $0.type == .address }
        var seen: Set<String> = []
        var kept: [ExtractedEntity] = []
        for entity in entities {
            switch entity.type {
            case .person, .organization: continue
            // "Document no. 182736455" read as a phone number
            case .phone where !looksLikePhone(entity): continue
            case .date where !dated: continue
            case .price where !billed: continue
            // "Old Westbury" next to its full address
            case .place where hasAddress: continue
            default: break
            }
            if let source = primary?.source, source == entity, entity.type != .address { continue }
            let key = entity.type.rawValue + ":" + entity.value.lowercased()
            guard seen.insert(key).inserted else { continue }
            kept.append(entity)
        }
        // One date and one price are enough: on a receipt, the total (its largest amount)
        if let total = kept.filter({ $0.type == .price }).max(by: { amount($0) < amount($1) }) {
            kept.removeAll { $0.type == .price && $0 != total }
        }
        var counted: [EntityType: Int] = [:]
        return kept
            .sorted { (rank[$0.type] ?? 99) < (rank[$1.type] ?? 99) }
            .filter { entity in
                counted[entity.type, default: 0] += 1
                return !(entity.type == .date || entity.type == .price) || counted[entity.type]! == 1
            }
            .prefix(limit)
            .map { $0 }
    }

    /// A dialable number: international, or written the way phone numbers are ("(212) 555-0100"), not a bare
    /// order or document number
    static func looksLikePhone(_ entity: ExtractedEntity) -> Bool {
        let raw = entity.value
        let digits = raw.filter(\.isNumber).count
        if raw.hasPrefix("+") { return digits >= 8 }
        let formatted = raw.contains { "()-. ".contains($0) }
        return digits >= 10 && (formatted || digits == 10)
    }

    private static func amount(_ entity: ExtractedEntity) -> Double {
        Double((entity.normalized ?? entity.value).filter { $0.isNumber || $0 == "." }) ?? 0
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
