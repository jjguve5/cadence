// Phase 2.9 (Noite, Antes de sair e Antes de dormir): Antes de sair as «Agora» with «Concluído» and Desfazer, the night's
// sequence with Preparar amanhã and «Vou dormir» as an intention, and the short version when it's late. Scenarios in
// Cadence/TestSeeds/NightSeeds.swift; elements found by identifier, no sleeps.
import XCTest

final class NightUITests: CadenceUITestCase {
    /// 8:00, a regular trip leaving at 8:40: Antes de sair is the step. Tapping an item marks it as taken, «Concluído»
    /// marks the rest and shows «Pronto para sair» with Desfazer, the list opens again, and then it's no longer the step
    func testAntesDeSairIsTheStepAndConcluidoMarksTheRest() {
        launch("night.leave", minute: 8 * 60)
        XCTAssertTrue(el("now.beforeleaving").waitForExistence(timeout: 5), "a departure within the hour with things to see")
        reveal("next.action").tap()
        XCTAssertTrue(el("leave.screen").waitForExistence(timeout: 5))
        let keys = el("leave.item.keys")
        XCTAssertTrue(keys.waitForExistence(timeout: 5))
        XCTAssertTrue(keys.label.contains("por ver"), "label was: \(keys.label)")
        keys.tap()
        XCTAssertTrue(el("leave.seen").waitForExistence(timeout: 5), "what's seen closes in one line")
        waitGone(el("undo.bar"), timeout: 10) // the bar could cover «Concluído»
        reveal("leave.done").tap()
        XCTAssertTrue(el("leave.ready").waitForExistence(timeout: 5), "«Pronto para sair»")
        XCTAssertTrue(el("undo.bar").exists, "with Desfazer")
        shot("night-leave-ready")
        reveal("leave.reopen").tap()
        XCTAssertTrue(el("leave.item.mine-night-pass").waitForExistence(timeout: 5), "the list opens again, everything in it")
        el("leave.close").tap()
        waitGone(el("leave.screen"))
        waitGone(el("now.beforeleaving"))
    }

    /// 22:00, brushing done: «Agora» is Preparar amanhã. «Aceitar roupa» chooses tomorrow's outfit, «Pus os 6 no saco»
    /// packs the bag; then the reading, and «Vou dormir» opens Boa noite and leaves only the intention on Today
    func testPreparingTomorrowThenGoingToSleep() {
        launch("night.prep", minute: 22 * 60)
        XCTAssertTrue(el("night.card").waitForExistence(timeout: 5), "at night «Agora» follows the night's sequence")
        XCTAssertTrue(el("night.now.prepare").exists, "teeth done: preparing tomorrow is now")
        shot("night-today")
        reveal("next.action").tap()
        XCTAssertTrue(el("night.prep.screen").waitForExistence(timeout: 5))
        reveal("night.outfit.accept").tap()
        XCTAssertTrue(el("night.outfit.chosen").waitForExistence(timeout: 5), "chosen, with no use counted")
        XCTAssertTrue(el("undo.bar").exists, "with Desfazer")
        waitGone(el("undo.bar"), timeout: 10) // the bar could cover the next button
        reveal("night.bag.packall").tap()
        XCTAssertTrue(el("night.bag.ready").waitForExistence(timeout: 5), "the bag is ready")
        shot("night-prep")
        waitGone(el("undo.bar"), timeout: 10)
        reveal("night.prep.read").tap()
        XCTAssertTrue(el("night.bedtime.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(el("night.plan").exists, "tonight's plan, as a suggestion")
        reveal("night.sleep").tap()
        XCTAssertTrue(el("night.goodnight").waitForExistence(timeout: 5), "«Vou dormir» opens Boa noite")
        shot("night-goodnight")
        el("night.goodnight.close").tap()
        XCTAssertTrue(el("night.intent").waitForExistence(timeout: 5), "Today keeps the intention, nothing more to do")
    }

    /// 22:00, the night's brushing answered «Não fiz»: the sequence moves on, and it's said as it was answered, in the
    /// sequence and in Antes de dormir, never «feito»
    func testATeethHabitAnsweredNotDoneIsSaidAsNotDone() {
        launch("night.skipped", minute: 22 * 60)
        XCTAssertTrue(el("night.now.prepare").waitForExistence(timeout: 5), "the sequence moves on with any answer")
        let steps = el("night.steps")
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        XCTAssertTrue(steps.label.contains("Dentes, não fiz"), "label was: \(steps.label)")
        reveal("night.later").tap()
        XCTAssertTrue(el("night.bedtime.screen").waitForExistence(timeout: 5))
        let row = reveal("night.step.teeth")
        XCTAssertTrue(row.label.contains("não fiz"), "label was: \(row.label)")
        XCTAssertFalse(row.label.contains("feito"), "label was: \(row.label)")
        shot("night-teeth-notdone")
    }

    /// 23:50, past lights out + 30: the short version straight away, with reading 10 min still possible
    func testLateShowsOnlyTheEssentials() {
        launch("night.late", minute: 23 * 60 + 50)
        XCTAssertTrue(el("night.now.sleep").waitForExistence(timeout: 5), "late: Antes de dormir at once")
        reveal("next.action").tap()
        XCTAssertTrue(el("night.bedtime.short").waitForExistence(timeout: 5), "«Só o essencial»")
        XCTAssertTrue(el("night.read.short").exists)
        XCTAssertTrue(el("night.sleep").exists)
        shot("night-late")
    }
}
