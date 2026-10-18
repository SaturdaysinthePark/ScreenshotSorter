import Testing
@testable import ScreenshotSorter

struct EntityExtractorTests {

    @Test func extractsLinksPhonesAndPrices() {
        let entities = EntityExtractor.extract(from: "Visit https://apple.com or call (415) 555-0132. Total $12.99", includeNames: false)
        #expect(entities.contains { $0.type == .url })
        #expect(entities.contains { $0.type == .phone })
        #expect(entities.contains { $0.type == .price && $0.value == "$12.99" })
    }

    @Test func extractsTrackingAndOneTimeCodes() {
        let entities = EntityExtractor.extract(from: "Tracking 1Z999AA10123456784\nYour verification code is 482913", includeNames: false)
        #expect(entities.contains { $0.type == .tracking })
        #expect(entities.contains { $0.type == .oneTimeCode && $0.value == "482913" })
    }

    @Test func ignoresBareClockTimes() {
        let entities = EntityExtractor.extract(from: "9:41", includeNames: false)
        #expect(!entities.contains { $0.type == .date })
    }
}
