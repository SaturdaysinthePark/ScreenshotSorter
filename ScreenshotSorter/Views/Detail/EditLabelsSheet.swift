import SwiftUI

// MARK: - Edit Labels Sheet
/// Edit the stacks (categories) and tags of one or more screenshots.
/// Every change is a correction the app learns from, so it applies instantly (optimistically)
/// and reconciles with the live library once re-scoring lands.

struct EditLabelsSheet: View {
    let screenshotIDs: [String]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchText: String = ""
    @State private var newTag: String = ""
    @State private var pendingCategories: [ScreenshotCategory: Bool] = [:]
    @State private var pendingTags: [String: Bool] = [:]
    @State private var changeCount: Int = 0
    @FocusState private var isTagFieldFocused: Bool

    init(screenshotIDs: [String]) {
        self.screenshotIDs = screenshotIDs
    }

    // MARK: Live data

    private var screenshots: [Screenshot] {
        model.library.screenshots(ids: screenshotIDs)
    }

    /// Union of categories across the edited screenshots, in first-seen (confidence) order.
    private var liveCategories: [ScreenshotCategory] {
        var seen: Set<ScreenshotCategory> = []
        var order: [ScreenshotCategory] = []
        for screenshot in screenshots {
            for category in screenshot.categories where category != .all {
                if !seen.contains(category) {
                    seen.insert(category)
                    order.append(category)
                }
            }
        }
        return order
    }

    private var liveTags: [String] {
        var seen: Set<String> = []
        var order: [String] = []
        for screenshot in screenshots {
            for tag in screenshot.tags where !seen.contains(tag) {
                seen.insert(tag)
                order.append(tag)
            }
        }
        return order
    }

    private var currentCategories: [ScreenshotCategory] {
        let live: [ScreenshotCategory] = liveCategories
        var result: [ScreenshotCategory] = live.filter { pendingCategories[$0] != false }
        let added: [ScreenshotCategory] = pendingCategories
            .filter { entry in entry.value && !live.contains(entry.key) }
            .map { entry in entry.key }
            .sorted { $0.displayName < $1.displayName }
        result.append(contentsOf: added)
        return result
    }

    private var currentTags: [String] {
        let live: [String] = liveTags
        var result: [String] = live.filter { pendingTags[$0] != false }
        let added: [String] = pendingTags
            .filter { entry in entry.value && !live.contains(entry.key) }
            .map { entry in entry.key }
            .sorted()
        result.append(contentsOf: added)
        return result
    }

    private var liveSignature: String {
        let categories: String = liveCategories.map { $0.key }.joined(separator: ",")
        let tags: String = liveTags.joined(separator: ",")
        return categories + "|" + tags
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var trimmedNewTag: String {
        ScreenshotClassifier.normalizeTag(newTag)
    }

    // MARK: Body

    var body: some View {
        let current: [ScreenshotCategory] = currentCategories
        let currentSet: Set<ScreenshotCategory> = Set(current)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if !isSearching {
                        learnsCard
                        currentSection(current)
                        tagsSection
                    }

                    VStack(alignment: .leading, spacing: Space.sm) {
                        if !isSearching {
                            LabelsSectionHeader(title: Brand.Copy.Labels.allStacks, systemImage: "plus.square.on.square", tint: Palette.brandSecondary)
                        }
                        CategoryPickerGrid(
                            searchText: searchText,
                            isSelected: { category in currentSet.contains(category) },
                            onSelect: { category in
                                setCategory(category, included: !currentSet.contains(category))
                            }
                        )
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xl)
                .dsAnimation(Motion.snappy, value: isSearching)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle(Brand.Copy.Labels.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(Brand.Copy.Labels.searchPrompt)
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Brand.Copy.Labels.done) {
                        HapticManager.shared.lightTap()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: liveSignature) { _, _ in
                reconcilePending()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private var learnsCard: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Image(systemName: "sparkles")
                .font(.dsHeadline)
                .foregroundStyle(Palette.onBrand)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Palette.brandGradient))
                .symbolEffect(.bounce, value: changeCount)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if screenshotIDs.count > 1 {
                    Text(Brand.Copy.Labels.editing(screenshotIDs.count))
                        .font(.dsCaption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text(Brand.Copy.Labels.learns)
                    .font(.dsCallout)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .dsSurface(radius: Radius.md, tint: Palette.brand)
        .accessibilityElement(children: .combine)
    }

    private func currentSection(_ current: [ScreenshotCategory]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelsSectionHeader(title: Brand.Copy.Labels.current, systemImage: "square.stack.3d.up.fill", tint: Palette.brand)

            if current.isEmpty {
                Text(Brand.Copy.Labels.noneYet)
                    .font(.dsCallout)
                    .foregroundStyle(Palette.inkSecondary)
                    .transition(.opacity)
            } else {
                ChipFlowLayout(spacing: Space.xs, lineSpacing: Space.xs) {
                    ForEach(current, id: \.self) { category in
                        RemovableChip(
                            text: category.displayName,
                            systemImage: category.icon,
                            tint: category.color,
                            accessibilityText: Brand.Copy.Labels.removeCategory(category.displayName)
                        ) {
                            setCategory(category, included: false)
                        }
                        .transition(chipTransition)
                    }
                }
            }
        }
        .dsAnimation(Motion.bouncy, value: current)
    }

    private var tagsSection: some View {
        let tags: [String] = currentTags
        return VStack(alignment: .leading, spacing: Space.sm) {
            LabelsSectionHeader(title: Brand.Copy.Labels.tags, systemImage: "number", tint: Palette.info)

            if !tags.isEmpty {
                ChipFlowLayout(spacing: Space.xs, lineSpacing: Space.xs) {
                    ForEach(tags, id: \.self) { tag in
                        RemovableChip(
                            text: tag,
                            systemImage: "number",
                            tint: Palette.info,
                            accessibilityText: Brand.Copy.Labels.removeTag(tag)
                        ) {
                            setTag(tag, included: false)
                        }
                        .transition(chipTransition)
                    }
                }
            }

            tagField
        }
        .dsAnimation(Motion.bouncy, value: tags)
    }

    private var tagField: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "tag.fill")
                .font(.dsCallout)
                .foregroundStyle(Palette.info)
                .accessibilityHidden(true)

