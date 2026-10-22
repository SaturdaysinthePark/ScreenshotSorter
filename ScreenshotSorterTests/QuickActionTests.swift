import Foundation
import Testing
@testable import ScreenshotSorter

struct QuickActionTests {
    private func entity(_ type: EntityType, _ value: String, _ normalized: String? = nil) -> ExtractedEntity {
        ExtractedEntity(type: type, value: value, normalized: normalized)
    }

    @Test func placeCardDetailsAreTheAddressNotItsHoursOrPrices() {
        // Old Westbury Gardens: "Closes 6 PM", "$22" tickets, the town name and its full address
        let entities = [entity(.date, "6 PM"), entity(.price, "$22"), entity(.place, "Old Westbury"),
                        entity(.address, "71 Old Westbury Rd, Old Westbury, NY 11568"), entity(.person, "John Phipps")]
        let primary = QuickAction.suggest(categories: [.places], entities: entities)
        let details = QuickAction.details(categories: [.places], entities: entities, primary: primary)
        // The address stays even though the button opens it: it's as often copied
        #expect(details.map(\.type) == [.address])
        // On a receipt the total matters, on an event its date
        let receipt = QuickAction.details(categories: [.receipts], entities: [entity(.price, "$2.99"), entity(.price, "$15.19"),
                                                                             entity(.phone, "182736455")], primary: nil)
        // The total, not the first line; a document number isn't a phone
        #expect(receipt.map(\.value) == ["$15.19"])
        #expect(QuickAction.looksLikePhone(entity(.phone, "(212) 555-0100")))
        #expect(QuickAction.looksLikePhone(entity(.phone, "+44 20 7946 0958")))
        #expect(QuickAction.details(categories: [.events], entities: [entity(.date, "Oct 9")], primary: nil).count == 1)
        // The button's own code isn't listed twice
        let code = [entity(.oneTimeCode, "335543"), entity(.url, "bank.com")]
        let codeAction = QuickAction.suggest(categories: [.notifications], entities: code)
        #expect(QuickAction.details(categories: [.notifications], entities: code, primary: codeAction).map(\.type) == [.url])
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
