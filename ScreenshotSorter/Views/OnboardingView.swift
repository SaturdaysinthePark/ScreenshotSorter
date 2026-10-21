import SwiftUI

// MARK: - Onboarding View
/// Three pages, each with a live mini-demo:
///  1. A messy pile of screenshots that sorts itself into colored stacks.
///  2. A real swipe card you can drag and fling (KEEP / TOSS stamps).
///  3. On-device privacy + a "search inside screenshots" teaser.

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageCount = 3

    init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            AmbientGlow(color: pageTint, secondary: Palette.brand, intensity: 0.2)
                .id(currentPage)
                .transition(.opacity)

            VStack(spacing: 0) {
                topBar

                TabView(selection: $currentPage) {
                    OnboardingPage(
                        eyebrow: Brand.Copy.Onboarding.page1Eyebrow,
                        title: Brand.Copy.Onboarding.page1Title,
                        message: Brand.Copy.Onboarding.page1Body,
                        tint: Palette.brandSecondary
                    ) {
                        PileSortDemo(isActive: currentPage == 0)
                    }
                    .tag(0)

                    OnboardingPage(
                        eyebrow: Brand.Copy.Onboarding.page2Eyebrow,
                        title: Brand.Copy.Onboarding.page2Title,
                        message: Brand.Copy.Onboarding.page2Body,
                        tint: Palette.brand
                    ) {
                        SwipePlaygroundDemo()
                    }
                    .tag(1)

                    OnboardingPage(
                        eyebrow: Brand.Copy.Onboarding.page3Eyebrow,
                        title: Brand.Copy.Onboarding.page3Title,
                        message: Brand.Copy.Onboarding.page3Body,
                        tint: Palette.keep
                    ) {
                        PrivacySearchDemo(isActive: currentPage == 2)
                    }
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
            }
        }
        .animation(Motion.animation(Motion.gentle, reduceMotion: reduceMotion), value: currentPage)
        .onChange(of: currentPage) { _, _ in
            HapticManager.shared.pageTurn()
        }
    }

    private var pageTint: Color {
        switch currentPage {
        case 0: return Palette.brandSecondary
        case 1: return Palette.brand
        default: return Palette.keep
        }
    }

    private var isLastPage: Bool { currentPage >= pageCount - 1 }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Text(Brand.appName)
                .font(.dsHeadline)
                .foregroundStyle(Palette.ink)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .lineLimit(1)
                .accessibilityHidden(true)
            Spacer()
            Button(Brand.Copy.Onboarding.skip) {
                HapticManager.shared.lightTap()
                completeOnboarding()
            }
            .buttonStyle(.brand(.ghost, size: .compact))
            .opacity(isLastPage ? 0 : 1)
            .disabled(isLastPage)
            .accessibilityHidden(isLastPage)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xs)
        .frame(minHeight: 44)
    }

    private var bottomBar: some View {
        VStack(spacing: Space.lg) {
            OnboardingPageDots(count: pageCount, current: currentPage)

            Button {
                if isLastPage {
                    completeOnboarding()
                } else {
                    HapticManager.shared.lightTap()
                    Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
                        currentPage += 1
                    }
                }
            } label: {
                HStack(spacing: Space.xs) {
                    Text(isLastPage ? Brand.Copy.Onboarding.getStarted : Brand.Copy.Onboarding.next)
                        .contentTransition(.interpolate)
                    Image(systemName: isLastPage ? "sparkles" : "arrow.right")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.brand())
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.md)
        .padding(.top, Space.sm)
    }

    private func completeOnboarding() {
        HapticManager.shared.success()
        OnboardingKeys.hasCompletedOnboarding = true
        Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
            hasCompletedOnboarding = true
        }
    }
}

// MARK: - Page Layout

