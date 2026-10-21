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
    /// How many upcoming assets to pre-cache after the last visible cell.
    static let prefetchCount: Int = 24
    /// Seconds the undo toast stays up.
    static let undoDuration: Double = 5
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

    init(kind: CollectionKind, zoomNamespace: Namespace.ID? = nil) {
        self.kind = kind
        self.zoomNamespace = zoomNamespace
    }

    // MARK: Body

    var body: some View {
        // Sections, counts and ids are O(library); rebuild them once per library change, not per body
        let derived: GalleryDerived = derivedCache.value(revision: model.library.revision, kind: kind, sort: sortOption) {
            let collection: ScreenshotCollection = model.library.collection(for: kind)
            let items: [Screenshot] = orderedItems(collection)
            return GalleryDerived(
                collection: collection,
                items: items,
                sections: GallerySection.make(from: items, groupByDate: sortOption != .relevancy),
                ids: items.map { $0.id },
                unsortedCount: unsortedCount(items),
                thisWeekCount: thisWeekCount(items)
            )
        }
        let collection: ScreenshotCollection = derived.collection
        let items: [Screenshot] = derived.items
        let sections: [GallerySection] = derived.sections
        let ids: [String] = derived.ids

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    GalleryHeader(
                        title: collection.title,
                        icon: collection.icon,
                        eyebrow: eyebrow,
                        tint: tint,
                        gradient: gradient,
                        count: items.count,
                        unsortedCount: derived.unsortedCount,
                        thisWeekCount: derived.thisWeekCount
                    )
                    .padding(.bottom, Space.md)

                    if items.isEmpty {
                        GalleryEmptyState(icon: collection.icon, tint: tint)
                            .transition(AnyTransition.opacity)
                    } else {
                        ForEach(sections) { section in
                            Section {
                                LazyVGrid(columns: columns, spacing: GalleryMetrics.spacing) {
                                    ForEach(section.items) { screenshot in
                                        cell(for: screenshot, items: items)
                                    }
                                }
                            } header: {
                                if let title = section.title {
                                    GallerySectionHeader(title: title, count: section.items.count)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, bottomContentPadding)
                .dsAnimation(Motion.gentle, value: ids)
            }
            .scrollIndicators(.automatic)
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
        }
        .background { backgroundLayer }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar { toolbarContent(items: items, collection: collection) }
        .overlay(alignment: .bottom) {
            bottomStack(items: items)
        }
        .onChange(of: ids) { _, newIDs in
            pruneSelection(to: newIDs)
        }
        .onDisappear {
            visibility.cancel()
        }
        .fullScreenCover(item: $viewer) { session in
            PhotoDetailView(
                screenshots: session.screenshots,
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
            return model.library.collection(for: kind).title
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

    private func orderedItems(_ collection: ScreenshotCollection) -> [Screenshot] {
        switch sortOption {
        case .dateDescending:
            return collection.screenshots
        case .dateAscending:
            return Array(collection.screenshots.reversed())
        case .relevancy:
            return collection.sorted(by: .relevancy)
        }
    }

    private func unsortedCount(_ items: [Screenshot]) -> Int {
        items.reduce(0) { partial, screenshot in
            partial + (screenshot.tier == .none ? 1 : 0)
        }
    }

    private func thisWeekCount(_ items: [Screenshot]) -> Int {
        let cutoff: Date = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return items.reduce(0) { partial, screenshot in
            partial + (screenshot.creationDate >= cutoff ? 1 : 0)
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

    private func cell(for screenshot: Screenshot, items: [Screenshot]) -> some View {
        let isSelected: Bool = selection.contains(screenshot.id)
        let dateText: String = screenshot.creationDate.formatted(date: .abbreviated, time: .shortened)
        var label: String = Brand.Copy.Gallery.cellAccessibility(title: screenshot.title, date: dateText)
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
        .matchedTransitionSource(id: screenshot.id, in: photoNamespace)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(screenshot, items: items)
        }
        .contextMenu {
            cellMenu(for: screenshot)
        }
        .onAppear {
            visibility.noteAppeared(screenshot.id) { visibleIDs, lastID in
                handleVisible(visibleIDs, lastID: lastID, items: items)
            }
        }
        .transition(cellTransition)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? Brand.Copy.Gallery.selected : "")
        .accessibilityHint(isSelecting ? Brand.Copy.Gallery.selectHint : Brand.Copy.Gallery.openHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction {
            handleTap(screenshot, items: items)
        }
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
    private func toolbarContent(items: [Screenshot], collection: ScreenshotCollection) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            GalleryInlineTitle(title: collection.title, icon: collection.icon, tint: tint)
                .opacity(showInlineTitle ? 1 : 0)
                .offset(y: showInlineTitle ? 0 : 6)
                .accessibilityHidden(!showInlineTitle)
        }

        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                let allSelected: Bool = !items.isEmpty && selection.count >= items.count
                Button(allSelected ? Brand.Copy.Gallery.deselectAll : Brand.Copy.Gallery.selectAll) {
                    toggleSelectAll(items, allSelected: allSelected)
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
                .disabled(items.isEmpty)
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

    private func bottomStack(items: [Screenshot]) -> some View {
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
                    onShare: { share(selectedIDs(in: items)) },
                    onMove: { moveRequest = GalleryIDsRequest(ids: selectedIDs(in: items)) },
                    onRemove: { performRemove(selectedIDs(in: items)) },
                    onDelete: { deleteRequest = GalleryIDsRequest(ids: selectedIDs(in: items)) }
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

    private func handleTap(_ screenshot: Screenshot, items: [Screenshot]) {
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
        viewer = GalleryViewerSession(screenshots: items, initialID: screenshot.id)
    }

    /// Batched from cell `onAppear`: prioritise analysis for what's on screen and pre-cache what's next.
    private func handleVisible(_ visibleIDs: [String], lastID: String, items: [Screenshot]) {
        model.boost(visibleIDs)
        guard let index = items.firstIndex(where: { $0.id == lastID }) else { return }
        let lower: Int = index + 1
        let upper: Int = min(items.count, index + 1 + GalleryMetrics.prefetchCount)
        guard lower < upper else { return }
        let assets: [PHAsset] = items[lower..<upper].map { $0.asset }
        ThumbnailLoader.shared.startCaching(assets, size: ThumbnailLoader.pixelSize(points: thumbnailPoints))
    }

    private func selectedIDs(in items: [Screenshot]) -> [String] {
        // Keep grid order so shares/moves feel predictable.
        items.compactMap { selection.contains($0.id) ? $0.id : nil }
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

    private func toggleSelectAll(_ items: [Screenshot], allSelected: Bool) {
        HapticManager.shared.selectionChanged()
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            if allSelected {
                selection = []
            } else {
                selection = Set(items.map { $0.id })
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
    let screenshots: [Screenshot]
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
/// Everything the gallery body derives from the library, cached per library revision.
struct GalleryDerived {
    let collection: ScreenshotCollection
    let items: [Screenshot]
    let sections: [GallerySection]
    let ids: [String]
    let unsortedCount: Int
    let thisWeekCount: Int
}

@MainActor
final class GalleryDerivedCache {
    private var key: (revision: Int, kind: CollectionKind, sort: SortOption)?
    private var cached: GalleryDerived?

    func value(revision: Int, kind: CollectionKind, sort: SortOption, build: () -> GalleryDerived) -> GalleryDerived {
        if let key, let cached, key.revision == revision, key.kind == kind, key.sort == sort { return cached }
        let value = build()
        key = (revision, kind, sort)
        cached = value
        return value
    }
}

struct GallerySection: Identifiable {
    let id: String
    let title: String?
    let items: [Screenshot]

    static func make(from items: [Screenshot], groupByDate: Bool, now: Date = Date(), calendar: Calendar = .current) -> [GallerySection] {
        guard !items.isEmpty else { return [] }
        guard groupByDate else {
            return [GallerySection(id: "all", title: nil, items: items)]
        }

        let startOfToday: Date = calendar.startOfDay(for: now)
        let startOfYesterday: Date = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek: Date = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfYesterday
        let currentYear: Int = calendar.component(.year, from: now)

        var sections: [GallerySection] = []
        var usedKeys: Set<String> = []
        var currentKey: String = ""
        var currentTitle: String = ""
        var bucket: [Screenshot] = []

        func flush() {
            guard !bucket.isEmpty else { return }
            var key: String = currentKey
            var suffix: Int = 1
            while usedKeys.contains(key) {
                suffix += 1
                key = currentKey + "#" + String(suffix)
            }
            usedKeys.insert(key)
            sections.append(GallerySection(id: key, title: currentTitle, items: bucket))
            bucket = []
        }

        for item in items {
            let date: Date = item.creationDate
            let key: String
            let title: String
            if date >= startOfToday {
                key = "today"
                title = Brand.Copy.Gallery.today
            } else if date >= startOfYesterday {
                key = "yesterday"
                title = Brand.Copy.Gallery.yesterday
            } else if date >= startOfWeek {
                key = "week"
                title = Brand.Copy.Gallery.thisWeek
            } else {
                let components: DateComponents = calendar.dateComponents([.year, .month], from: date)
                let year: Int = components.year ?? 0
                let month: Int = components.month ?? 0
                key = "m-" + String(year) + "-" + String(month)
                if key == currentKey {
                    title = currentTitle
                } else if year == currentYear {
                    title = date.formatted(.dateTime.month(.wide))
                } else {
                    title = date.formatted(.dateTime.month(.wide).year())
                }
            }
            if key != currentKey {
                flush()
                currentKey = key
                currentTitle = title
            }
            bucket.append(item)
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

/// Subtle sparkle on screenshots we haven't read yet.
private struct UnsortedBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "sparkles")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.onBrand)
            .padding(Space.xxs + 1)
            .background(Circle().fill(Palette.brand.opacity(0.85)))
            .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
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
