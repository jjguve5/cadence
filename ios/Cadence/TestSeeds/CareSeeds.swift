// UI-test scenarios for Higiene (2.5). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "care.<case>" and act only on those.
import Foundation

@MainActor
enum CareSeeds {
    static func apply(_ store: Store, scenario: String) {
    }
}
