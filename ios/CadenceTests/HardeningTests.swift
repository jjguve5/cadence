// Risk-based tests from the hardening pass: clock changes, missing and stale data, conflicting advice, dismissals
// that mustn't silence what matters, notification budgets, minimum-day scoring, capture parsing and old saved data.
import XCTest
@testable import Cadence

final class DateBoundaryTests: XCTestCase {
    let lisbon: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return c
    }()

    private func hourMinute(_ d: Date) -> [Int] { let c = lisbon.dateComponents([.hour, .minute], from: d); return [c.hour!, c.minute!] }

    func testEightStaysEightWhenClocksGoForward() {
        // 29 March 2026: 01:00 jumps to 02:00 in Lisbon
        XCTAssertEqual(hourMinute(Day.at(8 * 60, on: "2026-03-29", in: lisbon)), [8, 0])
        XCTAssertEqual(hourMinute(Day.at(22 * 60 + 30, on: "2026-03-29", in: lisbon)), [22, 30])
    }

    func testEightStaysEightWhenClocksGoBack() {
        // 25 October 2026: 02:00 goes back to 01:00
        XCTAssertEqual(hourMinute(Day.at(8 * 60, on: "2026-10-25", in: lisbon)), [8, 0])
        XCTAssertEqual(hourMinute(Day.at(23 * 60, on: "2026-10-25", in: lisbon)), [23, 0])
    }

    func testMinutesPastMidnightAndBeforeIt() {
        let next = Day.at(1440 + 60, on: "2026-10-24", in: lisbon)
        XCTAssertEqual(lisbon.component(.day, from: next), 25)
        XCTAssertEqual(hourMinute(next), [1, 0])
        let before = Day.at(-12 * 60, on: "2026-03-29", in: lisbon)
        XCTAssertEqual(lisbon.component(.day, from: before), 28)
        XCTAssertEqual(hourMinute(before), [12, 0])
    }

    func testDayArithmeticAcrossChangesAndMonths() {
        XCTAssertEqual(Day.add(1, to: "2026-03-28"), "2026-03-29")
        XCTAssertEqual(Day.add(1, to: "2026-03-29"), "2026-03-30")
        XCTAssertEqual(Day.add(1, to: "2026-10-25"), "2026-10-26")
        XCTAssertEqual(Day.add(1, to: "2026-12-31"), "2027-01-01")
        XCTAssertEqual(Day.between("2026-03-28", "2026-03-30"), 2)
        XCTAssertEqual(Day.between("2026-10-24", "2026-10-26"), 2)
    }

    func testOneOffReminderIsDueOnlyItsDay() {
        // Quick-capture reminders are an every-9999-days schedule starting that day
        let s = Schedule(rule: .everyNDays, every: 9999, start: "2026-11-02", minute: 18 * 60)
        XCTAssertTrue(s.isDue(on: "2026-11-02"))
        XCTAssertFalse(s.isDue(on: "2026-11-01"))
        XCTAssertFalse(s.isDue(on: "2026-11-03"))
        XCTAssertFalse(s.isDue(on: "2027-11-02"))
    }
}

final class FreshnessAndConflictTests: XCTestCase {
    func context(_ change: (inout DayContext) -> Void = { _ in }) -> DayContext {
        var c = DayContext(minute: 9 * 60, sleepMinutes: 470, sleepNeed: 465, sleepBaseline: RobustBaseline(median: 470, spread: 25, n: 28), sleepDebt: 0,
                           hrv: 60, hrvBaseline: nil, rhr: 55, rhrBaseline: nil, readiness: ReadinessResult(score: 72, confidence: .high, hrvZ: 0, rhrZ: 0, sleepRatio: 1, notes: []),
                           illnessSigns: [], lastSyncHours: 1, trainingToday: nil, deepWorkPlanned: false, meetingsMinutes: 0, deadline: nil, openMustDos: [],
                           proteinGap: nil, airBattery: 80, recentEnergy: [], suppressedKinds: [], minimumDay: false, readinessUseful: nil)
        change(&c)
        return c
    }

