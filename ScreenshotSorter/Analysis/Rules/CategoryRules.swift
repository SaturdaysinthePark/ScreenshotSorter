import Foundation

/// Keyword/pattern knowledge for text-driven categories.
///
/// Guidelines for editing:
/// - `strong` terms are specific enough to identify the category on their own (≈0.6–0.9).
/// - `weak` terms only count in combination (≈0.15–0.35).
/// - Terms are matched on whole words after case/diacritic folding; plurals match via stemming.
/// - Visual categories (animals, beaches…) are mostly handled by `VisionLabelMap`; the text
///   rules here only add supporting evidence (e.g. product listings).
/// Split per group so the type-checker stays fast.
enum CategoryRules {

    static var all: [CategoryRule] {
        planning + work + money + shopping + media + travel + lifestyle + information + system + visualText + communication
    }

    // MARK: Events & Planning

    static let planning: [CategoryRule] = [
        CategoryRule(
            category: .events,
            strong: ["rsvp": 0.85, "save the date": 0.9, "add to calendar": 0.8, "you're invited": 0.85,
                     "you are invited": 0.85, "event details": 0.75, "doors open": 0.8, "lineup": 0.55,
                     "going": 0.25, "interested": 0.2, "eventbrite": 0.85, "partiful": 0.9, "luma": 0.5],
            weak: ["concert": 0.3, "festival": 0.3, "party": 0.25, "wedding": 0.3, "birthday": 0.25,
                   "venue": 0.3, "tickets": 0.2, "invite": 0.25, "celebration": 0.2, "meetup": 0.3,
                   "conference": 0.3, "webinar": 0.3, "pm": 0.1, "date": 0.1],
            patterns: [.allOf(["when", "where"], weight: 0.45)],
            minWeakHits: 2
        ),
        CategoryRule(
            category: .codes,
            strong: ["scan this code": 0.85, "scan the qr": 0.85, "qr code": 0.8, "scan to pay": 0.85,
                     "scan me": 0.7, "barcode": 0.6],
            weak: ["scan": 0.3, "qr": 0.35]
        ),
        CategoryRule(
            category: .tickets,
            strong: ["boarding pass": 0.92, "admit one": 0.9, "e-ticket": 0.85, "eticket": 0.85,
                     "mobile ticket": 0.85, "general admission": 0.8, "section row seat": 0.85,
                     "your tickets": 0.75, "ticketmaster": 0.85, "add to apple wallet": 0.85,
                     "add to wallet": 0.7, "zone": 0.15, "seat": 0.3],
            weak: ["gate": 0.3, "row": 0.25, "section": 0.2, "entry": 0.2, "admission": 0.3,
                   "ticket": 0.35, "boarding": 0.35, "group": 0.1],
            patterns: [.allOf(["row", "seat"], weight: 0.65), .allOf(["gate", "seat"], weight: 0.6)]
        )
    ]

    // MARK: Work & Productivity

