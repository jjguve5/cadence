// UI-test scenarios for Comida (2.7). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "food.<case>" and act only on those.
import Foundation

@MainActor
enum FoodSeeds {
    static func apply(_ store: Store, scenario: String) {
    }
}
