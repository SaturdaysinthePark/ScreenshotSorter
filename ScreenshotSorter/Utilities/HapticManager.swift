import SwiftUI
import UIKit

// MARK: - Haptic Manager
/// Centralized haptic feedback system for consistent tactile responses
/// Respects user's Reduce Motion accessibility setting

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

    private init() {
        prepareGenerators()
    }

    // MARK: - Prepare Generators
    /// Pre-warm haptic generators for immediate response
    func prepareGenerators() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    // MARK: - Core Haptic Methods

    /// Light tap for subtle interactions (button taps, selections)
    func lightTap() {
        guard !isReduceMotionEnabled else { return }
        lightImpact.impactOccurred()
    }

    /// Medium tap for standard interactions
    func mediumTap() {
        guard !isReduceMotionEnabled else { return }
        mediumImpact.impactOccurred()
    }

    /// Heavy tap for significant actions (delete confirmation, etc.)
    func heavyTap() {
        guard !isReduceMotionEnabled else { return }
        heavyImpact.impactOccurred()
    }

    /// Soft tap for gentle feedback
    func softTap() {
        guard !isReduceMotionEnabled else { return }
        softImpact.impactOccurred()
    }

    /// Rigid tap for precise feedback
    func rigidTap() {
        guard !isReduceMotionEnabled else { return }
        rigidImpact.impactOccurred()
    }

    /// Selection changed feedback
    func selectionChanged() {
        guard !isReduceMotionEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    /// Success notification (green checkmark feedback)
    func success() {
        guard !isReduceMotionEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
    }

    /// Warning notification
    func warning() {
        guard !isReduceMotionEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Error notification (red X feedback)
    func error() {
        guard !isReduceMotionEnabled else { return }
        notificationGenerator.notificationOccurred(.error)
    }

    // MARK: - App-Specific Haptics

    /// Swipe left action (delete) - heavy impact
    func swipeDelete() {
        guard !isReduceMotionEnabled else { return }
        heavyImpact.impactOccurred()
    }

    /// Swipe right action (keep) - success notification
    func swipeKeep() {
        guard !isReduceMotionEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
    }

    /// Undo action feedback
    func undo() {
        guard !isReduceMotionEnabled else { return }
        mediumImpact.impactOccurred()
    }

    /// Pan boundary reached - light impact
    func panBoundary() {
        guard !isReduceMotionEnabled else { return }
        lightImpact.impactOccurred(intensity: 0.5)
    }

    /// Zoom boundary reached - soft impact
    func zoomBoundary() {
        guard !isReduceMotionEnabled else { return }
        softImpact.impactOccurred(intensity: 0.6)
    }

    /// Card flick/swipe threshold reached
    func swipeThresholdReached() {
        guard !isReduceMotionEnabled else { return }
        rigidImpact.impactOccurred(intensity: 0.7)
    }

    /// Processing complete
    func processingComplete() {
        guard !isReduceMotionEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
    }

    /// Button tap
    func buttonTap() {
        guard !isReduceMotionEnabled else { return }
        lightImpact.impactOccurred()
    }

    /// Navigation transition
    func navigate() {
        guard !isReduceMotionEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    // MARK: - Accessibility

    private var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
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
