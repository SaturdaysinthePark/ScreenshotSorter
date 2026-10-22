import Foundation
import Testing
@testable import ScreenshotSorter

struct QuickActionTests {
    private func entity(_ type: EntityType, _ value: String, _ normalized: String? = nil) -> ExtractedEntity {
        ExtractedEntity(type: type, value: value, normalized: normalized)
    }

    @Test func oneTimeCodeWinsEverywhere() {
        let action = QuickAction.suggest(categories: [.notifications], entities: [entity(.url, "bank.com"), entity(.oneTimeCode, "335543")])
        #expect(action?.kind == .copy("335543"))
    }

    @Test func placeCardOpensMaps() throws {
        let action = try #require(QuickAction.suggest(categories: [.places, .food], entities: [entity(.address, "811 W 10th Ave")]))
        guard case .open(let url) = action.kind else { Issue.record("expected a URL"); return }
        #expect(url.host() == "maps.apple.com")
    }

    @Test func productPageOpensItsSite() {
        let action = QuickAction.suggest(categories: [.stores, .clothes], entities: [entity(.url, "www.aimeleondore.com")])
        #expect(action?.title == Brand.Copy.Detail.openSite("aimeleondore.com"))
    }

    @Test func noActionWithoutSomethingToActOn() {
        // A link in a chat or a meme isn't what the screenshot is for
        #expect(QuickAction.suggest(categories: [.memes], entities: [entity(.url, "example.com")]) == nil)
        #expect(QuickAction.suggest(categories: [.places], entities: []) == nil)
    }
}