            TextField(Brand.Copy.Labels.addTagPlaceholder, text: $newTag)
                .font(.dsBody)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isTagFieldFocused)
                .onSubmit { addTag() }

            Button {
                addTag()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.brand)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableCard)
            .disabled(trimmedNewTag.isEmpty)
            .opacity(trimmedNewTag.isEmpty ? 0.4 : 1)
            .accessibilityLabel(Brand.Copy.Labels.addTag)
        }
        .padding(.leading, Space.md)
        .padding(.trailing, Space.xxs)
        .padding(.vertical, Space.xxs)
        .dsSurface(radius: Radius.md)
    }

    private var chipTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.scale(scale: 0.6).combined(with: AnyTransition.opacity)
    }

    // MARK: Actions

    private func setCategory(_ category: ScreenshotCategory, included: Bool) {
        guard !screenshotIDs.isEmpty else { return }
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            pendingCategories[category] = included
            changeCount += 1
        }
        // AppModel plays the correction haptic.
        model.setCategory(category, included: included, for: screenshotIDs)
    }

    private func setTag(_ tag: String, included: Bool) {
        guard !screenshotIDs.isEmpty else { return }
        let normalized: String = ScreenshotClassifier.normalizeTag(tag)
        guard !normalized.isEmpty else { return }
        Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
            pendingTags[normalized] = included
            changeCount += 1
        }
        model.setTag(normalized, included: included, for: screenshotIDs)
    }

    private func addTag() {
        let normalized: String = trimmedNewTag
        guard !normalized.isEmpty else {
            HapticManager.shared.warning()
            return
        }
        setTag(normalized, included: true)
        newTag = ""
    }

    /// Drop optimistic entries once the live library agrees with them.
    private func reconcilePending() {
        let liveCategorySet: Set<ScreenshotCategory> = Set(liveCategories)
        let liveTagSet: Set<String> = Set(liveTags)
        let categories: [ScreenshotCategory: Bool] = pendingCategories.filter { entry in
            liveCategorySet.contains(entry.key) != entry.value
        }
        let tags: [String: Bool] = pendingTags.filter { entry in
            liveTagSet.contains(entry.key) != entry.value
        }
        if categories != pendingCategories {
            pendingCategories = categories
        }
        if tags != pendingTags {
            pendingTags = tags
        }
    }
}

// MARK: - Section Header

struct LabelsSectionHeader: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.onBrand)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint))
                .accessibilityHidden(true)
            Text(title)
                .font(.dsHeadline)
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Removable Chip

/// Tinted capsule with a trailing remove glyph. The whole chip is the tap target.
struct RemovableChip: View {
    let text: String
    let systemImage: String?
    let tint: Color
    let accessibilityText: String
    let onRemove: () -> Void

