import SwiftUI

struct UnprocessedBannerView: View {
    let unprocessedCount: Int
    let onProcessTapped: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(SemanticColor.warning.gradient)

                    Text("\(unprocessedCount) screenshot\(unprocessedCount == 1 ? "" : "s") to process")
                        .font(.headline)
                }

                Text("Continue organizing your library")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: onProcessTapped) {
                    Text("Process Now")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.subheadline)
                        .frame(width: 80)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(16)
        .tintedGlass(color: .orange, cornerRadius: 12)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unprocessedCount) screenshots to process")
        .accessibilityHint("Contains buttons to process now or dismiss")
    }
}
