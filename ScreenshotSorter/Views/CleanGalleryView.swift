import Photos
import SwiftUI
import UIKit

// MARK: - Metrics

enum GalleryMetrics {
    /// Photos-style hairline gutters.
    static let spacing: CGFloat = 2
    /// Portrait cells show more of each screenshot than squares while staying dense.
    static let cellAspect: CGFloat = 3.0 / 4.0
    /// Thumbnail request size (points) for compact / regular widths. Detail view looks these up for its crossfade.
    static let compactThumbnailPoints: CGFloat = 140
    static let regularThumbnailPoints: CGFloat = 220
    /// Thumbnails kept warm ahead of / behind the scroll position (in cells).
    static let prefetchLead: Int = 36
    static let prefetchTrail: Int = 12
    /// Seconds the undo toast stays up.
    static let undoDuration: Double = 5
    /// Cell accessibility dates (one shared style instead of one per cell render)
    static let cellDateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)
}

// MARK: - Clean Gallery View
/// A collection's screenshots in a Photos-like grid: date sections, sorting, multi-select with a
/// floating Liquid Glass action bar, undoable corrections and a zoom transition into the pager.

struct CleanGalleryView: View {
    let kind: CollectionKind
    /// The caller's namespace (it zooms this screen in from a collection card). The photo pager uses its own namespace.
    let zoomNamespace: Namespace.ID?

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Namespace private var photoNamespace

    @State private var sortOption: SortOption = .dateDescending
    @State private var isSelecting: Bool = false
    @State private var selection: Set<String> = []
    @State private var viewer: GalleryViewerSession?
    @State private var zoomSourceID: String = ""
    @State private var moveRequest: GalleryIDsRequest?
    @State private var deleteRequest: GalleryIDsRequest?
    @State private var toast: GalleryToast?
    @State private var sharePayload: ScreenshotSharePayload?
    @State private var isPreparingShare: Bool = false
    @State private var showInlineTitle: Bool = false
    @State private var visibility: GalleryVisibilityTracker = GalleryVisibilityTracker()
    @State private var derivedCache: GalleryDerivedCache = GalleryDerivedCache()
    @State private var prefetcher: GalleryPrefetcher = GalleryPrefetcher()
    #if DEBUG
    @State private var qaScrollPosition: ScrollPosition = ScrollPosition()
    #endif

    init(kind: CollectionKind, zoomNamespace: Namespace.ID? = nil) {
        self.kind = kind
        self.zoomNamespace = zoomNamespace
    }

    // MARK: Body

