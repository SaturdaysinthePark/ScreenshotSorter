import Foundation
import FoundationModels

/// Category vocabulary the language model may choose from.
/// Case names must mirror `ScreenshotCategory` (enforced by `CategoryKeySyncTests`).
@Generable
enum CategoryKey: CaseIterable {
    case events, codes, receipts, directions, places, clothes, people, shoes
    case imessage, whatsapp, signal, telegram, discord, slack, email, gmail
    case instagram, tiktok, twitter, facebook, linkedin, reddit, youtube, food
    case drinks, cooking, recipes, stores, storefronts, watches, furniture, bags
    case jewelry, vehicles, electronics, homes, sitesOfInterest, animals, quotes, nature
    case landscapes, beaches, mountains, flowers, plants, sunset, books, movies
    case music, videoGames, flights, memes, sports, exercise, art, reading
    case documents, health, notes, weather, news, notifications, iosHomeScreens, settings
    case errors, finance, tickets, orders, programming, aiChats, other

    var category: ScreenshotCategory? {
        ScreenshotCategory(key: String(describing: self))
    }
}

@Generable
struct ScreenshotInsightResponse {
    @Guide(description: "The single best category for this screenshot")
    var primary: CategoryKey

    @Guide(description: "Up to 3 other categories that also clearly apply; empty if none")
    var secondary: [CategoryKey]

    @Guide(description: "Confidence in the primary category from 0 to 100")
    var confidence: Int

    @Guide(description: "Name of the app the screenshot was taken in, or an empty string if unclear")
    var app: String

    @Guide(description: "A short, specific title of at most 8 words")
    var title: String

    @Guide(description: "One plain sentence describing what the screenshot shows")
    var summary: String

    @Guide(description: "3 to 8 short lowercase tags: brands, products, places, people, topics")
    var tags: [String]
}

@Generable
struct CollectionNameResponse {
    @Guide(description: "A friendly collection name of 1 to 3 words in Title Case")
    var name: String

    @Guide(description: "The best matching SF Symbol name from the allowed list")
    var symbol: String
}
