// Phase 2.7 (Comida): nothing is saved with one tap, only «Guardar refeição» saves (with Desfazer), «Editar» reopens
// the same entry without duplicating it, and the water goal is suggested until you accept it. Scenarios in
// TestSeeds/FoodSeeds.swift; elements found by identifier, no sleeps.
import XCTest

final class FoodUITests: CadenceUITestCase {
    /// Corpo → Comida. The Comida card on Corpo has no identifier of its own (BodyView isn't this phase's file), so it
    /// is found by the word on its calories line, the only one on that tab; from there on everything has an identifier
    private func openFood(file: StaticString = #filePath, line: UInt = #line) {
        open(.body, file: file, line: line)
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Calorias")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no Comida card on Corpo", file: file, line: line)
        card.tap()
        XCTAssertTrue(el("fuel.screen").waitForExistence(timeout: 5), "Comida didn't open", file: file, line: line)
    }

    /// The rows of today's food on Comida
    private func entries() -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fuel.entry."))
    }

    /// A caffeine drink no longer saves on the tap: it opens the confirmation, going back saves nothing (the drink waits,
    /// marked to be saved), and only «Guardar refeição» saves, with Desfazer, then the summary closes back to Comida
    func testACaffeineDrinkIsSavedOnlyFromTheConfirmation() {
        launch("food.empty")
        openFood()
        XCTAssertTrue(el("fuel.empty").exists, "nothing logged today")
        reveal("fuel.log").tap()
        reveal("food.caffeine.0").tap()
        XCTAssertTrue(el("food.confirm.screen").waitForExistence(timeout: 5), "the tap opens the confirmation")
        XCTAssertTrue(el("food.confirm.save").exists)
        shot("food-confirm")
        el("food.confirm.back").tap()
        XCTAssertTrue(el("food.draft.review").waitForExistence(timeout: 5), "back on the list, the drink waits to be saved")
        el("food.close").tap()
        XCTAssertTrue(el("fuel.empty").waitForExistence(timeout: 5), "closing without «Guardar refeição» saved nothing")
        XCTAssertEqual(entries().count, 0)

        reveal("fuel.log").tap()
        reveal("food.caffeine.0").tap()
        let save = el("food.confirm.save")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(el("food.summary").waitForExistence(timeout: 5), "after saving, the summary")
        XCTAssertTrue(el("undo.bar").exists, "and Desfazer")
        shot("food-summary")
        reveal("food.summary.done").tap()
        XCTAssertTrue(el("fuel.screen").waitForExistence(timeout: 5))
        XCTAssertEqual(entries().count, 1, "saved once")
    }

    /// «Editar» reopens the same entry: changing the amount and saving again replaces it, there is still one entry
    func testEditingReopensTheSameEntryWithoutDuplicating() {
        launch("food.logged")
        openFood()
        XCTAssertEqual(entries().count, 1)
        reveal("fuel.entry.food-ui-1").tap()
        let item = el("food.item.food-ui-1")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the confirmation opens the saved entry itself")
        item.tap()
        reveal("food.item.food-ui-1.more").tap()
        XCTAssertTrue(el("food.item.food-ui-1.amount").label.contains("1,1"), "amount: \(el("food.item.food-ui-1.amount").label)")
        el("food.confirm.save").tap()
        XCTAssertTrue(el("food.summary").waitForExistence(timeout: 5))
        reveal("food.summary.done").tap()
        XCTAssertTrue(el("fuel.screen").waitForExistence(timeout: 5))
        XCTAssertEqual(entries().count, 1, "saved again, still one entry")
        let row = el("fuel.entry.food-ui-1")
        XCTAssertTrue(row.exists, "the same record")
        XCTAssertTrue(row.label.contains("1,1"), "with the new amount: \(row.label)")
        shot("food-edited")
    }

    /// The water goal shows as «Sugerido» until «Aceitar meta»; Desfazer takes the acceptance back
    func testTheWaterGoalIsSuggestedUntilAccepted() {
        launch("food.empty")
        openFood()
        XCTAssertTrue(reveal("water.goal.suggested").exists)
        XCTAssertFalse(el("water.goal.confirmed").exists, "not confirmed by itself")
        reveal("water.goal.accept").tap()
        XCTAssertTrue(el("water.goal.confirmed").waitForExistence(timeout: 5), "accepted: confirmed")
        shot("water-goal-accepted")
        let undo = el("undo.action")
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(el("water.goal.suggested").waitForExistence(timeout: 5), "Desfazer: suggested again")
    }
}
