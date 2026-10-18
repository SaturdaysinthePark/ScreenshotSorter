import SwiftUI

/// "Suggested for you": up to three AI-named collections waiting for Keep / Not for me.
struct SmartSuggestionsSection: View {
    let zoomNamespace: Namespace.ID

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                ShelfHeader(title: Brand.Copy.Smart.sectionTitle, systemImage: "sparkles", tint: Palette.brand,
                            count: model.library.suggestedSmartCollections.count)
                Text(Brand.Copy.Smart.sectionSubtitle)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, Space.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Space.sm) {
                    ForEach(model.library.suggestedSmartCollections) { suggestion in
                        SuggestionCard(suggestion: suggestion, zoomNamespace: zoomNamespace)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Space.gutter)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

private struct SuggestionCard: View {
    let suggestion: SmartCollection
    let zoomNamespace: Namespace.ID

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let kind = CollectionKind.smart(id: suggestion.id)
        let screenshots = model.library.screenshots(for: kind)
        VStack(alignment: .leading, spacing: Space.sm) {
            NavigationLink(value: kind) {
                HStack(spacing: Space.sm) {
                    MosaicThumbnail(screenshots: Array(screenshots.prefix(4)), tint: Palette.brand, size: 72)
                        .matchedTransitionSource(id: kind.id, in: zoomNamespace)
                    VStack(alignment: .leading, spacing: 2) {
                        Label(suggestion.name, systemImage: suggestion.symbol)
                            .font(.dsHeadline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                        Text(Brand.Copy.Smart.count(screenshots.count))
                            .font(.dsCaption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: Space.xs) {
                Button {
                    Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
                        model.keepSuggestion(suggestion.id)
                    }
                } label: {
                    Label(Brand.Copy.Smart.keep, systemImage: "checkmark")
                }
                .buttonStyle(.brand(.primary, size: .compact))

                Button {
                    HapticManager.shared.lightTap()
                    Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
                        model.dismissSuggestion(suggestion.id)
                    }
                } label: {
                    Text(Brand.Copy.Smart.dismiss)
                }
                .buttonStyle(.brand(.ghost, size: .compact))
            }
        }
        .padding(Space.md)
        .frame(width: 290)
        .dsSurface(radius: Radius.lg, tint: Palette.brand)
    }
}
