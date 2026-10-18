import SwiftUI
import UIKit

// MARK: - Collage Thumbnail Stack
/// Up to three thumbnails fanned like a little deck of cards.
/// Missing images (`nil`) render as tinted placeholders, so it always looks intentional.

struct CollageThumbnailStack: View {
    let images: [UIImage?]
    var tint: Color = Palette.brand
    var cardWidth: CGFloat = 56
    var maxCards: Int = 3

    init(images: [UIImage?], tint: Color = Palette.brand, cardWidth: CGFloat = 56, maxCards: Int = 3) {
        self.images = images
        self.tint = tint
        self.cardWidth = cardWidth
        self.maxCards = maxCards
    }

    private var cardHeight: CGFloat { cardWidth * 1.6 }

    private var slots: [Int] {
        let count: Int = max(1, min(maxCards, images.count))
        return Array(0..<count)
    }

    var body: some View {
        let count: Int = slots.count
        ZStack {
            ForEach(slots.reversed(), id: \.self) { index in
                thumbnail(at: index)
                    .rotationEffect(.degrees(rotation(for: index, count: count)))
                    .offset(x: xOffset(for: index, count: count), y: CGFloat(index) * 2)
                    .zIndex(Double(count - index))
            }
        }
        .frame(width: cardWidth * 1.6, height: cardHeight * 1.12)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func thumbnail(at index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        let image: UIImage? = index < images.count ? images[index] : nil
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                shape.fill(tint.opacity(0.22 + 0.12 * Double(index)))
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Palette.surface, lineWidth: 2) }
        .shadow(color: Color.black.opacity(0.14), radius: 4, x: 0, y: 2)
    }

    private func rotation(for index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        switch index {
        case 0: return 0
        case 1: return -9
        default: return 9
        }
    }

    private func xOffset(for index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        switch index {
        case 0: return 0
        case 1: return -cardWidth * 0.28
        default: return cardWidth * 0.28
        }
    }
}

#Preview("Collage") {
    HStack(spacing: 24) {
        CollageThumbnailStack(images: [nil, nil, nil], tint: CategoryGroup.foodDrink.color)
        CollageThumbnailStack(images: [nil], tint: CategoryGroup.communication.color)
    }
    .padding()
}
