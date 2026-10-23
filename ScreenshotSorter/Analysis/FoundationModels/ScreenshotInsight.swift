import Foundation
import FoundationModels

/// What the model may pick as a screenshot's topic: every category except the apps themselves (which app a
/// screenshot came from is the app detector's job). Case names are what the model reads, so they are plain
/// words, not our keys: as "codes", QR codes collected code screenshots; as "receipts", every price tag.
/// "other" comes first because the model leans to the first case when unsure, and abstaining is the safe lean.
@Generable
enum TopicKey: CaseIterable {
    case other
    case event, qrCode, paymentReceipt, directions, place, clothing, peoplePhoto, shoes
    case food, drink, recipe, shopping, watch, furniture, bag, jewelry, vehicle, electronics
    case homeInterior, animal, quote, nature, plant, book, movieOrShow, music, videoGame
    case travel, meme, sports, art, document, healthFitness, note, weather, newsArticle, notification
    case homeScreen, settings, errorMessage, money, ticketOrPass, orderOrDelivery, code, aiChat

    var category: ScreenshotCategory? {
        switch self {
        case .other: return .other
        case .event: return .events
        case .qrCode: return .codes
        case .paymentReceipt: return .receipts
        case .directions: return .directions
        case .place: return .places
        case .clothing: return .clothes
        case .peoplePhoto: return .people
        case .shoes: return .shoes
        case .food: return .food
        case .drink: return .drinks
        case .recipe: return .recipes
        case .shopping: return .stores
        case .watch: return .watches
        case .furniture: return .furniture
        case .bag: return .bags
        case .jewelry: return .jewelry
        case .vehicle: return .vehicles
        case .electronics: return .electronics
        case .homeInterior: return .homes
        case .animal: return .animals
        case .quote: return .quotes
        case .nature: return .nature
        case .plant: return .plants
        case .book: return .books
        case .movieOrShow: return .movies
        case .music: return .music
        case .videoGame: return .videoGames
        case .travel: return .flights
        case .meme: return .memes
        case .sports: return .sports
        case .art: return .art
        case .document: return .documents
        case .healthFitness: return .health
        case .note: return .notes
        case .weather: return .weather
        case .newsArticle: return .news
        case .notification: return .notifications
        case .homeScreen: return .iosHomeScreens
        case .settings: return .settings
        case .errorMessage: return .errors
        case .money: return .finance
        case .ticketOrPass: return .tickets
        case .orderOrDelivery: return .orders
        case .code: return .programming
        case .aiChat: return .aiChats
        }
    }
}

/// Words, not a 0–100 number: the model said 90+ about nearly everything when asked for a percentage.
@Generable
enum Certainty {
    case sure, likely, unsure

    var confidence: Double {
        switch self {
        case .sure: return 0.9
        case .likely: return 0.7
        case .unsure: return 0.4
        }
    }
}

/// Properties are generated in declaration order: describing the screenshot first gives the topic choice
/// something to stand on.
@Generable
struct ScreenshotInsightResponse {
    @Guide(description: "One plain sentence describing what the screenshot shows")
    var summary: String

    @Guide(description: "The single best topic for what the screenshot is about")
    var primary: TopicKey

    @Guide(description: "Other topics that clearly apply too; usually none", .maximumCount(2))
    var secondary: [TopicKey]

    @Guide(description: "How sure you are about that topic")
    var certainty: Certainty

    @Guide(description: "Name of the app the screenshot was taken in, or an empty string if unclear")
    var app: String

    @Guide(description: "What it is, by name, at most 8 words: a book as Title – Author, a product as brand and name, a place by its name, a post by its subject. Not the app or the kind of screen")
    var title: String

    @Guide(description: "3 to 6 short lowercase search words: brands, products, places, dishes, names", .count(3...6))
    var tags: [String]
}

@Generable
struct CollectionNameResponse {
    @Guide(description: "A friendly collection name of 1 to 3 words in Title Case")
    var name: String

    @Guide(description: "The best matching SF Symbol name from the allowed list")
    var symbol: String
}
