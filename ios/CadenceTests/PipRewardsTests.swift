import XCTest
@testable import Cadence

/// Pip's chests, collection and house (asked for by the user on 9 Nov)
final class PipRewardsTests: RegressionCase {
    private func closed(_ date: String, points: Int) -> DayEntry {
        var d = DayEntry(date: date)
        d.closedAt = 1
        d.points = points
        return d
    }

    /// `count` closed days in a row ending yesterday, worth `points` each
    private func days(_ count: Int, points: Int) -> [String: DayEntry] {
        var all: [String: DayEntry] = [:]
        for n in 1...count {
            let date = Day.add(-n, to: Day.today)
            all[date] = closed(date, points: points)
        }
        return all
    }

    func testTheCatalogueIsConsistent() {
        XCTAssertEqual(Set(pipPrizes.map(\.id)).count, pipPrizes.count, "one id, one prize")
        XCTAssertEqual(Set(pipAccessories.map(\.id)).count, pipAccessories.count)
        XCTAssertEqual(Set(pipAccessories.map(\.layer)).count, pipAccessories.count)
        XCTAssertEqual(pipPrizes.count, pipChestAccessories.count + pipRoomItems.filter { $0.rarity != nil }.count)
        for item in pipRoomItems { XCTAssertTrue(pipRoomSlots.contains(item.slot), item.id) }
        for (slot, id) in pipRoomDefaults {
            let item = pipRoomItems.first { $0.id == id }
            XCTAssertEqual(item?.slot, slot)
            XCTAssertNil(item?.rarity, "what comes with the house isn't a prize")
        }
        for kind in ChestKind.allCases { XCTAssertEqual(kind.odds.map(\.1).reduce(0, +), 100, kind.rawValue) }
        for rarity in PipRarity.allCases { XCTAssertFalse(pipPrizes.filter { $0.rarity == rarity }.isEmpty, rarity.label) }
    }

    func testHowChestsAreEarned() {
        XCTAssertEqual(ChestRules.earned(.wood, points: 99, level: 1, closed: []), 0)
        XCTAssertEqual(ChestRules.earned(.wood, points: 250, level: 1, closed: []), 2)
        XCTAssertEqual(ChestRules.earned(.silver, points: 0, level: 1, closed: []), 0)
        XCTAssertEqual(ChestRules.earned(.silver, points: 0, level: 4, closed: []), 3)
        let week = (0..<7).map { Day.add($0, to: "2026-11-02") }
        XCTAssertEqual(ChestRules.weekRuns(Array(week.dropLast())), 0, "six in a row isn't seven")
        XCTAssertEqual(ChestRules.weekRuns(week), 1)
        XCTAssertEqual(ChestRules.weekRuns(week + ["2026-11-10"]), 1, "a gap starts the count again")
        XCTAssertEqual(ChestRules.weekRuns((0..<14).map { Day.add($0, to: "2026-11-02") }), 2)
        XCTAssertEqual(ChestRules.currentRun(["2026-11-06", "2026-11-07"], upTo: "2026-11-08"), 2, "today still open: up to yesterday")
        XCTAssertEqual(ChestRules.currentRun(["2026-11-05"], upTo: "2026-11-08"), 0)
    }

    func testWhatAChestGives() {
        let common = PipPrize(id: "c", name: "", slot: "head", rarity: .common, emoji: "", isRoom: false)
        let rare = PipPrize(id: "r", name: "", slot: "head", rarity: .rare, emoji: "", isRoom: false)
        let legend = PipPrize(id: "l", name: "", slot: "head", rarity: .legendary, emoji: "", isRoom: false)
        XCTAssertNil(ChestRules.pick(.wood, from: [], roll: 0, which: 0))
        XCTAssertEqual(ChestRules.pick(.wood, from: [common, rare, legend], roll: 0.5, which: 0)?.id, "c", "70% of wood chests are common")
        XCTAssertEqual(ChestRules.pick(.wood, from: [common, rare, legend], roll: 0.8, which: 0)?.id, "r")
        XCTAssertEqual(ChestRules.pick(.gold, from: [common, rare, legend], roll: 0.9, which: 0)?.id, "l")
        XCTAssertEqual(ChestRules.pick(.gold, from: [common, rare, legend], roll: 0.5, which: 0)?.id, "r", "no epic left: the nearest below")
        XCTAssertEqual(ChestRules.pick(.wood, from: [legend], roll: 0, which: 0.99)?.id, "l", "only that left: it comes, whatever the chest")
        for roll in stride(from: 0.0, to: 1.0, by: 0.05) {
            XCTAssertNotEqual(ChestRules.pick(.wood, from: [common, legend], roll: roll, which: 0)?.id, "l", "wood never gives a legendary while something else is left")
        }
    }

