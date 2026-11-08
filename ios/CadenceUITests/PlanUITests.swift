// Phase 2.8 (Plano): Dia, Semana and Mês with the choice kept, a conflict with the training («Aplicar» with Desfazer,
// «Manter assim» keeps it in sight), a new event that isn't saved before Guardar, and the end-of-day review.
// Scenarios in Cadence/TestSeeds/PlanSeeds.swift; no sleeps, every wait is on an element.
import XCTest

final class PlanUITests: CadenceUITestCase {
    /// Dia, Semana or Mês, back at the top of the screen first if the choice is scrolled away
    private func choose(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = el("plan.views").buttons[name]
        _ = button.waitForExistence(timeout: 5)
        var tries = 0
        while !(button.exists && button.isHittable) && tries < 6 { app.swipeDown(velocity: .slow); tries += 1 }
        XCTAssertTrue(button.exists && button.isHittable, "\(name) never became tappable", file: file, line: line)
        button.tap()
    }

    /// Opens in Dia; Mês shows the grid, › moves to the next month and «Hoje» comes back. The choice survives a
    /// relaunch, and «Abrir o dia» opens the chosen day in Dia.
    func testTheViewYouChooseStaysAndTheMonthNavigates() {
        launch("plan.month")
        open(.plan)
        XCTAssertTrue(el("plan.day").waitForExistence(timeout: 5), "the Plano opens in Dia")
        choose("Mês")
        XCTAssertTrue(el("plan.month.grid").waitForExistence(timeout: 5))
        XCTAssertFalse(el("plan.today").exists, "«Hoje» only when you're away from this month")
        el("plan.next").tap()
        XCTAssertTrue(el("plan.today").waitForExistence(timeout: 3))
        el("plan.today").tap()
        waitGone(el("plan.today"))
        shot("plan-month")
        app.terminate()
        launch("plan.month", reset: false)
        open(.plan)
        XCTAssertTrue(el("plan.month.grid").waitForExistence(timeout: 5), "the view you chose stays")
        reveal("plan.month.open").tap()
        XCTAssertTrue(el("plan.day").waitForExistence(timeout: 5), "«Abrir o dia» opens it in Dia")
        XCTAssertFalse(el("plan.month.grid").exists)
    }

    /// A training at 18:30 and a Google dinner at 19:00: «Aplicar» moves only the training and offers Desfazer, which
    /// brings the conflict back; «Manter assim» keeps the conflict in sight in the day, the week and the month
    func testATrainingConflictIsAppliedUndoneOrKept() {
        launch("plan.conflict", minute: 12 * 60)
        open(.plan)
        XCTAssertTrue(el("plan.conflict").waitForExistence(timeout: 5), "the training and the dinner clash")
        shot("plan-conflict")
        reveal("plan.conflict.apply").tap()
        XCTAssertTrue(el("undo.action").waitForExistence(timeout: 3), "«Aplicar» offers Desfazer")
        XCTAssertFalse(el("plan.conflict").exists, "the training moved: no conflict")
        el("undo.action").tap()
        XCTAssertTrue(el("plan.conflict").waitForExistence(timeout: 5), "Desfazer puts the training back, so the conflict is back")
        reveal("plan.conflict.keep").tap()
        waitGone(el("plan.conflict.apply"))
        XCTAssertTrue(el("plan.conflict").exists, "«Manter assim» keeps the conflict in sight")
        choose("Semana")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'plan.week.day.' AND label CONTAINS 'conflito'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the week shows the conflict")
        XCTAssertFalse(el("plan.proposal").exists, "kept as it is: no proposal")
        choose("Mês")
        XCTAssertTrue(reveal("plan.month.conflict").exists, "and so does the month")
    }

    /// One line read back into the form: «às 3» has two readings, so Guardar waits for one; Cancelar saves nothing
    func testANewEventIsSavedOnlyWithGuardar() {
        launch("plan.new", minute: 9 * 60)
        open(.plan)
        reveal("plan.new.open").tap()
        let text = el("plan.new.text")
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("Dentista hoje as 3\n")
        XCTAssertTrue(el("plan.new.time.0").waitForExistence(timeout: 3), "an hour from 1 to 11 asks which one")
        XCTAssertFalse(el("plan.new.save").isEnabled, "Guardar waits for the time")
        shot("plan-new")
        el("plan.new.cancel").tap()
        waitGone(text)
        XCTAssertFalse(app.staticTexts["Dentista"].exists, "nothing is saved before Guardar")
        reveal("plan.new.open").tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("Dentista hoje as 3\n")
        reveal("plan.new.time.0").tap()
        let save = reveal("plan.new.save")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(el("undo.action").waitForExistence(timeout: 3), "Guardar offers Desfazer")
        XCTAssertTrue(app.staticTexts["Dentista"].waitForExistence(timeout: 5), "the event is on the day")
    }

    /// Feito, Não fiz and Não se aplica are yours to choose: «Fechar sem rever» saves nothing, «Concluído» saves the
    /// answer (with Desfazer), and the review then shows it
    func testTheReviewSavesOnlyWhatYouAnswer() {
        launch("plan.review", minute: 21 * 60 + 45)
        open(.plan)
        reveal("plan.review.open").tap()
        let done = el("plan.review.plan-review-shake.done")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "an unanswered habit has the three answers")
        XCTAssertTrue(el("plan.review.plan-review-shake.na").exists)
        reveal("plan.review.plan-review-shake.done").tap()
        XCTAssertTrue(done.isSelected)
        reveal("plan.review.close").tap()
        waitGone(done)
        reveal("plan.review.open").tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(done.isSelected, "closing without reviewing saved nothing")
        reveal("plan.review.plan-review-shake.na").tap()
        shot("plan-review")
        reveal("plan.review.save").tap()
        XCTAssertTrue(el("undo.action").waitForExistence(timeout: 3), "«Concluído» offers Desfazer")
        waitGone(el("undo.bar"), timeout: 10) // the bar sits over the bottom of the screen for 5 s
        reveal("plan.review.open").tap()
        let state = el("plan.review.plan-review-shake.state")
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertTrue(state.label.contains("Não se aplica"), "label was: \(state.label)")
        XCTAssertFalse(el("plan.review.plan-review-shake.done").exists, "answered: no more buttons")
    }
}
