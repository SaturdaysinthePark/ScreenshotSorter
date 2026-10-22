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

    /// - Parameter placeName: the place on a Maps card (`PlaceCard.name`), which often shows no address
    /// - Parameter text: the screenshot's text, for booking and confirmation codes the entity extractor doesn't know
    static func suggest(categories: [ScreenshotCategory], entities: [ExtractedEntity], placeName: String? = nil,
                        text: String = "") -> QuickAction? {
        let topics = Set(categories)
        let entities = usable(entities, text: text) + bookingCodes(in: text)
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
        // The card's name plus its address, unless the name line already carries it ("Nuar, 48 W 27th St")
        if let placeName {
            var query = placeName
            if let address = first(.address)?.value, !placeName.localizedCaseInsensitiveContains(address) {
                query += ", " + address
            }
            if let url = mapsURL(for: query) {
                return QuickAction(title: Brand.Copy.Detail.openInMaps, systemImage: "map.fill", kind: .open(url),
                                   source: first(.address))
            }
        }
        // An address, not a name the text tagger spotted: a city in a caption ("Day 6: Tokyo") isn't a place to go
        if !topics.isDisjoint(with: placeCategories),
           let place = first(.address), let url = mapsURL(for: place.value) {
            return QuickAction(title: Brand.Copy.Detail.openInMaps, systemImage: "map.fill", kind: .open(url), source: place)
        }
        let links = entities.filter { $0.type == .url && isWorthOpening($0) }
        if let link = links.first, let url = webURL(for: link), !topics.isDisjoint(with: linkCategories), let host = url.host() {
            return QuickAction(title: Brand.Copy.Detail.openSite(site(host)), systemImage: "safari.fill", kind: .open(url),
                               source: link)
        }
        if let phone = first(.phone), topics.contains(.places), looksLikePhone(phone) {
            let digits = (phone.normalized ?? phone.value).filter { $0.isNumber || $0 == "+" }
            if !digits.isEmpty, let url = URL(string: "tel:" + digits) {
                return QuickAction(title: Brand.Copy.Detail.call, systemImage: "phone.fill", kind: .open(url), source: phone)
            }
        }
        // Nothing better: the one shop or bio link on screen ("ravizupa.com", "linktr.ee/…"), not in a chat
        if links.count == 1, let link = links.first, topics.isDisjoint(with: [.messages, .email, .memes, .quotes, .notifications]),
           let url = webURL(for: link), let host = url.host() {
            return QuickAction(title: Brand.Copy.Detail.openSite(site(host)), systemImage: "safari.fill", kind: .open(url),
                               source: link)
        }
        return nil
    }

    /// The few details worth a row in the viewer, most useful first. A closing time, a price on a place card or
    /// a person's name are noise; an address you'll paste somewhere, a link, a number or a code aren't. Prices
    /// only matter on receipts and orders, dates on events, tickets and trips. The button's own detail isn't
    /// repeated, except an address, which is as often copied as opened.
    static func details(categories: [ScreenshotCategory], entities: [ExtractedEntity], primary: QuickAction?,
                        text: String = "", limit: Int = 4) -> [ExtractedEntity] {
        let topics = Set(categories)
        let entities = bookingCodes(in: text) + usable(entities, text: text)
        let dated = !topics.isDisjoint(with: [.events, .tickets, .flights])
        let billed = !topics.isDisjoint(with: [.receipts, .orders])
        let rank: [EntityType: Int] = [.oneTimeCode: 0, .tracking: 1, .flight: 2, .address: 3, .url: 4, .phone: 5,
                                       .email: 6, .date: 7, .price: 8, .place: 9]
        var seen: Set<String> = []
        var kept: [ExtractedEntity] = []
        for entity in entities {
            switch entity.type {
            // Names the text tagger guessed: a city in a caption, a word in a title ("Chimera")
            case .person, .organization, .place: continue
            // "Document no. 182736455" read as a phone number
            case .phone where !looksLikePhone(entity): continue
            // "Today", "SUNDAY", "12:00 PM - 2:30 PM", a countdown: not a day to remember
            case .date where !isCalendarDate(entity): continue
            case .url where !isWorthOpening(entity): continue
            case .date where !dated: continue
            case .price where !billed: continue
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
        let digitChars = raw.filter(\.isNumber)
        // Guitar tabs ("0000000 000", "22-21-22-21-17") are digits too
        guard Set(digitChars).count >= 4,
              raw.range(of: #"^\d{1,2}(-\d{1,2}){3,}$"#, options: .regularExpression) == nil else { return false }
        if raw.hasPrefix("+") { return digitChars.count >= 8 }
        let formatted = raw.contains { "()-. ".contains($0) }
        return digitChars.count >= 10 && (formatted || digitChars.count == 10)
    }

    /// Codes the extractor guessed from a bare number: a year ("2026") never is one, and without the text saying
    /// "code" (verification, passcode, OTP) a 4–6 digit number is more often a price, a count or a street number
    static func usable(_ entities: [ExtractedEntity], text: String) -> [ExtractedEntity] {
        let lowered = text.lowercased()
        let saysCode = text.isEmpty || ["code", "passcode", "otp", "verification", "pin"].contains { lowered.contains($0) }
        return entities.filter { entity in
            guard entity.type == .oneTimeCode else { return true }
            let value = entity.normalized ?? entity.value
            if value.count == 4, let year = Int(value), (1900...2099).contains(year) { return false }
            return saysCode
        }
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// A day you might put in a calendar: has a month or a numeric date
    static func isCalendarDate(_ entity: ExtractedEntity) -> Bool {
        let value = entity.value.lowercased()
        if months.contains(where: { value.contains($0) }) { return true }
        return value.range(of: #"\d{1,4}[/.-]\d{1,2}([/.-]\d{2,4})?"#, options: .regularExpression) != nil
            && value.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) == nil
    }

    /// Platforms' own home pages, image credits' cut-off links and the like aren't worth a button or a row
    private static let platformHosts: Set<String> = ["instagram.com", "tiktok.com", "reddit.com", "x.com", "twitter.com",
                                                     "facebook.com", "youtube.com", "google.com", "drive.google.com",
                                                     "linkedin.com", "maps.apple.com", "apple.com"]

    static func isWorthOpening(_ entity: ExtractedEntity) -> Bool {
        let raw = (entity.normalized ?? entity.value).trimmingCharacters(in: .whitespacesAndNewlines)
        // "github.com/zilliztech/claude-" was cut off by the screen's edge
        guard !raw.hasSuffix("-"), !raw.hasSuffix("."), let url = webURL(for: entity), let host = url.host()?.lowercased() else {
            return false
        }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let hasPath = url.path().count > 1
        if platformHosts.contains(bare) && !hasPath { return false }
        // A Wikipedia link without the article is just the site
        if bare.hasSuffix("wikipedia.org") && !hasPath { return false }
        // A domain needs a real-looking ending ("legaz.cafe" yes, "example.cor" no: OCR clipped it)
        let tld = bare.split(separator: ".").last.map(String.init) ?? ""
        return tld.count >= 2 && !["cor", "co m", "con"].contains(tld)
    }

    private static func site(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Booking references on passes and confirmations ("Confirmation code HLNTA5", "Reservation code: DQBMTH")
    static func bookingCodes(in text: String) -> [ExtractedEntity] {
        guard !text.isEmpty, let regex = try? NSRegularExpression(
            // "CONFIRMATION # | HLNTA5", "a new reservation code.\nDQBMTH"
            pattern: #"\b(?i:confirmation|reservation|booking|record locator)\b(?:\s*(?i:code|number|no\.?|#|id)\b)?[\s:#|.]{0,6}([A-Z0-9]{5,16})\b"#
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var codes: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: range) {
            guard let codeRange = Range(match.range(at: 1), in: text) else { continue }
            let code = String(text[codeRange])
            // A code mixes letters, or letters and digits; "NUMBER" or "123456" alone is a word or an amount
            guard code.contains(where: \.isLetter), !["NUMBER", "DETAILS", "CODE", "STATUS", "CONFIRMED", "REQUIRED", "PENDING", "SUMMARY", "CANCELLED"].contains(code),
                  !codes.contains(where: { $0.value == code }) else { continue }
            codes.append(ExtractedEntity(type: .oneTimeCode, value: code, normalized: code))
        }
        return codes
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
