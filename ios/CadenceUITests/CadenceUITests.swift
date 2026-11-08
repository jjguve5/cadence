// Drives the real app on a simulator. Every launch sets CADENCE_UITEST, so the app runs in its test mode: its own
// data file in a temporary folder, no network, no permission prompts, and a fixed scenario (see TestMode.swift).
// No sleeps: every wait is for an element to appear or disappear.
import XCTest

final class CadenceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let app { shot("end-\(name)", app) }
        app?.terminate()
    }

    // MARK: Helpers

    /// `areasOff` starts the scenario with those areas switched off (as in You); `portuguese` runs the app with the
    /// system language and region set to Portugal
    @discardableResult
    private func launch(_ scenario: String, minute: Int = 8 * 60, reset: Bool = true, areasOff: [String] = [], portuguese: Bool = false) -> XCUIApplication {
        let a = XCUIApplication()
        a.launchEnvironment = ["CADENCE_UITEST": scenario, "CADENCE_UITEST_MINUTE": String(minute), "CADENCE_UITEST_RESET": reset ? "1" : "0"]
        if !areasOff.isEmpty { a.launchEnvironment["CADENCE_UITEST_AREAS_OFF"] = areasOff.joined(separator: ",") }
        if portuguese { a.launchArguments += ["-AppleLanguages", "(pt-PT)", "-AppleLocale", "pt_PT"] }
        a.launch()
        // Today is recognised by the identifier on its title, not by the tab's name, so translating it can't break this
        XCTAssertTrue(a.descendants(matching: .any)[Tab.today.screen].firstMatch.waitForExistence(timeout: 20), "Cadence didn't reach the Today tab")
        app = a
        return a
    }

    /// The five tabs, known by the identifier on the title of each tab's screen (<name>.screen), internal and never
    /// translated. The tab buttons themselves have no identifier: one set inside .tabItem reaches the button in some
    /// launches and not in others (CI run 42470880896, attempt 3: the buttons came up with their labels only), so no
    /// test may rely on it. A tab is found by trying the buttons until its screen shows: neither its name nor its place
    /// in the bar matters (Hygiene can be switched off, which moves Life).
    private enum Tab: String, CaseIterable {
        case today, plan, body, hygiene, life
        var screen: String { "\(rawValue).screen" }
    }

    /// The tab screens showing right now (exactly one when a tab's root is on screen)
    private func screensShowing() -> [Tab] { Tab.allCases.filter { el($0.screen).exists } }

    private func open(_ tab: Tab, file: StaticString = #filePath, line: UInt = #line) {
        if el(tab.screen).exists { return }
        let buttons = app.tabBars.buttons
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 5), "no tab bar", file: file, line: line)
        for i in 0..<buttons.count {
            buttons.element(boundBy: i).tap()
            if el(tab.screen).waitForExistence(timeout: 3) { return }
        }
        XCTFail("no tab in the bar opens \(tab.screen)", file: file, line: line)
    }

    /// Taps every button in the bar, in order: each opens exactly one tab screen, every tab in `tabs` is reached once
    /// and no other, and each button has a name for VoiceOver. Returns the tab reached at each place; ends on Today.
    @discardableResult
    private func checkEveryTab(_ tabs: [Tab], file: StaticString = #filePath, line: UInt = #line) -> [Tab] {
        let buttons = app.tabBars.buttons
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 5), "no tab bar", file: file, line: line)
        XCTAssertEqual(buttons.count, tabs.count, "tabs in the bar", file: file, line: line)
        var reached: [Tab] = []
        var labels: [String] = []
        for i in 0..<buttons.count {
            let button = buttons.element(boundBy: i)
            button.tap()
            let any = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", Tab.allCases.map(\.screen))).firstMatch
            XCTAssertTrue(any.waitForExistence(timeout: 5), "place \(i) opened no tab screen", file: file, line: line)
            let showing = screensShowing()
            XCTAssertEqual(showing.count, 1, "place \(i) shows \(showing.map(\.screen))", file: file, line: line)
            if let tab = showing.first { reached.append(tab) }
            XCTAssertFalse(button.label.isEmpty, "place \(i) has no name for VoiceOver", file: file, line: line)
            labels.append(button.label)
        }
        XCTAssertEqual(Set(reached), Set(tabs), "tabs reached", file: file, line: line)
        XCTAssertEqual(reached.count, Set(reached).count, "two places open the same tab: \(reached)", file: file, line: line)
        XCTAssertEqual(labels.count, Set(labels).count, "two tabs share a name: \(labels)", file: file, line: line)
        open(.today, file: file, line: line)
        return reached
    }

    /// Text the tests read back from the screen. It is English today and changes on purpose with the app's strings in
    /// phase 2.3 (European Portuguese): these are the only lines to update then. Amounts, counts and times are checked
    /// separately in the tests and stay the same in both languages.
    private enum UIText {
        static let staleSync = "3 days"       // stale data: days since the band last synced
        static let groceries = "Groceries"    // the spending category quick capture picks for "groceries"
        static let undone = "Undone"          // quick capture after Undo
        static let logPrefix = "Log"          // quick capture summary for food
        static let threeFoods = "3 foods"     // "2 eggs and a banana" saved
        static let fourteenPairs = "14 pairs" // calibration sample size
    }

    private func shot(_ name: String, _ a: XCUIApplication) {
        let s = XCTAttachment(screenshot: a.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func waitGone(_ e: XCUIElement, timeout: TimeInterval = 5) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: e)
        wait(for: [gone], timeout: timeout)
    }

    /// Scrolls until the element can be tapped
    @discardableResult
    private func reveal(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = el(id)
        _ = e.waitForExistence(timeout: 3)
        var tries = 0
        while !(e.exists && e.isHittable) && tries < 10 { app.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(e.exists && e.isHittable, "\(id) never became tappable", file: file, line: line)
        return e
    }

    // MARK: Launch and Today

    func testLaunchShowsToday() {
        launch("normal")
        XCTAssertTrue(el("capture.open").exists)
        for r in ["sleep", "recovery", "strain", "calories", "protein", "water", "move", "promises"] { XCTAssertTrue(el("ring.\(r)").exists, "ring \(r) missing") }
        shot("today-normal", app)
    }

    func testAllRingsAlwaysShow() {
        launch("normal")
        XCTAssertFalse(el("rings.toggle").exists, "nothing to expand: all the rings are always there")
        XCTAssertTrue(el("ring.water").exists)
        shot("rings", app)
    }

    // MARK: Navigation

    /// Every tab opens its own screen, and the bar keeps the design's order
    func testEveryTabOpensItsOwnScreen() {
        launch("normal")
        XCTAssertEqual(checkEveryTab(Tab.allCases), [.today, .plan, .body, .hygiene, .life], "the tab bar's order")
        shot("tabs", app)
    }

    /// With Hygiene switched off there are four tabs and Life moves to the fourth place: found through its screen, it
    /// still opens (the 2.0 tests looked for Life at the fifth place, which no longer exists)
    func testLifeOpensWithHygieneOff() {
        launch("normal", areasOff: ["care"])
        let reached = checkEveryTab([.today, .plan, .body, .life])
        XCTAssertEqual(reached.last, .life, "Life is now in the fourth place")
        open(.life)
        XCTAssertTrue(el(Tab.life.screen).exists)
        shot("tabs-hygiene-off", app)
    }

    /// Navigation doesn't depend on the language: the same check with the system in European Portuguese. Until phase
    /// 2.3 translates the app this proves the system language and region don't matter; after it, that the tabs don't.
    func testNavigationInEuropeanPortuguese() {
        launch("normal", portuguese: true)
        checkEveryTab(Tab.allCases)
        shot("tabs-pt-PT", app)
    }

    /// The Sleep and Recovery rings open their screens and Strain doesn't open anything, now that the rings are told
    /// apart by key instead of by name. A fresh launch for each (launching ends the previous run), so nothing depends
    /// on the system's Back button.
    func testRingsKeepTheirDestinations() {
        for (ring, opens) in [("sleep", true), ("recovery", true), ("strain", false)] {
            launch("normal")
            reveal("ring.\(ring)").tap()
            let today = el(Tab.today.screen)
            if opens {
                waitGone(today)
            } else {
                let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: today)
                XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 3), .timedOut, "ring.\(ring) isn't meant to open a screen")
            }
            shot("ring-\(ring)", app)
        }
    }

    // MARK: Recommendations and the minimum viable day

    func testPoorSleepOffersMinimumDayAndActionTurnsItOn() {
        launch("poorSleep")
        XCTAssertTrue(el("focus.card").waitForExistence(timeout: 5))
        XCTAssertTrue(el("rec.minimumday").exists, "5 h of sleep should offer a minimum viable day")
        shot("recs-poor-sleep", app)
        reveal("rec.minimumday.action").tap()
        XCTAssertTrue(el("mvd.banner").waitForExistence(timeout: 5))
        waitGone(el("rec.minimumday"), timeout: 15)
        XCTAssertFalse(el("rec.focus").exists, "push-harder advice goes on a minimum viable day")
        shot("mvd-on", app)
        var tries = 0
        while !el("mvd.off").isHittable && tries < 6 { app.swipeDown(velocity: .fast); tries += 1 } // on a small phone the action was further down
        el("mvd.off").tap()
        waitGone(el("mvd.banner"))
        XCTAssertFalse(el("rec.minimumday").exists, "an answered recommendation stays away for today")
    }

    func testMinimumDayScenarioShowsBanner() {
        launch("minimumDay")
        XCTAssertTrue(el("mvd.banner").waitForExistence(timeout: 5))
        shot("mvd-scenario", app)
    }

    func testDismissHidesRecommendation() {
        launch("lowReadiness")
        let dismiss = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rec.' AND identifier ENDSWITH '.dismiss'")).firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "low readiness should produce at least one recommendation")
        let kind = dismiss.identifier.dropFirst(4).dropLast(8)
        XCTAssertNotEqual(kind, "mustdo")
        shot("recs-low-readiness", app)
        dismiss.tap()
        waitGone(el("rec.\(kind)"))
    }

    func testStaleDataAsksToSync() {
        launch("stale")
        let sync = el("rec.sync")
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        XCTAssertTrue(sync.label.contains(UIText.staleSync), "label was: \(sync.label)")
        shot("stale", app)
    }

    func testMissingTodayStillWorks() {
        launch("missingToday")
        XCTAssertTrue(el("rec.sync").waitForExistence(timeout: 5), "no sleep yet and a 10 h old sync should ask to sync")
        XCTAssertTrue(el("ring.calories").exists)
        shot("missing-today", app)
    }

    func testHighWorkloadLaunches() {
        launch("workload")
        XCTAssertTrue(el("ring.calories").exists)
        shot("workload", app)
    }

    func testEmptyHistoryLaunches() {
        launch("empty")
        XCTAssertTrue(el("capture.open").exists)
        shot("empty-history", app)
    }

    // MARK: Quick capture

    func testQuickCaptureEnglishConfirmAndUndo() {
        launch("normal")
        el("capture.open").tap()
        let field = el("capture.field")
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Spent 12,50 € on groceries")
        XCTAssertTrue(el("capture.summary").waitForExistence(timeout: 3))
        XCTAssertTrue(el("capture.summary").label.contains("12,50"), "summary was: \(el("capture.summary").label)")
        XCTAssertTrue(el("capture.summary").label.contains(UIText.groceries))
        shot("capture-spend", app)
        el("capture.confirm").tap()
        XCTAssertTrue(el("capture.done").waitForExistence(timeout: 3))
        el("capture.undo").tap()
        XCTAssertTrue(el("capture.done").label.contains(UIText.undone))
    }

    func testQuickCaptureFoodAndUnknownFood() {
        launch("normal")
        el("capture.open").tap()
        let field = el("capture.field")
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Ate xyzzyfood")
        XCTAssertTrue(el("capture.summary").waitForExistence(timeout: 3))
        XCTAssertFalse(el("capture.confirm").isEnabled, "nothing matched, so Confirm can't save")
        field.clearAndType("Ate 2 eggs and a banana")
        XCTAssertTrue(el("capture.summary").label.hasPrefix(UIText.logPrefix), "summary was: \(el("capture.summary").label)")
        el("capture.confirm").tap()
        XCTAssertTrue(el("capture.done").waitForExistence(timeout: 3))
        XCTAssertTrue(el("capture.done").label.contains(UIText.threeFoods), "two eggs and a banana: \(el("capture.done").label)")
    }

    func testQuickCapturePortugueseAndCancel() {
        launch("normal")
        el("capture.open").tap()
        let field = el("capture.field")
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Lembra-me de ligar à mãe amanhã às 18h")
        let summary = el("capture.summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("Ligar à mãe"), "summary was: \(summary.label)")
        XCTAssertTrue(summary.label.contains("18:00"), "summary was: \(summary.label)")
        XCTAssertFalse(summary.label.contains("amanhã"), "the day word belongs in the date, not the title")
        shot("capture-pt", app)
        // Cancel: closes without saving, and the next open starts empty
        el("capture.close").tap()
        waitGone(field)
        XCTAssertFalse(el("capture.done").exists)
        el("capture.open").tap()
        XCTAssertTrue(el("capture.field").waitForExistence(timeout: 3))
        XCTAssertFalse(el("capture.summary").exists, "a cancelled capture leaves nothing behind")
    }

    // MARK: Calibration

    func testCalibrationPage() {
        launch("calibration")
        el("you.open").tap()
        reveal("you.growth").tap()
        reveal("growth.learned").tap()
        XCTAssertTrue(el("learned.screen").waitForExistence(timeout: 5))
        let pairs = el("calibration.pairs")
        XCTAssertTrue(pairs.waitForExistence(timeout: 3))
        XCTAssertTrue(pairs.label.contains(UIText.fourteenPairs), "label was: \(pairs.label)")
        shot("calibration", app)
    }

    // MARK: Workout feedback

    func testWorkoutFeedback() {
        launch("normal")
        open(.body)
        reveal("body.training").tap()
        reveal("training.start.Test session").tap()
        let feel = reveal("workout.feel.4")
        feel.tap()
        XCTAssertTrue(feel.isSelected)
        shot("workout-feel", app)
        reveal("workout.finish").tap()
        XCTAssertTrue(el("training.start.Test session").waitForExistence(timeout: 5), "finishing returns to Training")
    }

    // MARK: Daily energy and persistence

    func testDailyEnergyPersistsAfterRelaunch() {
        launch("normal", minute: 20 * 60)
        reveal("closeday.open").tap()
        reveal("energy.4").tap()
        XCTAssertTrue(el("energy.4").isSelected)
        reveal("closeday.save").tap() // closes the day
        reveal("closeday.save").tap() // "Good night"
        XCTAssertTrue(el("closeday.closed").waitForExistence(timeout: 5))
        shot("day-closed", app)
        app.terminate()
        launch("normal", minute: 20 * 60, reset: false)
        XCTAssertTrue(reveal("closeday.closed").exists, "the closed day survives a relaunch")
    }

    func testMinimumDaySurvivesRelaunch() {
        launch("poorSleep")
        el("rec.minimumday.action").tap()
        XCTAssertTrue(el("mvd.banner").waitForExistence(timeout: 3))
        app.terminate()
        // Same data file, no reset: nothing is re-seeded and the store loads what was saved
        launch("poorSleep", reset: false)
        XCTAssertTrue(el("mvd.banner").waitForExistence(timeout: 5), "the minimum viable day survives a relaunch")
        XCTAssertFalse(el("rec.minimumday").exists, "and today's answer to the recommendation too")
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
