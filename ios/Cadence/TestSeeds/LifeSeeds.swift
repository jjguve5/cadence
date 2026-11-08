// UI-test scenarios for Vida (2.10). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "life.<case>" and act only on those.
import Foundation

@MainActor
enum LifeSeeds {
    static func apply(_ store: Store, scenario: String) {
        switch scenario {
        case "life.wardrobe":
            // A piece never worn since its wash, and one at its limit (suggested for washing, still under «Disponível»)
            store.save(Garment(id: "T1", name: "T-shirt cinzenta", type: "top", colors: ["9AA3B2"], wearsBeforeWash: 3, totalWears: 12))
            store.save(Garment(id: "B1", name: "Ganga azul", type: "bottom", colors: ["3E5C8A"], wearsBeforeWash: 4, wears: 4, state: "worn", totalWears: 30))
        case "life.laundry":
            // One piece drying, and one worn up to its limit, as «Vesti hoje» leaves it: suggested for washing, until you
            // tap «Para lavar»
            store.save(Garment(id: "D1", name: "Toalha de treino", type: "gym", washGroup: "towels 60°", wearsBeforeWash: 1, wears: 1, state: "drying", totalWears: 5))
            store.save(Garment(id: "W1", name: "T-shirt treino preta", type: "gym", washGroup: "gym 30°", wearsBeforeWash: 1, wears: 1, state: "worn", totalWears: 8))
        case "life.need":
            // Training every day and the only training kit at its limit: the need «Lavar a roupa de treino»
            store.save(WorkoutTemplate(id: "TPL", name: "Treino", exercises: [], weekdays: [1, 2, 3, 4, 5, 6, 7]))
            store.save(Garment(id: "K1", name: "T-shirt treino azul", type: "gym", washGroup: "gym 30°", wearsBeforeWash: 1, wears: 1, state: "worn", totalWears: 8))
        case "life.shopping":
            // The same product from the pantry (running out) and by hand, and another item of yours
            store.save(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30, aisle: "Health"))
            store.save(ShoppingItem(id: "S1", name: "Whey"))
            store.save(ShoppingItem(id: "S2", name: "Ovos", qty: 12, aisle: "Dairy"))
        default:
            break
        }
    }
}