    var body: some View {
        // The layout (ids, sections) only depends on membership and order, so an analysis batch
        // doesn't re-render this body; visible cells look up their own screenshot (`GalleryItem`).
        let derived: GalleryDerived = currentDerived
        let header: (title: String, icon: String) = model.library.header(for: kind)
        let sections: [GallerySection] = derived.sections
        let ids: [String] = derived.ids

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    GalleryLiveHeader(
                        kind: kind,
                        ids: ids,
                        title: header.title,
                        icon: header.icon,
                        eyebrow: eyebrow,
                        tint: tint,
                        gradient: gradient,
                        thisWeekCount: derived.thisWeekCount
                    )
                    .padding(.bottom, Space.md)

                    if ids.isEmpty {
                        GalleryEmptyState(icon: header.icon, tint: tint)
                            .transition(AnyTransition.opacity)
                    } else {
                        ForEach(sections) { section in
                            Section {
                                LazyVGrid(columns: columns, spacing: GalleryMetrics.spacing) {
                                    ForEach(section.ids, id: \.self) { id in
                                        cell(id: id)
                                            .id(id)
                                    }
                                }
                            } header: {
                                if let title = section.title {
                                    GallerySectionHeader(title: title, count: section.ids.count)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, bottomContentPadding)
                .dsAnimation(Motion.gentle, value: derived.token)
            }
            .scrollIndicators(.automatic)
            #if DEBUG
            .scrollPosition($qaScrollPosition)
            #endif
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 72
            } action: { _, isPastHeader in
                guard showInlineTitle != isPastHeader else { return }
                Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
                    showInlineTitle = isPastHeader
                }
            }
            .onChange(of: zoomSourceID) { _, newID in
                // Keep the current pager page's thumbnail on screen so the zoom lands on it.
                guard viewer != nil, !newID.isEmpty else { return }
                proxy.scrollTo(newID, anchor: .center)
            }
            #if DEBUG
            .task {
                // QA: scripted scrolling for frame-timing runs without UI-test input (`-QAAutoScroll YES`)
                guard UserDefaults.standard.bool(forKey: "QAAutoScroll") else { return }
                try? await Task.sleep(for: .seconds(3))
                guard currentDerived.ids.count > 120 else { return }
                NSLog("QA-AUTOSCROLL start %f", Date().timeIntervalSince1970)
                // ~20 rows per jump, down ~25 screens and back: roughly a fast fling's load
                let speed: Double = max(0.25, UserDefaults.standard.double(forKey: "QAAutoScrollSpeed").nonZero ?? 1)
                let stops: [CGFloat] = Array(stride(from: 1_200, through: 30_000, by: 1_200))
                for y in stops + stops.reversed().dropFirst() + [0] {
                    withAnimation(.easeInOut(duration: 0.7 / speed)) { qaScrollPosition.scrollTo(y: y) }
                    try? await Task.sleep(for: .milliseconds(Int(900 / speed)))
                }
                NSLog("QA-AUTOSCROLL end %f", Date().timeIntervalSince1970)
            }
            #endif
        }
        .background { backgroundLayer }
        .navigationTitle(header.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar { toolbarContent(ids: ids, header: header) }
        .overlay(alignment: .bottom) {
            bottomStack()
        }
        .onChange(of: derived.token) { _, _ in
            pruneSelection(to: currentDerived.ids)
        }
        .onDisappear {
            visibility.cancel()
            prefetcher.reset(size: ThumbnailLoader.pixelSize(points: thumbnailPoints))
        }
        .fullScreenCover(item: $viewer) { session in
            PhotoDetailView(
                ids: session.ids,
                initialID: session.initialID,
                context: kind,
                onCurrentChange: { id in
                    zoomSourceID = id
                }
            )
            .navigationTransition(.zoom(sourceID: zoomSourceID, in: photoNamespace))
        }
        .sheet(item: $moveRequest) { request in
            MoveToCategorySheet(count: request.ids.count, current: kind.category) { category in
                performMove(request.ids, to: category)
            }
        }
        .sheet(item: $sharePayload) { payload in
            ScreenshotShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .confirmationDialog(
            Text(Brand.Copy.Gallery.deleteTitle(deleteRequest?.ids.count ?? 0)),
            isPresented: deleteDialogBinding,
            titleVisibility: .visible,
            presenting: deleteRequest
        ) { request in
            Button(Brand.Copy.Gallery.delete, role: .destructive) {
                performDelete(request.ids)
            }
            Button(Brand.Copy.Completion.goBack, role: .cancel) {}
        } message: { _ in
            Text(Brand.Copy.Completion.deleteWarning)
        }
    }

    // MARK: Derived

    private var tint: Color {
        switch kind {
        case .category(let category):
            return category.color
        case .all, .smart:
            return Palette.brand
        }
    }

    private var gradient: LinearGradient {
        switch kind {
        case .category(let category):
            return category.gradient
        case .all, .smart:
            return Palette.brandGradient
        }
    }

    private var eyebrow: String {
        switch kind {
        case .category(let category):
            return category.group.rawValue
        case .all:
            return Brand.Copy.Gallery.allEyebrow
        case .smart:
            return Brand.Copy.Gallery.smartEyebrow
        }
    }

    /// Categories can be removed from; smart collections drop membership; "All" has nothing to remove from.
    private var canRemove: Bool {
        switch kind {
        case .category(let category):
            return category != .all
        case .smart:
            return true
        case .all:
            return false
        }
    }

    private var removeTargetName: String {
        switch kind {
        case .category(let category):
            return category.displayName
        case .all, .smart:
            return model.library.header(for: kind).title
        }
    }

    private var availableSorts: [SortOption] {
        if case .category(let category) = kind, category != .all {
            return SortOption.allCases
        }
        return [.dateDescending, .dateAscending]
    }

    private var thumbnailPoints: CGFloat {
        horizontalSizeClass == .regular ? GalleryMetrics.regularThumbnailPoints : GalleryMetrics.compactThumbnailPoints
    }

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: GalleryMetrics.spacing)]
        }
        let item: GridItem = GridItem(.flexible(), spacing: GalleryMetrics.spacing)
        return [item, item, item]
    }

    private var bottomContentPadding: CGFloat {
        if isSelecting { return 150 }
        if toast != nil || model.propagationSuggestion != nil { return 130 }
        return Space.xl
    }

    private var floatTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.move(edge: .bottom).combined(with: AnyTransition.opacity)
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { deleteRequest != nil },
            set: { isPresented in
                if !isPresented { deleteRequest = nil }
            }
        )
    }

    private var sortBinding: Binding<SortOption> {
        Binding(
            get: { sortOption },
            set: { newValue in
                guard newValue != sortOption else { return }
                HapticManager.shared.selectionChanged()
                Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
                    sortOption = newValue
                }
            }
        )
    }

    /// Layout for the current sort, rebuilt only when membership/order changes (relevancy depends on
    /// scores, so it follows every library revision instead).
    private var currentDerived: GalleryDerived {
        let library: LibraryStore = model.library
        let version: Int = sortOption == .relevancy ? library.revision : library.orderVersion(for: kind)
        return derivedCache.value(version: version, kind: kind, sort: sortOption) {
            let ids: [String]
            switch sortOption {
            case .dateDescending:
                ids = library.ids(for: kind)
            case .dateAscending:
                ids = Array(library.ids(for: kind).reversed())
            case .relevancy:
                ids = library.collection(for: kind).sorted(by: .relevancy).map { $0.id }
            }
            let date: (String) -> Date = { library.screenshot(id: $0)?.creationDate ?? .distantPast }
            let cutoff: Date = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            var indexByID: [String: Int] = [:]
            indexByID.reserveCapacity(ids.count)
            var thisWeek: Int = 0
            for (index, id) in ids.enumerated() {
                indexByID[id] = index
                if date(id) >= cutoff { thisWeek += 1 }
            }
            return GalleryDerived(
                ids: ids,
                indexByID: indexByID,
                sections: GallerySection.make(ids: ids, date: date, groupByDate: sortOption != .relevancy),
                thisWeekCount: thisWeek,
                token: 0
            )
        }
    }

    // MARK: Layers

    private var backgroundLayer: some View {
        ZStack(alignment: .top) {
            Palette.canvas
            AmbientGlow(color: tint, secondary: Palette.brandSecondary, intensity: 0.14)
        }
        .ignoresSafeArea()
    }

    // MARK: Cells

    private func cell(id: String) -> some View {
        GalleryItem(
            id: id,
            tint: tint,
            thumbnailPoints: thumbnailPoints,
            isSelecting: isSelecting,
            isSelected: selection.contains(id),
            namespace: photoNamespace,
            transition: cellTransition,
            onTap: { screenshot in handleTap(screenshot) },
            onAppear: {
                visibility.noteAppeared(id) { visibleIDs, lastID in
                    handleVisible(visibleIDs, lastID: lastID)
                }
            },
            menu: { screenshot in cellMenu(for: screenshot) }
        )
    }

    private var cellTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.scale(scale: 0.82).combined(with: AnyTransition.opacity)
    }

    @ViewBuilder
    private func cellMenu(for screenshot: Screenshot) -> some View {
        if !isSelecting {
            Button {
                enterSelection(with: screenshot.id)
            } label: {
                Label(Brand.Copy.Gallery.select, systemImage: "checkmark.circle")
            }
        }
        Button {
            share([screenshot.id])
        } label: {
            Label(Brand.Copy.Gallery.share, systemImage: "square.and.arrow.up")
        }
        Button {
            moveRequest = GalleryIDsRequest(ids: [screenshot.id])
        } label: {
            Label(Brand.Copy.Gallery.moveTo, systemImage: "folder")
        }
        if canRemove {
            Button {
                performRemove([screenshot.id])
            } label: {
                Label(Brand.Copy.Gallery.remove, systemImage: "minus.circle")
            }
        }
        Divider()
        Button(role: .destructive) {
            deleteRequest = GalleryIDsRequest(ids: [screenshot.id])
        } label: {
            Label(Brand.Copy.Gallery.delete, systemImage: "trash")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(ids: [String], header: (title: String, icon: String)) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            GalleryInlineTitle(title: header.title, icon: header.icon, tint: tint)
                .opacity(showInlineTitle ? 1 : 0)
                .offset(y: showInlineTitle ? 0 : 6)
                .accessibilityHidden(!showInlineTitle)
        }

        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                let allSelected: Bool = !ids.isEmpty && selection.count >= ids.count
                Button(allSelected ? Brand.Copy.Gallery.deselectAll : Brand.Copy.Gallery.selectAll) {
                    toggleSelectAll(ids, allSelected: allSelected)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(Brand.Copy.Gallery.done) {
                    exitSelection()
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.brand)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(Brand.Copy.Gallery.select) {
                    enterSelection(with: nil)
                }
                .disabled(ids.isEmpty)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(Brand.Copy.Gallery.sort, selection: sortBinding) {
                ForEach(availableSorts, id: \.self) { option in
                    Label(option.rawValue, systemImage: sortIcon(option))
                        .tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel(Brand.Copy.Gallery.sort)
        .accessibilityHint(Brand.Copy.Gallery.sortHint)
    }

    private func sortIcon(_ option: SortOption) -> String {
        switch option {
        case .dateDescending:
            return "arrow.down"
        case .dateAscending:
            return "arrow.up"
        case .relevancy:
            return "sparkles"
        }
    }

    // MARK: Bottom chrome

    private func bottomStack() -> some View {
        VStack(spacing: Space.sm) {
            if let suggestion = model.propagationSuggestion, viewer == nil, !isSelecting {
                GalleryPropagationCard(
                    suggestion: suggestion,
                    onAccept: { acceptPropagation(suggestion) },
                    onDecline: { declinePropagation() }
                )
                .transition(floatTransition)
            }

            if let toast {
                toastView(toast)
                    .transition(floatTransition)
            }

            if isSelecting {
                SelectionActionBar(
                    count: selection.count,
                    showsRemove: canRemove,
                    removeName: removeTargetName,
                    isPreparingShare: isPreparingShare,
                    onShare: { share(selectedIDs()) },
                    onMove: { moveRequest = GalleryIDsRequest(ids: selectedIDs()) },
                    onRemove: { performRemove(selectedIDs()) },
                    onDelete: { deleteRequest = GalleryIDsRequest(ids: selectedIDs()) }
                )
                .transition(floatTransition)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.bottom, Space.xs)
        .dsAnimation(Motion.bouncy, value: model.propagationSuggestion?.id)
        .task(id: toast?.id) {
            await autoDismissToast()
        }
    }

    @ViewBuilder
    private func toastView(_ toast: GalleryToast) -> some View {
        if let group = toast.undoGroup {
            UndoToastView(
                message: toast.message,
                systemImage: toast.systemImage,
                tint: toast.tint,
                duration: GalleryMetrics.undoDuration
            ) {
                undo(group: group, ids: toast.ids)
            }
            .id(toast.id)
        } else {
            GalleryInfoToast(message: toast.message, systemImage: toast.systemImage, tint: toast.tint)
                .id(toast.id)
        }
    }

    // MARK: Interaction

    private func handleTap(_ screenshot: Screenshot) {
        if isSelecting {
            HapticManager.shared.selectionChanged()
            Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
                if selection.contains(screenshot.id) {
                    selection.remove(screenshot.id)
                } else {
                    selection.insert(screenshot.id)
                }
            }
            return
        }
        HapticManager.shared.lightTap()
        zoomSourceID = screenshot.id
        viewer = GalleryViewerSession(ids: currentDerived.ids, initialID: screenshot.id)
    }

    /// Batched from cell `onAppear`: prioritise analysis for what's on screen and keep thumbnails
    /// warm in a window around the scroll position (more ahead in the scroll direction).
    private func handleVisible(_ visibleIDs: [String], lastID: String) {
        model.boost(visibleIDs)
        let derived: GalleryDerived = currentDerived
        guard let index = derived.indexByID[lastID] else { return }
        prefetcher.update(around: index, in: derived.ids, library: model.library,
                          size: ThumbnailLoader.pixelSize(points: thumbnailPoints))
    }

    private func selectedIDs() -> [String] {
        // Keep grid order so shares/moves feel predictable.
        currentDerived.ids.filter { selection.contains($0) }
    }

    private func enterSelection(with id: String?) {
        HapticManager.shared.lightTap()
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            isSelecting = true
            if let id {
                selection = [id]
            }
        }
    }

    private func exitSelection() {
        HapticManager.shared.lightTap()
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            exitSelectionState()
        }
    }

    private func exitSelectionState() {
        isSelecting = false
        selection = []
    }

    private func toggleSelectAll(_ ids: [String], allSelected: Bool) {
        HapticManager.shared.selectionChanged()
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            if allSelected {
                selection = []
            } else {
                selection = Set(ids)
            }
        }
    }

    private func pruneSelection(to ids: [String]) {
        guard !selection.isEmpty else { return }
        let valid: Set<String> = selection.intersection(ids)
        if valid.count != selection.count {
            selection = valid
        }
    }

    // MARK: Actions

    private func share(_ ids: [String]) {
        guard !isPreparingShare, !ids.isEmpty else { return }
        HapticManager.shared.lightTap()
        isPreparingShare = true
        let assets: [PHAsset] = model.library.screenshots(ids: ids).map { $0.asset }
        Task {
            let images: [UIImage] = await ScreenshotExporter.images(for: assets)
            isPreparingShare = false
            guard !images.isEmpty else {
                HapticManager.shared.error()
                showToast(GalleryToast(message: Brand.Copy.Gallery.shareFailed, systemImage: "exclamationmark.triangle.fill", tint: Palette.toss))
                return
            }
            sharePayload = ScreenshotSharePayload(items: images)
        }
    }

    private func performMove(_ ids: [String], to destination: ScreenshotCategory) {
        guard !ids.isEmpty else { return }
        let group: String = model.move(ids, from: kind.category, to: destination)
        let next: GalleryToast = GalleryToast(
            message: Brand.Copy.Gallery.moved(ids.count, to: destination.displayName),
            systemImage: destination.icon,
            tint: destination.color,
            undoGroup: group,
            ids: ids
        )
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            exitSelectionState()
            toast = next
        }
    }

    private func performRemove(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let next: GalleryToast
        switch kind {
        case .category(let category):
            guard category != .all else { return }
            let group: String = model.setCategory(category, included: false, for: ids)
            next = GalleryToast(
                message: Brand.Copy.Gallery.removed(ids.count, from: category.displayName),
                systemImage: "minus.circle.fill",
                tint: category.color,
                undoGroup: group,
                ids: ids
            )
        case .smart(id: let collectionID):
            let name: String = removeTargetName
            model.removeFromSmartCollection(ids, collectionID: collectionID)
            HapticManager.shared.mediumTap()
            next = GalleryToast(
                message: Brand.Copy.Gallery.removed(ids.count, from: name),
                systemImage: "minus.circle.fill",
                tint: Palette.brand
            )
        case .all:
            return
        }
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            exitSelectionState()
            toast = next
        }
    }

    private func performDelete(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        Task {
            let success: Bool = await model.delete(ids)
            if success {
                let next: GalleryToast = GalleryToast(
                    message: Brand.Copy.Gallery.deleted(ids.count),
                    systemImage: "trash.fill",
                    tint: Palette.toss
                )
                Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
                    exitSelectionState()
                    toast = next
                }
            } else {
                showToast(GalleryToast(
                    message: Brand.Copy.Completion.deleteCancelled,
                    systemImage: "hand.raised.fill",
                    tint: Palette.inkSecondary
                ))
            }
        }
    }

    private func undo(group: String, ids: [String]) {
        HapticManager.shared.undo()
        model.undoCorrection(group: group, ids: ids)
        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
            toast = nil
        }
    }

    private func acceptPropagation(_ suggestion: PropagationSuggestion) {
        let next: GalleryToast = GalleryToast(
            message: Brand.Copy.Gallery.added(suggestion.ids.count, to: suggestion.category.displayName),
            systemImage: suggestion.category.icon,
            tint: suggestion.category.color
        )
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            model.acceptPropagation(suggestion)
            toast = next
        }
        HapticManager.shared.success()
    }

    private func declinePropagation() {
        HapticManager.shared.lightTap()
        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
            model.propagationSuggestion = nil
        }
    }

    private func showToast(_ next: GalleryToast) {
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            toast = next
        }
    }

    private func autoDismissToast() async {
        guard let current = toast else { return }
        let seconds: Double = current.undoGroup == nil ? 2.4 : GalleryMetrics.undoDuration + 0.3
        UIAccessibility.post(notification: .announcement, argument: current.message)
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled, toast?.id == current.id else { return }
        Motion.perform(Motion.snappy, reduceMotion: reduceMotion) {
            toast = nil
        }
    }
}

