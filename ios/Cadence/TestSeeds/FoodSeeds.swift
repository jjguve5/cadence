// UI-test scenarios for Comida (2.7). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "food.<case>" and act only on those.
//   food.empty  — the normal history, nothing eaten or drunk today, the water goal only suggested
//   food.logged — the same, with one food logged today (id food-ui-1), to reopen with «Editar»
import Foundation

@MainActor
enum FoodSeeds {
    static func apply(_ store: Store, scenario: String) {
        guard scenario.hasPrefix("food.") else { return }
        // Desfazer stays a little longer in these scenarios, so a slow simulator still reaches it after saving
        UndoCenter.shared.seconds = 20
        switch scenario {
        case "food.logged":
            store.save(FoodEntry(id: "food-ui-1", date: Day.today, minute: 12 * 60 + 30, name: "Banana", kcal: 105, protein: 1.3,
                                 group: FoodGoals.fruit, quantity: 1, unit: FoodUnit.portion.rawValue, estimated: true))
        default:
            break
        }
    }
}
