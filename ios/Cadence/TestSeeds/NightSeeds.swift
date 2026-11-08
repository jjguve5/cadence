// UI-test scenarios for Noite, Antes de sair e Antes de dormir (2.9). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "night.<case>" and act only on those.
import Foundation

@MainActor
enum NightSeeds {
    static func apply(_ store: Store, scenario: String) {
    }
}
