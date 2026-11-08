// Phase 2.4 (Hoje): the «Agora» rule (decision D3), its answers «Adiar 10 min» and «Já não vou», the rings with no
// data, and the quick logs ordered by use. Synthetic data only; the pure rules take the minute and the day.
import XCTest
@testable import Cadence

final class NowTests: RegressionCase {
    private let iso = ISO8601DateFormatter()

    private func habit(_ id: String, _ title: String, at minute: Int, answered: Bool = false) -> NowHabit {
        NowHabit(promise: PromiseItem(id: id, title: title, schedule: Schedule(rule: .daily, start: "2026-01-01", minute: minute)), time: minute, answered: answered)
    }

    private func departure(_ id: String = "ev1", start: Int = 15 * 60, lead: Int = 25) -> NowDeparture {
        NowDeparture(eventId: id, title: "Dentista", start: start, leave: start - lead, place: "Clínica", trip: nil, lead: lead)
    }

    private func event(_ id: String, start: Int, location: String?, title: String = "Dentista", allDay: Bool = false, day: String = Day.today) -> CalendarEvent {
        CalendarEvent(id: id, title: title, start: iso.string(from: Day.at(start, on: day)), end: iso.string(from: Day.at(start + 60, on: day)), allDay: allDay, location: location)
    }

    // MARK: The rule

    /// Each step only applies when the one before it doesn't: urgent departure, workout in progress, Antes de sair,
    /// the routine of the moment, the next habit, and nothing (no card)
    func testTheFirstStepThatAppliesWins() {
        let workout = NowWorkout(id: "S1", name: "Pernas", start: 0)
        let creatine = habit("H1", "Creatina", at: 17 * 60)
        var i = NowInputs(minute: 14 * 60 + 20, departures: [departure()], workout: workout, beforeLeaving: .beforeLeaving, routine: .routine, habits: [creatine])
        XCTAssertEqual(NowRule.pick(i), .leave(departure()))
        i.departures = []
        XCTAssertEqual(NowRule.pick(i), .workout(workout))
        i.workout = nil
        XCTAssertEqual(NowRule.pick(i), .beforeLeaving, "phase 2.9's slot comes before the routine")
        i.beforeLeaving = nil
        XCTAssertEqual(NowRule.pick(i), .routine, "phase 2.5's slot comes before the habit")
        i.routine = nil
        XCTAssertEqual(NowRule.pick(i), .habit(creatine.promise))
        i.habits = []
        XCTAssertNil(NowRule.pick(i), "nothing pending: no card")
        XCTAssertTrue(NowStep.leave(departure()).isUrgent)
        XCTAssertFalse(NowStep.habit(creatine.promise).isUrgent)
    }

    /// Urgent from 45 min before the time to leave until the event starts; the earliest to leave first
    func testADepartureIsUrgentFromFortyFiveMinutesBeforeLeavingUntilTheStart() {
        let d = departure(start: 15 * 60, lead: 25) // leave at 14:35
        XCTAssertNil(NowRule.urgent([d], minute: 13 * 60 + 49))
        XCTAssertEqual(NowRule.urgent([d], minute: 13 * 60 + 50), d)
        XCTAssertEqual(NowRule.urgent([d], minute: 14 * 60 + 40), d, "past the time to leave it still shows, until the start")
        XCTAssertNil(NowRule.urgent([d], minute: 15 * 60), "the event has started")
        let later = departure("ev2", start: 15 * 60 + 10, lead: 10) // leave at 15:00
        XCTAssertEqual(NowRule.urgent([later, d], minute: 14 * 60 + 20), d)
    }

    /// An event needs you to leave only with a place or a regular trip; a trip sets the time from its door-to-door
    /// minutes and margin, otherwise it's 30 min before
    func testAnEventNeedsYouToLeaveOnlyWithAPlaceOrARegularTrip() throws {
        XCTAssertNil(NowRule.departure(for: event("a", start: 15 * 60, location: nil), trips: []), "no place, no trip: not a departure")
        XCTAssertNil(NowRule.departure(for: event("b", start: 15 * 60, location: "  "), trips: []))
        XCTAssertNil(NowRule.departure(for: event("c", start: 0, location: "Casa da avó", allDay: true), trips: []), "all-day events are not departures")
        let placed = try XCTUnwrap(NowRule.departure(for: event("d", start: 15 * 60, location: " Clínica "), trips: []))
        XCTAssertEqual(placed.leave, 15 * 60 - NowRule.defaultLead)
        XCTAssertEqual(placed.place, "Clínica")
        XCTAssertNil(placed.trip)
        let faculdade = RegularTrip(title: "Faculdade", destination: "Rua do Instituto, 5", travel: 25, buffer: 10)
        let byName = try XCTUnwrap(NowRule.departure(for: event("e", start: 9 * 60, location: nil, title: "faculdade"), trips: [faculdade]))
        XCTAssertEqual(byName.leave, 9 * 60 - 35, "the trip's door to door and margin")
        XCTAssertEqual(byName.trip, "Faculdade")
        let byPlace = try XCTUnwrap(NowRule.departure(for: event("f", start: 10 * 60, location: "rua do instituto, 5", title: "Aula"), trips: [faculdade]))
        XCTAssertEqual(byPlace.lead, 35)
        XCTAssertNil(NowRule.departure(for: event("g", start: 10 * 60, location: nil, title: "Aula"), trips: [faculdade]), "a trip that doesn't match doesn't make it a departure")
    }