    static let work: [CategoryRule] = [
        CategoryRule(
            category: .receipts,
            strong: ["receipt": 0.8, "subtotal": 0.8, "order total": 0.8, "amount paid": 0.8,
                     "payment received": 0.75, "invoice": 0.75, "transaction id": 0.7, "tip": 0.2,
                     "thank you for your purchase": 0.85, "thank you for your order": 0.7,
                     "sales tax": 0.75, "change due": 0.85, "cash": 0.2],
            weak: ["total": 0.3, "tax": 0.3, "paid": 0.25, "visa": 0.2, "mastercard": 0.2,
                   "amex": 0.2, "qty": 0.3, "item": 0.15, "balance": 0.15],
            patterns: [.priceCount(min: 4, weight: 0.5), .allOf(["subtotal", "total"], weight: 0.6)],
            negative: ["add to cart", "add to bag", "buy now"]
        ),
        CategoryRule(
            category: .documents,
            strong: ["page 1 of": 0.8, "terms and conditions": 0.7, "agreement": 0.5, "pdf": 0.5,
                     "signature": 0.45, "section 1": 0.5, "table of contents": 0.8, "abstract": 0.4,
                     "hereby": 0.6, "pursuant": 0.7, "docusign": 0.85, "lease": 0.45, "contract": 0.45],
            weak: ["document": 0.3, "page": 0.15, "appendix": 0.3, "references": 0.25,
                   "policy": 0.2, "form": 0.15, "date": 0.05, "name": 0.05],
            patterns: [.textDensity(min: 0.35, weight: 0.35), .lineCount(min: 30, weight: 0.25)],
            negative: ["likes", "retweets", "reply", "comments"]
        ),
        CategoryRule(
            category: .notes,
            strong: ["to do": 0.5, "todo": 0.55, "checklist": 0.6, "shopping list": 0.8, "grocery list": 0.85,
                     "reminders": 0.55, "new note": 0.8, "notes": 0.35],
            weak: ["list": 0.2, "remember": 0.25, "buy": 0.15, "ideas": 0.25, "done": 0.15]
        ),
        CategoryRule(
            category: .programming,
            strong: ["func": 0.6, "def": 0.35, "return": 0.25, "import": 0.3, "console.log": 0.85,
                     "public static void": 0.9, "stack trace": 0.7, "pull request": 0.8, "commit": 0.4,
                     "github": 0.6, "stackoverflow": 0.8, "stack overflow": 0.8, "npm install": 0.9,
                     "pip install": 0.9, "localhost": 0.8, "terminal": 0.4, "xcode": 0.7, "vscode": 0.7,
                     "swiftui": 0.8, "javascript": 0.6, "python": 0.5, "typescript": 0.7,
                     "const": 0.35, "let": 0.1, "var": 0.15, "null": 0.3, "undefined": 0.4],
            weak: ["function": 0.2, "class": 0.15, "error": 0.1, "build": 0.15, "debug": 0.25,
                   "api": 0.2, "json": 0.3, "repository": 0.3, "branch": 0.15, "merge": 0.2],
            patterns: [.countOf(["func", "return", "import", "let", "var", "const", "class", "def", "self", "true", "false", "nil", "null"], min: 4, weight: 0.75)],
            minWeakHits: 3
        )
    ]

    // MARK: Money

    static let money: [CategoryRule] = [
        CategoryRule(
            category: .finance,
            strong: ["available balance": 0.85, "account balance": 0.8, "routing number": 0.85,
                     "account number": 0.6, "direct deposit": 0.8, "venmo": 0.75, "zelle": 0.8,
                     "cash app": 0.8, "paypal": 0.6, "portfolio": 0.55, "dividend": 0.75, "stocks": 0.3,
                     "crypto": 0.45, "bitcoin": 0.7, "robinhood": 0.85, "credit score": 0.85,
                     "statement balance": 0.85, "minimum payment": 0.85, "apr": 0.5, "transfer": 0.3,
                     "you sent": 0.6, "you received": 0.55, "split the bill": 0.7, "budget": 0.4],
            weak: ["balance": 0.25, "deposit": 0.3, "withdrawal": 0.35, "savings": 0.3, "checking": 0.25,
                   "pending": 0.15, "transactions": 0.3, "bank": 0.3, "card": 0.1],
            patterns: [.priceCount(min: 3, weight: 0.2)],
            negative: ["in stock", "add to cart"]
        )
    ]

    // MARK: Shopping

