import Foundation
import Testing
@testable import ScreenshotSorter

struct QueryParserTests {
    /// Wednesday 15 October 2025, 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_760_529_600)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func categoryAndRelativeDate() {
        let query = QueryParser.parse("receipts from last week", now: now, calendar: calendar)
        #expect(query.categories == [.receipts])
        #expect(query.terms.isEmpty)
        let range = try? #require(query.dateRange)
        #expect(range?.end ?? now <= now)
        #expect((range?.duration ?? 0) > 6 * 86_400)
    }

    @Test func freeTextWithApp() {
        let query = QueryParser.parse("nike sneakers on instagram", now: now, calendar: calendar)
        #expect(query.apps.contains("instagram"))
        #expect(query.terms.contains("nike"))
        #expect(query.categories.contains(.shoes))
    }

    @Test func entityWords() {
        let query = QueryParser.parse("tweets with links", now: now, calendar: calendar)
        #expect(query.entityTypes == [.url])
        #expect(query.categories == [.twitter])
    }

    @Test func quotedPhrases() {
        let query = QueryParser.parse("\"order number\" amazon", now: now, calendar: calendar)
        #expect(query.phrases == ["order number"])
    }

    @Test func monthNames() {
        let query = QueryParser.parse("flights in march", now: now, calendar: calendar)
        let start = query.dateRange.map { calendar.component(.month, from: $0.start) }
        #expect(start == 3)
        #expect(query.categories == [.flights])
    }

    @Test func mayIsNotAlwaysAMonth() {
        let query = QueryParser.parse("you may like this", now: now, calendar: calendar)
        #expect(query.dateRange == nil)
    }

    @Test func todayAndYesterday() {
        #expect(QueryParser.parse("today", now: now, calendar: calendar).dateRange != nil)
        let yesterday = QueryParser.parse("memes yesterday", now: now, calendar: calendar)
        #expect(yesterday.dateRange != nil)
        #expect(yesterday.categories == [.memes])
    }

    @Test func stopWordsAreDropped() {
        let query = QueryParser.parse("show me the wifi password", now: now, calendar: calendar)
        #expect(query.terms == ["wifi", "password"])
    }
}