    /// «Adiar 10 min» hides the warning until its minute; «Já não vou» hides it for the day; an answer this build
    /// doesn't know hides nothing
    func testSnoozeComesBackTenMinutesLaterAndGoneStaysHidden() {
        let d = departure()
        let snoozed = NowDismiss(id: "x", date: Fixed.sunday, event: d.eventId, action: NowDismiss.snooze, until: 14 * 60 + 30)
        XCTAssertNil(NowRule.urgent([d], minute: 14 * 60 + 29, dismissals: [d.eventId: snoozed]))
        XCTAssertEqual(NowRule.urgent([d], minute: 14 * 60 + 30, dismissals: [d.eventId: snoozed]), d)
        let gone = NowDismiss(id: "x", date: Fixed.sunday, event: d.eventId, action: NowDismiss.gone)
        XCTAssertNil(NowRule.urgent([d], minute: 14 * 60 + 50, dismissals: [d.eventId: gone]))
        let unknown = NowDismiss(id: "x", date: Fixed.sunday, event: d.eventId, action: "later")
        XCTAssertFalse(NowRule.hidden(unknown, minute: 14 * 60 + 30))
        XCTAssertFalse(NowRule.hidden(nil, minute: 0))
    }

    /// The answer's id is `<day>_<event>` with only the characters the server takes, at most 80; an id that had to
    /// be cleaned or cut gets a hash, so two events never share an answer
    func testDismissKeysAreIdsTheServerTakes() throws {
        let server = try NSRegularExpression(pattern: "^[A-Za-z0-9_.:-]{1,80}$")
        func takes(_ id: String) -> Bool { server.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil }
        XCTAssertEqual(NowRule.dismissKey(day: "2026-11-12", event: "abc123_20261112T140000Z"), "2026-11-12_abc123_20261112T140000Z")
        let long = String(repeating: "a", count: 100)
        let odd = ["ev/1", "ev 1", "évènement", long, long + "b"].map { NowRule.dismissKey(day: "2026-11-12", event: $0) }
        for id in odd { XCTAssertTrue(takes(id), id); XCTAssertTrue(id.hasPrefix("2026-11-12_"), id) }
        XCTAssertEqual(Set(odd).count, odd.count, "never two events on one answer")
        XCTAssertNotEqual(NowRule.dismissKey(day: "2026-11-12", event: "ev/1"), NowRule.dismissKey(day: "2026-11-12", event: "ev-1"))
    }

    /// The next habit is today's behaviour: the first unanswered one not more than 90 min past its time
    func testTheNextHabitIsTheFirstUnansweredOneStillInTime() {
        let habits = [habit("H1", "Água ao acordar", at: 7 * 60), habit("H2", "Creatina", at: 9 * 60, answered: true), habit("H3", "Batido", at: 17 * 60)]
        XCTAssertEqual(NowRule.nextHabit(habits, minute: 8 * 60 + 30)?.promise.id, "H1", "90 min after its time it's still next")
        XCTAssertEqual(NowRule.nextHabit(habits, minute: 8 * 60 + 31)?.promise.id, "H3", "the answered one is skipped")
        XCTAssertNil(NowRule.nextHabit(habits, minute: 18 * 60 + 31))
    }

    /// «Depois» lists what's still ahead after the step, by time, at most three
    func testLaterListsWhatComesAfterTheStep() {
        let habits = [habit("H1", "Creatina", at: 10 * 60), habit("H2", "Batido", at: 17 * 60), habit("H3", "Ler", at: 22 * 60), habit("H4", "Dentes", at: 22 * 60 + 30), habit("H5", "Feito", at: 12 * 60, answered: true)]
        let training = NowLater(title: "Pernas", minute: 18 * 60)
        let later = NowRule.later(habits: habits, training: training, minute: 10 * 60, excluding: "H1")
        XCTAssertEqual(later.map(\.title), ["Batido", "Pernas", "Ler"])
        XCTAssertEqual(NowRule.laterText(later), "Batido 17:00 · Pernas 18:00 · Ler 22:00")
        XCTAssertFalse(NowRule.later(habits: [], training: training, minute: 18 * 60 + 1, excluding: nil).contains(training), "a training already past isn't ahead")
    }