    static let shopping: [CategoryRule] = [
        CategoryRule(
            category: .stores,
            strong: ["add to cart": 0.85, "add to bag": 0.85, "buy now": 0.85, "in stock": 0.7,
                     "free shipping": 0.65, "free returns": 0.65, "add to basket": 0.85, "wishlist": 0.6,
                     "customer reviews": 0.6, "select size": 0.75, "amazon": 0.45, "etsy": 0.6, "shein": 0.7,
                     "temu": 0.7, "checkout": 0.55, "limited time deal": 0.8],
            weak: ["sale": 0.25, "price": 0.2, "shipping": 0.2, "ratings": 0.2, "shop": 0.2,
                   "deal": 0.2, "discount": 0.3, "off": 0.05, "size": 0.15, "color": 0.1],
            patterns: [.priceCount(min: 1, weight: 0.15)]
        ),
        CategoryRule(
            category: .orders,
            strong: ["order confirmed": 0.85, "order number": 0.7, "tracking number": 0.85,
                     "out for delivery": 0.9, "has shipped": 0.85, "your order": 0.6, "estimated delivery": 0.85,
                     "arriving": 0.5, "delivered": 0.45, "track package": 0.9, "shipment": 0.6, "ups": 0.4,
                     "fedex": 0.6, "usps": 0.6, "dhl": 0.6],
            weak: ["order": 0.25, "shipping": 0.25, "package": 0.3, "delivery": 0.25, "carrier": 0.3]
        ),
        CategoryRule(
            category: .storefronts,
            strong: ["open now": 0.5, "closes at": 0.55, "opens at": 0.55, "store hours": 0.7, "storefront": 0.7],
            weak: ["hours": 0.2, "store": 0.2, "visit us": 0.3]
        )
    ]

    // MARK: Media & Entertainment

    static let media: [CategoryRule] = [
        CategoryRule(
            category: .books,
            strong: ["isbn": 0.9, "paperback": 0.8, "hardcover": 0.8, "kindle edition": 0.85, "goodreads": 0.85,
                     "audiobook": 0.75, "new york times bestseller": 0.85, "chapter": 0.4, "author": 0.35],
            weak: ["book": 0.3, "novel": 0.35, "read": 0.1, "pages": 0.15, "series": 0.15]
        ),
        CategoryRule(
            category: .reading,
            strong: ["kindle": 0.6, "apple books": 0.75, "min left in chapter": 0.9,
                     "chapter": 0.35, "location": 0.05],
            weak: ["highlight": 0.3, "page": 0.15]
        ),
        CategoryRule(
            category: .movies,
            strong: ["netflix": 0.8, "imdb": 0.85, "rotten tomatoes": 0.85, "letterboxd": 0.9, "hbo max": 0.8,
                     "disney plus": 0.8, "prime video": 0.8, "hulu": 0.8, "trailer": 0.5, "season 1": 0.6,
                     "episode": 0.45, "watchlist": 0.6, "now streaming": 0.75, "in theaters": 0.75, "showtimes": 0.8],
            weak: ["movie": 0.35, "film": 0.3, "series": 0.15, "cast": 0.2, "director": 0.3, "watch": 0.1]
        ),
        CategoryRule(
            category: .music,
            strong: ["spotify": 0.8, "apple music": 0.8, "now playing": 0.7, "liked songs": 0.85, "playlist": 0.6,
                     "album": 0.5, "lyrics": 0.6, "shazam": 0.85, "soundcloud": 0.85, "tidal": 0.5,
                     "monthly listeners": 0.9, "add to library": 0.4],
            weak: ["song": 0.3, "artist": 0.2, "track": 0.2, "listen": 0.25, "single": 0.1, "ep": 0.1]
        ),
        CategoryRule(
            category: .videoGames,
            strong: ["playstation": 0.8, "xbox": 0.8, "nintendo": 0.8, "steam": 0.45, "achievement unlocked": 0.85,
                     "game over": 0.75, "level up": 0.6, "victory royale": 0.95, "fortnite": 0.85, "minecraft": 0.85,
                     "roblox": 0.85, "pokemon": 0.6, "respawn": 0.75, "loading": 0.05, "high score": 0.7],
            weak: ["game": 0.25, "level": 0.15, "xp": 0.3, "quest": 0.3, "player": 0.2, "score": 0.15,
                   "coins": 0.2, "health": 0.05, "inventory": 0.2]
        ),
        CategoryRule(
            category: .memes,
            strong: ["nobody": 0.35, "me when": 0.55, "pov": 0.45, "be like": 0.4, "starter pack": 0.7,
                     "9gag": 0.85, "imgflip": 0.9, "meme": 0.6, "lmao": 0.35, "lmfao": 0.4],
            weak: ["lol": 0.2, "bruh": 0.3, "literally": 0.1, "vibes": 0.15, "mood": 0.2],
            // Meme phrasing ("me when…") shows up in normal chats too; require two cues.
            // Image-only memes are left to the on-device language model.
            minEvidence: 2
        )
    ]

