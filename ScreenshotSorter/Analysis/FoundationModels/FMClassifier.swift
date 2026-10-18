import Foundation
import FoundationModels
import os

enum FMOutcome: Sendable {
    case insight(ModelInsight)
    /// Permanently unsuitable (guardrails, unsupported language…) — don't retry this item
    case skipped
    /// Transient (rate limited, busy) — retry later
    case retryLater
    case unavailable
}

/// Serial lane on Apple's on-device language model (Apple Intelligence devices only).
actor FMClassifier {
    static let shared = FMClassifier()
    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "FMClassifier")

    /// Roughly 4k-token context; leave room for instructions + schema + response
    static let maxPromptCharacters = 2_400

    private static let instructions = """
    You organize iPhone screenshots in a private, on-device app. For each screenshot you get the text \
    read from the screen (grouped by screen region), labels from an image classifier and an app guess. \
    Pick categories that describe what the screenshot is about and why someone saved it. \
    Prefer specific categories (receipts, tickets, orders, recipes) over generic ones (documents, notes). \
    Use "other" only when nothing fits. Tags should help someone find the screenshot later by searching.
    """

    nonisolated static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func prewarm() {
        guard FMClassifier.isAvailable else { return }
        LanguageModelSession(instructions: FMClassifier.instructions).prewarm()
    }

    func insight(for features: ExtractedFeatures, appHint: String?) async -> FMOutcome {
        guard FMClassifier.isAvailable else { return .unavailable }
        var budget = FMClassifier.maxPromptCharacters
        for attempt in 0..<2 {
            let prompt = FMClassifier.prompt(for: features, appHint: appHint, budget: budget)
            let session = LanguageModelSession(instructions: FMClassifier.instructions)
            do {
                let response = try await session.respond(
                    to: prompt,
                    generating: ScreenshotInsightResponse.self,
                    options: GenerationOptions(sampling: .greedy)
                )
                return .insight(FMClassifier.convert(response.content))
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .exceededContextWindowSize:
                    if attempt == 0 {
                        budget /= 2
                        continue
                    }
                    return .skipped
                case .rateLimited:
                    return .retryLater
                default:
                    FMClassifier.logger.debug("FM skipped: \(String(describing: error), privacy: .public)")
                    return .skipped
                }
            } catch {
                FMClassifier.logger.debug("FM error: \(String(describing: error), privacy: .public)")
                return .retryLater
            }
        }
        return .skipped
    }

    func nameCollection(tags: [String], apps: [String], titles: [String], allowedSymbols: [String]) async -> (name: String, symbol: String)? {
        guard FMClassifier.isAvailable else { return nil }
        let prompt = """
        Name a photo collection of screenshots.
        Common tags: \(tags.prefix(8).joined(separator: ", "))
        Apps: \(apps.prefix(4).joined(separator: ", "))
        Example titles: \(titles.prefix(8).joined(separator: "; "))
        Allowed symbols: \(allowedSymbols.joined(separator: ", "))
        """
        let session = LanguageModelSession(instructions: "You give short, friendly names to collections of screenshots.")
        do {
            let response = try await session.respond(
                to: prompt,
                generating: CollectionNameResponse.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let symbol = allowedSymbols.contains(response.content.symbol) ? response.content.symbol : "sparkles"
            return (response.content.name.trimmingCharacters(in: .whitespacesAndNewlines), symbol)
        } catch {
            return nil
        }
    }

    // MARK: - Prompt

    static func prompt(for features: ExtractedFeatures, appHint: String?, budget: Int) -> String {
        var parts: [String] = []
        if let appHint, !appHint.isEmpty {
            parts.append("App guess: \(appHint)")
        }
        let labels = features.labels.prefix(10).map { "\($0.identifier) (\(Int($0.confidence * 100))%)" }
        if !labels.isEmpty {
            parts.append("Image labels: " + labels.joined(separator: ", "))
        }
        if features.faces.hasProminentFace {
            parts.append("A person's face is prominent.")
        }
        if !features.barcodes.isEmpty {
            parts.append("Contains a scannable code.")
        }
        var remaining = budget
        for zone in [ScreenZone.topBar, .body, .bottomBar] {
            let text = features.text(in: zone)
            guard !text.isEmpty, remaining > 0 else { continue }
            let clipped = String(text.prefix(remaining))
            remaining -= clipped.count
            let name: String
            switch zone {
            case .topBar: name = "Top of screen"
            case .bottomBar: name = "Bottom of screen"
            default: name = "Main content"
            }
            parts.append("\(name): \(clipped)")
        }
        if features.lines.isEmpty {
            parts.append("No readable text.")
        }
        return parts.joined(separator: "\n")
    }

    static func convert(_ response: ScreenshotInsightResponse) -> ModelInsight {
        let primary = response.primary.category
        let secondary = response.secondary.compactMap(\.category).filter { $0 != primary }
        let tags = response.tags
            .map { ScreenshotClassifier.normalizeTag($0) }
            .filter { !$0.isEmpty }
        return ModelInsight(
            primary: primary,
            secondary: Array(secondary.prefix(3)),
            confidence: min(max(Double(response.confidence) / 100, 0.05), 0.98),
            app: response.app.isEmpty ? nil : response.app,
            title: String(response.title.prefix(80)),
            summary: String(response.summary.prefix(240)),
            tags: Array(tags.prefix(8))
        )
    }
}
