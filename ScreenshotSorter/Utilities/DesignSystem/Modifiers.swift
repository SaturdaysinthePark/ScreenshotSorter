import SwiftUI

// MARK: - Card Modifiers

/// Liquid Glass card for floating chrome (banners, toasts, overlays).
private struct DSCardModifier: ViewModifier {
    let tint: Color?
    let radius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        content
            .glassEffect(glass, in: .rect(cornerRadius: radius))
    }

    private var glass: Glass {
        var result: Glass = .regular
        if let tint {
            result = result.tint(tint.opacity(0.22))
        }
        if interactive {
            result = result.interactive()
        }
        return result
    }
}

/// Solid card for content that sits on the canvas (lists, grids, stats).
private struct DSSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surface)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(tint.opacity(0.08))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
            }
    }
}

extension View {
    /// Liquid Glass card: `glassEffect(.regular.tint(...), in: .rect(cornerRadius:))`.
    func dsCard(tint: Color? = nil, radius: CGFloat = Radius.lg) -> some View {
        modifier(DSCardModifier(tint: tint, radius: radius, interactive: false))
    }

    /// Interactive Liquid Glass card (reacts to touch). Use only on tappable chrome.
    func dsInteractiveCard(tint: Color? = nil, radius: CGFloat = Radius.lg) -> some View {
        modifier(DSCardModifier(tint: tint, radius: radius, interactive: true))
    }

    /// Opaque surface card with hairline + soft shadow, for content on the canvas.
    func dsSurface(radius: CGFloat = Radius.lg, tint: Color? = nil) -> some View {
        modifier(DSSurfaceModifier(radius: radius, tint: tint))
    }

    /// Squish on press. Apply to a `Button` or `NavigationLink` (sets `PressableCardButtonStyle`).
    func pressable() -> some View {
        buttonStyle(PressableCardButtonStyle())
    }

    /// Full-bleed app canvas background.
    func dsCanvas() -> some View {
        background(Palette.canvas.ignoresSafeArea())
    }
}

// MARK: - Ambient Glow
/// Soft radial color wash used behind hero content. Cheap (no blur).

struct AmbientGlow: View {
    var color: Color = Palette.brand
    var secondary: Color = Palette.brandSecondary
    var intensity: Double = 0.22

    var body: some View {
        GeometryReader { proxy in
            let size: CGSize = proxy.size
            ZStack {
                RadialGradient(
                    colors: [color.opacity(intensity), Color.clear],
                    center: UnitPoint(x: 0.15, y: 0.0),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.7
                )
                RadialGradient(
                    colors: [secondary.opacity(intensity * 0.8), Color.clear],
                    center: UnitPoint(x: 0.95, y: 0.35),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.55
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
