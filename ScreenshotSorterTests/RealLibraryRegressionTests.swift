import CoreGraphics
import Testing
@testable import ScreenshotSorter

/// Mistakes found re-scoring a real 1,938-screenshot library (`Tools/eval/run.sh --db`), reduced to
/// minimal, scrubbed cases.
struct RealLibraryRegressionTests {

    private func labels(_ features: ExtractedFeatures, insight: ModelInsight? = nil) -> [ScreenshotCategory] {
        ScreenshotClassifier.classify(features: features, insight: insight, includeEntities: false).categories.map(\.category)
    }

    /// Spread lines down the screen so layout patterns see real positions
    private func screen(_ lines: [String], labels: [(String, Double)] = []) -> ExtractedFeatures {
        let step = 0.9 / Double(max(lines.count, 1))
        let boxes = lines.indices.map { CGRect(x: 0.05, y: 0.08 + Double($0) * step, width: 0.9, height: step * 0.8) }
        return TestSupport.features(lines: lines.map { ($0, .body) }, labels: labels, boxes: boxes)
    }

    @Test func adBannerInCapitalsIsNotAMeme() {
        let ad = screen(["studiofurnis.com", "Instagram", "TODAY: $150 CREDIT TOWARDS ANY BED PURCHASE",
                         "USE CODE: \"150\"", "SHOP THE SPRING SALE NOW", "GET 10% OFF YOUR FIRST ORDER", "STUDIO FURNIS"])
        #expect(!labels(ad).contains(.memes))
        let menu = screen(["DINNER DAWAT", "WOOD-FIRED POLENTA BREAD", "shallot-tomato butter, nigella seeds",
                           "SMOKED EGGPLANT BHARTHA", "serrano chili, cilantro", "GRILLED KABOCHA SQUASH",
                           "marinated feta, tamarind chutney", "GRILLED MALAI PRAWN", "coconut, curry leaf",
                           "CARDAMOM RICE PUDDING WITH PISTACHIO", "rose, saffron"])
        #expect(!labels(menu).contains(.memes))
        let meme = screen(["ONE DOES NOT SIMPLY", "WAKE UP BEFORE 9 ON A SATURDAY", "4.2K", "318 Share"])
        #expect(labels(meme).contains(.memes))
    }

    @Test func newYorkIsNotNews() {
        let event = screen(["Post", "letmebeyournavigator", "Brooklyn, New York", "MAY 14, 5 - 10 PM", "46 PARK ST, BK",
                            "ALL DONATIONS WILL GO TO CHARITY", "New Message", "New York, NY"] + Array(repeating: "details", count: 12))
        #expect(!labels(event).contains(.news))
    }

    @Test func bestsellerCoverIsBooksNotNews() {
        let cover = screen(["NEW YORK TIMES BESTSELLING AUTHOR", "KEN FOLLETT", "EYE OF THE NEEDLE", "Eye of the Needle",
                            "by Ken Follett", "4.22 · 17,000 ratings", "Want to Read", "Rate this book"])
        let result = labels(cover)
        #expect(result.contains(.books))
        #expect(!result.contains(.news))
    }

    @Test func languageModelAloneDoesNotAddCategories() {
        let search = screen(["Memoirs of hadrian", "Title", "Author", "Showing results 1-5 of 45"])
        let insight = ModelInsight(primary: .events, secondary: [.memes, .reading], confidence: 0.92,
                                   app: "private_app", title: "", summary: "", tags: ["books", "private app", "novel"])
        let output = ScreenshotClassifier.classify(features: search, insight: insight, includeEntities: false)
        let result = output.categories.map(\.category)
        #expect(!result.contains(.events) && !result.contains(.memes) && !result.contains(.reading))
        let tags = output.tags.map(\.value)
        #expect(tags.contains("novel"))
        #expect(!tags.contains("books") && !tags.contains("private app"))
        #expect(ScreenshotClassifier.knownApp("private_app") == nil)
        #expect(ScreenshotClassifier.knownApp("tiktok") == "TikTok")
    }

    @Test func namesFromOCRAreNotTags() {
        let features = screen(["bonus bet tokens", "Claim now"])
        let entities = [ExtractedEntity(type: .organization, value: "bonus bet tokens", normalized: nil)]
        let tags = ScreenshotClassifier.classify(features: features, entities: entities).tags.map(\.value)
        #expect(!tags.contains("bonus bet tokens"))
    }

    @Test func passingProductMentionInAnArticleIsNotJewelry() {
        var lines = ["Shinto in the Ancient Period", "23"]
        lines += (0..<36).map { "the ritual objects of the period, line \($0) of a long history text about the kami" }
        lines.insert("a bronze mirror, a sword and a bracelet were offered", at: 10)
        #expect(!labels(screen(lines)).contains(.jewelry))
    }

    @Test func mapsPlaceCardIsAPlaceNotDirections() {
        let card = screen(["Kasa Ramen", "4.3", "(1,245)", "Japanese restaurant · €10-20 · 18 min",
                           "Open · Closes 4:30 PM", "Directions", "Start", "Call", "Website", "Overview", "Menu", "Reviews"])
        let result = labels(card)
        #expect(result.contains(.places))
        #expect(!result.contains(.directions))
        let route = screen(["Your location → Citizen M NOMA", "Avoid tolls", "4h 32m", "230.1 mi", "Fastest route", "Go"])
        #expect(labels(route).contains(.directions))
    }

    @Test func tabBarInboxIsNotEmail() {
        let feed = screen(["Following", "Shop", "For You", "matcha tastes like grass", "Kyoto", "Home", "Friends", "Inbox", "Profile"])
        #expect(!labels(feed).contains(.email))
    }

    @Test func faceLessPeopleInsideAnAppNeedsMoreEvidence() {
        var input = FusionInput()
        input.apps = [AppMatch(appID: "tiktok", displayName: "TikTok", category: .tiktok, confidence: 0.95)]
        input.vision = [.people: 0.7]
        #expect(!SignalFusion.fuse(input).map(\.category).contains(.people))
        input.faces = FaceStats(count: 1, largestAreaFraction: 0.2, totalAreaFraction: 0.2)
        #expect(SignalFusion.fuse(input).map(\.category).contains(.people))
    }

    @Test func shelfOrderStaysPutWhileCountsChange() {
        func collection(_ category: ScreenshotCategory, _ count: Int) -> ScreenshotCollection {
            ScreenshotCollection(kind: .category(category), title: category.displayName, icon: "", screenshots: [], count: count)
        }
        let ranking = ShelfRanking([collection(.food, 50), collection(.drinks, 20), collection(.tiktok, 10), collection(.other, 99)])
        // Social now outnumbers food & drink, and a new category appeared
        let later = [collection(.tiktok, 300), collection(.food, 60), collection(.recipes, 40), collection(.drinks, 21), collection(.other, 120)]
        let shelves = ranking.shelves(later)
        #expect(shelves.map(\.group) == [ScreenshotCategory.food.group, ScreenshotCategory.tiktok.group, ScreenshotCategory.other.group])
        let foodShelf = shelves.first { $0.group == ScreenshotCategory.food.group }!.collections.map(\.category)
        #expect(foodShelf == [.food, .drinks, .recipes])
        // A fresh ranking follows the new counts
        #expect(ShelfRanking(later).shelves(later).first?.group == ScreenshotCategory.tiktok.group)
    }
}
