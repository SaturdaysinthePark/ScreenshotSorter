import Foundation

struct AppMatch: Sendable, Hashable {
    let appID: String
    let displayName: String
    let category: ScreenshotCategory?
    let confidence: Double
}

/// Identifies which app a screenshot was taken in.
struct AppDetector: Sendable {
    private struct CompiledSignature: Sendable {
        let signature: AppSignature
        let names: [String]
        let phrases: [(String, Double)]
        let chrome: [RuleEngine.CompiledPattern]
    }

    static let nameWeight = 0.4
    static let hostWeight = 0.6
    static let minimumConfidence = 0.5

    private let signatures: [CompiledSignature]

    static let shared = AppDetector(signatures: AppSignatures.all)

    init(signatures: [AppSignature]) {
        self.signatures = signatures.map { signature in
            CompiledSignature(
                signature: signature,
                names: signature.names.map { TextNormalizer.normalizeTerm($0) },
                phrases: signature.phrases.map { (TextNormalizer.normalizeTerm($0.key), $0.value) },
                chrome: signature.chrome.map { RuleEngine.CompiledPattern($0) }
            )
        }
    }

    /// All apps with confidence ≥ `minimumConfidence`, best first.
    func detect(_ text: NormalizedText, features: ExtractedFeatures? = nil) -> [AppMatch] {
        guard !text.isEmpty else { return [] }
        var matches: [AppMatch] = []

        for compiled in signatures {
            var weights: [Double] = []
            if compiled.names.contains(where: { text.contains(normalized: $0) }) {
                weights.append(AppDetector.nameWeight)
            }
            let hosts = compiled.signature.hosts
            if !hosts.isEmpty && text.urlHosts.contains(where: { host in hosts.contains { host == $0 || host.hasSuffix("." + $0) } }) {
                weights.append(AppDetector.hostWeight)
            }
            for (phrase, weight) in compiled.phrases where text.contains(normalized: phrase) {
                weights.append(weight)
            }
            for pattern in compiled.chrome {
                if let weight = pattern.weight(in: text, features: features) {
                    weights.append(weight)
                }
            }
            guard !weights.isEmpty else { continue }
            let confidence = RuleEngine.noisyOr(weights)
            if confidence >= AppDetector.minimumConfidence {
                matches.append(AppMatch(
                    appID: compiled.signature.appID,
                    displayName: compiled.signature.displayName,
                    category: compiled.signature.category,
                    confidence: confidence
                ))
            }
        }
        return matches.sorted { $0.confidence > $1.confidence }
    }

    func best(_ text: NormalizedText, features: ExtractedFeatures? = nil) -> AppMatch? {
        detect(text, features: features).first
    }
}
