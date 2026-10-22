import Foundation

/// Maps Vision image-classifier identifiers onto categories.
///
/// Identifiers are split on "_" / spaces and matched token-by-token against exact word
/// lists ("golden_retriever" → ["golden", "retriever"]). This replaces the old substring
/// checks where "catamaran" counted as a cat and "german_shepherd" as a person.
enum VisionLabelMap {
    /// Classifier observations below this confidence are ignored entirely
    static let minimumConfidence = 0.12
    /// Unmapped labels at or above this confidence become free-form tags
    static let tagConfidence = 0.5

    private static let table: [(ScreenshotCategory, Double, [String])] = [
        (.animals, 1.0, ["animal", "mammal", "canine", "dog", "puppy", "cat", "feline", "kitten", "bird", "pet",
                         "horse", "retriever", "terrier", "spaniel", "poodle", "bulldog", "hound", "shepherd",
                         "labrador", "husky", "corgi", "wildlife", "reptile", "fish", "rabbit", "hamster",
                         "cow", "sheep", "goat", "pig", "bear", "lion", "tiger", "elephant", "giraffe", "monkey",
                         "insect", "butterfly", "owl", "parrot", "duck", "chicken", "deer", "fox", "wolf",
                         "squirrel", "turtle", "snake", "lizard", "penguin", "dolphin", "whale", "shark"]),
        (.people, 0.95, ["people", "person", "adult", "child", "children", "baby", "crowd", "portrait", "selfie",
                         "face", "teen", "woman", "man", "girl", "boy", "bride", "groom", "toddler", "group"]),
        (.food, 1.0, ["food", "meal", "dish", "cuisine", "pizza", "burger", "hamburger", "sandwich", "salad",
                      "pasta", "spaghetti", "noodle", "noodles", "sushi", "sashimi", "dessert", "cake", "cupcake",
                      "cookie", "bread", "pastry", "donut", "fruit", "vegetable", "steak", "meat", "seafood",
                      "taco", "burrito", "soup", "curry", "rice", "egg", "breakfast", "pancake", "waffle",
                      "chocolate", "icecream", "ice", "cheese", "fries", "dumpling", "ramen", "barbecue", "baked"]),
        (.drinks, 0.95, ["drink", "beverage", "coffee", "espresso", "latte", "cappuccino", "tea", "cocktail",
                         "beer", "wine", "juice", "smoothie", "soda", "liquor", "whiskey", "martini", "milkshake"]),
        (.food, 0.85, ["cooking", "kitchen", "chef", "baking", "oven", "stove", "cookware", "frying"]),
        (.clothes, 0.9, ["clothing", "apparel", "garment", "shirt", "tshirt", "dress", "jacket", "coat", "jeans",
                         "denim", "pants", "trousers", "skirt", "sweater", "hoodie", "suit", "blouse", "shorts",
                         "swimsuit", "lingerie", "outfit", "fashion", "hat", "cap", "scarf"]),
        (.shoes, 0.95, ["shoe", "shoes", "footwear", "sneaker", "sneakers", "boot", "boots", "sandal", "sandals",
                        "heel", "heels", "loafer", "slipper"]),
        (.watches, 0.95, ["watch", "wristwatch", "timepiece", "smartwatch"]),
        (.bags, 0.9, ["bag", "handbag", "purse", "backpack", "luggage", "suitcase", "tote", "briefcase"]),
        (.jewelry, 0.95, ["jewelry", "jewellery", "necklace", "ring", "earring", "earrings", "bracelet", "pendant",
                          "diamond", "gemstone"]),
        (.furniture, 0.9, ["furniture", "chair", "sofa", "couch", "table", "desk", "bed", "lamp", "shelf",
                           "bookcase", "cabinet", "dresser", "armchair", "stool", "bench"]),
        (.homes, 0.8, ["house", "home", "interior", "room", "bedroom", "bathroom", "livingroom", "apartment",
                       "residential", "villa", "cottage", "mansion", "patio", "porch", "balcony", "roof", "chimney"]),
        (.vehicles, 0.95, ["vehicle", "car", "automobile", "truck", "motorcycle", "bicycle", "bike", "suv", "sedan",
                           "van", "bus", "convertible", "jeep", "scooter", "boat", "yacht", "airplane", "aircraft"]),
        (.electronics, 0.85, ["computer", "laptop", "smartphone", "phone", "tablet", "monitor", "keyboard",
                              "headphones", "earbuds", "speaker", "camera", "television", "console", "gadget", "gamepad",
                              "electronics", "drone"]),
        (.nature, 0.75, ["nature", "forest", "tree", "trees", "woods", "grass", "field", "meadow", "jungle",
                         "waterfall", "river", "lake", "wilderness", "park", "foliage"]),
        (.nature, 0.9, ["landscape", "scenery", "vista", "valley", "canyon", "cliff", "desert", "horizon",
                            "hill", "countryside", "panorama"]),
        (.nature, 0.95, ["beach", "shore", "coast", "ocean", "sea", "seashore", "sand", "tropical", "island",
                          "surf", "wave", "waves", "lagoon"]),
        (.nature, 0.95, ["mountain", "mountains", "peak", "summit", "alpine", "volcano", "glacier", "ridge"]),
        (.nature, 0.95, ["flower", "flowers", "rose", "tulip", "daisy", "orchid", "sunflower", "lily", "bouquet",
                          "blossom", "petal", "bloom", "lavender"]),
        (.plants, 0.85, ["plant", "plants", "houseplant", "succulent", "cactus", "fern", "leaf", "leaves",
                         "garden", "potted", "vegetation", "moss"]),
        (.nature, 0.95, ["sunset", "sunrise", "dusk", "dawn", "twilight"]),
        (.places, 0.85, ["landmark", "monument", "museum", "temple", "church", "cathedral", "castle",
                                  "palace", "tower", "bridge", "ruins", "statue", "mosque", "skyline"]),
        (.places, 0.8, ["storefront", "shop", "store", "boutique", "cafe", "restaurant", "bakery", "market",
                             "mall", "signage"]),
        (.art, 0.85, ["art", "painting", "drawing", "sketch", "illustration", "sculpture", "mural", "graffiti",
                      "artwork", "canvas", "watercolor"]),
        (.books, 0.7, ["book", "books", "bookshelf", "novel", "magazine", "library"]),
        // Not "document": Vision says it about nearly every screenshot (0.8–0.9 on chats, maps, feeds)
        (.documents, 0.55, ["page", "paper", "letter", "form", "receipt", "invoice"]),
        (.receipts, 0.7, ["receipt", "invoice"]),
        (.codes, 0.8, ["qrcode", "barcode"]),
        (.sports, 0.85, ["sport", "sports", "soccer", "football", "basketball", "baseball", "tennis", "golf",
                         "hockey", "stadium", "athlete", "ball"]),
        (.health, 0.8, ["gym", "exercise", "workout", "fitness", "yoga", "running", "dumbbell", "weightlifting"]),
        (.music, 0.6, ["guitar", "piano", "concert", "drum", "drums", "violin", "microphone", "musician"]),
        (.videoGames, 0.6, ["videogame", "gaming", "joystick", "controller", "gamepad"]),
        (.weather, 0.5, ["rain", "snow", "storm", "lightning", "rainbow", "fog"]),
        (.events, 0.5, ["wedding", "party", "festival", "celebration", "fireworks", "parade"])
    ]

