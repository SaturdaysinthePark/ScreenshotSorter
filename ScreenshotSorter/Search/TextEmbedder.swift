import Foundation
import NaturalLanguage

/// On-device sentence embeddings for semantic search and similarity.
actor TextEmbedder {
    static let shared = TextEmbedder()
    static let modelID = "nl-sentence-en-v\(PipelineVersion.embedding)"
    static let maxCharacters = 1_200

    private var embedding: NLEmbedding?
    private var didLoad = false

    private func model() -> NLEmbedding? {
        if !didLoad {
            embedding = NLEmbedding.sentenceEmbedding(for: .english)
            didLoad = true
        }
        return embedding
    }

    var dimension: Int { model()?.dimension ?? 0 }

    /// L2-normalized vector, or nil if the model is unavailable / text empty.
    func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let model = model() else { return nil }
        guard let vector = model.vector(for: String(trimmed.prefix(TextEmbedder.maxCharacters))) else { return nil }
        var floats = vector.map { Float($0) }
        let norm = sqrt(floats.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        for index in floats.indices { floats[index] /= norm }
        return floats
    }

    /// Text that best describes a record for embedding.
    static func document(for record: AnalysisRecord) -> String {
        var parts: [String] = []
        if let title = record.title { parts.append(title) }
        if let summary = record.summary { parts.append(summary) }
        if let app = record.app { parts.append(app) }
        parts.append(record.categories.map(\.category.displayName).joined(separator: ", "))
        parts.append(record.tags.map(\.value).joined(separator: ", "))
        parts.append(String(record.ocrText.prefix(600)))
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }
}
