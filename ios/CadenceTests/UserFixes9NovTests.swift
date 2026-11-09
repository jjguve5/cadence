import XCTest
@testable import Cadence

/// Asked for by the user on 9 Nov: a shake logged as food, a morning routine that wouldn't leave «Agora», and foods you put together
final class HabitFoodTests: RegressionCase {
    private let shake = PromiseItem(id: "SH", title: "Protein shake", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 16 * 60), kcal: 180, protein: 32)
    private let label = "Proteína - Caramelo Salgado"

    private func food(_ name: String, at minute: Int, id: String = "F1") -> FoodEntry {
        FoodEntry(id: id, date: Day.today, minute: minute, name: name, kcal: 150, protein: 25)
    }

    @MainActor
    func testAShakeLoggedAsFoodIsAskedAboutOnceAndThenRemembered() throws {
        let store = try makeStore { [shake] in $0.promises[shake.id] = shake }
        store.save(food(label, at: 15 * 60 + 53))
        var habit = try XCTUnwrap(store.promises["SH"])
        let asked = try XCTUnwrap(store.foodToAsk(about: habit))
        XCTAssertNil(store.status(habit), "a name alone answers nothing")

        store.acceptHabitFood(habit, asked)
        XCTAssertEqual(store.status(habit), .done)
        XCTAssertEqual(store.foods(on: Day.today).count, 1, "the food is already in the day: its kcal don't count twice")
        XCTAssertEqual(store.answerOrigin(habit), .you)

        store.undo(habit)
        habit = try XCTUnwrap(store.promises["SH"])
        store.remove(try XCTUnwrap(store.record(FoodEntry.self, "F1")))
        store.save(food("PROTEÍNA - caramelo salgado", at: 15 * 60, id: "F2"))
        XCTAssertEqual(store.status(habit), .done, "the same food, once taught, answers by itself")
        XCTAssertEqual(store.answerOrigin(habit), .imported(HabitFoodRules.fromFood))
        XCTAssertEqual(store.foods(on: Day.today).count, 1)

        store.remove(try XCTUnwrap(store.record(FoodEntry.self, "F2")))
        XCTAssertNil(store.status(habit), "the food is gone, and the answer that came from it")
    }

    @MainActor
    func testOnlyWithinAnHourEitherWay() throws {
        let store = try makeStore { [shake] in $0.promises[shake.id] = shake }
        store.save(food(label, at: 15 * 60 - 1))
        store.save(food(label, at: 17 * 60 + 1, id: "F2"))
        XCTAssertNil(store.foodToAsk(about: shake), "outside the hour it doesn't ask")
        store.save(food(label, at: 17 * 60, id: "F3"))
        let asked = try XCTUnwrap(store.foodToAsk(about: shake))
        XCTAssertEqual(asked.id, "F3")
        store.acceptHabitFood(shake, asked)
        let taught = try XCTUnwrap(store.promises["SH"])
        store.undo(taught)
        store.remove(try XCTUnwrap(store.record(FoodEntry.self, "F3")))

        store.save(food(label, at: 14 * 60, id: "F4"))
        XCTAssertNil(store.status(taught), "taught, but two hours early: it doesn't mark")
        store.save(food(label, at: 15 * 60, id: "F5"))
        XCTAssertEqual(store.status(taught), .done, "an hour early does")
        store.remove(try XCTUnwrap(store.record(FoodEntry.self, "F5")))
        XCTAssertNil(store.status(taught), "the one left is outside the hour: it doesn't hold the answer")
    }

    @MainActor
    func testABreakfastYoghurtIsNotTheAfternoonShake() throws {
        let store = try makeStore { [shake] in $0.promises[shake.id] = shake }
        store.save(food("+ Proteína Aroma Baunilha", at: 9 * 60 + 26))
        XCTAssertNil(store.foodToAsk(about: shake))
        store.save(food("Arroz", at: 15 * 60, id: "F2"))
        XCTAssertNil(store.foodToAsk(about: shake), "nothing like it")
    }

    @MainActor
    func testNoGoesBackToAskingAsUsualAndAHabitWithoutFoodIsNeverAsked() throws {
        let plain = PromiseItem(id: "PL", title: "Protein reading", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 16 * 60))
        let store = try makeStore { [shake] in
            $0.promises[shake.id] = shake
            $0.promises[plain.id] = plain
        }
        store.save(food(label, at: 15 * 60 + 53))
        XCTAssertNil(store.foodToAsk(about: plain))
        store.rejectHabitFood(shake)
        XCTAssertNil(store.foodToAsk(about: shake))
        XCTAssertNil(store.status(shake), "«Não é» doesn't answer the habit")
    }
}

final class RoutineInAgoraTests: RegressionCase {
    private let morning = CareRoutine(id: "RM", title: "Morning", icon: "sun.max", steps: [RoutineStep(id: "RM1", title: "Gel", seconds: 60)])
    private let night = CareRoutine(id: "RN", title: "Night skincare", icon: "moon.stars", steps: [RoutineStep(id: "RN1", title: "Gel", seconds: 60)])

