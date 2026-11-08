// Phase 2.8 (Plano): the day's load, conflicts with the training and what Cadence placed (only Cadence's side moves),
// the month grid, new events from one line, Portuguese dates and the end-of-day review. Synthetic data, fixed dates
// (Wednesday 11 November 2026 is the day of the conflicts); the calendar events are passed in, never read.
import XCTest
@testable import Cadence

final class PlanTests: RegressionCase {
    private let iso = ISO8601DateFormatter()
    private let wednesday = "2026-11-11"

    private func event(_ id: String, _ title: String, _ start: Int, _ end: Int, on day: String) -> CalendarEvent {
        CalendarEvent(id: id, title: title, start: iso.string(from: Day.at(start, on: day)), end: iso.string(from: Day.at(end, on: day)), allDay: false)
    }

    // MARK: Load

    /// What overlaps counts once, and only inside the window
    func testCoveredMinutesCountOverlapsOnce() {
        XCTAssertEqual(PlanRules.covered([PlanSpan(start: 0, end: 60), PlanSpan(start: 30, end: 90), PlanSpan(start: 120, end: 150)], from: 0, to: 1440), 120)
        XCTAssertEqual(PlanRules.covered([PlanSpan(start: 400, end: 500)], from: 435, to: 1395), 65, "before waking doesn't count")
        XCTAssertEqual(PlanRules.overlap(PlanSpan(start: 1110, end: 1185), PlanSpan(start: 1140, end: 1320)), 45)
        XCTAssertEqual(PlanRules.overlap(PlanSpan(start: 0, end: 60), PlanSpan(start: 60, end: 90)), 0, "back to back is no overlap")
    }

    /// The load line (decision 2.8): events, blocks and training against the hours awake; each part on its own, the
    /// total with overlaps once; nothing is level 0 with the whole day free
    func testTheLoadIsEventsBlocksAndTrainingAgainstTheHoursAwake() {
        let load = PlanRules.load(events: [PlanSpan(start: 540, end: 1050)], blocks: [PlanSpan(start: 1020, end: 1080)], training: PlanSpan(start: 1080, end: 1155), wake: 435, lightsOut: 1395)
        XCTAssertEqual(load.events, 510)
        XCTAssertEqual(load.blocks, 60)
        XCTAssertEqual(load.training, 75)
        XCTAssertEqual(load.busy, 615, "9:00 to 19:15, the half hour shared by work and the block counted once")
        XCTAssertEqual(load.awake, 960)
        XCTAssertEqual(load.free, 345)
        XCTAssertEqual(load.level, 3)
        let empty = PlanRules.load(events: [], blocks: [], training: nil, wake: 435, lightsOut: 1395)
        XCTAssertEqual(empty.busy, 0)
        XCTAssertEqual(empty.free, 960)
        XCTAssertEqual(empty.level, 0)
        XCTAssertEqual(PlanRules.level(busy: 75, awake: 960), 1)
        XCTAssertEqual(PlanRules.level(busy: 570, awake: 960), 2)
        XCTAssertEqual(PlanRules.level(busy: 576, awake: 960), 3)
    }

    /// The store's load counts the training from your plan, your blocks and the day's events, from waking to lights out
    @MainActor
    func testTheDaysLoadCountsTheTrainingFromThePlan() throws {
        let store = try makeStore { s in
            s.add(WorkoutTemplate(id: "T1", name: "Pernas", exercises: [], weekdays: [4], minutes: 60))
            s.add(PlanBlock(id: "B1", date: self.wednesday, start: 600, minutes: 100, title: "Trabalho focado", type: "deep"))
        }
        let load = store.dayLoad(on: wednesday, events: [event("e1", "Dentista", 900, 960, on: wednesday)])
        XCTAssertEqual(load.events, 60)
        XCTAssertEqual(load.blocks, 100)
        XCTAssertEqual(load.training, 60, "the template at 18:00")
        XCTAssertEqual(load.busy, 220)
        XCTAssertEqual(load.awake, 960, "7:15 to lights out at 23:15")
    }

    // MARK: Conflicts

