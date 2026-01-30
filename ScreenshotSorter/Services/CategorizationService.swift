@preconcurrency import Vision
import UIKit
import CoreML

class CategorizationService {
    static let shared = CategorizationService()

    // Debug mode: Set to true to get detailed scoring logs
    private var debugMode = false  // Disabled by default for better device performance

    private init() {}

    // MARK: - Async/Await API

    /// Categorize image using Vision + OCR for multi-category detection
    func categorizeAsync(image: UIImage) async throws -> [CategoryWithConfidence] {
        guard let ciImage = CIImage(image: image) else {
            #if DEBUG
            print("❌ Failed to create CIImage")
            #endif
            return [CategoryWithConfidence(category: .other, confidence: .medium, score: 0.5)]
        }

        #if DEBUG
        print("🔍 Starting categorization...")
        #endif

        // Run all detection methods in parallel with error handling
        // NEW: Single OCR pass, reused for both app and content detection
        async let allText = detectTextOnce(in: ciImage)
        async let peopleDetected = detectPeopleAsync(in: ciImage)
        async let animalsDetected = detectAnimalsAsync(in: ciImage)

        // Get vision classification results (already has internal error handling)
        let imageCats = await classifyImageAsync(ciImage: ciImage)

        let (text, hasPeople, hasAnimals) = await (allText, peopleDetected, animalsDetected)

        // Parse text results (pure functions, no async needed)
        let appCats = detectAppsFromText(text)
        let textCats = detectContentFromText(text, ciImage: ciImage)

        // Combine and score categories
        var categoryScores: [ScreenshotCategory: Double] = [:]

        // App-specific detection has highest priority (0.8)
        for (category, confidence) in appCats {
            categoryScores[category, default: 0] += confidence * 0.8
        }

        // Vision results get higher weight - important for visual content
        // These are more reliable than text for visual categories
        for (category, confidence) in imageCats {
            let weight: Double
            // Visual categories should be prioritized from Vision (animals, food, people, clothes, etc.)
            if category == .food || category == .people || category == .clothes ||
               category == .animals || category == .drinks || category == .shoes ||
               category == .vehicles || category == .furniture || category == .homes {
                weight = 0.8 // Higher weight for visual categories
            } else {
                weight = 0.5
            }
            categoryScores[category, default: 0] += confidence * weight
        }

        // OCR results have variable weight depending on category
        for (category, confidence) in textCats {
            let weight: Double
            // Visual categories from OCR should have LOWER weight (only as fallback)
            // We want actual images of these things, not just text mentioning them
            if category == .animals || category == .vehicles || category == .furniture ||
               category == .shoes || category == .bags || category == .watches {
                weight = 0.3  // Lower weight - require visual evidence
            }
            // Content-based categories from OCR can have medium weight
            else if category == .food || category == .people || category == .clothes || category == .drinks {
                weight = 0.5  // Medium weight for content detected from text
            }
            // Text-based categories (receipts, codes, documents) should have higher weight
            else if category == .receipts || category == .codes || category == .documents {
                weight = 0.7
            }
            // Messaging, email, and social media apps have medium-high weight (app detection is reliable)
            else if category == .imessage || category == .whatsapp || category == .signal ||
                    category == .telegram || category == .discord || category == .slack ||
                    category == .email || category == .gmail ||
                    category == .instagram || category == .tiktok || category == .twitter ||
                    category == .facebook || category == .linkedin || category == .reddit || category == .youtube {
                weight = 0.5
            }
            else {
                weight = 0.4
            }
            categoryScores[category, default: 0] += confidence * weight
        }

        // People detection gets strong multiplicative bonus (not flat addition)
        if hasPeople {
            categoryScores[.people, default: 0] *= 2.0
        }

        // Animal detection gets strong multiplicative bonus (not flat addition)
        if hasAnimals {
            categoryScores[.animals, default: 0] *= 2.0
        }

        // DEBUG: Log all scoring details
        if debugMode {
            print("\n" + String(repeating: "=", count: 80))
            print("📊 CATEGORIZATION DEBUG REPORT")
            print(String(repeating: "=", count: 80))
            print("🔍 Detection Results:")
            print("   • People detected: \(hasPeople)")
            print("   • Animals detected: \(hasAnimals)")
            print("   • App categories: \(appCats.count)")
            print("   • Text categories: \(textCats.count)")
            print("   • Vision categories: \(imageCats.count)")
            print("\n📈 All Category Scores (before filtering):")
            for (category, score) in categoryScores.sorted(by: { $0.value > $1.value }) {
                let passed = score >= 0.45 ? "✅" : "❌"
                print("   \(passed) \(category.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)): \(String(format: "%.3f", score))")
            }
            print(String(repeating: "=", count: 80) + "\n")
        }

        // Filter by minimum score and limit to top 3 categories
        // Increased threshold to reduce false positives
        let finalCategories = categoryScores
            .filter { $0.value >= 0.45 } // Higher threshold for better accuracy
            .sorted { $0.value > $1.value } // Sort by confidence
            .prefix(3) // Maximum 3 categories (was 4)
            .map { CategoryWithConfidence(category: $0.key, confidence: ConfidenceLevel(score: $0.value), score: $0.value) }

        let result = Array(finalCategories)
        let resultOrOther = result.isEmpty ? [CategoryWithConfidence(category: .other, confidence: .medium, score: 0.5)] : result

        #if DEBUG
        print("✅ Categorized as: \(resultOrOther.map { $0.category.rawValue }.joined(separator: ", "))")
        print("   Scores: \(categoryScores.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key.rawValue):\(String(format: "%.2f", $0.value))" }.joined(separator: ", "))")
        #endif
        return resultOrOther
    }

    // MARK: - Unified Text Detection

    /// Single OCR pass - replaces duplicate detectAppsAsync + detectTextAsync OCR calls
    private func detectTextOnce(in image: CIImage) async -> String {
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()

            let request = VNRecognizeTextRequest { request, error in
                lock.lock()
                defer { lock.unlock() }

                guard !hasResumed else { return }
                hasResumed = true

                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    #if DEBUG
                    print("❌ OCR failed: \(error?.localizedDescription ?? "unknown")")
                    #endif
                    continuation.resume(returning: "")
                    return
                }

                let allText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
                #if DEBUG
                print("📝 OCR text: \(allText.prefix(100))...")
                #endif
                continuation.resume(returning: allText)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    lock.lock()
                    defer { lock.unlock() }

                    if !hasResumed {
                        hasResumed = true
                        #if DEBUG
                        print("❌ OCR handler error: \(error)")
                        #endif
                        continuation.resume(returning: "")
                    }
                }
            }
        }
    }

    // MARK: - App-Specific Detection (Pure Function)

    /// Detects app-specific categories from OCR text (pure function, no async)
    private func detectAppsFromText(_ allText: String) -> [ScreenshotCategory: Double] {
        var categories: [ScreenshotCategory: Double] = [:]

        // Email Apps (check first to avoid confusion with messaging apps)
        if allText.contains("gmail") || allText.contains("google mail") {
            categories[.gmail] = 0.95
        } else if (allText.contains("mail") || allText.contains("inbox")) &&
                  (allText.contains("from:") || allText.contains("to:") || allText.contains("subject:") ||
                   allText.contains("email") || allText.contains("@") && allText.contains(".com")) {
            categories[.email] = 0.9
        }

        // Books (check early to avoid confusion with messaging)
        if allText.contains("kindle") || allText.contains("goodreads") || allText.contains("apple books") ||
           (allText.contains("chapter") && (allText.contains("page") || allText.contains("book"))) {
            categories[.books] = 0.95
        }

        // Messaging Apps (high priority - 0.95 confidence) - Made more strict
        // Only trigger iMessage if we see very specific iMessage UI elements
        if allText.contains("imessage") ||
           (allText.contains("messages") && allText.contains("imessage")) ||
           (allText.contains("message") && allText.contains("delivered") && allText.contains("read") && !allText.contains("email") && !allText.contains("mail")) {
            categories[.imessage] = 0.85  // Reduced confidence to allow other categories to win
        }
        if allText.contains("whatsapp") || allText.contains("wa.me") {
            categories[.whatsapp] = 0.95
        }
        if allText.contains("signal") && (allText.contains("message") || allText.contains("chat")) {
            categories[.signal] = 0.95
        }
        if allText.contains("telegram") {
            categories[.telegram] = 0.95
        }
        if allText.contains("discord") || allText.contains("#general") || allText.contains("@everyone") {
            categories[.discord] = 0.95
        }
        if allText.contains("slack") || allText.contains("workspace") {
            categories[.slack] = 0.95
        }

        // Social Media Apps (0.9 confidence)
        if allText.contains("instagram") || allText.contains("reels") || allText.contains("tagged") {
            categories[.instagram] = 0.9
        }
        if allText.contains("tiktok") || allText.contains("for you") || allText.contains("following") {
            categories[.tiktok] = 0.9
        }
        if allText.contains("twitter") || allText.contains("tweet") || allText.contains("x.com") || allText.contains("retweet") {
            categories[.twitter] = 0.9
        }
        if allText.contains("facebook") || allText.contains("fb.com") {
            categories[.facebook] = 0.9
        }
        if allText.contains("linkedin") || allText.contains("connection") && allText.contains("profile") {
            categories[.linkedin] = 0.9
        }
        if allText.contains("reddit") || allText.contains("r/") || allText.contains("upvote") {
            categories[.reddit] = 0.9
        }
        if allText.contains("youtube") || allText.contains("subscribe") && allText.contains("views") {
            categories[.youtube] = 0.9
        }

        // Map/Navigation Apps
        if (allText.contains("directions") && (allText.contains("min") || allText.contains("eta") || allText.contains("route"))) {
            categories[.directions] = 0.95
        }
        if allText.contains("google maps") || allText.contains("apple maps") ||
           (allText.contains("map") && (allText.contains("location") || allText.contains("navigate"))) {
            categories[.places] = 0.9
        }

        // Streaming/Media Apps
        if allText.contains("spotify") || allText.contains("apple music") || allText.contains("playlist") {
            categories[.music] = 0.85
        }
        if allText.contains("netflix") || allText.contains("hulu") || allText.contains("disney+") || allText.contains("hbo") {
            categories[.movies] = 0.85
        }

        // Reading Apps
        if allText.contains("kindle") || allText.contains("goodreads") || allText.contains("apple books") {
            categories[.books] = 0.85
        }

        // Health/Fitness Apps
        if allText.contains("apple health") || allText.contains("strava") || allText.contains("peloton") {
            categories[.health] = 0.85
        }

        // Notes Apps
        if allText.contains("apple notes") || allText.contains("notion") || allText.contains("evernote") {
            categories[.notes] = 0.85
        }

        // Weather Apps
        if allText.contains("weather") && (allText.contains("°") || allText.contains("forecast")) {
            categories[.weather] = 0.85
        }

        #if DEBUG
        print("📱 App detection: \(categories.map { "\($0.key.rawValue):\($0.value)" })")
        #endif
        return categories
    }

    // MARK: - People Detection (Async)

    private func detectPeopleAsync(in image: CIImage) async -> Bool {
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()

            let request = VNDetectFaceRectanglesRequest { request, error in
                lock.lock()
                defer { lock.unlock() }

                guard !hasResumed else { return }
                hasResumed = true

                guard error == nil,
                      let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: false)
                    return
                }

                let hasFaces = !observations.isEmpty
                #if DEBUG
                print("👤 Face detection: \(hasFaces ? "Found \(observations.count) face(s)" : "No faces")")
                #endif
                continuation.resume(returning: hasFaces)
            }

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    lock.lock()
                    defer { lock.unlock() }

                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    // MARK: - Animal Detection (Async)
    
    private func detectAnimalsAsync(in image: CIImage) async -> Bool {
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()
            
            let request = VNRecognizeAnimalsRequest { request, error in
                lock.lock()
                defer { lock.unlock() }
                
                guard !hasResumed else { return }
                hasResumed = true
                
                guard error == nil,
                      let observations = request.results as? [VNRecognizedObjectObservation],
                      !observations.isEmpty else {
                    continuation.resume(returning: false)
                    return
                }
                
                // Filter for high-confidence animal detections
                let confidenceThreshold: Float = 0.5
                let animals = observations.filter { $0.confidence >= confidenceThreshold }
                
                let hasAnimals = !animals.isEmpty
                #if DEBUG
                if hasAnimals {
                    let animalTypes = animals.compactMap { $0.labels.first?.identifier }.joined(separator: ", ")
                    print("🐾 Animal detection: Found \(animals.count) animal(s) - \(animalTypes)")
                } else {
                    print("🐾 Animal detection: No animals detected")
                }
                #endif

                continuation.resume(returning: hasAnimals)
            }
            
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    lock.lock()
                    defer { lock.unlock() }
                    
                    if !hasResumed {
                        hasResumed = true
                        #if DEBUG
                        print("⚠️ Animal detection error: \(error.localizedDescription)")
                        #endif
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    // MARK: - Content Detection (Pure Function)

    /// Detects content categories from OCR text (pure function, no async)
    private func detectContentFromText(_ allText: String, ciImage: CIImage) -> [ScreenshotCategory: Double] {
        var categories: [ScreenshotCategory: Double] = [:]

        // Events
        if self.detectEvents(allText) > 0 {
            categories[.events] = self.detectEvents(allText)
        }

        // Codes & QR
        if self.containsCodeKeywords(allText) || self.hasQRCode(in: ciImage) {
            categories[.codes] = 1.0
        }

        // Receipts
        if self.containsReceiptKeywords(allText) {
            categories[.receipts] = 1.0
        }

        // Directions
        if self.detectDirections(allText) > 0 {
            categories[.directions] = self.detectDirections(allText)
        }

        // Places
        if self.detectPlaces(allText) > 0 {
            categories[.places] = self.detectPlaces(allText)
        }

        // Clothes
        let clothingConfidence = self.getClothingConfidence(allText)
        if clothingConfidence > 0 {
            categories[.clothes] = clothingConfidence
        }

        // People
        let peopleConfidence = self.getPeopleConfidence(allText)
        if peopleConfidence > 0 {
            categories[.people] = peopleConfidence
        }

        // Shoes
        if self.detectShoes(allText) > 0 {
            categories[.shoes] = self.detectShoes(allText)
        }

        // Food
        let foodConfidence = self.getFoodConfidence(allText)
        if foodConfidence > 0 {
            categories[.food] = foodConfidence
        }

        // Drinks
        if self.detectDrinks(allText) > 0 {
            categories[.drinks] = self.detectDrinks(allText)
        }

        // Stores
        if self.containsStoreKeywords(allText) {
            categories[.stores] = 0.8
        }

        // Storefronts
        if self.detectStorefronts(allText) > 0 {
            categories[.storefronts] = self.detectStorefronts(allText)
        }

        // Watches
        if self.detectWatches(allText) > 0 {
            categories[.watches] = self.detectWatches(allText)
        }

        // Furniture
        if self.detectFurniture(allText) > 0 {
            categories[.furniture] = self.detectFurniture(allText)
        }

        // Homes
        if self.detectHomes(allText) > 0 {
            categories[.homes] = self.detectHomes(allText)
        }

        // Sites of Interest
        if self.detectSitesOfInterest(allText) > 0 {
            categories[.sitesOfInterest] = self.detectSitesOfInterest(allText)
        }

        // Bags
        if self.detectBags(allText) > 0 {
            categories[.bags] = self.detectBags(allText)
        }

        // Jewelry
        if self.detectJewelry(allText) > 0 {
            categories[.jewelry] = self.detectJewelry(allText)
        }

        // Vehicles
        if self.detectVehicles(allText) > 0 {
            categories[.vehicles] = self.detectVehicles(allText)
        }

        // Electronics
        if self.detectElectronics(allText) > 0 {
            categories[.electronics] = self.detectElectronics(allText)
        }

        // Animals
        if self.detectAnimals(allText) > 0 {
            categories[.animals] = self.detectAnimals(allText)
        }

        // Quotes
        if self.detectQuotes(allText) > 0 {
            categories[.quotes] = self.detectQuotes(allText)
        }

        // Books
        let bookConfidence = self.getBookConfidence(allText)
        if bookConfidence > 0 {
            categories[.books] = bookConfidence
        }

        // Movies & TV
        if self.detectMovies(allText) > 0 {
            categories[.movies] = self.detectMovies(allText)
        }

        // Music
        if self.detectMusic(allText) > 0 {
            categories[.music] = self.detectMusic(allText)
        }

        // Video Games
        if self.detectVideoGames(allText) > 0 {
            categories[.videoGames] = self.detectVideoGames(allText)
        }

        // Flights & Travel
        if self.detectFlights(allText) > 0 {
            categories[.flights] = self.detectFlights(allText)
        }

        // Memes
        if self.detectMemes(allText) > 0 {
            categories[.memes] = self.detectMemes(allText)
        }

        // Documents
        if self.containsDocumentKeywords(allText) {
            categories[.documents] = 0.8
        }

        // Health & Fitness
        if self.detectHealth(allText) > 0 {
            categories[.health] = self.detectHealth(allText)
        }

        // Notes
        if self.detectNotes(allText) > 0 {
            categories[.notes] = self.detectNotes(allText)
        }

        // Weather
        if self.detectWeather(allText) > 0 {
            categories[.weather] = self.detectWeather(allText)
        }

        // Sports
        if self.detectSports(allText) > 0 {
            categories[.sports] = self.detectSports(allText)
        }

        // News & Articles
        if self.detectNews(allText) > 0 {
            categories[.news] = self.detectNews(allText)
        }

        // Notifications
        if self.detectNotifications(allText) > 0 {
            categories[.notifications] = self.detectNotifications(allText)
        }

        // iOS Home Screens
        if self.detectIOSHomeScreen(allText) > 0 {
            categories[.iosHomeScreens] = self.detectIOSHomeScreen(allText)
        }

        #if DEBUG
        print("📋 OCR categories: \(categories.map { "\($0.key.rawValue):\($0.value)" })")
        #endif
        return categories
    }

    // MARK: - Vision Image Classification (Async)

    private func classifyImageAsync(ciImage: CIImage) async -> [ScreenshotCategory: Double] {
        do {
            // Try to use FastViT CoreML model first (better accuracy)
            if let fastVitResults = try? await classifyWithFastViT(ciImage: ciImage) {
                return fastVitResults
            }
            
            // Fallback to built-in Vision classifier
            #if DEBUG
            print("⚠️ FastViT unavailable, using built-in Vision classifier")
            #endif
            let request = ClassifyImageRequest()
            let results = try await request.perform(on: ciImage)

            var categoryScores: [ScreenshotCategory: Double] = [:]

            // Analyze top classifications with higher confidence threshold
            for observation in results.prefix(15) where observation.confidence > 0.25 {
                let identifier = observation.identifier.lowercased()
                let confidence = Double(observation.confidence)

                #if DEBUG
                print("  🔍 \(identifier): \(confidence)")
                #endif

                // Map Vision classifications to our categories
                if self.isFood(identifier) {
                    categoryScores[.food] = max(categoryScores[.food] ?? 0, confidence)
                }
                if self.isDrink(identifier) {
                    categoryScores[.drinks] = max(categoryScores[.drinks] ?? 0, confidence)
                }
                if self.isClothing(identifier) {
                    categoryScores[.clothes] = max(categoryScores[.clothes] ?? 0, confidence)
                }
                if self.isShoe(identifier) {
                    categoryScores[.shoes] = max(categoryScores[.shoes] ?? 0, confidence)
                }
                if self.isPerson(identifier) {
                    categoryScores[.people] = max(categoryScores[.people] ?? 0, confidence)
                }
                if self.isPlace(identifier) {
                    categoryScores[.places] = max(categoryScores[.places] ?? 0, confidence)
                }
                if self.isElectronics(identifier) {
                    categoryScores[.electronics] = max(categoryScores[.electronics] ?? 0, confidence)
                }
                if self.isFurniture(identifier) {
                    categoryScores[.furniture] = max(categoryScores[.furniture] ?? 0, confidence)
                }
                if self.isHome(identifier) {
                    categoryScores[.homes] = max(categoryScores[.homes] ?? 0, confidence)
                }
                if self.isVehicle(identifier) {
                    categoryScores[.vehicles] = max(categoryScores[.vehicles] ?? 0, confidence)
                }
                if self.isAnimal(identifier) {
                    categoryScores[.animals] = max(categoryScores[.animals] ?? 0, confidence)
                }
                if self.isWatch(identifier) {
                    categoryScores[.watches] = max(categoryScores[.watches] ?? 0, confidence)
                }
                if self.isBag(identifier) {
                    categoryScores[.bags] = max(categoryScores[.bags] ?? 0, confidence)
                }
                if self.isSiteOfInterest(identifier) {
                    categoryScores[.sitesOfInterest] = max(categoryScores[.sitesOfInterest] ?? 0, confidence)
                }
                if self.isBook(identifier) {
                    categoryScores[.books] = max(categoryScores[.books] ?? 0, confidence)
                }
                // Nature & Outdoors
                if self.isNature(identifier) {
                    categoryScores[.nature] = max(categoryScores[.nature] ?? 0, confidence)
                }
                if self.isLandscape(identifier) {
                    categoryScores[.landscapes] = max(categoryScores[.landscapes] ?? 0, confidence)
                }
                if self.isBeach(identifier) {
                    categoryScores[.beaches] = max(categoryScores[.beaches] ?? 0, confidence)
                }
                if self.isMountain(identifier) {
                    categoryScores[.mountains] = max(categoryScores[.mountains] ?? 0, confidence)
                }
                if self.isFlower(identifier) {
                    categoryScores[.flowers] = max(categoryScores[.flowers] ?? 0, confidence)
                }
                if self.isPlant(identifier) {
                    categoryScores[.plants] = max(categoryScores[.plants] ?? 0, confidence)
                }
                if self.isSunset(identifier) {
                    categoryScores[.sunset] = max(categoryScores[.sunset] ?? 0, confidence)
                }
                // Cooking & Activities
                if self.isCooking(identifier) {
                    categoryScores[.cooking] = max(categoryScores[.cooking] ?? 0, confidence)
                }
                if self.isRecipe(identifier) {
                    categoryScores[.recipes] = max(categoryScores[.recipes] ?? 0, confidence)
                }
                if self.isExercise(identifier) {
                    categoryScores[.exercise] = max(categoryScores[.exercise] ?? 0, confidence)
                }
                if self.isArt(identifier) {
                    categoryScores[.art] = max(categoryScores[.art] ?? 0, confidence)
                }
                if self.isReading(identifier) {
                    categoryScores[.reading] = max(categoryScores[.reading] ?? 0, confidence)
                }
            }

            #if DEBUG
            print("🖼️ Vision categories: \(categoryScores.map { "\($0.key.rawValue):\($0.value)" })")
            #endif
            return categoryScores
        } catch {
            #if DEBUG
            print("❌ Vision failed: \(error.localizedDescription)")
            #endif
            return [:]
        }
    }
    
    // MARK: - FastViT CoreML Classification
    
    private func classifyWithFastViT(ciImage: CIImage) async throws -> [ScreenshotCategory: Double] {
        #if DEBUG
        print("🚀 Using FastViT T8 CoreML model for classification...")
        #endif

        // Load FastViT T8F16 model - try both compiled (.mlmodelc) and package (.mlpackage) formats
        var modelURL = Bundle.main.url(forResource: "FastViTT8F16", withExtension: "mlmodelc")
        if modelURL == nil {
            modelURL = Bundle.main.url(forResource: "FastViTT8F16", withExtension: "mlpackage")
        }
        guard let modelURL = modelURL else {
            #if DEBUG
            print("❌ FastViT model file not found in bundle (tried .mlmodelc and .mlpackage)")
            #endif
            throw NSError(domain: "CoreML", code: -1, userInfo: [NSLocalizedDescriptionKey: "FastViT model not found"])
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all // Use Neural Engine when available
        #if DEBUG
        print("⚙️ FastViT loaded from \(modelURL.lastPathComponent) - using Neural Engine + GPU + CPU")
        #endif
        
        let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
        let visionModel = try VNCoreMLModel(for: mlModel)
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let results = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [:])
                    return
                }
                
                var categoryScores: [ScreenshotCategory: Double] = [:]
                
                // Analyze top classifications with higher confidence threshold
                for observation in results.prefix(15) where observation.confidence > 0.25 {
                    let identifier = observation.identifier.lowercased()
                    let confidence = Double(observation.confidence)
                    
                    #if DEBUG
                    print("  🚀 FastViT: \(identifier): \(confidence)")
                    #endif
                    
                    // Map FastViT classifications to our categories
                    if self.isFood(identifier) {
                        categoryScores[.food] = max(categoryScores[.food] ?? 0, confidence)
                    }
                    if self.isDrink(identifier) {
                        categoryScores[.drinks] = max(categoryScores[.drinks] ?? 0, confidence)
                    }
                    if self.isClothing(identifier) {
                        categoryScores[.clothes] = max(categoryScores[.clothes] ?? 0, confidence)
                    }
                    if self.isShoe(identifier) {
                        categoryScores[.shoes] = max(categoryScores[.shoes] ?? 0, confidence)
                    }
                    if self.isPerson(identifier) {
                        categoryScores[.people] = max(categoryScores[.people] ?? 0, confidence)
                    }
                    if self.isPlace(identifier) {
                        categoryScores[.places] = max(categoryScores[.places] ?? 0, confidence)
                    }
                    if self.isElectronics(identifier) {
                        categoryScores[.electronics] = max(categoryScores[.electronics] ?? 0, confidence)
                    }
                    if self.isFurniture(identifier) {
                        categoryScores[.furniture] = max(categoryScores[.furniture] ?? 0, confidence)
                    }
                    if self.isHome(identifier) {
                        categoryScores[.homes] = max(categoryScores[.homes] ?? 0, confidence)
                    }
                    if self.isVehicle(identifier) {
                        categoryScores[.vehicles] = max(categoryScores[.vehicles] ?? 0, confidence)
                    }
                    if self.isAnimal(identifier) {
                        categoryScores[.animals] = max(categoryScores[.animals] ?? 0, confidence)
                    }
                    if self.isWatch(identifier) {
                        categoryScores[.watches] = max(categoryScores[.watches] ?? 0, confidence)
                    }
                    if self.isBag(identifier) {
                        categoryScores[.bags] = max(categoryScores[.bags] ?? 0, confidence)
                    }
                    if self.isSiteOfInterest(identifier) {
                        categoryScores[.sitesOfInterest] = max(categoryScores[.sitesOfInterest] ?? 0, confidence)
                    }
                    if self.isBook(identifier) {
                        categoryScores[.books] = max(categoryScores[.books] ?? 0, confidence)
                    }
                    // Nature & Outdoors
                    if self.isNature(identifier) {
                        categoryScores[.nature] = max(categoryScores[.nature] ?? 0, confidence)
                    }
                    if self.isLandscape(identifier) {
                        categoryScores[.landscapes] = max(categoryScores[.landscapes] ?? 0, confidence)
                    }
                    if self.isBeach(identifier) {
                        categoryScores[.beaches] = max(categoryScores[.beaches] ?? 0, confidence)
                    }
                    if self.isMountain(identifier) {
                        categoryScores[.mountains] = max(categoryScores[.mountains] ?? 0, confidence)
                    }
                    if self.isFlower(identifier) {
                        categoryScores[.flowers] = max(categoryScores[.flowers] ?? 0, confidence)
                    }
                    if self.isPlant(identifier) {
                        categoryScores[.plants] = max(categoryScores[.plants] ?? 0, confidence)
                    }
                    if self.isSunset(identifier) {
                        categoryScores[.sunset] = max(categoryScores[.sunset] ?? 0, confidence)
                    }
                    // Cooking & Activities
                    if self.isCooking(identifier) {
                        categoryScores[.cooking] = max(categoryScores[.cooking] ?? 0, confidence)
                    }
                    if self.isRecipe(identifier) {
                        categoryScores[.recipes] = max(categoryScores[.recipes] ?? 0, confidence)
                    }
                    if self.isExercise(identifier) {
                        categoryScores[.exercise] = max(categoryScores[.exercise] ?? 0, confidence)
                    }
                    if self.isArt(identifier) {
                        categoryScores[.art] = max(categoryScores[.art] ?? 0, confidence)
                    }
                    if self.isReading(identifier) {
                        categoryScores[.reading] = max(categoryScores[.reading] ?? 0, confidence)
                    }
                }

                #if DEBUG
                print("🚀 FastViT detected categories: \(categoryScores.map { "\($0.key.rawValue):\(String(format: "%.2f", $0.value))" }.joined(separator: ", "))")
                #endif
                continuation.resume(returning: categoryScores)
            }
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Legacy Callback API (for backward compatibility)

    func categorize(image: UIImage, completion: @escaping ([ScreenshotCategory]) -> Void) {
        Task {
            do {
                let categoriesWithConfidence = try await categorizeAsync(image: image)
                let categories = categoriesWithConfidence.map { $0.category }
                await MainActor.run {
                    completion(categories)
                }
            } catch {
                #if DEBUG
                print("❌ Categorization error: \(error)")
                #endif
                await MainActor.run {
                    completion([.other])
                }
            }
        }
    }


    private func hasQRCode(in image: CIImage) -> Bool {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: image) ?? []
        return !features.isEmpty
    }

    // MARK: - Category Detection Helpers

    private func isFood(_ identifier: String) -> Bool {
        let keywords = ["food", "pizza", "burger", "sandwich", "salad", "pasta", "sushi", "dessert", "cake", "fruit", "vegetable", "drink", "coffee", "restaurant", "dining", "meal", "breakfast", "lunch", "dinner", "cuisine", "dish", "plate", "bowl", "egg", "rice", "noodle"]
        return keywords.contains(where: identifier.contains)
    }

    private func isClothing(_ identifier: String) -> Bool {
        let keywords = ["shirt", "dress", "pants", "shoes", "hat", "jacket", "coat", "clothing", "apparel", "fashion", "wear", "sneaker", "boot", "leather jacket", "jean", "sweater", "hoodie", "sock"]
        return keywords.contains(where: identifier.contains)
    }

    private func isPerson(_ identifier: String) -> Bool {
        let keywords = ["person", "people", "human", "man", "woman", "face", "portrait", "celebrity", "actor", "model", "singer", "artist", "musician", "performer", "male", "female", "gentleman", "lady", "boy", "girl"]
        return keywords.contains(where: identifier.contains)
    }

    private func isBook(_ identifier: String) -> Bool {
        let keywords = ["book", "novel", "publication", "cover", "paperback", "hardcover", "magazine"]
        return keywords.contains(where: identifier.contains)
    }

    private func isPlace(_ identifier: String) -> Bool {
        let keywords = ["building", "architecture", "landmark", "street", "city", "park", "outdoor", "landscape", "scenery"]
        return keywords.contains(where: identifier.contains)
    }

    private func isElectronics(_ identifier: String) -> Bool {
        let keywords = ["computer", "laptop", "phone", "tablet", "screen", "monitor", "keyboard", "electronic", "device", "gadget"]
        return keywords.contains(where: identifier.contains)
    }

    private func isHome(_ identifier: String) -> Bool {
        let keywords = ["home", "house", "apartment", "interior", "room", "bedroom", "kitchen", "bathroom", "living room"]
        return keywords.contains(where: identifier.contains)
    }

    // Text-based category detection
    private func getBookConfidence(_ text: String) -> Double {
        // Don't classify as book if it's a Google search
        if (text.contains("google") && text.contains("search")) ||
           (text.contains("all") && text.contains("images") && text.contains("videos")) {
            return 0.0
        }

        var confidence = 0.0
        let bookIndicators = [
            ("author:", 0.4),  // More specific with colon
            ("isbn", 0.5),
            ("publisher:", 0.4),
            ("chapter", 0.25),
            ("edition", 0.2),
            ("translated by", 0.3),
            ("foreword", 0.3),
            ("penguin", 0.25),
            ("vintage", 0.2),
            ("novel", 0.3),
            ("pages:", 0.3),
            ("library", 0.6),
            ("libraries", 0.6),
            ("bookshop", 0.7),
            ("bookstore", 0.7),
            ("book lovers", 0.6)
        ]

        for (keyword, weight) in bookIndicators {
            if text.contains(keyword) {
                confidence += weight
            }
        }

        // Higher confidence for book-specific apps/sites
        if text.contains("amazon books") || text.contains("kindle") || text.contains("goodreads") {
            confidence = max(confidence, 0.7)
        }

        return min(confidence, 1.0)
    }

    private func containsBookKeywords(_ text: String) -> Bool {
        return getBookConfidence(text) > 0
    }

    private func containsReceiptKeywords(_ text: String) -> Bool {
        let keywords = ["receipt", "total", "subtotal", "tax", "paid", "invoice", "order #", "transaction"]
        return keywords.contains(where: text.contains)
    }

    private func containsStoreKeywords(_ text: String) -> Bool {
        let keywords = ["amazon", "ebay", "walmart", "target", "shop", "buy now", "add to cart", "price", "$"]
        return keywords.contains(where: text.contains)
    }


    private func containsDocumentKeywords(_ text: String) -> Bool {
        let keywords = ["pdf", "document", "file", "download", "pages", "word", "excel"]
        return keywords.contains(where: text.contains)
    }

    private func containsCodeKeywords(_ text: String) -> Bool {
        let keywords = ["code:", "qr", "barcode", "scan"]
        return keywords.contains(where: text.contains)
    }

    // Enhanced content-based detection (works without Vision)
    private func getFoodConfidence(_ text: String) -> Double {
        var confidence = 0.0

        let foodKeywords = [
            ("recipe", 0.6),
            ("ingredients", 0.5),
            ("cooking", 0.5),
            ("baked", 0.5),
            ("scrambled", 0.6),
            ("eggs", 0.4),
            ("steak", 0.7),
            ("breakfast", 0.6),
            ("dinner", 0.5),
            ("lunch", 0.5),
            ("yield:", 0.6),  // Recipe indicator
            ("min •", 0.4),   // Recipe time format
            ("serve", 0.4),
            ("pizza", 0.8),
            ("burger", 0.8),
            ("pasta", 0.7),
            ("salad", 0.7),
            ("soup", 0.7),
            ("chicken", 0.6),
            ("beef", 0.6),
            ("pork", 0.6),
            ("fish", 0.6),
            ("vegetable", 0.5),
            ("fruit", 0.5),
            ("dessert", 0.7),
            ("cake", 0.7),
            ("cookie", 0.6),
            ("bread", 0.5)
        ]

        for (keyword, weight) in foodKeywords {
            if text.contains(keyword) {
                confidence += weight
            }
        }

        return min(confidence, 1.0)
    }

    private func getPeopleConfidence(_ text: String) -> Double {
        var confidence = 0.0

        // Celebrity/famous people names
        let celebrities = [
            "robert redford", "marlon brando", "brad pitt", "leonardo dicaprio",
            "tom cruise", "denzel washington", "morgan freeman", "will smith",
            "johnny depp", "harrison ford", "robert downey", "chris hemsworth",
            "scarlett johansson", "jennifer lawrence", "meryl streep", "julia roberts",
            "emma watson", "angelina jolie", "natalie portman", "beyonce",
            "taylor swift", "ariana grande", "billie eilish", "rihanna",
            "drake", "kanye west", "jay-z", "eminem", "kendrick lamar"
        ]

        for celebrity in celebrities {
            if text.contains(celebrity) {
                confidence = 0.9
                break
            }
        }

        // People-related keywords
        let peopleKeywords = [
            ("actor", 0.5),
            ("actress", 0.5),
            ("celebrity", 0.6),
            ("portrait", 0.6),
            ("model", 0.4),
            ("singer", 0.5),
            ("musician", 0.5),
            ("artist", 0.3),
            ("performer", 0.4),
            ("starring", 0.5)
        ]

        for (keyword, weight) in peopleKeywords {
            if text.contains(keyword) {
                confidence = max(confidence, weight)
            }
        }

        return confidence
    }

    private func getClothingConfidence(_ text: String) -> Double {
        var confidence = 0.0

        let clothingKeywords = [
            ("jacket", 0.7),
            ("coat", 0.7),
            ("dress", 0.8),
            ("shirt", 0.6),
            ("pants", 0.6),
            ("jeans", 0.7),
            ("suit", 0.7),
            ("leather jacket", 0.9),
            ("perfecto", 0.8),
            ("polo", 0.6),
            ("ralph lauren", 0.5),
            ("fashion", 0.5),
            ("apparel", 0.6),
            ("wear", 0.3),
            ("outfit", 0.6),
            ("style", 0.3),
            ("hoodie", 0.7),
            ("sweater", 0.7)
        ]

        for (keyword, weight) in clothingKeywords {
            if text.contains(keyword) {
                confidence = max(confidence, weight)
            }
        }

        return confidence
    }

    // MARK: - New Category Detection Methods

    private func detectEvents(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("calendar", 0.6),
            ("event", 0.7),
            ("rsvp", 0.9),
            ("join us", 0.8),
            ("save the date", 0.9),
            ("partiful", 0.95),
            ("eventbrite", 0.95),
            ("invite", 0.7),
            ("meeting", 0.5),
            ("venue", 0.6)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectDirections(_ text: String) -> Double {
        var confidence = 0.0
        if (text.contains("directions") || text.contains("route") || text.contains("navigate")) &&
           (text.contains("min") || text.contains("eta") || text.contains("miles") || text.contains("km")) {
            confidence = 0.9
        }
        return confidence
    }

    private func detectPlaces(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("address", 0.7),
            ("street", 0.6),
            ("location", 0.5),
            ("phone number", 0.6),
            ("business hours", 0.7),
            ("reviews", 0.5),
            ("yelp", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectShoes(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("shoes", 0.8),
            ("sneakers", 0.9),
            ("boots", 0.8),
            ("sandals", 0.8),
            ("kicks", 0.8),
            ("jordans", 0.95),
            ("nike", 0.6),
            ("adidas", 0.6),
            ("stockx", 0.95),
            ("goat", 0.7),
            ("heels", 0.9),
            ("flats", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectDrinks(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("coffee", 0.8),
            ("latte", 0.9),
            ("espresso", 0.9),
            ("starbucks", 0.9),
            ("cocktail", 0.9),
            ("beer", 0.8),
            ("wine", 0.8),
            ("smoothie", 0.8),
            ("juice", 0.7),
            ("tea", 0.7),
            ("drink", 0.5),
            ("beverage", 0.6),
            ("bar", 0.5)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectStorefronts(_ text: String) -> Double {
        var confidence = 0.0
        if text.contains("storefront") || text.contains("shop entrance") {
            confidence = 0.9
        }
        return confidence
    }

    private func detectWatches(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("watch", 0.7),
            ("rolex", 0.95),
            ("omega", 0.95),
            ("apple watch", 0.95),
            ("smartwatch", 0.9),
            ("timepiece", 0.9)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectFurniture(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("furniture", 0.8),
            ("sofa", 0.9),
            ("couch", 0.9),
            ("chair", 0.7),
            ("table", 0.7),
            ("desk", 0.8),
            ("lamp", 0.8),
            ("ikea", 0.9),
            ("wayfair", 0.9),
            ("bookshelf", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectHomes(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("zillow", 0.95),
            ("redfin", 0.95),
            ("real estate", 0.9),
            ("bedroom", 0.7),
            ("bathroom", 0.7),
            ("kitchen", 0.6),
            ("living room", 0.6),
            ("apartment", 0.7),
            ("condo", 0.8),
            ("property", 0.6)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectSitesOfInterest(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("landmark", 0.9),
            ("monument", 0.9),
            ("museum", 0.8),
            ("tourist", 0.7),
            ("attraction", 0.7),
            ("historic", 0.7),
            ("tripadvisor", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectBags(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("bag", 0.6),
            ("backpack", 0.9),
            ("purse", 0.9),
            ("handbag", 0.9),
            ("tote", 0.9),
            ("clutch", 0.9),
            ("briefcase", 0.8),
            ("luggage", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectJewelry(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("jewelry", 0.9),
            ("necklace", 0.9),
            ("ring", 0.7),
            ("bracelet", 0.9),
            ("earring", 0.9),
            ("diamond", 0.8),
            ("gold", 0.6),
            ("silver", 0.6),
            ("pendant", 0.9),
            ("chain", 0.6),
            ("carat", 0.9),
            ("gemstone", 0.9)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectVehicles(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("car", 0.6),
            ("vehicle", 0.7),
            ("suv", 0.9),
            ("truck", 0.8),
            ("motorcycle", 0.9),
            ("tesla", 0.95),
            ("bmw", 0.8),
            ("mercedes", 0.8),
            ("sedan", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectElectronics(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("iphone", 0.9),
            ("ipad", 0.9),
            ("macbook", 0.9),
            ("laptop", 0.8),
            ("computer", 0.7),
            ("camera", 0.8),
            ("headphones", 0.8),
            ("speaker", 0.7),
            ("playstation", 0.9),
            ("xbox", 0.9),
            ("gaming", 0.7)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectAnimals(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("dog", 0.8),
            ("cat", 0.8),
            ("puppy", 0.9),
            ("kitten", 0.9),
            ("pet", 0.7),
            ("animal", 0.6),
            ("bird", 0.7),
            ("bunny", 0.8),
            ("horse", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectQuotes(_ text: String) -> Double {
        var confidence = 0.0
        if (text.contains("\"") || text.contains("quote") || text.contains("inspiration") || text.contains("motivational")) {
            if text.contains(" - ") || text.contains("wisdom") || text.contains("saying") {
                confidence = 0.8
            } else {
                confidence = 0.5
            }
        }
        return confidence
    }

    private func detectMovies(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("netflix", 0.9),
            ("hulu", 0.9),
            ("disney+", 0.9),
            ("hbo", 0.9),
            ("imdb", 0.95),
            ("movie", 0.7),
            ("film", 0.7),
            ("episode", 0.8),
            ("season", 0.7),
            ("series", 0.7),
            ("watch now", 0.6)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectMusic(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("spotify", 0.95),
            ("apple music", 0.95),
            ("playlist", 0.8),
            ("album", 0.7),
            ("artist", 0.5),
            ("song", 0.6),
            ("track", 0.5),
            ("concert", 0.8),
            ("lyrics", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectVideoGames(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("playstation", 0.95),
            ("xbox", 0.95),
            ("nintendo", 0.95),
            ("steam", 0.9),
            ("gaming", 0.7),
            ("gamer", 0.8),
            ("game", 0.5),
            ("console", 0.7),
            ("multiplayer", 0.8),
            ("fps", 0.8),
            ("rpg", 0.7),
            ("esports", 0.9),
            ("twitch", 0.8),
            ("streamer", 0.7)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectFlights(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("flight", 0.9),
            ("boarding", 0.95),
            ("departure", 0.9),
            ("arrival", 0.9),
            ("gate", 0.8),
            ("airline", 0.8),
            ("airport", 0.7),
            ("confirmation", 0.6),
            ("booking", 0.6),
            ("hotel", 0.7),
            ("airbnb", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectMemes(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("lol", 0.7),
            ("lmao", 0.8),
            ("meme", 0.95),
            ("funny", 0.5),
            ("hilarious", 0.6),
            ("viral", 0.6)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectHealth(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("workout", 0.9),
            ("exercise", 0.9),
            ("calories", 0.8),
            ("steps", 0.8),
            ("heart rate", 0.9),
            ("fitness", 0.8),
            ("gym", 0.8),
            ("health", 0.6)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectNotes(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("todo", 0.8),
            ("checklist", 0.9),
            ("reminder", 0.7),
            ("task", 0.6),
            ("note", 0.5)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectWeather(_ text: String) -> Double {
        var confidence = 0.0
        if text.contains("weather") || text.contains("forecast") ||
           (text.contains("°") && (text.contains("sunny") || text.contains("rain") || text.contains("cloud"))) {
            confidence = 0.9
        }
        return confidence
    }

    private func detectSports(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("score", 0.6),
            ("game", 0.4),
            ("nfl", 0.9),
            ("nba", 0.9),
            ("mlb", 0.9),
            ("espn", 0.95),
            ("fantasy", 0.7),
            ("team", 0.3),
            ("player", 0.4)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectNews(_ text: String) -> Double {
        var confidence = 0.0
        let keywords = [
            ("breaking", 0.8),
            ("news", 0.6),
            ("article", 0.7),
            ("published", 0.6),
            ("newsletter", 0.8),
            ("journalism", 0.8)
        ]
        for (keyword, weight) in keywords {
            if text.contains(keyword) { confidence = max(confidence, weight) }
        }
        return confidence
    }

    private func detectNotifications(_ text: String) -> Double {
        var confidence = 0.0
        if text.contains("notification") && (text.contains("ago") || text.contains("now")) {
            confidence = 0.8
        }
        return confidence
    }

    private func detectIOSHomeScreen(_ text: String) -> Double {
        var confidence = 0.0
        // Detect if multiple app names appear (Settings, Photos, Messages, etc.)
        let appKeywords = ["settings", "photos", "camera", "messages", "mail", "safari", "maps", "wallet"]
        var appCount = 0
        for keyword in appKeywords {
            if text.contains(keyword) { appCount += 1 }
        }
        if appCount >= 3 {
            confidence = 0.9
        }
        return confidence
    }

    // MARK: - Vision Category Helpers (updated)

    private func isDrink(_ identifier: String) -> Bool {
        let keywords = ["coffee", "cup", "drink", "beverage", "tea", "cocktail", "beer", "wine", "glass"]
        return keywords.contains(where: identifier.contains)
    }

    private func isShoe(_ identifier: String) -> Bool {
        let keywords = ["shoe", "sneaker", "boot", "sandal", "footwear"]
        return keywords.contains(where: identifier.contains)
    }

    private func isFurniture(_ identifier: String) -> Bool {
        let keywords = ["furniture", "chair", "table", "sofa", "couch", "desk", "lamp", "bed"]
        return keywords.contains(where: identifier.contains)
    }

    private func isVehicle(_ identifier: String) -> Bool {
        let keywords = ["car", "vehicle", "automobile", "truck", "motorcycle", "bike", "sedan", "suv"]
        return keywords.contains(where: identifier.contains)
    }

    private func isAnimal(_ identifier: String) -> Bool {
        let keywords = ["dog", "cat", "animal", "pet", "bird", "horse", "wildlife", "mammal"]
        return keywords.contains(where: identifier.contains)
    }

    private func isWatch(_ identifier: String) -> Bool {
        let keywords = ["watch", "clock", "timepiece"]
        return keywords.contains(where: identifier.contains)
    }

    private func isBag(_ identifier: String) -> Bool {
        let keywords = ["bag", "backpack", "purse", "luggage", "suitcase"]
        return keywords.contains(where: identifier.contains)
    }


    // New category helpers for Nature & Outdoors
    private func isNature(_ identifier: String) -> Bool {
        let keywords = ["nature", "outdoor", "wilderness", "forest", "tree", "grass", "field", "park", "scenery", "natural"]
        return keywords.contains(where: identifier.contains)
    }
    
    private func isLandscape(_ identifier: String) -> Bool {
        let keywords = ["landscape", "scenery", "vista", "horizon", "valley", "cliff", "canyon", "rock"]
        return keywords.contains(where: identifier.contains)
    }
    
    private func isBeach(_ identifier: String) -> Bool {
        let keywords = ["beach", "sand", "ocean", "sea", "coast", "shore", "wave", "tropical", "island"]
        return keywords.contains(where: identifier.contains)
    }
    
    private func isMountain(_ identifier: String) -> Bool {
        let keywords = ["mountain", "peak", "summit", "alpine", "hill", "volcano"]
        return keywords.contains(where: identifier.contains)
    }
    
    private func isFlower(_ identifier: String) -> Bool {
        let keywords = ["flower", "rose", "daisy", "tulip", "bloom", "blossom", "petal", "bouquet"]
        return keywords.contains(where: identifier.contains)
    }
    
    private func isPlant(_ identifier: String) -> Bool {
        let keywords = ["plant", "leaf", "foliage", "fern", "succulent", "vegetation", "botanical", "garden"]
        return keywords.contains(where: identifier.contains)
    }
    
    private func isSunset(_ identifier: String) -> Bool {
        let keywords = ["sunset", "sunrise", "dusk", "dawn", "twilight", "golden hour", "sky"]
        return keywords.contains(where: identifier.contains)
    }
    
    // New category helpers for Cooking
    private func isCooking(_ identifier: String) -> Bool {
        let keywords = ["cooking", "kitchen", "chef", "cook", "baking", "oven", "stove", "pan", "pot", "spatula", "utensil"]
        return keywords.contains(where: identifier.contains)
    }
    
    private func isRecipe(_ identifier: String) -> Bool {
        let keywords = ["recipe", "ingredient", "preparation", "cookbook", "instruction"]
        return keywords.contains(where: identifier.contains)
    }
    
    // New category helpers for Activities
    private func isExercise(_ identifier: String) -> Bool {
        let keywords = ["exercise", "workout", "gym", "fitness", "running", "jogging", "cycling", "yoga", "training", "athlete", "dumbbell", "treadmill"]
        return keywords.contains(where: identifier.contains)
    }
    
    private func isArt(_ identifier: String) -> Bool {
        let keywords = ["art", "painting", "drawing", "sketch", "canvas", "palette", "brush", "sculpture", "artistic"]
        return keywords.contains(where: identifier.contains)
    }
    
    private func isReading(_ identifier: String) -> Bool {
        let keywords = ["reading", "library", "bookshelf", "literary", "text", "page"]
        return keywords.contains(where: identifier.contains)
    }

    private func isSiteOfInterest(_ identifier: String) -> Bool {
        let keywords = ["landmark", "monument", "museum", "temple", "church", "cathedral", "historic"]
        return keywords.contains(where: identifier.contains)
    }
}
