import SwiftUI

struct ReviewBannerView: View {
    let unreviewedCount: Int
    let isProcessing: Bool
    let onReviewTapped: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SemanticColor.primary.gradient)

                    Text("\(unreviewedCount) screenshot\(unreviewedCount == 1 ? "" : "s") to review")
                        .font(.headline)
                }

                if isProcessing {
                    Text("Processing... More may be added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Keep your library organized")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: onReviewTapped) {
                    Text("Review Now")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Button(action: onDismiss) {
                    Text("Later")
                        .font(.subheadline)
                        .frame(width: 80)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(16)
        .tintedGlass(color: .blue, cornerRadius: 12)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unreviewedCount) screenshots to review")
        .accessibilityHint("Contains buttons to review now or dismiss")
    }
}