    func testWhenAgoraAsks() {
        XCTAssertTrue(CareRules.asksInAgora(morning, minute: 12 * 60 - 1))
        XCTAssertFalse(CareRules.asksInAgora(morning, minute: 12 * 60), "lunchtime: the morning is over")
        XCTAssertFalse(CareRules.asksInAgora(night, minute: 17 * 60), "the afternoon isn't the night")
        XCTAssertTrue(CareRules.asksInAgora(night, minute: 19 * 60 + 30))
        var late = morning
        late.minute = 11 * 60 + 30
        XCTAssertTrue(CareRules.asksInAgora(late, minute: 12 * 60 + 59), "with its own time, 90 minutes after it")
        XCTAssertFalse(CareRules.asksInAgora(late, minute: 13 * 60))
        var early = night
        early.minute = 18 * 60
        XCTAssertTrue(CareRules.asksInAgora(early, minute: 18 * 60))
    }

    @MainActor
    func testHojeNaoLeavesAgoraButStaysToConfirmInHigiene() throws {
        let store = try makeStore { [morning] in $0.add(morning) }
        XCTAssertEqual(store.nowStep(minute: 9 * 60, events: []), .routine)
        store.skipRoutineToday(morning)
        XCTAssertNil(store.nowStep(minute: 9 * 60, events: []), "gone from «Agora»")
        XCTAssertEqual(store.pendingSteps(morning).count, 1, "not done: still to confirm in Higiene")
        XCTAssertEqual(store.routineDueNow(minute: 9 * 60)?.id, "RM")
        UndoCenter.shared.undo()
        XCTAssertEqual(store.nowStep(minute: 9 * 60, events: []), .routine, "Desfazer brings it back")
    }

    @MainActor
    func testTheMorningLeavesAgoraAtLunchtimeAndHabitsCarryOn() throws {
        let habit = PromiseItem(id: "H1", title: "Creatina", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 13 * 60))
        let store = try makeStore { [morning] in
            $0.add(morning)
            $0.promises[habit.id] = habit
        }
        guard case .habit(let next)? = store.nowStep(minute: 12 * 60 + 30, events: []) else { return XCTFail("the habit, not the routine") }
        XCTAssertEqual(next.id, "H1")
    }
}

final class FoodBuildTests: XCTestCase {
    private func section(_ food: BuildFood, _ title: String) throws -> BuildSection { try XCTUnwrap(food.sections.first { $0.title == title }) }

    func testEveryFoodToBuildIsInTheCatalogueAndNamesAreUnique() {
        let names = Set(commonFoods.map(\.name))
        for (name, food) in FoodBuilds.all {
            XCTAssertTrue(names.contains(name), name)
            XCTAssertGreaterThan(food.total(food.start).kcal, 0, name)
            for s in food.sections {
                XCTAssertEqual(Set(s.options.map(\.name)).count, s.options.count, "\(name) · \(s.title)")
                XCTAssertTrue(s.picked.isSubset(of: Set(s.options.map(\.name))), "\(name) · \(s.title)")
                if s.single { XCTAssertEqual(s.picked.count, 1, "\(name) · \(s.title)") }
            }
        }
    }

    func testPaoComMelIsThere() {
        XCTAssertTrue(FoodSearch.local("pao com mel").contains { $0.name == "Pão com mel" })
    }

    func testABurgerWithSauceAndSides() throws {
        let burger = try XCTUnwrap(FoodBuilds.named("Hambúrguer"))
        var c = burger.start
        let before = burger.total(c).kcal
        c = burger.toggling("Batata frita", in: try section(burger, "Acompanhamentos"), c)
        c = burger.toggling("Molho barbecue", in: try section(burger, "Molhos"), c)
        XCTAssertEqual(burger.total(c).kcal, before + 340 + 25, accuracy: 0.01)
        XCTAssertTrue(burger.label(c).contains("batata frita"))
        XCTAssertTrue(burger.label(c).contains("molho barbecue"))
        XCTAssertFalse(burger.label(c).contains("vaca"), "the usual meat isn't repeated in the name")
        c = burger.toggling("Frango grelhado", in: try section(burger, "Carne"), c)
        XCTAssertEqual(c.picked["Carne"], ["Frango grelhado"], "one meat")
        XCTAssertTrue(burger.label(c).contains("frango grelhado"))
    }

    func testAPizzaScalesButItsSaucesDoNot() throws {
        let pizza = try XCTUnwrap(FoodBuilds.named("Pizza"))
        var c = pizza.start
        XCTAssertEqual(c.size, "2 fatias")
        let plain = pizza.total(c).kcal
        XCTAssertEqual(plain, 550, accuracy: 0.01)
        c = pizza.toggling("Azeite picante", in: try section(pizza, "Molhos"), c)
        XCTAssertEqual(pizza.total(c).kcal, plain + 110, accuracy: 0.01)
        c.size = "Pizza média inteira"
        XCTAssertEqual(pizza.total(c).kcal, 1100 + 110, accuracy: 0.01)
        XCTAssertEqual(FoodBuilds.named("Pizza inteira")?.start.size, "Pizza média inteira")
    }

    func testTheItemIsAnEstimateToConfirmLikeAnyFood() throws {
        let toastie = try XCTUnwrap(FoodBuilds.named("Tosta mista"))
        let item = toastie.item(toastie.start)
        XCTAssertEqual(item.kcal, toastie.total(toastie.start).rounded.kcal)
        XCTAssertEqual(item.portionText, "1 tosta")
        XCTAssertTrue(item.name.hasPrefix("Tosta mista · "))
    }
}
