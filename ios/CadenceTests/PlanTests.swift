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

    /// An event you created in Cadence (a block that isn't the training) is shown as a conflict, with no other time
    /// offered: only the training is ever moved (B3-R3)
    @MainActor
    func testAnEventYouCreatedIsShownWithoutAMoveProposal() throws {
        let store = try makeStore { s in
            s.add(PlanBlock(id: "D1", date: self.wednesday, start: 900, minutes: 60, title: "Dentista", type: "other"))
        }
        let meeting = event("g1", "Reunião", 930, 990, on: wednesday)
        let c = try XCTUnwrap(store.planConflicts(on: wednesday, events: [meeting]).first)
        XCTAssertFalse(c.training)
        XCTAssertEqual(c.overlap, 30)
        XCTAssertEqual(store.planAlternatives(for: c, events: [meeting], today: "2026-11-10"), [], "no other time for something of yours")
    }

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

    /// An event repeats every day only when it's on every working day the calendar was read for, except at most one
    /// (B3-R2: this test used to pin «3 or more days», which hid a class three times a week). Work from Monday to Friday
    /// repeats every day, as the board N_PlanoMes says (B5-E1); a Monday/Wednesday/Friday class stays visible; days
    /// outside the read don't count.
    func testOnlyAnEventOnEveryCoveredDayRepeatsEveryDay() {
        let window = Agenda.window(from: "2026-11-08") // Saturday 7 to Sunday 15: nine days
        let nine = (0..<9).map { Day.add($0, to: "2026-11-07") }
        var events = nine.map { self.event("s\($0)", "Stand-up", 540, 555, on: $0) }
        events += nine.dropFirst().map { self.event("c\($0)", "Comprimidos", 480, 490, on: $0) } // eight of the nine
        events += ["2026-11-09", "2026-11-11", "2026-11-13"].map { self.event("a\($0)", "Aula", 1080, 1170, on: $0) } // Monday, Wednesday, Friday
        events += (0..<5).map { self.event("w\($0)", "Trabalho", 540, 1050, on: Day.add($0, to: "2026-11-09")) } // Monday to Friday
        events += [event("f1", "Futebol", 1200, 1290, on: "2026-11-09"), event("f2", "Futebol", 1200, 1290, on: "2026-11-16")]
        // three working days inside the read and four outside it: seven in all, but only the three count
        events += ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-16", "2026-11-17", "2026-11-18", "2026-11-19"].map { self.event("o\($0)", "Almoço", 780, 840, on: $0) }
        XCTAssertEqual(PlanRules.repeating(events, window: window), ["stand-up|540", "comprimidos|480", "trabalho|540"])
        XCTAssertEqual(PlanRules.repeating(events, window: nil), [], "a calendar never read has nothing daily")
    }

    /// Outside what the calendar was read for, a day is «sem dados», never «livre»: its own mark, no level (so no shade),
    /// and the load line says it's partial (B3-R1). `Agenda.covers` is the read's days and nothing else.
    @MainActor
    func testADayTheCalendarWasntReadForIsSemDadosNotFree() throws {
        let window = Agenda.window(from: "2026-11-08")
        XCTAssertTrue(Agenda.covers("2026-11-07", known: window), "the first day of the read")
        XCTAssertTrue(Agenda.covers("2026-11-15", known: window), "the last day of the read")
        XCTAssertFalse(Agenda.covers("2026-11-06", known: window))
        XCTAssertFalse(Agenda.covers("2026-11-16", known: window))
        XCTAssertFalse(Agenda.covers("2026-11-08", known: nil), "never read: no day is covered")

        XCTAssertEqual(PlanRules.marks(trainingPlanned: false, trainingLogged: false, past: false, commitments: 0, suggestions: 0, calendarKnown: false), [.noData])
        XCTAssertEqual(PlanRules.marks(trainingPlanned: true, trainingLogged: false, past: false, commitments: 1, suggestions: 0, calendarKnown: false), [.training, .commitment, .noData])
        XCTAssertEqual(PlanRules.loadWord(known: false), "carga parcial")
        XCTAssertEqual(PlanRules.loadWord(known: true), "carga")

        let store = try makeStore()
        let unknown = store.monthDay("2026-11-20", today: "2026-11-08", repeating: [], kept: [], known: false)
        XCTAssertEqual(unknown.marks, [.noData])
        XCTAssertNil(unknown.level, "no shade: an empty cell there isn't a free day")
        let known = store.monthDay("2026-11-20", today: "2026-11-08", repeating: [], kept: [], known: true)
        XCTAssertEqual(known.marks, [])
        XCTAssertEqual(known.level, 0, "read and empty is a free day")
    }

    /// The summary only ever shows a day of the month on screen (B3-M4): the day you picked if it's there, otherwise
    /// today if it's there, otherwise nothing
    func testTheSummaryShowsOnlyADayOfTheMonthOnScreen() {
        XCTAssertEqual(PlanRules.monthPick(nil, month: "2026-11-01", today: "2026-11-08"), "2026-11-08")
        XCTAssertEqual(PlanRules.monthPick("2026-11-20", month: "2026-11-01", today: "2026-11-08"), "2026-11-20")
        XCTAssertNil(PlanRules.monthPick("2026-11-20", month: "2026-12-01", today: "2026-11-08"), "a day picked in another month is cleared")
        XCTAssertNil(PlanRules.monthPick(nil, month: "2026-12-01", today: "2026-11-08"), "today isn't in December")
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

    /// «à 1» is a time (B3-M3): the hour 1 is the only singular one, so only it is read after a bare «a», and «a 2 amigos»
    /// isn't a time. With nothing saying morning or afternoon it has two readings, like any hour from 1 to 11.
    func testTheSingularHourIsATimeInTheLine() {
        let today = "2026-11-08"
        XCTAssertEqual(EventDraft.parse("dentista quinta à 1", today: today), EventDraft(title: "Dentista", day: "2026-11-12", minute: nil, options: [780, 60]))
        XCTAssertEqual(EventDraft.parse("almoço à 1:30", today: today), EventDraft(title: "Almoço", day: nil, minute: nil, options: [810, 90]))
        // «a 1 de dezembro» is a date (B5-E4), «à 1 de manhã» a time
        let dated = EventDraft.parse("dentista a 1 de dezembro às 15", today: today)
        XCTAssertEqual(dated.minute, 15 * 60)
        XCTAssertTrue(dated.title.contains("1 de dezembro"), dated.title)
        let early = EventDraft.parse("voo à 1 de manhã", today: today)
        XCTAssertTrue(early.minute == 60 || early.options.contains(60), "\(early)")
        XCTAssertEqual(EventDraft.parse("reunião a 1 da tarde", today: today), EventDraft(title: "Reunião", day: nil, minute: 780, options: []))
        let friends = EventDraft.parse("ligar a 2 amigos", today: today)
        XCTAssertNil(friends.minute, "«a» only goes with the hour 1")
        XCTAssertEqual(friends.options, [])
        XCTAssertEqual(friends.title, "Ligar a 2 amigos")
    }

    /// The hour 1 is singular in European Portuguese («à 1:00», «da 1:00»); every other hour, 13:00 and 0:00 included, is
    /// plural
    func testTheHourOneIsSingular() {
        XCTAssertEqual(PlanFormat.at(60), "à 1:00")
        XCTAssertEqual(PlanFormat.at(90), "à 1:30")
        XCTAssertEqual(PlanFormat.at(120), "às 2:00")
        XCTAssertEqual(PlanFormat.at(780), "às 13:00")
        XCTAssertEqual(PlanFormat.at(0), "às 0:00")
        XCTAssertEqual(PlanFormat.from(60), "da 1:00")
        XCTAssertEqual(PlanFormat.from(900), "das 15:00")
        XCTAssertEqual(PlanFormat.article(60), "a 1:00")
        XCTAssertEqual(PlanFormat.article(1050), "as 17:30")
        XCTAssertEqual(PlanFormat.atHour(1), "à 1")
        XCTAssertEqual(PlanFormat.atHour(3), "às 3")
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

    // MARK: «Não se aplica» is not «Não fiz» (B3-E1)

    private func habit(_ id: String, kind: PromiseKind = .routine, weekdays: [Int]? = nil) -> PromiseItem {
        var schedule = Schedule(rule: .daily, start: "2026-01-01", minute: 9 * 60)
        if let weekdays {
            schedule.rule = .weekdays
            schedule.weekdays = weekdays
        }
        return PromiseItem(id: id, title: id, kind: kind, schedule: schedule)
    }

    private func answer(_ p: PromiseItem, _ status: LogStatus, on day: String, notApplicable: Bool? = nil, in s: inout Saved) {
        let log = PromiseLog(promiseId: p.id, date: day, status: status, notApplicable: notApplicable)
        s.logs[log.id] = log
    }

    /// One habit done and one «Não se aplica» is all of what counted: 40 of 40 points for habits, 30 of 30 with Comida
    /// on. A plain «Não fiz» stays in the count (20 of 40). Saved points are read as they were saved.
    @MainActor
    func testNotApplicableLeavesTheScore() throws {
        let done = habit("D"), notApplicable = habit("NA"), missed = habit("M")
        let day = Fixed.saturday
        let withoutFuel = try makeStore { s in
            s.profile.areasOff = ["fuel"]
            s.promises = [done.id: done, notApplicable.id: notApplicable]
            self.answer(done, .done, on: day, in: &s)
            self.answer(notApplicable, .skipped, on: day, notApplicable: true, in: &s)
        }
        XCTAssertEqual(withoutFuel.score(on: day), 40)
        let withFuel = try makeStore { s in
            s.promises = [done.id: done, notApplicable.id: notApplicable]
            self.answer(done, .done, on: day, in: &s)
            self.answer(notApplicable, .skipped, on: day, notApplicable: true, in: &s)
        }
        XCTAssertEqual(withFuel.score(on: day), 30)
        let plainSkip = try makeStore { s in
            s.profile.areasOff = ["fuel"]
            s.promises = [done.id: done, missed.id: missed]
            self.answer(done, .done, on: day, in: &s)
            self.answer(missed, .skipped, on: day, in: &s)
        }
        XCTAssertEqual(plainSkip.score(on: day), 20, "«Não fiz» is a miss and stays in the count")
    }

    /// A day answered «Não se aplica» leaves «x/y esta semana»: done, due so far and the week's total
    @MainActor
    func testNotApplicableLeavesTheWeekCount() throws {
        let p = habit("H1")
        let store = try makeStore { s in
            s.promises[p.id] = p
            self.answer(p, .done, on: Fixed.monday, in: &s)
            self.answer(p, .skipped, on: Fixed.tuesday, notApplicable: true, in: &s)
            self.answer(p, .skipped, on: Fixed.wednesday, in: &s)
        }
        let w = store.week(p, upTo: Fixed.wednesday)
        XCTAssertEqual(w.done, 1)
        XCTAssertEqual(w.due, 2, "Monday and Wednesday: Tuesday didn't apply, Wednesday's skip still counts")
        XCTAssertEqual(w.total, 6, "the week's seven days less the one that didn't apply")
    }

    /// «Hábitos cumpridos %» in the weekly review and the habits ring leave it out too; a plain skip stays in
    @MainActor
    func testNotApplicableLeavesTheWeeklyReviewAndTheRing() throws {
        let done = habit("D", weekdays: [2]), notApplicable = habit("NA", weekdays: [2]), missed = habit("M", weekdays: [2]) // Mondays only
        let applied = try makeStore { s in
            s.promises = [done.id: done, notApplicable.id: notApplicable]
            self.answer(done, .done, on: Fixed.monday, in: &s)
            self.answer(notApplicable, .skipped, on: Fixed.monday, notApplicable: true, in: &s)
        }
        XCTAssertEqual(applied.weekReview(Fixed.monday).first { $0.0 == "Hábitos cumpridos" }?.1, "100%")
        let skipped = try makeStore { s in
            s.promises = [done.id: done, missed.id: missed]
            self.answer(done, .done, on: Fixed.monday, in: &s)
            self.answer(missed, .skipped, on: Fixed.monday, in: &s)
        }
        XCTAssertEqual(skipped.weekReview(Fixed.monday).first { $0.0 == "Hábitos cumpridos" }?.1, "50%")

        // the ring is today's, so its answers are today's
        let today = Day.today
        let daily = habit("D"), otherDaily = habit("NA")
        let ringStore = try makeStore { s in
            s.promises = [daily.id: daily, otherDaily.id: otherDaily]
            self.answer(daily, .done, on: today, in: &s)
            self.answer(otherDaily, .skipped, on: today, notApplicable: true, in: &s)
        }
        let ring = try XCTUnwrap(ringStore.ringStats().day.first { $0.key == .promises })
        XCTAssertEqual(ring.center, "1/1")
        XCTAssertEqual(ring.target, 1)
    }

    /// On a minimum day a must-do that doesn't apply leaves the essentials: done against the one that's left
    @MainActor
    func testNotApplicableLeavesTheMinimumDay() throws {
        let done = habit("M1", kind: .mustDo), notApplicable = habit("M2", kind: .mustDo), missed = habit("M3", kind: .mustDo)
        let day = Fixed.saturday
        let applied = try makeStore { s in
            s.promises = [done.id: done, notApplicable.id: notApplicable]
            self.answer(done, .done, on: day, in: &s)
            self.answer(notApplicable, .skipped, on: day, notApplicable: true, in: &s)
        }
        XCTAssertEqual(applied.minimumScore(on: day), 75, "50 for the essentials, 25 for sleep with no data")
        let skipped = try makeStore { s in
            s.promises = [done.id: done, missed.id: missed]
            self.answer(done, .done, on: day, in: &s)
            self.answer(missed, .skipped, on: day, in: &s)
        }
        XCTAssertEqual(skipped.minimumScore(on: day), 50, "one of two essentials")
    }

    /// In Today «Não se aplica» has its own circle and its own words for VoiceOver, not «Saltar»'s or «Não fiz»'s
    func testNotApplicableLooksAndReadsDifferentlyFromASkip() {
        XCTAssertEqual(TodayRules.habitIcon(.skipped, notApplicable: true), DataState.unavailable.icon)
        XCTAssertNotEqual(TodayRules.habitIcon(.skipped, notApplicable: true), TodayRules.habitIcon(.skipped, notApplicable: false))
        XCTAssertEqual(TodayRules.habitIcon(.skipped, notApplicable: false), "minus.circle")
        XCTAssertEqual(TodayRules.habitIcon(.done, notApplicable: false), "checkmark.circle.fill")
        XCTAssertEqual(TodayRules.habitIcon(nil, notApplicable: false), "circle")
        XCTAssertEqual(TodayRules.habitLabel("Batido", .skipped, notApplicable: true), "Batido, não se aplica")
        XCTAssertEqual(TodayRules.habitLabel("Batido", .skipped, notApplicable: false), "Batido, não fiz")
        XCTAssertEqual(TodayRules.habitLabel("Batido", .done, notApplicable: false), "Batido, feito")
        XCTAssertEqual(TodayRules.habitLabel("Batido", nil, notApplicable: false), "Batido, por responder")
    }

    // MARK: A session left open past its day (B3-E2, B4-N3, B4-N4, decision D23)

    /// Started and left with nothing registered: no session to count, so no «Parcial · 0 min», no «registado» in the month
    /// and no «feito» in the day (B5-E2: absence is never a result). It isn't «Em curso» either
    @MainActor
    func testAnOpenSessionWithNothingRegisteredIsNotCounted() throws {
        let start = Day.at(18 * 60, on: Fixed.wednesday).timeIntervalSince1970 * 1000
        let empty = WorkoutSession(id: "S2", date: Fixed.wednesday, name: "Pernas", start: start, end: nil, order: [],
                                   sets: [SetLog(exerciseId: "squat", weight: 40, reps: 8, done: false)])
        let store = try makeStore { $0.add(empty) }
        XCTAssertNil(DayReview.sessionLine(store.sessions(on: Fixed.wednesday), today: "2026-11-05"))
        XCTAssertFalse(store.trainingLogged(on: Fixed.wednesday, today: "2026-11-05"))
        XCTAssertFalse(TrainingRules.isEnded(empty, today: "2026-11-05"))
        XCTAssertFalse(TrainingRules.isPartial(empty, today: "2026-11-05"))
        XCTAssertNotEqual(store.trainingSlot(on: Fixed.wednesday)?.done, true)
        XCTAssertNil(store.activeSession, "and it isn't in progress: the day is over")
        XCTAssertEqual(store.record(WorkoutSession.self, "S2"), empty, "nothing written")
    }

    /// Open on a past day: partial when it's read, up to its last activity, in the review, the month, the weekly review
    /// and the time audit; nothing is written. Open today it is still in progress.
    @MainActor
    func testAnOpenSessionFromAPastDayIsPartialWhenRead() throws {
        let start = Day.at(18 * 60, on: Fixed.wednesday).timeIntervalSince1970 * 1000
        var open = WorkoutSession(id: "S1", date: Fixed.wednesday, name: "Pernas", start: start, end: nil, order: [],
                                  sets: [SetLog(exerciseId: "squat", weight: 40, reps: 8, done: true)])
        open.pausedAt = start + 40 * 60000 // the last thing done, 40 min in
        let left = open
        let store = try makeStore { $0.add(left) }

        let line = try XCTUnwrap(DayReview.sessionLine(store.sessions(on: Fixed.wednesday), today: "2026-11-05"))
        XCTAssertEqual(line.state, .partial)
        XCTAssertEqual(line.text, "Parcial")
        XCTAssertEqual(line.sub, "registado no treino · 40 min")
        let running = try XCTUnwrap(DayReview.sessionLine(store.sessions(on: Fixed.wednesday), today: Fixed.wednesday))
        XCTAssertEqual(running.state, .pending)
        XCTAssertEqual(running.text, "Em curso")

        XCTAssertTrue(store.trainingLogged(on: Fixed.wednesday, today: "2026-11-05"), "the month counts it as logged")
        XCTAssertFalse(store.trainingLogged(on: Fixed.wednesday, today: Fixed.wednesday), "still in progress on its own day")
        XCTAssertTrue(store.monthDay(Fixed.wednesday, today: "2026-11-05", repeating: [], kept: [], known: true).marks.contains(.trainingLogged))
        XCTAssertEqual(store.trainingSlot(on: Fixed.wednesday)?.done, true, "what really happened, not the plan")

        XCTAssertEqual(store.weekReview(Fixed.monday).first { $0.0 == "Treinos" }?.1, "1")
        XCTAssertEqual(store.timeAudit(week: Fixed.monday).first { $0.0 == "Training" }?.1, 40)

        XCTAssertNil(store.record(WorkoutSession.self, "S1")?.end, "computed on read: nothing is written")
        XCTAssertEqual(store.pendingSyncCount, 0)
    }

    // MARK: Pending records (C-L2, B4-N8, decisions D8 and D24)

    /// What the server can take, and what «Precisa de ação» and Perfil count: habit answers ("|" ids, decision D8) and
    /// plain values stay on this iPhone; a record object or a deletion goes
    @MainActor
    func testWhatTheServerCanTakeIsWhatIsPending() throws {
        let p = habit("H1")
        let store = try makeStore { $0.promises[p.id] = p }
        XCTAssertEqual(store.pendingSendableCount, 0)
        store.log(p, on: Fixed.saturday, .done)
        XCTAssertFalse(store.serverCanTake("log:H1|\(Fixed.saturday)"), "a habit answer has a | in its id")
        XCTAssertEqual(store.pendingSyncCount, 1)
        XCTAssertEqual(store.pendingSendableCount, 0, "it stays on this iPhone, so nothing needs action")
        store.put("bedshift", Fixed.saturday, .number(15))
        XCTAssertFalse(store.serverCanTake("bedshift:\(Fixed.saturday)"), "a plain value isn't an object")
        XCTAssertEqual(store.pendingSendableCount, 0)
        store.save(DayEntry(date: Fixed.saturday))
        XCTAssertTrue(store.serverCanTake("day:\(Fixed.saturday)"))
        XCTAssertEqual(store.pendingSendableCount, 1)
        store.put("thing", "a-1", .object(["x": .number(1)]))
        XCTAssertTrue(store.serverCanTake("thing:a-1"))
        XCTAssertEqual(store.pendingSendableCount, 2)
        store.put("thing", "a-1", nil)
        XCTAssertTrue(store.serverCanTake("thing:a-1"), "a deletion goes to the server")
        XCTAssertEqual(store.pendingSendableCount, 2)
        XCTAssertFalse(store.serverCanTake("Bad:x"), "a type the server wouldn't take")
        XCTAssertFalse(store.serverCanTake("thing:id with spaces"))
    }
}
