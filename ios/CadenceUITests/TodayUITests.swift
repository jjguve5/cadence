// Phase 2.4 (Hoje): «Agora» one step at a time, an urgent departure and its answers, the rings with no data, and the
// quick logs ordered by use. Scenarios in Cadence/TestSeeds/TodaySeeds.swift; no sleeps, every wait is on an element.
import XCTest

final class TodayUITests: CadenceUITestCase {
    /// 14:20, an event with a place at 15:00: the urgent step takes the place of «Agora» at the top and the rings shrink
    /// to a line. «Adiar 10 min» hides it at once and Desfazer brings it back.
    func testAnUrgentDepartureTakesTheTopAndCanBePutOff() {
        launch("today.urgent", minute: 14 * 60 + 20)
        XCTAssertTrue(el("now.leave").waitForExistence(timeout: 5), "an event to leave for in 10 min is urgent")
        XCTAssertTrue(el("today.rings.line").exists, "the rings shrink to a line")
        XCTAssertFalse(el("ring.calories").exists)
        shot("today-urgent")
        el("now.snooze").tap()
        XCTAssertTrue(el("undo.action").waitForExistence(timeout: 3), "putting it off offers Desfazer")
        XCTAssertFalse(el("now.leave").exists, "put off for 10 min")
        el("undo.action").tap()
        XCTAssertTrue(el("now.leave").waitForExistence(timeout: 5), "Desfazer brings the warning back")
    }

    /// «Já não vou» hides the warning, and with nothing urgent the rings are back in full
    func testNotGoingHidesTheWarning() {
        launch("today.urgent", minute: 14 * 60 + 20)
        reveal("now.gone").tap()
        waitGone(el("now.leave"))
        XCTAssertTrue(el("ring.calories").waitForExistence(timeout: 5), "with nothing urgent, the rings are back")
        XCTAssertFalse(el("today.rings.line").exists)
    }

    /// The band hasn't synced since last night: sleep and strain say «sem dados» instead of a zero, and food with
    /// nothing logged keeps its number with «sem registos»
    func testRingsWithoutDataSayNoData() {
        launch("today.nodata")
        let sleep = el("ring.sleep")
        XCTAssertTrue(sleep.waitForExistence(timeout: 5))
        XCTAssertTrue(sleep.label.contains("sem dados"), "label was: \(sleep.label)")
        XCTAssertTrue(el("ring.strain").label.contains("sem dados"), "label was: \(el("ring.strain").label)")
        XCTAssertTrue(el("ring.calories").label.contains("sem registos"), "label was: \(el("ring.calories").label)")
        shot("today-nodata")
    }

    /// A workout in progress is the step, and «Continuar» opens it
    func testAWorkoutInProgressIsTheStep() {
        launch("today.workout")
        let go = reveal("next.action")
        XCTAssertTrue(el("now.workout").exists, "the workout comes before the next habit")
        go.tap()
        XCTAssertTrue(el("workout.finish").waitForExistence(timeout: 5), "Continuar opens the workout")
    }

    /// Water used more than food in the last days comes first; 250 ml logs at once, with Desfazer
    func testQuickLogsFollowWhatYouUseMost() {
        launch("today.waterfirst")
        let water = reveal("today.quick.water")
        let food = el("today.quick.food")
        XCTAssertTrue(food.exists)
        XCTAssertLessThan(water.frame.minX, food.frame.minX, "water first")
        shot("today-quicklogs")
        water.tap()
        XCTAssertTrue(el("undo.action").waitForExistence(timeout: 3), "250 ml logs at once and offers Desfazer")
    }
}
