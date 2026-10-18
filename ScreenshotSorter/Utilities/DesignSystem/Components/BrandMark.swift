import SwiftUI

// MARK: - Mini Screenshot
/// Stylised placeholder "screenshot" used in illustrations (splash, onboarding, access prompt).

struct MiniScreenshot: View {
    enum Content {
        case chat
        case photo
        case list
    }

    let fill: AnyShapeStyle
    let ink: Color
    var width: CGFloat = 60
    var content: Content = .chat

    init(color: Color, width: CGFloat = 60, content: Content = .chat) {
        self.fill = AnyShapeStyle(color.gradient)
        self.ink = Color.white
        self.width = width
        self.content = content
    }

    init(gradient: LinearGradient, ink: Color = .white, width: CGFloat = 60, content: Content = .chat) {
        self.fill = AnyShapeStyle(gradient)
        self.ink = ink
        self.width = width
        self.content = content
    }

    init(style: AnyShapeStyle, ink: Color, width: CGFloat = 60, content: Content = .chat) {
        self.fill = style
        self.ink = ink
        self.width = width
        self.content = content
    }

    static func height(forWidth width: CGFloat) -> CGFloat { width * 1.85 }

    var body: some View {
        let height: CGFloat = MiniScreenshot.height(forWidth: width)
        let radius: CGFloat = width * 0.2
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
            .overlay(alignment: .top) {
                contentLayer
                    .padding(width * 0.12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: max(1.5, width * 0.035))
            }
    }

    private var line: CGFloat { max(3, width * 0.075) }

    @ViewBuilder
    private var contentLayer: some View {
        VStack(alignment: .leading, spacing: line * 0.9) {
            // Status bar
            HStack {
                Capsule().fill(ink.opacity(0.75)).frame(width: width * 0.22, height: line * 0.6)
                Spacer(minLength: 0)
                Capsule().fill(ink.opacity(0.75)).frame(width: width * 0.14, height: line * 0.6)
            }
            .padding(.bottom, line * 0.4)

            switch content {
            case .chat:
                chatBubble(widthFactor: 0.55, leading: true)
                chatBubble(widthFactor: 0.42, leading: false)
                chatBubble(widthFactor: 0.62, leading: true)
                chatBubble(widthFactor: 0.35, leading: false)
            case .photo:
                RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                    .fill(ink.opacity(0.35))
                    .frame(height: width * 0.62)
                textLine(0.8)
                textLine(0.55)
            case .list:
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: line * 0.6) {
                        Circle().fill(ink.opacity(0.8)).frame(width: line * 1.4, height: line * 1.4)
                        Capsule().fill(ink.opacity(0.55)).frame(height: line)
                            .frame(maxWidth: width * (index % 2 == 0 ? 0.5 : 0.36), alignment: .leading)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func textLine(_ factor: CGFloat) -> some View {
        Capsule()
            .fill(ink.opacity(0.6))
            .frame(width: width * factor, height: line)
    }

    private func chatBubble(widthFactor: CGFloat, leading: Bool) -> some View {
        HStack(spacing: 0) {
            if !leading { Spacer(minLength: 0) }
            RoundedRectangle(cornerRadius: line, style: .continuous)
                .fill(ink.opacity(leading ? 0.45 : 0.85))
                .frame(width: width * widthFactor, height: line * 2.2)
            if leading { Spacer(minLength: 0) }
        }
    }
}

// MARK: - Brand Mark
/// The logo: three screenshot cards that fan in from chaos and snap into a neat stack.
/// Drive `isSettled` from false → true (inside any transaction) to play the entrance.

struct BrandMark: View {
    var size: CGFloat = 120
    var isSettled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(size: CGFloat = 120, isSettled: Bool = true) {
        self.size = size
        self.isSettled = isSettled
    }

    private var cardWidth: CGFloat { size * 0.56 }

    var body: some View {
        ZStack {
            card(index: 0, view: MiniScreenshot(color: CategoryGroup.communication.color, width: cardWidth, content: .chat))
            card(index: 1, view: MiniScreenshot(color: CategoryGroup.socialMedia.color, width: cardWidth, content: .photo))
            card(index: 2, view: MiniScreenshot(
                style: AnyShapeStyle(Color.white),
                ink: Palette.brand,
                width: cardWidth,
                content: .list
            ))
            sticker
        }
        .frame(width: size * 1.1, height: size * 1.1)
        .accessibilityHidden(true)
    }

    private var sticker: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.13, weight: .black, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(width: size * 0.26, height: size * 0.26)
            .background(Circle().fill(Palette.brandSecondary))
            .overlay(Circle().strokeBorder(Color.white, lineWidth: max(2, size * 0.025)))
            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
            .scaleEffect(isSettled ? 1 : 0.01)
            .opacity(isSettled ? 1 : 0)
            .offset(x: cardWidth * 0.55, y: -size * 0.42)
            .animation(Motion.animation(Motion.bouncy.delay(0.16), reduceMotion: reduceMotion), value: isSettled)
    }

    private func card<V: View>(index: Int, view: V) -> some View {
        let pose: CardPose = isSettled ? settledPose(index) : scatteredPose(index)
        return view
            .shadow(color: Color.black.opacity(0.18), radius: size * 0.06, x: 0, y: size * 0.03)
            .rotationEffect(.degrees(pose.rotation))
            .scaleEffect(pose.scale)
            .offset(x: pose.x, y: pose.y)
            .opacity(pose.opacity)
            .animation(Motion.animation(Motion.bouncy.delay(Motion.stagger(index, step: 0.05)), reduceMotion: reduceMotion), value: isSettled)
    }

    private struct CardPose {
        var x: CGFloat
        var y: CGFloat
        var rotation: Double
        var scale: CGFloat
        var opacity: Double
    }

    private func settledPose(_ index: Int) -> CardPose {
        switch index {
        case 0: return CardPose(x: -size * 0.2, y: size * 0.03, rotation: -13, scale: 0.92, opacity: 1)
        case 1: return CardPose(x: size * 0.2, y: size * 0.03, rotation: 13, scale: 0.92, opacity: 1)
        default: return CardPose(x: 0, y: 0, rotation: 0, scale: 1, opacity: 1)
        }
    }

    private func scatteredPose(_ index: Int) -> CardPose {
        if reduceMotion {
            var pose: CardPose = settledPose(index)
            pose.opacity = 0
            return pose
        }
        switch index {
        case 0: return CardPose(x: -size * 0.9, y: -size * 0.55, rotation: -48, scale: 0.7, opacity: 0)
        case 1: return CardPose(x: size * 0.95, y: size * 0.35, rotation: 40, scale: 0.7, opacity: 0)
        default: return CardPose(x: -size * 0.1, y: size * 0.9, rotation: -22, scale: 0.6, opacity: 0)
        }
    }
}

#Preview("Brand mark") {
    BrandMark(size: 160)
        .padding(60)
        .background(Palette.brandGradient)
}
