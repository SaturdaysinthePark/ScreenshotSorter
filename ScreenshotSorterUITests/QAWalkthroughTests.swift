import XCTest

/// Drives the interactions in docs/qa/animation-review.md so they can be recorded with
/// `xcrun simctl io booted recordVideo` and checked frame by frame. Not an assertion-heavy test:
/// it attaches a screenshot at every checkpoint (export with `xcresulttool export attachments`).
final class QAWalkthroughTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        if env["QA_ONBOARDING"] == "1" {
            app.launchArguments += ["-hasSeenOnboarding", "NO"]
        }
        if let extra = env["QA_ARGS"], !extra.isEmpty {
            app.launchArguments += extra.split(separator: " ").map(String.init)
        }
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow While Using App", "Allow", "OK", "Don’t Allow"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Wall-clock marker so the runner can line interactions up with the screen recording.
    private func mark(_ name: String) {
        print("QA-MARK \(name) \(Date().timeIntervalSince1970)")
    }

    private func waitForHome() {
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 10)
        sleep(2)
    }

    private var galleryCells: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", ", 202"))
    }

    private func dismissSpringboardAlerts(firstWait: TimeInterval = 1) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for attempt in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: attempt == 0 ? firstWait : 1) else { return }
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow While Using App", "Allow", "OK", "Don’t Allow"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); break }
            }
        }
    }

    // Row 1 alone, for frame-timing the splash hand-off.
    @MainActor
    func test00LaunchOnly() throws {
        app.launch()
        sleep(3)
        snap("00-after-launch")
    }

    // Rows 1–4: launch, photo access, onboarding, analysis card.
    @MainActor
    func test01LaunchOnboardingAccess() throws {
        app.launch()
        for i in 0..<6 { snap("01-launch-\(i)"); usleep(150_000) }
        dismissSpringboardAlerts()

        // Onboarding (only when QA_ONBOARDING=1)
        let next = app.buttons["Next"]
        if next.waitForExistence(timeout: 3) {
            snap("03-onboarding-1")
            sleep(3)
            snap("03-onboarding-1-sorted")
            next.tap()
            sleep(1)
            snap("03-onboarding-2")
            // Fling the demo card
            let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
            center.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 0.34)), withVelocity: .fast, thenHoldForDuration: 0)
            usleep(300_000)
            snap("03-onboarding-2-flung")
            sleep(1)
            snap("03-onboarding-2-reset")
            next.tap()
            sleep(2)
            snap("03-onboarding-3")
            app.buttons["Let's go"].tap()
            usleep(500_000)
            snap("03-onboarding-done")
        }

        let allow = app.buttons["Allow Photo Access"]
        if allow.waitForExistence(timeout: 3) {
            snap("02-access")
            allow.tap()
            sleep(1)
            snap("02-access-prompt")
            dismissSpringboardAlerts()
            for i in 0..<4 { snap("02-access-granted-\(i)"); usleep(200_000) }
        }

        // Row 4/5: home with analysis card
        for i in 0..<6 { snap("04-home-\(i)"); sleep(1) }
    }

    // Rows 4–11: home, shelves, category → gallery, gallery → detail, detail gestures, insights.
    @MainActor
    func test02HomeGalleryDetail() throws {
        app.launch()
        waitForHome()
        mark("home")
        snap("04-home")
        print(app.debugDescription.prefix(6000))

        // Row 6: shelf scroll (first horizontal card row below "All Screenshots")
        let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND NOT (label BEGINSWITH %@)", "screenshot", "All Screenshots"))
        if cards.count > 0 {
            let card = cards.element(boundBy: 0)
            mark("shelf-scroll")
            card.swipeLeft(velocity: .slow)
            usleep(400_000)
            snap("06-shelf-scrolled")
            card.swipeRight(velocity: .slow)
            usleep(400_000)

            // Row 7: category card → gallery (zoom), back
            mark("category-open")
            cards.element(boundBy: 0).tap()
            sleep(1)
            snap("07-category-gallery")
            mark("category-back")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
            snap("07-category-back")
        }

        // Row 7/9 on All Screenshots
        mark("all-open")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All Screenshots")).firstMatch.tap()
        sleep(1)
        snap("07-all-gallery")

        let cells = galleryCells
        guard cells.count > 2 else { snap("09-no-cells"); return }
        mark("detail-open")
        cells.element(boundBy: 1).tap()
        usleep(150_000)
        snap("09-detail-opening")
        sleep(1)
        snap("09-detail")

        // Row 9: page twice, then drag-dismiss → should land on the new thumbnail
        mark("page")
        app.swipeLeft()
        usleep(700_000)
        app.swipeLeft()
        usleep(700_000)
        snap("09-paged")
        mark("drag-dismiss")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.62)), withVelocity: .slow, thenHoldForDuration: 0.3)
        usleep(150_000)
        snap("10-drag-dismissing")
        sleep(1)
        snap("09-dismissed-back-to-grid")

        // Row 10: double-tap zoom and pinch on the photo itself
        mark("reopen")
        galleryCells.element(boundBy: 3).tap()
        sleep(1)
        // Hide chrome so a window-wide pinch can't land on the drawer.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        sleep(1)
        let photo = app.windows.firstMatch
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        mark("double-tap-in")
        center.doubleTap()
        usleep(600_000)
        snap("10-double-tap-zoomed")
        mark("double-tap-out")
        center.doubleTap()
        usleep(600_000)
        snap("10-double-tap-out")
        mark("pinch-out")
        photo.pinch(withScale: 2.0, velocity: 2)
        usleep(500_000)
        snap("10-pinched")
        mark("pinch-in")
        photo.pinch(withScale: 0.5, velocity: -2)
        usleep(800_000)
        snap("10-pinched-back")
        mark("pinch-close")
        photo.pinch(withScale: 0.5, velocity: -2)
        sleep(1)
        snap("10-pinch-closed")
        // Bring the chrome back and close the viewer.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        sleep(1)
        if app.buttons["Close"].firstMatch.isHittable {
            app.buttons["Close"].firstMatch.tap()
            sleep(1)
        }

        // Row 11: insight drawer
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        sleep(1)
        mark("insights")
        let expand = app.buttons["Show details"].firstMatch
        if expand.waitForExistence(timeout: 2) {
            expand.tap()
            usleep(200_000)
            snap("11-insights-opening")
            sleep(1)
            snap("11-insights")
            mark("insights-close")
            app.buttons["Hide details"].firstMatch.tap()
            sleep(1)
            snap("11-insights-closed")
        }
        mark("end")
    }

    // Row 9 focused: does horizontal paging work in the detail viewer?
    @MainActor
    func test03Paging() throws {
        app.launch()
        waitForHome()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All Screenshots")).firstMatch.tap()
        sleep(1)
        galleryCells.element(boundBy: 1).tap()
        sleep(1)
        func counter() -> String {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " of ")).firstMatch.label
        }
        print("QA-PAGE start \(counter())")
        mark("flick")
        app.swipeLeft()
        sleep(1)
        print("QA-PAGE after-flick \(counter())")
        snap("p-after-flick")
        mark("slow-drag")
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.4))
        a.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.4)), withVelocity: .slow, thenHoldForDuration: 0)
        sleep(1)
        print("QA-PAGE after-slow-drag \(counter())")
        snap("p-after-slow")
        mark("fast-drag")
        a.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.42)), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        print("QA-PAGE after-fast-drag \(counter())")
        snap("p-after-fast")
        mark("dismiss")
        app.buttons["Close"].firstMatch.tap()
        sleep(1)
        snap("p-back-in-grid")
    }

    // Rows 4, 5, 8: home while a fresh library is analyzing, then the gallery as items arrive.
    @MainActor
    func test04Analyzing() throws {
        app.launch()
        dismissSpringboardAlerts()
        let allow = app.buttons["Allow Photo Access"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
            sleep(1)
            dismissSpringboardAlerts()
        }
        mark("home-analyzing")
        for i in 0..<8 { snap("04-analyzing-\(i)"); usleep(700_000) }
        mark("gallery-analyzing")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All Screenshots")).firstMatch.tap()
        for i in 0..<6 { snap("08-gallery-\(i)"); sleep(1) }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        mark("home-later")
        for i in 0..<6 { snap("04-home-later-\(i)"); sleep(2) }
        mark("end")
    }

    // Rows 6, 7, 12, 14, 15, 16, 17, 19 on an analyzed library.
    @MainActor
    func test05SortedLibrary() throws {
        app.launch()
        waitForHome()
        snap("05-home")

        // Row 6: shelf scroll; Row 7: category card → gallery and back
        let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND NOT (label BEGINSWITH %@)", "screenshot", "All Screenshots"))
        if cards.count > 0 {
            app.swipeUp(velocity: .slow)
            sleep(1)
            let card = cards.element(boundBy: 0)
            mark("shelf-scroll")
            card.swipeLeft(velocity: .slow)
            usleep(300_000)
            snap("06-shelf-mid")
            sleep(1)
            snap("06-shelf-settled")
            card.swipeRight(velocity: .slow)
            sleep(1)
            mark("category-open")
            cards.allElementsBoundByIndex.first { $0.isHittable }?.tap()
            usleep(200_000)
            snap("07-zooming")
            sleep(1)
            snap("07-category")

            // Row 12: move one screenshot out of this stack (Select → Move)
            mark("move")
            app.buttons["Select"].firstMatch.tap()
            sleep(1)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.42)).tap()
            sleep(1)
            snap("12-selected")
            let move = app.buttons["Move"].firstMatch
            if move.waitForExistence(timeout: 2) {
                move.tap()
                sleep(1)
                snap("12-move-sheet")
                mark("move-pick")
                app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Instagram")).firstMatch.tap()
                usleep(250_000)
                snap("12-moved")
                sleep(1)
                snap("12-toast")
                let undo = app.buttons["Undo"].firstMatch
                if undo.exists {
                    mark("undo")
                    undo.tap()
                    sleep(1)
                    snap("12-undone")
                }
            }
            if app.buttons["Done"].exists { app.buttons["Done"].firstMatch.tap(); sleep(1) }
            mark("category-back")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
            snap("07-back-home")
            app.swipeDown(velocity: .slow)
            sleep(1)
        }

        // Row 19: pause / resume
        mark("pause")
        app.buttons["More"].firstMatch.tap()
        sleep(1)
        snap("19-menu")
        let pause = app.buttons["Pause sorting"]
        if pause.exists {
            pause.tap()
            sleep(1)
            snap("19-paused")
            app.buttons["More"].firstMatch.tap()
            sleep(1)
            app.buttons["Resume sorting"].tap()
            sleep(1)
            snap("19-resumed")
        } else {
            app.tap()
        }

        // Row 14/15: search typing and result → detail
        mark("search")
        let field = app.searchFields.firstMatch
        field.tap()
        for ch in "weather" {
            field.typeText(String(ch))
            usleep(120_000)
        }
        sleep(1)
        snap("14-search")
        mark("search-open")
        do {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34)).tap()
            usleep(200_000)
            snap("15-opening")
            sleep(1)
            snap("15-detail")
            app.buttons["Close"].firstMatch.tap()
            sleep(1)
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.075)).tap()
        sleep(1)
        snap("14-search-closed")

        // Row 16/17: review deck
        mark("review")
        let review = app.buttons["Start swiping"].firstMatch
        if review.waitForExistence(timeout: 2) {
            review.tap()
            sleep(2)
            snap("16-deck")
            let resume = app.buttons["Start over"]
            if resume.exists { resume.tap(); sleep(1) }
            let deckCenter = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
            mark("fling-right")
            deckCenter.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 1.2, dy: 0.45)), withVelocity: .fast, thenHoldForDuration: 0)
            usleep(150_000)
            snap("16-flung-right")
            sleep(1)
            mark("fling-left")
            deckCenter.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: -0.2, dy: 0.45)), withVelocity: .fast, thenHoldForDuration: 0)
            sleep(1)
            snap("16-flung-left")
            mark("undo-card")
            app.buttons["Undo"].firstMatch.tap()
            sleep(1)
            snap("16-undone")
            mark("drag-threshold")
            deckCenter.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42)), withVelocity: .slow, thenHoldForDuration: 0.5)
            sleep(1)
            snap("16-released-short")
            mark("sort-up")
            deckCenter.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.1)), withVelocity: .fast, thenHoldForDuration: 0)
            sleep(1)
            snap("16-sort-sheet")
            if app.buttons["Close"].exists && !app.buttons["Keep"].isHittable { app.buttons["Close"].firstMatch.tap(); sleep(1) }

            // Row 17: clear the deck
            mark("clear-deck")
            for _ in 0..<70 {
                if app.staticTexts["Deck cleared!"].exists { break }
                let keep = app.buttons["Keep"].firstMatch
                guard keep.exists && keep.isHittable else { break }
                keep.tap()
                usleep(250_000)
            }
            mark("completion")
            usleep(300_000)
            snap("17-completion")
            sleep(2)
            snap("17-completion-settled")
            if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            sleep(1)
        }
        mark("end")
    }

    /// Clears system alerts left on screen (e.g. before corpus capture).
    @MainActor
    func test99DismissSystemAlerts() throws {
        dismissSpringboardAlerts()
    }

    /// Large-library run: first sort of the whole library while the user scrolls the grid.
    /// Pair with `ps`/`log stream` on the host (see docs/qa/animation-review.md).
    @MainActor
    func test06LargeLibraryFirstSort() throws {
        app.launch()
        mark("launch")
        let allow = app.buttons["Allow Photo Access"]
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
            dismissSpringboardAlerts(firstWait: 10)
        }
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All Screenshots")).firstMatch
        _ = all.waitForExistence(timeout: 30)
        mark("home")
        snap("06-home-start")
        all.tap()
        sleep(1)
        mark("scroll")
        for round in 0..<12 {
            app.swipeUp(velocity: .fast)
            usleep(300_000)
            app.swipeUp(velocity: .fast)
            usleep(300_000)
            app.swipeDown(velocity: .fast)
            usleep(300_000)
            if round % 4 == 0 { snap("06-grid-\(round)") }
        }
        mark("scroll-end")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for i in 0..<12 { sleep(5); snap("06-home-\(i)") }
        mark("end")
    }

    /// A/B for scroll smoothness on a large library: grid scrolling with sorting paused, then running.
    @MainActor
    func test07GridScrollPausedVsSorting() throws {
        app.launch()
        waitForHome()
        func setSorting(paused: Bool) {
            app.buttons["More"].firstMatch.tap()
            let item = app.buttons[paused ? "Pause sorting" : "Resume sorting"]
            if item.waitForExistence(timeout: 2) { item.tap() } else { app.tap() }
            sleep(1)
        }
        func scroll(_ label: String) {
            mark(label)
            for _ in 0..<6 {
                app.swipeUp(velocity: .fast); usleep(250_000)
                app.swipeUp(velocity: .fast); usleep(250_000)
                app.swipeDown(velocity: .fast); usleep(250_000)
            }
            mark(label + "-end")
        }
        setSorting(paused: true)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All Screenshots")).firstMatch.tap()
        sleep(2)
        scroll("paused")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
        setSorting(paused: false)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All Screenshots")).firstMatch.tap()
        sleep(2)
        scroll("sorting")
    }

    /// Scrolls the All Screenshots grid for ~40 s (for profiling with `sample` / Instruments).
    @MainActor
    func test08GridScrollOnly() throws {
        app.launch()
        waitForHome()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All Screenshots")).firstMatch.tap()
        sleep(2)
        mark("scroll")
        for _ in 0..<10 {
            app.swipeUp(velocity: .fast); usleep(250_000)
            app.swipeUp(velocity: .fast); usleep(250_000)
            app.swipeDown(velocity: .fast); usleep(250_000)
        }
        mark("scroll-end")
    }
}