    // MARK: Places & Travel

    static let travel: [CategoryRule] = [
        CategoryRule(
            category: .flights,
            strong: ["boarding pass": 0.6, "flight": 0.5, "departure": 0.5, "arrival": 0.4, "terminal": 0.3,
                     "confirmation code": 0.55, "check in": 0.3, "layover": 0.85, "nonstop": 0.75,
                     "itinerary": 0.6, "airbnb": 0.7, "booking.com": 0.75, "expedia": 0.75, "hotel": 0.4,
                     "check-in": 0.35, "reservation": 0.35, "baggage": 0.7, "carry-on": 0.7, "delta": 0.3,
                     "united": 0.15, "american airlines": 0.85, "southwest": 0.5, "jetblue": 0.85],
            weak: ["gate": 0.25, "seat": 0.15, "airport": 0.35, "trip": 0.2, "travel": 0.2, "passenger": 0.4,
                   "depart": 0.3, "arrive": 0.2, "nights": 0.2, "guests": 0.2]
        ),
        CategoryRule(
            category: .directions,
            strong: ["directions": 0.6, "turn left": 0.85, "turn right": 0.85, "continue straight": 0.85,
                     "fastest route": 0.85, "arrival time": 0.5, "eta": 0.5, "min drive": 0.8, "min walk": 0.7,
                     "get directions": 0.8, "google maps": 0.6, "route": 0.35, "transit": 0.4, "miles": 0.15],
            weak: ["mi": 0.2, "km": 0.2, "min": 0.1, "exit": 0.2, "head north": 0.5, "head south": 0.5,
                   "street": 0.1, "ave": 0.1, "st": 0.05]
        ),
        CategoryRule(
            category: .places,
            strong: ["open now": 0.4, "closes": 0.35, "reviews": 0.15, "yelp": 0.7, "tripadvisor": 0.75,
                     "google maps": 0.4, "save place": 0.7, "add to guide": 0.7, "neighborhood": 0.35],
            weak: ["address": 0.3, "located": 0.25, "visit": 0.2, "area": 0.1, "nearby": 0.3, "hours": 0.2],
            patterns: [.allOf(["open", "closes"], weight: 0.45)]
        ),
        CategoryRule(
            category: .sitesOfInterest,
            strong: ["museum": 0.6, "national park": 0.75, "landmark": 0.6, "monument": 0.65, "cathedral": 0.6,
                     "tourist attraction": 0.8, "unesco": 0.8, "historic site": 0.8],
            weak: ["tour": 0.25, "visit": 0.15, "history": 0.2, "gallery": 0.2]
        ),
        CategoryRule(
            category: .homes,
            strong: ["zillow": 0.85, "redfin": 0.85, "for sale": 0.45, "for rent": 0.55, "sq ft": 0.75, "sqft": 0.75,
                     "bedrooms": 0.6, "bathrooms": 0.5, "beds baths": 0.7, "open house": 0.8, "listing": 0.3,
                     "apartments.com": 0.85, "streeteasy": 0.85, "per month": 0.25],
            weak: ["bed": 0.15, "bath": 0.2, "rent": 0.25, "lease": 0.2, "home": 0.1, "apartment": 0.3]
        )
    ]

    // MARK: Lifestyle & Wellness

