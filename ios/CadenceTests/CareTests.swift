// Phase 2.5 · Higiene: routines kept by day and step, the routine of the moment, confirming with Desfazer, frequencies
// and the learned interval as a suggestion, products and their estimate, and «Adicionar às compras». Synthetic data
// only; Store-backed tests use RegressionCase.makeStore (no server, own file). Fixed dates where the code takes a day.
import XCTest
@testable import Cadence

private enum CareFixture {
    static let morning = CareRoutine(id: "RM", title: "Rotina da manhã", icon: "sun.max", steps: [RoutineStep(id: "RM1", title: "Lavar os dentes", seconds: 120),
                                                                                                RoutineStep(id: "RM2", title: "Lavar a cara", seconds: 60, productId: "PB")])
    static let night = CareRoutine(id: "RN", title: "Rotina da noite", icon: "moon.stars", steps: [RoutineStep(id: "RN1", title: "Lavar a cara", seconds: 60, productId: "PB"),
                                                                                              RoutineStep(id: "RN2", title: "Lavar os dentes", seconds: 120)])
    static let product = CareProduct(id: "PB", name: "Bioderma Sébium Gel Moussant", size: 200, perUse: 2)
    static let beard = GroomingItem(id: "G1", title: "Aparar a barba", interval: 7, history: ["2026-10-01", "2026-10-08", "2026-10-16"])
}

/// A time on a day, as the records keep it (ms since 1970)
private func ms(_ minute: Int, _ day: String) -> Double { Day.at(minute, on: day).timeIntervalSince1970 * 1000 }

private func serverTakes(_ id: String) -> Bool {
    id.range(of: "^[A-Za-z0-9_.:-]{1,80}$", options: .regularExpression) != nil
}

final class CareTests: RegressionCase {
    // MARK: Routines kept by day and step

    func testARoutineLogIdIsTheRoutineAndTheDayInTheServersCharacters() {
        let uuid = "6F1C2A3B-4D5E-4F60-8A7B-9C0D1E2F3A4B"
        XCTAssertEqual(CareRules.logId(routine: uuid, day: Fixed.saturday), uuid + "_2026-11-07", "the ids the app makes stay as they are")
        XCTAssertEqual(CareRules.logId(routine: "RM", day: Fixed.saturday), "RM_2026-11-07")
        let odd = ["rotina da manhã", "rotina/da/manhã", String(repeating: "x", count: 120), "a b"]
        let ids = odd.map { CareRules.logId(routine: $0, day: Fixed.saturday) }
        for id in ids {
            XCTAssertTrue(serverTakes(id), "\(id) is an id the server skips")
            XCTAssertTrue(id.hasSuffix("_2026-11-07"), id)
        }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertNotEqual(CareRules.logId(routine: "a b", day: Fixed.saturday), CareRules.logId(routine: "a-b", day: Fixed.saturday), "cleaned ids never collide")
        XCTAssertNotEqual(CareRules.logId(routine: "RM", day: Fixed.saturday), CareRules.logId(routine: "RM", day: Fixed.sunday), "one log per day")
    }

    func testMorningUntilTwoAndNightFromThenUnlessTheRoutineHasItsOwnTime() {
        XCTAssertEqual(CareRules.moment(at: 7 * 60), .morning)
        XCTAssertEqual(CareRules.moment(at: 13 * 60 + 59), .morning)
        XCTAssertEqual(CareRules.moment(at: 14 * 60), .night)
        XCTAssertEqual(CareRules.moment(at: 23 * 60 + 30), .night)
        XCTAssertEqual(CareRules.moment(of: CareFixture.morning), .morning)
        XCTAssertEqual(CareRules.moment(of: CareFixture.night), .night)
        XCTAssertEqual(CareRules.moment(of: CareRoutine(title: "Morning", icon: "sun.max", steps: [])), .morning, "seeded before phase 2.3")
        XCTAssertEqual(CareRules.moment(of: CareRoutine(title: "Night skincare", icon: "moon.stars", steps: [])), .night)
        XCTAssertEqual(CareRules.moment(of: CareRoutine(title: "Antes de dormir", steps: [])), .night)
        XCTAssertNil(CareRules.moment(of: CareRoutine(title: "Antes de sair", steps: [])), "no moment: it never shows in «Agora»")
        var early = CareFixture.night
        early.minute = 9 * 60
        XCTAssertEqual(CareRules.moment(of: early), .morning, "its own time wins over the name")
        var skin = CareRoutine(title: "Pele", steps: [])
        skin.minute = 21 * 60
        XCTAssertEqual(CareRules.moment(of: skin), .night)
    }

