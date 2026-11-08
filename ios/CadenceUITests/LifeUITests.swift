// Phase 2.10 (Vida): the Roupeiro's «Vesti hoje», the Lavandaria's explicit steps, one shopping line per product,
// each with Desfazer. Scenarios in Cadence/TestSeeds/LifeSeeds.swift; elements found by identifier, no sleeps.
import XCTest

final class LifeUITests: CadenceUITestCase {
    /// «Vesti hoje» on one piece adds one use and shows Desfazer; Desfazer takes the use back
    func testWearingAPieceAddsOneUseAndCanBeUndone() {
        launch("life.wardrobe")
        open(.life)
        reveal("life.area.wardrobe").tap()
        reveal("life.wardrobe.piece.T1").tap()
        let uses = reveal("life.wardrobe.uses")
        XCTAssertTrue(uses.label.contains("Ainda não usada"), uses.label)
        reveal("life.wardrobe.wear").tap()
        XCTAssertTrue(el("undo.bar").waitForExistence(timeout: 5))
        waitForLabel(uses, contains: "Usada 1 vez")
        shot("life-wardrobe-worn")
        el("undo.action").tap()
        waitForLabel(uses, contains: "Ainda não usada")
    }

    /// «Arrumada» returns a drying piece to the wardrobe and Desfazer puts it back to dry; a piece at its limit reaches
    /// «para lavar» only with your tap, and «Pôr a lavar agora» moves the load into «em lavagem»
    func testLaundryStepsAreExplicitAndCanBeUndone() {
        launch("life.laundry")
        open(.life)
        reveal("life.area.laundry").tap()
        XCTAssertTrue(el("life.laundry.screen").waitForExistence(timeout: 5))
        let putAway = reveal("life.laundry.putaway.D1")
        putAway.tap()
        waitGone(el("life.laundry.putaway.D1"))
        XCTAssertTrue(el("undo.bar").waitForExistence(timeout: 5))
        el("undo.action").tap()
        XCTAssertTrue(el("life.laundry.putaway.D1").waitForExistence(timeout: 5), "Desfazer puts it back to dry")
        XCTAssertFalse(el("life.laundry.plan.gym30").exists, "at its limit it's only suggested: nothing to plan yet")
        reveal("life.laundry.towash.W1").tap()
        reveal("life.laundry.plan.gym30").tap()
        XCTAssertTrue(el("life.load.screen").waitForExistence(timeout: 5))
        reveal("life.load.start").tap()
        XCTAssertTrue(el("life.laundry.washing.W1").waitForExistence(timeout: 5), "the piece is in the machine")
        shot("life-laundry-washing")
    }

    /// The need for the training kit opens a load where the pieces at their limit are candidates: nothing goes in by
    /// itself, and once you join one, «Pôr a lavar agora» puts it in the machine
    func testTheGymKitNeedLeadsToALoadYouCanStart() {
        launch("life.need")
        open(.life)
        reveal("life.now.action").tap()
        XCTAssertTrue(el("life.load.screen").waitForExistence(timeout: 5))
        let join = reveal("life.load.join.K1")
        XCTAssertFalse(el("life.load.start").isEnabled, "nothing goes in by itself")
        shot("life-load-candidate")
        join.tap()
        let start = reveal("life.load.start")
        XCTAssertTrue(start.isEnabled, "joined: part of the load")
        start.tap()
        XCTAssertTrue(el("undo.bar").waitForExistence(timeout: 5))
        reveal("life.area.laundry").tap()
        XCTAssertTrue(el("life.laundry.washing.K1").waitForExistence(timeout: 5), "the piece is in the machine")
    }

    /// The same product from the pantry and by hand is one line naming both; the circle marks it bought by you and
    /// Desfazer brings it back
    func testShoppingHasOneLinePerProductAndBuyingCanBeUndone() {
        launch("life.shopping")
        open(.life)
        reveal("life.area.shopping").tap()
        XCTAssertTrue(el("life.shopping.screen").waitForExistence(timeout: 5))
        let whey = el("life.shopping.line.whey")
        XCTAssertTrue(whey.waitForExistence(timeout: 5))
        XCTAssertFalse(el("life.shopping.line.s-S1").exists, "your own «Whey» folds into the same line")
        XCTAssertTrue(whey.label.contains("adicionado por ti"), whey.label)
        shot("life-shopping")
        reveal("life.shopping.buy.whey").tap()
        waitGone(el("life.shopping.line.whey"))
        XCTAssertTrue(el("undo.bar").waitForExistence(timeout: 5))
        el("undo.action").tap()
        XCTAssertTrue(el("life.shopping.line.whey").waitForExistence(timeout: 5), "Desfazer puts the line back")
    }

    private func waitForLabel(_ e: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: e)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "label was: \(e.label)", file: file, line: line)
    }
}
