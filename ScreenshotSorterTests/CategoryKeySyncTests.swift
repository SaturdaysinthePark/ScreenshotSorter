import Testing
@testable import ScreenshotSorter

struct CategoryKeySyncTests {
    /// The language model's vocabulary must mirror the app's categories exactly.
    @Test func languageModelKeysMatchCategories() {
        let modelKeys = Set(CategoryKey.allCases.map { String(describing: $0) })
        let appKeys = Set(ScreenshotCategory.assignable.map(\.key))
        #expect(modelKeys == appKeys)
        for key in CategoryKey.allCases {
            #expect(key.category != nil)
        }
    }
}
