import Foundation

/// What the engine needs to know about the library.
struct ClusterContext: Sendable {
    /// Deep-analyzed screenshots eligible for clustering (newest first)
    var candidateIDs: [String] = []
    var tags: [String: [String]] = [:]
    var topCategory: [String: ScreenshotCategory] = [:]
    var apps: [String: String] = [:]
    var titles: [String: String] = [:]
    /// All library ids (for tag document frequency)
    var libraryCount: Int = 0
    var tagDocumentFrequency: [String: Int] = [:]
}

/// Suggests AI-named collections from clusters of similar screenshots — with guard rails:
/// - only clusters of ≥ 8 cohesive, distinct screenshots
/// - at most 3 suggestions visible at a time
/// - nothing reaches the home screen until the user taps Keep
/// - dismissed suggestions never come back
actor SmartCollectionEngine {
    static let minimumMembers = 8
    static let maxVisibleSuggestions = 3
    static let maxCandidates = 2_000
    static let dismissedSimilarity: Float = 0.9
    static let joinSimilarity: Float = 0.75
    static let tagAgreement = 0.5
    static let categoryOverlap = 0.7

    static let allowedSymbols = [
        "sparkles", "airplane", "house.fill", "cart.fill", "fork.knife", "tshirt.fill", "heart.fill", "book.fill",
        "music.note", "film.fill", "gamecontroller.fill", "briefcase.fill", "graduationcap.fill", "dumbbell.fill",
        "pawprint.fill", "leaf.fill", "car.fill", "gift.fill", "calendar", "map.fill", "camera.fill",
        "paintpalette.fill", "star.fill", "bag.fill", "laptopcomputer", "building.2.fill", "ticket.fill",
        "person.2.fill", "globe", "lightbulb.fill", "sofa.fill", "cup.and.saucer.fill", "figure.run", "beach.umbrella.fill"
    ]
    /// Never name a collection after sensitive topics
    static let blockedNameFragments = ["nude", "sex", "diagnos", "pregnan", "religio", "politic", "medical", "therapy"]

    private let store: AnalysisStore
    private let vectors: VectorIndex

    init(store: AnalysisStore, vectors: VectorIndex) {
        self.store = store
        self.vectors = vectors
    }

    func all() async -> [SmartCollection] {
        await store.smartCollections()
    }

    /// Re-cluster and add new suggestions (keeps at most `maxVisibleSuggestions` pending).
    func refresh(context: ClusterContext) async -> [SmartCollection] {
        var collections = await store.smartCollections()
        let pending = collections.filter { $0.status == .suggested }
        guard pending.count < SmartCollectionEngine.maxVisibleSuggestions else { return collections }

        let claimed = Set(collections.filter { $0.status == .kept }.flatMap(\.memberIDs))
        let candidates = context.candidateIDs.filter { !claimed.contains($0) }.prefix(SmartCollectionEngine.maxCandidates)
        let entries = await vectors.combinedVectors(for: Array(candidates))
        let clusters = Clusterer.cluster(entries)

        let knownSignatures = collections.map(\.centroid)
        let ranked = clusters.sorted { $0.cohesion * log2(Double($0.memberIDs.count)) > $1.cohesion * log2(Double($1.memberIDs.count)) }

        var slots = SmartCollectionEngine.maxVisibleSuggestions - pending.count
        for cluster in ranked where slots > 0 {
            // Same as something already suggested, kept or dismissed?
            if knownSignatures.contains(where: { $0.count == cluster.centroid.count && cosine($0, cluster.centroid) >= SmartCollectionEngine.dismissedSimilarity }) {
                continue
            }
            let topTags = distinctiveTags(for: cluster.memberIDs, context: context)
            let withTopTag = cluster.memberIDs.filter { id in
                !Set(context.tags[id] ?? []).isDisjoint(with: topTags.prefix(3))
            }.count
            let agreement = Double(withTopTag) / Double(cluster.memberIDs.count)
            guard agreement >= SmartCollectionEngine.tagAgreement || cluster.cohesion >= 0.85 else { continue }

            guard let naming = await name(cluster: cluster, topTags: topTags, context: context) else { continue }
            // Redundant with a curated category ("Receipts" cluster of receipts)?
            if let dominant = dominantCategory(cluster.memberIDs, context: context),
               dominant.share >= SmartCollectionEngine.categoryOverlap,
               SmartCollectionEngine.isSameConcept(naming.name, dominant.category.displayName) {
                continue
            }
            if collections.contains(where: { $0.name.caseInsensitiveCompare(naming.name) == .orderedSame }) { continue }

            let collection = SmartCollection(
                id: UUID().uuidString,
                name: naming.name,
                symbol: naming.symbol,
                status: .suggested,
                centroid: cluster.centroid,
                cohesion: cluster.cohesion,
                memberIDs: cluster.memberIDs,
                removedIDs: [],
                createdAt: Date(),
                decidedAt: nil
            )
            await store.saveSmartCollection(collection)
            collections.append(collection)
            slots -= 1
        }
        return collections
    }

    // MARK: - User decisions

    func keep(id: String, name: String? = nil) async -> [SmartCollection] {
        await update(id: id) {
            $0.status = .kept
            $0.decidedAt = Date()
            if let name, !name.isEmpty { $0.name = name }
        }
    }

    func dismiss(id: String) async -> [SmartCollection] {
        await update(id: id) {
            $0.status = .dismissed
            $0.decidedAt = Date()
            $0.memberIDs = []
        }
    }

    func rename(id: String, to name: String) async -> [SmartCollection] {
        await update(id: id) { $0.name = name }
    }

    func removeMember(_ assetID: String, from id: String) async -> [SmartCollection] {
        await update(id: id) {
            $0.memberIDs.removeAll { $0 == assetID }
            if !$0.removedIDs.contains(assetID) { $0.removedIDs.append(assetID) }
        }
    }

    func addMember(_ assetID: String, to id: String) async -> [SmartCollection] {
        await update(id: id) {
            $0.removedIDs.removeAll { $0 == assetID }
            if !$0.memberIDs.contains(assetID) { $0.memberIDs.append(assetID) }
        }
    }

    func delete(id: String) async -> [SmartCollection] {
        await store.deleteSmartCollection(id: id)
        return await store.smartCollections()
    }

    /// New screenshots join kept collections they clearly belong to.
    func absorb(newIDs: [String]) async -> [SmartCollection] {
        var collections = await store.smartCollections()
        for index in collections.indices where collections[index].status == .kept {
            var collection = collections[index]
            let members = Set(collection.memberIDs)
            let removed = Set(collection.removedIDs)
            var changed = false
            for (id, vector) in await vectors.combinedVectors(for: newIDs) where !members.contains(id) && !removed.contains(id) {
                guard vector.count == collection.centroid.count,
                      cosine(vector, collection.centroid) >= SmartCollectionEngine.joinSimilarity else { continue }
                let neighbours = await vectors.neighbours(of: id, k: 10, minimum: 0.6)
                let inside = neighbours.filter { members.contains($0.id) }.count
                if inside >= 5 {
                    collection.memberIDs.append(id)
                    changed = true
                }
            }
            if changed {
                collections[index] = collection
                await store.saveSmartCollection(collection)
            }
        }
        return collections
    }

    // MARK: - Helpers

    private func update(id: String, _ change: (inout SmartCollection) -> Void) async -> [SmartCollection] {
        var collections = await store.smartCollections()
        if let index = collections.firstIndex(where: { $0.id == id }) {
            change(&collections[index])
            await store.saveSmartCollection(collections[index])
        }
        return collections
    }

    /// Tags over-represented in the cluster relative to the library (TF-IDF).
    func distinctiveTags(for ids: [String], context: ClusterContext) -> [String] {
        var counts: [String: Int] = [:]
        for id in ids {
            for tag in Set(context.tags[id] ?? []) { counts[tag, default: 0] += 1 }
        }
        let total = Double(max(1, context.libraryCount))
        return counts
            .map { tag, count -> (String, Double) in
                let tf = Double(count) / Double(ids.count)
                let idf = log(total / Double(1 + (context.tagDocumentFrequency[tag] ?? count)))
                return (tag, tf * max(idf, 0.1))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map(\.0)
    }

    private func dominantCategory(_ ids: [String], context: ClusterContext) -> (category: ScreenshotCategory, share: Double)? {
        var counts: [ScreenshotCategory: Int] = [:]
        for id in ids {
            if let category = context.topCategory[id] { counts[category, default: 0] += 1 }
        }
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, Double(best.value) / Double(ids.count))
    }

    private func name(cluster: ClusterCandidate, topTags: [String], context: ClusterContext) async -> (name: String, symbol: String)? {
        let apps = Array(Set(cluster.memberIDs.compactMap { context.apps[$0] }))
        let titles = cluster.memberIDs.prefix(10).compactMap { context.titles[$0] }
        var naming = await FMClassifier.shared.nameCollection(
            tags: topTags, apps: apps, titles: titles, allowedSymbols: SmartCollectionEngine.allowedSymbols
        )
        if naming == nil, let first = topTags.first {
            let words = ([first] + topTags.dropFirst().prefix(1)).joined(separator: " & ")
            naming = (words.capitalized, "sparkles")
        }
        guard let result = naming, !result.name.isEmpty, result.name.count <= 32 else { return nil }
        let lowered = result.name.lowercased()
        guard !SmartCollectionEngine.blockedNameFragments.contains(where: { lowered.contains($0) }) else { return nil }
        return result
    }

    static func isSameConcept(_ name: String, _ categoryName: String) -> Bool {
        let nameTokens = Set(TextNormalizer.tokenize(name).map(TextNormalizer.stem))
        let categoryTokens = Set(TextNormalizer.tokenize(categoryName).map(TextNormalizer.stem))
        guard !nameTokens.isEmpty else { return true }
        return !nameTokens.isDisjoint(with: categoryTokens)
    }
}
