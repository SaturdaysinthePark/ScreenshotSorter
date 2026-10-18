import Foundation
import Photos
import UIKit

enum ConfidenceLevel: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    init(score: Double) {
        if score >= 0.7 {
            self = .high
        } else if score >= 0.4 {
            self = .medium
        } else {
            self = .low
        }
    }
}

struct CategoryWithConfidence: Hashable {
    let category: ScreenshotCategory
    let confidence: ConfidenceLevel
    let score: Double
}

enum ScreenshotStatus {
    case unprocessed
    case processing
    case processed
    case reviewed
}

struct Screenshot: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let categories: [ScreenshotCategory] // For backward compatibility
    let categoriesWithConfidence: [CategoryWithConfidence]
    let creationDate: Date
    var thumbnail: UIImage?
    var isReviewed: Bool = false
    var markedForDeletion: Bool = false
    var lastReviewedDate: Date?
    var processingStatus: ScreenshotStatus = .unprocessed

    // Rich analysis (populated by the analysis pipeline)
    var app: String?
    var tags: [String] = []
    var title: String?
    var summary: String?
    var tier: AnalysisTier = .none

    init(asset: PHAsset, categories: [ScreenshotCategory]) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.categories = categories
        self.categoriesWithConfidence = categories.map {
            CategoryWithConfidence(category: $0, confidence: .medium, score: 0.5)
        }
        self.creationDate = asset.creationDate ?? Date()
    }

    init(asset: PHAsset, categoriesWithConfidence: [CategoryWithConfidence]) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.categoriesWithConfidence = categoriesWithConfidence
        self.categories = categoriesWithConfidence.map { $0.category }
        self.creationDate = asset.creationDate ?? Date()
    }

    /// Build from a PHAsset plus (optional) persisted analysis summary
    init(asset: PHAsset, summary: RecordSummary?) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate ?? summary?.creationDate ?? Date()
        if let summary, summary.tier != .none {
            let scored = summary.categories.map {
                CategoryWithConfidence(category: $0.category, confidence: ConfidenceLevel(score: $0.score), score: $0.score)
            }
            self.categoriesWithConfidence = scored
            self.categories = scored.map { $0.category }
            self.processingStatus = .processed
        } else {
            self.categoriesWithConfidence = []
            self.categories = []
            self.processingStatus = .unprocessed
        }
        self.app = summary?.app
        self.tags = summary?.tags ?? []
        self.title = summary?.title
        self.tier = summary?.tier ?? .none
        self.isReviewed = summary?.isReviewed ?? false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Screenshot, rhs: Screenshot) -> Bool {
        lhs.id == rhs.id
    }
}

enum ScreenshotCategory: String, CaseIterable, Hashable {
    case all = "All Screenshots"

    // Core categories
    case events = "Events"
    case codes = "QR Codes"
    case receipts = "Receipts"
    case directions = "Directions"
    case places = "Places"
    case clothes = "Clothes"
    case people = "People"
    case shoes = "Shoes"

    // Messaging apps
    case imessage = "iMessage"
    case whatsapp = "WhatsApp"
    case signal = "Signal"
    case telegram = "Telegram"
    case discord = "Discord"
    case slack = "Slack"

    // Email
    case email = "Email"
    case gmail = "Gmail"

    // Social media
    case instagram = "Instagram"
    case tiktok = "TikTok"
    case twitter = "Twitter/X"
    case facebook = "Facebook"
    case linkedin = "LinkedIn"
    case reddit = "Reddit"
    case youtube = "YouTube"

    // Food & Drinks
    case food = "Food"
    case drinks = "Drinks"
    case cooking = "Cooking"
    case recipes = "Recipes"

    // Shopping
    case stores = "Stores"
    case storefronts = "Storefronts"

    // Products
    case watches = "Watches"
    case furniture = "Furniture"
    case bags = "Bags"
    case jewelry = "Jewelry"
    case vehicles = "Vehicles"
    case electronics = "Electronics"

    // Lifestyle
    case homes = "Homes"
    case sitesOfInterest = "Sites of Interest"
    case animals = "Animals"
    case quotes = "Quotes"

    // Nature & Outdoors
    case nature = "Nature"
    case landscapes = "Landscapes"
    case beaches = "Beaches"
    case mountains = "Mountains"
    case flowers = "Flowers"
    case plants = "Plants"
    case sunset = "Sunset"