    @MainActor
    func testStepsAreConfirmedOneAtATimeOrAllAtOnceAndDesfazerPutsTheDayBack() throws {
        let m = CareFixture.morning, n = CareFixture.night
        let store = try makeStore { s in
            s.add(m)
            s.add(n)
        }
        let day = Fixed.saturday
        XCTAssertEqual(store.pendingSteps(m, on: day).map(\.id), ["RM1", "RM2"])
        XCTAssertNil(store.routineLog(m, on: day), "nothing on record before you confirm")
        let t1 = ms(8 * 60, day)
        let before1 = store.confirmSteps(["RM1": t1], of: m, on: day)
        XCTAssertNil(before1)
        XCTAssertEqual(store.routineLog(m, on: day)?.id, "RM_2026-11-07")
        XCTAssertEqual(store.doneSteps(m, on: day), ["RM1": t1])
        XCTAssertEqual(store.pendingSteps(m, on: day).map(\.id), ["RM2"])
        // «Já fiz os dois»: both at once; the one already confirmed keeps its time
        let t2 = ms(8 * 60 + 5, day)
        let before2 = store.confirmSteps(["RM1": t2, "RM2": t2], of: m, on: day)
        XCTAssertEqual(before2?.steps, ["RM1": t1])
        XCTAssertEqual(store.doneSteps(m, on: day), ["RM1": t1, "RM2": t2])
        XCTAssertTrue(store.pendingSteps(m, on: day).isEmpty)
        XCTAssertEqual(store.pendingSteps(n, on: day).count, 2, "the night counts apart")
        // Desfazer: back to how it was, then to nothing at all
        store.restoreRoutineLog(before2, routine: m, on: day)
        XCTAssertEqual(store.doneSteps(m, on: day), ["RM1": t1])
        store.restoreRoutineLog(before1, routine: m, on: day)
        XCTAssertNil(store.routineLog(m, on: day))
        // only the routine's own steps, and the value is an object, as the server takes
        store.confirmSteps(["RM2": t2, "XX": t2], of: m, on: day)
        XCTAssertEqual(Array(store.doneSteps(m, on: day).keys), ["RM2"])
        let id = CareRules.logId(routine: "RM", day: day)
        XCTAssertTrue(serverTakes(id))
        guard case .object(let value)? = store.records(RoutineLog.kind)[id] else { return XCTFail("the value must be an object") }
        XCTAssertNotNil(value["steps"])
    }

    @MainActor
    func testNaoFizTakesOneStepBackAndTheLogGoesWhenNothingIsLeft() throws {
        let m = CareFixture.morning
        let store = try makeStore { $0.add(m) }
        let day = Fixed.saturday
        store.confirmSteps(["RM1": ms(8 * 60, day), "RM2": ms(8 * 60 + 1, day)], of: m, on: day)
        let before = store.unconfirmStep("RM2", of: m, on: day)
        XCTAssertEqual(before?.steps.count, 2)
        XCTAssertEqual(store.pendingSteps(m, on: day).map(\.id), ["RM2"])
        store.unconfirmStep("RM1", of: m, on: day)
        XCTAssertNil(store.routineLog(m, on: day), "nothing left: the record goes")
        store.restoreRoutineLog(before, routine: m, on: day)
        XCTAssertEqual(store.doneSteps(m, on: day).count, 2, "Desfazer brings both back")
    }

