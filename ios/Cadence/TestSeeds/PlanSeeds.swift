// UI-test scenarios for Plano (2.8). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "plan.<case>" and act only on those.
import Foundation

@MainActor
enum PlanSeeds {
    static func apply(_ store: Store, scenario: String) {
    }
}