// MARK: - Supporting Models

/// A pager presentation: the list is snapshotted so paging is stable while analysis reorders the grid.
struct GalleryViewerSession: Identifiable {
    let id: UUID = UUID()
    let ids: [String]
    let initialID: String
}

struct GalleryIDsRequest: Identifiable {
    let id: UUID = UUID()
    let ids: [String]
}

struct GalleryToast: Identifiable {
    let id: UUID
    let message: String
    let systemImage: String
    let tint: Color
    /// Correction group to undo; `nil` for informational toasts.
    let undoGroup: String?
    let ids: [String]

    init(message: String, systemImage: String, tint: Color, undoGroup: String? = nil, ids: [String] = []) {
        self.id = UUID()
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.undoGroup = undoGroup
        self.ids = ids
    }
}

/// Date-bucketed slice of the grid ("Today", "Yesterday", "This week", months).
/// The gallery's layout: everything derived from membership and order, never from analysis content.
struct GalleryDerived {
    let ids: [String]
    let indexByID: [String: Int]
    let sections: [GallerySection]
    let thisWeekCount: Int
    /// Changes only when `ids` actually change (drives insert/remove animation and selection pruning)
    var token: Int
}

@MainActor
final class GalleryDerivedCache {
    private var key: (version: Int, kind: CollectionKind, sort: SortOption)?
    private var cached: GalleryDerived?
    private var token: Int = 0

