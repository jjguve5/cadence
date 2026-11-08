// UI-test scenarios for Vida (2.10). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "life.<case>" and act only on those.
import Foundation

@MainActor
enum LifeSeeds {
    static func apply(_ store: Store, scenario: String) {
    }
}
