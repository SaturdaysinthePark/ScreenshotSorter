import SwiftUI

// MARK: - Undo Toast View
/// Floating Liquid Glass toast with a draining countdown ring and a chunky Undo button.
/// The ring drains with a single linear animation (no per-frame timers);
/// the seconds label ticks once per second with a rolling number.
/// Give it a new `.id(...)` per action to restart the countdown.

struct UndoToastView: View {
    let message: String
    let systemImage: String?
    let tint: Color
    let duration: TimeInterval
    let onUndo: () -> Void

    @State private var ringProgress: CGFloat = 1.0
    @State private var remainingSeconds: Int
    @State private var hasUndone = false

    init(
        message: String,
        systemImage: String? = nil,
        tint: Color = Palette.brand,
        duration: TimeInterval = 5.0,
        onUndo: @escaping () -> Void
    ) {
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.duration = duration
        self.onUndo = onUndo
        self._remainingSeconds = State(initialValue: Int(ceil(duration)))
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            CountdownRing(
                progress: ringProgress,
                remainingSeconds: remainingSeconds,
                tint: tint,
                systemImage: systemImage
            )

            Text(message)
                .font(.dsHeadline)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                guard !hasUndone else { return }
                hasUndone = true
                onUndo()
            } label: {
                Label(Brand.Copy.Review.undo, systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.brand(.primary, size: .compact))
            .accessibilityHint(Brand.Copy.Toast.undoHint)
        }
        .padding(.vertical, Space.sm)
        .padding(.leading, Space.sm)
        .padding(.trailing, Space.sm)
        .dsCard(tint: tint, radius: Radius.xl)
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Brand.Copy.Toast.undoAccessibility(message, seconds: remainingSeconds))
        .task {
            await runCountdown()
        }
    }

    private func runCountdown() async {
        // One smooth linear drain for the ring (120Hz friendly, no timer).
        withAnimation(.linear(duration: duration)) {
            ringProgress = 0
        }

        let total: Int = Int(ceil(duration))
        guard total > 0 else { return }
        for second in stride(from: total - 1, through: 0, by: -1) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.snappy) {
                remainingSeconds = second
            }
        }
    }
}

// MARK: - Countdown Ring

struct CountdownRing: View {
    let progress: CGFloat
    let remainingSeconds: Int
    var tint: Color = Palette.brand
    var systemImage: String?

    private let ringSize: CGFloat = 40
    private let lineWidth: CGFloat = 4

    init(progress: CGFloat, remainingSeconds: Int, tint: Color = Palette.brand, systemImage: String? = nil) {
        self.progress = progress
        self.remainingSeconds = remainingSeconds
        self.tint = tint
        self.systemImage = systemImage
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(progress, 0.0001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(remainingSeconds)")
                .font(.dsCaption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(countsDown: true))
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .frame(width: ringSize, height: ringSize)
        .overlay(alignment: .bottomTrailing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.onBrand)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(tint))
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Undo Toast") {
    ZStack {
        Palette.canvas.ignoresSafeArea()

        VStack {
            Spacer()
            UndoToastView(message: "Tossed it", systemImage: "trash.fill", tint: Palette.toss) {
                print("Undo tapped")
            }
            .padding()
        }
    }
}