    static let lifestyle: [CategoryRule] = [
        CategoryRule(
            category: .health,
            strong: ["heart rate": 0.85, "resting heart rate": 0.9, "blood pressure": 0.85, "sleep score": 0.85,
                     "calories": 0.4, "steps": 0.35, "apple health": 0.85, "prescription": 0.75, "pharmacy": 0.6,
                     "appointment": 0.3, "dosage": 0.75, "symptoms": 0.55, "mychart": 0.9, "bpm": 0.6],
            weak: ["sleep": 0.2, "health": 0.25, "doctor": 0.3, "medical": 0.3, "patient": 0.3, "mg": 0.2]
        ),
        CategoryRule(
            category: .exercise,
            strong: ["workout": 0.65, "active calories": 0.85, "move ring": 0.85, "strava": 0.9, "reps": 0.6,
                     "sets": 0.15, "personal record": 0.75, "pace": 0.3, "peloton": 0.85,
                     "training plan": 0.7, "stand hours": 0.85],
            weak: ["run": 0.2, "miles": 0.15, "gym": 0.35, "cardio": 0.4, "strength": 0.25, "yoga": 0.35,
                   "minutes": 0.05, "distance": 0.2]
        ),
        CategoryRule(
            category: .sports,
            strong: ["espn": 0.8, "final score": 0.75, "box score": 0.85, "standings": 0.6, "playoffs": 0.65,
                     "nba": 0.75, "nfl": 0.75, "mlb": 0.75, "nhl": 0.75, "premier league": 0.8, "fantasy": 0.4,
                     "touchdown": 0.8, "quarter": 0.2, "halftime": 0.7, "championship": 0.5],
            weak: ["game": 0.15, "team": 0.2, "score": 0.2, "vs": 0.2, "season": 0.15, "league": 0.3,
                   "player": 0.15, "win": 0.1, "match": 0.15]
        ),
        CategoryRule(
            category: .recipes,
            strong: ["ingredients": 0.8, "instructions": 0.35, "prep time": 0.85, "cook time": 0.85,
                     "servings": 0.6, "tablespoon": 0.75, "tbsp": 0.8, "tsp": 0.75, "teaspoon": 0.75,
                     "preheat": 0.85, "recipe": 0.7, "cups flour": 0.9],
            weak: ["cup": 0.15, "cups": 0.2, "oz": 0.15, "bake": 0.3, "stir": 0.3, "mix": 0.2, "minutes": 0.05,
                   "salt": 0.2, "pepper": 0.15, "garlic": 0.25, "butter": 0.25, "sugar": 0.2]
        ),
        CategoryRule(
            category: .cooking,
            strong: ["preheat": 0.5, "simmer": 0.6, "saute": 0.65, "stir fry": 0.6, "air fryer": 0.7,
                     "dutch oven": 0.7],
            weak: ["bake": 0.25, "stir": 0.2, "boil": 0.3, "chop": 0.3, "dice": 0.25, "oven": 0.25, "pan": 0.15]
        ),
        CategoryRule(
            category: .food,
            strong: ["doordash": 0.75, "uber eats": 0.75, "grubhub": 0.75, "menu": 0.4, "appetizers": 0.75,
                     "entrees": 0.75, "reservation": 0.2, "opentable": 0.75, "resy": 0.75, "brunch": 0.5,
                     "restaurant": 0.4],
            weak: ["pizza": 0.3, "burger": 0.3, "sushi": 0.35, "tacos": 0.35, "salad": 0.25, "pasta": 0.3,
                   "chicken": 0.2, "dessert": 0.3, "breakfast": 0.25, "lunch": 0.25, "dinner": 0.25, "food": 0.25,
                   "delicious": 0.3, "yummy": 0.3]
        ),
        CategoryRule(
            category: .drinks,
            strong: ["cocktail": 0.6, "espresso": 0.55, "latte": 0.55, "starbucks": 0.6, "wine list": 0.8,
                     "happy hour": 0.6, "brewery": 0.65, "matcha": 0.5, "boba": 0.6],
            weak: ["coffee": 0.3, "tea": 0.2, "beer": 0.3, "wine": 0.3, "drink": 0.25, "drinks": 0.25, "bar": 0.1]
        )
    ]

