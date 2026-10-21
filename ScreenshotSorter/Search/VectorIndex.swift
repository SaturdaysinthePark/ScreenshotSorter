import Accelerate
import Foundation

/// Exact cosine-similarity search over L2-normalized vectors held in one contiguous matrix.
/// 10k × 512 floats ≈ 20 MB and a query takes a few milliseconds with vDSP.
struct VectorMatrix: Sendable {
    private(set) var ids: [String] = []
    private(set) var dimension: Int = 0
    private var values: [Float] = []
    private var rowByID: [String: Int] = [:]

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    init() {}

    init(_ entries: [(String, [Float])]) {
        for (id, vector) in entries { upsert(id: id, vector: vector) }
    }

    mutating func upsert(id: String, vector: [Float]) {
        guard !vector.isEmpty else { return }
        if dimension == 0 { dimension = vector.count }
        guard vector.count == dimension else { return }
        if let row = rowByID[id] {
            values.replaceSubrange(row * dimension..<(row + 1) * dimension, with: vector)
        } else {
            rowByID[id] = ids.count
            ids.append(id)
            values.append(contentsOf: vector)
        }
    }

    mutating func remove(ids removed: Set<String>) {
        guard !removed.isEmpty, removed.contains(where: { rowByID[$0] != nil }) else { return }
        let kept = ids.enumerated().filter { !removed.contains($0.element) }
        var newValues: [Float] = []
        newValues.reserveCapacity(kept.count * dimension)
        var newIDs: [String] = []
        var newRows: [String: Int] = [:]
        for (row, id) in kept {
            newRows[id] = newIDs.count
            newIDs.append(id)
            newValues.append(contentsOf: values[row * dimension..<(row + 1) * dimension])
        }
        ids = newIDs
        values = newValues
        rowByID = newRows
    }

    func vector(for id: String) -> [Float]? {
        guard let row = rowByID[id] else { return nil }
        return Array(values[row * dimension..<(row + 1) * dimension])
    }

    /// Cosine similarity of `query` against every row.
    func similarities(to query: [Float]) -> [Float] {
        guard dimension > 0, query.count == dimension, !ids.isEmpty else { return [] }
        var result = [Float](repeating: 0, count: ids.count)
        values.withUnsafeBufferPointer { matrix in
            query.withUnsafeBufferPointer { vector in
                result.withUnsafeMutableBufferPointer { output in
                    // (rows × dim) · (dim × 1) = (rows × 1)
                    vDSP_mmul(matrix.baseAddress!, 1, vector.baseAddress!, 1, output.baseAddress!, 1,
                              vDSP_Length(ids.count), 1, vDSP_Length(dimension))
                }
            }
        }
        return result
    }

    /// Top-k most similar ids above `minimum`, best first.
    func nearest(to query: [Float], k: Int, minimum: Float = -1, excluding: Set<String> = []) -> [(id: String, similarity: Float)] {
        let scores = similarities(to: query)
        guard !scores.isEmpty, k > 0 else { return [] }
        // Top-k selection on row indices: sorting every row (and touching every id) cost
        // ~40 ms at 25k rows; this keeps a k-sized buffer, ascending, and only reads ids that qualify.
        var top: [(row: Int, score: Float)] = []
        top.reserveCapacity(k + 1)
        scores.withUnsafeBufferPointer { buffer in
            for row in 0..<buffer.count {
                let score = buffer[row]
                guard score >= minimum else { continue }
                if top.count == k, score <= top[0].score { continue }
                if !excluding.isEmpty, excluding.contains(ids[row]) { continue }
                let index = top.firstIndex { $0.score > score } ?? top.count
                top.insert((row, score), at: index)
                if top.count > k { top.removeFirst() }
            }
        }
        return top.reversed().map { (ids[$0.row], $0.score) }
    }
}

func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
    var result: Float = 0
    vDSP_dotpr(lhs, 1, rhs, 1, &result, vDSP_Length(lhs.count))
    return result
}

/// In-memory similarity index for text embeddings and image feature prints.
///
/// The combined vector `[√0.6·text, √0.4·visual]` makes a plain dot product equal
/// `0.6·cos_text + 0.4·cos_visual`, so one kNN query covers both signals.
actor VectorIndex {
    static let textWeight: Float = 0.6
    static let visualWeight: Float = 0.4

    private(set) var text = VectorMatrix()
    private(set) var visual = VectorMatrix()

    func load(text textEntries: [(String, [Float])], visual visualEntries: [(String, [Float])]) {
        text = VectorMatrix(textEntries)
        visual = VectorMatrix(visualEntries)
    }

    func upsert(id: String, text textVector: [Float]?, visual visualVector: [Float]?) {
        if let textVector { text.upsert(id: id, vector: textVector) }
        if let visualVector { visual.upsert(id: id, vector: visualVector) }
    }

    func remove(ids: Set<String>) {
        text.remove(ids: ids)
        visual.remove(ids: ids)
    }

    func textNearest(to query: [Float], k: Int, minimum: Float) -> [(id: String, similarity: Float)] {
        text.nearest(to: query, k: k, minimum: minimum)
    }

    /// Blended similarity between `id` and all other items.
    func neighbours(of id: String, k: Int, minimum: Float, among candidates: Set<String>? = nil) -> [(id: String, similarity: Float)] {
        let textQuery = text.vector(for: id)
        let visualQuery = visual.vector(for: id)
        guard textQuery != nil || visualQuery != nil else { return [] }

        var blended: [String: Float] = [:]
        if let textQuery {
            let scores = text.similarities(to: textQuery)
            let weight: Float = visualQuery == nil ? 1 : VectorIndex.textWeight
            for (row, score) in scores.enumerated() { blended[text.ids[row], default: 0] += weight * score }
        }
        if let visualQuery {
            let scores = visual.similarities(to: visualQuery)
            let weight: Float = textQuery == nil ? 1 : VectorIndex.visualWeight
            for (row, score) in scores.enumerated() { blended[visual.ids[row], default: 0] += weight * score }
        }
        blended[id] = nil
        var results = blended
            .filter { $0.value >= minimum && (candidates?.contains($0.key) ?? true) }
            .map { (id: $0.key, similarity: $0.value) }
        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(k))
    }

    /// Combined vectors for clustering (ids with at least one signal).
    func combinedVectors(for ids: [String]) -> [(String, [Float])] {
        let textScale = VectorIndex.textWeight.squareRoot()
        let visualScale = VectorIndex.visualWeight.squareRoot()
        return ids.compactMap { id in
            let textVector = text.vector(for: id)
            let visualVector = visual.vector(for: id)
            if textVector == nil && visualVector == nil { return nil }
            let textPart = textVector?.map { $0 * textScale } ?? [Float](repeating: 0, count: text.dimension)
            let visualPart = visualVector?.map { $0 * visualScale } ?? [Float](repeating: 0, count: visual.dimension)
            var combined = textPart + visualPart
            let norm = sqrt(combined.reduce(0) { $0 + $1 * $1 })
            guard norm > 0 else { return nil }
            for index in combined.indices { combined[index] /= norm }
            return (id, combined)
        }
    }
}
