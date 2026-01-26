import SwiftUI

// MARK: - Tooltip Keys for One-Time Display
/// Identifiers for different tooltips to track which have been shown

enum TooltipKey: String, CaseIterable {
    case swipeToReview = "tooltip_swipe_to_review"
    case doubleTapToZoom = "tooltip_double_tap_zoom"
    case dragToDismiss = "tooltip_drag_to_dismiss"
    case processScreenshots = "tooltip_process_screenshots"
    case undoAction = "tooltip_undo_action"
    case reviewBadges = "tooltip_review_badges"

    var hasBeenShown: Bool {
        get { UserDefaults.standard.bool(forKey: rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: rawValue) }
    }

    mutating func markAsShown() {
        UserDefaults.standard.set(true, forKey: rawValue)
    }

    static func resetAll() {
        allCases.forEach { key in
            UserDefaults.standard.removeObject(forKey: key.rawValue)
        }
    }
}

// MARK: - Tooltip Manager

@MainActor
final class TooltipManager: ObservableObject {
    static let shared = TooltipManager()

    @Published var activeTooltip: TooltipKey?
    @Published var isVisible = false

    private var dismissTimer: Task<Void, Never>?

    private init() {}

    func showTooltip(_ key: TooltipKey, duration: TimeInterval = 3.0) {
        guard !UserDefaults.standard.bool(forKey: key.rawValue) else { return }

        dismissTimer?.cancel()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            activeTooltip = key
            isVisible = true
        }

        // Mark as shown
        UserDefaults.standard.set(true, forKey: key.rawValue)

        // Auto-dismiss
        dismissTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            isVisible = false
        }
        // Clear after animation
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            activeTooltip = nil
        }
    }
}

// MARK: - Tooltip View

struct TooltipView: View {
    let text: String
    let icon: String?
    let position: TooltipPosition

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum TooltipPosition {
        case top
        case bottom
        case leading
        case trailing
    }

    init(_ text: String, icon: String? = nil, position: TooltipPosition = .bottom) {
        self.text = text
        self.icon = icon
        self.position = position
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SemanticColor.info.gradient)
            }

            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(Color.cyan.opacity(0.15)), in: .capsule)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Tooltip Modifier

struct TooltipModifier: ViewModifier {
    let key: TooltipKey
    let text: String
    let icon: String?
    let position: TooltipView.TooltipPosition
    let showCondition: Bool

    @StateObject private var tooltipManager = TooltipManager.shared
    @State private var hasTriggered = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: overlayAlignment) {
                if tooltipManager.activeTooltip == key && tooltipManager.isVisible {
                    TooltipView(text, icon: icon, position: position)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .padding(tooltipPadding)
                        .onTapGesture {
                            tooltipManager.dismiss()
                        }
                }
            }
            .onChange(of: showCondition) { _, newValue in
                if newValue && !hasTriggered {
                    hasTriggered = true
                    tooltipManager.showTooltip(key)
                }
            }
            .onAppear {
                if showCondition && !hasTriggered {
                    hasTriggered = true
                    // Delay to let the view appear first
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        tooltipManager.showTooltip(key)
                    }
                }
            }
    }

    private var overlayAlignment: Alignment {
        switch position {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    private var tooltipPadding: EdgeInsets {
        switch position {
        case .top: return EdgeInsets(top: 0, leading: 0, bottom: 60, trailing: 0)
        case .bottom: return EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0)
        case .leading: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 60)
        case .trailing: return EdgeInsets(top: 0, leading: 60, bottom: 0, trailing: 0)
        }
    }
}

extension View {
    func tooltip(
        _ key: TooltipKey,
        text: String,
        icon: String? = nil,
        position: TooltipView.TooltipPosition = .bottom,
        showWhen condition: Bool = true
    ) -> some View {
        modifier(TooltipModifier(
            key: key,
            text: text,
            icon: icon,
            position: position,
            showCondition: condition
        ))
    }
}

// MARK: - Contextual Tooltip Content

extension TooltipKey {
    var defaultText: String {
        switch self {
        case .swipeToReview:
            return "Swipe left to delete, right to keep"
        case .doubleTapToZoom:
            return "Double-tap to zoom in"
        case .dragToDismiss:
            return "Drag down to close"
        case .processScreenshots:
            return "Tap to organize your screenshots"
        case .undoAction:
            return "Made a mistake? Tap Undo"
        case .reviewBadges:
            return "Badges show AI confidence level"
        }
    }

    var defaultIcon: String {
        switch self {
        case .swipeToReview:
            return "hand.draw"
        case .doubleTapToZoom:
            return "hand.tap"
        case .dragToDismiss:
            return "arrow.down"
        case .processScreenshots:
            return "wand.and.stars"
        case .undoAction:
            return "arrow.uturn.backward"
        case .reviewBadges:
            return "sparkles"
        }
    }
}

// MARK: - Preview

#Preview("Tooltips") {
    VStack(spacing: 40) {
        TooltipView("Swipe left to delete, right to keep", icon: "hand.draw")

        TooltipView("Double-tap to zoom", icon: "hand.tap", position: .top)

        Button("Show Tooltip") {
            TooltipManager.shared.showTooltip(.swipeToReview)
        }
        .buttonStyle(.borderedProminent)
    }
    .padding()
}
