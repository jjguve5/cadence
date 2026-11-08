// Treino (phase 2.6) on a simulator, in test mode with the scenarios in TestSeeds/TrainingSeeds.swift. No sleeps: every
// wait is for an element. In test mode the exercise catalogue isn't downloaded, so every exercise gets its light warm-up
// and keeps its template's rest.
import XCTest

final class TrainingUITests: CadenceUITestCase {
    private let template = "Pernas teste" // TrainingSeeds.templateName

    private func openTraining(_ scenario: String) {
        launch(scenario)
        open(.body)
        reveal("body.training").tap()
        XCTAssertTrue(el("training.start.\(template)").waitForExistence(timeout: 5), "Treino shows the scenario's template")
    }

    /// Scrolls until an element found inside another one can be tapped
    private func revealInside(_ e: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = e.waitForExistence(timeout: 3)
        var tries = 0
        while !(e.exists && e.isHittable) && tries < 10 { app.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(e.exists && e.isHittable, "\(e) never became tappable", file: file, line: line)
    }

    /// Before starting: with no history the weights are yours («escolhes tu»), and «Começar treino» opens the exercise
    func testBeforeStartingWithoutHistory() {
        openTraining("training.nohistory")
        reveal("training.template.\(template)").tap()
        XCTAssertTrue(el("training.preview.nohistory").waitForExistence(timeout: 5), "no history: the weights are yours")
        XCTAssertTrue(el("training.preview.exercise.0").exists)
        shot("training-preview")
        reveal("training.preview.start").tap()
        XCTAssertTrue(el("workout.log").waitForExistence(timeout: 5), "starting opens the exercise in progress")
    }

    /// A working set starts the rest; the summary proposes the next target, which applies only once accepted, with
    /// Desfazer; «Concluído» closes the training
    func testRegisterRestSummaryAndAccept() {
        openTraining("training.history")
        reveal("training.start.\(template)").tap()
        XCTAssertTrue(el("workout.current").waitForExistence(timeout: 5))
        reveal("workout.log").tap() // the light warm-up: no rest after it
        reveal("workout.log").tap() // set 1 of 2
        XCTAssertTrue(el("workout.rest").waitForExistence(timeout: 5), "a working set starts the rest")
        shot("training-rest")
        reveal("workout.rest.skip").tap()
        reveal("workout.rir.2").tap() // the last working set asks what was left in reserve (optional)
        XCTAssertTrue(el("workout.rir.2").isSelected)
        reveal("workout.log").tap() // set 2 of 2
        reveal("workout.rest.skip").tap()
        reveal("workout.finish").tap()
        XCTAssertTrue(el("workout.summary").waitForExistence(timeout: 5), "with sets registered, Terminar shows the summary")
        let proposal = el("workout.next.leg-extension")
        XCTAssertTrue(proposal.waitForExistence(timeout: 5), "both sets at the top: a proposal for next time")
        let accept = proposal.buttons["Aceitar"]
        revealInside(accept)
        accept.tap()
        XCTAssertTrue(el("undo.bar").waitForExistence(timeout: 3), "Aceitar shows Desfazer")
        shot("training-summary")
        waitGone(el("undo.bar"), timeout: 8) // the bar sits over the bottom of the screen for its 5 s
        reveal("workout.done").tap()
        XCTAssertTrue(el("training.start.\(template)").waitForExistence(timeout: 5), "Concluído goes back to Treino")
        XCTAssertFalse(el("training.active").exists, "nothing in progress any more")
    }

    /// Pausing keeps what was done; «Terminar aqui» ends it as a partial training, and «Concluído» closes it
    func testPauseAndEndHere() {
        openTraining("training.history")
        reveal("training.start.\(template)").tap()
        reveal("workout.log").tap() // the warm-up
        reveal("workout.log").tap() // set 1 of 2
        reveal("workout.pause").tap()
        XCTAssertTrue(el("workout.resume").waitForExistence(timeout: 5), "paused: Retomar")
        XCTAssertTrue(el("workout.paused").exists)
        shot("training-paused")
        reveal("workout.endhere").tap()
        let summary = el("workout.summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("parcial"), "ended before the plan was done: \(summary.label)")
        reveal("workout.done").tap()
        XCTAssertTrue(el("training.start.\(template)").waitForExistence(timeout: 5))
        XCTAssertFalse(el("training.active").exists, "nothing in progress any more")
    }

    /// A session left open yesterday passed to partial at 23:59: it isn't shown as in progress
    func testASessionLeftOpenYesterdayIsNotInProgress() {
        openTraining("training.leftopen")
        XCTAssertFalse(el("training.active").exists, "left open past 23:59: partial, not in progress")
    }
}
