import Foundation

/// A search query broken into structured filters and free text.
struct ParsedQuery: Sendable, Equatable {
    var raw: String = ""
    /// Normalized free-text tokens (stop words removed)
    var terms: [String] = []
    /// Quoted phrases
    var phrases: [String] = []
    var dateRange: DateInterval?
    var categories: Set<ScreenshotCategory> = []
    /// App display names (lowercased)
    var apps: Set<String> = []
    var entityTypes: Set<EntityType> = []

    var hasFreeText: Bool { !terms.isEmpty || !phrases.isEmpty }
    var hasFilters: Bool { dateRange != nil || !categories.isEmpty || !apps.isEmpty || !entityTypes.isEmpty }
    var isEmpty: Bool { !hasFreeText && !hasFilters }
    var freeText: String { (phrases + terms).joined(separator: " ") }
}

/// Deterministic natural-language query parsing ("receipts from last week", "nike in march",
/// "tweets with links"). Runs on every keystroke, so no ML here.
enum QueryParser {
    static let stopWords: Set<String> = [
        "a", "an", "the", "of", "in", "on", "at", "from", "with", "about", "my", "that", "this", "these",
        "those", "show", "me", "find", "all", "for", "to", "and", "or", "screenshot", "screenshots", "pic",
        "pics", "picture", "pictures", "photo", "photos", "image", "images", "some", "any", "where", "i", "saved"
    ]

    /// Extra category vocabulary on top of each category's display name.
    static let categorySynonyms: [String: ScreenshotCategory] = [
        "receipt": .receipts, "receipts": .receipts, "invoice": .receipts, "invoices": .receipts,
        "tweet": .twitter, "tweets": .twitter, "twitter": .twitter, "insta": .instagram, "ig": .instagram,
        "boarding pass": .tickets, "boarding passes": .tickets, "ticket": .tickets, "tickets": .tickets,
        "qr": .codes, "qr code": .codes, "qr codes": .codes, "barcode": .codes,
        "recipe": .recipes, "recipes": .recipes, "meme": .memes, "memes": .memes,
        "flight": .flights, "flights": .flights, "hotel": .flights, "trip": .flights,
        "bank": .finance, "money": .finance, "payment": .finance, "venmo": .finance,
        "package": .orders, "packages": .orders, "delivery": .orders, "shipping": .orders, "order": .orders, "orders": .orders,
        "chatgpt": .aiChats, "ai chat": .aiChats, "ai chats": .aiChats,
        "email": .email, "emails": .email, "mail": .email,
        "error": .errors, "errors": .errors, "bug": .errors, "crash": .errors,
        "home screen": .iosHomeScreens, "home screens": .iosHomeScreens,
        "dog": .animals, "dogs": .animals, "cat": .animals, "cats": .animals, "pet": .animals, "pets": .animals,
        "outfit": .clothes, "outfits": .clothes, "sneakers": .shoes, "workout": .health, "workouts": .health,
        "song": .music, "songs": .music, "movie": .movies, "movies": .movies, "book": .books,
        "code snippet": .programming, "code": .programming, "article": .news, "articles": .news,
        "map": .directions, "maps": .directions, "event": .events, "invite": .events, "concert": .events
    ]

    static let entitySynonyms: [String: EntityType] = [
        "link": .url, "links": .url, "url": .url, "urls": .url, "website": .url,
        "phone": .phone, "phone number": .phone, "number": .phone,
        "address": .address, "addresses": .address,
        "tracking": .tracking, "tracking number": .tracking,
        "price": .price, "prices": .price,
        "verification code": .oneTimeCode, "otp": .oneTimeCode
    ]

