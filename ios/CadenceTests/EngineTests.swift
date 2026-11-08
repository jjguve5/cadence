// Tests for the pure calculations: they run on a simulator in CI before every build.
import XCTest
@testable import Cadence

final class BaselineTests: XCTestCase {
    func testOneBadNightBarelyMovesTheBaseline() {
        let normal = [60.0, 62, 58, 61, 59, 63, 60, 61, 62, 59]
        let withOutlier = normal + [20]
        let a = RobustBaseline.of(normal)!, b = RobustBaseline.of(withOutlier)!
        XCTAssertEqual(a.median, b.median, accuracy: 1)
        XCTAssertLessThan(abs(b.spread - a.spread), 1.5)
    }

    func testNeedsEnoughDays() {
        XCTAssertNil(RobustBaseline.of([1, 2, 3], minimum: 7))
    }
}

final class ReadinessTests: XCTestCase {
    let hb = RobustBaseline(median: 60, spread: 6, n: 28)
    let rb = RobustBaseline(median: 55, spread: 2, n: 28)

    func testTypicalDayIsMiddling() {
        let r = Engine.readiness(hrv: 60, hrvBase: hb, rhr: 55, rhrBase: rb, sleepMinutes: 465, sleepNeed: 465)!
        XCTAssertTrue((60...80).contains(r.score), "\(r.score)")
        XCTAssertEqual(r.confidence, .high)
    }

    func testMissingSleepLowersConfidenceAndSaysSo() {
        let r = Engine.readiness(hrv: 60, hrvBase: hb, rhr: 55, rhrBase: rb, sleepMinutes: nil, sleepNeed: 465)!
        XCTAssertEqual(r.confidence, .moderate)
        XCTAssertTrue(r.notes.contains { $0.contains("sono") })
    }

    func testYesterdaySoftensASingleNight() {
        let alone = Engine.readiness(hrv: 40, hrvBase: hb, rhr: 55, rhrBase: rb, sleepMinutes: 465, sleepNeed: 465)!
        let blended = Engine.readiness(hrv: 40, hrvBase: hb, rhr: 55, rhrBase: rb, sleepMinutes: 465, sleepNeed: 465, previousHrvZ: 0)!
        XCTAssertGreaterThan(blended.score, alone.score)
    }

    func testNothingMeansNoScore() {
        XCTAssertNil(Engine.readiness(hrv: nil, hrvBase: nil, rhr: nil, rhrBase: nil, sleepMinutes: nil, sleepNeed: 465))
    }
}

final class SleepDebtTests: XCTestCase {
    func testCappedAndConservative() {
        XCTAssertEqual(Engine.sleepDebt(nights: Array(repeating: 0, count: 7), need: 480), 600) // 7 × 2 h capped at 10 h
        XCTAssertEqual(Engine.sleepDebt(nights: [420, 540], need: 480), 0) // one long night repays at most 1 h
        XCTAssertEqual(Engine.sleepDebt(nights: [360, 600], need: 480), 60)
        XCTAssertEqual(Engine.sleepDebt(nights: Array(repeating: 480, count: 20), need: 480), 0)
    }
}

final class RecommendationTests: XCTestCase {
    func context(_ change: (inout DayContext) -> Void = { _ in }) -> DayContext {
        var c = DayContext(minute: 9 * 60, sleepMinutes: 470, sleepNeed: 465, sleepBaseline: RobustBaseline(median: 470, spread: 25, n: 28), sleepDebt: 0,
                           hrv: 60, hrvBaseline: nil, rhr: 55, rhrBaseline: nil, readiness: ReadinessResult(score: 72, confidence: .high, hrvZ: 0, rhrZ: 0, sleepRatio: 1, notes: []),
                           illnessSigns: [], lastSyncHours: 1, trainingToday: nil, deepWorkPlanned: false, meetingsMinutes: 0, deadline: nil, openMustDos: [],
                           proteinGap: nil, airBattery: 80, recentEnergy: [], suppressedKinds: [], minimumDay: false, readinessUseful: nil)
        change(&c)
        return c
    }

    func testAnOrdinaryGoodDayStaysQuiet() {
        XCTAssertTrue(Engine.recommendations(context()).isEmpty)
    }

