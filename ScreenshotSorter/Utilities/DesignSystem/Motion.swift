import SwiftUI

// MARK: - Motion
/// Every animation in the app goes through here. Springy, never slow.
/// Always pass the user's Reduce Motion preference through `Motion.animation(_:reduceMotion:)`
/// (or use `.dsAnimation(_:value:)` / `Motion.perform`), which swaps in a short crossfade-friendly ease.

enum Motion {
    /// Default UI response: toggles, selection, small layout changes.
    static let snappy: Animation = .snappy(duration: 0.28, extraBounce: 0.04)
    /// Playful pops: stamps, badges, cards settling.
    static let bouncy: Animation = .bouncy(duration: 0.42, extraBounce: 0.12)
    /// Larger, softer transitions: page changes, sheets of content.
    static let gentle: Animation = .smooth(duration: 0.45)
    /// Cards being flung off the deck.
    static let cardFling: Animation = .spring(response: 0.36, dampingFraction: 0.9)
    /// Tiny feedback (press states, fades).
    static let quick: Animation = .easeOut(duration: 0.16)

    /// Reduce Motion replacement: short ease, pair with opacity changes instead of movement.
    static let reduced: Animation = .easeInOut(duration: 0.2)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// `withAnimation` that respects Reduce Motion.
    @discardableResult
    static func perform<Result>(
        _ animation: Animation,
        reduceMotion: Bool,
        _ body: () throws -> Result
    ) rethrows -> Result {
        try withAnimation(Motion.animation(animation, reduceMotion: reduceMotion), body)
    }

    /// Staggered delay for list/fan entrances.
    static func stagger(_ index: Int, step: Double = 0.04) -> Double {
        Double(index) * step
    }
}

// MARK: - Reduce-Motion-aware implicit animation

private struct DSAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Like `.animation(_:value:)` but swaps to a short ease when Reduce Motion is on.
    func dsAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(DSAnimationModifier(animation: animation, value: value))
    }
}
