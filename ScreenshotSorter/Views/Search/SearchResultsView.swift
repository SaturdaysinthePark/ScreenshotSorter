import SwiftUI

/// Search results: shows how the query was understood, then ranked matches with text snippets.
struct SearchResultsView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoomNamespace
    @State private var selection: SearchSelection?
    /// Page currently shown in the detail pager (zoom returns to this row)
    @State private var currentID: String?

    private struct SearchSelection: Identifiable {
        let id: String
    }

    var body: some View {
        let results = model.searchResults
        let screenshots = model.library.screenshots(ids: results.map(\.id))

        LazyVStack(alignment: .leading, spacing: Space.md) {
            UnderstoodQueryRow(query: model.parsedQuery)
                .padding(.horizontal, Space.gutter)

            if model.isSearchRunning && results.isEmpty {
                HStack(spacing: Space.xs) {
                    ProgressView()
                    Text(Brand.Copy.Search.searching)
                        .font(.dsCallout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Space.xl)
            } else if results.isEmpty {
                NoResultsView()
                    .padding(.top, Space.xl)
            } else {
                Text(Brand.Copy.Search.resultCount(results.count))
                    .font(.dsCaption)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, Space.gutter)
                    .contentTransition(.numericText())

                ForEach(results) { hit in
                    if let screenshot = model.library.screenshot(id: hit.id) {
                        Button {
                            HapticManager.shared.lightTap()
                            currentID = hit.id
                            selection = SearchSelection(id: hit.id)
                        } label: {
                            SearchResultRow(screenshot: screenshot, snippet: hit.snippet, zoomNamespace: zoomNamespace)
                        }
                        .pressable()
                        .padding(.horizontal, Space.gutter)
                    }
                }
            }
        }
        .padding(.vertical, Space.md)
        .dsAnimation(Motion.snappy, value: results.map(\.id))
        .fullScreenCover(item: $selection) { item in
            PhotoDetailView(
                screenshots: screenshots,
                initialID: item.id,
                context: nil,
                onCurrentChange: { id in currentID = id }
            )
            .navigationTransition(.zoom(sourceID: currentID ?? item.id, in: zoomNamespace))
        }
    }
}

/// Chips explaining the parsed query ("Receipts · Last week · Links").
private struct UnderstoodQueryRow: View {
    let query: ParsedQuery

    var body: some View {
        let chips = chipModels
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    Text(Brand.Copy.Search.understoodAs)
                        .font(.dsCaption)
                        .foregroundStyle(Palette.inkSecondary)
                    ForEach(chips, id: \.text) { chip in
                        TagChip(chip.text, systemImage: chip.icon, tint: chip.tint)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private struct ChipModel {
        let text: String
        let icon: String
        let tint: Color
    }

    private var chipModels: [ChipModel] {
        var chips: [ChipModel] = []
        for category in query.categories.sorted(by: { $0.displayName < $1.displayName }) {
            chips.append(ChipModel(text: category.displayName, icon: category.icon, tint: category.color))
        }
        for app in query.apps.sorted() {
            chips.append(ChipModel(text: app.capitalized, icon: "app.fill", tint: Palette.brandSecondary))
        }
        if let range = query.dateRange {
            let formatter = DateIntervalFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            chips.append(ChipModel(text: formatter.string(from: range) ?? "", icon: "calendar", tint: Palette.info))
        }
        for type in query.entityTypes.sorted(by: { $0.rawValue < $1.rawValue }) {
            let token = SearchToken.entity(type)
            chips.append(ChipModel(text: token.title, icon: token.systemImage, tint: Palette.warning))
        }
        for phrase in query.phrases {
            chips.append(ChipModel(text: "“\(phrase)”", icon: "quote.opening", tint: Palette.brand))
        }
        if !query.terms.isEmpty {
            chips.append(ChipModel(text: query.terms.joined(separator: " "), icon: "text.magnifyingglass", tint: Palette.brand))
        }
        return chips.filter { !$0.text.isEmpty }
    }
}

private struct SearchResultRow: View {
    let screenshot: Screenshot
    let snippet: String?
    let zoomNamespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            AsyncThumbnail(asset: screenshot.asset, pointSize: 90, placeholderTint: screenshot.categories.first?.color ?? Palette.brand)
                .frame(width: 64, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .matchedTransitionSource(id: screenshot.id, in: zoomNamespace)

            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(screenshot.title ?? screenshot.categories.first?.displayName ?? Brand.Copy.Home.allScreenshots)
                    .font(.dsHeadline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let snippet, !snippet.isEmpty {
                    SnippetText(snippet: snippet)
                        .lineLimit(3)
                }
                HStack(spacing: Space.xxs) {
                    if let category = screenshot.categories.first, category != .other {
                        Label(category.displayName, systemImage: category.icon)
                            .foregroundStyle(category.color)
                    }
                    if let app = screenshot.app {
                        Text("· \(app)")
                    }
                    Text("· \(screenshot.creationDate.formatted(.relative(presentation: .named)))")
                }
                .font(.dsCaption)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .dsSurface(radius: Radius.md)
        .accessibilityElement(children: .combine)
    }
}

/// Renders FTS snippets, highlighting text wrapped in [ ].
private struct SnippetText: View {
    let snippet: String

    var body: some View {
        Text(attributed)
            .font(.dsCallout)
            .foregroundStyle(Palette.inkSecondary)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        var remaining = Substring(snippet)
        while let open = remaining.firstIndex(of: "[") {
            result += AttributedString(String(remaining[remaining.startIndex..<open]))
            let afterOpen = remaining.index(after: open)
            guard let close = remaining[afterOpen...].firstIndex(of: "]") else {
                remaining = remaining[open...]
                break
            }
            var highlighted = AttributedString(String(remaining[afterOpen..<close]))
            highlighted.foregroundColor = Palette.ink
            highlighted.backgroundColor = Palette.brand.opacity(0.18)
            highlighted.font = .dsCallout.bold()
            result += highlighted
            remaining = remaining[remaining.index(after: close)...]
        }
        result += AttributedString(String(remaining))
        return result
    }
}

private struct NoResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.brand.gradient)
            Text(Brand.Copy.Empty.noResultsTitle)
                .font(.dsTitle2)
                .foregroundStyle(Palette.ink)
            Text(Brand.Copy.Empty.noResultsBody)
                .font(.dsCallout)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
            VStack(spacing: Space.xs) {
                Text(Brand.Copy.Search.tipsTitle)
                    .font(.dsEyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkSecondary)
                FlowTips(tips: Brand.Copy.Search.tips) { tip in
                    model.searchText = tip
                }
            }
            .padding(.top, Space.sm)
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity)
    }
}

private struct FlowTips: View {
    let tips: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(spacing: Space.xs) {
            ForEach(tips, id: \.self) { tip in
                TagChip(tip, systemImage: "magnifyingglass", tint: Palette.brand) {
                    onTap(tip)
                }
            }
        }
    }
}
