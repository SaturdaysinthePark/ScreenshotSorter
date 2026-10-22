import CoreGraphics
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

    @Test func aCityInACaptionIsNotAPlaceToOpen() {
        let post = [entity(.place, "Tokyo")]
        #expect(QuickAction.suggest(categories: [.tiktok, .flights], entities: post) == nil)
        #expect(QuickAction.details(categories: [.tiktok, .flights], entities: post, primary: nil).isEmpty)
        // A Maps card's name is
        let card = QuickAction.suggest(categories: [.places], entities: [], placeName: "Pocketbook Hudson")
        #expect(card?.title == Brand.Copy.Detail.openInMaps)
        #expect(PlaceCard.name(in: ["11:07", "Pocketbook Hudson", "4.3", "★（60）・Hotel", "• 2 hr 15 min", "Directions"])
            == "Pocketbook Hudson")
        #expect(PlaceCard.name(in: ["Day 6: Tokyo", "Teamlab Planets", "Sushiro"]) == nil)
    }

    @Test func bookingCodesAndNoiseRows() {
        #expect(QuickAction.bookingCodes(in: "JFK - GRU\nCONFIRMATION # |\nHLNTA5\nDELTA").map(\.value) == ["HLNTA5"])
        #expect(QuickAction.bookingCodes(in: "we have generated a new\nreservation code.\nDQBMTH\nThe code").map(\.value) == ["DQBMTH"])
        #expect(QuickAction.bookingCodes(in: "Your reservation was made by a partner. RESERVATION CONFIRMED").isEmpty)
        let pass = QuickAction.suggest(categories: [.flights], entities: [], text: "CONFIRMATION # |\nHLNTA5")
        #expect(pass?.kind == .copy("HLNTA5"))
        // Guitar tabs, countdowns and opening hours aren't phones or dates
        #expect(!QuickAction.looksLikePhone(entity(.phone, "0000000 000")))
        #expect(!QuickAction.looksLikePhone(entity(.phone, "22-21-22-21-17")))
        #expect(!QuickAction.isCalendarDate(entity(.date, "00:14:43")))
        #expect(!QuickAction.isCalendarDate(entity(.date, "12:00 PM - 2:30 PM")))
        #expect(QuickAction.isCalendarDate(entity(.date, "Apr 25 - 29")))
        // A clipped link isn't opened; a lone shop link becomes the button
        #expect(!QuickAction.isWorthOpening(entity(.url, "github.com/zilliztech/claude-")))
        #expect(!QuickAction.isWorthOpening(entity(.url, "instagram.com")))
        #expect(QuickAction.suggest(categories: [.instagram, .art], entities: [entity(.url, "ravizupa.com")])?.title
            == Brand.Copy.Detail.openSite("ravizupa.com"))
        #expect(PlaceCard.taggedVenue(in: ["KOFFEE MAMEYA Kakeru - Koto City", "1,329 people posted about this place"])
            == "KOFFEE MAMEYA Kakeru, Koto City")
        #expect(PlaceCard.taggedVenue(in: ["Manhattan", "350.2K people posted about this place"]) == nil)
    }

    @Test func titlesSkipChromeAndFragments() {
        func line(_ text: String, _ y: Double, height: Double = 0.02) -> OCRLine {
            OCRLine(text: text, confidence: 1, box: CGRect(x: 0.05, y: y, width: 0.6, height: height), zone: .body)
        }
        let post = [line("Following Shop For You", 0.06, height: 0.03), line("Day 6: Tokyo", 0.3, height: 0.05),
                    line("Teamlab Planets", 0.4)]
        #expect(ScreenshotTitle.headline(post) == "Day 6: Tokyo")
        #expect(ScreenshotTitle.headline([line("Your confirmation ID is", 0.2, height: 0.05), line("Brooklyn Botanic Garden", 0.3)])
            == "Brooklyn Botanic Garden")
        let features = TestSupport.features(lines: [("Cartier London Lozenge", .body)])
        #expect(ScreenshotTitle.choose(model: "Instagram", features: features, app: "Instagram") == "Cartier London Lozenge")
        #expect(ScreenshotTitle.choose(model: "Koffee Mameya Kakeru", features: features, app: "TikTok") == "Koffee Mameya Kakeru")
    }

    @Test func postsThatSpellOutAVenueOpenItInMaps() {
        func line(_ text: String, _ y: Double, height: Double = 0.02) -> OCRLine {
            OCRLine(text: text, confidence: 1, box: CGRect(x: 0.05, y: y, width: 0.6, height: height), zone: .body)
        }
        // A venue tag with its area, and a caption naming a venue with its street address
        let tagged = [line("Georgie's Cafe & Bar • New York", 0.5), line("Discover more", 0.52)]
        #expect(PlaceCard.mapsQuery(lines: tagged, categories: [.tiktok]) == "Georgie's Cafe & Bar, New York")
        let caption = [line("The cutest little cafe", 0.5), line("Nuar - 48 W 27th St", 0.6)]
        #expect(PlaceCard.mapsQuery(lines: caption, categories: [.tiktok, .drinks]) == "Nuar, 48 W 27th St")
        // Big overlay text is a dish, a product or a list as often as a venue: no guess
        let overlay = [line("udon shin", 0.3, height: 0.05), line("• Photo", 0.6), line("Tokyo", 0.62),
                       line("478.0K people posted about this place", 0.64)]
        #expect(PlaceCard.mapsQuery(lines: overlay, categories: [.tiktok, .food]) == nil)
        // A Maps card's rating line still wins over the tabs below it; scrolled down, the tabs give the name
        #expect(PlaceCard.name(in: ["Pocketbook Hudson", "4.3", "Directions", "Apr 25 - 29", "Overview", "Prices"])
            == "Pocketbook Hudson")
        #expect(PlaceCard.name(in: ["Embajada de", "OSSO San Isidro", "Overview", "Menu", "Reviews"]) == "OSSO San Isidro")
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