    func value(version: Int, kind: CollectionKind, sort: SortOption, build: () -> GalleryDerived) -> GalleryDerived {
        if let key, let cached, key.version == version, key.kind == kind, key.sort == sort { return cached }
        var value = build()
        if value.ids != cached?.ids { token += 1 }
        value.token = token
        key = (version, kind, sort)
        cached = value
        return value
    }
}

/// Keeps `PHCachingImageManager` warm for a window of cells around the scroll position and releases
/// what scrolled far away (the old code only ever started caching, never stopped).
@MainActor
final class GalleryPrefetcher {
    private var cached: [String: PHAsset] = [:]
    private var lastIndex: Int = 0

    func update(around index: Int, in ids: [String], library: LibraryStore, size: CGSize) {
        let forward: Bool = index >= lastIndex
        lastIndex = index
        let lead: Int = forward ? GalleryMetrics.prefetchLead : GalleryMetrics.prefetchTrail
        let trail: Int = forward ? GalleryMetrics.prefetchTrail : GalleryMetrics.prefetchLead
        let lower: Int = max(0, index - trail)
        let upper: Int = min(ids.count, index + lead + 1)
        guard lower < upper else { return }
        let window: ArraySlice<String> = ids[lower..<upper]
        let windowSet: Set<String> = Set(window)
        let start: [Screenshot] = library.screenshots(ids: window.filter { cached[$0] == nil })
        let stop: [String] = cached.keys.filter { !windowSet.contains($0) }
        ThumbnailLoader.shared.startCaching(start.map { $0.asset }, size: size)
        ThumbnailLoader.shared.stopCaching(stop.compactMap { cached[$0] }, size: size)
        for id in stop { cached[id] = nil }
        for screenshot in start { cached[screenshot.id] = screenshot.asset }
    }