private struct OnboardingPage<Demo: View>: View {
    let eyebrow: String
    let title: String
    let message: String
    let tint: Color
    let demo: Demo

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(eyebrow: String, title: String, message: String, tint: Color, @ViewBuilder demo: () -> Demo) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.tint = tint
        self.demo = demo()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                // At accessibility sizes the demo shrinks so the title and copy start on screen.
                demo
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .scaleEffect(dynamicTypeSize.isAccessibilitySize ? 0.62 : 1)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 200 : 320)
                    .frame(maxWidth: .infinity)

                VStack(spacing: Space.sm) {
                    Text(eyebrow.uppercased())
                        .font(.dsEyebrow)
                        .tracking(1.2)
                        .foregroundStyle(tint)

                    Text(title)
                        .font(.dsDisplay)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(message)
                        .font(.dsBody)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.lg)
            }
            .padding(.top, Space.sm)
            .padding(.bottom, Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

// MARK: - Page Dots

private struct OnboardingPageDots: View {
    let count: Int
    let current: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == current ? AnyShapeStyle(Palette.brandGradientHorizontal) : AnyShapeStyle(Palette.inkSecondary.opacity(0.28)))
                    .frame(width: index == current ? 28 : 8, height: 8)
            }
        }
        .animation(Motion.animation(Motion.bouncy, reduceMotion: reduceMotion), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.Copy.Onboarding.pageAccessibility(current + 1, of: count))
    }
}

// MARK: - Demo 1: Pile → Stacks

private struct PileSortDemo: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSorted = false

    private let groups: [CategoryGroup] = [.foodDrink, .communication, .socialMedia]
    private let contents: [MiniScreenshot.Content] = [.photo, .chat, .list]
    private let cardWidth: CGFloat = 46

    // Hand-tuned "messy pile" poses (x, y, rotation) for 9 cards.
    private let pileX: [CGFloat] = [-74, 46, -18, 88, -100, 8, 64, -46, 26]
    private let pileY: [CGFloat] = [-46, -66, 6, 26, 40, -18, -84, 74, 66]
    private let pileR: [Double] = [-24, 18, -8, 28, -32, 6, -16, 22, 12]

    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                card(index)
            }

            ForEach(0..<groups.count, id: \.self) { column in
                groupLabel(column)
            }
        }
        .frame(width: 320, height: 300)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A messy pile of screenshots sorting itself into Food, Chats and Social stacks.")
        .task(id: isActive) {
            await runLoop()
        }
    }

    private func card(_ index: Int) -> some View {
        let column: Int = index / 3
        let row: Int = index % 3
        let group: CategoryGroup = groups[column]
        let x: CGFloat = isSorted ? CGFloat(column - 1) * 104 : pileX[index]
        let y: CGFloat = isSorted ? CGFloat(row) * -9 - 14 : pileY[index]
        let rotation: Double = isSorted ? Double(row - 1) * 5 : pileR[index]
        let z: Double = isSorted ? Double(row) : Double(index)

        return MiniScreenshot(gradient: group.gradient, width: cardWidth, content: contents[column])
            .shadow(color: Color.black.opacity(0.14), radius: 5, x: 0, y: 3)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: y)
            .zIndex(z)
            .animation(cardAnimation(index), value: isSorted)
    }

    private func groupLabel(_ column: Int) -> some View {
        let group: CategoryGroup = groups[column]
        return TagChip(group.chipName, systemImage: group.icon, tint: group.color)
            .background(Capsule(style: .continuous).fill(Palette.surface))
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .scaleEffect(isSorted ? 1 : 0.5)
            .opacity(isSorted ? 1 : 0)
            .offset(x: CGFloat(column - 1) * 104, y: 88)
            .zIndex(20)
            .animation(cardAnimation(9 + column), value: isSorted)
    }

    private func cardAnimation(_ index: Int) -> Animation {
        let base: Animation = isSorted ? Motion.bouncy : Motion.gentle
        return Motion.animation(base.delay(Motion.stagger(index, step: 0.035)), reduceMotion: reduceMotion)
    }

    private func runLoop() async {
        guard isActive else { return }
        if reduceMotion {
            isSorted = true
            return
        }
        isSorted = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            isSorted = true
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            isSorted = false
        }
    }
}

// MARK: - Demo 2: Swipe Playground

