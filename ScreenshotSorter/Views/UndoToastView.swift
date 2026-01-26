import SwiftUI

// MARK: - Undo Toast View
/// Enhanced toast with circular countdown timer and prominent undo button

struct UndoToastView: View {
    let message: String
    let duration: TimeInterval
    let onUndo: () -> Void

    @State private var remainingTime: TimeInterval
    @State private var progress: CGFloat = 1.0
    @State private var timer: Timer?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(message: String, duration: TimeInterval = 5.0, onUndo: @escaping () -> Void) {
        self.message = message
        self.duration = duration
        self.onUndo = onUndo
        self._remainingTime = State(initialValue: duration)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Circular countdown
            CountdownRing(
                progress: progress,
                remainingSeconds: Int(ceil(remainingTime))
            )

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Text("\(Int(ceil(remainingTime)))s remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Prominent Undo button
            Button(action: {
                HapticManager.shared.undo()
                stopTimer()
                onUndo()
            }) {
                Text("Undo")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(SemanticColor.primary.gradient)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo action")
            .accessibilityHint("Double-tap to undo the last action")
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            stopTimer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). \(Int(ceil(remainingTime))) seconds to undo")
    }

    private func startCountdown() {
        let startTime = Date()
        let updateInterval: TimeInterval = 0.05 // 50ms for smooth animation

        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, duration - elapsed)

            withAnimation(reduceMotion ? nil : .linear(duration: updateInterval)) {
                remainingTime = remaining
                progress = remaining / duration
            }

            if remaining <= 0 {
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Countdown Ring

struct CountdownRing: View {
    let progress: CGFloat
    let remainingSeconds: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ringSize: CGFloat = 44
    private let lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color(.systemGray4), lineWidth: lineWidth)
                .frame(width: ringSize, height: ringSize)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.05), value: progress)

            // Seconds number
            Text("\(remainingSeconds)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(progressColor)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: remainingSeconds)
        }
    }

    private var progressColor: Color {
        if progress > 0.5 {
            return .green
        } else if progress > 0.25 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Enhanced Undo Toast (Alternative Style)

struct EnhancedUndoToast: View {
    let action: String  // "deleted" or "kept"
    let duration: TimeInterval
    let onUndo: () -> Void

    @State private var remainingTime: TimeInterval
    @State private var progress: CGFloat = 1.0
    @State private var timer: Timer?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDelete: Bool { action == "deleted" }

    init(action: String, duration: TimeInterval = 5.0, onUndo: @escaping () -> Void) {
        self.action = action
        self.duration = duration
        self.onUndo = onUndo
        self._remainingTime = State(initialValue: duration)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Action icon with color
            ZStack {
                Circle()
                    .fill(isDelete ? SemanticColor.danger.lightBackground : SemanticColor.success.lightBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: isDelete ? "trash.fill" : "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isDelete ? .red : .green)
            }

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot \(action)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 4)

                        Capsule()
                            .fill(progressGradient)
                            .frame(width: geometry.size.width * progress, height: 4)
                            .animation(reduceMotion ? nil : .linear(duration: 0.05), value: progress)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)

            // Undo button
            Button(action: {
                HapticManager.shared.undo()
                stopTimer()
                onUndo()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .bold))
                    Text("Undo")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(SemanticColor.primary.gradient)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private var progressGradient: LinearGradient {
        if progress > 0.5 {
            return SemanticColor.success.horizontalGradient
        } else if progress > 0.25 {
            return SemanticColor.warning.horizontalGradient
        } else {
            return SemanticColor.danger.horizontalGradient
        }
    }

    private func startCountdown() {
        let startTime = Date()
        let updateInterval: TimeInterval = 0.05

        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, duration - elapsed)

            withAnimation(reduceMotion ? nil : .linear(duration: updateInterval)) {
                remainingTime = remaining
                progress = remaining / duration
            }

            if remaining <= 0 {
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Preview

#Preview("Undo Toast") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            UndoToastView(message: "Screenshot deleted") {
                print("Undo tapped")
            }
        }
    }
}

#Preview("Enhanced Undo Toast") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            EnhancedUndoToast(action: "deleted") {
                print("Undo tapped")
            }
        }
    }
}
