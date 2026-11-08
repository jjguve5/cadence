// Phase 2.0 regression base, part 1: current behaviour to KEEP through the redesign (phases 2.1–2.13).
// If one of these fails in a later phase, that phase changed something it shouldn't have.
// Synthetic data, fixed dates, no server, no Fitbit, no Apple Health (see RegressionSupport.swift).
import XCTest
@testable import Cadence

// MARK: - Food and water

final class RegressionFoodTests: RegressionCase {
    @MainActor
    func testFuelAddsUpOneDayAndLeavesOtherDaysOut() throws {
        let store = try makeStore { s in
            s.add(FoodEntry(id: "F1", date: Fixed.saturday, minute: 13 * 60, name: "Lunch", kcal: 500, protein: 30, carbs: 50, fat: 10))
            s.add(FoodEntry(id: "F2", date: Fixed.saturday, minute: 15 * 60, name: "Espresso", kcal: 2, protein: 0, caffeine: 80))
            s.add(FoodEntry(id: "F3", date: Fixed.friday, minute: 13 * 60, name: "Another day", kcal: 900, protein: 50))
            s.add(WaterEntry(id: "W1", date: Fixed.saturday, minute: 600, ml: 250))
            s.add(WaterEntry(id: "W2", date: Fixed.saturday, minute: 700, ml: 500))
            s.add(WaterEntry(id: "W3", date: Fixed.friday, minute: 700, ml: 300))
        }
        let f = store.fuel(on: Fixed.saturday)
        XCTAssertEqual(f.kcal, 502)
        XCTAssertEqual(f.protein, 30)
        XCTAssertEqual(f.carbs, 50)
        XCTAssertEqual(f.fat, 10)
        XCTAssertEqual(f.caffeine, 80)
        XCTAssertEqual(f.water, 750)
        XCTAssertEqual(f.lastMeal, 13 * 60, "a 2 kcal coffee is not a meal")
        XCTAssertEqual(f.lastCaffeine, 15 * 60)
        XCTAssertEqual(store.foods(on: Fixed.saturday).map(\.id), ["F1", "F2"], "in time order")
    }

    /// The calculation stays; phase 2.4/2.5 only change how the result is offered (a suggested goal you accept or adjust)
    @MainActor
    func testWaterGoalRisesWithStepsAboveTheGoalAndOnTrainingDays() throws {
        let store = try makeStore { s in
            s.profile.waterGoalMl = 3000
            s.profile.stepGoal = 8000
            s.health[Fixed.saturday] = HealthDay(date: Fixed.saturday, steps: 13000)
            s.health[Fixed.sunday] = HealthDay(date: Fixed.sunday, steps: 20000)
            s.health[Fixed.tuesday] = HealthDay(date: Fixed.tuesday, steps: 8000)
            s.health[Fixed.wednesday] = HealthDay(date: Fixed.wednesday, steps: 9100)
            s.add(WorkoutSession(id: "S1", date: Fixed.saturday, name: "Legs", start: 1_000, end: 2_000, order: []))
        }
        XCTAssertEqual(store.waterGoal(on: Fixed.saturday), 4000, "+500 for 5000 steps over, +500 for training")
        XCTAssertEqual(store.waterGoal(on: Fixed.sunday), 4000, "steps add at most 1000")
        XCTAssertEqual(store.waterGoal(on: Fixed.monday), 3000, "no data: the profile goal")
        XCTAssertEqual(store.waterGoal(on: Fixed.tuesday), 3000, "at the step goal, nothing extra")
        XCTAssertEqual(store.waterGoal(on: Fixed.wednesday), 3100, "rounded to 50 ml")
    }

    /// Phase 2.7 (moved from RegressionPlannedChangeTests): the food group is chosen per item and always saved, and a
    /// flavour isn't a fruit: a protein drink «aroma manga», typed or from a product, counts for no group until you
    /// choose one. An old entry without a stored group keeps the name rule, which itself is unchanged.
    @MainActor
    func testAFlavourIsNotAFruitOnceTheGroupIsChosenPerItem() throws {
        let typed = FoodItem(manual: "Proteína Aroma Manga", kcal: 120, protein: 24)
        let product = FoodItem(product: OFFProduct(name: "Proteína Aroma Manga", kcal100: 40, protein100: 8, carbs100: nil, fat100: nil, serving: 330))
        for item in [typed, product] {
            let e = item.entry(date: Fixed.saturday, minute: 600)
            XCTAssertEqual(e.group, FoodGoals.noGroup, "the group is saved, and it is none until you choose one")
            XCTAssertEqual(FoodGoals.count([e]), FoodGoalCounts(), "a flavour isn't a fruit")
        }
        var chosen = FoodItem(manual: "Manga", kcal: 60, protein: 0.5)
        chosen.group = FoodGoals.fruit
        XCTAssertEqual(FoodGoals.count([chosen.entry(date: Fixed.saturday, minute: 620)]).fruit, 1, "fruit when you choose it")
        let old = FoodEntry(id: "OLD", date: Fixed.saturday, minute: 900, name: "Proteína Aroma Manga", kcal: 120, protein: 24)
        XCTAssertEqual(FoodGoals.groups(of: old), [FoodGoals.fruit], "an old entry without a stored group keeps the name rule")
        XCTAssertEqual(FoodGoals.groups(name: "Proteína Aroma Manga"), [FoodGoals.fruit], "the name rule itself is unchanged")
        let store = try makeStore { $0.add(old) }
        store.saveMeal([typed], date: Fixed.saturday, minute: 600)
        XCTAssertEqual(store.foods(on: Fixed.saturday).count, 2)
        XCTAssertEqual(FoodGoals.count(store.foods(on: Fixed.saturday)).fruit, 1, "only the old entry still counts as fruit")
    }
}

