import SwiftUI
import UIKit

// MARK: - Haptic Manager
/// Centralized haptic feedback for consistent tactile responses.
/// Haptics are NOT motion, so they intentionally ignore the Reduce Motion setting
/// (the system already honors the user's global "System Haptics" switch).

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    private var celebrationTask: Task<Void, Never>?

    private init() {
        prepareGenerators()
    }

    // MARK: - Prepare Generators
    /// Pre-warm haptic generators for immediate response.
    func prepareGenerators() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        softImpact.prepare()
        rigidImpact.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    /// Call when a drag begins so the threshold/commit haptics fire with no latency.
    func prepareForSwipe() {
        rigidImpact.prepare()
        heavyImpact.prepare()
        notificationGenerator.prepare()
    }

    // MARK: - Core Haptic Methods

    /// Light tap for subtle interactions (button taps, selections).
    func lightTap() {
        lightImpact.impactOccurred()
    }

    /// Medium tap for standard interactions.
    func mediumTap() {
        mediumImpact.impactOccurred()
    }

    /// Heavy tap for significant actions (delete confirmation, etc.).
    func heavyTap() {
        heavyImpact.impactOccurred()
    }

    /// Soft tap for gentle feedback.
    func softTap() {
        softImpact.impactOccurred()
    }

    /// Rigid tap for precise feedback.
    func rigidTap() {
        rigidImpact.impactOccurred()
    }

    /// Selection changed feedback.
    func selectionChanged() {
        selectionGenerator.selectionChanged()
    }

    /// Success notification.
    func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    /// Warning notification.
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Error notification.
    func error() {
        notificationGenerator.notificationOccurred(.error)
    }

    // MARK: - App-Specific Haptics

    /// Swipe left action (toss) — heavy, decisive thunk.
    func swipeDelete() {
        heavyImpact.impactOccurred(intensity: 0.9)
    }

    /// Swipe right action (keep) — crisp success.
    func swipeKeep() {
        notificationGenerator.notificationOccurred(.success)
    }

    /// Card filed into a category (up-swipe).
    func sortInto() {
        mediumImpact.impactOccurred(intensity: 0.8)
    }

    /// Card snapped back to the deck without committing.
    func cardReturn() {
        softImpact.impactOccurred(intensity: 0.5)
    }

    /// Undo action feedback.
    func undo() {
        mediumImpact.impactOccurred()
    }

    /// Pan boundary reached.
    func panBoundary() {
        lightImpact.impactOccurred(intensity: 0.5)
    }

    /// Zoom boundary reached.
    func zoomBoundary() {
        softImpact.impactOccurred(intensity: 0.6)
    }

    /// Card drag crossed the commit threshold (fire once per crossing).
    func swipeThresholdReached() {
        rigidImpact.impactOccurred(intensity: 0.75)
    }

    /// Card drag moved back below the commit threshold.
    func swipeThresholdLeft() {
        lightImpact.impactOccurred(intensity: 0.4)
    }

    /// Processing complete.
    func processingComplete() {
        notificationGenerator.notificationOccurred(.success)
    }

    /// Button tap.
    func buttonTap() {
        lightImpact.impactOccurred()
    }

    /// Navigation transition.
    func navigate() {
        selectionGenerator.selectionChanged()
    }

    /// Onboarding / pager page change.
    func pageTurn() {
        selectionGenerator.selectionChanged()
    }

    /// Celebration: success followed by a short sparkle of light taps (matches confetti).
    func celebrate() {
        notificationGenerator.notificationOccurred(.success)
        celebrationTask?.cancel()
        celebrationTask = Task { @MainActor [weak self] in
            let intensities: [CGFloat] = [0.7, 0.5, 0.35]
            for intensity in intensities {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                self?.lightImpact.impactOccurred(intensity: intensity)
            }
        }
    }
}

// MARK: - View Modifier for Haptic Feedback

struct HapticFeedbackModifier: ViewModifier {
    let type: HapticType
    let trigger: Bool

    enum HapticType {
        case light
        case medium
        case heavy
        case success
        case error
        case warning
        case selection
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, newValue in
                if newValue {
                    triggerHaptic()
                }
            }
    }

    private func triggerHaptic() {
        switch type {
        case .light:
            HapticManager.shared.lightTap()
        case .medium:
            HapticManager.shared.mediumTap()
        case .heavy:
            HapticManager.shared.heavyTap()
        case .success:
            HapticManager.shared.success()
        case .error:
            HapticManager.shared.error()
        case .warning:
            HapticManager.shared.warning()
        case .selection:
            HapticManager.shared.selectionChanged()
        }
    }
}

extension View {
    func hapticFeedback(_ type: HapticFeedbackModifier.HapticType, trigger: Bool) -> some View {
        modifier(HapticFeedbackModifier(type: type, trigger: trigger))
    }
}
