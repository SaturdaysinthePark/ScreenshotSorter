import SwiftUI

// MARK: - Review Banner
/// "N screenshots waiting for a verdict" — brand-tinted glass card with a bouncing icon and one CTA.

struct ReviewBannerView: View {
    let unreviewedCount: Int
    let isProcessing: Bool
    let onReviewTapped: () -> Void
    let onDismiss: () -> Void

    init(
        unreviewedCount: Int,
        isProcessing: Bool,
        onReviewTapped: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.unreviewedCount = unreviewedCount
        self.isProcessing = isProcessing
        self.onReviewTapped = onReviewTapped
        self.onDismiss = onDismiss
    }

    var body: some View {
        BannerCard(
            systemImage: "rectangle.stack.fill",
            tint: Palette.brand,
            title: Brand.Copy.Banners.reviewTitle(unreviewedCount),
            subtitle: isProcessing ? Brand.Copy.Banners.reviewSubtitleProcessing : Brand.Copy.Banners.reviewSubtitle,
            ctaTitle: Brand.Copy.Banners.reviewCTA,
            ctaSystemImage: "hand.draw.fill",
            dismissLabel: Brand.Copy.Banners.later,
            onCTA: onReviewTapped,
            onDismiss: onDismiss
        ) {
            if isProcessing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Palette.brand)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.md)
    }
}

#Preview("Review banner") {
    VStack(spacing: 20) {
        ReviewBannerView(unreviewedCount: 24, isProcessing: false, onReviewTapped: {}, onDismiss: {})
        ReviewBannerView(unreviewedCount: 1, isProcessing: true, onReviewTapped: {}, onDismiss: {})
    }
    .frame(maxHeight: .infinity)
    .background(Palette.canvas)
}