// MARK: - Training

final class RegressionTrainingTests: RegressionCase {
    private let legExtension = TemplateExercise(exerciseId: "leg-extension", name: "Leg Extensions", sets: 3, repLow: 8, repHigh: 12)

    private func finished(_ id: String, start: Double, _ sets: [(Double, Int)]) -> WorkoutSession {
        WorkoutSession(id: id, date: Fixed.saturday, name: "Legs", start: start, end: start + 3_600_000, order: [],
                       sets: sets.map { SetLog(exerciseId: "leg-extension", weight: $0.0, reps: $0.1, done: true) })
    }

    @MainActor
    func testNoHistoryAsksYouToPickTheWeight() throws {
        let store = try makeStore()
        let s = store.suggestion(for: legExtension)
        XCTAssertEqual(s.weight, 0)
        XCTAssertEqual(s.sets, 3)
        XCTAssertEqual(s.reason, "Primeira vez: escolhe um peso com que conseguirias fazer 14 repetições")
    }

    @MainActor
    func testEverySetAtTheTopOfTheRangeAddsTheIncrement() throws {
        let store = try makeStore { $0.add(self.finished("S1", start: 1_000, [(18, 12), (18, 12), (18, 12)])) }
        let s = store.suggestion(for: legExtension)
        XCTAssertEqual(s.weight, 20.5)
        XCTAssertEqual(s.sets, 3, "low or missing readiness never removes a set (docs/AUDIT.md, problem 2)")
        XCTAssertEqual(s.reason, "+2.5 kg: da última vez fizeste 3 × 12 com 18")
    }

    @MainActor
    func testMissingTheTopKeepsTheWeight() throws {
        let store = try makeStore { $0.add(self.finished("S1", start: 1_000, [(18, 12), (18, 11), (18, 10)])) }
        let s = store.suggestion(for: legExtension)
        XCTAssertEqual(s.weight, 18)
        XCTAssertEqual(s.reason, "Mesmo peso: tenta 12 em todas as séries")
    }

    @MainActor
    func testFourFlatSessionsDeloadTenPercent() throws {
        let store = try makeStore { s in
            for i in 0..<4 { s.add(self.finished("S\(i)", start: Double(1_000 + i * 10_000_000), [(20, 10), (20, 10), (20, 10)])) }
        }
        let s = store.suggestion(for: legExtension)
        XCTAssertEqual(s.weight, 17.5, "20 kg × 0.9, rounded to 2.5 kg")
        XCTAssertEqual(s.reason, "Sem progresso há 3 sessões: desce 10% e volta a subir")
    }

    @MainActor
    func testLastSetsComeFromTheLatestFinishedSessionOnly() throws {
        let store = try makeStore { s in
            s.add(self.finished("old", start: 1_000, [(15, 12)]))
            s.add(self.finished("new", start: 5_000, [(17.5, 10), (17.5, 9)]))
            s.add(WorkoutSession(id: "open", date: Fixed.saturday, name: "Legs", start: 9_000, order: [],
                                 sets: [SetLog(exerciseId: "leg-extension", weight: 30, reps: 10, done: true)]))
            s.add(WorkoutSession(id: "warm", date: Fixed.saturday, name: "Legs", start: 7_000, end: 8_000, order: [],
                                 sets: [SetLog(exerciseId: "leg-extension", kind: .warmup, weight: 10, reps: 10, done: true)]))
        }
        XCTAssertEqual(store.lastSets("leg-extension").map(\.weight), [17.5, 17.5], "unfinished sessions and warm-up-only sessions don't count")
    }

    /// The percentages stay. Which exercises get warm-ups changed in phase 2.6: only the first of each muscle group new
    /// in the session (TrainingTests); these sets are still the ones it gets.
    @MainActor
    func testWarmUpsAreFortySixtyEightyPercentAboveBarPlusTen() throws {
        let store = try makeStore { $0.profile.barKg = 20 }
        XCTAssertTrue(store.warmups(for: 30).isEmpty, "30 kg is not above bar + 10")
        XCTAssertEqual(store.warmups(for: 60).map { "\($0.weight)×\($0.reps)" }, ["25.0×8", "35.0×5", "47.5×3"])
        XCTAssertEqual(store.warmups(for: 31).map { "\($0.weight)×\($0.reps)" }, ["20.0×8", "20.0×5", "25.0×3"], "never below the bar")
    }

    @MainActor
    func testPlatesPerSide() throws {
        let store = try makeStore { s in
            s.profile.barKg = 20
            s.profile.plates = [25, 20, 15, 10, 5, 2.5, 1.25]
        }
        XCTAssertEqual(store.plates(for: 60), [20])
        XCTAssertEqual(store.plates(for: 47.5), [10, 2.5, 1.25])
        XCTAssertTrue(store.plates(for: 20).isEmpty)
    }

    func testEpleyAndVolume() {
        XCTAssertEqual(e1rm(100, 1), 100)
        XCTAssertEqual(e1rm(100, 10), 133.333, accuracy: 0.001)
        let s = WorkoutSession(id: "V", date: Fixed.saturday, name: "Legs", order: [], sets: [
            SetLog(exerciseId: "x", kind: .warmup, weight: 10, reps: 10, done: true),
            SetLog(exerciseId: "x", weight: 20, reps: 10, done: true),
            SetLog(exerciseId: "x", weight: 20, reps: 10, done: false),
        ])
        XCTAssertEqual(s.volume, 200, "only done working sets count")
    }

