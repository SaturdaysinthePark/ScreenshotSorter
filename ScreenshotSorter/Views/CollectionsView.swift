import SwiftUI

/// Home: hero stats, live analysis, review banner, smart suggestions and category shelves.
/// Becomes the search results screen while a search is active.
struct CollectionsView: View {
    @Binding var path: NavigationPath

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoomNamespace
    @State private var showReview = false
    @State private var showReanalyzeConfirm = false

    var body: some View {
        @Bindable var model = model

        ScrollView {
            if model.isSearchActive {
                SearchResultsView()
                    .transition(.opacity)
            } else {
                homeContent
                    .transition(.opacity)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .background {
            ZStack {
                Palette.canvas.ignoresSafeArea()
                AmbientGlow(intensity: 0.14)
            }
        }
        .dsAnimation(Motion.gentle, value: model.isSearchActive)
        .navigationTitle(Brand.Copy.Home.title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $model.searchText,
            tokens: $model.searchTokens,
            suggestedTokens: .constant(model.suggestedSearchTokens),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(Brand.Copy.Search.prompt)
        ) { token in
            Label(token.title, systemImage: token.systemImage)
        }
        .toolbar { toolbarContent }
        .navigationDestination(for: CollectionKind.self) { kind in
            CleanGalleryView(kind: kind, zoomNamespace: zoomNamespace)
                .navigationTransition(.zoom(sourceID: kind.id, in: zoomNamespace))
        }
        .fullScreenCover(isPresented: $showReview, onDismiss: {
            model.syncReviewedFromDefaults()
        }) {
            ScreenshotReviewView(
                viewModel: ScreenshotReviewViewModel(screenshots: model.unreviewedScreenshots),
                onSortInto: { screenshot, category in
                    model.move([screenshot.id], from: screenshot.categories.first, to: category)
                }
            )
        }
        #if DEBUG
        .task {
            // QA: open All Screenshots on launch (`-QAOpenGallery YES`), e.g. with `-QAAutoScroll YES`
            if UserDefaults.standard.bool(forKey: "QAOpenGallery"), path.isEmpty {
                try? await Task.sleep(for: .seconds(1))
                path.append(CollectionKind.all)
            }
        }
        #endif
        .alert(Brand.Copy.Home.reanalyzeConfirmTitle, isPresented: $showReanalyzeConfirm) {
            Button(Brand.Copy.Home.reanalyze) { model.reanalyzeAll() }
            Button(Brand.Copy.Banners.later, role: .cancel) {}
        } message: {
            Text(Brand.Copy.Home.reanalyzeConfirmBody)
        }
    }

    // MARK: - Home content

    @ViewBuilder
    private var homeContent: some View {
        LazyVStack(alignment: .leading, spacing: Space.lg) {
            heroStats
                .padding(.horizontal, Space.gutter)

            if !model.progress.isIdle || model.progress.isPaused || model.progress.waitingForNetwork > 0 {
                AnalysisProgressCard()
                    .padding(.horizontal, Space.gutter)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.showReviewBanner {
                ReviewBannerView(
                    unreviewedCount: model.unreviewedCount,
                    isProcessing: !model.progress.isIdle,
                    onReviewTapped: {
                        HapticManager.shared.lightTap()
                        showReview = true
                    },
                    onDismiss: {
                        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
                            model.dismissReviewBanner()
                        }
                    }
                )
                .padding(.horizontal, Space.gutter)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if let suggestion = model.propagationSuggestion {
                PropagationCard(suggestion: suggestion)
                    .padding(.horizontal, Space.gutter)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if model.isLibraryLoaded && model.library.isEmpty {
                EmptyLibraryView()
                    .padding(.top, Space.xl)
            } else {
                allScreenshotsCard
                    .padding(.horizontal, Space.gutter)

                if !model.library.suggestedSmartCollections.isEmpty {
                    SmartSuggestionsSection(zoomNamespace: zoomNamespace)
                }

                if !model.library.keptSmartCollections.isEmpty {
                    keptCollectionsShelf
                }

                ForEach(groupedShelves, id: \.group) { shelf in
                    CategoryShelf(group: shelf.group, collections: shelf.collections, zoomNamespace: zoomNamespace)
                }
            }
        }
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xxl)
        .dsAnimation(Motion.snappy, value: model.progress.isIdle)
        .dsAnimation(Motion.snappy, value: model.showReviewBanner)
        .dsAnimation(Motion.bouncy, value: model.propagationSuggestion)
        .dsAnimation(Motion.gentle, value: model.library.smartCollections)
    }

    private var heroStats: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(Brand.Copy.Home.greeting())
                .font(.dsEyebrow)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    StatPill(value: model.library.count, label: Brand.Copy.Home.totalLabel, systemImage: "photo.stack.fill", tint: Palette.brand)
                    StatPill(value: Int((model.analysisFraction * 100).rounded()), label: Brand.Copy.Home.sortedLabel, systemImage: "wand.and.stars", tint: Palette.keep)
                    StatPill(value: groupedShelves.reduce(0) { $0 + $1.collections.count }, label: Brand.Copy.Home.stacksLabel, systemImage: "square.stack.3d.up.fill", tint: Palette.brandSecondary)
                }
            }
            .scrollClipDisabled()
        }
    }

    private var allScreenshotsCard: some View {
        let collection = model.library.preview(for: .all)
        return NavigationLink(value: CollectionKind.all) {
            HStack(spacing: Space.md) {
                MosaicThumbnail(screenshots: Array(collection.screenshots.prefix(4)), tint: Palette.brand, size: 84)
                    .matchedTransitionSource(id: CollectionKind.all.id, in: zoomNamespace)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(Brand.Copy.Home.allScreenshots)
                        .font(.dsTitle2)
                        .foregroundStyle(Palette.ink)
                    Text(Brand.Copy.Home.allScreenshotsSubtitle)
                        .font(.dsCallout)
                        .foregroundStyle(Palette.inkSecondary)
                    Text(collection.count.formatted())
                        .font(.dsMono)
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.dsHeadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(Space.md)
            .dsSurface(radius: Radius.lg, tint: Palette.brand)
        }
        .pressable()
        .accessibilityLabel("\(Brand.Copy.Home.allScreenshots), \(Brand.screenshots(collection.count))")
    }

    private var keptCollectionsShelf: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ShelfHeader(title: Brand.Copy.Home.yourCollections, systemImage: "sparkles", tint: Palette.brandSecondary, count: model.library.keptSmartCollections.count)
                .padding(.horizontal, Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Space.sm) {
                    ForEach(model.library.keptSmartCollections) { smart in
                        let kind = CollectionKind.smart(id: smart.id)
                        NavigationLink(value: kind) {
                            CollectionCard(collection: model.library.preview(for: kind), tint: Palette.brandSecondary, zoomNamespace: zoomNamespace)
                        }
                        .pressable()
                        .contextMenu {
                            Button(role: .destructive) {
                                model.deleteSmartCollection(smart.id)
                            } label: {
                                Label(Brand.Copy.Smart.delete, systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private struct Shelf {
        let group: CategoryGroup
        let collections: [ScreenshotCollection]
    }

    /// In `model.shelfRanking` order, which stays put while sorting runs
    private var groupedShelves: [Shelf] {
        model.shelfRanking.shelves(model.library.categoryCollections(sort: model.collectionsSort)).map { shelf in
            Shelf(group: shelf.group, collections: shelf.collections)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                HapticManager.shared.lightTap()
                showReview = true
            } label: {
                Image(systemName: "rectangle.stack.badge.play.fill")
            }
            .disabled(model.unreviewedCount == 0)
            .accessibilityLabel(Brand.Copy.Banners.reviewCTA)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(Brand.Copy.Home.sortMenu, selection: Binding(
                    get: { model.collectionsSort },
                    set: { model.collectionsSort = $0 }
                )) {
                    ForEach(CollectionsSortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Divider()
                Button {
                    model.togglePause()
                } label: {
                    Label(model.progress.isPaused ? Brand.Copy.Home.resume : Brand.Copy.Home.pause,
                          systemImage: model.progress.isPaused ? "play.fill" : "pause.fill")
                }
                Button {
                    showReanalyzeConfirm = true
                } label: {
                    Label(Brand.Copy.Home.reanalyze, systemImage: "arrow.triangle.2.circlepath")
                }
                #if DEBUG
                NavigationLink {
                    EvaluationView()
                } label: {
                    Label("Evaluation (debug)", systemImage: "ladybug")
                }
                #endif
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(Brand.Copy.Home.moreMenu)
        }
    }
}

// MARK: - Shelf

private struct CategoryShelf: View {
    let group: CategoryGroup
    let collections: [ScreenshotCollection]
    let zoomNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ShelfHeader(title: group.rawValue, systemImage: group.icon, tint: group.color, count: collections.count)
                .padding(.horizontal, Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Space.sm) {
                    ForEach(collections) { collection in
                        NavigationLink(value: collection.kind) {
                            CollectionCard(collection: collection, tint: collection.category.color, zoomNamespace: zoomNamespace)
                        }
                        .pressable()
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                .opacity(phase.isIdentity ? 1 : 0.75)
                        }
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

struct ShelfHeader: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: systemImage)
                .font(.dsCaption)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.dsTitle2)
                .foregroundStyle(Palette.ink)
            Text(count.formatted())
                .font(.dsCaption)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.horizontal, Space.xs)
                .padding(.vertical, 2)
                .background(Palette.hairline, in: Capsule())
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Cards

/// Collection card with a live 2×2 mosaic of its newest screenshots.
struct CollectionCard: View {
    let collection: ScreenshotCollection
    let tint: Color
    let zoomNamespace: Namespace.ID

    private let width: CGFloat = 156

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            MosaicThumbnail(screenshots: Array(collection.screenshots.prefix(4)), tint: tint, size: width)
                .overlay(alignment: .topLeading) {
                    Image(systemName: collection.icon)
                        .font(.dsCaption)
                        .foregroundStyle(.white)
                        .padding(Space.xs)
                        .background(tint.gradient, in: Circle())
                        .padding(Space.xs)
                }
                .matchedTransitionSource(id: collection.kind.id, in: zoomNamespace)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.dsHeadline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(Brand.screenshots(collection.count))
                    .font(.dsCaption)
                    .foregroundStyle(Palette.inkSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Space.xxs)
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collection.title), \(Brand.screenshots(collection.count))")
        .accessibilityAddTraits(.isButton)
    }
}

/// 2×2 grid of thumbnails (fewer tiles when the collection is small).
struct MosaicThumbnail: View {
    let screenshots: [Screenshot]
    let tint: Color
    let size: CGFloat

    var body: some View {
        let spacing: CGFloat = 2
        let half = (size - spacing) / 2
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tint.opacity(0.14))
            if screenshots.count >= 4 {
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        tile(0, half)
                        tile(1, half)
                    }
                    HStack(spacing: spacing) {
                        tile(2, half)
                        tile(3, half)
                    }
                }
            } else if let first = screenshots.first {
                AsyncThumbnail(asset: first.asset, pointSize: size, placeholderTint: tint)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.dsTitle)
                    .foregroundStyle(tint.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func tile(_ index: Int, _ side: CGFloat) -> some View {
        AsyncThumbnail(asset: screenshots[index].asset, pointSize: side, placeholderTint: tint)
            .frame(width: side, height: side)
    }
}

// MARK: - Propagation

private struct PropagationCard: View {
    let suggestion: PropagationSuggestion
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.sm) {
            MosaicThumbnail(screenshots: model.library.screenshots(ids: Array(suggestion.ids.prefix(4))), tint: suggestion.category.color, size: 56)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Brand.Copy.Propagation.title(suggestion.ids.count, suggestion.category.displayName))
                    .font(.dsHeadline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.xs) {
                    Button(Brand.Copy.Propagation.accept) {
                        model.acceptPropagation(suggestion)
                    }
                    .buttonStyle(.brand(.primary, size: .compact))
                    Button(Brand.Copy.Propagation.decline) {
                        model.propagationSuggestion = nil
                    }
                    .buttonStyle(.brand(.ghost, size: .compact))
                }
            }
        }
        .padding(Space.md)
        .dsCard(tint: suggestion.category.color)
    }
}

// MARK: - Empty

private struct EmptyLibraryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false

    var body: some View {
        VStack(spacing: Space.md) {
            BrandMark(size: 96)
                .symbolEffect(.bounce, value: bounce)
            Text(Brand.Copy.Empty.noScreenshotsTitle)
                .font(.dsTitle)
                .foregroundStyle(Palette.ink)
            Text(Brand.Copy.Empty.noScreenshotsBody)
                .font(.dsBody)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity)
        .onAppear { if !reduceMotion { bounce.toggle() } }
    }
}
