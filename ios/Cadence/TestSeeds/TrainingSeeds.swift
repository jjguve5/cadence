// UI-test scenarios for Treino (2.6). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "training.<case>" and act only on those.
import Foundation

@MainActor
enum TrainingSeeds {
    static func apply(_ store: Store, scenario: String) {
    }
}