    /// Phase 2.6 (was RegressionPlannedChangeTests.testCurrentASetKeepsNoSeparateTarget): the suggested target and what
    /// you did are kept apart. A set can carry its target in optional fields: a set without one writes exactly the keys
    /// it always did (older builds read it), and an older set reads with no target.
    func testASetKeepsItsTargetApartFromWhatYouDid() throws {
        let plain = try JSONEncoder().encode(SetLog(id: "X", exerciseId: "leg-extension", weight: 20, reps: 10, done: true))
        let plainKeys = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any]).keys
        XCTAssertEqual(Set(plainKeys), ["id", "exerciseId", "kind", "weight", "reps", "done"])
        let withTarget = SetLog(id: "X", exerciseId: "leg-extension", weight: 20, reps: 11, done: true, targetWeight: 20, targetReps: 10)
        let data = try JSONEncoder().encode(withTarget)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["id", "exerciseId", "kind", "weight", "reps", "done", "targetWeight", "targetReps"])
        let back = try JSONDecoder().decode(SetLog.self, from: data)
        XCTAssertEqual(back.reps, 11, "what you did")
        XCTAssertEqual(back.targetReps, 10, "what was suggested")
        let older = try JSONDecoder().decode(SetLog.self, from: Data(#"{"id":"Y","exerciseId":"x","kind":"working","weight":20,"reps":10,"done":true}"#.utf8))
        XCTAssertNil(older.targetWeight)
        XCTAssertNil(older.targetReps)
    }
}

// MARK: - Sleep plan and promises

final class RegressionPlanTests: RegressionCase {
    private func profile(_ s: inout Saved) {
        s.profile.wakeMinute = 7 * 60 + 15
        s.profile.sleepNeed = 7 * 60 + 45
        s.profile.windDownLead = 30
    }

    @MainActor
    func testSleepPlanFromTheProfileWhenThereIsNoSleepData() throws {
        let store = try makeStore { self.profile(&$0) }
        let p = store.sleepPlan(for: Fixed.saturday)
        XCTAssertEqual(p.debt, 0)
        XCTAssertEqual(p.need, 465)
        XCTAssertEqual(p.perform, 1395, "lights out 23:15: wake 7:15 − 7h 45m − 15 min to fall asleep")
        XCTAssertEqual(p.windDown, 1365)
        XCTAssertEqual(p.getBy, 1455)
    }

    @MainActor
    func testSleepDebtIsCappedAndPaidBackHalfAnHourANight() throws {
        let store = try makeStore { s in
            self.profile(&s)
            for i in 0..<7 {
                let d = Day.add(-i, to: Fixed.saturday)
                s.health[d] = HealthDay(date: d, sleep: SleepRecord(start: "\(d)T00:00:00Z", end: "\(d)T05:45:00Z", asleep: 345))
            }
        }
        let p = store.sleepPlan(for: Fixed.saturday)
        XCTAssertEqual(p.debt, 600, "7 × 120 min short, capped at 10 h")
        XCTAssertEqual(p.need, 495, "465 + 30 to pay back")
        XCTAssertEqual(p.perform, 1365)
    }

    @MainActor
    func testLightsOutEarlierTonightMovesTheEvening() throws {
        let store = try makeStore { s in
            self.profile(&s)
            s.put("bedshift", Fixed.saturday, .number(30))
        }
        let p = store.sleepPlan(for: Fixed.saturday)
        XCTAssertEqual(p.perform, 1365)
        XCTAssertEqual(p.windDown, 1335)
    }

    @MainActor
    func testAnchoredPromisesFollowTheDay() throws {
        let read = PromiseItem(id: "read", title: "Read 30 min", schedule: Schedule(rule: .daily, minute: 0, anchor: "windDown", offset: 5))
        let brush = PromiseItem(id: "brush", title: "Brush teeth, morning", schedule: Schedule(rule: .daily, minute: 0, anchor: "wake", offset: 10))
        let pill = PromiseItem(id: "pill", title: "Creatine", schedule: Schedule(rule: .daily, minute: 9 * 60))
        let store = try makeStore { s in
            self.profile(&s)
            for p in [read, brush, pill] { s.promises[p.id] = p }
        }
        XCTAssertEqual(store.time(of: read, on: Fixed.saturday), 1370, "wind-down 22:45 + 5")
        XCTAssertEqual(store.time(of: brush, on: Fixed.saturday), 445, "wake 7:15 + 10")
        XCTAssertEqual(store.time(of: pill, on: Fixed.saturday), 540)
    }

    @MainActor
    func testWeekCountsTinyAsDoneAndSkippedAsNot() throws {
        let p = PromiseItem(id: "P1", title: "Creatine", kind: .mustDo, schedule: Schedule(rule: .daily, start: "2026-11-01", minute: 470))
        let store = try makeStore { s in
            s.promises[p.id] = p
            for (d, st) in [(Fixed.monday, LogStatus.done), (Fixed.tuesday, .skipped), (Fixed.wednesday, .tiny)] {
                let log = PromiseLog(promiseId: p.id, date: d, status: st)
                s.logs[log.id] = log
            }
        }
        let w = store.week(p, upTo: Fixed.wednesday)
        XCTAssertEqual(w.done, 2)
        XCTAssertEqual(w.due, 3)
        XCTAssertEqual(w.total, 7)
    }

