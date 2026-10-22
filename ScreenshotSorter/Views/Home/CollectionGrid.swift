import SwiftUI

/// Home's collections: one two-column grid, biggest topics first, app collections after them.
/// Shows the first `collapsedCount` until "Show all" so a big library doesn't open on a wall of tiles.
struct CollectionGrid: View {
    let collections: [ScreenshotCollection]
    let zoomNamespace: Namespace.ID
    var onDelete: ((CollectionKind) -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showAll = false
    @State private var showNew = false

    /// Six rows on a phone: enough to see what was found, short enough to scan
    static let collapsedCount = 12

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Space.sm, alignment: .top), count: count)
    }

    private var visible: [ScreenshotCollection] {
        showAll ? collections : Array(collections.prefix(CollectionGrid.collapsedCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text(Brand.Copy.Home.collectionsTitle)
                    .font(.dsTitle2)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    HapticManager.shared.lightTap()
                    showNew = true
                } label: {
                    Label(Brand.Copy.NewCollection.newButton, systemImage: "plus")
                }
                .buttonStyle(.brand(.secondary, size: .compact))
                .accessibilityLabel(Brand.Copy.NewCollection.title)
            }

            LazyVGrid(columns: columns, spacing: Space.md) {
                ForEach(visible) { collection in
                    NavigationLink(value: collection.kind) {
                        CollectionTile(collection: collection, newCount: model.newCount(for: collection.kind),
                                       zoomNamespace: zoomNamespace)
                    }
                    .pressable()
                    .contextMenu {
                        if let onDelete, case .smart = collection.kind {
                            Button(role: .destructive) { onDelete(collection.kind) } label: {
                                Label(Brand.Copy.Smart.delete, systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if collections.count > CollectionGrid.collapsedCount {
                Button {
                    HapticManager.shared.lightTap()
                    Motion.perform(Motion.snappy, reduceMotion: reduceMotion) { showAll.toggle() }
                } label: {
                    Text(showAll ? Brand.Copy.Home.showFewer : Brand.Copy.Home.showAll(collections.count))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.brand(.secondary, size: .compact))
                .padding(.top, Space.xs)
            }
        }
        .sheet(isPresented: $showNew) {
            NewCollectionSheet()
        }
    }
}

/// A collection as a fanned stack of its newest screenshots, its name, and its size (or what's new).
struct CollectionTile: View {
    let collection: ScreenshotCollection
    var newCount: Int?
    let zoomNamespace: Namespace.ID

    private var tint: Color {
        if case .category(let category) = collection.kind { return category.color }
        return Palette.brandSecondary
    }

    private var countText: String {
        if let newCount, newCount > 0 { return Brand.Copy.Home.newSinceVisit(newCount) }
        return Brand.screenshots(collection.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            StackCover(screenshots: Array(collection.screenshots.prefix(3)), tint: tint)
                .matchedTransitionSource(id: collection.kind.id, in: zoomNamespace)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.dsHeadline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(countText)
                    .font(.dsCaption)
                    .foregroundStyle((newCount ?? 0) > 0 ? tint : Palette.inkSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Space.xxs)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collection.title), \(countText)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Up to three screenshots fanned like a hand of cards on a soft tint: you can tell a recipe from a receipt
/// at a glance, which a 2×2 mosaic of 70-point squares never managed.
struct StackCover: View {
    let screenshots: [Screenshot]
    let tint: Color
    var height: CGFloat = 150
    /// Screenshot proportions (iPhone 9:19.5), shown from the top where the content is
    private static let cardAspect: CGFloat = 0.62

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = height - Space.md
            let cardWidth = min(proxy.size.width * 0.5, cardHeight * StackCover.cardAspect)
            ZStack {
                ForEach(Array(screenshots.enumerated().reversed()), id: \.element.id) { index, screenshot in
                    card(screenshot, width: cardWidth, height: cardHeight)
                        .rotationEffect(.degrees(rotation(index)))
                        .offset(x: offset(index, width: proxy.size.width))
                }
                if screenshots.isEmpty {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.dsTitle)
                        .foregroundStyle(tint.opacity(0.6))
                }
            }
            .frame(width: proxy.size.width, height: height)
        }
        .frame(height: height)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityHidden(true)
    }

    private func card(_ screenshot: Screenshot, width: CGFloat, height: CGFloat) -> some View {
        AsyncThumbnail(asset: screenshot.asset, pointSize: height, placeholderTint: tint)
            .frame(width: width, height: height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 3)
    }

    /// Newest in front and upright; older ones fan out behind it
    private func rotation(_ index: Int) -> Double {
        guard screenshots.count > 1 else { return 0 }
        return [0, -8, 8][min(index, 2)]
    }

    private func offset(_ index: Int, width: CGFloat) -> CGFloat {
        guard screenshots.count > 1 else { return 0 }
        return [0, -width * 0.2, width * 0.2][min(index, 2)]
    }
}
