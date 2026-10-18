import Foundation

/// Learns from the user's manual corrections, entirely on device.
///
/// 1. Direct corrections always override the classifier for that screenshot.
/// 2. Neighbour propagation: similar screenshots (text + visual similarity) are nudged toward
///    what the user chose — but only when at least two corrected neighbours agree, so a single
///    correction never spreads.
/// 3. Per-category calibration: categories the user keeps removing are gradually suppressed,
///    ones they keep adding are boosted.
actor UserFeedbackLearner {
    static let neighbourCount = 15
    static let neighbourMinimumSimilarity: Float = 0.72
    static let minimumAgreeingNeighbours = 2
    static let calibrationRate = 0.04
    static let maxBias = 0.25

    private let store: AnalysisStore

    /// asset → category → added (true) / removed (false). Latest correction wins.
    private var categoryOverrides: [String: [ScreenshotCategory: Bool]] = [:]
    private var addedTags: [String: [String]] = [:]
    private var removedTags: [String: Set<String>] = [:]
    private var bias: [ScreenshotCategory: Double] = [:]
    private var biasCounts: [ScreenshotCategory: Int] = [:]
    private var loaded = false

    init(store: AnalysisStore) {
        self.store = store
    }

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        for correction in await store.allCorrections() {
            apply(correction)
        }
        for (category, value) in await store.learnedBias() {
            bias[category] = value.bias
            biasCounts[category] = value.count
        }
    }

    private func apply(_ correction: Correction) {
        switch correction.kind {
        case .category:
            guard let category = ScreenshotCategory(persisted: correction.value) else { return }
            categoryOverrides[correction.assetID, default: [:]][category] = correction.action == .add
        case .tag:
            let tag = ScreenshotClassifier.normalizeTag(correction.value)
            if correction.action == .add {
                removedTags[correction.assetID]?.remove(tag)
                if !(addedTags[correction.assetID]?.contains(tag) ?? false) {
                    addedTags[correction.assetID, default: []].append(tag)
                }
            } else {
                addedTags[correction.assetID]?.removeAll { $0 == tag }
                removedTags[correction.assetID, default: []].insert(tag)
            }
        case .smartMember:
            break
        }
    }

    var correctedIDs: Set<String> { Set(categoryOverrides.keys) }

    /// Everything the learner knows that's relevant to `id`.
    func signals(for id: String, vectors: VectorIndex) async -> UserSignals {
        await loadIfNeeded()
        var signals = UserSignals()
        signals.overrides = categoryOverrides[id] ?? [:]
        signals.bias = bias
        signals.addedTags = addedTags[id] ?? []
        signals.removedTags = removedTags[id] ?? []

        let corrected = correctedIDs.subtracting([id])
        if !corrected.isEmpty {
            let neighbours = await vectors.neighbours(
                of: id,
                k: UserFeedbackLearner.neighbourCount,
                minimum: UserFeedbackLearner.neighbourMinimumSimilarity,
                among: corrected
            )
            signals.knn = UserFeedbackLearner.propagate(neighbours: neighbours, overrides: categoryOverrides)
        }
        return signals
    }

    /// Similarity-weighted vote of corrected neighbours, per category, in −1…1.
    static func propagate(neighbours: [(id: String, similarity: Float)],
                          overrides: [String: [ScreenshotCategory: Bool]]) -> [ScreenshotCategory: Double] {
        var weighted: [ScreenshotCategory: Double] = [:]
        var totalWeight: [ScreenshotCategory: Double] = [:]
        var positive: [ScreenshotCategory: Int] = [:]
        var negative: [ScreenshotCategory: Int] = [:]

        for neighbour in neighbours {
            guard let votes = overrides[neighbour.id] else { continue }
            let weight = pow(Double(neighbour.similarity), 4)
            for (category, added) in votes {
                weighted[category, default: 0] += weight * (added ? 1 : -1)
                totalWeight[category, default: 0] += weight
                if added { positive[category, default: 0] += 1 } else { negative[category, default: 0] += 1 }
            }
        }

        var result: [ScreenshotCategory: Double] = [:]
        for (category, sum) in weighted {
            guard let total = totalWeight[category], total > 0 else { continue }
            let agreeing = sum >= 0 ? positive[category, default: 0] : negative[category, default: 0]
            guard agreeing >= minimumAgreeingNeighbours else { continue }
            let confidence = min(1, Double(agreeing) / 4)
            result[category] = (sum / total) * confidence
        }
        return result
    }

    /// Persist corrections and update calibration.
    /// - Parameter previousScores: fused score of each corrected category before the correction
    func record(_ corrections: [Correction], previousScores: [String: [ScreenshotCategory: Double]]) async {
        await loadIfNeeded()
        await store.addCorrections(corrections)
        for correction in corrections {
            apply(correction)
            guard correction.kind == .category,
                  let category = ScreenshotCategory(persisted: correction.value) else { continue }
            let target: Double = correction.action == .add ? 1 : 0
            let before = previousScores[correction.assetID]?[category] ?? (correction.action == .add ? 0 : 1)
            let updated = bias[category, default: 0] + UserFeedbackLearner.calibrationRate * (target - before)
            bias[category] = min(max(updated, -UserFeedbackLearner.maxBias), UserFeedbackLearner.maxBias)
            biasCounts[category, default: 0] += 1
            await store.setLearnedBias(category, bias: bias[category] ?? 0, count: biasCounts[category] ?? 0)
        }
    }

    /// Undo a grouped correction (e.g. a "move") — rebuilds state from the store.
    func undo(groupID: String) async {
        await store.removeCorrections(groupID: groupID)
        categoryOverrides.removeAll()
        addedTags.removeAll()
        removedTags.removeAll()
        loaded = false
        bias.removeAll()
        biasCounts.removeAll()
        await loadIfNeeded()
    }

    /// Screenshots similar to `id` that should be re-scored after it was corrected.
    func affectedNeighbours(of id: String, vectors: VectorIndex) async -> [String] {
        await vectors.neighbours(of: id, k: 50, minimum: UserFeedbackLearner.neighbourMinimumSimilarity).map(\.id)
    }
}
