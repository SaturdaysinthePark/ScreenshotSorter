import Testing
@testable import ScreenshotSorter

struct CategoryKeySyncTests {
    /// The model's topics are every category except the apps (those come from the app detector), each once.
    @Test func languageModelTopicsCoverTheNonAppCategories() {
        let mapped = TopicKey.allCases.compactMap(\.category)
        #expect(mapped.count == TopicKey.allCases.count)
        #expect(Set(mapped).count == mapped.count, "two topics map to one category")
        let expected = Set(ScreenshotCategory.assignable.filter { $0.kind != .app })
        #expect(Set(mapped) == expected)
    }

    /// Stored labels and corrections written before the October 2026 merge still resolve.
    @Test func mergedKeysResolve() {
        #expect(ScreenshotCategory(key: "beaches") == .nature)
        #expect(ScreenshotCategory(key: "whatsapp") == .messages)
        #expect(ScreenshotCategory(persisted: "reading") == .books)
        #expect(ScreenshotCategory(persisted: "Stores") == .stores)
        for (key, category) in ScreenshotCategory.mergedKeys {
            #expect(ScreenshotCategory(key: key) == category)
        }
    }
}