    func reset(size: CGSize) {
        ThumbnailLoader.shared.stopCaching(Array(cached.values), size: size)
        cached = [:]
        lastIndex = 0
    }
}

struct GallerySection: Identifiable {
    let id: String
    let title: String?
    let ids: [String]

    /// Groups ids (in display order) into Today / Yesterday / This week / month sections.
    /// Calendar math runs once per month boundary, not once per screenshot (25k items took ~50 ms).
    static func make(ids: [String], date: (String) -> Date, groupByDate: Bool,
                     now: Date = Date(), calendar: Calendar = .current) -> [GallerySection] {
        guard !ids.isEmpty else { return [] }
        guard groupByDate else {
            return [GallerySection(id: "all", title: nil, ids: ids)]
        }

        let startOfToday: Date = calendar.startOfDay(for: now)
        let startOfYesterday: Date = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek: Date = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfYesterday
        let currentYear: Int = calendar.component(.year, from: now)

        var sections: [GallerySection] = []
        var usedKeys: Set<String> = []
        var currentKey: String = ""
        var currentTitle: String = ""
        var bucket: [String] = []
        var monthInterval: DateInterval?
        var monthKey: String = ""
        var monthTitle: String = ""

        func flush() {
            guard !bucket.isEmpty else { return }
            var key: String = currentKey
            var suffix: Int = 1
            while usedKeys.contains(key) {
                suffix += 1
                key = currentKey + "#" + String(suffix)
            }
            usedKeys.insert(key)
            sections.append(GallerySection(id: key, title: currentTitle, ids: bucket))
            bucket = []
        }

        for id in ids {
            let created: Date = date(id)
            let key: String
            let title: String
            if created >= startOfToday {
                key = "today"
                title = Brand.Copy.Gallery.today
            } else if created >= startOfYesterday {
                key = "yesterday"
                title = Brand.Copy.Gallery.yesterday
            } else if created >= startOfWeek {
                key = "week"
                title = Brand.Copy.Gallery.thisWeek
            } else {
                if monthInterval?.contains(created) != true {
                    monthInterval = calendar.dateInterval(of: .month, for: created)
                    let components: DateComponents = calendar.dateComponents([.year, .month], from: created)
                    let year: Int = components.year ?? 0
                    monthKey = "m-" + String(year) + "-" + String(components.month ?? 0)
                    monthTitle = year == currentYear
                        ? created.formatted(.dateTime.month(.wide))
                        : created.formatted(.dateTime.month(.wide).year())
                }
                key = monthKey
                title = monthTitle
            }
            if key != currentKey {
                flush()
                currentKey = key
                currentTitle = title
            }
            bucket.append(id)
        }
        flush()
        return sections
    }
}