    /// Nearest free window first, 15 min clear of what's busy, on the quarter hour; one time per window; none when
    /// there's no room
    func testAlternativesAreTheNearestFreeTimes() {
        let one = PlanRules.alternatives(length: 75, original: 1110, busy: [PlanSpan(start: 1140, end: 1320)], from: 720, to: 1365, margin: 15)
        XCTAssertEqual(one, [PlanAlternative(start: 1050, freeFrom: 720, freeTo: 1140)], "17:30, finished 15 min before the dinner")
        let busy = [PlanSpan(start: 780, end: 1020), PlanSpan(start: 1140, end: 1200)]
        XCTAssertEqual(PlanRules.alternatives(length: 60, original: 1110, busy: busy, from: 540, to: 1380, margin: 15).map(\.start), [1065, 1215, 705])
        XCTAssertEqual(PlanRules.alternatives(length: 60, original: 1110, busy: busy, from: 540, to: 1380, margin: 15, limit: 2).map(\.start), [1065, 1215])
        XCTAssertEqual(PlanRules.alternatives(length: 60, original: 600, busy: [PlanSpan(start: 500, end: 1400)], from: 540, to: 1380, margin: 15), [])
    }

    /// A training block at 18:30 against a Google dinner at 19:00 is a conflict. «Aplicar» moves only the training
    /// (the event is never touched) and its undo puts it back; a day gone by has nothing to offer
    @MainActor
    func testATrainingThatClashesMovesAndComesBack() throws {
        let store = try makeStore { s in
            s.add(PlanBlock(id: "B1", date: self.wednesday, start: 1110, minutes: 75, title: "Treino de quarta", type: "training"))
        }
        let dinner = event("g1", "Jantar de anos", 1140, 1320, on: wednesday)
        let conflicts = store.planConflicts(on: wednesday, events: [dinner])
        XCTAssertEqual(conflicts.count, 1)
        let c = try XCTUnwrap(conflicts.first)
        XCTAssertEqual(c.id, "block:B1")
        XCTAssertTrue(c.training)
        XCTAssertTrue(c.otherIsGoogle)
        XCTAssertEqual(c.overlap, 45)
        XCTAssertEqual(c.at, 1140)
        let best = try XCTUnwrap(store.planAlternatives(for: c, events: [dinner], today: "2026-11-10").first)
        XCTAssertEqual(best, PlanAlternative(start: 1050, freeFrom: 495, freeTo: 1140), "from an hour after waking, 15 min before the dinner")
        XCTAssertEqual(store.planAlternatives(for: c, events: [dinner], today: "2026-11-12"), [], "a day gone by")
        let undo = store.applyAlternative(c, start: best.start)
        XCTAssertEqual(store.record(PlanBlock.self, "B1")?.start, 1050)
        XCTAssertEqual(store.planConflicts(on: wednesday, events: [dinner]), [])
        undo()
        XCTAssertEqual(store.record(PlanBlock.self, "B1")?.start, 1110)
        XCTAssertEqual(store.planConflicts(on: wednesday, events: [dinner]).count, 1)
    }