    // Media
    case books = "Books"
    case movies = "Movies & TV"
    case music = "Music"
    case videoGames = "Video Games"

    // Travel & Activities
    case flights = "Flights & Travel"
    case memes = "Memes"
    case sports = "Sports"
    case exercise = "Exercise"
    case art = "Art"
    case reading = "Reading"

    // Utility
    case documents = "Documents"
    case health = "Health & Fitness"
    case notes = "Notes"
    case weather = "Weather"
    case news = "News & Articles"
    case notifications = "Notifications"
    case iosHomeScreens = "iOS Home Screens"
    case settings = "Settings"
    case errors = "Errors & Bugs"

    // Added in the 2026 ML pass
    case finance = "Money & Finance"
    case tickets = "Tickets & Passes"
    case orders = "Orders & Shipping"
    case programming = "Programming"
    case aiChats = "AI Chats"

    case other = "Other"

    var icon: String {
        switch self {
        case .all: return "photo.stack.fill"
        case .events: return "calendar"
        case .codes: return "qrcode"
        case .receipts: return "receipt.fill"
        case .directions: return "arrow.triangle.turn.up.right.diamond.fill"
        case .places: return "map.fill"
        case .clothes: return "tshirt.fill"
        case .people: return "person.fill"
        case .shoes: return "shoe.fill"

        // Messaging apps
        case .imessage: return "message.fill"
        case .whatsapp: return "message.circle.fill"
        case .signal: return "lock.fill"
        case .telegram: return "paperplane.fill"
        case .discord: return "bubble.left.and.bubble.right.fill"
        case .slack: return "number"

        // Email
        case .email: return "envelope.fill"
        case .gmail: return "envelope.badge.fill"

        // Social media
        case .instagram: return "camera.fill"
        case .tiktok: return "music.note"
        case .twitter: return "bird.fill"
        case .facebook: return "f.square.fill"
        case .linkedin: return "briefcase.fill"
        case .reddit: return "arrow.up.circle.fill"
        case .youtube: return "play.rectangle.fill"

        // Food & Drinks
        case .food: return "fork.knife"
        case .drinks: return "cup.and.saucer.fill"
        case .cooking: return "flame.fill"
        case .recipes: return "book.pages.fill"

        // Shopping
        case .stores: return "cart.fill"
        case .storefronts: return "storefront.fill"

        // Products
        case .watches: return "watchface.applewatch.case"
        case .furniture: return "lamp.table.fill"
        case .bags: return "bag.fill"
        case .jewelry: return "sparkles"
        case .vehicles: return "car.fill"
        case .electronics: return "laptopcomputer"

        // Lifestyle
        case .homes: return "house.fill"
        case .sitesOfInterest: return "building.columns.fill"
        case .animals: return "pawprint.fill"
        case .quotes: return "quote.bubble.fill"

        // Nature & Outdoors
        case .nature: return "leaf.fill"
        case .landscapes: return "photo.fill.on.rectangle.fill"
        case .beaches: return "water.waves"
        case .mountains: return "mountain.2.fill"
        case .flowers: return "camera.macro"
        case .plants: return "leaf.arrow.circlepath"
        case .sunset: return "sun.horizon.fill"

        // Media
        case .books: return "book.fill"
        case .movies: return "film.fill"
        case .music: return "music.note.list"
        case .videoGames: return "gamecontroller.fill"

        // Travel & Activities
        case .flights: return "airplane"
        case .memes: return "face.smiling.fill"
        case .sports: return "sportscourt.fill"
        case .exercise: return "figure.run"
        case .art: return "paintpalette.fill"
        case .reading: return "text.book.closed.fill"

        // Utility
        case .documents: return "doc.text.fill"
        case .health: return "heart.fill"
        case .notes: return "note.text"
        case .weather: return "cloud.sun.fill"
        case .news: return "newspaper.fill"
        case .notifications: return "bell.fill"
        case .iosHomeScreens: return "apps.iphone"
        case .settings: return "gearshape.fill"
        case .errors: return "exclamationmark.triangle.fill"
        case .finance: return "creditcard.fill"
        case .tickets: return "ticket.fill"
        case .orders: return "shippingbox.fill"
        case .programming: return "chevron.left.forwardslash.chevron.right"
        case .aiChats: return "sparkles"

        case .other: return "square.grid.2x2.fill"
        }
    }