    /// token → [(category, weight)]
    private static let tokenIndex: [String: [(ScreenshotCategory, Double)]] = {
        var index: [String: [(ScreenshotCategory, Double)]] = [:]
        for (category, weight, tokens) in table {
            for token in tokens {
                index[token, default: []].append((category, weight))
            }
        }
        return index
    }()

    /// Labels too generic to be useful as tags
    static let genericLabels: Set<String> = [
        "structure", "material", "textile", "outdoor", "indoor", "people", "adult", "sky", "wood", "plant",
        "document", "text", "screenshot", "graphic", "art", "machine", "liquid", "water", "cloud", "clouds",
        "land", "conveyance", "consumer electronics", "electronics", "display", "screen", "light",
        // Seen behind or around almost anything on a real library; they describe the frame, not the subject
        "wood processed", "sign", "portal", "printed page", "illustrations", "window", "container", "decoration",
        "raw glass", "brick", "fence", "blue sky", "cloudy", "interior room", "utensil", "tableware", "table",
        "optical equipment", "headgear", "crowd", "building", "foliage", "decorative plant", "vehicle", "automobile",
        // Duplicates of a clearer label ("watch", "shoes")
        "timepiece", "dial", "footwear"
    ]

    static func tokens(of identifier: String) -> [String] {
        identifier
            .lowercased()
            .split(whereSeparator: { $0 == "_" || $0 == " " || $0 == "-" || $0 == "," })
            .map(String.init)
    }

