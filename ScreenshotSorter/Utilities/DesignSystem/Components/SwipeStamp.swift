import SwiftUI

// MARK: - Swipe Stamp
/// Rubber-stamp label ("KEEP" / "TOSS" / "SORT") that fades & scales in with drag progress.

struct SwipeStamp: View {
    enum Kind {
        case keep
        case toss
        case sort

        var text: String {
            switch self {
            case .keep: return Brand.Copy.Review.keepStamp
            case .toss: return Brand.Copy.Review.tossStamp
            case .sort: return Brand.Copy.Review.sortStamp
            }
        }

        var color: Color {
            switch self {
            case .keep: return Palette.keep
            case .toss: return Palette.toss
            case .sort: return Palette.brand
            }
        }

        var systemImage: String {
            switch self {
            case .keep: return "heart.fill"
            case .toss: return "trash.fill"
            case .sort: return "tray.and.arrow.down.fill"
            }
        }

        var tilt: Double {
            switch self {
            case .keep: return -14
            case .toss: return 14
            case .sort: return -4
            }
        }
    }

    let kind: Kind
    /// 0...1 — how close the drag is to committing.
    let progress: Double
    var compact: Bool = false

    var body: some View {
        let clamped: Double = min(max(progress, 0), 1)
        HStack(spacing: Space.xs) {
            Image(systemName: kind.systemImage)
            Text(kind.text)
                .tracking(compact ? 1 : 2)
        }
        .font(compact ? Font.dsHeadline : Font.dsTitle.weight(.black))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundStyle(kind.color)
        .padding(.horizontal, compact ? Space.sm : Space.md)
        .padding(.vertical, compact ? Space.xxs + 2 : Space.xs)
        .background {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surface.opacity(0.92))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(kind.color, lineWidth: compact ? 3 : 4)
        }
        .rotationEffect(.degrees(kind.tilt))
        .scaleEffect(1.35 - 0.35 * clamped)
        .opacity(clamped)
        .accessibilityHidden(true)
    }
}

#Preview("Stamps") {
    VStack(spacing: 40) {
        SwipeStamp(kind: .keep, progress: 1)
        SwipeStamp(kind: .toss, progress: 0.6)
        SwipeStamp(kind: .sort, progress: 1, compact: true)
    }
    .padding()
}
