// Phase 2.0 regression base, part 2: current behaviour that the design v17 INTENTIONALLY changes.
// These tests describe the app as it is today so a change is never accidental, but they must not block the fix:
// the phase named on each test changes the assertion to the new behaviour in the same commit as the fix (and moves
// the test to RegressionPreservedTests if the new behaviour should then be kept). No other phase should touch them.
// Behaviour that lives only in a view (and can't be tested here without changing the app) is listed at the end.
import XCTest
@testable import Cadence

final class RegressionPlannedChangeTests: RegressionCase {
    // Phase 2.10 (Vida) updated its three tests (washing keeps the wear count until «Arrumada», a piece worn below its
    // limit can be suggested again, one shopping line per product) and moved them to RegressionPreservedTests
    // (RegressionWardrobeTests and RegressionCareAndShoppingTests).
    // Phase 2.9 (Noite) updated the bedtime habit's test (the band's answer shows as «Importado», «Vou dormir» is a
    // separate intention) and moved it to RegressionPreservedTests (RegressionNightTests).

    // Phase 2.8 (Plano) updated testCurrentAHabitHasOnlyThreeAnswers (the review's «Não se aplica» is a skip with
    // notApplicable, «não confirmado» is no log, still three LogStatus values) and moved it to RegressionPreservedTests
    // (RegressionPlanReviewTests.testTheReviewTellsFourAnswersApartWithThreeStatuses).
}

// Changes the design v17 asks for that live in views only, so this phase can't test them without changing the app.
// The phase that changes each one adds its test (a unit test of a new function, or a UI test with a stable identifier):
// - 2.6 Treino: done in phase 2.6 (the target apart from the set, warm-ups by muscle group: TrainingTests).
// - 2.3 PT-PT: tab names and the texts the UI tests read (UIText in CadenceUITests). Since phase 2.1 tab screens and
//   rings have internal identifiers (<name>.screen, ring.<key>) that a translation doesn't change, and the UI tests
//   find a tab through its screen, not by its name or place.