    // MARK: The Store glue

    /// A workout in progress comes before the next habit; with nothing in progress the habit is the step
    @MainActor
    func testAWorkoutInProgressComesBeforeTheNextHabit() throws {
        let creatine = PromiseItem(id: "H1", title: "Creatina", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 23 * 60))
        let store = try makeStore { $0.promises[creatine.id] = creatine }
        guard case .habit(let next)? = store.nowStep(minute: 8 * 60, events: []) else { return XCTFail("with nothing in progress the habit is the step") }
        XCTAssertEqual(next.id, "H1")
        store.save(WorkoutSession(id: "S1", name: "Pernas", start: nowMs() - 600_000, order: []))
        guard case .workout(let w)? = store.nowStep(minute: 8 * 60, events: []) else { return XCTFail("the workout should be the step") }
        XCTAssertEqual(w.id, "S1")
        XCTAssertTrue(store.nowLater(after: .workout(w), minute: 8 * 60).contains { $0.title == "Creatina" }, "the habit waits in «Depois»")
    }

    /// «Adiar 10 min» and «Já não vou» save their own record (an object, id <day>_<event>), never touch the event, and
    /// Desfazer puts back what was there
    @MainActor
    func testSnoozeAndGoneSaveTheirOwnRecordAndUndo() throws {
        let store = try makeStore()
        let dentist = event("ev1", start: 15 * 60, location: "Clínica")
        let events = [dentist]
        let now = 14 * 60 + 20
        guard case .leave(let d)? = store.nowStep(minute: now, events: events) else { return XCTFail("14:20, dentist at 15:00 with a place: urgent") }
        XCTAssertEqual(d.leave, 15 * 60 - NowRule.defaultLead)

        store.answerNow(d, snooze: true, minute: now)
        let key = NowRule.dismissKey(day: Day.today, event: "ev1")
        let saved = try XCTUnwrap(store.record(NowDismiss.self, key))
        XCTAssertEqual(saved.action, NowDismiss.snooze)
        XCTAssertEqual(saved.until, now + 10)
        guard case .object(let fields)? = store.records(NowDismiss.kind)[key] else { return XCTFail("the record's value is an object") }
        XCTAssertEqual(Set(fields.keys), ["id", "date", "event", "action", "until", "at"])
        XCTAssertNotEqual(store.nowStep(minute: now + 9, events: events)?.isUrgent, true, "put off for 10 min")
        XCTAssertEqual(store.nowStep(minute: now + 10, events: events)?.isUrgent, true, "back 10 min later")

        store.answerNow(d, snooze: false, minute: now + 10)
        XCTAssertNotEqual(store.nowStep(minute: now + 30, events: events)?.isUrgent, true, "«Já não vou» hides it for the day")
        UndoCenter.shared.undo()
        XCTAssertEqual(store.record(NowDismiss.self, key)?.action, NowDismiss.snooze, "Desfazer puts the snooze back")
        XCTAssertEqual(events, [dentist], "the calendar event is never changed")

        store.answerNow(d, snooze: true, minute: now)
        store.put(NowDismiss.kind, key, nil)
        store.answerNow(d, snooze: true, minute: now)
        UndoCenter.shared.undo()
        XCTAssertNil(store.record(NowDismiss.self, key), "with nothing before, Desfazer leaves no record")
    }

    // MARK: Rings with no data

    /// No band data is «sem dados», drawn dashed with no number; food and water with nothing logged keep their number,
    /// with «sem registos», never as behind
    @MainActor
    func testRingsTellNoDataFromZero() throws {
        let empty = try makeStore().ringStats()
        for r in empty.main {
            XCTAssertTrue(r.noData, "\(r.key)")
            XCTAssertEqual(r.center, "—", "\(r.key): no number")
            XCTAssertEqual(r.goal, "sem dados", "\(r.key)")
        }
        let steps = try XCTUnwrap(empty.day.first { $0.key == .move })
        XCTAssertTrue(steps.noData)
        XCTAssertNil(steps.now)
        for key in [RingKey.calories, .protein, .water] {
            let r = try XCTUnwrap(empty.day.first { $0.key == key })
            XCTAssertFalse(r.noData, "\(key) keeps its number")
            XCTAssertEqual(r.note, "sem registos", "\(key)")
            XCTAssertFalse(r.behind, "\(key): nothing logged is never shown as behind")
        }
        XCTAssertEqual(RingStat.summary(empty.main), "Sono sem dados · recuperação sem dados · esforço sem dados")

        let start = iso.string(from: Day.at(-60, on: Day.today)), end = iso.string(from: Day.at(7 * 60, on: Day.today))
        let full = try makeStore { s in
            s.health[Day.today] = HealthDay(date: Day.today, sleep: SleepRecord(start: start, end: end, asleep: 450), steps: 6000, azm: 20)
            s.add(FoodEntry(name: "Sopa", kcal: 120, protein: 4))
            s.add(WaterEntry(ml: 250))
        }.ringStats()
        for key in [RingKey.sleep, .strain] { XCTAssertFalse(try XCTUnwrap(full.main.first { $0.key == key }).noData, "\(key)") }
        XCTAssertEqual(full.main.first { $0.key == .sleep }?.center, "7h 30m")
        XCTAssertFalse(try XCTUnwrap(full.day.first { $0.key == .move }).noData)
        for key in [RingKey.calories, .protein, .water] { XCTAssertNil(try XCTUnwrap(full.day.first { $0.key == key }).note, "\(key)") }
    }

    /// The source line's age in the design's words
    func testHowLongAgo() {
        XCTAssertEqual(TodayFormat.ago(minutes: 0), "agora mesmo")
        XCTAssertEqual(TodayFormat.ago(minutes: -3), "agora mesmo")
        XCTAssertEqual(TodayFormat.ago(minutes: 8), "há 8 min")
        XCTAssertEqual(TodayFormat.ago(minutes: 130), "há 2 h")
        XCTAssertEqual(TodayFormat.ago(minutes: 1500), "há 1 dia")
        XCTAssertEqual(TodayFormat.ago(minutes: 3 * 1440), "há 3 dias")
    }

    // MARK: Quick logs and records not sent

    /// The quick logs follow their use in the 14 days before today; a tie keeps today's order (food, then water)
    func testQuickLogsFollowUseAndTiesKeepTodaysOrder() {
        XCTAssertEqual(TodayQuickLog.ordered(uses: [:]), [.food, .water])
        XCTAssertEqual(TodayQuickLog.ordered(uses: [.food: 3, .water: 3]), [.food, .water])
        XCTAssertEqual(TodayQuickLog.ordered(uses: [.food: 1, .water: 4]), [.water, .food])
    }

    /// Uses are counted from the 14 days before today only, one per moment; what a routine logs isn't a use
    @MainActor
    func testQuickLogUsesCountTheFourteenDaysBeforeToday() throws {
        let today = Fixed.sunday
        let store = try makeStore { s in
            for (i, d) in [1, 2, 14].enumerated() { s.add(WaterEntry(id: "w\(i)", date: Day.add(-d, to: today), minute: 600, ml: 250)) }
            s.add(WaterEntry(id: "old", date: Day.add(-15, to: today), minute: 600, ml: 250))
            s.add(WaterEntry(id: "today", date: today, minute: 600, ml: 250))
            // a meal of two foods at one moment is one use; a shake ticked as a routine is none
            s.add(FoodEntry(id: "f1", date: Day.add(-1, to: today), minute: 780, name: "Arroz", kcal: 300, protein: 6))
            s.add(FoodEntry(id: "f2", date: Day.add(-1, to: today), minute: 780, name: "Frango", kcal: 250, protein: 40))
            s.add(FoodEntry(id: "f3", date: Day.add(-2, to: today), minute: 1020, name: "Batido", kcal: 180, protein: 32, promiseId: "P1"))
        }
        let uses = store.quickLogUses(today: today)
        XCTAssertEqual(uses[.water], 3)
        XCTAssertEqual(uses[.food], 1)
        XCTAssertEqual(TodayQuickLog.ordered(uses: uses), [.water, .food])
    }

    /// The water quick log saves at once and Desfazer removes just that entry
    @MainActor
    func testTheWaterQuickLogCanBeUndone() throws {
        let store = try makeStore { $0.add(WaterEntry(id: "kept", ml: 500)) }
        store.logWaterNow(250)
        XCTAssertEqual(store.fuel().water, 750)
        XCTAssertEqual(UndoCenter.shared.current?.text, "Água +250 ml")
        UndoCenter.shared.undo()
        XCTAssertEqual(store.fuel().water, 500)
        XCTAssertNotNil(store.record(WaterEntry.self, "kept"), "only what the quick log added goes")
    }

    /// «Ver o que falta» shows only when records wait and sending fails
    func testTheUnsentCardOnlyWhenSendingFails() {
        XCTAssertTrue(TodayRules.showsUnsent(pending: 3, failing: true))
        XCTAssertFalse(TodayRules.showsUnsent(pending: 3, failing: false), "waiting for the next send is normal")
        XCTAssertFalse(TodayRules.showsUnsent(pending: 0, failing: true), "nothing to see")
        XCTAssertEqual(TodayRules.unsentText(1), "1 registo ainda não chegou ao servidor. Está guardado neste iPhone.")
        XCTAssertEqual(TodayRules.unsentText(4), "4 registos ainda não chegaram ao servidor. Estão guardados neste iPhone.")
    }
}