/// Coalesces cell appearances into one `boost` + prefetch every ~quarter second.
final class GalleryVisibilityTracker {
    private var pending: [String] = []
    private var lastID: String?
    private var flushTask: Task<Void, Never>?

    init() {}

    @MainActor
    func noteAppeared(_ id: String, flush: @escaping @MainActor (_ ids: [String], _ lastID: String) -> Void) {
        pending.append(id)
        lastID = id
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            let ids: [String] = self.pending
            let last: String? = self.lastID
            self.pending.removeAll()
            self.flushTask = nil
            guard !Task.isCancelled, let last, !ids.isEmpty else { return }
            flush(ids, last)
        }
    }

    @MainActor
    func cancel() {
        flushTask?.cancel()
        flushTask = nil
        pending.removeAll()
    }
}

// MARK: - Cell

/// One grid cell. Looks its screenshot up by id so analysis updates re-render only visible cells,
/// not the whole gallery.
private struct GalleryItem<Menu: View>: View {
    let id: String
    let tint: Color
    let thumbnailPoints: CGFloat
    let isSelecting: Bool
    let isSelected: Bool
    let namespace: Namespace.ID
    let transition: AnyTransition
    let onTap: (Screenshot) -> Void
    let onAppear: () -> Void
    @ViewBuilder let menu: (Screenshot) -> Menu

    @Environment(AppModel.self) private var model

    var body: some View {
        if let screenshot = model.library.screenshot(id: id) {
            cell(screenshot)
        } else {
            // Removed a moment ago; keep the slot until the layout catches up
            Color.clear.aspectRatio(GalleryMetrics.cellAspect, contentMode: .fit)
        }
    }

    private func cell(_ screenshot: Screenshot) -> some View {
        var label: String = Brand.Copy.Gallery.cellAccessibility(title: screenshot.title, date: screenshot.creationDate.formatted(GalleryMetrics.cellDateStyle))
        if screenshot.tier == .none {
            label += ". " + Brand.Copy.Gallery.notSortedYet
        }
        return GalleryCell(
            screenshot: screenshot,
            tint: tint,
            thumbnailPoints: thumbnailPoints,
            isSelecting: isSelecting,
            isSelected: isSelected
        )
        .matchedTransitionSource(id: id, in: namespace)
        .contentShape(Rectangle())
        .onTapGesture { onTap(screenshot) }
        .contextMenu { menu(screenshot) }
        .onAppear(perform: onAppear)
        .transition(transition)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? Brand.Copy.Gallery.selected : "")
        .accessibilityHint(isSelecting ? Brand.Copy.Gallery.selectHint : Brand.Copy.Gallery.openHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { onTap(screenshot) }
    }
}

/// Header whose "still sorting" count follows analysis without re-rendering the grid around it.
private struct GalleryLiveHeader: View {
    let kind: CollectionKind
    let ids: [String]
    let title: String
    let icon: String
    let eyebrow: String
    let tint: Color
    let gradient: LinearGradient
    let thisWeekCount: Int

