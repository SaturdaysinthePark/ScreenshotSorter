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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One compact row: home shows a single next step, and it shouldn't push the collections off screen.
    /// At accessibility sizes the text gets the full width and the button its own line.
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .top) {
                        labels
                        Spacer(minLength: 0)
                        dismissButton
                    }
                    reviewButton.frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: Space.sm) {
                    icon
                    labels
                    Spacer(minLength: 0)
                    reviewButton
                    dismissButton
                }
            }
        }
        .padding(Space.sm)
        .dsSurface(radius: Radius.lg, tint: Palette.brand)
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        Image(systemName: "rectangle.stack.fill")
            .font(.dsHeadline)
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Palette.brand.gradient, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .accessibilityHidden(true)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Brand.Copy.Banners.reviewTitle(unreviewedCount))
                .font(.dsHeadline)
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text(isProcessing ? Brand.Copy.Banners.reviewSubtitleProcessing : Brand.Copy.Banners.reviewSubtitle)
                .font(.dsCaption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var reviewButton: some View {
        Button(action: onReviewTapped) {
            Text(Brand.Copy.Banners.reviewCTA)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        }
        .buttonStyle(.brand(.primary, size: .compact))
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.dsCaption.weight(.bold))
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Brand.Copy.Banners.later)
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
