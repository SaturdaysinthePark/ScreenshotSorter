import Testing
@testable import ScreenshotSorter

struct TextNormalizerTests {

    @Test func wholeWordMatchingAvoidsSubstringFalsePositives() {
        let text = TextNormalizer.normalize(text: "Location Services\nEdit profile\nPassword\nAdd card")
        #expect(!text.contains("cat"))
        #expect(!text.contains("file"))
        #expect(!text.contains("word"))
        #expect(!text.contains("car"))
        #expect(text.contains("location"))
        #expect(text.contains("profile"))
    }

    @Test func phrasesMatchConsecutiveTokens() {
        let text = TextNormalizer.normalize(text: "Liked by sarah and 1,204 others")
        #expect(text.contains("liked by"))
        #expect(!text.contains("by liked"))
    }

    @Test func caseAndDiacriticsAreFolded() {
        let text = TextNormalizer.normalize(text: "SAUTÉ the onions")
        #expect(text.contains("saute"))
    }

    @Test func pluralsMatchViaStemming() {
        let text = TextNormalizer.normalize(text: "Fresh strawberries and sneakers")
        #expect(text.contains("strawberry"))
        #expect(text.contains("sneaker"))
    }

    @Test func zonesAreTrackedSeparately() {
        let lines = [
            OCRLine(text: "Chats", confidence: 1, box: .zero, zone: .topBar),
            OCRLine(text: "Updates Calls", confidence: 1, box: .zero, zone: .bottomBar)
        ]
        let text = TextNormalizer.normalize(lines: lines)
        #expect(text.contains("calls", in: .bottomBar))
        #expect(!text.contains("calls", in: .topBar))
        #expect(text.contains("chats", in: .topBar))
    }

    @Test func structuralCounts() {
        let text = TextNormalizer.normalize(text: "Latte $5.50\nTotal $10.62\n@nasa and @spacex\nr/swift\nMeet at 7:30 PM")
        #expect(text.priceCount == 2)
        #expect(text.handleCount == 2)
        #expect(text.subredditCount == 1)
        #expect(text.timeCount == 1)
    }

    @Test func statusBarTimeIsIgnored() {
        let lines = [OCRLine(text: "9:41", confidence: 1, box: .zero, zone: .statusBar)]
        #expect(TextNormalizer.normalize(lines: lines).timeCount == 0)
    }

    @Test func zoneFromMidY() {
        #expect(ScreenZone.zone(forMidY: 0.02) == .statusBar)
        #expect(ScreenZone.zone(forMidY: 0.1) == .topBar)
        #expect(ScreenZone.zone(forMidY: 0.5) == .body)
        #expect(ScreenZone.zone(forMidY: 0.95) == .bottomBar)
    }
}
