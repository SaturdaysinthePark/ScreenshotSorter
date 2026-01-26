import SwiftUI

// MARK: - Semantic Color System
/// Centralized color system for consistent theming throughout the app
/// iOS 26+ only - uses native gradients and glass effects

enum SemanticColor {
    case primary
    case success
    case danger
    case warning
    case info

    var gradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var horizontalGradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var colors: [Color] {
        switch self {
        case .primary:
            return [.blue, .purple]
        case .success:
            return [.green, .teal]
        case .danger:
            return [.red, .orange]
        case .warning:
            return [.orange, .yellow]
        case .info:
            return [.cyan, .blue]
        }
    }

    var solidColor: Color {
        switch self {
        case .primary:
            return .blue
        case .success:
            return .green
        case .danger:
            return .red
        case .warning:
            return .orange
        case .info:
            return .cyan
        }
    }

    var lightBackground: Color {
        solidColor.opacity(0.15)
    }
}

// MARK: - Color Extensions

extension Color {
    static let semanticPrimary = SemanticColor.primary.solidColor
    static let semanticSuccess = SemanticColor.success.solidColor
    static let semanticDanger = SemanticColor.danger.solidColor
    static let semanticWarning = SemanticColor.warning.solidColor
    static let semanticInfo = SemanticColor.info.solidColor
}

// MARK: - Glass Card Modifiers (iOS 26+ only)

struct PrimaryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct SecondaryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(.thin, in: .rect(cornerRadius: 12))
    }
}

struct TintedGlassModifier: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.tint(color.opacity(0.2)), in: .rect(cornerRadius: cornerRadius))
    }
}

struct CapsuleGlassModifier: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color = color {
            content
                .glassEffect(.regular.tint(color.opacity(0.2)), in: .capsule)
        } else {
            content
                .glassEffect(.regular, in: .capsule)
        }
    }
}

// MARK: - View Extensions

extension View {
    func primaryCard() -> some View {
        modifier(PrimaryCardModifier())
    }

    func secondaryCard() -> some View {
        modifier(SecondaryCardModifier())
    }

    func tintedGlass(color: Color, cornerRadius: CGFloat = 12) -> some View {
        modifier(TintedGlassModifier(color: color, cornerRadius: cornerRadius))
    }

    func capsuleGlass(tint: Color? = nil) -> some View {
        modifier(CapsuleGlassModifier(color: tint))
    }

    func semanticGradient(_ semantic: SemanticColor) -> some View {
        foregroundStyle(semantic.gradient)
    }
}

// MARK: - Gradient Button Styles

struct SemanticGradientButtonStyle: ButtonStyle {
    let semantic: SemanticColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(semantic.gradient)
            .cornerRadius(12)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SemanticGradientButtonStyle {
    static func semantic(_ semantic: SemanticColor) -> SemanticGradientButtonStyle {
        SemanticGradientButtonStyle(semantic: semantic)
    }
}
