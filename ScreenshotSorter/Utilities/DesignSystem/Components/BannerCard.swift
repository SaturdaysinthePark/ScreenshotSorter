import SwiftUI

// MARK: - Banner Card
/// Playful floating banner: animated icon tile, title + subtitle, one clear CTA, dismiss.

struct BannerCard<Accessory: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    let ctaTitle: String
    let ctaSystemImage: String?
    let dismissLabel: String
    let onCTA: () -> Void
    let onDismiss: () -> Void
    let accessory: Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateIcon = false

    init(
        systemImage: String,
        tint: Color,
        title: String,
        subtitle: String,
        ctaTitle: String,
        ctaSystemImage: String? = nil,
        dismissLabel: String,
        onCTA: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.ctaTitle = ctaTitle
        self.ctaSystemImage = ctaSystemImage
        self.dismissLabel = dismissLabel
        self.onCTA = onCTA
        self.onDismiss = onDismiss
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .top, spacing: Space.sm) {
                iconTile

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dsHeadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.xxs + 2) {
                        accessory
                        Text(subtitle)
                            .font(.dsCaption)
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                Button {
                    HapticManager.shared.lightTap()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Palette.inkSecondary.opacity(0.12)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableCard)
                .padding(.top, -Space.xs)
                .padding(.trailing, -Space.xs)
                .accessibilityLabel(dismissLabel)
            }

            Button {
                onCTA()
            } label: {
                HStack(spacing: Space.xs) {
                    Text(ctaTitle)
                    if let ctaSystemImage {
                        Image(systemName: ctaSystemImage)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brand(.primary, size: .compact))
        }
        .padding(Space.md)
        .dsCard(tint: tint, radius: Radius.lg)
        .onAppear {
            if !reduceMotion {
                animateIcon = true
            }
        }
    }

    private var iconTile: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.bold))
            .foregroundStyle(Palette.onBrand)
            .symbolEffect(.bounce, options: .repeating.speed(0.35), value: animateIcon)
            .frame(width: 44, height: 44)
            .background {
                RoundedRectangle(cornerRadius: Radius.sm + 2, style: .continuous)
                    .fill(tint.gradient)
            }
            .rotationEffect(.degrees(-6))
            .accessibilityHidden(true)
    }
}

extension BannerCard where Accessory == EmptyView {
    init(
        systemImage: String,
        tint: Color,
        title: String,
        subtitle: String,
        ctaTitle: String,
        ctaSystemImage: String? = nil,
        dismissLabel: String,
        onCTA: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.init(
            systemImage: systemImage,
            tint: tint,
            title: title,
            subtitle: subtitle,
            ctaTitle: ctaTitle,
            ctaSystemImage: ctaSystemImage,
            dismissLabel: dismissLabel,
            onCTA: onCTA,
            onDismiss: onDismiss,
            accessory: { EmptyView() }
        )
    }
}

// MARK: - Progress Bar
/// Chunky rounded progress bar with brand gradient fill. Animates via scale (no layout thrash).

struct DSProgressBar: View {
    let progress: Double
    var tint: AnyShapeStyle = AnyShapeStyle(Palette.brandGradientHorizontal)
    var height: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(progress: Double, tint: AnyShapeStyle = AnyShapeStyle(Palette.brandGradientHorizontal), height: CGFloat = 8) {
        self.progress = progress
        self.tint = tint
        self.height = height
    }

    var body: some View {
        let clamped: Double = min(max(progress, 0), 1)
        Capsule(style: .continuous)
            .fill(Palette.inkSecondary.opacity(0.16))
            .frame(height: height)
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(height: height)
                    .scaleEffect(x: max(clamped, 0.001), y: 1, anchor: .leading)
                    .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: clamped)
            }
            .clipShape(Capsule(style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}