    @MainActor
    func testTheRoutineOfTheMomentStaysPendingUntilYouConfirmIt() throws {
        let m = CareFixture.morning, n = CareFixture.night
        let store = try makeStore { s in
            s.add(m)
            s.add(n)
            s.add(CareRoutine(id: "RS", title: "Antes de sair", steps: [RoutineStep(id: "RS1", title: "Chaves", seconds: 10)]))
        }
        let day = Fixed.saturday
        XCTAssertEqual(store.routineDueNow(minute: 8 * 60, day: day)?.id, "RM")
        XCTAssertEqual(store.routineDueNow(minute: 22 * 60, day: day)?.id, "RN", "from 14:00, the night's")
        // the morning went by without a confirmation: it stays pending, nothing is marked for you
        XCTAssertEqual(store.pendingSteps(m, on: day).count, 2)
        XCTAssertTrue(store.records(RoutineLog.kind).isEmpty, "the hour passing writes nothing")
        store.confirmSteps(["RN1": ms(22 * 60, day), "RN2": ms(22 * 60, day)], of: n, on: day)
        XCTAssertNil(store.routineDueNow(minute: 22 * 60, day: day), "all done: nothing left for the moment")
        XCTAssertEqual(store.routineDueNow(minute: 8 * 60, day: day)?.id, "RM", "morning and night count apart")
        XCTAssertEqual(store.routineDueNow(minute: 22 * 60, day: Fixed.sunday)?.id, "RN", "a new day starts with nothing confirmed")
        store.update { $0.areasOff = ["care"] }
        XCTAssertNil(store.routineDueNow(minute: 8 * 60, day: day), "Higiene switched off: nothing for «Agora»")
    }

    /// Phase 2.5 (from the notes at the end of RegressionPlannedChangeTests): the routine player saved nothing at the
    /// end. Now the steps you went through are saved once, at the end, in the record Higiene and Hoje show; a skipped
    /// step stays pending.
    @MainActor
    func testThePlayerSavesWhatYouDidAtTheEnd() throws {
        let n = CareFixture.night
        let store = try makeStore { $0.add(n) }
        var play = RoutinePlayback(steps: n.steps)
        let t = ms(22 * 60, Day.today)
        play.complete(at: t)
        XCTAssertFalse(play.finished)
        XCTAssertTrue(store.records(RoutineLog.kind).isEmpty, "nothing is saved before the end")
        play.skip()
        XCTAssertTrue(play.finished)
        XCTAssertEqual(play.done, ["RN1": t], "a skipped step isn't done")
        store.confirmSteps(play.done, of: n) // what RoutinePlayer does at the end
        XCTAssertEqual(store.doneSteps(n), ["RN1": t])
        XCTAssertEqual(store.pendingSteps(n).map(\.id), ["RN2"])
        play.skip()
        play.complete()
        XCTAssertEqual(play.index, 2, "nothing past the end")
    }

    // MARK: Frequencies

    func testTheLearnedIntervalIsOnlyASuggestion() {
        var beard = CareFixture.beard
        XCTAssertEqual(beard.learned, 8, "gaps of 7 and 8 days")
        XCTAssertEqual(beard.rhythm, 7, "what's set stays until you accept")
        XCTAssertEqual(beard.suggestedInterval, 8)
        XCTAssertTrue(beard.isDue(on: "2026-10-23"), "7 days after the last time")
        XCTAssertFalse(beard.isDue(on: "2026-10-22"))
        beard.interval = 8
        XCTAssertNil(beard.suggestedInterval, "accepted: nothing more to suggest")
        beard.weekdays = [7]
        XCTAssertNil(beard.suggestedInterval, "fixed days: no interval to suggest")
        XCTAssertNil(GroomingItem(id: "G2", title: "Cortar o cabelo", interval: 35, history: ["2026-10-01", "2026-10-30"]).suggestedInterval, "fewer than three times")
    }