    // MARK: Information

    static let information: [CategoryRule] = [
        CategoryRule(
            category: .news,
            strong: ["breaking news": 0.85, "breaking": 0.4, "reuters": 0.85, "associated press": 0.85,
                     "new york times": 0.75, "the guardian": 0.75, "bbc news": 0.85, "cnn": 0.7, "washington post": 0.8,
                     "bloomberg": 0.6, "subscribe to read": 0.7, "min read": 0.55, "updated": 0.15, "opinion": 0.3,
                     "apple news": 0.85, "reporting": 0.3, "correspondent": 0.6],
            weak: ["news": 0.3, "according": 0.2, "said": 0.1, "officials": 0.3, "report": 0.2, "article": 0.3,
                   "published": 0.25, "government": 0.2, "president": 0.2],
            patterns: [.lineCount(min: 18, weight: 0.1)]
        ),
        CategoryRule(
            category: .quotes,
            strong: ["quote of the day": 0.9, "daily quote": 0.85, "words to live by": 0.7, "inspirational": 0.5],
            weak: ["life": 0.15, "love": 0.1, "never": 0.1, "always": 0.1, "believe": 0.2, "dream": 0.2,
                   "happiness": 0.25, "success": 0.15, "soul": 0.2, "heart": 0.1]
        ),
        CategoryRule(
            category: .weather,
            strong: ["feels like": 0.6, "chance of rain": 0.85, "uv index": 0.85, "humidity": 0.6,
                     "precipitation": 0.75, "hourly forecast": 0.9, "10-day forecast": 0.9, "air quality": 0.6,
                     "forecast": 0.5, "wind": 0.15, "sunrise": 0.2, "sunset": 0.15],
            weak: ["rain": 0.2, "cloudy": 0.35, "sunny": 0.3, "storm": 0.25, "snow": 0.2, "high": 0.05, "low": 0.05],
            patterns: [.countOf(["mostly cloudy", "partly cloudy", "mostly sunny", "clear", "showers", "thunderstorms"], min: 1, weight: 0.5)]
        ),
        CategoryRule(
            category: .aiChats,
            strong: ["chatgpt": 0.85, "message chatgpt": 0.95, "ask anything": 0.6, "claude": 0.5,
                     "reply to claude": 0.95, "how can i help you today": 0.75, "gemini": 0.4, "ask gemini": 0.9,
                     "perplexity": 0.7, "copilot": 0.5, "can make mistakes": 0.85, "regenerate": 0.6, "new chat": 0.5],
            weak: ["prompt": 0.25, "model": 0.1, "ai": 0.2, "assistant": 0.2, "generate": 0.2]
        )
    ]

    // MARK: System

