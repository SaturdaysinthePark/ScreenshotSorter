import SwiftUI

// MARK: - Tag Chip
/// Rounded capsule label for categories/tags.
/// - Regular: soft tint fill, ink text, tinted icon.
/// - Suggested: dashed tinted outline + sparkle, signalling "tap to accept".
/// Becomes a squishy button when `action` is provided.

struct TagChip: View {
    let text: String
    let systemImage: String?
    let tint: Color
    let isSuggested: Bool
    let action: (() -> Void)?

    init(
        _ text: String,
        systemImage: String? = nil,
        tint: Color = Palette.brand,
        isSuggested: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.isSuggested = isSuggested
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) {
                chip
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
        } else {
            chip
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
        }
    }

    private var accessibilityText: String {
        isSuggested ? "Suggested: \(text)" : text
    }

    private var chip: some View {
        HStack(spacing: Space.xxs + 2) {
            if isSuggested {
                Image(systemName: "sparkles")
                    .imageScale(.small)
                    .foregroundStyle(tint)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.dsCaption)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs - 1)
        .background {
            if isSuggested {
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .background(Capsule(style: .continuous).fill(tint.opacity(0.06)))
            } else {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                    }
            }
        }
        .contentShape(Capsule(style: .continuous))
    }
}

#Preview("Tag chips") {
    VStack(spacing: 12) {
        TagChip("Receipts", systemImage: "receipt.fill", tint: CategoryGroup.workProductivity.color)
        TagChip("Memes", systemImage: "face.smiling.fill", tint: CategoryGroup.mediaEntertainment.color, isSuggested: true) {}
        TagChip("Food", systemImage: "fork.knife", tint: CategoryGroup.foodDrink.color) {}
    }
    .padding()
}
