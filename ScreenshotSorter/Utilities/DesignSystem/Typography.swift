import SwiftUI

// MARK: - Typography
/// All styles are built on text styles, so they scale with Dynamic Type.
/// Display + titles use SF Rounded heavy/black for a bold, friendly voice.

extension Font {
    /// Hero headlines (splash, onboarding, completion).
    static let dsDisplay: Font = .system(.largeTitle, design: .rounded, weight: .black)
    /// Screen titles.
    static let dsTitle: Font = .system(.title, design: .rounded, weight: .heavy)
    /// Section titles, card titles.
    static let dsTitle2: Font = .system(.title2, design: .rounded, weight: .bold)
    /// Emphasized row text, button labels.
    static let dsHeadline: Font = .system(.headline, design: .rounded, weight: .bold)
    /// Body copy.
    static let dsBody: Font = .system(.body, design: .default, weight: .regular)
    /// Secondary copy.
    static let dsCallout: Font = .system(.callout, design: .default, weight: .medium)
    /// Chips, labels, metadata.
    static let dsCaption: Font = .system(.caption, design: .rounded, weight: .semibold)
    /// Counters, sizes, technical bits.
    static let dsMono: Font = .system(.callout, design: .monospaced, weight: .semibold)

    /// Big stamp lettering on review cards (still Dynamic-Type based, clamped by the view).
    static let dsStamp: Font = .system(.largeTitle, design: .rounded, weight: .black)
    /// Eyebrow labels above titles.
    static let dsEyebrow: Font = .system(.footnote, design: .rounded, weight: .heavy)
}
