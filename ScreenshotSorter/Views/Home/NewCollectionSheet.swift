import SwiftUI

/// "New collection": type what it's for, see what already matches, create. New screenshots that look like
/// its members join it later on their own.
struct NewCollectionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var name = ""
    @State private var matches: [String] = []
    @State private var isSearching = false
    @FocusState private var nameFocused: Bool

    private static let examples = ["Barcelona trip", "Gift ideas", "Coffee spots", "Outfits", "Recipes to try"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    TextField(Brand.Copy.NewCollection.placeholder, text: $name)
                        .font(.dsTitle2)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .padding(Space.md)
                        .dsSurface(radius: Radius.lg, tint: Palette.brand)
                        .onSubmit { if canCreate { create() } }

                    if name.trimmingCharacters(in: .whitespaces).count < 2 {
                        examples
                    } else {
                        if let existing = existingCategory {
                            Label(Brand.Copy.NewCollection.alreadyExists(existing.displayName), systemImage: existing.icon)
                                .font(.dsCallout)
                                .foregroundStyle(existing.color)
                        }
                        Text(statusText)
                            .font(.dsCallout)
                            .foregroundStyle(Palette.inkSecondary)
                            .contentTransition(.numericText())
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(matches.prefix(40), id: \.self) { id in
                                if let screenshot = model.library.screenshot(id: id) {
                                    AsyncThumbnail(asset: screenshot.asset, pointSize: 90)
                                        .aspectRatio(0.62, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .padding(Space.gutter)
            }
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle(Brand.Copy.NewCollection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Brand.Copy.NewCollection.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Brand.Copy.NewCollection.create) { create() }
                        .disabled(!canCreate)
                }
            }
            .task(id: name) {
                // Debounce typing; results update as the name settles
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isSearching = true
                let found = await model.collectionMatches(for: name)
                guard !Task.isCancelled else { return }
                Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
                    matches = found
                    isSearching = false
                }
            }
            .onAppear { nameFocused = true }
        }
        .presentationDetents([.large])
    }

    /// A category with this name is already sorted automatically: say so rather than make a twin
    private var existingCategory: ScreenshotCategory? {
        let typed = name.trimmingCharacters(in: .whitespaces).lowercased()
        return ScreenshotCategory.assignable.first { category in
            category != .other && (category.displayName.lowercased() == typed || category.key.lowercased() == typed
                || category.displayName.lowercased().hasPrefix(typed + " "))
        }
    }

    private var canCreate: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2 && !matches.isEmpty
    }

    private var statusText: String {
        if isSearching && matches.isEmpty { return Brand.Copy.NewCollection.searching }
        return matches.isEmpty ? Brand.Copy.NewCollection.noMatches : Brand.Copy.NewCollection.matches(matches.count)
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(Brand.Copy.NewCollection.hint)
                .font(.dsCallout)
                .foregroundStyle(Palette.inkSecondary)
            FlowingChips(items: NewCollectionSheet.examples) { example in
                name = example
            }
        }
    }

    private func create() {
        guard canCreate else { return }
        HapticManager.shared.success()
        var title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if title == title.lowercased(), let first = title.first { title = first.uppercased() + title.dropFirst() }
        model.createCollection(named: title, memberIDs: matches)
        dismiss()
    }
}

/// Wrapping row of tappable suggestion chips
private struct FlowingChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        ChipFlowLayout(spacing: Space.xs) { chips }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { item in
            Button(item) { onTap(item) }
                .buttonStyle(.brand(.secondary, size: .compact))
        }
    }
}
