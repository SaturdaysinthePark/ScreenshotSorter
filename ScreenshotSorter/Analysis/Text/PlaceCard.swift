import Foundation

/// Reads a Maps place card (Google or Apple Maps): the place's name is the line above its rating
/// ("Pocketbook Hudson" / "4.3 ★ (60) · Hotel"), with a Directions button a few lines below. Cards often show no
/// address, so the name is what Maps gets searched for, and what the screenshot is titled.
enum PlaceCard {
    static func name(in lines: [String]) -> String? {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let card = nameAboveRating(lines) { return card }
        // Scrolled past the buttons: the name sits right above the "Overview · Menu · Reviews" tabs
        guard !lines.contains(where: { $0.lowercased() == "directions" }),
              let overview = lines.firstIndex(where: { $0.lowercased() == "overview" }), overview > 0,
              lines[(overview + 1)..<min(lines.count, overview + 3)].contains(where: { ["menu", "reviews", "prices"].contains($0.lowercased()) }),
              isName(lines[overview - 1]), looksLikeVenue(lines[overview - 1]),
              // One word ("Lingo") is too vague for Maps without the card's address
              lines[overview - 1].split(separator: " ").count >= 2 else { return nil }
        return lines[overview - 1]
    }

    private static func nameAboveRating(_ lines: [String]) -> String? {
        guard let directions = lines.firstIndex(where: { $0.lowercased() == "directions" }) else { return nil }
        for index in stride(from: directions - 1, through: max(0, directions - 5), by: -1) where isRating(lines[index]) {
            // The name sits right above the rating; a second line above it is a wrapped long name at most
            for candidate in stride(from: index - 1, through: max(0, index - 2), by: -1) {
                let name = cleaned(lines[candidate])
                if isName(name) && !isCaption(name) { return name }
            }
            return nil
        }
        return nil
    }

    /// A venue tagged on a TikTok post: the pill above "1,329 people posted about this place". Most pills are a city
    /// ("Manhattan", "Mexico City"), not somewhere to go; a venue comes with its area ("Catskill Mountains • Phoenicia",
    /// "KOFFEE MAMEYA Kakeru - Koto City").
    static func taggedVenue(in lines: [String]) -> String? {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let counters = ["posted about this place", "featured this place", "posts of this place", "shared related posts",
                        "discover more"]
        guard let counter = lines.firstIndex(where: { line in counters.contains { line.lowercased().contains($0) } }) else {
            return nil
        }
        for index in stride(from: counter - 1, through: max(0, counter - 3), by: -1) {
            let line = lines[index]
            for separator in [" • ", " · ", " - "] where line.contains(separator) {
                let parts = line.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
                // "Gottesman Research Librar..." was cut off: Maps can't find half a name
                // An area has no digits ("Izyyng • 1d ago" is a username and a time)
                guard parts.count == 2, parts.allSatisfy({ $0.filter(\.isLetter).count >= 2 }),
                      !parts.contains(where: { $0.hasSuffix("...") || $0.hasSuffix("…") }),
                      !parts[1].contains(where: \.isNumber) else { continue }
                // "Plaza Mayor, Madrid • Madrid"
                if parts[0].lowercased().hasSuffix(parts[1].lowercased()) { return parts[0] }
                return parts.joined(separator: ", ")
            }
        }
        return nil
    }

    /// What to search Maps for: a Maps card's name, a venue tag with its area, or a caption line naming a venue and
    /// its street address ("Nuar - 48 W 27th St"). Only places spelled out like that: a post's big overlay text names a
    /// dish, a product, a list or a district as often as a venue (14 right in 39 on a judged library), and a city
    /// alone isn't somewhere to go.
    static func mapsQuery(lines: [OCRLine], categories: Set<ScreenshotCategory>) -> String? {
        let texts = lines.map(\.text)
        if let card = name(in: texts) { return card }
        if let venue = taggedVenue(in: texts) { return venue }
        guard !categories.isDisjoint(with: [.places, .food, .drinks]) else { return nil }
        return venueWithAddress(in: texts)
    }