    static let system: [CategoryRule] = [
        CategoryRule(
            category: .notifications,
            strong: ["notification center": 0.9, "notifications": 0.4, "now": 0.1, "clear all": 0.4, "show less": 0.3],
            weak: ["ago": 0.15, "min ago": 0.3, "options": 0.1],
            patterns: [.countOf(["now", "1m ago", "2m ago", "5m ago", "yesterday", "min ago", "hours ago"], min: 3, weight: 0.55)]
        ),
        CategoryRule(
            category: .iosHomeScreens,
            strong: ["app library": 0.85],
            weak: [:],
            patterns: [.countOf(["settings", "photos", "camera", "messages", "mail", "safari", "maps", "wallet",
                                 "calendar", "clock", "weather", "notes", "reminders", "app store", "music",
                                 "facetime", "phone", "files", "health", "fitness"], min: 6, weight: 0.85)]
        ),
        CategoryRule(
            category: .settings,
            strong: ["wi-fi": 0.4, "bluetooth": 0.35, "cellular": 0.35, "privacy & security": 0.75,
                     "screen time": 0.6, "general": 0.15, "software update": 0.75, "airplane mode": 0.75,
                     "display & brightness": 0.85, "notifications": 0.15, "control center": 0.5,
                     "focus": 0.15, "battery health": 0.8, "storage": 0.2],
            weak: ["settings": 0.3, "on": 0.02, "off": 0.02, "allow": 0.15, "enable": 0.2, "toggle": 0.2],
            patterns: [.countOf(["wi-fi", "bluetooth", "cellular", "general", "notifications", "sounds & haptics",
                                 "focus", "screen time", "privacy & security", "battery", "display & brightness",
                                 "accessibility", "wallpaper"], min: 3, weight: 0.85)]
        ),
        CategoryRule(
            category: .errors,
            strong: ["something went wrong": 0.9, "an error occurred": 0.9, "error": 0.35, "failed to": 0.6,
                     "try again": 0.35, "not found": 0.4, "404": 0.6, "500 internal server error": 0.95,
                     "unexpected error": 0.9, "unable to": 0.45, "crash": 0.5, "exception": 0.55,
                     "cannot connect": 0.7, "no internet connection": 0.85, "access denied": 0.75],
            weak: ["failed": 0.25, "problem": 0.2, "issue": 0.15, "bug": 0.35, "retry": 0.3, "oops": 0.4]
        )
    ]

    // MARK: Visual categories (supporting text evidence only)

