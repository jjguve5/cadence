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

    /// Phases 2.2 and 2.9: data from the band can mark a habit done, but it must show as «Importado», not as confirmed
    /// by you, and «Vou dormir» becomes a separate intention. Phase 2.2 did its part: the answer keeps its source (the
    /// health source, "fitbit" by default). Phase 2.9 updates this test when the UI shows it as imported and «Vou dormir»
    /// exists, then moves it to RegressionPreservedTests.
    /// Built relative to today because autoComplete() only looks at today and yesterday.
    @MainActor
    func testCurrentBandSleepTicksTheBedtimeHabitAsImported() throws {
        let yesterday = Day.add(-1, to: Day.today)
        let lightsOut = PromiseItem(id: "L1", title: "Lights out", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 23 * 60))
        let start = ISO8601DateFormatter().string(from: Day.at(23 * 60 + 5, on: yesterday))
        let end = ISO8601DateFormatter().string(from: Day.at(7 * 60, on: Day.today))
        let store = try makeStore { s in
            s.promises[lightsOut.id] = lightsOut
            s.health[Day.today] = HealthDay(date: Day.today, sleep: SleepRecord(start: start, end: end, asleep: 450))
        }
        store.autoComplete()
        XCTAssertEqual(store.status(lightsOut, on: yesterday), .done, "still counts as done")
        XCTAssertEqual(store.answerOrigin(lightsOut, on: yesterday), .imported("fitbit"), "but kept as imported from the band, not as your answer")
    }

    /// Phase 2.8 (Plano): the end-of-day review tells «não fiz», «não confirmado» and «não se aplica» apart. Update:
    /// the new answer(s) exist, and the rollback test still passes (an older build must keep reading the file).
    func testCurrentAHabitHasOnlyThreeAnswers() {
        XCTAssertEqual(["done", "skipped", "tiny"].compactMap(LogStatus.init(rawValue:)), [.done, .skipped, .tiny])
        XCTAssertNil(LogStatus(rawValue: "notConfirmed"))
        XCTAssertNil(LogStatus(rawValue: "notApplicable"))
    }
}

// Changes the design v17 asks for that live in views only, so this phase can't test them without changing the app.
// The phase that changes each one adds its test (a unit test of a new function, or a UI test with a stable identifier):
// - 2.6 Treino: done in phase 2.6 (the target apart from the set, warm-ups by muscle group: TrainingTests).
// - 2.3 PT-PT: tab names and the texts the UI tests read (UIText in CadenceUITests). Since phase 2.1 tab screens and
//   rings have internal identifiers (<name>.screen, ring.<key>) that a translation doesn't change, and the UI tests
//   find a tab through its screen, not by its name or place.
