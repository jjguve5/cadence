// Phase 2.10 (Vida): the rules behind the Roupeiro, the Lavandaria's five stages, the load planner, the assisted add,
// one shopping line per product, and the panel's needs. Synthetic data, fixed dates, no server (RegressionSupport).
import XCTest
@testable import Cadence

final class LifeTests: RegressionCase {
    // MARK: Data stays readable by older builds

    /// The new fields are optional: left out when unset, so an untouched piece is saved exactly as before; a piece in
    /// the machine keeps the saved state "wash", which an older build reads as «para lavar»
    func testNewFieldsAreOptionalAndLeftOutWhenUnset() throws {
        func keys<T: Encodable>(_ value: T) throws -> Set<String> {
            Set(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]).keys)
        }
        let plain = try keys(Garment(id: "G1", name: "T-shirt"))
        XCTAssertFalse(plain.contains("washing"))
        XCTAssertFalse(plain.contains("unsure"))
        var inMachine = Garment(id: "G1", name: "T-shirt", state: "wash")
        inMachine.washing = true
        let back = try JSONDecoder().decode(Garment.self, from: JSONEncoder().encode(inMachine))
        XCTAssertEqual(back.state, "wash")
        XCTAssertEqual(back.washing, true)
        let item = try keys(ShoppingItem(id: "S1", name: "Ovos"))
        XCTAssertTrue(item.isDisjoint(with: ["shop", "occasion", "boughtOn"]), "\(item)")
    }

    // MARK: Lavandaria

    /// Five stages from the four saved states: «Sugerida» is worked out (still worn, one use from the limit or past
    /// it), «Em lavagem» is `washing` on top of "wash"
    func testTheFiveStagesComeFromTheSavedStates() {
        func stage(_ state: String, wears: Int = 0, limit: Int = 3, washing: Bool? = nil) -> LaundryStage {
            Garment(name: "x", wearsBeforeWash: limit, wears: wears, state: state, washing: washing).stage
        }
        XCTAssertEqual(stage("clean"), .available)
        XCTAssertEqual(stage("worn", wears: 1), .available, "1 of 3: still well below the limit")
        XCTAssertEqual(stage("worn", wears: 2), .suggested, "2 of 3: one use from the limit")
        XCTAssertEqual(stage("worn", wears: 5, limit: 4), .suggested, "past the limit (the limit was lowered)")
        XCTAssertEqual(stage("wash", wears: 3), .toWash)
        XCTAssertEqual(stage("wash", wears: 3, washing: true), .washing)
        XCTAssertEqual(stage("drying", wears: 3), .drying)
        XCTAssertEqual(LaundryStage.allCases.map(\.label), ["Sugerida", "Para lavar", "Em lavagem", "A secar", "Disponível"])
    }

    /// Para lavar → em lavagem → a secar → arrumada: each step only on its own call; the count goes back to zero only
    /// at «Arrumada», the history stays; a piece in the machine is no longer in a load to plan
    @MainActor
    func testEachLaundryStepIsExplicitAndOnlyPutAwayResetsTheCount() throws {
        let store = try makeStore { s in
            s.add(Garment(id: "T1", name: "T-shirt", type: "top", washGroup: "darks 30°", wearsBeforeWash: 3, wears: 2, state: "worn", totalWears: 7))
            s.add(Garment(id: "T2", name: "Jeans", type: "bottom", washGroup: "darks 30°", wearsBeforeWash: 4, wears: 4, state: "wash", totalWears: 20))
        }
        let t1 = try XCTUnwrap(store.record(Garment.self, "T1"))
        XCTAssertEqual(t1.stage, .suggested, "suggested, not moved: nothing changes without your tap")
        store.sendToWash(t1)
        XCTAssertEqual(store.record(Garment.self, "T1")?.stage, .toWash)
        XCTAssertEqual(store.laundryLoads().first?.items.count, 2)
        let both = store.garments
        store.startWashing(both)
        XCTAssertEqual(store.garments.map(\.stage), [.washing, .washing])
        XCTAssertEqual(store.garments.map(\.state), ["wash", "wash"], "the saved state stays one of the four")
        XCTAssertTrue(store.laundryLoads().isEmpty, "already in the machine")
        store.hangToDry(store.garments)
        let drying = try XCTUnwrap(store.record(Garment.self, "T1"))
        XCTAssertEqual(drying.state, "drying")
        XCTAssertNil(drying.washing)
        XCTAssertEqual(drying.wears, 2, "drying keeps the count")
        store.putAway(piece: drying)
        let away = try XCTUnwrap(store.record(Garment.self, "T1"))
        XCTAssertEqual(away.state, "clean")
        XCTAssertEqual(away.wears, 0)
        XCTAssertEqual(away.totalWears, 7, "the history stays")
        XCTAssertEqual(store.record(Garment.self, "T2")?.state, "drying", "«Arrumada» is for one piece")
    }

    /// Desfazer puts the pieces back exactly as they were
    @MainActor
    func testUndoingALaundryStepRestoresThePieces() throws {
        let store = try makeStore { $0.add(Garment(id: "T1", name: "T-shirt", wears: 2, state: "drying", totalWears: 7)) }
        let before = try XCTUnwrap(store.record(Garment.self, "T1"))
        store.putAway(piece: before)
        store.restoreGarments([before])
        XCTAssertEqual(store.record(Garment.self, "T1"), before)
    }

    /// A load takes only the pieces whose care you set; a piece whose wash group the app only guessed is listed apart
    /// («Desconhecido») and never goes in by itself
    @MainActor
    func testALoadOnlyTakesPiecesWhoseCareIsKnown() throws {
        let store = try makeStore { s in
            s.add(Garment(id: "K1", name: "Calções", type: "gym", washGroup: "gym 30°", wearsBeforeWash: 1, wears: 1, state: "wash"))
            s.add(Garment(id: "K2", name: "T-shirt treino", type: "gym", washGroup: "gym 30°", wearsBeforeWash: 1, wears: 1, state: "wash"))
            s.add(Garment(id: "H1", name: "Hoodie preto", type: "layer", washGroup: "darks 30°", wearsBeforeWash: 4, wears: 3, state: "worn", unsure: ["washGroup"]))
            s.add(Garment(id: "D1", name: "Ganga", type: "bottom", washGroup: "darks 30°", state: "wash"))
            s.add(Garment(id: "M1", name: "Em lavagem", type: "gym", washGroup: "gym 30°", state: "wash", washing: true))
        }
        let plan = store.loadPlan("gym 30°")
        XCTAssertEqual(plan.known.map(\.id), ["K1", "K2"], "the group's pieces for washing, not the one already in the machine")
        XCTAssertEqual(plan.unknown.map(\.id), ["H1"], "care not confirmed: apart, not presumed")
    }

    /// More training days left this week than clean training kit, with kit waiting to be washed: a need, in the group
    /// where most of that kit washes. Enough clean kit, or nothing to wash: no need
    @MainActor
    func testGymKitNeedCountsTheTrainingsLeftAgainstCleanKit() throws {
        let kit = { (s: inout Saved) in
            s.add(WorkoutTemplate(id: "TPL", name: "Fim de semana", exercises: [], weekdays: [7, 1])) // Saturday, Sunday
            s.add(Garment(id: "K1", name: "Calções", type: "gym"))
            s.add(Garment(id: "K2", name: "T-shirt treino", type: "gym", washGroup: "gym 30°", wearsBeforeWash: 1, wears: 1, state: "wash"))
        }
        let short = try makeStore(kit)
        let need = try XCTUnwrap(short.gymKitNeed(on: Fixed.friday))
        XCTAssertEqual(need.trainings, 2, "Saturday and Sunday are left")
        XCTAssertEqual(need.clean, 1)
        XCTAssertEqual(need.group, "gym 30°")
        XCTAssertNil(short.gymKitNeed(on: Fixed.sunday), "only Sunday left, and one clean piece")
        let enough = try makeStore { s in kit(&s); s.add(Garment(id: "K3", name: "T-shirt treino 2", type: "gym")) }
        XCTAssertNil(enough.gymKitNeed(on: Fixed.friday))
        let nothingToWash = try makeStore { s in s.add(WorkoutTemplate(id: "TPL", name: "Fim de semana", exercises: [], weekdays: [7, 1])) }
        XCTAssertNil(nothingToWash.gymKitNeed(on: Fixed.friday), "nothing waiting to be washed: washing doesn't help")
    }

    // MARK: Roupeiro

    /// «Vesti hoje» on one piece: one use, counted as wear() counts it; a suggested outfit is left alone, a worn one
    /// gains the piece; Desfazer puts the piece and the day back
    @MainActor
    func testWearingOnePieceCountsOnceAndCanBeUndone() throws {
        let store = try makeStore { s in
            s.add(Garment(id: "T1", name: "T-shirt", type: "top", wearsBeforeWash: 3))
            s.add(Garment(id: "J1", name: "Ganga", type: "bottom", wearsBeforeWash: 2, wears: 1, state: "worn"))
        }
        let t1 = try XCTUnwrap(store.record(Garment.self, "T1"))
        store.wearPiece(t1, on: Fixed.saturday)
        let worn = try XCTUnwrap(store.record(Garment.self, "T1"))
        XCTAssertEqual(worn.wears, 1)
        XCTAssertEqual(worn.totalWears, 1)
        XCTAssertEqual(worn.state, "worn")
        XCTAssertEqual(worn.lastWorn, Fixed.saturday)
        XCTAssertNil(store.record(OutfitLog.self, Fixed.saturday), "no outfit is made up from one piece")
        store.undoWear([t1], log: nil, on: Fixed.saturday)
        XCTAssertEqual(store.record(Garment.self, "T1"), t1)

        store.save(OutfitLog(date: Fixed.saturday, items: ["T1"], worn: true))
        let log = store.record(OutfitLog.self, Fixed.saturday)
        let j1 = try XCTUnwrap(store.record(Garment.self, "J1"))
        store.wearPiece(j1, on: Fixed.saturday)
        XCTAssertEqual(store.record(Garment.self, "J1")?.state, "wash", "at its limit it goes for washing, as with wear()")
        XCTAssertEqual(store.record(OutfitLog.self, Fixed.saturday)?.items, ["T1", "J1"], "the day's worn outfit gains it")
        store.undoWear([j1], log: log, on: Fixed.saturday)
        XCTAssertEqual(store.record(Garment.self, "J1"), j1)
        XCTAssertEqual(store.record(OutfitLog.self, Fixed.saturday), log)
    }

    /// Undoing the outfit's «Vesti hoje» removes the log it made, and the suggestion is back with no wear counted
    @MainActor
    func testUndoingTheOutfitsWearRemovesTheLogItMade() throws {
        let store = try makeStore { $0.add(Garment(id: "T1", name: "T-shirt", type: "top")) }
        let t1 = try XCTUnwrap(store.record(Garment.self, "T1"))
        store.wear([t1], on: Fixed.saturday)
        store.undoWear([t1], log: nil, on: Fixed.saturday)
        XCTAssertNil(store.record(OutfitLog.self, Fixed.saturday))
        XCTAssertEqual(store.record(Garment.self, "T1")?.wears, 0)
    }

    /// A piece worn on its own isn't suggested again the next day (nothing worn the last two days), but the day after
    /// that it can be, while it's below its limit
    @MainActor
    func testAPieceWornOnItsOwnRestsForTwoDays() throws {
        let store = try makeStore { s in
            s.add(Garment(id: "T1", name: "T-shirt cinzenta", type: "top", wearsBeforeWash: 3))
            s.add(Garment(id: "B1", name: "Ganga", type: "bottom"))
        }
        store.wearPiece(try XCTUnwrap(store.record(Garment.self, "T1")), on: Fixed.wednesday)
        XCTAssertFalse(store.outfit(for: Fixed.friday).map(\.id).contains("T1"), "worn two days before")
        XCTAssertTrue(store.outfit(for: Fixed.saturday).map(\.id).contains("T1"), "rested, and 1 of 3 uses")
    }

    /// «Para lavar» takes the piece out of the available ones, whatever its count
    @MainActor
    func testSendingToWashTakesThePieceOutOfTheOutfits() throws {
        let store = try makeStore { s in
            s.add(Garment(id: "T1", name: "T-shirt", type: "top"))
            s.add(Garment(id: "B1", name: "Ganga", type: "bottom"))
        }
        store.sendToWash(try XCTUnwrap(store.record(Garment.self, "T1")))
        XCTAssertEqual(store.record(Garment.self, "T1")?.stage, .toWash)
        XCTAssertFalse(store.outfit(for: Fixed.saturday).map(\.id).contains("T1"))
    }

    /// The «Cor» filter's families, from the saved hex colours
    func testColourFamilies() {
        let expected = ["000000": "Preto", "1C1C1C": "Preto", "FFFFFF": "Branco", "808080": "Cinzento", "2D3E63": "Azul", "1A2540": "Azul",
                        "4A3527": "Castanho", "C8B89A": "Bege", "FF0000": "Vermelho", "00FF00": "Verde", "FFFF00": "Amarelo", "FF8800": "Laranja"]
        for (hex, family) in expected { XCTAssertEqual(colourFamily(hex), family, hex) }
        XCTAssertNil(colourFamily("nope"))
        XCTAssertNil(colourFamily(""))
    }

    // MARK: Nova peça

    /// A lookalike is the same category with the same name, or a very close colour; another category never is.
    /// «É a mesma» adds what's new (a photo, colours, a price) to the piece you have and keeps what you had set
    @MainActor
    func testALookalikeIsPointedOutAndTheSameIsMergedNotDuplicated() throws {
        let store = try makeStore { s in
            s.add(Garment(id: "H1", name: "Hoodie azul", type: "layer", colors: ["22324F"], wearsBeforeWash: 4, totalWears: 12))
            s.add(Garment(id: "P1", name: "Calças azuis", type: "bottom", colors: ["22324F"]))
        }
        let byColour = Garment(id: "NEW", name: "Camisola nova", type: "layer", colors: ["24344F"])
        XCTAssertEqual(store.lookalike(of: byColour)?.id, "H1")
        XCTAssertEqual(store.lookalike(of: Garment(id: "NEW", name: "hoodie AZUL ", type: "layer"))?.id, "H1", "the same name, any case")
        XCTAssertNil(store.lookalike(of: Garment(id: "NEW", name: "Casaco", type: "outer", colors: ["22324F"])), "another category")
        XCTAssertNil(store.lookalike(of: Garment(id: "NEW", name: "Hoodie vermelho", type: "layer", colors: ["C0392B"])))

        var entry = Garment(id: "NEW", name: "Hoodie", type: "layer", colors: ["24344F"], wearsBeforeWash: 2, unsure: ["washGroup"])
        entry.thumb = "AAAA"
        entry.price = 30
        let existing = try XCTUnwrap(store.record(Garment.self, "H1"))
        store.mergeGarment(entry, into: existing)
        let merged = try XCTUnwrap(store.record(Garment.self, "H1"))
        XCTAssertEqual(merged.thumb, "AAAA", "the photo it didn't have")
        XCTAssertEqual(merged.price, 30)
        XCTAssertEqual(merged.colors, ["22324F"], "its own colour stays")
        XCTAssertEqual(merged.wearsBeforeWash, 4, "what you had set stays")
        XCTAssertEqual(merged.totalWears, 12)
        XCTAssertNil(store.record(Garment.self, "NEW"), "no second piece")
        XCTAssertEqual(store.garments.count, 2)
    }

    // MARK: Compras

    /// The same product from several places is one line: the computed id and aisle, the larger quantity when the
    /// units agree, each reason once. Lines the app works out alone are suggestions; with one of yours, on your list
    @MainActor
    func testOneLinePerProductFoldsEverySource() throws {
        let store = try makeStore { s in
            s.add(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30, aisle: "Health"))
            s.add(ShoppingItem(id: "S1", name: "whey ", qty: 2))
            s.add(ShoppingItem(id: "S2", name: "Whey"))
            s.add(PantryItem(id: "PR", name: "Arroz", qty: 100, lowAt: 500))
            s.add(ShoppingItem(id: "S3", name: "Ovos", qty: 12, aisle: "Dairy"))
        }
        let list = store.shoppingList()
        XCTAssertEqual(list.map(\.id), ["s-S3", "whey", "arroz"], "by aisle, then name: Dairy, Health, Pantry")
        let whey = try XCTUnwrap(list.first { $0.id == "whey" })
        XCTAssertEqual(whey.aisle, "Health")
        XCTAssertEqual(whey.qty, 2, "the larger quantity")
        XCTAssertEqual(whey.reason, "acaba em 10 dias · adicionado por ti", "each source's reason, once")
        XCTAssertEqual(Set(whey.merged.compactMap(\.manual).map(\.id)), ["S1", "S2"])
        XCTAssertTrue(whey.mine, "you put it on the list too")
        XCTAssertFalse(try XCTUnwrap(list.first { $0.id == "arroz" }).mine, "worked out by the app alone: a suggestion")
        XCTAssertTrue(try XCTUnwrap(list.first { $0.id == "s-S3" }).mine)
    }

    /// Folding two lines: different units keep the first line's quantity
    func testFoldingKeepsTheFirstQuantityWhenUnitsDiffer() {
        let recipe = ListLine(id: "frango", name: "Frango", qty: 800, unit: "g", aisle: "Meat and fish", reason: "Chili", origin: "recipe")
        let yours = ListLine(id: "s-1", name: "frango", qty: 1, unit: "", aisle: "Other", reason: "added by you", manual: ShoppingItem(id: "1", name: "frango"))
        let line = Store.fold(yours, into: recipe)
        XCTAssertEqual(line.id, "frango")
        XCTAssertEqual(line.qty, 800)
        XCTAssertEqual(line.unit, "g")
        XCTAssertEqual(line.reason, "Chili · adicionado por ti")
        XCTAssertEqual(line.occasionLabel, "Preparação da semana")
        XCTAssertEqual(line.shopLabel, "Supermercado")
    }

    /// The circle marks every source of the line bought by you (your items keep the day); Desfazer takes it all back,
    /// the pantry included
    @MainActor
    func testBuyingAFoldedLineMarksEverySourceAndCanBeUndone() throws {
        let store = try makeStore { s in
            s.add(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30))
            s.add(ShoppingItem(id: "S1", name: "Whey"))
        }
        let week: String = store.week
        let line = try XCTUnwrap(store.shoppingList().first)
        let undo = store.buy(line)
        XCTAssertTrue(store.shoppingList().isEmpty, "nothing comes back on its own")
        XCTAssertNotNil(store.records("bought")["\(week)_whey"], "the pantry's need, marked for the week")
        let mine = try XCTUnwrap(store.record(ShoppingItem.self, "S1"))
        XCTAssertTrue(mine.bought)
        XCTAssertEqual(mine.boughtOn, Day.today)
        XCTAssertEqual(store.boughtToday.map(\.id), ["S1"])
        XCTAssertEqual(store.record(PantryItem.self, "PW")?.qty, 301, "what tick(_:) adds to the pantry")
        undo()
        XCTAssertEqual(store.shoppingList().map(\.id), ["whey"])
        XCTAssertNil(store.records("bought")["\(week)_whey"])
        XCTAssertEqual(store.record(ShoppingItem.self, "S1")?.bought, false)
        XCTAssertEqual(store.record(PantryItem.self, "PW")?.qty, 300)
    }

    /// After buying it this week, a new item of yours for the same product is a line of its own again
    @MainActor
    func testANewItemAfterBuyingIsListedAgain() throws {
        let store = try makeStore { $0.add(PantryItem(id: "PW", name: "Whey", qty: 300, usePerDay: 30)) }
        _ = store.buy(try XCTUnwrap(store.shoppingList().first)) // the Desfazer closure it returns isn't needed here
        store.save(ShoppingItem(id: "S9", name: "Whey"))
        XCTAssertEqual(store.shoppingList().map(\.id), ["s-S9"])
    }

    // MARK: The panel

    /// One need at a time, the most useful first; only areas that are on; nothing saved by looking
    @MainActor
    func testTheNeedsComeFromWhatIsKnownAndFollowTheAreas() throws {
        let build = { (s: inout Saved) in
            s.add(WorkoutTemplate(id: "TPL", name: "Fim de semana", exercises: [], weekdays: [7, 1]))
            s.add(Garment(id: "K2", name: "T-shirt treino", type: "gym", washGroup: "gym 30°", wearsBeforeWash: 1, wears: 1, state: "wash"))
            s.add(PantryItem(id: "PR", name: "Arroz", qty: 100, lowAt: 500))
        }
        let store = try makeStore(build)
        let needs = store.lifeNeeds(on: Fixed.friday)
        XCTAssertEqual(needs.map(\.id), ["laundry.gym", "shopping"])
        XCTAssertEqual(needs.map(\.state), [.suggested, .suggested])
        if case .load(let group) = needs[0].go { XCTAssertEqual(group, "gym 30°") } else { XCTFail("opens the load to plan") }
        XCTAssertEqual(needs[0].why, "esta semana tens mais 2 treinos e nenhuma peça de treino disponível.")
        XCTAssertEqual(store.garments.first?.state, "wash", "a need changes nothing")
        let off = try makeStore { s in build(&s); s.profile.areasOff = ["wardrobe", "kitchen"] }
        XCTAssertTrue(off.lifeNeeds(on: Fixed.friday).isEmpty)
    }
}
