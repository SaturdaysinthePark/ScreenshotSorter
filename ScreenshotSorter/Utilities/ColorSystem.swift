import SwiftUI

// MARK: - DEPRECATED compatibility shim
/// Legacy color API kept compiling while screens migrate to the design system
/// (`Palette`, `dsCard`, `BrandButtonStyle` in Utilities/DesignSystem).
/// Everything here maps onto `Palette`. Do not use in new code — delete once all callers migrate.

enum SemanticColor {
    case primary
    case success
    case danger
    case warning
    case info

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var horizontalGradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    var colors: [Color] {
        switch self {
        case .primary:
            return [Palette.brand, Palette.brandSecondary]
        case .success:
            return [Palette.keep, CategoryGroup.placesTravel.color]
        case .danger:
            return [Palette.toss, Palette.brandSecondary]
        case .warning:
            return [Palette.warning, CategoryGroup.information.color]
        case .info:
            return [Palette.info, CategoryGroup.system.color]
        }
    }

    var solidColor: Color {
        switch self {
        case .primary:
            return Palette.brand
        case .success:
            return Palette.keep
        case .danger:
            return Palette.toss
        case .warning:
            return Palette.warning
        case .info:
            return Palette.info
        }
    }

    var lightBackground: Color {
        solidColor.opacity(0.15)
    }
}

// MARK: - Legacy View Extensions (mapped onto the design system)

extension View {
    /// Deprecated: use `dsCard()`.
    func primaryCard() -> some View {
        dsCard(radius: Radius.md)
    }

    /// Deprecated: use `dsCard(radius: Radius.sm)`.
    func secondaryCard() -> some View {
        dsCard(radius: Radius.sm + 2)
    }

    /// Deprecated: use `dsCard(tint:radius:)`.
    func tintedGlass(color: Color, cornerRadius: CGFloat = 12) -> some View {
        dsCard(tint: color, radius: cornerRadius)
    }

    /// Deprecated: use `glassEffect(.regular.tint(...), in: .capsule)` or `TagChip`.
    func capsuleGlass(tint: Color? = nil) -> some View {
        modifier(LegacyCapsuleGlassModifier(tint: tint))
    }

    /// Deprecated: use `foregroundStyle(Palette.brandGradient)`.
    func semanticGradient(_ semantic: SemanticColor) -> some View {
        foregroundStyle(semantic.gradient)
    }
}

private struct LegacyCapsuleGlassModifier: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        content.glassEffect(glass, in: .capsule)
    }

    private var glass: Glass {
        if let tint {
            return Glass.regular.tint(tint.opacity(0.22))
        }
        return Glass.regular
    }
}
