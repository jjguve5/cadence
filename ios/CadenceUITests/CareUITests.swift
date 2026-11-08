// Phase 2.5 · Higiene: the routine of the moment is confirmed by you, all at once or one step at a time, with Desfazer,
// and kept per day; the routine player saves what you did at the end; «Adicionar» puts one real line on the shopping
// list and the suggestion goes. Scenarios "care.<case>" in TestSeeds/CareSeeds.swift (the morning at 8:00).
import XCTest

final class CareUITests: CadenceUITestCase {
    func testTheMorningRoutineIsConfirmedAtOnceAndCanBeUndone() {
        launch("care.morning", minute: 8 * 60)
        open(.hygiene)
        XCTAssertTrue(el("hygiene.now.pending").waitForExistence(timeout: 5), "the morning routine waits for you")
        shot("care-now-pending")
        reveal("hygiene.batch").tap()
        XCTAssertTrue(el("hygiene.now.done").waitForExistence(timeout: 5), "«Já fiz os dois» confirms both")
        let undo = el("undo.action")
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(el("hygiene.now.pending").waitForExistence(timeout: 5), "Desfazer puts both back")
        // one step, kept after the app closes
        reveal("hygiene.step.RM1").tap()
        XCTAssertTrue(el("undo.bar").waitForExistence(timeout: 5))
        app.terminate()
        launch("care.morning", minute: 8 * 60, reset: false)
        open(.hygiene)
        XCTAssertTrue(el("hygiene.now.pending").waitForExistence(timeout: 5))
        XCTAssertTrue(el("hygiene.step.RM1").label.contains("feito"), "label was: \(el("hygiene.step.RM1").label)")
        XCTAssertTrue(el("hygiene.step.RM2").label.contains("por confirmar"), "label was: \(el("hygiene.step.RM2").label)")
        shot("care-now-one-done")
    }

    func testThePlayerSavesTheStepsAtTheEnd() {
        launch("care.morning", minute: 8 * 60)
        open(.hygiene)
        reveal("hygiene.start").tap()
        let done = el("care.player.done")
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the second step")
        done.tap()
        XCTAssertTrue(el("care.player.finished").waitForExistence(timeout: 5))
        shot("care-player-end")
        el("care.player.close").tap()
        XCTAssertTrue(el("hygiene.now.done").waitForExistence(timeout: 5), "what you did in the player is in Higiene")
    }

    func testAddingAProductToShoppingSavesOneLineOnce() {
        launch("care.product", minute: 8 * 60)
        open(.hygiene)
        reveal("hygiene.product.PB").tap()
        let suggestion = el("care.product.refill")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "it runs out soon and isn't on the list")
        XCTAssertTrue(el("care.product.estimate").exists)
        shot("care-product-suggestion")
        let add = suggestion.buttons["Adicionar"]
        var tries = 0
        while !(add.exists && add.isHittable) && tries < 6 { app.swipeUp(velocity: .slow); tries += 1 }
        add.tap()
        XCTAssertTrue(el("care.product.onlist").waitForExistence(timeout: 5))
        waitGone(el("care.product.refill"))
        // after the app closes it's still on the list, and the suggestion doesn't come back
        app.terminate()
        launch("care.product", minute: 8 * 60, reset: false)
        open(.hygiene)
        reveal("hygiene.product.PB").tap()
        XCTAssertTrue(el("care.product.onlist").waitForExistence(timeout: 5))
        XCTAssertFalse(el("care.product.refill").exists)
        shot("care-product-on-list")
    }
}