private struct SwipePlaygroundDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var topIndex = 0
    @State private var drag: CGSize = .zero
    @State private var isPastThreshold = false
    @State private var flying: [Int: FlyAway] = [:]
    @State private var keptCount = 0
    @State private var tossedCount = 0

    private let threshold: CGFloat = 90
    private let cardWidth: CGFloat = 150
    private let palette: [CategoryGroup] = [.communication, .foodDrink, .socialMedia, .placesTravel, .mediaEntertainment, .eventsPlanning]
    private let contents: [MiniScreenshot.Content] = [.chat, .photo, .list]

    private struct FlyAway {
        let offset: CGSize
        let rotation: Double
        let keep: Bool
    }

    private struct Entry: Identifiable {
        let id: Int
        let depth: Int
        let fly: FlyAway?
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        for depth in stride(from: 1, through: 0, by: -1) {
            let id: Int = topIndex + depth
            result.append(Entry(id: id, depth: depth, fly: nil))
        }
        let flyingIDs: [Int] = flying.keys.sorted()
        for id in flyingIDs {
            result.append(Entry(id: id, depth: 0, fly: flying[id]))
        }
        return result
    }

    var body: some View {
        VStack(spacing: Space.md) {
            ZStack {
                ForEach(entries) { entry in
                    cardView(entry)
                }
            }
            .frame(height: 250)

            HStack(spacing: Space.sm) {
                counter(value: tossedCount, label: Brand.Copy.Review.toss, arrowLeading: true, tint: Palette.toss, isLit: drag.width < -20)
                counter(value: keptCount, label: Brand.Copy.Review.keep, arrowLeading: false, tint: Palette.keep, isLit: drag.width > 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.Copy.Onboarding.page2Try)
        .accessibilityValue("Kept \(keptCount), tossed \(tossedCount)")
        .accessibilityAction(named: Text(Brand.Copy.Review.keep)) { fling(keep: true, predicted: .zero) }
        .accessibilityAction(named: Text(Brand.Copy.Review.toss)) { fling(keep: false, predicted: .zero) }
    }

    // MARK: Card

    @ViewBuilder
    private func cardView(_ entry: Entry) -> some View {
        let group: CategoryGroup = palette[entry.id % palette.count]
        let isTop: Bool = entry.fly == nil && entry.depth == 0
        let offset: CGSize = entry.fly?.offset ?? (isTop ? drag : .zero)
        let rotation: Double = entry.fly?.rotation ?? (isTop ? Double(drag.width / 14) : 0)
        let keepProgress: Double = stampProgress(entry: entry, isTop: isTop, keep: true)
        let tossProgress: Double = stampProgress(entry: entry, isTop: isTop, keep: false)

        MiniScreenshot(gradient: group.gradient, width: cardWidth, content: contents[entry.id % contents.count])
            .overlay(alignment: .topLeading) {
                SwipeStamp(kind: .keep, progress: keepProgress, compact: true)
                    .padding(Space.sm)
            }
            .overlay(alignment: .topTrailing) {
                SwipeStamp(kind: .toss, progress: tossProgress, compact: true)
                    .padding(Space.sm)
            }
            .shadow(color: Color.black.opacity(entry.depth == 0 ? 0.2 : 0.08), radius: 12, x: 0, y: 8)
            .scaleEffect(entry.depth == 0 ? 1 : 0.92)
            .offset(y: entry.depth == 0 ? 0 : 14)
            .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: entry.depth)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .offset(offset)
            .opacity(entry.fly != nil && reduceMotion ? 0 : 1)
            .zIndex(entry.fly != nil ? 10 : Double(2 - entry.depth))
            .transition(AnyTransition.scale(scale: 0.85).combined(with: AnyTransition.opacity))
            .gesture(dragGesture, including: isTop ? .all : .subviews)
    }

    private func stampProgress(entry: Entry, isTop: Bool, keep: Bool) -> Double {
        if let fly = entry.fly {
            return fly.keep == keep ? 1.0 : 0.0
        }
        guard isTop else { return 0 }
        let signed: CGFloat = keep ? drag.width : -drag.width
        return Double(signed / threshold)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if drag == .zero {
                    HapticManager.shared.prepareForSwipe()
                }
                drag = value.translation
                let past: Bool = abs(value.translation.width) > threshold
                if past != isPastThreshold {
                    isPastThreshold = past
                    if past {
                        HapticManager.shared.swipeThresholdReached()
                    }
                }
            }
            .onEnded { value in
                let dx: CGFloat = value.translation.width
                let projected: CGFloat = value.predictedEndTranslation.width
                isPastThreshold = false
                if abs(dx) > threshold || abs(projected) > threshold * 2 {
                    let direction: CGFloat = abs(projected) > abs(dx) ? projected : dx
                    fling(keep: direction > 0, predicted: value.predictedEndTranslation)
                } else {
                    HapticManager.shared.cardReturn()
                    Motion.perform(Motion.bouncy, reduceMotion: reduceMotion) {
                        drag = .zero
                    }
                }
            }
    }

    // MARK: Actions

    private func fling(keep: Bool, predicted: CGSize) {
        let id: Int = topIndex
        let sign: CGFloat = keep ? 1 : -1
        let targetX: CGFloat = reduceMotion ? sign * 60 : sign * 520
        let targetY: CGFloat = reduceMotion ? 0 : drag.height + predicted.height * 0.25
        let fly = FlyAway(
            offset: CGSize(width: targetX, height: targetY),
            rotation: reduceMotion ? 0 : Double(sign * 24),
            keep: keep
        )

        if keep {
            HapticManager.shared.swipeKeep()
        } else {
            HapticManager.shared.swipeDelete()
        }

        Motion.perform(Motion.cardFling, reduceMotion: reduceMotion) {
            flying[id] = fly
            drag = .zero
            topIndex += 1
            if keep {
                keptCount += 1
            } else {
                tossedCount += 1
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                _ = flying.removeValue(forKey: id)
            }
        }
    }

    private func counter(value: Int, label: String, arrowLeading: Bool, tint: Color, isLit: Bool) -> some View {
        HStack(spacing: Space.xs) {
            if arrowLeading {
                Image(systemName: "arrow.left")
            }
            Text(label)
            Text(value, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            if !arrowLeading {
                Image(systemName: "arrow.right")
            }
        }
        .font(.dsCaption.weight(.heavy))
        .foregroundStyle(isLit ? Palette.onBrand : tint)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
        .background {
            Capsule(style: .continuous)
                .fill(isLit ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)))
        }
        .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: isLit)
        .animation(Motion.animation(Motion.bouncy, reduceMotion: reduceMotion), value: value)
    }
}

