import SwiftUI

// MARK: - Photo Access Prompt
/// First-run permission screen: playful animated hero, a clear value prop,
/// a privacy promise, and one obvious button.

struct PhotoAccessPromptView: View {
    let onRequestAccess: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false

    init(onRequestAccess: @escaping () -> Void) {
        self.onRequestAccess = onRequestAccess
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            AmbientGlow(intensity: 0.2)

            ScrollView {
                VStack(spacing: Space.xl) {
                    AccessHero(isSettled: isSettled)
                        .padding(.top, Space.xl)

                    textBlock

                    privacyCard
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Space.sm) {
                Button {
                    HapticManager.shared.mediumTap()
                    onRequestAccess()
                } label: {
                    Label(Brand.Copy.Access.cta, systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(.brand())
                .accessibilityHint(Brand.Copy.Access.ctaHint)

                Text(Brand.Copy.Access.footnote)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xs)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Palette.canvas.opacity(0.94).ignoresSafeArea())
        }
        .onAppear {
            isSettled = true
        }
    }

    private var textBlock: some View {
        VStack(spacing: Space.sm) {
            Text(Brand.Copy.Access.eyebrow)
                .font(.dsEyebrow)
                .foregroundStyle(Palette.brand)

            Text(Brand.Copy.Access.title)
                .font(.dsDisplay)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(Brand.Copy.Access.body)
                .font(.dsBody)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(isSettled ? 1 : 0)
        .offset(y: isSettled || reduceMotion ? 0 : 14)
        .animation(Motion.animation(Motion.gentle.delay(0.1), reduceMotion: reduceMotion), value: isSettled)
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(Palette.keep)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(Brand.Copy.Access.privacy)
                    .font(.dsHeadline)
                    .foregroundStyle(Palette.ink)
                Text(Brand.Copy.Access.privacyDetail)
                    .font(.dsCallout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .dsSurface(radius: Radius.lg, tint: Palette.keep)
        .accessibilityElement(children: .combine)
        .opacity(isSettled ? 1 : 0)
        .animation(Motion.animation(Motion.gentle.delay(0.2), reduceMotion: reduceMotion), value: isSettled)
    }
}

// MARK: - Hero

/// Card-stack illustration with category chips bobbing around it.
private struct AccessHero: View {
    let isSettled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.brand.opacity(0.10))
                .frame(width: 230, height: 230)

            BrandMark(size: 150, isSettled: isSettled)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, lifted in
                    content.offset(y: lifted ? -6 : 4)
                } animation: { _ in
                    .easeInOut(duration: 1.8)
                }

            floatingChip(.foodDrink, label: "Recipes", icon: "fork.knife", x: -118, y: -70, delay: 0.18)
            floatingChip(.communication, label: "Chats", icon: "message.fill", x: 112, y: -40, delay: 0.24)
            floatingChip(.placesTravel, label: "Directions", icon: "map.fill", x: -96, y: 92, delay: 0.3)
            floatingChip(.mediaEntertainment, label: "Memes", icon: "face.smiling.fill", x: 108, y: 78, delay: 0.36)
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func floatingChip(
        _ group: CategoryGroup,
        label: String,
        icon: String,
        x: CGFloat,
        y: CGFloat,
        delay: Double
    ) -> some View {
        TagChip(label, systemImage: icon, tint: group.color)
            .background(Capsule(style: .continuous).fill(Palette.surface))
            .shadow(color: group.color.opacity(0.25), radius: 8, x: 0, y: 4)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, up in
                content.offset(y: up ? -5 : 5)
            } animation: { _ in
                .easeInOut(duration: 1.4 + delay * 2)
            }
            .scaleEffect(isSettled ? 1 : 0.4)
            .opacity(isSettled ? 1 : 0)
            .offset(x: x, y: y)
            .animation(Motion.animation(Motion.bouncy.delay(delay), reduceMotion: reduceMotion), value: isSettled)
    }
}

#Preview("Photo access") {
    PhotoAccessPromptView(onRequestAccess: {})
}