    func testNoSyncForOneThreeAndSevenDaysSaysSoAtAnyHour() {
        for (hours, words) in [(26.0, "1 day"), (74, "3 days"), (170, "7 days")] {
            for minute in [8 * 60, 15 * 60, 21 * 60] {
                let recs = Engine.recommendations(context { $0.lastSyncHours = hours; $0.minute = minute; $0.sleepMinutes = nil })
                let sync = recs.first { $0.kind == "sync" }
                XCTAssertNotNil(sync, "\(hours) h at \(minute)")
                XCTAssertTrue(sync?.title.contains(words) == true, sync?.title ?? "")
            }
        }
    }

    func testFreshDataAsksNothing() {
        XCTAssertFalse(Engine.recommendations(context()).contains { $0.kind == "sync" })
    }

    func testDismissingCantSilenceALongMissingSync() {
        let recs = Engine.recommendations(context { $0.lastSyncHours = 74; $0.suppressedKinds = ["sync"] })
        XCTAssertTrue(recs.contains { $0.kind == "sync" })
    }

    func testDismissingCanQuietAShortStaleness() {
        let recs = Engine.recommendations(context { $0.lastSyncHours = 10; $0.sleepMinutes = nil; $0.suppressedKinds = ["sync"] })
        XCTAssertFalse(recs.contains { $0.kind == "sync" })
    }

    func testIllnessSignalsKeepTheLightDayOfferEvenIfDismissedBefore() {
        let recs = Engine.recommendations(context { $0.illnessSigns = ["resting HR up", "temperature up"]; $0.suppressedKinds = ["minimumday"] })
        XCTAssertTrue(recs.contains { $0.kind == "minimumday" })
    }

    func testOtherwiseADismissedLightDayStaysQuiet() {
        let recs = Engine.recommendations(context { $0.sleepMinutes = 300; $0.suppressedKinds = ["minimumday"] })
        XCTAssertFalse(recs.contains { $0.kind == "minimumday" })
    }

    func testMinimumDayDropsPushHarderAdvice() {
        let busy: (inout DayContext) -> Void = {
            $0.sleepMinutes = 340; $0.deepWorkPlanned = true; $0.trainingToday = "Legs"
            $0.readiness = ReadinessResult(score: 40, confidence: .high, hrvZ: -1.5, rhrZ: 1.2, sleepRatio: 0.7, notes: [])
            $0.deadline = (title: "Thesis", daysLeft: 3, behind: true)
        }
        let normal = Engine.recommendations(context(busy))
        XCTAssertTrue(normal.contains { ["focus", "trainfeel"].contains($0.kind) }, "baseline: these appear on a normal day")
        let light = Engine.recommendations(context { busy(&$0); $0.minimumDay = true })
        XCTAssertFalse(light.contains { ["focus", "deadline", "trainfeel"].contains($0.kind) }, light.map(\.kind).joined(separator: ","))
    }

    func testOfferingALightDayDropsDeadlinePressure() {
        let recs = Engine.recommendations(context { $0.sleepMinutes = 300; $0.deadline = (title: "Thesis", daysLeft: 3, behind: true) })
        XCTAssertTrue(recs.contains { $0.kind == "minimumday" })
        XCTAssertFalse(recs.contains { $0.kind == "deadline" })
    }

    func testNoDuplicateKinds() {
        let recs = Engine.recommendations(context { $0.sleepMinutes = 300; $0.lastSyncHours = 30; $0.sleepDebt = 400; $0.minute = 20 * 60; $0.proteinGap = 50 })
        let kinds = recs.map(\.kind)
        XCTAssertEqual(kinds.count, Set(kinds).count, kinds.joined(separator: ","))
        XCTAssertLessThanOrEqual(recs.count, 3)
    }

    func testSleepDebtIsLabelledAnEstimate() {
        let recs = Engine.recommendations(context { $0.sleepDebt = 240; $0.minute = 20 * 60 })
        let bed = recs.first { $0.kind == "bedtime" }
        XCTAssertNotNil(bed)
        XCTAssertTrue(bed!.evidence.joined().contains("estimate"))
    }
}

final class TrendTests: XCTestCase {
    let base = RobustBaseline(median: 60, spread: 5, n: 28)

    func testAWeekLongSlideIsNoticed() {
        XCTAssertTrue(Engine.sustainedDecline(week: [52, 53, 54, 51, 55, 53, 52], baseline: base))
    }