    @MainActor
    func testOpenMustDosAreUnansweredMustDosOnly() throws {
        let must = PromiseItem(id: "M", title: "Creatine", kind: .mustDo, schedule: Schedule(rule: .daily, start: "2026-11-01", minute: 470))
        let routine = PromiseItem(id: "R", title: "Stretch", kind: .routine, schedule: Schedule(rule: .daily, start: "2026-11-01", minute: 600))
        let store = try makeStore { s in
            s.promises[must.id] = must
            s.promises[routine.id] = routine
            let log = PromiseLog(promiseId: "M", date: Fixed.monday, status: .done)
            s.logs[log.id] = log
        }
        XCTAssertEqual(store.openMustDos(on: Fixed.monday).map(\.id), [], "answered")
        XCTAssertEqual(store.openMustDos(on: Fixed.tuesday).map(\.id), ["M"], "routines never count as open must-dos")
    }

    /// No data is not zero: without a health day there is no readiness at all
    @MainActor
    func testNoHealthDataMeansNoReadinessRatherThanZero() throws {
        let store = try makeStore()
        XCTAssertNil(store.readiness(on: Fixed.saturday))
    }
}

// MARK: - Shopping, medicines and grooming

final class RegressionCareAndShoppingTests: RegressionCase {
    /// Phase 2.2 (moved from RegressionPlannedChangeTests): a bought mark has an id and a value the server takes
    /// (it skips ids outside [A-Za-z0-9_.:-]{1,80} and values that aren't objects), so it doesn't stay queued forever.
    /// The line still leaves the list once bought, and a mark saved the old way ("<week>|<line>") still counts.
    @MainActor
    func testBuyingAComputedLineSavesAnIdTheServerTakes() throws {
        let store = try makeStore { s in
            s.add(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30))
            s.add(PantryItem(id: "PM", name: "Maçã Gala", qty: 1, usePerDay: 1))
        }
        let week: String = store.week // the Monday of this week (Store also has a week(_:upTo:) method)
        let server = try NSRegularExpression(pattern: "^[A-Za-z0-9_.:-]{1,80}$")
        func takes(_ id: String) -> Bool { server.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil }
        let lines = store.shoppingList()
        XCTAssertEqual(lines.count, 2)
        for line in lines { store.tick(line) }
        let marks = store.records("bought")
        XCTAssertEqual(marks.count, 2)
        XCTAssertNotNil(marks["\(week)_whey"], "a line already in the server's characters keeps its plain id, which older builds also read")
        XCTAssertTrue(marks.keys.contains { $0.hasPrefix("\(week)_maca-gala_") }, "accents dropped, anything else becomes -, then a hash: \(marks.keys)")
        for (id, value) in marks {
            XCTAssertTrue(takes(id), "\(id) is an id the server skips")
            guard case .object = value else { return XCTFail("\(id): the server skips values that aren't objects") }
        }
        XCTAssertTrue(store.shoppingList().isEmpty, "once bought, the lines go")
        XCTAssertEqual(Store.boughtKey(week: "2026-11-02", line: String(repeating: "x", count: 100)).count, 80, "never longer than the server takes")
    }

    /// Two lines that clean to the same text, or share their first 70 characters, never share a bought mark: buying one
    /// must not take the other off the list
    func testBoughtMarksNeverCollide() throws {
        let week = "2026-11-02"
        let long = String(repeating: "arroz basmati ", count: 8)
        let pairs = [("café", "cafe"), ("pão de forma", "pão-de-forma"), ("maçã", "maca"), (long + "a", long + "b")]
        let server = try NSRegularExpression(pattern: "^[A-Za-z0-9_.:-]{1,80}$")
        for (a, b) in pairs {
            let ka = Store.boughtKey(week: week, line: a), kb = Store.boughtKey(week: week, line: b)
            XCTAssertNotEqual(ka, kb, "\(a) and \(b)")
            for k in [ka, kb] { XCTAssertNotNil(server.firstMatch(in: k, range: NSRange(k.startIndex..., in: k)), k) }
            XCTAssertEqual(ka, Store.boughtKey(week: week, line: a), "the same line always gives the same mark")
        }
        XCTAssertEqual(Store.boughtKey(week: week, line: "med-M1"), "2026-11-02_med-M1", "ids already safe stay as they are")
    }

    /// A bought mark saved before phase 2.2 ("<week>|<line>" with a bare true) still takes the line off the list
    @MainActor
    func testAnOldBoughtMarkStillCounts() throws {
        let probe = try makeStore { _ in }
        let week: String = probe.week
        let store = try makeStore { s in
            s.add(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30))
            s.put("bought", "\(week)|whey", .bool(true))
        }
        XCTAssertTrue(store.shoppingList().isEmpty)
    }

    @MainActor
    func testShoppingListFromPantryMedicinesAndYourOwnItems() throws {
        let store = try makeStore { s in
            s.add(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30))
            s.add(PantryItem(id: "PR", name: "Rice", qty: 200, lowAt: 500))
            s.add(PantryItem(id: "PO", name: "Olive oil", qty: 1000, usePerDay: 10))
            s.add(Medicine(id: "M1", name: "Vitamin D", times: [540], stock: 6, perDose: 1, refillAt: 7))
            s.add(ShoppingItem(id: "S1", name: "Eggs", qty: 12, aisle: "Dairy"))
            s.add(ShoppingItem(id: "S2", name: "Milk", aisle: "Dairy", bought: true))
        }
        let list = store.shoppingList()
        XCTAssertEqual(list.map(\.id), ["s-S1", "med-M1", "rice", "whey"], "by aisle, then name; bought items and well-stocked ones are out")
        XCTAssertEqual(list.map(\.reason), ["added by you", "restam 6 doses", "a acabar", "acaba em 10 dias"])
        XCTAssertEqual(list.first?.qty, 12)
    }

    /// Phases 2.5 and 2.10 (moved from RegressionPlannedChangeTests, where it pinned two "Whey" lines): one line per
    /// product, wherever the need comes from, and its reason names both sources
    @MainActor
    func testTheSameProductFromThePantryAndByHandIsOneLine() throws {
        let store = try makeStore { s in
            s.add(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30))
            s.add(ShoppingItem(id: "S1", name: "Whey"))
        }
        let list = store.shoppingList()
        XCTAssertEqual(list.map(\.name), ["Whey"], "one line per product")
        let reason = try XCTUnwrap(list.first?.reason)
        XCTAssertTrue(reason.contains("acaba em 10 dias"), "the pantry's reason: \(reason)")
        XCTAssertTrue(reason.contains("adicionado por ti"), "and yours: \(reason)")
    }

    @MainActor
    func testDosesLeftAndWhenTheyRunOut() throws {
        let store = try makeStore()
        let m = Medicine(id: "M2", name: "Omega 3", times: [540, 1260], stock: 10, perDose: 2)
        let left = try XCTUnwrap(store.dosesLeft(m))
        XCTAssertEqual(left.doses, 5)
        XCTAssertEqual(Day.between(Day.today, left.runsOut), 2, "5 doses at 2 a day")
        XCTAssertNil(store.dosesLeft(Medicine(id: "M3", name: "No stock")))
    }

    func testGroomingLearnsYourOwnIntervalAfterThreeTimes() {
        var beard = GroomingItem(id: "G1", title: "Trim beard", interval: 7, history: ["2026-10-01", "2026-10-08"])
        XCTAssertNil(beard.learned)
        XCTAssertEqual(beard.rhythm, 7, "the starting interval until there are three")
        beard.history.append("2026-10-16")
        XCTAssertEqual(beard.learned, 8, "gaps of 7 and 8 days")
        // Phase 2.5 (design v17, decision 63): the learned interval is offered as a suggestion and the frequency only
        // changes if you accept it, so the rhythm stays the interval set (it was 8, applied by itself)
        XCTAssertEqual(beard.rhythm, 7)
    }

    /// brushHeadDue only looks at today, so the dates are built relative to today: the result is the same any day
    @MainActor
    func testBrushHeadIsDueNinetyDaysAfterTheLastChange() throws {
        let never = try makeStore()
        XCTAssertFalse(never.brushHeadDue)
        let old = try makeStore { $0.put("brushhead", Day.add(-95, to: Day.today), .number(1)) }
        XCTAssertTrue(old.brushHeadDue)
        let recent = try makeStore { $0.put("brushhead", Day.add(-10, to: Day.today), .number(1)) }
        XCTAssertFalse(recent.brushHeadDue)
    }
}