    /// The training from your plan against an event you created in Cadence: the training is what moves, as a training
    /// block at the new time (the plan stays as it is); undo removes that block. A deep-work block against a calendar
    /// event is still a conflict, as before, but not a training one.
    @MainActor
    func testTheTrainingFromThePlanBecomesABlockWhenMoved() throws {
        let store = try makeStore { s in
            s.add(WorkoutTemplate(id: "T1", name: "Pernas", exercises: [], weekdays: [4], minutes: 60))
            s.add(PlanBlock(id: "D1", date: self.wednesday, start: 1110, minutes: 60, title: "Dentista", type: "other"))
        }
        let c = try XCTUnwrap(store.planConflicts(on: wednesday, events: []).first)
        XCTAssertEqual(c.id, "train:\(wednesday)")
        XCTAssertNil(c.block)
        XCTAssertFalse(c.otherIsGoogle)
        XCTAssertEqual(c.other, "Dentista")
        let starts = store.planAlternatives(for: c, events: [], today: "2026-11-10").map(\.start)
        XCTAssertEqual(starts, [1035, 1185], "17:15 or 19:45, 15 min clear of the dentist")
        let undo = store.applyAlternative(c, start: 1035)
        XCTAssertEqual(store.all(PlanBlock.self).filter { $0.type == "training" }.map(\.start), [1035])
        XCTAssertEqual(store.trainingSlot(on: wednesday)?.start, 1035)
        XCTAssertEqual(store.planConflicts(on: wednesday, events: []), [])
        XCTAssertEqual(store.all(WorkoutTemplate.self).first?.weekdays, [4], "the plan itself doesn't change")
        undo()
        XCTAssertTrue(store.all(PlanBlock.self).filter { $0.type == "training" }.isEmpty)
        XCTAssertEqual(store.planConflicts(on: wednesday, events: []).map(\.id), ["train:\(wednesday)"])

        let deep = try makeStore { s in s.add(PlanBlock(id: "W1", date: self.wednesday, start: 600, minutes: 100, title: "Trabalho focado", type: "deep")) }
        let clash = try XCTUnwrap(deep.planConflicts(on: wednesday, events: [event("g2", "Reunião", 630, 690, on: wednesday)]).first)
        XCTAssertFalse(clash.training)
        XCTAssertEqual(clash.overlap, 60)
    }

    // MARK: Month

    /// The same name at the same time on 3 or more days repeats every day (work); a weekly event doesn't
    func testDailyEventsAreTheSameNameAndTimeOnThreeDays() {
        var events = ["2026-11-09", "2026-11-10", "2026-11-11"].map { self.event("w\($0)", "Trabalho", 540, 1050, on: $0) }
        events += [event("d1", "Dentista", 900, 960, on: "2026-11-12"), event("f1", "Futebol", 1200, 1290, on: "2026-11-09"), event("f2", "Futebol", 1200, 1290, on: "2026-11-16")]
        XCTAssertEqual(PlanRules.repeating(events), ["trabalho|540"])
    }

    /// Marks by shape: a training registered, planned, or planned in the past with no record (never «falhado»), then
    /// commitments, then suggestions
    func testMonthMarks() {
        XCTAssertEqual(PlanRules.marks(trainingPlanned: true, trainingLogged: false, past: true, commitments: 0, suggestions: 0), [.trainingNoRecord])
        XCTAssertEqual(PlanRules.marks(trainingPlanned: true, trainingLogged: true, past: true, commitments: 1, suggestions: 0), [.trainingLogged, .commitment])
        XCTAssertEqual(PlanRules.marks(trainingPlanned: true, trainingLogged: false, past: false, commitments: 2, suggestions: 1), [.training, .commitment, .suggestion])
        XCTAssertEqual(PlanRules.marks(trainingPlanned: false, trainingLogged: false, past: false, commitments: 0, suggestions: 0), [])
        XCTAssertEqual(Set(PlanMark.allCases.map(\.word)).count, PlanMark.allCases.count, "one word per mark")
    }

    /// Weeks from Monday, with empty cells before the 1st and after the last day
    func testMonthCellsAndMonths() {
        let november = PlanRules.monthCells("2026-11-12")
        XCTAssertEqual(november.count, 42)
        XCTAssertNil(november[5])
        XCTAssertEqual(november[6], "2026-11-01", "1 November 2026 is a Sunday")
        XCTAssertEqual(november[35], "2026-11-30")
        XCTAssertNil(november[36])
        let february = PlanRules.monthCells("2027-02-10")
        XCTAssertEqual(february.count, 28, "February 2027 starts on a Monday")
        XCTAssertEqual(february[0], "2027-02-01")
        XCTAssertEqual(PlanRules.monthStart("2026-11-12"), "2026-11-01")
        XCTAssertEqual(PlanRules.addMonths(1, to: "2026-11-12"), "2026-12-01")
        XCTAssertEqual(PlanRules.addMonths(-1, to: "2026-11-12"), "2026-10-01")
        XCTAssertEqual(PlanRules.addMonths(2, to: "2026-11-30"), "2027-01-01")
    }

