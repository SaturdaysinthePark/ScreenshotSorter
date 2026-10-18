import SwiftUI

// MARK: - Unprocessed Banner
/// "N screenshots still unsorted" — warm-tinted glass card with a wiggling wand and one CTA.

struct UnprocessedBannerView: View {
    let unprocessedCount: Int
    let onProcessTapped: () -> Void
    let onDismiss: () -> Void

    init(
        unprocessedCount: Int,
        onProcessTapped: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.unprocessedCount = unprocessedCount
        self.onProcessTapped = onProcessTapped
        self.onDismiss = onDismiss
    }

    var body: some View {
        BannerCard(
            systemImage: "wand.and.stars",
            tint: Palette.brandSecondary,
            title: Brand.Copy.Banners.unprocessedTitle(unprocessedCount),
            subtitle: Brand.Copy.Banners.unprocessedSubtitle,
            ctaTitle: Brand.Copy.Banners.unprocessedCTA,
            ctaSystemImage: "sparkles",
            dismissLabel: Brand.Copy.Banners.dismiss,
            onCTA: onProcessTapped,
            onDismiss: onDismiss
        )
        .padding(.horizontal, Space.md)
    }
}

#Preview("Unprocessed banner") {
    UnprocessedBannerView(unprocessedCount: 12, onProcessTapped: {}, onDismiss: {})
        .frame(maxHeight: .infinity)
        .background(Palette.canvas)
}