    var group: CategoryGroup {
        CategoryGroup.group(for: self)
    }

    /// Display name (alias of rawValue, which may change between releases)
    var displayName: String { rawValue }

    /// Stable persistence key (the case name). Never persist `rawValue`.
    var key: String { String(describing: self) }

    private static let byKey: [String: ScreenshotCategory] = Dictionary(
        uniqueKeysWithValues: ScreenshotCategory.allCases.map { ($0.key, $0) }
    )

    /// Legacy display names that have since been renamed
    private static let legacyNames: [String: ScreenshotCategory] = [
        "Code & QR": .codes
    ]

    init?(key: String) {
        guard let category = ScreenshotCategory.byKey[key] else { return nil }
        self = category
    }

    /// Decode a value written by any app version (key, current display name, or legacy display name)
    init?(persisted value: String) {
        if let category = ScreenshotCategory(key: value) ?? ScreenshotCategory(rawValue: value) ?? ScreenshotCategory.legacyNames[value] {
            self = category
        } else {
            return nil
        }
    }

    /// Categories the classifier can assign (excludes the synthetic `.all`)
    static var assignable: [ScreenshotCategory] {
        allCases.filter { $0 != .all }
    }
}

// MARK: - Codable (stable keys, tolerant decoding)

extension ScreenshotCategory: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = ScreenshotCategory(persisted: value) ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

enum CategoryGroup: String, CaseIterable {
    case socialMedia = "Social Media"
    case communication = "Communication"
    case clothingAccessories = "Clothing & Accessories"
    case productsTech = "Products & Tech"
    case homeLiving = "Home & Living"
    case foodDrink = "Food & Drink"
    case placesTravel = "Places & Travel"
    case eventsPlanning = "Events & Planning"
    case workProductivity = "Work & Productivity"
    case mediaEntertainment = "Media & Entertainment"
    case lifestyleWellness = "Lifestyle & Wellness"
    case information = "Information"
    case system = "System"
    case other = "Other"

    var icon: String {
        switch self {
        case .socialMedia: return "person.3.fill"
        case .communication: return "bubble.left.and.bubble.right.fill"
        case .clothingAccessories: return "tshirt.fill"
        case .productsTech: return "laptopcomputer"
        case .homeLiving: return "house.fill"
        case .foodDrink: return "fork.knife"
        case .placesTravel: return "map.fill"
        case .eventsPlanning: return "calendar"
        case .workProductivity: return "doc.text.fill"
        case .mediaEntertainment: return "film.fill"
        case .lifestyleWellness: return "heart.fill"
        case .information: return "newspaper.fill"
        case .system: return "apps.iphone"
        case .other: return "square.grid.2x2.fill"
        }
    }

    static func group(for category: ScreenshotCategory) -> CategoryGroup {
        switch category {
        // Social Media
        case .instagram, .tiktok, .twitter, .facebook, .linkedin, .reddit, .youtube:
            return .socialMedia

        // Communication
        case .imessage, .whatsapp, .signal, .telegram, .discord, .slack, .email, .gmail, .aiChats:
            return .communication

        // Clothing & Accessories
        case .clothes, .shoes, .watches, .bags, .jewelry:
            return .clothingAccessories

        // Products & Tech
        case .vehicles, .electronics, .stores, .orders:
            return .productsTech

        // Home & Living
        case .furniture, .homes:
            return .homeLiving

        // Food & Drink
        case .food, .drinks, .cooking, .recipes:
            return .foodDrink

        // Places & Travel
        case .places, .storefronts, .sitesOfInterest, .directions, .flights,
             .nature, .landscapes, .beaches, .mountains, .sunset:
            return .placesTravel

        // Events & Planning
        case .events, .codes, .tickets:
            return .eventsPlanning

        // Work & Productivity
        case .documents, .notes, .receipts, .finance, .programming:
            return .workProductivity

        // Media & Entertainment
        case .books, .movies, .music, .memes, .videoGames:
            return .mediaEntertainment

        // Lifestyle & Wellness
        case .health, .sports, .weather, .people, .animals,
             .flowers, .plants, .exercise, .art, .reading:
            return .lifestyleWellness

        // Information
        case .news, .quotes:
            return .information

        // System
        case .notifications, .iosHomeScreens, .settings, .errors:
            return .system

        // Other
        case .all, .other:
            return .other
        }
    }
}
