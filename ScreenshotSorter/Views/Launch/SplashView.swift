import SwiftUI

// MARK: - Splash View
/// Short branded entrance (~0.5s): three screenshot cards fly in from chaos,
/// snap into a neat stack, the check sticker pops, and the wordmark rises.
/// Under Reduce Motion everything simply fades in.

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false
    @State private var popTrigger = 0

    init() {}

    var body: some View {
        ZStack {
            Palette.brandGradient
                .ignoresSafeArea()

            // Soft light wash so the gradient doesn't feel flat.
            RadialGradient(
                colors: [Color.white.opacity(0.22), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: Space.lg) {
                BrandMark(size: 132, isSettled: isSettled)
                    .keyframeAnimator(initialValue: SplashPop(), trigger: popTrigger) { content, pop in
                        content
                            .scaleEffect(pop.scale)
                            .rotationEffect(.degrees(pop.tilt))
                    } keyframes: { _ in
                        KeyframeTrack(\SplashPop.scale) {
                            CubicKeyframe(1.0, duration: 0.24)
                            SpringKeyframe(1.08, duration: 0.12, spring: .snappy)
                            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                        }
                        KeyframeTrack(\SplashPop.tilt) {
                            CubicKeyframe(0, duration: 0.24)
                            SpringKeyframe(-4, duration: 0.12, spring: .snappy)
                            SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                        }
                    }

                VStack(spacing: Space.xs) {
                    Text(Brand.appName)
                        .font(.dsDisplay)
                        .foregroundStyle(Palette.onBrand)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)

                    Text(Brand.tagline)
                        .font(.dsHeadline)
                        .foregroundStyle(Palette.onBrand.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Space.xl)
                .offset(y: isSettled || reduceMotion ? 0 : 18)
                .opacity(isSettled ? 1 : 0)
                .animation(Motion.animation(Motion.gentle.delay(0.12), reduceMotion: reduceMotion), value: isSettled)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.Copy.Splash.accessibilityLabel)
        .onAppear {
            isSettled = true
            if !reduceMotion {
                popTrigger += 1
            }
        }
    }
}

/// Keyframe values for the logo "snap" once the cards land. Starts and ends at rest.
private struct SplashPop {
    var scale: CGFloat = 1.0
    var tilt: Double = 0
}

#Preview("Splash") {
    SplashView()
}
