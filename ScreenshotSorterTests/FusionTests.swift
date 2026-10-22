import Testing
@testable import ScreenshotSorter

struct FusionTests {

    @Test func strongSingleSourcePasses() {
        var input = FusionInput()
        input.vision = [.animals: 0.9]
        let result = SignalFusion.fuse(input)
        #expect(result.first?.category == .animals)
    }

    @Test func weakSingleSourceDoesNotPass() {
        var input = FusionInput()
        input.vision = [.food: 0.3]
        input.rules = [.receipts: 0.9]
        let categories = SignalFusion.fuse(input).map(\.category)
        #expect(categories.contains(.receipts))
        #expect(!categories.contains(.food))
    }

    @Test func agreeingSourcesReinforce() {
        var single = FusionInput()
        single.rules = [.food: 0.5]
        var both = single
        both.vision = [.food: 0.5]
        let singleScore = SignalFusion.fuse(single).first { $0.category == .food }?.score ?? 0
        let bothScore = SignalFusion.fuse(both).first { $0.category == .food }?.score ?? 0
        #expect(bothScore > singleScore)
        #expect(bothScore >= 0.5)
    }

    @Test func missingSourcesAreNeutral() {
        var input = FusionInput()
        input.vision = [.nature: 0.85]
        let withoutText = SignalFusion.fuse(input).first { $0.category == .nature }?.score ?? 0
        input.rules = [:]
        input.model = [:]
        let stillWithoutText = SignalFusion.fuse(input).first { $0.category == .nature }?.score ?? 0
        #expect(withoutText == stillWithoutText)
    }

    @Test func nothingConfidentFallsBackToOther() {
        let result = SignalFusion.fuse(FusionInput())
        #expect(result.map(\.category) == [.other])
    }

    @Test func capsCategoryCount() {
        var input = FusionInput()
        for category in [ScreenshotCategory.food, .drinks, .receipts, .events, .news, .music, .movies, .books] {
            input.rules[category] = 0.95
        }
        #expect(SignalFusion.fuse(input).count == FusionConfig.default.maxCategories)
    }

    @Test func userOverridesWin() {
        var input = FusionInput()
        input.vision = [.animals: 0.95]
        input.userOverrides = [.animals: false, .memes: true]
        let categories = SignalFusion.fuse(input).map(\.category)
        #expect(!categories.contains(.animals))
        #expect(categories.contains(.memes))
    }

    @Test func negativeNeighbourEvidenceSuppresses() {
        var input = FusionInput()
        input.rules = [.documents: 0.7]
        let before = SignalFusion.fuse(input).first { $0.category == .documents }?.score ?? 0
        input.userKNN = [.documents: -1]
        let after = SignalFusion.fuse(input).first { $0.category == .documents }?.score ?? 0
        #expect(after < before)
    }

    @Test func qrCodesAndTicketBarcodes() {
        var input = FusionInput()
        input.barcodes = [BarcodeInfo(payload: "https://x.y", symbology: "VNBarcodeSymbologyQR")]
        #expect(SignalFusion.fuse(input).contains { $0.category == .codes })

        var ticket = FusionInput()
        ticket.barcodes = [BarcodeInfo(payload: nil, symbology: "VNBarcodeSymbologyAztec")]
        ticket.rules = [.tickets: 0.4]
        let categories = SignalFusion.fuse(ticket).map(\.category)
        #expect(categories.contains(.tickets))
        #expect(!categories.contains(.codes))
    }
}
