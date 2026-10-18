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
    static let tagConfidence = 0.3

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
        (.cooking, 0.85, ["cooking", "kitchen", "chef", "baking", "oven", "stove", "cookware", "utensil", "frying"]),
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
                       "residential", "villa", "cottage", "mansion", "patio", "porch", "balcony"]),
        (.vehicles, 0.95, ["vehicle", "car", "automobile", "truck", "motorcycle", "bicycle", "bike", "suv", "sedan",
                           "van", "bus", "convertible", "jeep", "scooter", "boat", "yacht", "airplane", "aircraft"]),
        (.electronics, 0.85, ["computer", "laptop", "smartphone", "phone", "tablet", "monitor", "keyboard",
                              "headphones", "earbuds", "speaker", "camera", "television", "console", "gadget",
                              "electronics", "drone"]),
        (.nature, 0.75, ["nature", "forest", "tree", "trees", "woods", "grass", "field", "meadow", "jungle",
                         "waterfall", "river", "lake", "wilderness", "park", "foliage"]),
        (.landscapes, 0.9, ["landscape", "scenery", "vista", "valley", "canyon", "cliff", "desert", "horizon",
                            "hill", "countryside", "panorama"]),
        (.beaches, 0.95, ["beach", "shore", "coast", "ocean", "sea", "seashore", "sand", "tropical", "island",
                          "surf", "wave", "waves", "lagoon"]),
        (.mountains, 0.95, ["mountain", "mountains", "peak", "summit", "alpine", "volcano", "glacier", "ridge"]),
        (.flowers, 0.95, ["flower", "flowers", "rose", "tulip", "daisy", "orchid", "sunflower", "lily", "bouquet",
                          "blossom", "petal", "bloom", "lavender"]),
        (.plants, 0.85, ["plant", "plants", "houseplant", "succulent", "cactus", "fern", "leaf", "leaves",
                         "garden", "potted", "vegetation", "moss"]),
        (.sunset, 0.95, ["sunset", "sunrise", "dusk", "dawn", "twilight"]),
        (.sitesOfInterest, 0.85, ["landmark", "monument", "museum", "temple", "church", "cathedral", "castle",
                                  "palace", "tower", "bridge", "ruins", "statue", "mosque", "skyline"]),
        (.storefronts, 0.8, ["storefront", "shop", "store", "boutique", "cafe", "restaurant", "bakery", "market",
                             "mall", "signage"]),
        (.art, 0.85, ["art", "painting", "drawing", "sketch", "illustration", "sculpture", "mural", "graffiti",
                      "artwork", "canvas", "watercolor"]),
        (.books, 0.7, ["book", "books", "bookshelf", "novel", "magazine", "library"]),
        (.documents, 0.55, ["document", "paper", "letter", "form", "receipt", "invoice"]),
        (.receipts, 0.7, ["receipt", "invoice"]),
        (.codes, 0.8, ["qrcode", "barcode"]),
        (.sports, 0.85, ["sport", "sports", "soccer", "football", "basketball", "baseball", "tennis", "golf",
                         "hockey", "stadium", "athlete", "ball"]),
        (.exercise, 0.8, ["gym", "exercise", "workout", "fitness", "yoga", "running", "dumbbell", "weightlifting"]),
        (.music, 0.6, ["guitar", "piano", "concert", "drum", "drums", "violin", "microphone", "musician"]),
        (.videoGames, 0.6, ["videogame", "gaming", "joystick", "controller"]),
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
        "land", "conveyance", "consumer electronics", "electronics", "display", "screen", "light"
    ]

    static func tokens(of identifier: String) -> [String] {
        identifier
            .lowercased()
            .split(whereSeparator: { $0 == "_" || $0 == " " || $0 == "-" || $0 == "," })
            .map(String.init)
    }

    /// Per-category score: max over labels of confidence × mapping weight.
    static func categoryScores(for labels: [VisionLabel]) -> [ScreenshotCategory: Double] {
        var scores: [ScreenshotCategory: Double] = [:]
        for label in labels where label.confidence >= minimumConfidence {
            var seen = Set<ScreenshotCategory>()
            for token in tokens(of: label.identifier) {
                guard let targets = tokenIndex[token] else { continue }
                for (category, weight) in targets where !seen.contains(category) {
                    seen.insert(category)
                    let value = label.confidence * weight
                    if value > scores[category, default: 0] {
                        scores[category] = value
                    }
                }
            }
        }
        return scores
    }

    /// Human-readable tags from confident, specific labels ("golden_retriever" → "golden retriever").
    static func tags(for labels: [VisionLabel], limit: Int = 5) -> [(String, Double)] {
        labels
            .filter { $0.confidence >= tagConfidence }
            .map { (tokens(of: $0.identifier).joined(separator: " "), $0.confidence) }
            .filter { !$0.0.isEmpty && !genericLabels.contains($0.0) }
            .prefix(limit)
            .map { $0 }
    }
}