    @MainActor
    func testAcceptingTheSuggestionChangesTheIntervalAndDesfazerPutsItBack() throws {
        let beard = CareFixture.beard
        let store = try makeStore { $0.add(beard) }
        XCTAssertEqual(store.record(GroomingItem.self, "G1")?.interval, 7, "nothing changes by itself")
        let before = try XCTUnwrap(store.acceptInterval(8, for: beard))
        XCTAssertEqual(store.record(GroomingItem.self, "G1")?.interval, 8)
        store.save(before)
        XCTAssertEqual(store.record(GroomingItem.self, "G1"), beard)
        // Concluído starts the interval again from that day, once a day
        let undone = try XCTUnwrap(store.markGroomingDone(beard, on: Fixed.saturday))
        XCTAssertEqual(store.record(GroomingItem.self, "G1")?.last, Fixed.saturday)
        XCTAssertNil(store.markGroomingDone(beard, on: Fixed.saturday), "already done that day")
        store.save(undone)
        XCTAssertEqual(store.record(GroomingItem.self, "G1"), beard)
    }

    func testFixedDaysAreDueOnTheirDaysUntilDone() {
        // Monday, Wednesday and Friday; done on Monday 2 November
        let floss = GroomingItem(id: "F", title: "Fio dentário", interval: 2, history: [Fixed.monday], weekdays: [2, 4, 6])
        XCTAssertFalse(floss.isDue(on: Fixed.tuesday), "Tuesday isn't one of the days")
        XCTAssertTrue(floss.isDue(on: Fixed.wednesday))
        XCTAssertTrue(floss.isDue(on: "2026-11-05"), "Thursday: Wednesday's is still pending, never marked for you")
        var done = floss
        done.history.append(Fixed.wednesday)
        XCTAssertFalse(done.isDue(on: "2026-11-05"))
        XCTAssertTrue(done.isDue(on: Fixed.friday))
        XCTAssertEqual(floss.rhythm, 2, "about 7 ÷ 3")
        XCTAssertEqual(CareRules.frequencyText(floss), "seg, qua, sex")
        let beard = GroomingItem(title: "Aparar a barba", interval: 7)
        XCTAssertEqual(CareRules.frequencyText(beard), "a cada 7 dias")
        XCTAssertTrue(beard.isDue(on: Fixed.monday), "never registered is due, as before")
        XCTAssertNil(CareRules.sinceText(beard, today: Fixed.monday))
        XCTAssertEqual(CareRules.sinceText(floss, today: Fixed.monday), "hoje")
        XCTAssertEqual(CareRules.sinceText(floss, today: Fixed.saturday), "há 5 dias")
    }

    func testConsistencyCountsFullAndPartialDaysAndNoDataIsNeither() {
        let c = CareRules.consistency(steps: ["a", "b"], days: [["a": 1, "b": 2], ["a": 1], [:], ["b": 3, "x": 4], [:]])
        XCTAssertEqual(c.full, 1)
        XCTAssertEqual(c.partial, 2, "the empty days count for neither")
        XCTAssertEqual(CareRules.consistency(steps: [], days: [["a": 1]]).full, 0)
    }

    // MARK: Products and the shopping list

