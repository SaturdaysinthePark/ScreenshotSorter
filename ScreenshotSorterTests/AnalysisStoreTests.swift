import Foundation
import Testing
@testable import ScreenshotSorter

struct AnalysisStoreTests {

    private func makeStore() throws -> AnalysisStore {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString).sqlite").path
        return try AnalysisStore(path: path)
    }

    private func record(_ id: String, text: String, categories: [ScreenshotCategory], tags: [String] = []) -> AnalysisRecord {
        var record = AnalysisRecord(id: id, createdAt: Date())
        record.tier = .deep
        record.visionVersion = PipelineVersion.vision
        record.rulesVersion = PipelineVersion.rules
        record.ocrText = text
        record.title = "Title \(id)"
        record.categories = categories.map { ScoredCategory(category: $0, score: 0.9, sources: .ocrRules) }
        record.tags = tags.map { ScreenshotTag(value: $0, score: 0.8, sources: .foundationModel) }
        record.entities = [ExtractedEntity(type: .url, value: "apple.com", normalized: "https://apple.com")]
        record.embedding = [0.6, 0.8]
        record.embeddingModel = "test"
        return record
    }

    @Test func roundTripsRecords() async throws {
        let store = try makeStore()
        await store.upsert([record("a", text: "Subtotal 9.75 Total 10.62", categories: [.receipts], tags: ["coffee"])])
        let loaded = try #require(await store.record(id: "a"))
        #expect(loaded.ocrText == "Subtotal 9.75 Total 10.62")
        #expect(loaded.categories.map(\.category) == [.receipts])
        #expect(loaded.tags.map(\.value) == ["coffee"])
        #expect(loaded.embedding == [0.6, 0.8])
        #expect(await store.entityTypeMap()["a"] == [.url])
        let summaries = await store.loadSummaries()
        #expect(summaries.first?.tags == ["coffee"])
    }

    @Test func upsertReplacesWithoutDuplicatingSearchRows() async throws {
        let store = try makeStore()
        guard store.isFTSAvailable else { return }
        await store.upsert([record("a", text: "banana bread recipe", categories: [.recipes])])
        await store.upsert([record("a", text: "banana bread recipe updated", categories: [.recipes])])
        let hits = await store.ftsSearch(match: "\"banana\"*", limit: 10)
        #expect(hits.map(\.id) == ["a"])
    }

    @Test func fullTextSearchRanksAndSnippets() async throws {
        let store = try makeStore()
        guard store.isFTSAvailable else { return }
        await store.upsert([
            record("wifi", text: "Network: HomeNet password: hunter2", categories: [.notes]),
            record("other", text: "Lunch menu", categories: [.food])
        ])
        let hits = await store.ftsSearch(match: "\"passw\"*", limit: 10)
        #expect(hits.first?.id == "wifi")
        #expect(hits.first?.snippet?.contains("[") == true)
    }

    @Test func deleteRemovesEverything() async throws {
        let store = try makeStore()
        await store.upsert([record("a", text: "hello world", categories: [.notes])])
        await store.delete(ids: ["a"])
        #expect(await store.record(id: "a") == nil)
        #expect(await store.embeddings(model: "test").isEmpty)
        if store.isFTSAvailable {
            #expect(await store.ftsSearch(match: "\"hello\"*", limit: 10).isEmpty)
        }
    }

    @Test func categoriesEncodeCompactly() {
        let categories = [ScoredCategory(category: .movies, score: 0.81234, sources: [.ocrRules, .visionClassifier])]
        let encoded = AnalysisStore.encodeCategories(categories)
        let decoded = AnalysisStore.decodeCategories(encoded)
        #expect(decoded.first?.category == .movies)
        #expect(abs((decoded.first?.score ?? 0) - 0.812) < 0.001)
        #expect(decoded.first?.sources == [.ocrRules, .visionClassifier])
    }

    @Test func correctionsPersist() async throws {
        let store = try makeStore()
        let correction = Correction(assetID: "a", kind: .category, value: "receipts", action: .add, groupID: "g", createdAt: Date())
        await store.addCorrections([correction])
        #expect(await store.allCorrections().count == 1)
        await store.removeCorrections(groupID: "g")
        #expect(await store.allCorrections().isEmpty)
    }
}