    /// In "adult_cat" or "computer_monitor" the last word is the subject; earlier words only modify it.
    static let modifierWeight = 0.5

    /// Scene categories that show up behind almost any outdoor subject (grass behind a dog, trees behind a house)
    static let backgroundCategories: Set<ScreenshotCategory> = [.nature, .plants]
    static let foregroundCategories: Set<ScreenshotCategory> = [
        .animals, .people, .vehicles, .homes, .food, .drinks, .places, .furniture,
        .electronics, .clothes, .shoes, .bags, .watches, .jewelry, .sports
    ]
    /// A foreground subject at least this likely scales background scene categories by `backgroundScale`
    static let foregroundThreshold = 0.55
    static let backgroundScale = 0.6

    /// Specific categories that a generic one should not outrank once the specific label appears at all
    /// (Vision reports "plant" at 0.9 and "flower" at 0.3 for a rose).
    static let specificOverGeneric: [(specific: ScreenshotCategory, generic: ScreenshotCategory)] = []
    static let specificMinimum = 0.25

    /// Per-category score: max over labels of confidence × mapping weight, then scene/subject adjustments.
    static func categoryScores(for labels: [VisionLabel]) -> [ScreenshotCategory: Double] {
        var scores: [ScreenshotCategory: Double] = [:]
        for label in labels where label.confidence >= minimumConfidence {
            var best: [ScreenshotCategory: Double] = [:]
            let parts = tokens(of: label.identifier)
            for (offset, token) in parts.enumerated() {
                guard let targets = tokenIndex[token] else { continue }
                let role = offset == parts.count - 1 ? 1.0 : modifierWeight
                for (category, weight) in targets {
                    best[category] = max(best[category] ?? 0, label.confidence * weight * role)
                }
            }
            for (category, value) in best where value > scores[category, default: 0] {
                scores[category] = value
            }
        }

        for (specific, generic) in specificOverGeneric {
            if let specificScore = scores[specific], specificScore >= specificMinimum, let genericScore = scores[generic] {
                scores[specific] = max(specificScore, genericScore * 0.9)
            }
        }
        let hasSubject = foregroundCategories.contains { (scores[$0] ?? 0) >= foregroundThreshold }
        if hasSubject {
            for category in backgroundCategories {
                if let score = scores[category] { scores[category] = score * backgroundScale }
            }
        }
        return scores
    }

    /// Human-readable tags from confident, specific labels ("golden_retriever" → "golden retriever").
    /// `scale` < 1 on text-heavy screens, where pictures are thumbnails inside a feed or article
    static func tags(for labels: [VisionLabel], scale: Double = 1, limit: Int = 4) -> [(String, Double)] {
        labels
            .filter { $0.confidence * scale >= tagConfidence }
            .map { (tokens(of: $0.identifier).joined(separator: " "), $0.confidence) }
            .filter { !$0.0.isEmpty && !genericLabels.contains($0.0) }
            .prefix(limit)
            .map { $0 }
    }
}