// MARK: - Wardrobe

final class RegressionWardrobeTests: RegressionCase {
    @MainActor
    func testChoosingAnOutfitCountsNoWear() throws {
        let store = try makeStore { s in
            s.add(Garment(id: "T1", name: "Grey T-shirt", type: "top"))
            s.add(Garment(id: "B1", name: "Jeans", type: "bottom"))
        }
        let picked = store.outfit(for: Fixed.saturday)
        XCTAssertTrue(picked.map(\.id).contains("T1"))
        XCTAssertNil(store.record(OutfitLog.self, Fixed.saturday), "a suggestion saves nothing")
        XCTAssertEqual(store.all(Garment.self).map(\.wears), [0, 0])
    }

    @MainActor
    func testWearingCountsEachPieceOnceAndLogsTheOutfit() throws {
        let store = try makeStore { $0.add(Garment(id: "T1", name: "Grey T-shirt", type: "top", wearsBeforeWash: 3)) }
        let t = try XCTUnwrap(store.record(Garment.self, "T1"))
        store.wear([t], on: Fixed.saturday)
        let after = try XCTUnwrap(store.record(Garment.self, "T1"))
        XCTAssertEqual(after.wears, 1)
        XCTAssertEqual(after.totalWears, 1)
        XCTAssertEqual(after.lastWorn, Fixed.saturday)
        XCTAssertEqual(after.state, "worn")
        let log = try XCTUnwrap(store.record(OutfitLog.self, Fixed.saturday))
        XCTAssertTrue(log.worn)
        XCTAssertEqual(log.items, ["T1"])
    }

    /// Changed in phase 2.10 by the design v17 (decision 96: «Sugerida para lavar», and states change explicitly): at
    /// its limit the piece is suggested for washing, no longer moved there by itself; it still isn't offered in outfits
    @MainActor
    func testReachingTheWashLimitSuggestsWashing() throws {
        let store = try makeStore { $0.add(Garment(id: "T2", name: "Training T-shirt", type: "gym", wearsBeforeWash: 2, wears: 1, state: "worn")) }
        let shirt = try XCTUnwrap(store.record(Garment.self, "T2"))
        store.wear([shirt], on: Fixed.saturday)
        let after = try XCTUnwrap(store.record(Garment.self, "T2"))
        XCTAssertEqual(after.state, "worn")
        XCTAssertEqual(after.wears, 2)
        XCTAssertEqual(after.stage, .suggested)
        XCTAssertFalse(store.outfit(for: Fixed.sunday).map(\.id).contains("T2"), "at its limit, never offered")
    }