    func testShortSleepAndADeadlineProtectFocusAndKeepTheWorkout() {
        let recs = Engine.recommendations(context { $0.sleepMinutes = 330; $0.deepWorkPlanned = true; $0.trainingToday = "Friday" })
        let focus = recs.first { $0.kind == "focus" }
        XCTAssertNotNil(focus)
        XCTAssertTrue(focus!.why.contains("Mantém Friday"))
    }

    func testLowReadinessNeverCutsTheSessionByItself() {
        let recs = Engine.recommendations(context { $0.trainingToday = "Monday"; $0.readiness = ReadinessResult(score: 40, confidence: .high, hrvZ: -1.5, rhrZ: 1.2, sleepRatio: 1, notes: []) })
        let r = recs.first { $0.kind == "trainfeel" }!
        XCTAssertEqual(r.action, .trainByFeel)
        XCTAssertTrue(r.why.contains("continua no plano"))
    }

    func testLateMustDoComesFirst() {
        let recs = Engine.recommendations(context { $0.openMustDos = [("Creatine", true)]; $0.sleepDebt = 400 })
        XCTAssertEqual(recs.first?.kind, "mustdo")
    }

    func testAtMostThree() {
        let recs = Engine.recommendations(context {
            $0.openMustDos = [("Creatine", true)]; $0.sleepDebt = 400; $0.sleepMinutes = 300; $0.deepWorkPlanned = true
            $0.trainingToday = "Legs"; $0.illnessSigns = ["a", "b"]; $0.airBattery = 5
        })
        XCTAssertEqual(recs.count, 3)
    }

    func testStaleDataLowersConfidence() {
        let fresh = Engine.recommendations(context { $0.sleepDebt = 400 }).first { $0.kind == "bedtime" }!
        let stale = Engine.recommendations(context { $0.sleepDebt = 400; $0.lastSyncHours = 20 }).first { $0.kind == "bedtime" }!
        XCTAssertLessThan(stale.confidence, fresh.confidence)
    }

    func testDismissedKindsGoQuietButMustDosNeverDo() {
        let recs = Engine.recommendations(context { $0.sleepDebt = 400; $0.openMustDos = [("Creatine", true)]; $0.suppressedKinds = ["bedtime", "mustdo"] })
        XCTAssertNil(recs.first { $0.kind == "bedtime" })
        XCTAssertNotNil(recs.first { $0.kind == "mustdo" })
    }

    func testMinimumDayIsOfferedNotImposed() {
        let c = context { $0.illnessSigns = ["Resting HR up", "HRV down"] }
        XCTAssertNotNil(Engine.recommendations(c).first { $0.kind == "minimumday" })
        XCTAssertNil(Engine.recommendations(context { $0.illnessSigns = ["Resting HR up", "HRV down"]; $0.minimumDay = true }).first { $0.kind == "minimumday" })
    }
}

final class CalibrationTests: XCTestCase {
    func testTooFewPairsSaysSo() {
        let c = Engine.calibrate([(1, 2), (2, 3)])
        XCTAssertNil(c.spearman)
        XCTAssertTrue(c.verdict.contains("de 10"))
    }

    func testAGoodPredictorIsRecognised() {
        let pairs = (1...20).map { (predicted: Double($0 % 5 + 1), observed: Double($0 % 5 + 1)) }
        let c = Engine.calibrate(pairs)
        XCTAssertGreaterThan(c.spearman ?? 0, 0.9)
        XCTAssertTrue(c.verdict.hasPrefix("Útil"))
    }

    func testNoiseIsNotUseful() {
        let observed: [Double] = [3, 1, 4, 1, 5, 2, 2, 3, 5, 4, 1, 3]
        let predicted: [Double] = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3.1]
        XCTAssertFalse(Engine.calibrate(Array(zip(predicted, observed)).map { (predicted: $0.0, observed: $0.1) }).verdict.hasPrefix("Útil"))
    }

    func testSpearmanHandlesTies() {
        XCTAssertEqual(Engine.spearman([1, 2, 2, 3], [1, 2, 2, 3]) ?? 0, 1, accuracy: 0.0001)
    }
}

