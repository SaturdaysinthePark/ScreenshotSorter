import SwiftUI
import UIKit

// MARK: - Skeleton Loading View
/// Shimmer animation for loading thumbnails with smooth crossfade
/// Respects user's Reduce Motion accessibility setting

struct SkeletonView: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(width: CGFloat = 100, height: CGFloat = 100, cornerRadius: CGFloat = 12) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .overlay {
                if !reduceMotion {
                    shimmerOverlay
                }
            }
            .onAppear {
                if !reduceMotion {
                    withAnimation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        isAnimating = true
                    }
                }
            }
    }

    private var shimmerOverlay: some View {
        GeometryReader { geometry in
            let gradientWidth = geometry.size.width * 0.6
            let startX = isAnimating ? geometry.size.width + gradientWidth : -gradientWidth

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.4),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: gradientWidth)
                .offset(x: startX)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Skeleton Modifier
/// Apply shimmer skeleton effect to any view

struct SkeletonModifier: ViewModifier {
    let isLoading: Bool
    let cornerRadius: CGFloat

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isLoading {
            content
                .redacted(reason: .placeholder)
                .overlay {
                    if !reduceMotion {
                        shimmerOverlay
                    }
                }
                .onAppear {
                    if !reduceMotion {
                        withAnimation(
                            .linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                        ) {
                            isAnimating = true
                        }
                    }
                }
        } else {
            content
        }
    }

    private var shimmerOverlay: some View {
        GeometryReader { geometry in
            let gradientWidth = geometry.size.width * 0.6
            let startX = isAnimating ? geometry.size.width + gradientWidth : -gradientWidth

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: gradientWidth)
                .offset(x: startX)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func skeleton(isLoading: Bool, cornerRadius: CGFloat = 12) -> some View {
        modifier(SkeletonModifier(isLoading: isLoading, cornerRadius: cornerRadius))
    }
}

// MARK: - Image Skeleton View
/// Specifically for image loading with skeleton placeholder

struct ImageSkeletonView: View {
    let image: UIImage?
    let aspectRatio: CGFloat
    let cornerRadius: CGFloat

    @State private var showImage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(image: UIImage?, aspectRatio: CGFloat = 1.0, cornerRadius: CGFloat = 12) {
        self.image = image
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Skeleton placeholder
                if image == nil {
                    SkeletonView(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        cornerRadius: cornerRadius
                    )
                }

                // Actual image with crossfade
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .opacity(showImage ? 1 : 0)
                        .onAppear {
                            if reduceMotion {
                                showImage = true
                            } else {
                                withAnimation(.easeIn(duration: 0.25)) {
                                    showImage = true
                                }
                            }
                        }
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

// MARK: - Thumbnail Skeleton Grid Item
/// For use in collection grids

struct ThumbnailSkeletonView: View {
    let size: CGFloat

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(size: CGFloat = 100) {
        self.size = size
    }

    var body: some View {
        SkeletonView(
            width: size,
            height: size,
            cornerRadius: 8
        )
    }
}

// MARK: - Preview

#Preview("Skeleton Loading") {
    VStack(spacing: 20) {
        SkeletonView(width: 200, height: 150)

        ThumbnailSkeletonView(size: 80)

        HStack(spacing: 12) {
            ForEach(0..<4) { _ in
                ThumbnailSkeletonView(size: 60)
            }
        }
    }
    .padding()
}