    func testOneBadNightIsNot() {
        XCTAssertFalse(Engine.sustainedDecline(week: [40, 60, 61, 59, 62, 60, 58], baseline: base))
    }

    func testTooFewDaysSaysNothing() {
        XCTAssertFalse(Engine.sustainedDecline(week: [40, 41, 42], baseline: base))
    }

    func testBaselineIgnoresTheValueBeingJudged() {
        // A baseline built only from earlier days doesn't move when today is extreme
        let earlier: [Double] = Array(repeating: 60, count: 20)
        XCTAssertEqual(RobustBaseline.of(earlier)!.median, 60)
    }
}

final class MinimumScoreTests: XCTestCase {
    func testEssentialsDoneIsAFullDay() {
        XCTAssertEqual(Engine.minimumScore(essentials: 3, essentialsDone: 3, sleep: 465, sleepNeed: 465, water: 1800, waterGoal: 2500), 100)
    }

    func testMissingSleepDataDoesntCountAgainstYou() {
        XCTAssertEqual(Engine.minimumScore(essentials: 0, essentialsDone: 0, sleep: nil, sleepNeed: 465, water: 2500, waterGoal: 2500), 100)
    }

    func testHalfTheEssentials() {
        XCTAssertEqual(Engine.minimumScore(essentials: 2, essentialsDone: 1, sleep: 465, sleepNeed: 465, water: 2500, waterGoal: 2500), 75)
    }

    func testNeverAboveAHundredOrBelowZero() {
        let high = Engine.minimumScore(essentials: 1, essentialsDone: 5, sleep: 900, sleepNeed: 465, water: 9000, waterGoal: 2500)
        let low = Engine.minimumScore(essentials: 4, essentialsDone: 0, sleep: 0, sleepNeed: 465, water: 0, waterGoal: 2500)
        XCTAssertEqual(high, 100)
        XCTAssertEqual(low, 0)
    }
}

final class NotificationPlannerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func item(_ id: String, hours: Double, _ priority: Int) -> NotificationPlanner.Item { .init(id: id, at: now.addingTimeInterval(hours * 3600), priority: priority) }

    func testEssentialsIgnoreTheBudget() {
        let items = (0..<6).map { item("m\($0)", hours: Double($0) + 1, 0) }
        XCTAssertEqual(NotificationPlanner.select(items, now: now, horizon: now.addingTimeInterval(48 * 3600), budget: 2).count, 6)
    }

    func testBudgetCapsTheRestPerDay() {
        let items = (0..<6).map { item("o\($0)", hours: Double($0) * 0.5 + 1, 2) }
        let picked = NotificationPlanner.select(items, now: now, horizon: now.addingTimeInterval(48 * 3600), budget: 3)
        XCTAssertLessThanOrEqual(picked.count, 6)
        let perDay = Dictionary(grouping: picked) { Day.key($0.at) }.mapValues(\.count)
        XCTAssertTrue(perDay.values.allSatisfy { $0 <= 3 }, "\(perDay)")
    }

    func testHigherPriorityWinsTheBudget() {
        let items = [item("low", hours: 1, 3), item("high", hours: 2, 1)]
        let picked = NotificationPlanner.select(items, now: now, horizon: now.addingTimeInterval(48 * 3600), budget: 1)
        XCTAssertEqual(picked.map(\.id), ["high"])
    }

    func testPastAndFarAwayAreLeftOut() {
        let items = [item("past", hours: -1, 0), item("soon", hours: 1, 0), item("far", hours: 72, 0)]
        XCTAssertEqual(NotificationPlanner.select(items, now: now, horizon: now.addingTimeInterval(48 * 3600), budget: 5).map(\.id), ["soon"])
    }

    func testStaysUnderTheSystemLimit() {
        let items = (0..<100).map { item("e\($0)", hours: Double($0) * 0.4 + 0.1, 0) }
        XCTAssertLessThanOrEqual(NotificationPlanner.select(items, now: now, horizon: now.addingTimeInterval(48 * 3600), budget: 5).count, 60)
    }
}

final class CaptureHardeningTests: XCTestCase {
    let today = "2026-11-02"