    /// The grid's marks from the store: commitments leave out the daily events; the training from the plan and a
    /// session you registered
    @MainActor
    func testTheGridCountsWhatIsThere() throws {
        let store = try makeStore { s in
            s.add(WorkoutTemplate(id: "T1", name: "Pernas", exercises: [], weekdays: [4], minutes: 60))
            s.add(PlanBlock(id: "D1", date: "2026-11-12", start: 900, minutes: 60, title: "Dentista", type: "other"))
            s.add(WorkoutSession(id: "S1", date: "2026-11-04", name: "Pernas", start: 1, end: 2, order: []))
        }
        let daily: Set<String> = ["trabalho|540"]
        XCTAssertEqual(store.planCommitments(on: "2026-11-12", repeating: daily, events: [event("w", "Trabalho", 540, 1050, on: "2026-11-12")]), 1)
        XCTAssertEqual(store.planCommitments(on: "2026-11-10", repeating: daily, events: [event("w2", "Trabalho", 540, 1050, on: "2026-11-10")]), 0)
        XCTAssertTrue(store.trainingPlanned(on: wednesday))
        XCTAssertFalse(store.trainingPlanned(on: "2026-11-12"))
        XCTAssertTrue(store.trainingLogged(on: "2026-11-04"))
        XCTAssertFalse(store.trainingLogged(on: wednesday))
    }

    // MARK: Words

    func testDatesInPortuguese() {
        XCTAssertEqual(PlanFormat.day("2026-11-12"), "Quinta, 12 de novembro")
        XCTAssertEqual(PlanFormat.day("2026-11-07"), "Sábado, 7 de novembro")
        XCTAssertEqual(PlanFormat.short("2026-11-09"), "Seg")
        XCTAssertEqual(PlanFormat.week(from: "2026-11-09"), "9 a 15 de novembro")
        XCTAssertEqual(PlanFormat.week(from: "2026-11-30"), "30 de novembro a 6 de dezembro")
        XCTAssertEqual(PlanFormat.month("2026-11-01"), "Novembro de 2026")
        XCTAssertEqual(PlanFormat.month("2026-03-05"), "Março de 2026")
        XCTAssertEqual(PlanFormat.relative("2026-11-08", today: "2026-11-08"), "Hoje")
        XCTAssertEqual(PlanFormat.relative("2026-11-09", today: "2026-11-08"), "Amanhã")
        XCTAssertEqual(PlanFormat.relative("2026-11-07", today: "2026-11-08"), "Ontem")
        XCTAssertEqual(PlanFormat.relative("2026-11-12", today: "2026-11-08"), "Quinta, 12 de novembro")
    }

    /// The calendar is read from the day before for 9 days; outside that, «sem dados»
    func testWhatOneCalendarReadCovers() {
        XCTAssertEqual(Agenda.window(from: "2026-11-08"), "2026-11-07"..."2026-11-15")
    }

    // MARK: New event

    /// One line read back: the day and time words go, an hour from 1 to 11 with nothing saying morning or afternoon
    /// gives two readings, a written 24-hour time or «da noite» settles it, and «lembra-me de» keeps QuickCapture's text
    func testANewEventFromOneLine() {
        let today = "2026-11-08" // a Sunday
        XCTAssertEqual(EventDraft.parse("dentista quinta às 3", today: today), EventDraft(title: "Dentista", day: "2026-11-12", minute: nil, options: [900, 180]))
        XCTAssertEqual(EventDraft.parse("Reunião amanhã às 15:30", today: today), EventDraft(title: "Reunião", day: "2026-11-09", minute: 930, options: []))
        XCTAssertEqual(EventDraft.parse("jantar sexta às 8 da noite", today: today), EventDraft(title: "Jantar", day: "2026-11-13", minute: 1200, options: []))
        XCTAssertEqual(EventDraft.parse("café com a Ana", today: today), EventDraft(title: "Café com a Ana", day: nil, minute: nil, options: []))
        XCTAssertEqual(EventDraft.parse("lembra-me de ligar à mãe amanhã às 10", today: today), EventDraft(title: "Ligar à mãe", day: "2026-11-09", minute: nil, options: [1320, 600]))
        XCTAssertEqual(EventDraft.parse("ginásio 18h", today: today), EventDraft(title: "Ginásio", day: nil, minute: 1080, options: []))
        XCTAssertEqual(EventDraft.parse("consulta às 09:00", today: today).minute, 540, "a leading zero is a 24-hour time")
        XCTAssertEqual(EventDraft.parse("almoço às 12", today: today).minute, 720)
        XCTAssertEqual(EventDraft.parse("Dentista hoje as 3", today: today), EventDraft(title: "Dentista", day: today, minute: nil, options: [900, 180]))
    }