    func testTheRefillEstimateComesFromTheUsesYouConfirmed() throws {
        let now = ms(12 * 60, Fixed.sunday)
        var uses: [Double] = [] // twice a day for the 7 days before: 14 uses over 8 days
        for i in 1...7 {
            let d = Day.add(-i, to: Fixed.sunday)
            uses += [ms(8 * 60, d), ms(22 * 60, d)]
        }
        var p = CareProduct(id: "P", name: "Gel", size: 200, perUse: 2)
        let full = try XCTUnwrap(CareRules.refill(p, uses: uses, now: now))
        XCTAssertEqual(full, CareRules.Refill(days: 49, low: 33, high: 66), "172 ml left at 3.5 ml a day")
        // «Pouco», said yesterday at noon: one use since
        p.left = 0.2
        p.leftAt = ms(12 * 60, Fixed.saturday)
        let little = try XCTUnwrap(CareRules.refill(p, uses: uses, now: now))
        XCTAssertEqual(little.days, 11, "38 ml left")
        XCTAssertLessThanOrEqual(little.days, CareRules.refillWithin, "soon enough to suggest the shopping list")
        p.left = 0.5
        XCTAssertGreaterThan(try XCTUnwrap(CareRules.refill(p, uses: uses, now: now)).days, CareRules.refillWithin, "«Metade» puts it further away")
        // a pack started on Thursday counts only the uses since
        p.left = nil
        p.leftAt = nil
        p.startedAt = ms(0, "2026-11-05")
        XCTAssertEqual(try XCTUnwrap(CareRules.refill(p, uses: uses, now: now)).days, 54, "188 ml left")
        // no data, no estimate: never a made-up number
        XCTAssertNil(CareRules.refill(CareProduct(name: "Gel", perUse: 2), uses: uses, now: now), "no pack size")
        XCTAssertNil(CareRules.refill(CareProduct(name: "Gel", size: 200), uses: uses, now: now), "no amount per use")
        XCTAssertNil(CareRules.refill(CareProduct(name: "Gel", size: 200, perUse: 2), uses: Array(uses.prefix(2)), now: now), "fewer than 3 uses")
    }

    func testTheEstimateReadsInDaysWeeksOrMonths() {
        XCTAssertEqual(CareRules.spanText(0), "menos de 1 dia")
        XCTAssertEqual(CareRules.spanText(1), "1 dia")
        XCTAssertEqual(CareRules.spanText(11), "11 dias")
        XCTAssertEqual(CareRules.spanText(21), "3 semanas")
        XCTAssertEqual(CareRules.spanText(90), "3 meses")
        XCTAssertEqual(CareRules.rangeText(CareRules.Refill(days: 21, low: 14, high: 28)), "entre 2 e 4 semanas")
        XCTAssertEqual(CareRules.rangeText(CareRules.Refill(days: 11, low: 7, high: 14)), "entre 7 dias e 2 semanas")
        XCTAssertNil(CareRules.rangeText(CareRules.Refill(days: 1, low: 1, high: 1)))
        XCTAssertEqual(CareRules.stepLength(120), "2 min")
        XCTAssertEqual(CareRules.stepLength(45), "45 s")
        XCTAssertEqual(CareRules.stepLength(90), "1 min 30 s")
    }

    /// Built relative to today, because the estimate looks at the last 28 days up to now
    @MainActor
    func testAProductsUsesAreItsConfirmedStepsAndPoucoRecalculates() throws {
        let m = CareFixture.morning, n = CareFixture.night, p = CareFixture.product
        let store = try makeStore { s in
            s.add(m)
            s.add(n)
            s.add(p)
            for i in 1...7 {
                let d = Day.add(-i, to: Day.today)
                s.add(RoutineLog(id: CareRules.logId(routine: "RM", day: d), routineId: "RM", date: d, steps: ["RM1": ms(8 * 60, d), "RM2": ms(8 * 60 + 2, d)]))
                s.add(RoutineLog(id: CareRules.logId(routine: "RN", day: d), routineId: "RN", date: d, steps: ["RN2": ms(22 * 60, d)])) // the night's face wash not confirmed
            }
        }
        XCTAssertEqual(store.productUses(p).count, 7, "only the confirmed steps that use it")
        XCTAssertEqual(store.productMoments(p), "Manhã e noite")
        let first = try XCTUnwrap(store.refillEstimate(p))
        XCTAssertEqual(first.days, 106, "186 ml left at 1.75 ml a day")
        let before = try XCTUnwrap(store.setLevel(0.2, of: p))
        let little = try XCTUnwrap(store.record(CareProduct.self, "PB"))
        XCTAssertEqual(little.left, 0.2)
        XCTAssertEqual(try XCTUnwrap(store.refillEstimate(little)).days, 23, "«Pouco»: 40 ml left")
        store.save(before) // Desfazer
        XCTAssertEqual(store.record(CareProduct.self, "PB"), p)
        XCTAssertEqual(store.refillEstimate(p), first)
    }

