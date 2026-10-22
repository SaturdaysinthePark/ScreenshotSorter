import SwiftUI

/// Live "sorting" card: animated progress, throughput, deep-pass / language-model status,
/// iCloud screenshots waiting for Wi-Fi, pause/resume.
struct AnalysisProgressCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var progress: AnalysisProgress { model.progress }

    private enum Phase { case paused, sorting, reading, polishing, waiting }

    private var phase: Phase {
        if progress.isPaused { return .paused }
        if progress.fastRemaining > 0 { return .sorting }
        if progress.deepRemaining > 0 { return .reading }
        if progress.modelRemaining > 0 { return .polishing }
        // Only shown in this state because iCloud screenshots are waiting for Wi-Fi
        return .waiting
    }

    var body: some View {
        let total = model.library.count
        let analyzed = model.library.analyzedCount
        let fraction = total > 0 ? Double(analyzed) / Double(total) : 0
        let isFastPhase = progress.fastRemaining > 0

        VStack(alignment: .leading, spacing: Space.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                // Text gets the full width; side by side it would wrap mid-word.
                HStack(spacing: Space.sm) {
                    statusIcon
                    Spacer(minLength: 0)
                    if phase != .waiting { pauseButton }
                }
                labels(analyzed: analyzed, total: total, isFastPhase: isFastPhase)
            } else {
                HStack(spacing: Space.sm) {
                    statusIcon
                    labels(analyzed: analyzed, total: total, isFastPhase: isFastPhase)
                    Spacer(minLength: 0)
                    if phase != .waiting { pauseButton }
                }
            }

            DSProgressBar(progress: barFraction(analyzedFraction: fraction))
                .dsAnimation(Motion.gentle, value: fraction)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .dsCard(tint: Palette.brand)
        .accessibilityElement(children: .contain)
    }

    private var statusIcon: some View {
        Image(systemName: phase == .paused ? "pause.circle.fill" : phase == .waiting ? "icloud.and.arrow.down" : "wand.and.stars")
            .font(.dsHeadline)
            .foregroundStyle(Palette.brand)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: phase != .paused && phase != .waiting && !reduceMotion)
            .frame(width: 28)
    }

    private func labels(analyzed: Int, total: Int, isFastPhase: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline(analyzed: analyzed, total: total, isFastPhase: isFastPhase))
                .font(.dsCallout.weight(.semibold))
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
                .font(.dsCaption.weight(.bold))
                .frame(width: 32, height: 32)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .accessibilityLabel(progress.isPaused ? Brand.Copy.Analysis.resumeLabel : Brand.Copy.Analysis.pauseLabel)
    }

    private func barFraction(analyzedFraction: Double) -> Double {
        func share(_ done: Int, _ remaining: Int) -> Double {
            done + remaining > 0 ? Double(done) / Double(done + remaining) : 1
        }
        switch phase {
        case .sorting, .paused, .waiting: return analyzedFraction
        case .reading: return share(progress.deepCompleted, progress.deepRemaining)
        case .polishing: return share(progress.modelCompleted, progress.modelRemaining)
        }
    }

    private func headline(analyzed: Int, total: Int, isFastPhase: Bool) -> String {
        switch phase {
        case .paused: return Brand.Copy.Analysis.paused
        case .sorting: return Brand.Copy.Analysis.sorting(analyzed, total)
        case .reading: return Brand.Copy.Analysis.reading(progress.deepRemaining)
        case .polishing: return Brand.Copy.Analysis.polishing(progress.modelRemaining)
        case .waiting: return Brand.Copy.Analysis.waitingForWiFi(progress.waitingForNetwork)
        }
    }

    private var detailLine: String? {
        switch phase {
        case .paused: return nil
        case .waiting: return Brand.Copy.Analysis.waitingDetail
        default: break
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return Brand.Copy.Analysis.lowPowerHint }
        var parts: [String] = []
        let speed = Brand.Copy.Analysis.speed(progress.itemsPerSecond)
        if !speed.isEmpty { parts.append(speed) }
        if progress.waitingForNetwork > 0 { parts.append(Brand.Copy.Analysis.waitingForWiFi(progress.waitingForNetwork)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