    /// The same name in the same week, Monday to Sunday
    func testSomethingWithTheSameNameThatWeek() {
        let entries = [PlanEntry(title: "Dentista", day: "2026-11-10", minute: 900), PlanEntry(title: "Dentista", day: "2026-11-17", minute: 900)]
        XCTAssertEqual(PlanRules.similar(to: "dentista", on: "2026-11-12", among: entries), entries[0])
        XCTAssertEqual(PlanRules.similar(to: "Dentista", on: "2026-11-20", among: entries), entries[1])
        XCTAssertNil(PlanRules.similar(to: "Jantar", on: "2026-11-12", among: entries))
        XCTAssertNil(PlanRules.similar(to: "  ", on: "2026-11-12", among: entries))
    }

    // MARK: End-of-day review

    func testTheReviewsAnswersAndTheirSummary() {
        XCTAssertEqual(DayReview.answer(nil), .notConfirmed)
        XCTAssertEqual(DayReview.answer(PromiseLog(promiseId: "P", date: "2026-11-07", status: .tiny)), .done)
        XCTAssertEqual(DayReview.answer(PromiseLog(promiseId: "P", date: "2026-11-07", status: .skipped)), .notDone)
        XCTAssertEqual(DayReview.answer(PromiseLog(promiseId: "P", date: "2026-11-07", status: .skipped, notApplicable: true)), .notApplicable)
        XCTAssertEqual(DayReview.saved(.notApplicable)?.status, .skipped)
        XCTAssertEqual(DayReview.saved(.notApplicable)?.notApplicable, true)
        XCTAssertEqual(DayReview.saved(.notDone)?.status, .skipped)
        XCTAssertNil(DayReview.saved(.notDone)?.notApplicable)
        XCTAssertNil(DayReview.saved(.notConfirmed), "«não confirmado» saves nothing")
        XCTAssertEqual(DayReview.summary([.done, .done, .notDone, .notApplicable, .notConfirmed]), "2 feitos · 1 não feito · 1 não se aplica · 1 não confirmado")
        XCTAssertEqual(DayReview.summary([.notApplicable, .notApplicable]), "2 não se aplicam")
        XCTAssertEqual(DayReview.summary([]), "Nada para rever neste dia.")
    }

    /// An answer from the review undone is «não confirmado» again; the day's plan says «não se aplica» for one
    @MainActor
    func testAReviewAnswerCanBeUndoneAndShowsOnThePlan() throws {
        let shake = PromiseItem(id: "S1", title: "Batido", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 17 * 60))
        let store = try makeStore { $0.promises[shake.id] = shake }
        store.saveReview(shake, on: Fixed.saturday, .done)
        XCTAssertEqual(store.reviewAnswer(shake, on: Fixed.saturday), .done)
        store.undo(shake, on: Fixed.saturday)
        XCTAssertEqual(store.reviewAnswer(shake, on: Fixed.saturday), .notConfirmed)
        store.saveReview(shake, on: Fixed.saturday, .notApplicable)
        XCTAssertEqual(store.planItems(for: Fixed.saturday).first { $0.id == "S1" }?.detail, "não se aplica")
        store.saveReview(shake, on: Fixed.saturday, .notDone)
        XCTAssertEqual(store.planItems(for: Fixed.saturday).first { $0.id == "S1" }?.detail, "saltado")
    }
}