    static let visualText: [CategoryRule] = [
        CategoryRule(
            category: .clothes,
            strong: ["select size": 0.4, "size guide": 0.65, "fits true to size": 0.8, "outfit": 0.5, "ootd": 0.8],
            weak: ["dress": 0.3, "shirt": 0.3, "jacket": 0.3, "jeans": 0.3, "hoodie": 0.3, "sweater": 0.3,
                   "pants": 0.25, "skirt": 0.3, "cotton": 0.2, "xs": 0.15, "xl": 0.15, "fit": 0.1]
        ),
        CategoryRule(
            category: .shoes,
            strong: ["sneakers": 0.6, "air jordan": 0.75, "air max": 0.75, "yeezy": 0.75, "stockx": 0.75, "goat": 0.2],
            weak: ["shoe": 0.35, "shoes": 0.35, "boots": 0.3, "sandals": 0.3, "heels": 0.3, "nike": 0.2,
                   "adidas": 0.2, "new balance": 0.3, "us size": 0.3]
        ),
        CategoryRule(
            category: .watches,
            strong: ["rolex": 0.75, "omega": 0.35, "chronograph": 0.75, "automatic movement": 0.8, "dial": 0.3,
                     "chrono24": 0.85, "patek philippe": 0.85, "audemars piguet": 0.85],
            weak: ["watch": 0.25, "strap": 0.3, "bezel": 0.4, "mm": 0.1, "sapphire": 0.25]
        ),
        CategoryRule(
            category: .bags,
            strong: ["tote": 0.5, "crossbody": 0.7, "backpack": 0.5, "handbag": 0.65, "luggage": 0.45],
            weak: ["bag": 0.3, "leather": 0.2, "purse": 0.4, "wallet": 0.05]
        ),
        CategoryRule(
            category: .jewelry,
            strong: ["necklace": 0.65, "earrings": 0.65, "bracelet": 0.6, "engagement ring": 0.8, "14k": 0.7,
                     "18k": 0.7, "sterling silver": 0.65, "diamond": 0.4, "carat": 0.65, "pendant": 0.6],
            weak: ["gold": 0.2, "silver": 0.15, "ring": 0.15, "jewelry": 0.4, "gemstone": 0.4]
        ),
        CategoryRule(
            category: .furniture,
            strong: ["ikea": 0.6, "wayfair": 0.75, "west elm": 0.75, "sectional": 0.65, "nightstand": 0.65,
                     "dining table": 0.6, "bookshelf": 0.45, "dresser": 0.5],
            weak: ["sofa": 0.35, "couch": 0.35, "chair": 0.25, "table": 0.15, "desk": 0.2, "lamp": 0.25, "rug": 0.3]
        ),
        CategoryRule(
            category: .vehicles,
            strong: ["carvana": 0.85, "autotrader": 0.85, "carfax": 0.85, "mpg": 0.65, "test drive": 0.75,
                     "horsepower": 0.7, "tesla": 0.5, "mileage": 0.4, "vin": 0.4, "awd": 0.5],
            weak: ["car": 0.25, "sedan": 0.4, "suv": 0.35, "truck": 0.25, "engine": 0.2, "dealer": 0.3, "lease": 0.1]
        ),
        CategoryRule(
            category: .electronics,
            strong: ["iphone": 0.3, "macbook": 0.45, "ipad": 0.35, "airpods": 0.45, "best buy": 0.6, "tech specs": 0.75,
                     "gb storage": 0.6, "noise cancelling": 0.6, "oled": 0.5, "4k": 0.35, "mah": 0.6],
            weak: ["laptop": 0.3, "headphones": 0.3, "camera": 0.15, "monitor": 0.25, "battery": 0.1,
                   "charger": 0.3, "bluetooth": 0.1, "gb": 0.2, "tb": 0.15]
        ),
        CategoryRule(
            category: .art,
            strong: ["oil on canvas": 0.9, "acrylic on canvas": 0.9, "watercolor": 0.55, "exhibition": 0.45,
                     "artist": 0.2, "gallery": 0.25, "commission": 0.3, "procreate": 0.75],
            weak: ["painting": 0.35, "art": 0.25, "sketch": 0.3, "drawing": 0.3, "canvas": 0.25]
        ),
        CategoryRule(
            category: .people,
            strong: ["selfie": 0.6, "family photo": 0.7, "tagged": 0.15],
            weak: ["friends": 0.15, "together": 0.1]
        ),
        CategoryRule(
            category: .animals,
            strong: ["adopt": 0.35, "puppy": 0.5, "kitten": 0.5, "petfinder": 0.85, "rescue dog": 0.75],
            weak: ["dog": 0.3, "cat": 0.3, "pet": 0.3, "vet": 0.2, "breed": 0.3]
        ),
        CategoryRule(
            category: .beaches,
            strong: ["beach": 0.4],
            weak: ["ocean": 0.2, "surf": 0.25, "coast": 0.2]
        ),
        CategoryRule(
            category: .mountains,
            strong: ["summit": 0.3, "trailhead": 0.6, "elevation gain": 0.75],
            weak: ["hike": 0.25, "trail": 0.25, "peak": 0.2, "mountain": 0.3]
        ),
        CategoryRule(
            category: .plants,
            strong: ["houseplant": 0.7, "watering schedule": 0.75, "succulent": 0.6, "monstera": 0.75],
            weak: ["plant": 0.3, "soil": 0.3, "repot": 0.4, "sunlight": 0.2]
        ),
        CategoryRule(
            category: .flowers,
            strong: ["bouquet": 0.55, "florist": 0.7],
            weak: ["roses": 0.3, "tulips": 0.35, "flowers": 0.3, "bloom": 0.25]
        )
    ]

    // MARK: Communication (text cues beyond app detection)

    static let communication: [CategoryRule] = [
        CategoryRule(
            category: .email,
            strong: ["reply all": 0.75, "unsubscribe": 0.55, "sent from my iphone": 0.85, "inbox": 0.5,
                     "forward": 0.15, "to me": 0.4, "cc": 0.2],
            weak: ["from": 0.1, "to": 0.02, "reply": 0.15, "sent": 0.15, "draft": 0.25, "archive": 0.2],
            patterns: [.allOf(["from", "to", "subject"], weight: 0.7)]
        )
    ]
}
