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
        let insight = ModelInsight(primary: .events, secondary: [.memes, .news], confidence: 0.92,
                                   app: "private_app", title: "", summary: "", tags: ["books", "private app", "novel"])
        let output = ScreenshotClassifier.classify(features: search, insight: insight, includeEntities: false)
        let result = output.categories.map(\.category)
        #expect(!result.contains(.events) && !result.contains(.memes) && !result.contains(.news))
        let tags = output.tags.map(\.value)
        #expect(tags.contains("novel"))
        #expect(!tags.contains("books") && !tags.contains("private app"))
        #expect(ScreenshotClassifier.knownApp("private_app") == nil)
        #expect(ScreenshotClassifier.knownApp("tiktok") == "TikTok")
    }

    @Test func modelFillsTheTopicGapOnFeedPosts() {
        let post = TestSupport.features(lines: [("Following", .topBar), ("Shop", .topBar), ("For You", .topBar),
                                                ("Visiting Boston's", .body), ("Ube cafe", .body), ("1,239", .body),
                                                ("Home", .bottomBar), ("Friends", .bottomBar), ("Inbox", .bottomBar),
                                                ("Profile", .bottomBar)])
        #expect(ScreenshotClassifier.classify(features: post, includeEntities: false).app?.appID == "tiktok")
        let rulesOnly = labels(post)
        #expect(!rulesOnly.contains(.places))
        let sure = ModelInsight(primary: .places, secondary: [], confidence: 0.9, app: nil, title: "Ube Cafe Boston",
                                summary: "", tags: [])
        #expect(labels(post, insight: sure).contains(.places))
        // Not on a guess, and never with the topics it falls back on when it has no idea
        let likely = ModelInsight(primary: .places, secondary: [], confidence: 0.7, app: nil, title: "", summary: "", tags: [])
        #expect(!labels(post, insight: likely).contains(.places))
        let fallback = ModelInsight(primary: .events, secondary: [], confidence: 0.9, app: nil, title: "", summary: "", tags: [])
        #expect(!labels(post, insight: fallback).contains(.events))
        // A stand-alone ad isn't a feed post: no gap filling there
        let ad = screen(["caraway_home", "Sponsored", "Holiday Savings", "Shop now"])
        let recipe = ModelInsight(primary: .recipes, secondary: [], confidence: 0.9, app: nil, title: "", summary: "", tags: [])
        #expect(!labels(ad, insight: recipe).contains(.recipes))
    }

    @Test func imageBackedAnswersLabelAloneExceptFallbackTopics() {
        let post = screen(["Kukbingwan", "specialty", "Seoul"])
        func insight(_ topic: ScreenshotCategory) -> ModelInsight {
            ModelInsight(primary: topic, secondary: [], confidence: 0.9, app: nil, title: "", summary: "", tags: [], sawImage: true)
        }
        #expect(labels(post, insight: insight(.food)).contains(.food))
        // Its fallbacks when unsure, image or not (events ~5/12 right on a real phone)
        #expect(!labels(post, insight: insight(.events)).contains(.events))
        #expect(!labels(post, insight: insight(.orders)).contains(.orders))
    }

    @Test func textlessScreenshotsAreNotSentToATextOnlyModel() {
        let photo = screen(["9:41"])
        #expect(!FMClassifier.isWorthAsking(photo, canSeeImages: false))
        #expect(FMClassifier.isWorthAsking(photo, canSeeImages: true))
        #expect(FMClassifier.isWorthAsking(screen(["Kaldi's Coffee", "4.6", "Open · Closes 5 PM"]), canSeeImages: false))
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

    @Test func peopleInsideAFeedPostNeedsMoreThanAFace() {
        var input = FusionInput()
        input.apps = [AppMatch(appID: "tiktok", displayName: "TikTok", category: .tiktok, confidence: 0.95)]
        input.vision = [.people: 0.7]
        #expect(!SignalFusion.fuse(input).map(\.category).contains(.people))
        // A creator's face on their own post isn't People either (right 3 times in 13 on a judged library)
        input.faces = FaceStats(count: 1, largestAreaFraction: 0.2, totalAreaFraction: 0.2)
        #expect(!SignalFusion.fuse(input).map(\.category).contains(.people))
        // Outside a feed, a face is: a selfie, a friend's photo
        input.apps = []
        #expect(SignalFusion.fuse(input).map(\.category).contains(.people))
    }

    @Test func shelfOrderStaysPutWhileCountsChange() {
        func collection(_ category: ScreenshotCategory, _ count: Int) -> ScreenshotCollection {
            ScreenshotCollection(kind: .category(category), title: category.displayName, icon: "", screenshots: [], count: count)
        }
        let ranking = ShelfRanking([collection(.food, 50), collection(.drinks, 20), collection(.places, 10),
                                    collection(.tiktok, 400), collection(.other, 99)])
        // Places now outnumbers food & drink, and a new category appeared
        let later = [collection(.tiktok, 500), collection(.places, 300), collection(.food, 60), collection(.recipes, 40),
                     collection(.drinks, 21), collection(.other, 120)]
        let shelves = ranking.shelves(later)
        #expect(shelves.map(\.group) == [ScreenshotCategory.food.group, ScreenshotCategory.places.group,
                                          ScreenshotCategory.tiktok.group, ScreenshotCategory.other.group])
        let foodShelf = shelves.first { $0.group == ScreenshotCategory.food.group }!.collections.map(\.category)
        #expect(foodShelf == [.food, .drinks, .recipes])
        // A fresh ranking follows the new counts; topic shelves still come before the biggest app shelf
        #expect(ShelfRanking(later).shelves(later).map(\.group).prefix(3) == [ScreenshotCategory.places.group,
                                                                              ScreenshotCategory.food.group,
                                                                              ScreenshotCategory.tiktok.group])
    }

    // MARK: Found judging every shelf of a real library (12 random members each)

    private let tiktok = AppMatch(appID: "tiktok", displayName: "TikTok", category: .tiktok, confidence: 0.95)

    @Test func someoneInTheFrameIsNotPeople() {
        // A creator talking about a market, an artist on a song page
        var post = FusionInput()
        post.apps = [tiktok]
        post.vision = [.people: 0.85]
        post.faces = FaceStats(count: 1, largestAreaFraction: 0.15, totalAreaFraction: 0.15)
        post.rules = [.places: 0.8]
        #expect(!SignalFusion.fuse(post).map(\.category).contains(.people))
        var songPage = FusionInput()
        songPage.vision = [.people: 0.85]
        songPage.faces = post.faces
        songPage.rules = [.music: 0.9]
        #expect(!SignalFusion.fuse(songPage).map(\.category).contains(.people))
        // A selfie is: and the clothes worn in it don't make it a fashion post
        var selfie = FusionInput()
        selfie.vision = [.people: 0.9, .clothes: 0.7]
        selfie.faces = FaceStats(count: 1, largestAreaFraction: 0.3, totalAreaFraction: 0.3)
        #expect(SignalFusion.fuse(selfie).map(\.category) == [.people])
    }

    @Test func secondTopicNeedsTwoKindsOfEvidence() {
        var post = FusionInput()
        post.rules = [.books: 0.9, .drinks: 0.7]
        let one = SignalFusion.fuse(post).map(\.category)
        #expect(one.contains(.books) && !one.contains(.drinks))
        post.vision = [.drinks: 0.6]
        #expect(SignalFusion.fuse(post).map(\.category).contains(.drinks))
    }

    @Test func backgroundPlantsInAFeedPostAreNotPlants() {
        var cafe = FusionInput()
        cafe.apps = [tiktok]
        cafe.vision = [.plants: 0.65]
        #expect(!SignalFusion.fuse(cafe).map(\.category).contains(.plants))
        cafe.vision = [.plants: 0.85]
        #expect(SignalFusion.fuse(cafe).map(\.category).contains(.plants))
    }

    @Test func productBarcodesAreNotCodes() {
        var book = FusionInput()
        book.barcodes = [BarcodeInfo(payload: "9780374534202", symbology: "VNBarcodeSymbologyEAN13")]
        #expect(!SignalFusion.fuse(book).map(\.category).contains(.codes))
        book.barcodes = [BarcodeInfo(payload: "https://example.com", symbology: "VNBarcodeSymbologyQR")]
        #expect(SignalFusion.fuse(book).map(\.category).contains(.codes))
    }

    @Test func genericWordsDontLabelOnTheirOwn() {
        // A captive Wi-Fi sheet, a post about a bug, a history book page, a place card's Directions button
        #expect(!labels(screen(["Free Wi-Fi", "Airport guest network", "Email address", "Connect"])).contains(.settings))
        #expect(!labels(screen(["r/ClaudeAI", "Found a bug: the search plugin has an issue", "Same problem here"])).contains(.errors))
        #expect(!labels(screen(["Shinto in the Ancient Period", "officials said the government", "according to the record"]))
            .contains(.news))
        #expect(!labels(screen(["Wo Hop", "4.3", "Chinese restaurant", "Directions", "17 Mott St", "12 min"])).contains(.directions))
        #expect(labels(screen(["0.4 mi", "Kebo St", "25", "mph", "Spring St"])).contains(.directions))
        #expect(!labels(screen(["things to do in kyoto", "Notes", "Remember me"])).contains(.notes))
        #expect(!labels(screen(["Following", "For You", "ramen spot", "Home", "Friends", "Inbox", "Profile"])).contains(.email))
        #expect(!labels(screen(["Your cart", "Subtotal $89", "Promo code", "Checkout"])).contains(.receipts))
        #expect(!labels(screen(["Carrom board", "$129", "Estimated delivery Oct 3", "Free shipping", "Add to cart"])).contains(.orders))
        #expect(labels(screen(["Balcony • Row H", "$123 each incl. fees", "1-5 tickets"])).contains(.tickets))
    }

    @Test func modelCantAddWhatTheRulesRuleOut() {
        let film = screen(["Fujifilm Camera", "My favorite film simulations", "Recipes Kodak Portra 400",
                           "Grain effect: strong", "Dynamic range: DR400"])
        let insight = ModelInsight(primary: .recipes, secondary: [], confidence: 0.9, app: nil, title: "", summary: "",
                                   tags: [], sawImage: true)
        #expect(!labels(film, insight: insight).contains(.recipes))
    }

    // MARK: Found judging all 1,938 screenshots of a real library

    @Test func feedPostsTheAppMissedBefore() {
        let story = screen(["throwingfits", "Suggested for you", "Follow", "In the City", "Joan Silber"])
        #expect(ScreenshotClassifier.classify(features: story, includeEntities: false).app?.appID == "instagram")
        let comments = screen(["124 comments", "View 4 replies", "the best matcha in kyoto", "Add comment..."])
        #expect(ScreenshotClassifier.classify(features: comments, includeEntities: false).app?.appID == "tiktok")
    }

    @Test func whatAFeedPostShowsInPassingIsNotItsTopic() {
        var post = FusionInput()
        post.apps = [tiktok]
        post.vision = [.art: 0.65, .clothes: 0.8]
        post.rules = [.books: 0.9]
        let labels = SignalFusion.fuse(post).map(\.category)
        #expect(labels.contains(.books) && !labels.contains(.art) && !labels.contains(.clothes))
    }

    @Test func foodAtAVenueIsAPlaceToo() {
        let cafe = screen(["Following", "For You", "the cutest little cafe", "Thai tea latte and matcha latte",
                           "Home", "Friends", "Inbox", "Profile"])
        let result = labels(cafe)
        #expect(result.contains(.drinks) && result.contains(.places))
    }

    @Test func tagsLeaveOutTheAppAndPassingObjects() {
        let post = TestSupport.features(lines: [("Following", .topBar), ("For You", .topBar), ("Shop", .topBar),
                                                ("lamp with ceramic base", .body)],
                                        labels: [("jeans", 0.9), ("lamp", 0.9)])
        let tags = ScreenshotClassifier.classify(features: post, includeEntities: false).tags.map(\.value)
        #expect(!tags.contains("tiktok") && !tags.contains("jeans"))
    }
}
