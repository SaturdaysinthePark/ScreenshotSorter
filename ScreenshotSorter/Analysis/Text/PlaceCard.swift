import Foundation

/// Reads a Maps place card (Google or Apple Maps): the place's name is the line above its rating
/// ("Pocketbook Hudson" / "4.3 ★ (60) · Hotel"), with a Directions button a few lines below. Cards often show no
/// address, so the name is what Maps gets searched for, and what the screenshot is titled.
enum PlaceCard {
    static func name(in lines: [String]) -> String? {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let directions = lines.firstIndex(where: { $0.lowercased() == "directions" }) else { return nil }
        for index in stride(from: directions - 1, through: max(0, directions - 5), by: -1) where isRating(lines[index]) {
            // The name sits right above the rating; a second line above it is a wrapped long name at most
            for candidate in stride(from: index - 1, through: max(0, index - 2), by: -1) where isName(lines[candidate]) {
                return lines[candidate]
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
        let counters = ["posted about this place", "featured this place", "posts of this place", "shared related posts"]
        guard let counter = lines.firstIndex(where: { line in counters.contains { line.lowercased().contains($0) } }) else {
            return nil
        }
        for index in stride(from: counter - 1, through: max(0, counter - 3), by: -1) {
            let line = lines[index]
            for separator in [" • ", " · ", " - "] where line.contains(separator) {
                let parts = line.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts.allSatisfy({ $0.filter(\.isLetter).count >= 2 }) else { continue }
                return parts.joined(separator: ", ")
            }
        }
        return nil
    }

    /// "4.3", "4.6 ★ (850)", "4,7 ★★★★★ (3,743) · 16 min"
    private static func isRating(_ line: String) -> Bool {
        line.range(of: #"^[1-5][.,][0-9](\s|$|★|\*|\(|·)"#, options: .regularExpression) != nil
    }

    private static func isName(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        guard (2...60).contains(line.count), letters >= 2 else { return false }
        // Not the status bar's clock or a search field
        if line.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return false }
        return !["search here", "search maps"].contains(line.lowercased())
    }
}
