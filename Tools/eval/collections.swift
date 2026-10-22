import Foundation
import SQLite3

// `--db <analysis.sqlite> --collections "books,coffee,girl"`: runs the app's own search over a copy of a real
// library, both as a New Collection fills itself (`.whatItShows`) and as plain search (`.everything`), and writes
// the top results per query to collections.json for judging (Tools/eval/judge). The copy is opened, not the file
// you pass, so nothing writes to it.

struct CollectionQueryResult: Codable {
    var query: String
    var whatItShows: [String]
    var everything: [String]
    var whatItShowsCount: Int
    var everythingCount: Int
}

func runCollections(database: String, queries: [String], out: URL) async throws {
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("collections-\(UUID().uuidString).sqlite")
    try FileManager.default.copyItem(atPath: database, toPath: copy.path)
    for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: database + suffix) {
        try? FileManager.default.copyItem(atPath: database + suffix, toPath: copy.path + suffix)
    }
    let store = try AnalysisStore(path: copy.path)
    let vectors = VectorIndex()
    await vectors.load(text: await store.embeddings(model: TextEmbedder.modelID), visual: await store.featurePrints())
    let search = SearchService(store: store, vectors: vectors)

    var context = SearchContext()
    var db: OpaquePointer?
    guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { fatalError("cannot open copy") }
    var statement: OpaquePointer?
    sqlite3_prepare_v2(db, "SELECT id, created_at, categories, app FROM assets", -1, &statement, nil)
    while sqlite3_step(statement) == SQLITE_ROW {
        guard let raw = sqlite3_column_text(statement, 0) else { continue }
        let id = String(cString: raw)
        context.dates[id] = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1))
        if let categories = sqlite3_column_text(statement, 2) {
            context.categories[id] = Set(String(cString: categories).split(separator: ",")
                .compactMap { ScreenshotCategory(key: String($0.split(separator: ":").first ?? "")) })
        }
        if let app = sqlite3_column_text(statement, 3) { context.apps[id] = String(cString: app).lowercased() }
    }
    sqlite3_finalize(statement)
    sqlite3_close(db)

    var results: [CollectionQueryResult] = []
    for query in queries {
        let parsed = QueryParser.parse(query)
        let shows = await search.search(parsed, context: context, scope: .whatItShows)
        let everything = await search.search(parsed, context: context, scope: .everything)
        results.append(CollectionQueryResult(query: query, whatItShows: Array(shows.prefix(24).map(\.id)),
                                             everything: Array(everything.prefix(24).map(\.id)),
                                             whatItShowsCount: shows.count, everythingCount: everything.count))
        print(String(format: "%-18@ collection %4d · search %4d", query as NSString, shows.count, everything.count))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(results).write(to: out)
    print("collections: \(out.path)")
}
