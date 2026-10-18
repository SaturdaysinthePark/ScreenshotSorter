import SwiftUI
import UIKit

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

        Motion.perform(Motion.bouncy, reduceMotion: UIAccessibility.isReduceMotionEnabled) {
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
        Motion.perform(Motion.quick, reduceMotion: UIAccessibility.isReduceMotionEnabled) {
            isVisible = false
        }
        // Clear after animation
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !self.isVisible else { return }
            activeTooltip = nil
        }
    }
}

// MARK: - Tooltip View
/// On-brand hint bubble: Liquid Glass capsule with a brand-gradient icon badge
/// and a small pointer nub facing the anchored view.

struct TooltipView: View {
    let text: String
    let icon: String?
    let position: TooltipPosition

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
        HStack(spacing: Space.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.onBrand)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Palette.brandGradient))
                    .accessibilityHidden(true)
            }

            Text(text)
                .font(.dsCallout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, icon == nil ? Space.md : Space.xs)
        .padding(.trailing, Space.md)
        .padding(.vertical, Space.xs)
        .glassEffect(.regular.tint(Palette.brand.opacity(0.18)), in: .capsule)
        .overlay(alignment: nubAlignment) {
            TooltipNub()
                .fill(Palette.brand.opacity(0.85))
                .frame(width: 14, height: 7)
                .rotationEffect(.degrees(nubRotation))
                .offset(nubOffset)
                .accessibilityHidden(true)
        }
        .shadow(color: Palette.brand.opacity(0.18), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    // The nub points toward the view the tooltip is attached to.
    private var nubAlignment: Alignment {
        switch position {
        case .bottom: return .top
        case .top: return .bottom
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }

    private var nubRotation: Double {
        switch position {
        case .bottom: return 0
        case .top: return 180
        case .leading: return 90
        case .trailing: return -90
        }
    }

    private var nubOffset: CGSize {
        switch position {
        case .bottom: return CGSize(width: 0, height: -6)
        case .top: return CGSize(width: 0, height: 6)
        case .leading: return CGSize(width: 9, height: 0)
        case .trailing: return CGSize(width: -9, height: 0)
        }
    }
}

/// Small upward-pointing triangle.
private struct TooltipNub: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Tooltip Modifier

struct TooltipModifier: ViewModifier {
    let key: TooltipKey
    let text: String
    let icon: String?
    let position: TooltipView.TooltipPosition
    let showCondition: Bool

    @ObservedObject private var tooltipManager = TooltipManager.shared
    @State private var hasTriggered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: overlayAlignment) {
                if tooltipManager.activeTooltip == key && tooltipManager.isVisible {
                    TooltipView(text, icon: icon, position: position)
                        .transition(
                            reduceMotion
                                ? AnyTransition.opacity
                                : AnyTransition.asymmetric(
                                    insertion: AnyTransition.scale(scale: 0.85, anchor: transitionAnchor).combined(with: AnyTransition.opacity),
                                    removal: AnyTransition.opacity
                                )
                        )
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

    private var transitionAnchor: UnitPoint {
        switch position {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
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
            return Brand.Copy.Review.hint
        case .doubleTapToZoom:
            return "Double-tap to zoom in"
        case .dragToDismiss:
            return "Drag down to close"
        case .processScreenshots:
            return "Tap to organize your screenshots"
        case .undoAction:
            return "Made a mistake? Tap Undo"
        case .reviewBadges:
            return "Dashed chips are our best guesses"
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
        TooltipView(TooltipKey.swipeToReview.defaultText, icon: "hand.draw")

        TooltipView("Double-tap to zoom", icon: "hand.tap", position: .top)

        Button("Show Tooltip") {
            TooltipManager.shared.showTooltip(.swipeToReview)
        }
        .buttonStyle(.brand(.primary, size: .compact))
    }
    .padding()
    .background(Palette.canvas)
}