// MARK: - Demo 3: Privacy + Smart Search

private struct PrivacySearchDemo: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typedCount = 0
    @State private var showResult = false

    private var query: String { Brand.Copy.Onboarding.searchTeaser }

    var body: some View {
        VStack(spacing: Space.md) {
            searchField

            HStack(alignment: .center, spacing: Space.md) {
                resultCard
                VStack(alignment: .leading, spacing: Space.sm) {
                    privacyRow(icon: "iphone", text: Brand.Copy.Onboarding.privacyPoint1)
                    privacyRow(icon: "icloud.slash.fill", text: Brand.Copy.Onboarding.privacyPoint2)
                    privacyRow(icon: "text.magnifyingglass", text: Brand.Copy.Onboarding.privacyPoint3)
                }
            }
            .padding(.horizontal, Space.gutter)
        }
        .task(id: isActive) {
            await runTyping()
        }
    }

    private var searchField: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.brand)
            Text(String(query.prefix(typedCount)))
                .font(.dsCallout)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Capsule()
                .fill(Palette.brand)
                .frame(width: 2, height: 18)
                .opacity(typedCount < query.count ? 1 : 0)
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(Palette.keep)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .dsCard(tint: Palette.brand, radius: Radius.xl)
        .padding(.horizontal, Space.gutter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Search example: \(query)")
    }

    private var resultCard: some View {
        MiniScreenshot(
            style: AnyShapeStyle(Palette.surface),
            ink: CategoryGroup.system.color,
            width: 92,
            content: .list
        )
        .overlay(alignment: .center) {
            // Highlighted "match" inside the screenshot.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Palette.brandSecondary, lineWidth: 2.5)
                .frame(width: 74, height: 22)
                .offset(y: 6)
                .scaleEffect(showResult ? 1 : 1.4)
                .opacity(showResult ? 1 : 0)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 6)
        .rotationEffect(.degrees(showResult ? -4 : 0))
        .scaleEffect(showResult ? 1 : 0.9)
        .opacity(showResult ? 1 : 0.35)
        .animation(Motion.animation(Motion.bouncy, reduceMotion: reduceMotion), value: showResult)
        .accessibilityHidden(true)
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.keep)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.dsCallout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runTyping() async {
        guard isActive else { return }
        let total: Int = query.count
        if reduceMotion {
            typedCount = total
            showResult = true
            return
        }
        while !Task.isCancelled {
            typedCount = 0
            showResult = false
            try? await Task.sleep(for: .milliseconds(500))
            for index in 1...max(total, 1) {
                guard !Task.isCancelled else { return }
                typedCount = index
                try? await Task.sleep(for: .milliseconds(65))
            }
            guard !Task.isCancelled else { return }
            showResult = true
            try? await Task.sleep(for: .seconds(2.4))
        }
    }
}

// MARK: - Onboarding Keys

struct OnboardingKeys {
    static let hasSeenOnboarding = "hasSeenOnboarding"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenOnboarding) }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: hasSeenOnboarding)
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