    @Environment(AppModel.self) private var model

    var body: some View {
        GalleryHeader(
            title: title,
            icon: icon,
            eyebrow: eyebrow,
            tint: tint,
            gradient: gradient,
            count: ids.count,
            unsortedCount: unsortedCount,
            thisWeekCount: thisWeekCount
        )
    }

    private var unsortedCount: Int {
        let library: LibraryStore = model.library
        if case .all = kind { return max(0, library.count - library.analyzedCount) }
        return ids.reduce(0) { $0 + ((library.screenshot(id: $1)?.tier ?? .none) == .none ? 1 : 0) }
    }
}

private struct GalleryCell: View {
    let screenshot: Screenshot
    let tint: Color
    let thumbnailPoints: CGFloat
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        let radius: CGFloat = isSelected ? Radius.sm : 0
        Color.clear
            .aspectRatio(GalleryMetrics.cellAspect, contentMode: .fit)
            .overlay {
                AsyncThumbnail(asset: screenshot.asset, pointSize: thumbnailPoints, placeholderTint: tint)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if screenshot.tier == .none {
                    UnsortedBadge()
                        .transition(AnyTransition.scale.combined(with: AnyTransition.opacity))
                }
            }
            .scaleEffect(isSelected ? 0.86 : 1)
            .background {
                if isSelected {
                    Rectangle()
                        .fill(tint.opacity(0.18))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelecting {
                    SelectionBadge(isSelected: isSelected, tint: tint)
                        .transition(AnyTransition.scale.combined(with: AnyTransition.opacity))
                }
            }
    }
}

/// Subtle sparkle on screenshots we haven't read yet. Static on purpose: during a first sort every
/// visible cell has one, and a repeating effect on each kept the whole grid re-rendering.
private struct UnsortedBadge: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.onBrand)
            .padding(Space.xxs + 1)
            .background(Circle().fill(Palette.brand.opacity(0.85)))
            .padding(Space.xxs + 2)
            .accessibilityHidden(true)
    }
}

private struct SelectionBadge: View {
    let isSelected: Bool
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? tint : Color.black.opacity(0.22))
            Circle()
                .strokeBorder(Color.white, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.onBrand)
                    .transition(AnyTransition.scale.combined(with: AnyTransition.opacity))
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
        .padding(Space.xs - 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Header

private struct GalleryHeader: View {
    let title: String
    let icon: String
    let eyebrow: String
    let tint: Color
    let gradient: LinearGradient
    let count: Int
    let unsortedCount: Int
    let thisWeekCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .center, spacing: Space.md) {
                Image(systemName: icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.onBrand)
                    .frame(width: 60, height: 60)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.md + 2, style: .continuous)
                            .fill(gradient)
                    }
                    .shadow(color: tint.opacity(0.35), radius: 12, x: 0, y: 6)
                    .rotationEffect(.degrees(appeared ? -8 : 0))
                    .scaleEffect(appeared ? 1 : 0.7)
                    .symbolEffect(.bounce, value: appeared)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow)
                        .font(.dsEyebrow)
                        .foregroundStyle(Palette.inkSecondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    Text(title)
                        .font(.dsDisplay)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            pills
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xs)
        .onAppear {
            guard !appeared else { return }
            Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
                appeared = true
            }
        }
    }

    private var pills: some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.sm))
            : AnyLayout(HStackLayout(spacing: Space.sm))
        return layout {
            StatPill(value: count, label: Brand.Copy.Gallery.screenshotsLabel, systemImage: "photo.stack.fill", tint: tint)
            if unsortedCount > 0 {
                StatPill(value: unsortedCount, label: Brand.Copy.Gallery.sortingLabel, systemImage: "sparkles", tint: Palette.brandSecondary)
            } else {
                StatPill(value: thisWeekCount, label: Brand.Copy.Gallery.thisWeekLabel, systemImage: "calendar", tint: Palette.brandSecondary)
            }
        }
    }
}

private struct GalleryInlineTitle: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.onBrand)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint))
                .accessibilityHidden(true)
            Text(title)
                .font(.dsHeadline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Sticky date header: a small glass capsule that floats over the grid.
private struct GallerySectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(title)
                .font(.dsHeadline)
                .foregroundStyle(.primary)
            Text(count, format: .number)
                .font(.dsCaption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(count)))
        }
        .padding(.horizontal, Space.sm + 2)
        .padding(.vertical, Space.xxs + 2)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct GalleryEmptyState: View {
    let icon: String
    let tint: Color

    @State private var bounce: Int = 0

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: icon)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 96, height: 96)
                .background(Circle().fill(tint.opacity(0.14)))
                .symbolEffect(.bounce, value: bounce)
                .accessibilityHidden(true)
            Text(Brand.Copy.Empty.emptyCollectionTitle)
                .font(.dsTitle2)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(Brand.Copy.Empty.emptyCollectionBody)
                .font(.dsCallout)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.xxl)
        .accessibilityElement(children: .combine)
        .onAppear {
            bounce += 1
        }
    }
}

// MARK: - Selection Action Bar