    func testDecimalAndThousandsSeparators() {
        XCTAssertEqual(QuickCapture.number(in: "12,50"), 12.5)
        XCTAssertEqual(QuickCapture.number(in: "12.50"), 12.5)
        XCTAssertEqual(QuickCapture.number(in: "1.234,56"), 1234.56)
        XCTAssertEqual(QuickCapture.number(in: "1,234.56"), 1234.56)
        XCTAssertEqual(QuickCapture.number(in: "1.200"), 1200)
        XCTAssertEqual(QuickCapture.number(in: "gastei 7 euros"), 7)
    }

    func testPortugueseSpendingWithEuroSign() {
        guard case .spend(let a, let c, _) = QuickCapture.parse("Gastei 23,40 € no supermercado", today: today) else { return XCTFail() }
        XCTAssertEqual(a, 23.4, accuracy: 0.001)
        XCTAssertEqual(c, "Groceries")
    }

    func testPortugueseReminderKeepsAccentsAndDropsTheDayWords() {
        guard case .reminder(let t, let d, let m) = QuickCapture.parse("Lembra-me de ligar à mãe amanhã às 18h", today: today) else { return XCTFail() }
        XCTAssertEqual(t, "Ligar à mãe")
        XCTAssertEqual(d, "2026-11-03")
        XCTAssertEqual(m, 18 * 60)
    }

    func testReminderWithoutATimeIsAnHonestTask() {
        let i = QuickCapture.parse("Remind me to buy stamps tomorrow", today: today)
        guard case .reminder(_, _, let m) = i else { return XCTFail() }
        XCTAssertNil(m)
        XCTAssertTrue(i.summary.hasPrefix("Task"), i.summary)
    }

    func testCountsRepeatTheSingleItem() {
        guard case .food(let f, let rest) = QuickCapture.parse("Ate 2 eggs and a banana", today: today) else { return XCTFail() }
        XCTAssertEqual(f.count, 3)
        XCTAssertEqual(f.filter { $0.name.hasPrefix("Egg") }.count, 2, f.map(\.name).joined(separator: ","))
        XCTAssertTrue(rest.isEmpty)
    }

    func testUnknownFoodSavesNothing() {
        let i = QuickCapture.parse("Ate xyzzyfood", today: today)
        XCTAssertFalse(i.savesSomething)
        XCTAssertTrue(i.summary.contains("Nothing will be saved"), i.summary)
    }

    func testPartlyKnownFoodSaysWhatIsLeftOut() {
        let i = QuickCapture.parse("Ate a banana and xyzzyfood", today: today)
        XCTAssertTrue(i.savesSomething)
        XCTAssertTrue(i.summary.contains("Not saved"), i.summary)
    }

    func testAmbiguousTextBecomesATaskNotAGuess() {
        guard case .task(let t) = QuickCapture.parse("Spent the afternoon at the library", today: today) else { return XCTFail("a verb without an amount isn't spending") }
        XCTAssertEqual(t, "Spent the afternoon at the library")
    }

    func testParsingIsRepeatable() {
        let a = QuickCapture.parse("Spent 12 euros on groceries", today: today), b = QuickCapture.parse("Spent 12 euros on groceries", today: today)
        XCTAssertEqual(a.summary, b.summary)
    }
}

final class SavedDataTests: XCTestCase {
    func testAnOldProfileKeepsItsValuesAndFillsNewOnes() throws {
        let old = #"{"name":"J","wakeMinute":420,"sleepNeed":480}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(Profile.self, from: old)
        XCTAssertEqual(p.wakeMinute, 420)
        XCTAssertEqual(p.sleepNeed, 480)
        XCTAssertEqual(p.stepGoal, Profile().stepGoal, "a field the old file didn't have gets its default")
    }

    func testAnEmptyProfileDecodes() throws {
        XCTAssertNoThrow(try JSONDecoder().decode(Profile.self, from: "{}".data(using: .utf8)!))
    }

    func testASessionWhoseListsCameBackAsObjectsDecodes() throws {
        let json = #"{"id":"s1","name":"Legs","sets":{},"order":{}}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(WorkoutSession.self, from: json)
        XCTAssertEqual(s.name, "Legs")
        XCTAssertTrue(s.sets.isEmpty)
    }

    func testProfileRoundTrips() throws {
        var p = Profile()
        p.sleepNeed = 450
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }
}