final class ExperimentTests: XCTestCase {
    func testClearChangeAndHonestWording() {
        let r = Engine.experiment(before: [400, 410, 395, 405, 400, 398, 402], during: [440, 450, 445, 438, 442, 447, 450])!
        XCTAssertGreaterThan(r.effectSize, 0.8)
        XCTAssertTrue(r.summary.contains("não uma prova"))
    }

    func testNeedsEnoughDays() {
        XCTAssertNil(Engine.experiment(before: [1, 2], during: [3, 4]))
    }
}

final class QuickCaptureTests: XCTestCase {
    let today = "2026-11-02" // a Monday

    func testFood() {
        guard case .food(let foods, _) = QuickCapture.parse("Ate Greek yogurt and a banana", today: today) else { return XCTFail() }
        XCTAssertEqual(Set(foods.map(\.name)), ["Iogurte grego", "Banana"])
    }

    func testSpending() {
        guard case .spend(let a, let c, _) = QuickCapture.parse("Spent 12 euros on groceries", today: today) else { return XCTFail() }
        XCTAssertEqual(a, 12)
        XCTAssertEqual(c, "Groceries")
    }

    func testReminderWithDayAndTime() {
        guard case .reminder(let t, let d, let m) = QuickCapture.parse("Remind me to wash my clothes tomorrow at 18:00", today: today) else { return XCTFail() }
        XCTAssertEqual(t, "Wash my clothes")
        XCTAssertEqual(d, "2026-11-03")
        XCTAssertEqual(m, 18 * 60)
    }

    func testMove() {
        guard case .move(let k, let d) = QuickCapture.parse("Move studying to tomorrow", today: today) else { return XCTFail() }
        XCTAssertEqual(k, "studying")
        XCTAssertEqual(d, "2026-11-03")
    }

    func testFeeling() {
        guard case .feeling(let w, let e, _) = QuickCapture.parse("Felt exhausted after lunch", today: today) else { return XCTFail() }
        XCTAssertEqual(w, "Drained")
        XCTAssertLessThan(e, 0)
    }

    func testAnythingElseBecomesATask() {
        XCTAssertEqual(QuickCapture.parse("Call the bank", today: today), .task("Call the bank"))
    }
}

final class ScheduleTests: XCTestCase {
    func testEveryNDays() {
        let s = Schedule(rule: .everyNDays, every: 2, start: "2026-11-01")
        XCTAssertTrue(s.isDue(on: "2026-11-01"))
        XCTAssertFalse(s.isDue(on: "2026-11-02"))
        XCTAssertTrue(s.isDue(on: "2026-11-03"))
        XCTAssertFalse(s.isDue(on: "2026-10-30"))
    }

    func testWeekdays() {
        let s = Schedule(rule: .weekdays, weekdays: [2, 3, 4, 5, 6])
        XCTAssertTrue(s.isDue(on: "2026-11-02")) // Monday
        XCTAssertFalse(s.isDue(on: "2026-11-01")) // Sunday
    }
}

final class SetupTests: XCTestCase {
    func testLoseFatPlan() {
        var i = SetupInputs()
        i.male = true; i.age = 25; i.height = 178; i.weight = 76; i.job = "desk"; i.trainingDays = 4; i.goal = "lose"; i.pace = "steady"
        let p = SetupPlanner.plan(i, airBurn: nil, averageSteps: 7000)
        // Mifflin-St Jeor: 10·76 + 6.25·178 − 5·25 + 5 = 1752.5
        XCTAssertLessThan(p.kcal, 1752.5 * 1.25 + 300)
        XCTAssertEqual(p.protein, (76 * 2.2).rounded())
        XCTAssertGreaterThanOrEqual(p.fat, 76 * 0.8 - 1)
        XCTAssertEqual(p.steps, 8000)
    }

    func testAirBurnLeadsTheEstimate() {
        var i = SetupInputs()
        i.goal = "maintain"
        let p = SetupPlanner.plan(i, airBurn: 3000, averageSteps: nil)
        XCTAssertGreaterThan(p.kcal, 2800)
    }
}