    @MainActor
    func testLaundryLoadsGroupByWashGroup() throws {
        let store = try makeStore { s in
            s.add(Garment(id: "D1", name: "Black jeans", type: "bottom", washGroup: "darks 30°", state: "wash"))
            s.add(Garment(id: "D2", name: "Navy hoodie", type: "layer", washGroup: "darks 30°", state: "wash"))
            s.add(Garment(id: "W1", name: "White shirt", type: "top", washGroup: "whites 40°", state: "wash"))
            s.add(Garment(id: "C1", name: "Clean shirt", type: "top", washGroup: "whites 40°", state: "clean"))
        }
        let loads = store.laundryLoads()
        XCTAssertEqual(loads.map(\.group), ["darks 30°", "whites 40°"], "fullest first")
        XCTAssertEqual(Set(loads[0].items.map(\.id)), ["D1", "D2"])
        XCTAssertEqual(Set(loads[1].items.map(\.id)), ["W1"])
        XCTAssertFalse(loads[0].full, "a machine takes 11")
    }

    @MainActor
    func testGymBagIsNeededOnTrainingDaysWithCleanKitOnly() throws {
        let store = try makeStore { s in
            s.add(WorkoutTemplate(id: "TPL", name: "Saturday · legs", exercises: [], weekdays: [7]))
            s.add(Garment(id: "K1", name: "Shorts", type: "gym"))
            s.add(Garment(id: "K2", name: "Training T-shirt", type: "gym", wears: 1, state: "worn"))
        }
        let saturday = store.gymBag(on: Fixed.saturday)
        XCTAssertTrue(saturday.needed)
        XCTAssertEqual(saturday.clean.map(\.id), ["K1"])
        XCTAssertFalse(store.gymBag(on: Fixed.friday).needed)
    }

    /// Phase 2.10 (moved from RegressionPlannedChangeTests, where it pinned the reset at washing): the wear count goes
    /// back to zero only when you confirm «Arrumada» (put away); the history of uses stays
    @MainActor
    func testWashingKeepsTheWearCountUntilPutAway() throws {
        let store = try makeStore { $0.add(Garment(id: "J1", name: "Jeans", type: "bottom", washGroup: "darks 30°", wears: 3, state: "wash", totalWears: 9)) }
        store.washed("darks 30°")
        let drying = try XCTUnwrap(store.record(Garment.self, "J1"))
        XCTAssertEqual(drying.state, "drying")
        XCTAssertEqual(drying.wears, 3, "washing alone doesn't reset the count")
        store.putAway()
        let away = try XCTUnwrap(store.record(Garment.self, "J1"))
        XCTAssertEqual(away.state, "clean")
        XCTAssertEqual(away.wears, 0, "«Arrumada» puts the count back to zero")
        XCTAssertEqual(away.totalWears, 9, "the history of uses stays")
    }

    /// Phase 2.10 (moved from RegressionPlannedChangeTests, where only clean pieces were offered): a piece worn below
    /// its wash limit can be suggested again; at its limit, for washing, in the machine or drying, never
    @MainActor
    func testAPieceWornBelowItsLimitCanBeSuggestedAgain() throws {
        let worn = try makeStore { s in
            s.add(Garment(id: "T1", name: "Grey T-shirt", type: "top", wearsBeforeWash: 3, wears: 1, state: "worn"))
            s.add(Garment(id: "B1", name: "Jeans", type: "bottom"))
        }
        XCTAssertTrue(worn.outfit(for: Fixed.saturday).map(\.id).contains("T1"), "worn once of three: offered")
        let never: [(wears: Int, state: String, washing: Bool?)] = [(3, "worn", nil), (3, "wash", nil), (3, "wash", true), (0, "drying", nil)]
        for c in never {
            let store = try makeStore { s in
                s.add(Garment(id: "T1", name: "Grey T-shirt", type: "top", wearsBeforeWash: 3, wears: c.wears, state: c.state, washing: c.washing))
                s.add(Garment(id: "B1", name: "Jeans", type: "bottom"))
            }
            XCTAssertFalse(store.outfit(for: Fixed.saturday).map(\.id).contains("T1"), "\(c) is never offered")
        }
    }
}

// MARK: - Journal

final class RegressionJournalTests: RegressionCase {
    /// Saved answers are keyed by these exact texts: renaming or translating one cuts it from its history.
    /// Phase 2.2 separates a stable key from the text shown; these keys must still read afterwards.
    func testTheEightStoredJournalKeysStayTheSame() {
        XCTAssertEqual(journalQuestions, ["Caffeine after 14:00", "Alcohol", "Screens in bed", "Late dinner", "Stressful day",
                                          "Outside in the morning", "Trained", "Hot or noisy room"])
    }

    private func journal(_ s: inout Saved, yes: Int, no: Int) {
        // Day i answers "Alcohol"; the night after it (day i + 1) slept 400 min after a yes, 460 after a no
        for i in 0..<(yes + no) {
            let d = Day.add(i, to: "2026-10-01"), next = Day.add(i + 1, to: "2026-10-01")
            let said = i < yes
            s.add(JournalDay(date: d, yes: said ? ["Alcohol"] : [], answered: ["Alcohol"]))
            s.health[next] = HealthDay(date: next, sleep: SleepRecord(start: "\(next)T00:00:00Z", end: "\(next)T07:00:00Z", asleep: said ? 400 : 460))
        }
    }

    @MainActor
    func testJournalEffectsNeedFiveNightsEachWay() throws {
        let enough = try makeStore { self.journal(&$0, yes: 5, no: 5) }
        let effects = enough.journalEffects()
        XCTAssertEqual(effects.map(\.question), ["Alcohol"])
        XCTAssertEqual(effects.first?.sleep, -60)
        XCTAssertEqual(effects.first?.n, 5)
        let tooFew = try makeStore { self.journal(&$0, yes: 4, no: 4) }
        XCTAssertTrue(tooFew.journalEffects().isEmpty)
    }
}

// MARK: - Ring keys (phase 2.1)