    /// "Nuar - 48 W 27th St", "Kasa Ramen · 811 W 10th Ave"
    static func venueWithAddress(in lines: [String]) -> String? {
        for line in lines.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            for separator in [" - ", " · ", " • ", " – "] where line.contains(separator) {
                let parts = line.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, looksLikeVenue(parts[0]),
                      // A number then a street ("48 W 27th St"), not "1d ago"
                      parts[1].range(of: #"^\d{1,5}[A-Za-z]?\s+.*\b(St|Street|Ave|Avenue|Rd|Road|Blvd|Dr|Drive|Ln|Lane|Way|Pl|Place|Sq|Square|Ct|Hwy|Pkwy)\b"#,
                                     options: [.regularExpression, .caseInsensitive]) != nil else { continue }
                return parts.joined(separator: ", ")
            }
        }
        return nil
    }

    /// Words of a caption about a place, not a place's name ("MUST EAT food in Tokyo", "Day 6", "best stores")
    private static let notAName: Set<String> = [
        "best", "spots", "spot", "places", "place", "things", "must", "guide", "part", "day", "pov", "how", "why",
        "what", "where", "top", "my", "i", "we", "you", "is", "are", "was", "food", "trip", "itinerary", "favorite",
        "favourite", "hidden", "gems", "visit", "list", "haul", "called", "eat", "try", "rating", "stores", "shops",
        "cafes", "restaurants", "this", "these", "here", "if", "when", "worth", "new", "street"
    ]

    static func looksLikeVenue(_ text: String) -> Bool {
        let raw = text.split { !$0.isLetter && $0 != "'" && $0 != "&" }.map(String.init).filter { $0 != "&" }
        let words = raw.map { $0.lowercased() }
        guard (1...5).contains(words.count), !text.contains(where: \.isNumber), !text.contains(":"),
              !text.contains("!"), !text.contains("?") || text.count <= 12 else { return false }
        if words.count == 1 {
            // A descriptor in capitals ("PERSONALISED"), not a name
            let word = words[0]
            if word.count < 4 || ["ed", "ing", "ly", "ous", "ful"].contains(where: { word.hasSuffix($0) }) { return false }
        }
        // A name is styled one way: "Togoshi Ginza", "udon shin", "AT YOUR LEISURE"; "Wagyu & tsukiji" is a caption
        let capitalised = raw.filter { $0.first?.isUppercase == true }.count
        guard capitalised == raw.count || capitalised == 0 || raw.count == 1 else { return false }
        return words.allSatisfy { !notAName.contains($0) }
    }

    /// "4.3", "4.6 ★ (850)", "4,7 ★★★★★ (3,743) · 16 min"
    private static func isRating(_ line: String) -> Bool {
        line.range(of: #"^[1-5][.,][0-9](\s|$|★|\*|\(|·)"#, options: .regularExpression) != nil
    }

    /// "CRIA CAFÉ Cafés Especiais 4)", "Casa Pedregal 1": a badge or photo count read into the name
    private static func cleaned(_ line: String) -> String {
        line.replacingOccurrences(of: #"\s*\d\s*[)）]?$|\s*[)）]$"#, with: "", options: .regularExpression)
    }

    /// A creator's caption laid over a Maps card ("favorite temple", "UNIQLO was one of", "real. This place is a")
    private static func isCaption(_ line: String) -> Bool {
        if ScreenshotTitle.isFragment(line) || line.contains(". ") { return true }
        // Lower case and three words or more is a sentence ("had so much stuff"); short lower-case names are real
        // ("le gaz", "recess grove"); a stray letter in front is OCR of the caption's edge ("p Kebab")
        let words = line.split(separator: " ")
        guard line.first?.isLowercase ?? false else { return false }
        return words.count >= 3 || (words.first?.count == 1)
    }

    private static func isName(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        guard (2...60).contains(line.count), letters >= 2 else { return false }
        // Not the status bar's clock or a search field
        if line.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return false }
        // Nor a feed's own chrome showing through ("LIVE", "STEM")
        return !["search here", "search maps", "live", "stem", "explore", "following", "for you", "shop"].contains(line.lowercased())
    }
}