    private static let monthNames: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9,
        "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12
    ]

    /// Phrase → category, built once (longest phrases first).
    private static let categoryPhrases: [(String, ScreenshotCategory)] = {
        var map: [String: ScreenshotCategory] = [:]
        for category in ScreenshotCategory.assignable where category != .other {
            map[TextNormalizer.normalizeTerm(category.displayName)] = category
        }
        for (phrase, category) in categorySynonyms {
            map[TextNormalizer.normalizeTerm(phrase)] = category
        }
        return map.sorted { $0.key.split(separator: " ").count > $1.key.split(separator: " ").count }
    }()

    private static let appPhrases: [(String, String)] = {
        var map: [String: String] = [:]
        for signature in AppSignatures.all {
            let display = signature.displayName.lowercased()
            for name in [signature.displayName, signature.appID] + signature.names {
                let normalized = TextNormalizer.normalizeTerm(name)
                if normalized.count >= 3 { map[normalized] = display }
            }
        }
        return map.sorted { $0.key.split(separator: " ").count > $1.key.split(separator: " ").count }
    }()

    static func parse(_ query: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedQuery {
        var parsed = ParsedQuery(raw: query)

        // Quoted phrases first
        var remainder = query
        if let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"") {
            let ns = query as NSString
            for match in regex.matches(in: query, range: NSRange(location: 0, length: ns.length)) {
                let phrase = TextNormalizer.normalizeTerm(ns.substring(with: match.range(at: 1)))
                if !phrase.isEmpty { parsed.phrases.append(phrase) }
            }
            remainder = regex.stringByReplacingMatches(in: query, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }

        var tokens = TextNormalizer.tokenize(remainder)

        parsed.dateRange = extractDate(from: &tokens, now: now, calendar: calendar)

        for (phrase, type) in entitySynonyms.sorted(by: { $0.key.count > $1.key.count }) {
            if remove(phrase: TextNormalizer.normalizeTerm(phrase), from: &tokens) { parsed.entityTypes.insert(type) }
        }
        for (phrase, display) in appPhrases where remove(phrase: phrase, from: &tokens) {
            parsed.apps.insert(display)
        }
        for (phrase, category) in categoryPhrases where remove(phrase: phrase, from: &tokens) {
            parsed.categories.insert(category)
        }

        parsed.terms = tokens.filter { !stopWords.contains($0) }
        return parsed
    }

    /// Removes the first occurrence of a (multi-token) phrase. Returns true if found.
    @discardableResult
    static func remove(phrase: String, from tokens: inout [String]) -> Bool {
        let parts = phrase.split(separator: " ").map(String.init)
        guard !parts.isEmpty, parts.count <= tokens.count else { return false }
        for start in 0...(tokens.count - parts.count) where Array(tokens[start..<start + parts.count]) == parts {
            tokens.removeSubrange(start..<start + parts.count)
            return true
        }
        return false
    }

    // MARK: Dates

    static func extractDate(from tokens: inout [String], now: Date, calendar: Calendar) -> DateInterval? {
        let startOfToday = calendar.startOfDay(for: now)
        func interval(_ start: Date, _ end: Date) -> DateInterval { DateInterval(start: start, end: max(start, end)) }
        func days(_ count: Int) -> Date { calendar.date(byAdding: .day, value: count, to: startOfToday) ?? startOfToday }

        if remove(phrase: "today", from: &tokens) { return interval(startOfToday, now) }
        if remove(phrase: "yesterday", from: &tokens) { return interval(days(-1), startOfToday) }

        let relative: [(String, Calendar.Component, Int)] = [
            ("this week", .weekOfYear, 0), ("last week", .weekOfYear, -1), ("past week", .day, -7),
            ("this month", .month, 0), ("last month", .month, -1), ("past month", .day, -30),
            ("this year", .year, 0), ("last year", .year, -1), ("past year", .day, -365)
        ]
        for (phrase, component, offset) in relative where remove(phrase: phrase, from: &tokens) {
            if component == .day {
                return interval(days(offset), now)
            }
            guard let current = calendar.dateInterval(of: component, for: now) else { return nil }
            if offset == 0 { return interval(current.start, now) }
            guard let previousStart = calendar.date(byAdding: component, value: offset, to: current.start) else { return nil }
            return interval(previousStart, current.start)
        }

        // "last 3 days" / "past 2 weeks"
        for index in tokens.indices.dropLast(2) where tokens[index] == "last" || tokens[index] == "past" {
            guard let count = Int(tokens[index + 1]) else { continue }
            let unit = tokens[index + 2]
            var start: Date?
            if unit.hasPrefix("day") { start = days(-count) }
            if unit.hasPrefix("week") { start = days(-7 * count) }
            if unit.hasPrefix("month") { start = calendar.date(byAdding: .month, value: -count, to: startOfToday) }
            if let start {
                tokens.removeSubrange(index...index + 2)
                return interval(start, now)
            }
        }

        // Month name, optionally followed by a year ("march", "march 2024")
        for (index, token) in tokens.enumerated() {
            // "may" is too often a verb; only accept it with a year or after "in"
            guard let month = monthNames[token] else { continue }
            let followedByYear = index + 1 < tokens.count ? Int(tokens[index + 1]).flatMap { (1990...2100).contains($0) ? $0 : nil } : nil
            let precededByIn = index > 0 && tokens[index - 1] == "in"
            if token == "may" && followedByYear == nil && !precededByIn { continue }
            var year = followedByYear ?? calendar.component(.year, from: now)
            if followedByYear == nil && month > calendar.component(.month, from: now) { year -= 1 }
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            tokens.removeSubrange(index...(followedByYear == nil ? index : index + 1))
            return interval(start, end)
        }

        // Bare year
        for (index, token) in tokens.enumerated() {
            guard token.count == 4, let year = Int(token), (2007...2100).contains(year),
                  let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else { continue }
            tokens.remove(at: index)
            return interval(start, end)
        }
        return nil
    }
}
