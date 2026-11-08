// UI-test scenarios for Hoje (2.4). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "today.<case>" and act only on those.
import Foundation

@MainActor
enum TodaySeeds {
    static func apply(_ store: Store, scenario: String) {
    }
}
