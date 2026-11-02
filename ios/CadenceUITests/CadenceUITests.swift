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

    @discardableResult
    private func launch(_ scenario: String, minute: Int = 8 * 60, reset: Bool = true) -> XCUIApplication {
        let a = XCUIApplication()
        a.launchEnvironment = ["CADENCE_UITEST": scenario, "CADENCE_UITEST_MINUTE": String(minute), "CADENCE_UITEST_RESET": reset ? "1" : "0"]
        a.launch()
        XCTAssertTrue(a.tabBars.buttons["Today"].waitForExistence(timeout: 20), "Cadence didn't reach the Today tab")
        app = a
        return a
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
        XCTAssertTrue(sync.label.contains("3 days"), "label was: \(sync.label)")
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
        XCTAssertTrue(el("capture.summary").label.contains("Groceries"))
        shot("capture-spend", app)
        el("capture.confirm").tap()
        XCTAssertTrue(el("capture.done").waitForExistence(timeout: 3))
        el("capture.undo").tap()
        XCTAssertTrue(el("capture.done").label.contains("Undone"))
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
        XCTAssertTrue(el("capture.summary").label.hasPrefix("Log"), "summary was: \(el("capture.summary").label)")
        el("capture.confirm").tap()
        XCTAssertTrue(el("capture.done").waitForExistence(timeout: 3))
        XCTAssertTrue(el("capture.done").label.contains("3 foods"), "two eggs and a banana: \(el("capture.done").label)")
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
        XCTAssertTrue(pairs.label.contains("14 pairs"), "label was: \(pairs.label)")
        shot("calibration", app)
    }

    // MARK: Workout feedback

    func testWorkoutFeedback() {
        launch("normal")
        app.tabBars.buttons["Body"].tap()
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
