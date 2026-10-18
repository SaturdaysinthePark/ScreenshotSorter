import Foundation
import Testing
@testable import ScreenshotSorter

struct SearchAndLearningTests {

    @Test func editDistance() {
        #expect(SearchService.editDistance("recipt", "receipt", limit: 2) == 1)
        #expect(SearchService.editDistance("kitten", "sitting", limit: 3) == 3)
        #expect(SearchService.editDistance("abc", "xyz123", limit: 1) == 2)
    }

    @Test func vectorMatrixNearest() {
        let matrix = VectorMatrix([("a", [1, 0]), ("b", [0, 1]), ("c", [0.8, 0.6])])
        let nearest = matrix.nearest(to: [1, 0], k: 2)
        #expect(nearest.map(\.id) == ["a", "c"])
        var mutable = matrix
        mutable.remove(ids: ["a"])
        #expect(mutable.nearest(to: [1, 0], k: 1).first?.id == "c")
    }

    @Test func singleCorrectionDoesNotPropagate() {
        let neighbours: [(id: String, similarity: Float)] = [("n1", 0.9)]
        let overrides: [String: [ScreenshotCategory: Bool]] = ["n1": [.receipts: true]]
        #expect(UserFeedbackLearner.propagate(neighbours: neighbours, overrides: overrides).isEmpty)
    }

    @Test func agreeingCorrectionsPropagate() {
        let neighbours: [(id: String, similarity: Float)] = [("n1", 0.9), ("n2", 0.85), ("n3", 0.8)]
        let overrides: [String: [ScreenshotCategory: Bool]] = [
            "n1": [.receipts: true, .documents: false],
            "n2": [.receipts: true, .documents: false],
            "n3": [.receipts: true]
        ]
        let result = UserFeedbackLearner.propagate(neighbours: neighbours, overrides: overrides)
        #expect((result[.receipts] ?? 0) > 0.5)
        #expect((result[.documents] ?? 0) < 0)
    }

    @Test func clustererRequiresMinimumSize() {
        // 7 near-identical vectors: below the 8-member minimum → no suggestion
        let small = (0..<7).map { ("s\($0)", [Float(1), Float($0) * 0.001]) }
        #expect(Clusterer.cluster(small).isEmpty)
    }

    @Test func clustererFindsCohesiveGroup() {
        var entries: [(String, [Float])] = []
        for index in 0..<10 {
            let jitter = Float(index) * 0.002
            entries.append(("a\(index)", normalized([1, jitter, 0])))
        }
        for index in 0..<10 {
            let jitter = Float(index) * 0.002
            entries.append(("b\(index)", normalized([0, 1, jitter])))
        }
        let clusters = Clusterer.cluster(entries)
        #expect(clusters.count == 2)
        #expect(clusters.allSatisfy { $0.memberIDs.count >= Clusterer.Parameters().minimumSize })
    }

    @Test func sameConceptDetection() {
        #expect(SmartCollectionEngine.isSameConcept("Receipts", "Receipts"))
        #expect(!SmartCollectionEngine.isSameConcept("Japan Trip", "Receipts"))
    }

    private func normalized(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return vector.map { $0 / norm }
    }
}