    init(text: String, systemImage: String?, tint: Color, accessibilityText: String, onRemove: @escaping () -> Void) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.accessibilityText = accessibilityText
        self.onRemove = onRemove
    }

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: Space.xxs + 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .foregroundStyle(tint)
                }
                Text(text)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.leading, Space.sm)
            .padding(.trailing, Space.xs)
            .padding(.vertical, Space.xs - 1)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                    }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(accessibilityText)
    }
}

// MARK: - Category Picker Grid
/// All assignable categories grouped by `CategoryGroup`, filtered by `searchText`.
/// Shared by the edit-labels sheet and the gallery's "Move to…" sheet.

struct CategoryPickerGrid: View {
    let searchText: String
    let isSelected: (ScreenshotCategory) -> Bool
    let onSelect: (ScreenshotCategory) -> Void
    let excluded: Set<ScreenshotCategory>

    init(
        searchText: String,
        excluded: Set<ScreenshotCategory> = [],
        isSelected: @escaping (ScreenshotCategory) -> Bool,
        onSelect: @escaping (ScreenshotCategory) -> Void
    ) {
        self.searchText = searchText
        self.excluded = excluded
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: Space.sm)]

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func members(of group: CategoryGroup) -> [ScreenshotCategory] {
        let needle: String = query
        return ScreenshotCategory.assignable.filter { category in
            guard category.group == group, !excluded.contains(category) else { return false }
            if needle.isEmpty { return true }
            if category.displayName.lowercased().contains(needle) { return true }
            return group.rawValue.lowercased().contains(needle)
        }
    }

    private var hasResults: Bool {
        CategoryGroup.allCases.contains { group in !members(of: group).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ForEach(CategoryGroup.allCases, id: \.self) { group in
                let items: [ScreenshotCategory] = members(of: group)
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(spacing: Space.xs) {
                            Image(systemName: group.icon)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(group.color)
                                .accessibilityHidden(true)
                            Text(group.rawValue)
                                .font(.dsEyebrow)
                                .foregroundStyle(Palette.inkSecondary)
                                .textCase(.uppercase)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)

                        LazyVGrid(columns: columns, spacing: Space.sm) {
                            ForEach(items, id: \.self) { category in
                                CategoryPickerTile(category: category, isSelected: isSelected(category)) {
                                    onSelect(category)
                                }
                            }
                        }
                    }
                }
            }

            if !hasResults {
                VStack(spacing: Space.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.inkSecondary)
                        .accessibilityHidden(true)
                    Text(Brand.Copy.Labels.noMatches)
                        .font(.dsCallout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xl)
            }
        }
    }
}

// MARK: - Category Picker Tile

struct CategoryPickerTile: View {
    let category: ScreenshotCategory
    let isSelected: Bool
    let action: () -> Void

    init(category: ScreenshotCategory, isSelected: Bool, action: @escaping () -> Void) {
        self.category = category
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            HapticManager.shared.selectionChanged()
            action()
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: category.icon)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Palette.onBrand)
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(category.gradient)
                    }
                    .accessibilityHidden(true)

                Text(category.displayName)
                    .font(.dsCallout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? category.color : Palette.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(radius: Radius.md, tint: isSelected ? category.color : nil)
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(isSelected ? Brand.Copy.Labels.removeCategory(category.displayName) : Brand.Copy.Labels.addCategory(category.displayName))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Chip Flow Layout
/// Wraps chips onto new lines like text. Chips wider than the line are capped to the line width.

struct ChipFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    init(spacing: CGFloat = Space.xs, lineSpacing: CGFloat = Space.xs) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth: CGFloat = proposal.width ?? .infinity
        let result: ChipFlowResult = arrange(subviews: subviews, maxWidth: maxWidth)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result: ChipFlowResult = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, subview) in subviews.enumerated() {
            guard index < result.frames.count else { continue }
            let frame: CGRect = result.frames[index]
            let origin: CGPoint = CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY)
            subview.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> ChipFlowResult {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let ideal: CGSize = subview.sizeThatFits(.unspecified)
            let width: CGFloat = min(ideal.width, maxWidth)
            var height: CGFloat = ideal.height
            if width < ideal.width {
                height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            }
            if x > 0 && x + width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: width, height: height))
            x += width + spacing
            rowHeight = max(rowHeight, height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return ChipFlowResult(frames: frames, size: CGSize(width: usedWidth, height: y + rowHeight))
    }
}

struct ChipFlowResult {
    let frames: [CGRect]
    let size: CGSize
}
