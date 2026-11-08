// Phase 2.9 (Noite, Antes de sair e Antes de dormir): the rules behind Antes de sair, the night's sequence, tomorrow's
// outfit and gym bag, «Vou dormir», the reading planned and done, and the morning's sleep. Synthetic data, fixed
// dates where the code takes a day, no server (RegressionSupport). D3's order in «Agora» is in NowTests.
import XCTest
@testable import Cadence

final class NightTests: RegressionCase {
    private let iso = ISO8601DateFormatter()

    private func takes(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_.:-]{1,80}$", options: .regularExpression) != nil
    }

    private func keys<T: Encodable>(_ value: T) throws -> Set<String> {
        Set(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]).keys)
    }

    // MARK: Antes de sair: the list

    /// The app's three come first (as you edited them), then yours in the order you added them; what you removed is
    /// gone, even one of the app's three
    func testTheListKeepsTheAppsThreeThenYoursAndWhatYouRemoveStaysGone() {
        XCTAssertEqual(LeaveRules.list(saved: []).map { $0.id }, ["keys", "gymBag", "umbrella"])
        let pass = LeaveItem(id: "mine-pass", title: "Passe", at: 5)
        let bottle = LeaveItem(id: "mine-bottle", title: "Garrafa de água", when: LeaveItem.training, optional: true, at: 3)
        var umbrella = LeaveRules.builtIns[2]
        umbrella.removed = true
        var keys = LeaveRules.builtIns[0]
        keys.title = "Chaves"
        let list = LeaveRules.list(saved: [pass, bottle, umbrella, keys])
        XCTAssertEqual(list.map { $0.id }, ["keys", "gymBag", "mine-bottle", "mine-pass"], "yours in the order you added them; the umbrella removed")
        XCTAssertEqual(list.first?.title, "Chaves", "an edit to one of the app's three is kept")
    }

    /// The gym bag only on training days, the umbrella only with rain forecast; a rule this build doesn't know keeps
    /// the item on the list, so nothing is lost
    func testItemsApplyByTheirRule() {
        let items = LeaveRules.builtIns
        XCTAssertEqual(items.filter { LeaveRules.applies($0, training: false, rain: false) }.map { $0.id }, ["keys"])
        XCTAssertEqual(items.filter { LeaveRules.applies($0, training: true, rain: true) }.map { $0.id }, ["keys", "gymBag", "umbrella"])
        XCTAssertTrue(LeaveRules.applies(LeaveItem(id: "x", title: "X", when: "weekday:2"), training: false, rain: false))
        XCTAssertEqual(LeaveRules.whenLabel(LeaveItem(id: "x", title: "X", when: LeaveItem.training, optional: true)), "opcional · em dias de treino fora de casa")
        XCTAssertEqual(LeaveRules.whenLabel(LeaveRules.builtIns[2]), "quando há chuva prevista")
    }

    /// Antes de sair shows from an hour before the time to leave until it (decision of phase 2.9), and only with
    /// something still to see
    func testTheWindowIsTheHourBeforeLeaving() {
        let trip = LeaveDeparture(title: "Faculdade", leave: 8 * 60 + 15)
        let gym = LeaveDeparture(title: "Treino", leave: 18 * 60)
        XCTAssertNil(LeaveRules.next([trip, gym], minute: 7 * 60 + 14))
        XCTAssertEqual(LeaveRules.next([trip, gym], minute: 7 * 60 + 15), trip)
        XCTAssertEqual(LeaveRules.next([trip, gym], minute: 7 * 60 + 42), trip, "7:42, leaving at 8:15 (D3)")
        XCTAssertEqual(LeaveRules.next([trip, gym], minute: 8 * 60 + 15), trip, "until the time to leave")
        XCTAssertNil(LeaveRules.next([trip, gym], minute: 8 * 60 + 16))
        XCTAssertEqual(LeaveRules.next([trip, gym], minute: 17 * 60 + 30), gym, "17:30, training at 18:30 (D3)")
        XCTAssertEqual(LeaveRules.passed([trip, gym], minute: 9 * 60), trip)
        XCTAssertNil(LeaveRules.passed([trip, gym], minute: 8 * 60))
        XCTAssertFalse(LeaveRules.isStep([trip], minute: 7 * 60 + 42, pending: 0), "nothing left to see: no step")
        XCTAssertTrue(LeaveRules.isStep([trip], minute: 7 * 60 + 42, pending: 2))
    }

    /// After the time to leave, what wasn't seen becomes one line in Today, once: until you close it or say «Concluído»,
    /// and never while the next departure's own hour is on
    func testTheLineAfterLeavingShowsOnceUntilClosed() {
        let trip = LeaveDeparture(title: "Faculdade", leave: 8 * 60 + 15)
        let gym = LeaveDeparture(title: "Treino", leave: 18 * 60)
        XCTAssertFalse(LeaveRules.showsLine([trip, gym], minute: 8 * 60, pending: 2, day: nil), "not before leaving")
        XCTAssertTrue(LeaveRules.showsLine([trip, gym], minute: 9 * 60, pending: 2, day: nil))
        XCTAssertFalse(LeaveRules.showsLine([trip, gym], minute: 9 * 60, pending: 0, day: nil), "nothing left")
        XCTAssertFalse(LeaveRules.showsLine([trip, gym], minute: 17 * 60 + 30, pending: 2, day: nil), "the next departure's step instead")
        let closed = LeaveDay(id: Fixed.monday, date: Fixed.monday, closed: true)
        XCTAssertFalse(LeaveRules.showsLine([trip, gym], minute: 9 * 60, pending: 2, day: closed), "closed: it doesn't come back")
        let ready = LeaveDay(id: Fixed.monday, date: Fixed.monday, ready: 1)
        XCTAssertFalse(LeaveRules.showsLine([trip], minute: 9 * 60, pending: 1, day: ready))
        XCTAssertEqual(LeaveRules.names(["Guarda-chuva", "Saco do ginásio", "Passe"]), "guarda-chuva, saco do ginásio e passe")
        XCTAssertEqual(LeaveRules.names(["Passe"]), "passe")
        XCTAssertEqual(LeaveRules.reminderBody(["Guarda-chuva"]), "Antes de sair: guarda-chuva.")
    }

    /// The new records are left out of the file when unset and their ids are ones the server takes
    func testNewRecordsAreObjectsWithIdsTheServerTakes() throws {
        XCTAssertEqual(try keys(LeaveItem(id: "keys", title: "Chaves e carteira")), ["id", "title", "when", "at"])
        XCTAssertEqual(try keys(LeaveDay(id: Fixed.monday, date: Fixed.monday)), ["id", "date", "seen", "at"])
        XCTAssertEqual(try keys(SleepIntent(id: Fixed.sunday, date: Fixed.sunday, minute: 1353)), ["id", "date", "minute", "at"])
        for id in ["keys", "gymBag", "umbrella", "mine-" + UUID().uuidString, Fixed.sunday] { XCTAssertTrue(takes(id), id) }
    }

    // MARK: Antes de sair: the Store

    /// Tapping marks one item as taken; «Concluído» marks the rest and Desfazer puts the day back as it was
    @MainActor
    func testConcluidoMarksTheRestWithUndo() throws {
        let store = try makeStore { s in
            s.add(RegularTrip(id: "R", title: "Faculdade", weekdays: [Day.weekday(Day.today)], arrive: 9 * 60, travel: 35, buffer: 10))
            s.add(LeaveItem(id: "mine-pass", title: "Passe", at: 1))
        }
        XCTAssertEqual(store.nowStep(minute: 7 * 60 + 42, events: []), .beforeLeaving)
        let pass = try XCTUnwrap(store.leaveEntries().first { $0.id == "mine-pass" })
        store.toggleLeaveSeen(pass)
        XCTAssertEqual(store.leaveDay()?.seen, ["mine-pass"])
        store.finishLeaving()
        XCTAssertNotNil(store.leaveDay()?.ready, "«Pronto para sair»")
        XCTAssertTrue(store.leaveEntries().allSatisfy { $0.seen }, "«Concluído» marks the rest")
        XCTAssertNotEqual(store.nowStep(minute: 7 * 60 + 42, events: []), .beforeLeaving, "everything seen: not the step")
        UndoCenter.shared.undo()
        XCTAssertEqual(store.leaveDay()?.seen, ["mine-pass"], "Desfazer puts the day back as it was")
        XCTAssertNil(store.leaveDay()?.ready)
        XCTAssertEqual(store.nowStep(minute: 7 * 60 + 42, events: []), .beforeLeaving)
        guard case .object? = store.records(LeaveDay.kind)[Day.today] else { return XCTFail("the day's value is an object") }
        XCTAssertFalse(store.leaveLineShows(minute: 7 * 60 + 42))
        XCTAssertTrue(store.leaveLineShows(minute: 9 * 60), "past the time to leave with something not seen: the line")
        store.closeLeaveLine()
        XCTAssertFalse(store.leaveLineShows(minute: 9 * 60), "closed, once")
    }

    /// A removed item is kept as removed: its rule never puts it back. Desfazer leaves no record. Yours get a safe id.
    @MainActor
    func testARemovedItemNeverComesBack() throws {
        let store = try makeStore { $0.add(PlanBlock(id: "B", date: Day.today, start: 18 * 60 + 30, minutes: 60, title: "Pernas", type: "training")) }
        XCTAssertTrue(store.leaveEntries().contains { $0.id == "gymBag" }, "a training day: the gym bag is on the list")
        let bag = try XCTUnwrap(store.leaveItems.first { $0.id == "gymBag" })
        store.removeLeaveItem(bag)
        XCTAssertFalse(store.leaveEntries().contains { $0.id == "gymBag" }, "removed, it doesn't come back as a suggestion")
        XCTAssertEqual(store.record(LeaveItem.self, "gymBag")?.removed, true, "the removal is kept as a record")
        UndoCenter.shared.undo()
        XCTAssertNil(store.record(LeaveItem.self, "gymBag"), "Desfazer: as before, with no record")
        XCTAssertTrue(store.leaveEntries().contains { $0.id == "gymBag" })
        store.saveLeaveItem(LeaveItem(id: "mine-" + UUID().uuidString, title: "  Passe  "))
        let mine = try XCTUnwrap(store.all(LeaveItem.self).first)
        XCTAssertEqual(mine.title, "Passe")
        XCTAssertTrue(takes(mine.id), mine.id)
        store.saveLeaveItem(LeaveItem(id: "mine-empty", title: "   "))
        XCTAssertNil(store.record(LeaveItem.self, "mine-empty"), "an empty name saves nothing")
    }

    /// Regular trips, events with a place and training are the day's departures, earliest first
    @MainActor
    func testTripsEventsAndTrainingAreDepartures() throws {
        let store = try makeStore { s in
            s.add(RegularTrip(id: "R", title: "Faculdade", weekdays: [Day.weekday(Day.today)], arrive: 9 * 60, travel: 35, buffer: 10))
            s.add(PlanBlock(id: "B", date: Day.today, start: 18 * 60 + 30, minutes: 60, title: "Pernas", type: "training"))
        }
        let dentist = CalendarEvent(id: "E", title: "Dentista", start: iso.string(from: Day.at(15 * 60, on: Day.today)), end: iso.string(from: Day.at(16 * 60, on: Day.today)), allDay: false, location: "Clínica")
        let noPlace = CalendarEvent(id: "F", title: "Chamada", start: iso.string(from: Day.at(11 * 60, on: Day.today)), end: iso.string(from: Day.at(12 * 60, on: Day.today)), allDay: false)
        let list = store.leaveDepartures(events: [dentist, noPlace])
        XCTAssertEqual(list.map { $0.title }, ["Faculdade", "Dentista", "Pernas"], "an event with no place isn't a departure")
        XCTAssertEqual(list.map { $0.leave }, [8 * 60 + 15, 15 * 60 - NowRule.defaultLead, 18 * 60 + 30 - NowRule.defaultLead])
        let warning = try XCTUnwrap(store.nowDepartures(events: [dentist]).first)
        store.answerNow(warning, snooze: false, minute: 14 * 60)
        XCTAssertEqual(store.leaveDepartures(events: [dentist, noPlace]).map { $0.title }, ["Faculdade", "Pernas"], "«Já não vou»: nothing to get ready for")
    }

    // MARK: Tomorrow

    /// The gym bag packed the night before is its own record and reaches Antes de sair as packed, still to take; the
    /// training clothes drying are never offered as available
    @MainActor
    func testTheBagPackedLastNightReachesAntesDeSairAsPacked() throws {
        let tomorrow = Day.add(1, to: Day.today)
        let store = try makeStore { s in
            s.add(WorkoutTemplate(id: "T", name: "Tronco", exercises: [], weekdays: [Day.weekday(tomorrow)], minutes: 60))
            s.add(Garment(id: "K1", name: "Calções", type: "gym"))
            s.add(Garment(id: "K2", name: "T-shirt de treino", type: "gym", wearsBeforeWash: 1, wears: 1, state: "drying"))
        }
        let bag = store.bagItems(for: tomorrow)
        XCTAssertEqual(bag.items.map { $0.id }, ["g.K1", "towel", "bottle", "lock", "headphones"], "available training clothes, then the basics")
        XCTAssertEqual(bag.unavailable.map { $0.id }, ["K2"])
        store.toggleBagItem(bag.items[0], of: bag.items, for: tomorrow)
        XCTAssertEqual(store.gymBagPack(for: tomorrow)?.done, false, "one item in: not ready yet")
        store.packBag(bag.items, for: tomorrow)
        let pack = try XCTUnwrap(store.gymBagPack(for: tomorrow))
        XCTAssertTrue(pack.done)
        XCTAssertEqual(Set(pack.items), Set(bag.items.map { $0.id }))
        guard case .object? = store.records(GymBagPack.kind)[tomorrow] else { return XCTFail("the bag's value is an object") }
        let entry = try XCTUnwrap(store.leaveEntries(on: tomorrow).first { $0.id == "gymBag" })
        XCTAssertFalse(entry.seen, "packed is not taken: it stays to see")
        XCTAssertEqual(entry.state, .pending)
        XCTAssertTrue(entry.note.hasPrefix("preparado ontem às"), entry.note)
        UndoCenter.shared.undo()
        XCTAssertEqual(store.gymBagPack(for: tomorrow)?.done, false, "Desfazer: back to one item in")
    }

    /// Tomorrow's outfit only from pieces that are clean and available (2.10's stages): not one near its wash limit,
    /// not one drying. «Aceitar roupa» saves the outfit with worn false and counts no use; Desfazer takes it back; an
    /// outfit already worn that day is never replaced
    @MainActor
    func testTomorrowsOutfitOnlyFromAvailablePiecesAndChoosingCountsNoWear() throws {
        let day = Fixed.saturday
        let store = try makeStore { s in
            s.add(Garment(id: "T1", name: "T-shirt cinzenta", type: "top", wearsBeforeWash: 3, wears: 1, state: "worn"))
            s.add(Garment(id: "T2", name: "T-shirt quase no limite", type: "top", wearsBeforeWash: 3, wears: 2, state: "worn", accepted: 50))
            s.add(Garment(id: "T3", name: "T-shirt a secar", type: "top", state: "drying", accepted: 99))
            s.add(Garment(id: "B1", name: "Calças de ganga", type: "bottom"))
        }
        XCTAssertEqual(store.outfit(for: day).first?.id, "T2", "today's rule (2.10) still offers a piece below its limit")
        let pieces = store.tomorrowOutfit(day)
        XCTAssertEqual(pieces.map { $0.id }, ["T1", "B1"], "for tomorrow, only what's «Disponível»")
        let before = store.chooseOutfit(pieces, for: day)
        XCTAssertNil(before)
        let log = try XCTUnwrap(store.record(OutfitLog.self, day))
        XCTAssertFalse(log.worn, "chosen, not worn")
        XCTAssertEqual(log.items, ["T1", "B1"])
        XCTAssertEqual(store.record(Garment.self, "T1")?.wears, 1, "choosing counts no use")
        XCTAssertEqual(store.record(Garment.self, "B1")?.wears, 0)
        XCTAssertEqual(store.record(Garment.self, "B1")?.totalWears, 0)
        XCTAssertEqual(store.tomorrowOutfit(day).map { $0.id }, ["T1", "B1"], "what you chose is what shows")
        store.restoreOutfit(before, for: day)
        XCTAssertNil(store.record(OutfitLog.self, day), "Desfazer: no outfit, as before")
        store.wear([pieces[1]], on: day)
        store.chooseOutfit(pieces, for: day)
        XCTAssertEqual(store.record(OutfitLog.self, day)?.worn, true, "a worn outfit is never replaced by a choice")
    }

    /// Tomorrow's weather from the forecast's second day: the rain window and the temperatures while you're out
    func testTomorrowsWeatherFromTheForecastsSecondDay() throws {
        func hour(_ m: Int, temp: Double, rain: Double) -> HourWeather { HourWeather(minute: m, temp: temp, feels: temp, rain: rain, wind: 0, uv: 0, code: 0) }
        let wake = 7 * 60 + 15
        let hours = [hour(10 * 60, temp: 25, rain: 90)] + (8...21).map { h in hour(1440 + h * 60, temp: Double(9 + (h - 8) / 2), rain: h <= 10 ? 70 : 0) }
        let w = try XCTUnwrap(NightRules.tomorrowWeather(hours, wake: wake))
        XCTAssertTrue(w.rain)
        XCTAssertEqual(w.text, "chuva até às 11:00 · 9–15 °C")
        XCTAssertEqual(w.layers, 3)
        XCTAssertNil(NightRules.tomorrowWeather([hour(10 * 60, temp: 20, rain: 0)], wake: wake), "no hours for tomorrow: nothing")
        let dry = try XCTUnwrap(NightRules.tomorrowWeather([hour(1440 + 9 * 60, temp: 18, rain: 10)], wake: wake))
        XCTAssertEqual(dry.text, "sem chuva prevista · 18 °C")
        XCTAssertFalse(dry.rain)
        XCTAssertEqual(NightRules.tomorrowText([]), "Amanhã: nada marcado")
        XCTAssertEqual(NightRules.tomorrowText(["treino às 18:30", "saco pronto"]), "Amanhã: treino às 18:30 · saco pronto")
    }

    // MARK: The night

    /// Teeth → prepare tomorrow → read → sleep; a step with nothing to do is hidden; late, the short version at once;
    /// after «Vou dormir», nothing more (what was left isn't a failure)
    func testTheNightFollowsTheSequenceAndHidesWhatHasNothingToDo() {
        var s = NightRules.status(teeth: false, prepare: false, read: false, sleep: false)
        XCTAssertEqual(s.steps, [.teeth, .prepare, .read, .sleep])
        XCTAssertEqual(s.current, .teeth)
        s = NightRules.status(teeth: true, prepare: false, read: false, sleep: false)
        XCTAssertEqual(s.current, .prepare)
        s = NightRules.status(teeth: true, prepare: nil, read: false, sleep: false)
        XCTAssertEqual(s.steps, [.teeth, .read, .sleep], "nothing to prepare: hidden")
        XCTAssertEqual(s.current, .read)
        XCTAssertEqual(NightRules.status(teeth: nil, prepare: nil, read: nil, sleep: false).steps, [.sleep])
        XCTAssertEqual(NightRules.status(teeth: false, prepare: false, read: false, sleep: false, late: true).current, .sleep)
        XCTAssertNil(NightRules.status(teeth: true, prepare: true, read: false, sleep: true).current)
        XCTAssertEqual(NightStep.allCases.map { $0.label }, ["Dentes", "Preparar amanhã", "Ler", "Dormir"])
        XCTAssertTrue(NightRules.takesAgora(nil))
        XCTAssertTrue(NightRules.takesAgora(.routine))
        XCTAssertFalse(NightRules.takesAgora(.beforeLeaving), "Antes de sair keeps its place at night")
        XCTAssertFalse(NightRules.takesAgora(.workout(NowWorkout(id: "S", name: "Pernas", start: 0))))
    }

    /// The night runs from an hour before wind-down to two hours before waking; the short version 30 min past lights
    /// out (decision of phase 2.9); the reading suggested ends 5 min before lights out, 10 to 30 min
    func testTheNightTheShortVersionAndTheReadingFollowThePlan() {
        let windDown = 22 * 60 + 45, wake = 7 * 60 + 15, lightsOut = 23 * 60 + 15
        XCTAssertFalse(NightRules.isNight(minute: 21 * 60 + 44, windDown: windDown, wake: wake))
        XCTAssertTrue(NightRules.isNight(minute: 21 * 60 + 45, windDown: windDown, wake: wake))
        XCTAssertTrue(NightRules.isNight(minute: 60, windDown: windDown, wake: wake), "after midnight it's still the night")
        XCTAssertTrue(NightRules.isNight(minute: 5 * 60 + 14, windDown: windDown, wake: wake))
        XCTAssertFalse(NightRules.isNight(minute: 5 * 60 + 15, windDown: windDown, wake: wake))
        XCTAssertFalse(NightRules.isNight(minute: 12 * 60, windDown: windDown, wake: wake))
        XCTAssertFalse(NightRules.isLate(minute: 23 * 60 + 45, lightsOut: lightsOut))
        XCTAssertTrue(NightRules.isLate(minute: 23 * 60 + 46, lightsOut: lightsOut))
        XCTAssertTrue(NightRules.isLate(minute: 30, lightsOut: lightsOut), "0:30 counts as 24:30")
        XCTAssertTrue(NightRules.isMorning(minute: 8 * 60, wake: wake))
        XCTAssertFalse(NightRules.isMorning(minute: 11 * 60, wake: wake))
        XCTAssertEqual(NightRules.reading(minute: 21 * 60 + 58, lightsOut: 22 * 60 + 30)?.minutes, 27)
        XCTAssertEqual(NightRules.reading(minute: 21 * 60 + 58, lightsOut: 22 * 60 + 30)?.until, 22 * 60 + 25)
        XCTAssertEqual(NightRules.reading(minute: 20 * 60, lightsOut: 22 * 60 + 30)?.minutes, 30, "at most 30")
        XCTAssertNil(NightRules.reading(minute: 22 * 60 + 20, lightsOut: 22 * 60 + 30), "under 10 min: no reading planned")
        XCTAssertEqual(NightRules.shortMinutes(teeth: true, stepSeconds: 60), 3)
        XCTAssertEqual(NightRules.fallAsleep([10, 30, 15]), 15)
        XCTAssertNil(NightRules.fallAsleep([10, 12]), "too few nights: no claim")
        XCTAssertEqual(NightRules.planWhy(need: 480, fallAsleep: nil), "precisas de 8h; contamos 15 min para adormecer.")
    }

    /// The night's steps come from what you did: brushing answered, reading done, the intention
    @MainActor
    func testTheNightStepsComeFromWhatYouDid() throws {
        let brush = PromiseItem(id: "BR", title: "Brush teeth, night", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60))
        let read = PromiseItem(id: "RD", title: "Read 30 min", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60 + 15))
        let store = try makeStore { s in
            s.promises[brush.id] = brush
            s.promises[read.id] = read
        }
        let minute = 22 * 60 + 30
        XCTAssertEqual(store.nightStatus(minute: minute).steps, [.teeth, .read, .sleep], "no wardrobe and no training tomorrow: nothing to prepare")
        XCTAssertEqual(store.nightStatus(minute: minute).current, .teeth)
        store.markTeethDone(on: Day.today)
        XCTAssertEqual(store.answerOrigin(brush), .you)
        XCTAssertEqual(store.nightStatus(minute: minute).current, .read)
        UndoCenter.shared.undo()
        XCTAssertNil(store.status(brush), "Desfazer takes the answer back")
        store.markTeethDone(on: Day.today)
        store.save(ReadingSession(id: "RS", date: Day.today, start: Day.at(22 * 60 + 5, on: Day.today).timeIntervalSince1970 * 1000, minutes: 20))
        XCTAssertEqual(store.nightStatus(minute: minute).current, .sleep)
        store.goingToSleep(minute: minute, on: Day.today)
        XCTAssertNil(store.nightStatus(minute: minute).current, "after «Vou dormir», nothing more to do")
    }

    /// «Vou dormir» saves the intention alone (its own record, an object, id = the day): no habit answered, no sleep
    /// made up. Desfazer takes it back.
    @MainActor
    func testVouDormirSavesOnlyTheIntention() throws {
        let lightsOut = PromiseItem(id: "L1", title: "Lights out", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 23 * 60))
        let store = try makeStore { $0.promises[lightsOut.id] = lightsOut }
        store.goingToSleep(minute: 22 * 60 + 33, on: Fixed.sunday)
        let intent = try XCTUnwrap(store.sleepIntent(Fixed.sunday))
        XCTAssertEqual(intent.id, Fixed.sunday)
        XCTAssertEqual(intent.minute, 22 * 60 + 33)
        guard case .object? = store.records(SleepIntent.kind)[Fixed.sunday] else { return XCTFail("the intention's value is an object") }
        XCTAssertNil(store.status(lightsOut, on: Fixed.sunday), "not an answer to the bedtime habit")
        XCTAssertTrue(store.health.isEmpty, "and no sleep is made up")
        UndoCenter.shared.undo()
        XCTAssertNil(store.sleepIntent(Fixed.sunday), "Desfazer takes it back")
    }

    /// The reading planned and the reading done are different records: planning reads nothing, reading changes no plan
    @MainActor
    func testReadingPlannedAndDoneAreDifferentRecords() throws {
        let store = try makeStore()
        store.planReading(minutes: 25, from: 22 * 60, on: Fixed.sunday)
        let plan = try XCTUnwrap(store.record(ReadingPlan.self, Fixed.sunday))
        XCTAssertEqual(plan.until, 22 * 60 + 25)
        XCTAssertTrue(store.all(ReadingSession.self).isEmpty, "planned is not read")
        XCTAssertEqual(store.readingMinutes(on: Fixed.sunday), 0)
        store.save(ReadingSession(id: "RS", date: Fixed.sunday, minutes: 27))
        XCTAssertEqual(store.record(ReadingPlan.self, Fixed.sunday)?.minutes, 25, "the reading done doesn't change the plan")
        XCTAssertEqual(store.readingMinutes(on: Fixed.sunday), 27)
        guard case .object? = store.records(ReadingPlan.kind)[Fixed.sunday] else { return XCTFail("the plan's value is an object") }
    }

    /// «O dia»: imported apart from yours, past their time with no answer as «por confirmar» (never «não feito»), and no
    /// water or food logged as no data
    @MainActor
    func testTheDaySummaryKeepsImportedApartAndNeverSaysNotDone() throws {
        let walk = PromiseItem(id: "W1", title: "10k steps", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 9 * 60))
        let shake = PromiseItem(id: "S1", title: "Batido", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 17 * 60))
        let creatine = PromiseItem(id: "C1", title: "Creatina", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 20 * 60))
        let store = try makeStore { s in
            for p in [walk, shake, creatine] { s.promises[p.id] = p }
            s.health[Day.today] = HealthDay(date: Day.today, steps: 20000)
        }
        store.autoComplete()
        store.log(shake, .done)
        let s = store.nightDaySummary(on: Day.today, minute: 22 * 60)
        XCTAssertEqual(s.imported, ["10k steps"])
        XCTAssertEqual(s.yours, ["Batido"])
        XCTAssertEqual(s.open, ["Creatina"])
        XCTAssertTrue(s.noWater)
        XCTAssertTrue(s.noFood)
    }

    // MARK: Answered is not done (audit B3-E3 and M7)

    /// How a step ended: done when you did it, or answered «feito»; with every habit answered and none done, «Não se
    /// aplica» if all were, otherwise «Não fiz»; nil while one is open. A tag for what wasn't done, none for what was.
    func testAStepsOutcomeFollowsWhatYouDidAndTheAnswers() {
        XCTAssertEqual(NightRules.outcome(did: true, answers: [.notDone]), .done, "brushed after all: done, whatever the habit said")
        XCTAssertEqual(NightRules.outcome(did: true, answers: []), .done, "brushed with no habit")
        XCTAssertEqual(NightRules.outcome(did: false, answers: [.done, .notDone]), .done)
        XCTAssertEqual(NightRules.outcome(did: false, answers: [.notDone]), .notDone)
        XCTAssertEqual(NightRules.outcome(did: false, answers: [.notApplicable]), .notApplicable)
        XCTAssertEqual(NightRules.outcome(did: false, answers: [.notApplicable, .notDone]), .notDone)
        XCTAssertNil(NightRules.outcome(did: false, answers: [.done, .notConfirmed]), "one still open: not resolved")
        XCTAssertNil(NightRules.outcome(did: false, answers: []))
        XCTAssertEqual(NightRules.skipTag(.notDone)?.text, "Não fiz")
        XCTAssertEqual(NightRules.skipTag(.notDone)?.state, .ignored)
        XCTAssertEqual(NightRules.skipTag(.notApplicable)?.text, "Não se aplica")
        XCTAssertEqual(NightRules.skipTag(.notApplicable)?.state, .unavailable)
        XCTAssertNil(NightRules.skipTag(.done), "done shows as done")
        XCTAssertNil(NightRules.skipTag(nil))
    }

    /// A teeth habit answered «Não fiz» or «Não se aplica»: the sequence moves on, but it's said as it was answered,
    /// never «feito»
    @MainActor
    func testATeethHabitSkippedMovesTheNightOnButIsNeverDone() throws {
        let brush = PromiseItem(id: "BR", title: "Brush teeth, night", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60))
        let store = try makeStore { $0.promises[brush.id] = brush }
        let minute = 22 * 60 + 30
        XCTAssertEqual(store.nightStatus(minute: minute).current, .teeth)
        store.log(brush, on: Day.today, .skipped)
        var status = store.nightStatus(minute: minute)
        XCTAssertNotEqual(status.current, .teeth, "the sequence moves on with any answer")
        XCTAssertEqual(status.skipped[.teeth], .notDone)
        XCTAssertEqual(status.spoken(.teeth), "Dentes, não fiz", "what VoiceOver says")
        XCTAssertEqual(store.nightTeethAnswer(on: Day.today), .notDone)
        store.log(brush, on: Day.today, .skipped, notApplicable: true)
        status = store.nightStatus(minute: minute)
        XCTAssertNotEqual(status.current, .teeth)
        XCTAssertEqual(status.skipped[.teeth], .notApplicable)
        XCTAssertEqual(status.spoken(.teeth), "Dentes, não se aplica")
        store.log(brush, on: Day.today, .done)
        status = store.nightStatus(minute: minute)
        XCTAssertNil(status.skipped[.teeth])
        XCTAssertEqual(status.spoken(.teeth), "Dentes, feito")
    }

    /// The same for a reading habit; and a reading done that night counts as done, even after a «Não fiz»
    @MainActor
    func testAReadingHabitSkippedIsNeverDoneUnlessYouRead() throws {
        let read = PromiseItem(id: "RD", title: "Read 30 min", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60 + 15))
        let store = try makeStore { $0.promises[read.id] = read }
        let day = Fixed.saturday
        XCTAssertEqual(store.nightRead(on: day), false, "still open")
        XCTAssertNil(store.nightReadAnswer(on: day))
        store.log(read, on: day, .skipped, notApplicable: true)
        XCTAssertEqual(store.nightRead(on: day), true, "resolved: the sequence moves on")
        XCTAssertEqual(store.nightReadAnswer(on: day), .notApplicable)
        store.log(read, on: day, .skipped)
        XCTAssertEqual(store.nightReadAnswer(on: day), .notDone)
        store.save(ReadingSession(id: "RS", date: day, start: Day.at(22 * 60, on: day).timeIntervalSince1970 * 1000, minutes: 20))
        XCTAssertEqual(store.nightReadAnswer(on: day), .done, "you read after all")
    }

    /// In the morning a bedtime habit answered «Não fiz» is said as that, never «Confirmado»; no source is still no label
    func testABedtimeHabitAnsweredNotDoneIsNotConfirmed() {
        XCTAssertEqual(NightRules.answerTag(.you, .done)?.state, .confirmed)
        XCTAssertNil(NightRules.answerTag(.you, .done)?.text, "the state's own word")
        XCTAssertEqual(NightRules.answerTag(.imported("fitbit"), .done)?.state, .imported)
        XCTAssertEqual(NightRules.answerTag(.you, .notDone)?.state, .ignored)
        XCTAssertEqual(NightRules.answerTag(.you, .notDone)?.text, "Não fiz")
        XCTAssertEqual(NightRules.answerTag(.you, .notApplicable)?.state, .unavailable)
        XCTAssertEqual(NightRules.answerTag(.you, .notApplicable)?.text, "Não se aplica")
        XCTAssertNil(NightRules.answerTag(.unknown, .notDone), "no source: no label, as before")
        XCTAssertNil(NightRules.answerTag(nil, .notConfirmed))
    }

    // MARK: After midnight the night still belongs to the evening before (audit B3-E4)

    /// On the night's day from 14:00 (teeth) or 18:00 (reading), or on the next day before the morning: your wake time,
    /// or 05:00 without one. Neither the evening before the night nor the next evening.
    func testWhatYouDoCountsForTheNightInItsWindow() {
        let night = Fixed.saturday, next = Fixed.sunday, wake = 7 * 60 + 15
        let teeth = { (date: String, minute: Int) -> Bool in NightRules.inNight(date: date, minute: minute, night: night, from: NightRules.teethFrom, wake: wake) }
        XCTAssertEqual(NightRules.teethFrom, 14 * 60)
        XCTAssertEqual(NightRules.readFrom, 18 * 60)
        XCTAssertFalse(teeth(night, 14 * 60 - 1))
        XCTAssertTrue(teeth(night, 14 * 60))
        XCTAssertTrue(teeth(night, 23 * 60 + 59))
        XCTAssertTrue(teeth(next, 30), "0:30 belongs to the night")
        XCTAssertTrue(teeth(next, wake - 1))
        XCTAssertFalse(teeth(next, wake), "from the wake time on it's the morning")
        XCTAssertFalse(teeth(Day.add(-1, to: night), 23 * 60), "the evening before isn't this night")
        XCTAssertFalse(teeth(Day.add(2, to: night), 30))
        XCTAssertFalse(NightRules.inNight(date: night, minute: 18 * 60 - 1, night: night, from: NightRules.readFrom, wake: wake), "reading from 18:00")
        XCTAssertTrue(NightRules.inNight(date: night, minute: 18 * 60, night: night, from: NightRules.readFrom, wake: wake))
        XCTAssertTrue(NightRules.inNight(date: next, minute: 5 * 60 - 1, night: night, from: NightRules.teethFrom, wake: nil), "no wake time: until 05:00")
        XCTAssertFalse(NightRules.inNight(date: next, minute: 5 * 60, night: night, from: NightRules.teethFrom, wake: nil))
    }

    /// A brushing and a reading at 0:30 count for the night that started the evening before, up to your wake time, and
    /// not for the evening of the day they fall on
    @MainActor
    func testBrushingAndReadingAtHalfPastMidnightCountForTheNight() throws {
        let night = Fixed.saturday, next = Fixed.sunday
        let brush = PromiseItem(id: "BR", title: "Brush teeth, night", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60))
        let read = PromiseItem(id: "RD", title: "Read 30 min", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60 + 15))
        let store = try makeStore { s in
            s.promises[brush.id] = brush
            s.promises[read.id] = read
            s.profile.wakeMinute = 6 * 60
        }
        XCTAssertEqual(store.nightTeeth(on: night), false)
        XCTAssertEqual(store.nightRead(on: night), false)
        store.save(BrushLog(id: "B1", date: next, minute: 30, seconds: 120))
        store.save(ReadingSession(id: "RS", date: next, start: Day.at(35, on: next).timeIntervalSince1970 * 1000, minutes: 20))
        XCTAssertEqual(store.nightTeeth(on: night), true, "brushed at 0:30")
        XCTAssertEqual(store.nightTeethAnswer(on: night), .done)
        XCTAssertEqual(store.nightBrushMinute(on: night), 24 * 60 + 30, "on the evening's clock")
        XCTAssertEqual(store.nightRead(on: night), true, "read at 0:35")
        XCTAssertEqual(store.nightReadAnswer(on: night), .done)
        XCTAssertEqual(store.nightTeeth(on: next), false, "0:30 isn't the evening of that day")
        XCTAssertEqual(store.nightRead(on: next), false)
        let wake = try makeStore { s in
            s.promises[brush.id] = brush
            s.profile.wakeMinute = 6 * 60
            s.add(BrushLog(id: "B2", date: next, minute: 6 * 60, seconds: 120))
        }
        XCTAssertEqual(wake.nightTeeth(on: night), false, "at the wake time it's a morning brushing, by your wake time and not 7:15")
    }

    /// At 0:30 the night's status sees the brushing and the reading done since midnight
    @MainActor
    func testTheNightsStatusAtHalfPastMidnightSeesWhatYouDidThen() throws {
        let brush = PromiseItem(id: "BR", title: "Brush teeth, night", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60))
        let read = PromiseItem(id: "RD", title: "Read 30 min", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60 + 15))
        let store = try makeStore { s in
            s.promises[brush.id] = brush
            s.promises[read.id] = read
        }
        XCTAssertFalse(store.nightStatus(minute: 30).done.contains(.teeth))
        XCTAssertFalse(store.nightStatus(minute: 30).done.contains(.read))
        store.save(BrushLog(id: "B1", date: Day.today, minute: 30, seconds: 120))
        store.save(ReadingSession(id: "RS", date: Day.today, start: Day.at(20, on: Day.today).timeIntervalSince1970 * 1000, minutes: 20))
        let status = store.nightStatus(minute: 30)
        XCTAssertTrue(status.done.contains(.teeth), "brushed since midnight")
        XCTAssertTrue(status.done.contains(.read), "read since midnight")
        XCTAssertEqual(status.spoken(.teeth), "Dentes, feito")
    }

    /// The brushing timer used after midnight and before you wake answers the evening's open habit, as yours, and not
    /// today's; with that one answered, or past the wake time, the rule is today's habit within 3 h, as before
    @MainActor
    func testTheBrushingTimerAfterMidnightAnswersTheEveningsHabit() throws {
        let night = Fixed.saturday, next = Fixed.sunday
        let brush = PromiseItem(id: "BR", title: "Brush teeth, night", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60))
        let morning = PromiseItem(id: "BM", title: "Brush teeth, morning", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 7 * 60 + 30))
        let store = try makeStore { s in
            s.promises[brush.id] = brush
            s.promises[morning.id] = morning
        }
        var target = try XCTUnwrap(store.brushingHabit(minute: 6 * 60, today: next))
        XCTAssertEqual(target.promise.id, "BR", "before you wake, the night's habit first, though the morning's is within 3 h")
        XCTAssertEqual(target.day, night)
        store.saveBrushing(BrushLog(id: "B1", date: next, minute: 30, seconds: 120))
        XCTAssertNotNil(store.record(BrushLog.self, "B1"), "the brushing itself is saved")
        XCTAssertEqual(store.status(brush, on: night), .done, "the evening's habit")
        XCTAssertEqual(store.answerOrigin(brush, on: night), .you)
        XCTAssertNil(store.status(brush, on: next), "not today's")
        XCTAssertNil(store.status(morning, on: next))
        target = try XCTUnwrap(store.brushingHabit(minute: 6 * 60, today: next))
        XCTAssertEqual(target.promise.id, "BM", "the night's answered: today's within 3 h, as before")
        XCTAssertEqual(target.day, next)
        XCTAssertNil(store.brushingHabit(minute: 30, today: next), "nothing open and nothing within 3 h")
        let evening = try XCTUnwrap(store.brushingHabit(minute: 22 * 60 + 30, today: next))
        XCTAssertEqual(evening.promise.id, "BR", "in the evening, today's habit")
        XCTAssertEqual(evening.day, next)
        let later = try makeStore { $0.promises[brush.id] = brush }
        XCTAssertNil(later.brushingHabit(minute: later.profile.wakeMinute, today: next), "from the wake time on the evening's habit is left as it is")
    }

    // MARK: Desfazer's restores (validation C-L2)

    /// restoreLeaveDay: puts the day back exactly as it was, or removes it if there was none; with none and nothing
    /// there it adds nothing
    @MainActor
    func testRestoreLeaveDayPutsTheDayBackOrRemovesIt() throws {
        let store = try makeStore()
        let day = Fixed.monday
        store.restoreLeaveDay(nil, day: day)
        XCTAssertNil(store.records(LeaveDay.kind)[day], "nothing there: nothing added")
        let before = LeaveDay(id: day, date: day, seen: ["keys"], at: 3)
        store.save(LeaveDay(id: day, date: day, seen: ["keys", "umbrella"], ready: 9, closed: true, at: 9))
        store.restoreLeaveDay(before, day: day)
        XCTAssertEqual(store.leaveDay(day), before, "as it was before: not merged with what came after")
        store.restoreLeaveDay(nil, day: day)
        XCTAssertNil(store.leaveDay(day), "there was none before: gone")
        XCTAssertNil(store.records(LeaveDay.kind)[day])
    }

    /// restoreLeaveItem: an edit to one of the app's three goes back to the code's version; one of yours to what it was
    @MainActor
    func testRestoreLeaveItemPutsTheItemBackOrRemovesIt() throws {
        let store = try makeStore()
        var keys = LeaveRules.builtIns[0]
        keys.title = "Chaves"
        store.save(keys)
        XCTAssertEqual(store.leaveItems.first?.title, "Chaves")
        store.restoreLeaveItem(nil, id: "keys")
        XCTAssertNil(store.record(LeaveItem.self, "keys"), "no record before: none now")
        XCTAssertEqual(store.leaveItems.first?.title, "Chaves e carteira")
        let before = LeaveItem(id: "mine-pass", title: "Passe", at: 1)
        store.save(LeaveItem(id: "mine-pass", title: "Passe do metro", removed: true, at: 2))
        XCTAssertFalse(store.leaveItems.contains { $0.id == "mine-pass" })
        store.restoreLeaveItem(before, id: "mine-pass")
        XCTAssertEqual(store.record(LeaveItem.self, "mine-pass"), before)
        XCTAssertTrue(store.leaveItems.contains { $0.id == "mine-pass" }, "back on the list")
    }

    /// restoreBag: the bag as it was, or none if there was none
    @MainActor
    func testRestoreBagPutsTheBagBackOrRemovesIt() throws {
        let store = try makeStore()
        let day = Fixed.monday
        store.restoreBag(nil, day: day)
        XCTAssertNil(store.records(GymBagPack.kind)[day], "nothing there: nothing added")
        let before = GymBagPack(id: day, date: day, items: ["towel"], done: false, at: 5)
        store.save(GymBagPack(id: day, date: day, items: ["towel", "bottle"], done: true, at: 9))
        store.restoreBag(before, day: day)
        XCTAssertEqual(store.gymBagPack(for: day), before)
        store.restoreBag(nil, day: day)
        XCTAssertNil(store.gymBagPack(for: day), "there was none before: gone")
        XCTAssertNil(store.records(GymBagPack.kind)[day])
    }

    /// The reminder at the time to leave is on unless you turn it off. (The scheduling itself is inside Reminders'
    /// private rebuild, on the shared store and the notification centre: not testable without changing it.)
    func testTheLeaveReminderIsOnUnlessYouTurnItOff() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: LeaveRules.reminderKey)
        defer { defaults.set(saved, forKey: LeaveRules.reminderKey) }
        defaults.removeObject(forKey: LeaveRules.reminderKey)
        XCTAssertTrue(LeaveRules.reminderOn, "on by default")
        defaults.set(false, forKey: LeaveRules.reminderKey)
        XCTAssertFalse(LeaveRules.reminderOn)
    }

    // MARK: The morning

    /// Where an answer came from, as its label: imported, yours, or no label at all for an unknown source
    func testAnAnswersLabelFollowsItsSource() {
        XCTAssertEqual(NightRules.answerState(.imported("fitbit")), .imported)
        XCTAssertEqual(NightRules.answerState(.you), .confirmed)
        XCTAssertNil(NightRules.answerState(.unknown), "no source: no label, never confirmed")
        XCTAssertNil(NightRules.answerState(nil))
    }

    /// Hours typed in the morning are read only when they're clear: an hour is never guessed
    func testHoursAreNeverGuessed() {
        XCTAssertEqual(NightRules.parseClock("23:00"), 23 * 60)
        XCTAssertEqual(NightRules.parseClock("23h05"), 23 * 60 + 5)
        XCTAssertEqual(NightRules.parseClock("23h"), 23 * 60)
        XCTAssertEqual(NightRules.parseClock("0715"), 7 * 60 + 15)
        XCTAssertEqual(NightRules.parseClock("715"), 7 * 60 + 15)
        XCTAssertEqual(NightRules.parseClock(" 7 "), 7 * 60)
        for bad in ["", "ab", "24:00", "7:60", "12345", "7:3a"] { XCTAssertNil(NightRules.parseClock(bad), bad) }
        XCTAssertEqual(NightRules.span(bed: 23 * 60, wake: 7 * 60 + 10), 8 * 60 + 10)
    }

    /// «Corrigir» saves the hours as yours, next to the band's sleep, which never changes; Desfazer takes them back
    @MainActor
    func testCorrigirSavesTheHoursAsYoursNextToTheBand() throws {
        let band = SleepRecord(start: iso.string(from: Day.at(-69, on: Day.today)), end: iso.string(from: Day.at(7 * 60 + 9, on: Day.today)), asleep: 458)
        let store = try makeStore { $0.health[Day.today] = HealthDay(date: Day.today, sleep: band) }
        XCTAssertNil(store.sleepManual(Day.today), "nothing of yours until you save")
        XCTAssertEqual(store.sleepSourceName, "Fitbit", "the band's source in sight")
        store.saveSleepManual(bed: 22 * 60 + 40, wake: 7 * 60, on: Day.today)
        let mine = try XCTUnwrap(store.sleepManual(Day.today))
        XCTAssertEqual(mine.source, PromiseLog.byYou)
        XCTAssertEqual(mine.bed, 22 * 60 + 40)
        XCTAssertEqual(store.health[Day.today]?.sleep, band, "the band's sleep is never changed")
        UndoCenter.shared.undo()
        XCTAssertNil(store.sleepManual(Day.today))
    }
}