    /// Phase 2.5 (from the notes at the end of RegressionPlannedChangeTests): "Adicionado à lista de compras" saved
    /// nothing. Now «Adicionar» saves one real item, and never a second one for the same product, however it's written
    /// or wherever the list already has it from.
    @MainActor
    func testAddingToShoppingSavesOneRealItemAndNeverTheSameProductTwice() throws {
        let store = try makeStore { s in
            s.add(ShoppingItem(id: "S1", name: "Sébium Gel"))
            s.add(ShoppingItem(id: "S2", name: "Protetor solar", bought: true))
            s.add(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30))
        }
        XCTAssertNil(store.addToShopping(name: "  sebium   GEL ", reason: "acaba em cerca de 3 semanas", source: "Higiene"), "already yours on the list")
        XCTAssertNil(store.addToShopping(name: "WHEY", reason: "", source: "Higiene"), "already on the list, from the pantry")
        XCTAssertNil(store.addToShopping(name: "   ", reason: "x", source: "Higiene"))
        XCTAssertEqual(store.all(ShoppingItem.self).count, 2, "nothing saved")
        let item = try XCTUnwrap(store.addToShopping(name: "Protetor solar", reason: "acaba em cerca de 3 semanas", source: "Higiene"), "a bought one is off the list")
        XCTAssertEqual(item.reason, "de Higiene: acaba em cerca de 3 semanas")
        XCTAssertEqual(item.aisle, "Health")
        XCTAssertFalse(item.bought, "bought is only ever marked by you")
        XCTAssertEqual(store.record(ShoppingItem.self, item.id), item, "it is saved")
        XCTAssertTrue(store.shoppingList().contains { $0.id == "s-" + item.id })
        XCTAssertTrue(store.isOnShoppingList("PROTETOR  SOLAR"))
        XCTAssertNil(store.addToShopping(name: "protetor solar", reason: "x", source: "Medicamentos"), "and only once")
        XCTAssertEqual(store.all(ShoppingItem.self).filter { !$0.bought }.count, 2)
        store.remove(item) // Desfazer
        XCTAssertFalse(store.isOnShoppingList("Protetor solar"))
    }

    func testTheSameProductHoweverItIsWritten() {
        XCTAssertEqual(CareRules.productKey("  Bioderma  SÉBIUM gel "), "bioderma sebium gel")
        XCTAssertEqual(CareRules.productKey("Protetor Solar"), CareRules.productKey("protetor solar"))
        XCTAssertNotEqual(CareRules.productKey("Gel"), CareRules.productKey("Gel 2"))
    }

    // MARK: Data

    /// The new fields are optional: what older builds saved reads as it is, and the new records' values are objects
    func testOlderRecordsStillReadAndTheNewRecordsAreObjects() throws {
        let routine = #"{"id":"R1","title":"Morning","icon":"sun.max","steps":[{"id":"S1","title":"Cleanser","seconds":45}]}"#
        let r = try JSONDecoder().decode(CareRoutine.self, from: Data(routine.utf8))
        XCTAssertNil(r.minute)
        XCTAssertNil(r.steps.first?.productId)
        let groom = #"{"id":"G1","title":"Trim beard","icon":"scissors","interval":7,"history":["2026-10-01"]}"#
        let g = try JSONDecoder().decode(GroomingItem.self, from: Data(groom.utf8))
        XCTAssertNil(g.weekdays)
        XCTAssertEqual(g.rhythm, 7)
        guard case .object? = JSONValue.from(RoutineLog(id: "R1_2026-11-07", routineId: "R1", date: Fixed.saturday, steps: ["S1": 1])) else { return XCTFail("a routine log must be an object") }
        guard case .object? = JSONValue.from(CareProduct(name: "Gel")) else { return XCTFail("a product must be an object") }
        for kind in [RoutineLog.kind, CareProduct.kind] {
            XCTAssertNotNil(kind.range(of: "^[a-z][a-zA-Z0-9]{0,31}$", options: .regularExpression), "\(kind): a record type the server takes")
        }
    }
}