private struct SelectionActionBar: View {
    let count: Int
    let showsRemove: Bool
    let removeName: String
    let isPreparingShare: Bool
    let onShare: () -> Void
    let onMove: () -> Void
    let onRemove: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.xs) {
            Text(Brand.Copy.Gallery.selectedCount(count))
                .font(.dsCaption.weight(.heavy))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(count)))
                .dsAnimation(Motion.snappy, value: count)

            HStack(spacing: Space.xxs) {
                SelectionActionButton(
                    title: Brand.Copy.Gallery.share,
                    systemImage: "square.and.arrow.up",
                    tint: Palette.brand,
                    isBusy: isPreparingShare,
                    action: onShare
                )
                SelectionActionButton(
                    title: Brand.Copy.Gallery.move,
                    systemImage: "folder.fill",
                    tint: Palette.brand,
                    action: onMove
                )
                if showsRemove {
                    SelectionActionButton(
                        title: Brand.Copy.Gallery.remove,
                        systemImage: "minus.circle.fill",
                        tint: Palette.brandSecondary,
                        action: onRemove
                    )
                    .accessibilityHint(Brand.Copy.Gallery.removeHint(removeName))
                }
                SelectionActionButton(
                    title: Brand.Copy.Gallery.delete,
                    systemImage: "trash.fill",
                    tint: Palette.toss,
                    action: onDelete
                )
            }
            .disabled(count == 0)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.sm)
        .dsCard(radius: Radius.xl)
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    }
}

private struct SelectionActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isBusy: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(title: String, systemImage: String, tint: Color, isBusy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isBusy = isBusy
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xxs) {
                ZStack {
                    if isBusy {
                        ProgressView()
                            .tint(tint)
                    } else {
                        Image(systemName: systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(tint)
                            .symbolEffect(.bounce, value: isEnabled)
                    }
                }
                .frame(height: 28)

                Text(title)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(isBusy)
        .accessibilityLabel(title)
    }
}

// MARK: - Toasts & Cards

private struct GalleryInfoToast: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: systemImage)
                .font(.dsHeadline)
                .foregroundStyle(Palette.onBrand)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tint))
                .accessibilityHidden(true)
            Text(message)
                .font(.dsHeadline)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.sm)
        .dsCard(tint: tint, radius: Radius.xl)
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// "Add N similar screenshots to Receipts?" after a correction.
private struct GalleryPropagationCard: View {
    let suggestion: PropagationSuggestion
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let category: ScreenshotCategory = suggestion.category
        let previewIDs: [String] = Array(suggestion.ids.prefix(3))
        let previews: [Screenshot] = model.library.screenshots(ids: previewIDs)

        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .center, spacing: Space.sm) {
                PreviewFan(screenshots: previews, tint: category.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Brand.Copy.Gallery.propagationTitle(suggestion.ids.count, category.displayName))
                        .font(.dsHeadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Brand.Copy.Gallery.propagationBody)
                        .font(.dsCaption)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Space.xs) {
                Button(Brand.Copy.Gallery.propagationNotNow, action: onDecline)
                    .buttonStyle(.brand(.ghost, size: .compact))

                Button(action: onAccept) {
                    Label(Brand.Copy.Gallery.propagationAdd, systemImage: category.icon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.brand(.primary, size: .compact))
            }
        }
        .padding(Space.md)
        .dsCard(tint: category.color, radius: Radius.lg)
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }
}

/// Up to three tiny thumbnails fanned like cards.
private struct PreviewFan: View {
    let screenshots: [Screenshot]
    let tint: Color

    var body: some View {
        ZStack {
            ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, screenshot in
                AsyncThumbnail(asset: screenshot.asset, pointSize: 60, placeholderTint: tint)
                    .frame(width: 34, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.surface, lineWidth: 2)
                    }
                    .shadow(color: Color.black.opacity(0.14), radius: 3, x: 0, y: 2)
                    .rotationEffect(.degrees(Double(index - 1) * 10))
                    .offset(x: CGFloat(index - 1) * 12)
                    .zIndex(index == 1 ? 3 : Double(index))
            }
        }
        .frame(width: 70, height: 64)
        .accessibilityHidden(true)
    }
}

// MARK: - Move Sheet

private struct MoveToCategorySheet: View {
    let count: Int
    let current: ScreenshotCategory?
    let onPick: (ScreenshotCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var excluded: Set<ScreenshotCategory> {
        if let current, current != .all {
            return [current]
        }
        return []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Palette.brand)
                            .accessibilityHidden(true)
                        Text(Brand.Copy.Gallery.moveSubtitle)
                            .font(.dsCallout)
                            .foregroundStyle(Palette.inkSecondary)
                    }

                    CategoryPickerGrid(
                        searchText: searchText,
                        excluded: excluded,
                        isSelected: { _ in false },
                        onSelect: { category in
                            onPick(category)
                            dismiss()
                        }
                    )
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle(Brand.Copy.Gallery.moveTo)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(Brand.Copy.Labels.searchPrompt)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Brand.Copy.Review.close)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#if DEBUG
private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
#endif
