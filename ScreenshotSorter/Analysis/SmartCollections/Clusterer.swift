import Foundation

struct ClusterCandidate: Sendable {
    let memberIDs: [String]
    let centroid: [Float]
    /// Mean similarity of members to the centroid
    let cohesion: Double
}

/// Density clustering on a mutual-kNN graph (DBSCAN-style), tuned to be conservative:
/// it is far better to suggest nothing than to suggest a junk collection.
enum Clusterer {
    struct Parameters: Sendable {
        var neighbours = 10
        var edgeSimilarity: Float = 0.78
        /// Core points need this many mutual neighbours (so a core + neighbours ≥ minimumSize)
        var coreNeighbours = 7
        var minimumSize = 8
        var minimumCohesion = 0.75
        /// Clusters whose centroids are more similar than this get merged
        var mergeSimilarity: Float = 0.9
    }

    static func cluster(_ entries: [(String, [Float])], parameters: Parameters = Parameters()) -> [ClusterCandidate] {
        let matrix = VectorMatrix(entries)
        let count = matrix.count
        guard count >= parameters.minimumSize else { return [] }

        // kNN lists above the edge threshold
        var neighbourSets: [Set<Int>] = Array(repeating: [], count: count)
        for row in 0..<count {
            guard let vector = matrix.vector(for: matrix.ids[row]) else { continue }
            let similarities = matrix.similarities(to: vector)
            var best: [(Int, Float)] = []
            for (other, similarity) in similarities.enumerated() where other != row && similarity >= parameters.edgeSimilarity {
                best.append((other, similarity))
            }
            best.sort { $0.1 > $1.1 }
            neighbourSets[row] = Set(best.prefix(parameters.neighbours).map(\.0))
        }

        // Mutual edges only
        var mutual: [[Int]] = Array(repeating: [], count: count)
        for row in 0..<count {
            mutual[row] = neighbourSets[row].filter { neighbourSets[$0].contains(row) }.sorted()
        }
        let isCore = mutual.map { $0.count >= parameters.coreNeighbours }

        // Connected components over core points, then attach border points
        var label = [Int](repeating: -1, count: count)
        var clusters: [[Int]] = []
        for seed in 0..<count where isCore[seed] && label[seed] == -1 {
            var component: [Int] = []
            var stack = [seed]
            label[seed] = clusters.count
            while let node = stack.popLast() {
                component.append(node)
                for next in mutual[node] where label[next] == -1 {
                    label[next] = clusters.count
                    // Only expand through core points; border points join but don't propagate
                    if isCore[next] { stack.append(next) } else { component.append(next) }
                }
            }
            clusters.append(component)
        }

        var candidates: [ClusterCandidate] = clusters.compactMap { rows in
            guard rows.count >= parameters.minimumSize else { return nil }
            return makeCandidate(rows: rows, matrix: matrix)
        }
        candidates = merge(candidates, matrix: matrix, threshold: parameters.mergeSimilarity)
        return candidates.filter { $0.memberIDs.count >= parameters.minimumSize && $0.cohesion >= parameters.minimumCohesion }
    }

    static func centroid(of vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors where vector.count == sum.count {
            for index in sum.indices { sum[index] += vector[index] }
        }
        let norm = sqrt(sum.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return sum }
        return sum.map { $0 / norm }
    }

    private static func makeCandidate(rows: [Int], matrix: VectorMatrix) -> ClusterCandidate? {
        let ids = rows.map { matrix.ids[$0] }
        let vectors = ids.compactMap { matrix.vector(for: $0) }
        guard !vectors.isEmpty else { return nil }
        let center = centroid(of: vectors)
        let cohesion = vectors.reduce(0.0) { $0 + Double(cosine($1, center)) } / Double(vectors.count)
        return ClusterCandidate(memberIDs: ids, centroid: center, cohesion: cohesion)
    }

    private static func merge(_ candidates: [ClusterCandidate], matrix: VectorMatrix, threshold: Float) -> [ClusterCandidate] {
        var result = candidates
        var merged = true
        while merged {
            merged = false
            outer: for i in result.indices {
                for j in result.indices where j > i && cosine(result[i].centroid, result[j].centroid) >= threshold {
                    let ids = result[i].memberIDs + result[j].memberIDs
                    let rows = ids.compactMap { id in matrix.ids.firstIndex(of: id) }
                    if let combined = makeCandidate(rows: rows, matrix: matrix) {
                        result[i] = combined
                        result.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }
        return result
    }
}