final class RegressionRingKeyTests: RegressionCase {
    /// Each ring is found by its key, never by its name: the key is the ring's id, its accessibility identifier
    /// (ring.<key>, which the UI tests read) and what Today, Body and Fuel look a ring up by. Translating or renaming
    /// a ring changes `name` only, so these keys must stay exactly as they are.
    @MainActor
    func testRingKeysAreStable() throws {
        let store = try makeStore { _ in }
        let rings = store.ringStats()
        XCTAssertEqual(rings.main.map(\.key.rawValue), ["sleep", "recovery", "strain"])
        XCTAssertEqual(rings.day.map(\.key.rawValue), ["calories", "protein", "water", "move", "promises"])
        let all = rings.main + rings.day
        XCTAssertEqual(all.map(\.key), RingKey.allCases, "every key is on Today once, so a lookup by any key finds its ring")
        XCTAssertEqual(all.map(\.id), all.map(\.key.rawValue), "a ring's id is its key")
        XCTAssertEqual(all.map(\.accessibilityID), RingKey.allCases.map { "ring.\($0.rawValue)" }, "the identifiers the UI tests read")
        let renamed = RingStat(key: .sleep, name: "Sono", value: 0, target: 1, pace: nil, area: .sleep, center: "–", goal: "")
        XCTAssertEqual(renamed.id, "sleep", "a new name keeps the key")
        XCTAssertEqual(renamed.accessibilityID, "ring.sleep", "and the identifier")
    }
}

// MARK: - Where an answer came from (phase 2.2)

final class RegressionAnswerSourceTests: RegressionCase {
    private let walk = PromiseItem(id: "W1", title: "10k steps", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 9 * 60))

    /// An answer you give is marked as yours; with no answer there is no origin
    @MainActor
    func testAnAnswerYouGiveIsMarkedAsYours() throws {
        let store = try makeStore { $0.promises[self.walk.id] = self.walk }
        XCTAssertNil(store.answerOrigin(walk))
        store.log(walk, .done)
        XCTAssertEqual(store.status(walk), .done)
        XCTAssertEqual(store.answerOrigin(walk), .you)
    }

    /// The steps goal ticked by the band's data is saved as imported from the health source the profile uses, and
    /// becomes yours again when you answer it yourself
    @MainActor
    func testTheBandTicksTheStepsGoalAsImported() throws {
        for healthSource in ["fitbit", "apple"] {
            let store = try makeStore { s in
                s.promises[self.walk.id] = self.walk
                s.profile.healthSource = healthSource
                s.health[Day.today] = HealthDay(date: Day.today, steps: 20000)
            }
            store.autoComplete()
            XCTAssertEqual(store.status(walk), .done)
            XCTAssertEqual(store.answerOrigin(walk), .imported(healthSource))
            store.log(walk, .done)
            XCTAssertEqual(store.answerOrigin(walk), .you, "answered by you now")
        }
    }

    /// Below the goal nothing is ticked: low data never becomes an answer
    @MainActor
    func testTooFewStepsTickNothing() throws {
        let store = try makeStore { s in
            s.promises[self.walk.id] = self.walk
            s.health[Day.today] = HealthDay(date: Day.today, steps: 100)
        }
        store.autoComplete()
        XCTAssertNil(store.status(walk))
    }

    /// An answer saved before phase 2.2, or one that went through an older build (which drops the field when it saves),
    /// has no source: it still reads, still counts as done, and its origin is unknown, never taken as yours
    @MainActor
    func testOlderLogsWithoutASourceReadAsUnknown() throws {
        let old = #"{"promiseId":"W1","date":"2026-11-02","status":"done","at":1}"#
        let decoded = try JSONDecoder().decode(PromiseLog.self, from: Data(old.utf8))
        XCTAssertNil(decoded.source)
        let store = try makeStore { s in
            s.promises[self.walk.id] = self.walk
            s.logs[decoded.id] = decoded
        }
        XCTAssertEqual(store.status(walk, on: "2026-11-02"), .done)
        XCTAssertEqual(store.answerOrigin(walk, on: "2026-11-02"), .unknown)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["promiseId", "date", "status", "at"], "an unknown origin is saved as it came, with nothing added")
        var imported = decoded
        imported.source = "fitbit"
        XCTAssertEqual(try JSONDecoder().decode(PromiseLog.self, from: JSONEncoder().encode(imported)).source, "fitbit")
    }
}

// MARK: - Journal question texts (phase 2.2)

final class RegressionJournalTextTests: XCTestCase {
    /// Every saved key has a text to show; phase 2.3 translates the texts, never the keys
    func testEveryJournalKeyHasItsText() {
        XCTAssertEqual(Set(journalQuestionText.keys), Set(journalQuestions))
        for key in journalQuestions { XCTAssertFalse(journalText(key).isEmpty, key) }
        XCTAssertEqual(journalText("Unknown question"), "Unknown question", "an unknown key shows as itself")
    }
}

// MARK: - Today (phase 2.4)

