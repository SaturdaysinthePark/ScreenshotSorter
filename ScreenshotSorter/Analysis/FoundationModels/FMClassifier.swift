import CoreGraphics
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
    Pick the topic that describes what the screenshot is about and why someone saved it, not the app it \
    was taken in. Prefer specific topics (receipts, tickets, orders, recipes) over generic ones (documents, \
    notes). Use "other" only when nothing fits. Tags should help someone find the screenshot later by searching.
    """

    nonisolated static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// iOS 27's system model can look at the screenshot itself, not just the text read from it — the
    /// difference between guessing from "Following · For You · 12.4K" and seeing a plate of tacos.
    nonisolated static var canSeeImages: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            return isAvailable && SystemLanguageModel.default.capabilities.contains(.vision)
        }
        #endif
        return false
    }

    /// Without the image, a screenshot with almost no text gives the model nothing to go on: on the eval
    /// corpus it answered "receipts" or "events" for nearly every photo. Don't ask.
    static func isWorthAsking(_ features: ExtractedFeatures, canSeeImages: Bool = FMClassifier.canSeeImages) -> Bool {
        canSeeImages || features.lines.filter { $0.zone != .statusBar }.count >= minimumTextLines
    }
    static let minimumTextLines = 3

    /// Longest side of the image handed to the model: enough to read a post or a product photo, small
    /// enough to keep each request to a couple of seconds.
    static let imageMaxPixel: CGFloat = 768

    func prewarm() {
        guard FMClassifier.isAvailable else { return }
        LanguageModelSession(instructions: FMClassifier.instructions).prewarm()
    }

    /// - Parameter image: the screenshot, used when the model can see images (`canSeeImages`)
    func insight(for features: ExtractedFeatures, appHint: String?, image: CGImage? = nil) async -> FMOutcome {
        guard FMClassifier.isAvailable else { return .unavailable }
        var budget = FMClassifier.maxPromptCharacters
        for attempt in 0..<2 {
            let prompt = FMClassifier.prompt(for: features, appHint: appHint, budget: budget)
            do {
                let (content, sawImage) = try await FMClassifier.respond(to: prompt, image: image)
                var insight = FMClassifier.convert(content)
                insight.sawImage = sawImage
                return .insight(insight)
            } catch {
                switch FMClassifier.disposition(of: error) {
                case .shrinkPrompt where attempt == 0:
                    budget /= 2
                    continue
                case .shrinkPrompt, .skip:
                    FMClassifier.logger.debug("FM skipped: \(String(describing: error), privacy: .public)")
                    return .skipped
                case .retryLater:
                    FMClassifier.logger.debug("FM retry later: \(String(describing: error), privacy: .public)")
                    return .retryLater
                }
            }
        }
        return .skipped
    }

    enum Disposition { case shrinkPrompt, retryLater, skip }

    /// iOS 27 reports `LanguageModelError`; earlier systems `LanguageModelSession.GenerationError`.
    static func disposition(of error: Error) -> Disposition {
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .shrinkPrompt
            case .rateLimited, .timeout: return .retryLater
            default: return .skip
            }
        }
        #endif
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return .shrinkPrompt
            case .rateLimited, .concurrentRequests: return .retryLater
            default: return .skip
            }
        }
        // Unknown failures (model busy, assets loading): try again later rather than give up on the item
        return .retryLater
    }

    private static func respond(to prompt: String, image: CGImage?) async throws -> (ScreenshotInsightResponse, sawImage: Bool) {
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *), let image, canSeeImages {
            let session = LanguageModelSession(instructions: instructions + " " + imageInstructions)
            let response = try await session.respond(generating: ScreenshotInsightResponse.self, options: GenerationOptions(sampling: .greedy)) {
                Attachment(image).label("screenshot")
                prompt
            }
            return (response.content, true)
        }
        #endif
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: ScreenshotInsightResponse.self,
                                                 options: GenerationOptions(sampling: .greedy))
        return (response.content, false)
    }

    private static let imageInstructions = """
    You also see the screenshot itself. Judge it by its main content (the photo, product, post or page), \
    not by the app's buttons and tab bars.
    """

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
            confidence: response.certainty.confidence,
            app: response.app.isEmpty ? nil : response.app,
            title: String(response.title.prefix(80)),
            summary: String(response.summary.prefix(240)),
            tags: Array(tags.prefix(6))
        )
    }
}
