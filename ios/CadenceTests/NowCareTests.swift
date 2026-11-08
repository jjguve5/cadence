import XCTest
@testable import Cadence

/// Higiene's reminders in «Agora» (decision D40), asked for by the user: Higiene said the beard was due and Today didn't
final class NowCareTests: RegressionCase {
    private func beard(lastDone daysAgo: Int?, interval: Int = 7) -> GroomingItem {
        GroomingItem(id: "G1", title: "Aparar a barba", interval: interval, history: daysAgo.map { [Day.add(-$0, to: Day.today)] } ?? [])
    }

    private let habit = PromiseItem(id: "H1", title: "Ler", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60))
    private let careStep = NowStep.care(NowCare(key: "groom.G1", title: "Aparar a barba", why: "", groomingId: "G1"))

    func testTheOrderOfTheRule() {
        let next = NowHabit(promise: habit, time: 22 * 60, answered: false)
        XCTAssertEqual(NowRule.pick(NowInputs(minute: 600, routine: .routine, care: careStep, habits: [next])), .routine, "the routine of the moment first")
        XCTAssertEqual(NowRule.pick(NowInputs(minute: 600, care: careStep, habits: [next])), careStep, "due now: before the next habit")
        XCTAssertEqual(NowRule.pick(NowInputs(minute: 600, careWhenFree: careStep, habits: [next])), .habit(habit), "it can wait: the habit first")
        XCTAssertEqual(NowRule.pick(NowInputs(minute: 600, careWhenFree: careStep)), careStep, "and with no habit next, it's asked")
        XCTAssertNil(NowRule.pick(NowInputs(minute: 600)))
    }

    @MainActor
    func testOverdueGroomingIsAskedInTheEveningAndWhenFreeEarlier() throws {
        let item = beard(lastDone: 10)
        let store = try makeStore { $0.add(item) }
        var care = store.nowCare(minute: NowRule.careFrom)
        guard case .care(let c)? = care.now else { return XCTFail("from 19:30, before the next habit") }
        XCTAssertEqual(c.title, "Aparar a barba")
        XCTAssertEqual(c.why, "há 10 dias desde a última vez; o ritmo é a cada 7 dias.")
        XCTAssertNil(care.whenFree)
        care = store.nowCare(minute: NowRule.careFrom - 1)
        XCTAssertNil(care.now, "earlier it doesn't jump ahead of the habits")
        XCTAssertNotNil(care.whenFree)
    }

    @MainActor
    func testWhatIsNotOverdueOrNeverRegisteredIsNotAsked() throws {
        let notYet = try makeStore { [item = beard(lastDone: 2)] in $0.add(item) }
        XCTAssertNil(notYet.nowCare(minute: NowRule.careFrom).now)
        let never = try makeStore { [item = beard(lastDone: nil)] in $0.add(item) }
        XCTAssertNil(never.nowCare(minute: NowRule.careFrom).now, "never registered stays in Frequências, as in «A seguir»")
        let off = try makeStore { [item = beard(lastDone: 10)] s in
            s.add(item)
            s.profile.areasOff = ["care"]
        }
        XCTAssertNil(off.nowCare(minute: NowRule.careFrom).now, "Higiene turned off")
    }

    @MainActor
    func testFeitoStartsTheIntervalAgainAndCanBeUndone() throws {
        let item = beard(lastDone: 10)
        let store = try makeStore { $0.add(item) }
        guard case .care(let c)? = store.nowCare(minute: NowRule.careFrom).now else { return XCTFail("no step") }
        store.finishNowCare(c)
        XCTAssertEqual(store.record(GroomingItem.self, "G1")?.last, Day.today)
        XCTAssertNil(store.nowCare(minute: NowRule.careFrom).now, "done: not asked again")
        UndoCenter.shared.undo()
        XCTAssertEqual(store.record(GroomingItem.self, "G1"), item, "Desfazer puts it back")
        XCTAssertNotNil(store.nowCare(minute: NowRule.careFrom).now)
    }

    @MainActor
    func testHojeNaoHidesItForTheDayOnlyAndChangesNothingElse() throws {
        let item = beard(lastDone: 10)
        let store = try makeStore { $0.add(item) }
        guard case .care(let c)? = store.nowCare(minute: NowRule.careFrom).now else { return XCTFail("no step") }
        store.skipNowCare(c)
        XCTAssertNil(store.nowCare(minute: NowRule.careFrom).now)
        XCTAssertEqual(store.record(GroomingItem.self, "G1"), item, "no wash, no date: the item is as it was")
        XCTAssertNotNil(store.nowCare(minute: NowRule.careFrom, day: Day.add(1, to: Day.today)).now, "tomorrow it's asked again")
        UndoCenter.shared.undo()
        XCTAssertNotNil(store.nowCare(minute: NowRule.careFrom).now, "Desfazer: asked again today")
    }

    /// At night the night's sequence stays, with the reminder above it (B6-E1); a departure or a workout keep their place
    func testAtNightTheReminderDoesNotTakeTheNightsPlace() {
        XCTAssertTrue(NightRules.takesAgora(careStep))
        XCTAssertFalse(NightRules.takesAgora(.beforeLeaving))
    }

    /// A shower planned for this morning stops being asked at noon: from then a shower counts for today (B6-E2)
    func testLastNightsShowerIsOnlyAskedInTheMorning() {
        XCTAssertEqual(NowRule.showerDays(day: "2026-11-08", minute: 12 * 60 - 1), ["2026-11-07", "2026-11-08"])
        XCTAssertEqual(NowRule.showerDays(day: "2026-11-08", minute: 12 * 60), ["2026-11-08"])
    }

    func testTheGroomingReminderSaysSinceWhenOnlyWhenItKnows() {
        XCTAssertEqual(Reminders.groomingText(beard(lastDone: 10)), "Há 10 dias desde a última vez; o ritmo é a cada 7 dias.")
        XCTAssertEqual(Reminders.groomingText(beard(lastDone: nil)), "Ainda sem registo. O ritmo é a cada 7 dias.")
    }

    func testTheShowerIsDueFromItsPlannedMinute() {
        XCTAssertFalse(NowRule.showerIsDue(at: 21 * 60, minute: 20 * 60))
        XCTAssertTrue(NowRule.showerIsDue(at: 21 * 60, minute: 21 * 60 - 6), "the plan reads as five minutes away once its time has come")
        XCTAssertTrue(NowRule.showerIsDue(at: 21 * 60, minute: 21 * 60 + 30))
    }
}
