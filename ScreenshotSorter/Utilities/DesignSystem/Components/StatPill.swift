import SwiftUI

// MARK: - Stat Pill
/// Icon + rolling number + label. Number changes roll with `.numericText()`.

struct StatPill: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Int, label: String, systemImage: String, tint: Color) {
        self.value = value
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: systemImage)
                .font(.dsHeadline)
                .foregroundStyle(Palette.onBrand)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tint))

            VStack(alignment: .leading, spacing: 0) {
                Text(value, format: .number)
                    .font(.dsTitle2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: value)
                Text(label)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .padding(.trailing, Space.xxs)
        .dsSurface(radius: Radius.lg, tint: tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

#Preview("Stat pills") {
    HStack {
        StatPill(value: 42, label: "Kept", systemImage: "heart.fill", tint: Palette.keep)
        StatPill(value: 7, label: "Tossed", systemImage: "trash.fill", tint: Palette.toss)
    }
    .padding()
}
