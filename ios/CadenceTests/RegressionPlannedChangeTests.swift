// Phase 2.0 regression base, part 2: current behaviour that the design v17 INTENTIONALLY changes.
// These tests describe the app as it is today so a change is never accidental, but they must not block the fix:
// the phase named on each test changes the assertion to the new behaviour in the same commit as the fix (and moves
// the test to RegressionPreservedTests if the new behaviour should then be kept). No other phase should touch them.
// Behaviour that lives only in a view (and can't be tested here without changing the app) is listed at the end.
import XCTest
@testable import Cadence

final class RegressionPlannedChangeTests: RegressionCase {
    /// Phase 2.10 (Vida): the wear count goes back to zero only when you confirm «Arrumada» (put away), not when the
    /// load is washed. Update: after washed(), wears stays as it was; after putAway(), it is 0.
    @MainActor
    func testCurrentWashingResetsTheWearCountBeforePuttingAway() throws {
        let store = try makeStore { $0.add(Garment(id: "J1", name: "Jeans", type: "bottom", washGroup: "darks 30°", wears: 3, state: "wash")) }
        store.washed("darks 30°")
        let drying = try XCTUnwrap(store.record(Garment.self, "J1"))
        XCTAssertEqual(drying.state, "drying")
        XCTAssertEqual(drying.wears, 0, "today: reset when washed")
        store.putAway()
        XCTAssertEqual(store.record(Garment.self, "J1")?.state, "clean")
    }

    /// Phase 2.10 (Vida): a piece worn fewer times than its wash limit can still be suggested. Update: the worn top
    /// below its limit is offered; one at its limit, in the wash or drying is never offered.
    @MainActor
    func testCurrentAPieceWornOnceIsNotSuggestedAgainUntilWashed() throws {
        let store = try makeStore { s in
            s.add(Garment(id: "T1", name: "Grey T-shirt", type: "top", wearsBeforeWash: 3, wears: 1, state: "worn"))
            s.add(Garment(id: "B1", name: "Jeans", type: "bottom"))
        }
        XCTAssertFalse(store.outfit(for: Fixed.saturday).map(\.id).contains("T1"), "today: only clean pieces are suggested")
    }

    /// Phases 2.5 and 2.10: one line per product, wherever the need comes from. Update: one "Whey" line whose reason
    /// names both sources.
    @MainActor
    func testCurrentTheSameProductFromThePantryAndByHandIsListedTwice() throws {
        let store = try makeStore { s in
            s.add(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30))
            s.add(ShoppingItem(id: "S1", name: "Whey"))
        }
        XCTAssertEqual(store.shoppingList().map(\.name), ["Whey", "Whey"], "today: no check for duplicates across sources")
    }

    /// Phase 2.7 (Comida): the food group is chosen per item and a flavour isn't a fruit. Update: a protein drink
    /// "aroma manga" counts for no group (an old entry without a stored group may keep the name rule).
    func testCurrentAFlavourWordCountsAsFruit() {
        XCTAssertEqual(FoodGoals.groups(name: "Proteína Aroma Manga"), [FoodGoals.fruit], "today: «manga» in the name makes it fruit")
    }

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
        XCTAssertEqual(store.answerSource(lightsOut, on: yesterday), "fitbit", "but kept as imported from the band, not as your answer")
    }

    /// Phase 2.8 (Plano): the end-of-day review tells «não fiz», «não confirmado» and «não se aplica» apart. Update:
    /// the new answer(s) exist, and the rollback test still passes (an older build must keep reading the file).
    func testCurrentAHabitHasOnlyThreeAnswers() {
        XCTAssertEqual(["done", "skipped", "tiny"].compactMap(LogStatus.init(rawValue:)), [.done, .skipped, .tiny])
        XCTAssertNil(LogStatus(rawValue: "notConfirmed"))
        XCTAssertNil(LogStatus(rawValue: "notApplicable"))
    }

    /// Phase 2.6 (Treino): the suggested target and what you did are kept apart. Update: a set can carry its target
    /// (optional fields, so older sessions still read and older builds ignore them).
    func testCurrentASetKeepsNoSeparateTarget() throws {
        let data = try JSONEncoder().encode(SetLog(id: "X", exerciseId: "leg-extension", weight: 20, reps: 10, done: true))
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["id", "exerciseId", "kind", "weight", "reps", "done"])
    }
}

// Changes the design v17 asks for that live in views only, so this phase can't test them without changing the app.
// The phase that changes each one adds its test (a unit test of a new function, or a UI test with a stable identifier):
// - 2.4 Hoje: "Next up" looks at habits only, and a ring with no data draws an empty arc instead of a dashed one.
// - 2.5 Higiene: the routine player saves nothing at the end; "Added to shopping" saves nothing.
// - 2.6 Treino: the suggested weight is written into the set (TrainingView); warm-ups go on every exercise above
//   bar + 10 kg instead of the first exercise of each muscle group.
// - 2.7 Comida: several paths save on one tap with no confirmation (portion pick, recent foods, caffeine drinks).
// - 2.3 PT-PT: tab names and the texts the UI tests read (UIText in CadenceUITests). Since phase 2.1 tab screens and
//   rings have internal identifiers (<name>.screen, ring.<key>) that a translation doesn't change, and the UI tests
//   find a tab through its screen, not by its name or place.
