import SwiftUI

// MARK: - Skeleton View
/// Placeholder block with a soft shimmer sweep. Colors adapt to light/dark mode;
/// under Reduce Motion the shimmer is replaced by a static fill.

struct SkeletonView: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0

    init(width: CGFloat = 100, height: CGFloat = 100, cornerRadius: CGFloat = 12) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseColor)
            .frame(width: width, height: height)
            .overlay {
                if !reduceMotion {
                    shimmer
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                phase = 0
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }

    private var baseColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Palette.ink.opacity(0.07)
    }

    private var highlightColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.65)
    }

    /// A diagonal highlight band swept across with a transform-only animation.
    private var shimmer: some View {
        let bandWidth: CGFloat = max(width * 0.6, 60)
        let travel: CGFloat = width + bandWidth * 2
        return LinearGradient(
            colors: [Color.clear, highlightColor, Color.clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: bandWidth, height: height * 1.4)
        .rotationEffect(.degrees(16))
        .offset(x: -width / 2 - bandWidth + travel * phase)
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview("Skeleton Loading") {
    VStack(spacing: 20) {
        SkeletonView(width: 200, height: 150)
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonView(width: 60, height: 60, cornerRadius: 10)
            }
        }
    }
    .padding()
    .background(Palette.canvas)
}
