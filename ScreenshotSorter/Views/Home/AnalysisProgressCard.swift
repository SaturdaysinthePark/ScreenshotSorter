import SwiftUI

/// Live "sorting" card: animated progress, throughput, deep-pass status, pause/resume.
struct AnalysisProgressCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var progress: AnalysisProgress { model.progress }

    var body: some View {
        let total = model.library.count
        let analyzed = model.library.analyzedCount
        let fraction = total > 0 ? Double(analyzed) / Double(total) : 0
        let isFastPhase = progress.fastRemaining > 0

        VStack(alignment: .leading, spacing: Space.sm) {
            if dynamicTypeSize.isAccessibilitySize {
                // Text gets the full width; side by side it would wrap mid-word.
                HStack(spacing: Space.sm) {
                    statusIcon
                    Spacer(minLength: 0)
                    pauseButton
                }
                labels(analyzed: analyzed, total: total, isFastPhase: isFastPhase)
            } else {
                HStack(spacing: Space.sm) {
                    statusIcon
                    labels(analyzed: analyzed, total: total, isFastPhase: isFastPhase)
                    Spacer(minLength: 0)
                    pauseButton
                }
            }

            DSProgressBar(progress: isFastPhase ? fraction : deepFraction)
                .dsAnimation(Motion.gentle, value: fraction)
        }
        .padding(Space.md)
        .dsCard(tint: Palette.brand)
        .accessibilityElement(children: .contain)
    }

    private var statusIcon: some View {
        Image(systemName: progress.isPaused ? "pause.circle.fill" : "wand.and.stars")
            .font(.dsTitle2)
            .foregroundStyle(Palette.brand)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !progress.isPaused && !reduceMotion)
            .frame(width: 36)
    }

    private func labels(analyzed: Int, total: Int, isFastPhase: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline(analyzed: analyzed, total: total, isFastPhase: isFastPhase))
                .font(.dsHeadline)
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            if let detail = detailLine {
                Text(detail)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.inkSecondary)
                    .contentTransition(.opacity)
            }
        }
    }

    private var pauseButton: some View {
        Button {
            HapticManager.shared.lightTap()
            Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
                model.togglePause()
            }
        } label: {
            Image(systemName: progress.isPaused ? "play.fill" : "pause.fill")
                .font(.dsHeadline)
                .frame(width: 40, height: 40)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .accessibilityLabel(progress.isPaused ? Brand.Copy.Analysis.resumeLabel : Brand.Copy.Analysis.pauseLabel)
    }

    private var deepFraction: Double {
        let done = Double(progress.deepCompleted)
        let remaining = Double(progress.deepRemaining)
        guard done + remaining > 0 else { return 1 }
        return done / (done + remaining)
    }

    private func headline(analyzed: Int, total: Int, isFastPhase: Bool) -> String {
        if progress.isPaused { return Brand.Copy.Analysis.paused }
        if isFastPhase { return Brand.Copy.Analysis.sorting(analyzed, total) }
        return Brand.Copy.Analysis.reading(progress.deepRemaining)
    }

    private var detailLine: String? {
        if progress.isPaused { return nil }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return Brand.Copy.Analysis.lowPowerHint }
        let speed = Brand.Copy.Analysis.speed(progress.itemsPerSecond)
        return speed.isEmpty ? nil : speed
    }
}