final class RegressionTodayTests: RegressionCase {
    /// «Agora» is one step chosen by the D3 rule, not habits only (what "A seguir" looked at before 2.4): a workout in
    /// progress comes before the next habit. The rule itself is tested in NowTests.
    @MainActor
    func testAgoraIsNotHabitsOnly() throws {
        let creatine = PromiseItem(id: "H1", title: "Creatina", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 23 * 60))
        let store = try makeStore { s in
            s.promises[creatine.id] = creatine
            s.add(WorkoutSession(id: "S1", name: "Pernas", start: nowMs() - 600_000, order: []))
        }
        guard case .workout(let w)? = store.nowStep(minute: 8 * 60, events: []) else { return XCTFail("a workout in progress is the step") }
        XCTAssertEqual(w.id, "S1")
    }

    /// A ring with no data is «sem dados» with no number (drawn dashed, Ring(noData:)), never an empty arc read as zero
    @MainActor
    func testARingWithNoDataIsNotZero() throws {
        let rings = try makeStore().ringStats()
        for r in rings.main + rings.day where r.key == .sleep || r.key == .recovery || r.key == .strain || r.key == .move {
            XCTAssertTrue(r.noData, "\(r.key)")
            XCTAssertEqual(r.goal, "sem dados", "\(r.key)")
            XCTAssertFalse(r.center.contains("0"), "\(r.key): no number")
        }
    }
}

// MARK: - Plano · end-of-day review (phase 2.8)

final class RegressionPlanReviewTests: RegressionCase {
    /// Was RegressionPlannedChangeTests.testCurrentAHabitHasOnlyThreeAnswers. The review tells «Feito», «Não fiz», «Não
    /// se aplica» and «não confirmado» apart without a new LogStatus value (an older build protects the whole file when
    /// it meets one): «Não se aplica» is a skip with notApplicable true, so an older build reads it as skipped, and «não
    /// confirmado» is no log at all. The answer is yours (source "you").
    @MainActor
    func testTheReviewTellsFourAnswersApartWithThreeStatuses() throws {
        XCTAssertEqual(["done", "skipped", "tiny"].compactMap(LogStatus.init(rawValue:)), [.done, .skipped, .tiny])
        XCTAssertNil(LogStatus(rawValue: "notConfirmed"))
        XCTAssertNil(LogStatus(rawValue: "notApplicable"))

        let shake = PromiseItem(id: "S1", title: "Batido", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 17 * 60))
        let store = try makeStore { $0.promises[shake.id] = shake }
        XCTAssertEqual(store.reviewAnswer(shake, on: Fixed.saturday), .notConfirmed, "no log is «não confirmado»")
        store.saveReview(shake, on: Fixed.saturday, .notConfirmed)
        XCTAssertNil(store.logs["S1|\(Fixed.saturday)"], "«não confirmado» saves nothing")

        store.saveReview(shake, on: Fixed.saturday, .notApplicable)
        let log = try XCTUnwrap(store.logs["S1|\(Fixed.saturday)"])
        XCTAssertEqual(log.status, .skipped)
        XCTAssertEqual(log.notApplicable, true)
        XCTAssertEqual(log.source, PromiseLog.byYou)
        XCTAssertEqual(store.reviewAnswer(shake, on: Fixed.saturday), .notApplicable)

        // What a build from before 2.8 reads from that log: the same JSON, without knowing the new field
        struct Before28: Decodable { var promiseId: String; var date: String; var status: LogStatus; var at: Double; var source: String? }
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(Before28.self, from: data).status, .skipped)
        // and one saved without the field reads back as nil, a plain skip
        let plain = #"{"promiseId":"S1","date":"2026-11-07","status":"skipped","at":1}"#
        XCTAssertNil(try JSONDecoder().decode(PromiseLog.self, from: Data(plain.utf8)).notApplicable)

        store.saveReview(shake, on: Fixed.saturday, .notDone)
        XCTAssertEqual(store.reviewAnswer(shake, on: Fixed.saturday), .notDone)
        XCTAssertNil(store.logs["S1|\(Fixed.saturday)"]?.notApplicable, "«Não fiz» is a plain skip")
        store.saveReview(shake, on: Fixed.saturday, .done)
        XCTAssertEqual(store.status(shake, on: Fixed.saturday), .done)
        XCTAssertEqual(store.answerOrigin(shake, on: Fixed.saturday), .you)

// MARK: - The night (phase 2.9)

final class RegressionNightTests: RegressionCase {
    /// Phases 2.2 and 2.9 (moved from RegressionPlannedChangeTests, where it pinned only the answer's source): data from
    /// the band can mark the bedtime habit done, but it is kept and shown as «Importado» (StateTag), never as confirmed
    /// by you; «Vou dormir» is a separate intention (its own record, id = the day, an object) that answers no habit and
    /// never says when sleep started.
    /// Built relative to today because autoComplete() only looks at today and yesterday.
    @MainActor
    func testBandSleepTicksTheBedtimeHabitAsImportedAndVouDormirIsOnlyAnIntention() throws {
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
        XCTAssertEqual(store.answerOrigin(lightsOut, on: yesterday), .imported("fitbit"), "kept as imported from the band, not as your answer")
        XCTAssertEqual(NightRules.answerState(store.answerOrigin(lightsOut, on: yesterday)), .imported, "and shown as «Importado», not «Confirmado»")
        XCTAssertEqual(DataState.imported.label, "Importado")
        XCTAssertEqual(store.bedtimeHabits(on: yesterday).map { $0.id }, ["L1"], "the morning's «Como dormiste» lists it with its label")

        store.goingToSleep(minute: 22 * 60 + 33, on: Day.today)
        let intent = try XCTUnwrap(store.record(SleepIntent.self, Day.today), "«Vou dormir» exists, as its own record")
        XCTAssertEqual(intent.id, Day.today)
        XCTAssertEqual(intent.minute, 22 * 60 + 33)
        guard case .object? = store.records(SleepIntent.kind)[Day.today] else { return XCTFail("the intention's value is an object") }
        XCTAssertNil(store.status(lightsOut, on: Day.today), "the intention doesn't answer the bedtime habit")
        XCTAssertEqual(store.health[Day.today]?.sleep?.start, start, "nor change when the band says sleep started")
    }
}
