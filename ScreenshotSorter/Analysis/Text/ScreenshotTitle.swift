import Foundation

/// A readable title without the language model: the place on a Maps card, else the screen's headline, else the app.
enum ScreenshotTitle {
    /// Words of apps' own buttons and tabs: "Following · Shop · For You" is on every TikTok screenshot
    private static let chrome: Set<String> = [
        "following", "for", "you", "shop", "explore", "local", "stem", "live", "friends", "inbox", "profile", "home",
        "search", "find", "related", "content", "suggested", "add", "this", "to", "your", "story", "expand", "sponsored",
        "comment", "comments", "location", "or", "ask", "a", "question", "send", "message", "reply", "photo", "more",
        "see", "translation", "follow", "share", "repost", "original", "sound", "playlist", "contains", "em", "o", "q",
        "instagram", "tiktok", "reddit", "threads", "pinterest", "youtube", "google", "maps", "safari",
        "followers", "posts", "likes", "views", "message", "edit", "profile"
    ]

    /// The model's title unless it only names the app or a collection ("Instagram", "Places"): then one from the text
    static func choose(model: String?, features: ExtractedFeatures, app: String?) -> String? {
        if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            let lowered = model.lowercased()
            let generic = lowered == app?.lowercased()
                || ScreenshotCategory.allCases.contains { $0.displayName.lowercased() == lowered }
                || chrome.contains(lowered)
            if !generic { return model }
        }
        return fallback(features: features, app: app)
    }

    /// Half a sentence ("Your confirmation ID is", "Tag someone you'd"), a legend ("/ - Slide Up"), a greeting
    private static func isFragment(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if let first = text.unicodeScalars.first, !CharacterSet.alphanumerics.contains(first), !"@#\"'“(".unicodeScalars.contains(first) {
            return true
        }
        // Greetings, social proof and shop banners
        let uiPhrases = ["good morning", "good afternoon", "good evening", "good night", "followed by", "only 1 left",
                         "only 2 left", "free shipping", "event details", "update", "new arrivals", "sold out", "limited time"]
        if uiPhrases.contains(where: { lowered.hasPrefix($0) }) { return true }
        let last = lowered.split { !$0.isLetter && $0 != "'" }.last.map(String.init) ?? ""
        return ["is", "the", "of", "to", "a", "an", "and", "for", "with", "by", "you'd", "your", "my", "in", "at", "on",
                "or", "that", "this", "are", "was", "be"].contains(last)
    }

    /// The screen's headline: the largest text that reads like words and isn't the app's own chrome
    static func headline(_ lines: [OCRLine]) -> String? {
        var best: (text: String, size: Double, index: Int)?
        for (index, line) in lines.enumerated() where line.zone == .body || line.zone == .topBar {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = text.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
            let content = words.filter { !chrome.contains($0) && $0.count >= 2 }
            let letters = text.filter(\.isLetter).count
            guard content.count >= 2 || (content.count == 1 && content[0].count >= 6),
                  text.count <= 90, Double(letters) >= Double(text.count) * 0.5,
                  // A sentence's tail ("is a great choice!") isn't a title
                  text.first.map({ !$0.isLowercase }) ?? false, !isFragment(text) else { continue }
            let size = line.box.height
            if best == nil || size > best!.size * 1.15 { best = (text, size, index) }
        }
        // "Quality Hats for", "Step 2:", "2004 Limited Edition >"
        return best.map { String($0.text.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: " :>•-–,")) }
    }

    static func fallback(features: ExtractedFeatures, app: String?) -> String? {
        // A Maps card is titled by the place, not its first long line ("• 2 hr 15 min")
        // The app is in the subtitle ("From TikTok"): the title is what it shows
        if let place = PlaceCard.name(in: features.lines.map(\.text)) { return String(place.prefix(60)) }
        return headline(features.lines) ?? firstSentence(features.lines) ?? app
    }

    /// The first line that reads like a sentence and isn't chrome: better than just "Instagram" when no line stands out
    static func firstSentence(_ lines: [OCRLine]) -> String? {
        lines.lazy
            .filter { $0.zone == .body || $0.zone == .topBar }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                let words = line.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
                return words.filter { !chrome.contains($0) && $0.count >= 2 }.count >= 3 && line.count <= 90 && !isFragment(line)
            }
            .map { String($0.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: " :>•-–,")) }
    }
}
