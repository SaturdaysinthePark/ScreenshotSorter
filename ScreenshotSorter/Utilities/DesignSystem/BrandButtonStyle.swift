import SwiftUI

// MARK: - Brand Button Style
/// Chunky, squishy buttons. Press = scale 0.96 + spring.
///
///     Button("Let's go") { ... }.buttonStyle(.brand())
///     Button("Later") { ... }.buttonStyle(.brand(.ghost))
///     Button("Sort") { ... }.buttonStyle(.brand(.primary, size: .compact))

struct BrandButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case destructive
        case ghost
    }

    enum Size {
        /// Full-width, 56pt tall. For primary screen actions.
        case large
        /// Intrinsic width capsule. For banners, toolbars, inline actions.
        case compact
    }

    var kind: Kind = .primary
    var size: Size = .large

    init(kind: Kind = .primary, size: Size = .large) {
        self.kind = kind
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        BrandButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: kind,
            size: size
        )
    }
}

private struct BrandButtonBody: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let kind: BrandButtonStyle.Kind
    let size: BrandButtonStyle.Size

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        styledLabel
            .scaleEffect(pressScale)
            .opacity(isEnabled ? 1.0 : 0.45)
            .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: isPressed)
    }

    private var pressScale: CGFloat {
        guard isPressed else { return 1.0 }
        return reduceMotion ? 0.99 : 0.96
    }

    @ViewBuilder
    private var styledLabel: some View {
        switch size {
        case .large:
            label
                .font(.dsHeadline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background { fillLayer(shape: RoundedRectangle(cornerRadius: Radius.md + 4, style: .continuous)) }
                .contentShape(RoundedRectangle(cornerRadius: Radius.md + 4, style: .continuous))
        case .compact:
            label
                .font(.dsCaption.weight(.heavy))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.xs + 2)
                .frame(minHeight: 36)
                .background { fillLayer(shape: Capsule(style: .continuous)) }
                .contentShape(Capsule(style: .continuous))
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive:
            return Palette.onBrand
        case .secondary:
            return Palette.ink
        case .ghost:
            return Palette.brand
        }
    }

    @ViewBuilder
    private func fillLayer<S: Shape>(shape: S) -> some View {
        switch kind {
        case .primary:
            shape
                .fill(Palette.brandGradientHorizontal)
                .overlay {
                    // Soft top highlight for a bit of candy-like depth.
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isPressed ? 0.0 : 0.18), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                }
                .shadow(color: Palette.brand.opacity(isPressed ? 0.15 : 0.32), radius: isPressed ? 6 : 14, x: 0, y: isPressed ? 3 : 8)
        case .destructive:
            shape
                .fill(Palette.toss)
                .shadow(color: Palette.toss.opacity(isPressed ? 0.15 : 0.3), radius: isPressed ? 6 : 12, x: 0, y: isPressed ? 3 : 6)
        case .secondary:
            shape
                .fill(Palette.surface)
                .overlay { shape.stroke(Palette.hairline, lineWidth: 1) }
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        case .ghost:
            shape
                .fill(Palette.brand.opacity(isPressed ? 0.14 : 0.0))
        }
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static func brand(_ kind: BrandButtonStyle.Kind = .primary) -> BrandButtonStyle {
        BrandButtonStyle(kind: kind, size: .large)
    }

    static func brand(_ kind: BrandButtonStyle.Kind, size: BrandButtonStyle.Size) -> BrandButtonStyle {
        BrandButtonStyle(kind: kind, size: size)
    }
}

// MARK: - Pressable Card Button Style
/// For tappable cards/tiles: a gentle squish without changing their look.
///
///     NavigationLink(value: item) { Card() }.buttonStyle(.pressableCard)
///     Button { } label: { Tile() }.pressable()

struct PressableCardButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressableCardBody(label: configuration.label, isPressed: configuration.isPressed, scale: scale)
    }
}

private struct PressableCardBody: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .contentShape(Rectangle())
            .scaleEffect(isPressed && !reduceMotion ? scale : 1.0)
            .opacity(isPressed && reduceMotion ? 0.8 : 1.0)
            .brightness(isPressed ? -0.02 : 0)
            .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: isPressed)
    }
}

extension ButtonStyle where Self == PressableCardButtonStyle {
    static var pressableCard: PressableCardButtonStyle { PressableCardButtonStyle() }
}