    @MainActor
    func testOpeningSavesWhatCameOutAndNeverTwice() throws {
        // 3 days of 80: 240 points, level 2 (from 100), no week in a row
        let store = try makeStore { $0.days = self.days(3, points: 80) }
        XCTAssertEqual(store.chestsEarned(.wood), 2)
        XCTAssertEqual(store.chestsEarned(.silver), 1)
        XCTAssertEqual(store.chestsReady, [.silver, .wood, .wood], "the best first")
        XCTAssertNil(store.openChest(.gold), "none earned")

        let first = try XCTUnwrap(store.openChest(.silver, roll: 0, which: 0))
        XCTAssertTrue(store.pipOwned.contains(first.id))
        XCTAssertNil(store.openChest(.silver), "the only silver chest is open")
        let second = try XCTUnwrap(store.openChest(.wood, roll: 0, which: 0))
        XCTAssertNotEqual(second.id, first.id, "never something you already have")
        XCTAssertNotNil(store.openChest(.wood))
        XCTAssertNil(store.openChest(.wood))
        XCTAssertTrue(store.chestsReady.isEmpty)
        XCTAssertEqual(store.all(PipChest.self).map(\.id).sorted(), ["silver-1", "wood-1", "wood-2"])
        XCTAssertEqual(store.pipOwned.count, 3)
    }

    @MainActor
    func testAWeekInARowGivesAGoldChest() throws {
        let store = try makeStore { $0.days = self.days(7, points: 10) }
        XCTAssertEqual(store.chestsEarned(.gold), 1)
        XCTAssertEqual(store.goldRun, 0, "the next week starts")
        XCTAssertEqual(store.chestsReady.first, .gold)
    }

    @MainActor
    func testPipOnlyWearsWhatIsOwned() throws {
        let store = try makeStore { $0.days = self.days(2, points: 60) } // 120 points: one wood chest
        let crown = try XCTUnwrap(pipAccessories.first { $0.id == "crown" })
        store.wear(crown, slot: "head")
        XCTAssertTrue(store.pipOutfit.isEmpty, "chosen but not owned: not worn")
        let prize = try XCTUnwrap(store.openChest(.wood, roll: 0, which: 0))

        store.use(prize)
        if prize.isRoom {
            XCTAssertTrue(store.pipRoom().contains { $0.id == prize.id })
        } else {
            XCTAssertEqual(store.pipOutfit.map(\.id), [prize.id])
        }
    }

    @MainActor
    func testTheHouseStartsWithItsOwnAndOnlyShowsWhatIsOwned() throws {
        let store = try makeStore { s in
            s.add(PipChest(id: "wood-1", chest: "wood", prize: "left-plant"))
            s.add(PipChest(id: "wood-2", chest: "wood", prize: "wall-stripes"))
        }
        XCTAssertEqual(store.pipRoom().map(\.id), ["wall-cream", "floor-wood", "window-day"])
        let plant = try XCTUnwrap(pipRoomItems.first { $0.id == "left-plant" })
        let treasure = try XCTUnwrap(pipRoomItems.first { $0.id == "right-treasure" })
        let stripes = try XCTUnwrap(pipRoomItems.first { $0.id == "wall-stripes" })
        store.place(plant, slot: "left")
        store.place(treasure, slot: "right")
        store.place(stripes, slot: "wall")
        XCTAssertEqual(store.pipRoom().map(\.id), ["wall-stripes", "floor-wood", "window-day", "left-plant"], "the treasure isn't owned")
        store.place(nil, slot: "left")
        store.place(nil, slot: "wall")
        XCTAssertEqual(store.pipRoom().map(\.id), ["wall-cream", "floor-wood", "window-day"], "a wall always: back to the house's own")
    }

    @MainActor
    func testThePiecesByLevelStayAsTheyWere() throws {
        let store = try makeStore { $0.days = self.days(2, points: 60) } // level 2: the scarf
        let scarf = try XCTUnwrap(pipAccessories.first { $0.id == "scarf" })
        let medal = try XCTUnwrap(pipAccessories.first { $0.id == "medal" })
        XCTAssertTrue(store.owns(scarf))
        XCTAssertFalse(store.owns(medal))
        store.wear(scarf, slot: "neck")
        XCTAssertEqual(store.pipOutfit.map(\.id), ["scarf"])
    }

    @MainActor
    func testHarderGivesMorePoints() throws {
        var easy = PromiseItem(id: "E", title: "Água ao acordar", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 480))
        easy.effort = 1
        var hard = PromiseItem(id: "H", title: "Estudar 1 hora", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 600))
        hard.effort = 3
        let plain = PromiseItem(id: "P", title: "Ler", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 1300))
        let store = try makeStore { s in
            for p in [easy, hard, plain] { s.promises[p.id] = p }
        }
        XCTAssertEqual(store.points(), 0, "nothing done: nothing earned")
        store.log(easy, .done)
        XCTAssertEqual(store.points(), 5)
        store.log(hard, .done)
        XCTAssertEqual(store.points(), 25)
        store.log(plain, .tiny)
        XCTAssertEqual(store.points(), 30, "no difficulty chosen is medium, and the minimum version is half")
        store.log(hard, .skipped)
        XCTAssertEqual(store.points(), 10, "not done gives nothing, and takes nothing else away")
        XCTAssertEqual(store.points(closing: true), 15)
        XCTAssertEqual(store.totalPoints, 10, "today counts as it stands")
        XCTAssertEqual(store.pointLines().first { $0.id == "habit.H" }?.points, 20, "still open: what it would give")
    }

    @MainActor
    func testClosedDaysKeepThePointsTheyHad() throws {
        let store = try makeStore { $0.days = self.days(2, points: 80) }
        XCTAssertEqual(store.totalPoints, 160, "nothing in the history is recalculated")
    }
}
