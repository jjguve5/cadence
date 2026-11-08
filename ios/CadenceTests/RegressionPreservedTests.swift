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
        XCTAssertEqual(s.reason, "First time: pick a weight you could do for 14")
    }

    @MainActor
    func testEverySetAtTheTopOfTheRangeAddsTheIncrement() throws {
        let store = try makeStore { $0.add(self.finished("S1", start: 1_000, [(18, 12), (18, 12), (18, 12)])) }
        let s = store.suggestion(for: legExtension)
        XCTAssertEqual(s.weight, 20.5)
        XCTAssertEqual(s.sets, 3, "low or missing readiness never removes a set (docs/AUDIT.md, problem 2)")
        XCTAssertEqual(s.reason, "+2.5 kg: you hit 3 × 12 at 18 last time")
    }

    @MainActor
    func testMissingTheTopKeepsTheWeight() throws {
        let store = try makeStore { $0.add(self.finished("S1", start: 1_000, [(18, 12), (18, 11), (18, 10)])) }
        let s = store.suggestion(for: legExtension)
        XCTAssertEqual(s.weight, 18)
        XCTAssertEqual(s.reason, "Same weight: aim for 12 on every set")
    }

    @MainActor
    func testFourFlatSessionsDeloadTenPercent() throws {
        let store = try makeStore { s in
            for i in 0..<4 { s.add(self.finished("S\(i)", start: Double(1_000 + i * 10_000_000), [(20, 10), (20, 10), (20, 10)])) }
        }
        let s = store.suggestion(for: legExtension)
        XCTAssertEqual(s.weight, 17.5, "20 kg × 0.9, rounded to 2.5 kg")
        XCTAssertEqual(s.reason, "Stalled for 3 sessions: a 10% deload, then build back")
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

    /// The percentages stay; which exercises get warm-ups (today: every one above bar + 10 kg) changes in phase 2.6
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
        XCTAssertEqual(list.map(\.reason), ["added by you", "6 doses left", "running low", "10 days left"])
        XCTAssertEqual(list.first?.qty, 12)
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
        XCTAssertEqual(beard.rhythm, 8)
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

    @MainActor
    func testReachingTheWashLimitMovesThePieceToWash() throws {
        let store = try makeStore { $0.add(Garment(id: "T2", name: "Training T-shirt", type: "gym", wearsBeforeWash: 2, wears: 1, state: "worn")) }
        let shirt = try XCTUnwrap(store.record(Garment.self, "T2"))
        store.wear([shirt], on: Fixed.saturday)
        XCTAssertEqual(store.record(Garment.self, "T2")?.state, "wash")
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
