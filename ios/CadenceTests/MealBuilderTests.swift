// The meal builder's arithmetic and data, and counting food goals from logged names and groups.
import XCTest
@testable import Cadence

final class MealBuilderTests: XCTestCase {
    func testPlainPlateAddsUpFromPer100g() {
        let m = MealBuilder.plate(MealDraft(bases: ["rice"], protein: "chicken-breast", method: .boiled))
        // boiled isn't a way for chicken here, so it falls back to grilled: 180 g rice + 150 g chicken + a little oil
        XCTAssertEqual(MealBuilder.effectiveMethod(MealDraft(protein: "chicken-breast", method: .boiled)), .grilled)
        XCTAssertEqual(m.kcal, 234 + 247.5 + 21, accuracy: 0.5)
        XCTAssertEqual(m.protein, 4.86 + 46.5, accuracy: 0.1)
        XCTAssertEqual(m.carbs, 50.4, accuracy: 0.1)
    }

    func testFryingAndBreadingCostMoreThanGrilling() {
        func kcal(_ method: CookMethod) -> Double { MealBuilder.plate(MealDraft(protein: "chicken-breast", method: method)).kcal }
        XCTAssertGreaterThan(kcal(.fried), kcal(.grilled))
        XCTAssertGreaterThan(kcal(.breaded), kcal(.fried))
        XCTAssertGreaterThan(MealBuilder.plate(MealDraft(protein: "chicken-breast", method: .breaded)).carbs, 0)
    }

    func testPotatoesRankByCooking() {
        func kcal(_ id: String) -> Double { MealBuilder.plate(MealDraft(bases: [id])).kcal }
        XCTAssertGreaterThan(kcal("potato-fried"), kcal("potato-roast"))
        XCTAssertGreaterThan(kcal("potato-roast"), kcal("potato-boiled"))
    }

    func testFoodWithoutCookingChoiceIgnoresMethod() {
        XCTAssertNil(MealBuilder.effectiveMethod(MealDraft(protein: "tuna-tin", method: .fried)))
        XCTAssertEqual(MealBuilder.plate(MealDraft(protein: "tuna-tin", method: .fried)), MealBuilder.plate(MealDraft(protein: "tuna-tin")))
    }

    func testTwoBasesShareThePlate() {
        let rice = MealBuilder.plate(MealDraft(bases: ["rice"])).kcal, fries = MealBuilder.plate(MealDraft(bases: ["potato-fried"])).kcal
        XCTAssertEqual(MealBuilder.plate(MealDraft(bases: ["rice", "potato-fried"])).kcal, (rice + fries) * 0.6, accuracy: 0.01)
    }

    func testPortionScalesThePlateButNotSaucesOrAddOns() {
        var d = MealDraft(bases: ["rice"], protein: "cod", method: .boiled, sauces: ["olive-oil"], addOns: ["banana"])
        let normal = MealBuilder.plate(MealDraft(bases: ["rice"], protein: "cod", method: .boiled)).kcal
        let oil = MealBuilder.sauces.first { $0.id == "olive-oil" }!.macros().kcal
        d.factor = 1.5
        XCTAssertEqual(MealBuilder.plate(d).kcal, normal * 1.5 + oil, accuracy: 0.01)
        XCTAssertEqual(MealBuilder.total(d).kcal, normal * 1.5 + oil + 105, accuracy: 0.01)
    }

    func testEmptyDraftIsNothing() {
        XCTAssertTrue(MealBuilder.isEmpty(MealDraft()))
        XCTAssertEqual(MealBuilder.total(MealDraft()), Macros())
        XCTAssertTrue(MealBuilder.entries(MealDraft()).isEmpty)
    }

    func testDataIsSensibleAndIdsAreUnique() {
        let parts = MealBuilder.bases + MealBuilder.proteins + MealBuilder.vegetables + MealBuilder.sauces
        XCTAssertEqual(Set(parts.map(\.id)).count, parts.count)
        XCTAssertEqual(Set(MealBuilder.addOns.map(\.id)).count, MealBuilder.addOns.count)
        func energy(_ p: Double, _ c: Double, _ f: Double) -> Double { 4 * p + 4 * c + 9 * f }
        for x in parts {
            XCTAssertGreaterThan(x.grams, 0, x.id)
            XCTAssertEqual(energy(x.protein, x.carbs, x.fat), x.kcal, accuracy: max(8, x.kcal * 0.2), x.id)
        }
        // Alcohol is energy that isn't protein, carbs or fat
        for a in MealBuilder.addOns where !["wine", "beer"].contains(a.id) {
            XCTAssertEqual(energy(a.protein, a.carbs, a.fat), a.kcal, accuracy: max(8, a.kcal * 0.2), a.id)
            XCTAssertTrue(MealBuilder.addOnCategories.contains(a.category), a.id)
        }
        for g in MealBuilder.proteins.map(\.group) { XCTAssertTrue(MealBuilder.proteinGroups.contains(g), g) }
    }

    func testEveryAddOnCategoryOffersSomething() {
        for c in MealBuilder.addOnCategories { XCTAssertFalse(MealBuilder.addOns.filter { $0.category == c }.isEmpty, c) }
    }

    func testTypicalPlatesUseRealFoodsAndAreBelievable() {
        for dish in MealBuilder.dishes {
            let d = dish.draft
            for b in d.bases { XCTAssertNotNil(MealBuilder.base(b), dish.name) }
            XCTAssertNotNil(d.protein.flatMap { MealBuilder.protein($0) }, dish.name)
            for v in d.vegetables { XCTAssertTrue(MealBuilder.vegetables.contains { $0.id == v }, dish.name) }
            for s in d.sauces { XCTAssertTrue(MealBuilder.sauces.contains { $0.id == s }, dish.name) }
            let kcal = MealBuilder.plate(d).kcal
            XCTAssertTrue((300...1300).contains(kcal), "\(dish.name): \(kcal) kcal")
            XCTAssertEqual(MealBuilder.name(d), dish.name)
        }
    }

    func testDishNameGoesWhenThePlateChanges() {
        var d = MealBuilder.dishes.first { $0.name == "Bitoque" }!.draft
        d.factor = 0.75
        XCTAssertEqual(MealBuilder.name(d), "Bitoque (75%)")
        d.factor = 1
        d.protein = "pork-loin"
        d.method = .grilled
        XCTAssertFalse(MealBuilder.name(d).contains("Bitoque"))
        XCTAssertTrue(MealBuilder.name(d).hasPrefix("Pork loin grilled"), MealBuilder.name(d))
    }

    func testSaveLogsThePlateAndEachAddOn() {
        let d = MealDraft(bases: ["pure"], protein: "hake", method: .boiled, vegetables: ["salad-mixed", "grelos"], addOns: ["soup-veg", "fruit", "bread-roll"])
        let e = MealBuilder.entries(d, date: "2026-11-02", minute: 780)
        XCTAssertEqual(e.count, 4)
        XCTAssertEqual(e[0].date, "2026-11-02")
        XCTAssertEqual(e[0].minute, 780)
        XCTAssertEqual(e[0].kcal, MealBuilder.plate(d).kcal.rounded())
        XCTAssertEqual(FoodGoals.count(e), FoodGoalCounts(fruit: 1, soup: 1, veg: 2))
    }

    func testPlateWithoutVegetablesIsNotReadFromItsName() {
        let e = MealBuilder.entries(MealDraft(bases: ["rice-tomato"], protein: "cod", method: .boiled))
        XCTAssertEqual(FoodGoals.count(e), FoodGoalCounts())
    }

    func testFavouriteHoldsTheWholeMealInOne() {
        let d = MealDraft(bases: ["rice"], protein: "salmon", method: .grilled, vegetables: ["salad-mixed"], addOns: ["soup-veg", "cola"])
        let m = MealBuilder.favourite(d, name: "  Tuesday salmon ")
        XCTAssertEqual(m.name, "Tuesday salmon")
        XCTAssertEqual(m.built, true)
        XCTAssertEqual(m.kcal, MealBuilder.total(d).rounded.kcal)
        XCTAssertEqual(m.caffeine, 34)
        let logged = FoodEntry(name: m.name, kcal: m.kcal, protein: m.protein, group: m.group)
        XCTAssertEqual(FoodGoals.count([logged]), FoodGoalCounts(fruit: 0, soup: 1, veg: 1))
        XCTAssertTrue(MealBuilder.favourite(d).name.contains("+ cola"))
    }

    func testAFullMealIsOfferedAddOnsASnackIsNot() {
        XCTAssertTrue(MealBuilder.isFullMeal(kcal: 600))
        XCTAssertFalse(MealBuilder.isFullMeal(kcal: 105))
    }
}

final class FoodGoalsTests: XCTestCase {
    private func food(_ name: String, minute: Int = 720, protein: Double = 0, group: String? = nil) -> FoodEntry {
        FoodEntry(date: "2026-11-02", minute: minute, name: name, kcal: 100, protein: protein, group: group)
    }
    private func counted(_ names: String...) -> FoodGoalCounts { FoodGoals.count(names.map { food($0) }) }

    func testPortugueseAndEnglishFruit() {
        for name in ["Banana", "Maçã", "maca", "Pêra", "Laranja", "Fruta", "2 peras", "Apple", "Morangos", "Salada de fruta"] {
            XCTAssertEqual(counted(name), FoodGoalCounts(fruit: 1), name)
        }
    }

    func testThingsMadeFromFruitAreNotPiecesOfFruit() {
        for name in ["Sumo de laranja", "Orange juice", "Bolo de banana", "Tarte de maçã", "Iogurte de morango", "Smoothie", "Gelado de morango", "Barra de cereais com banana"] {
            XCTAssertEqual(counted(name).fruit, 0, name)
        }
        XCTAssertEqual(counted("Iogurte com banana").fruit, 1)
    }

    func testWordsMatchWholeNotInsideOthers() {
        for name in ["Opera cake", "Espera", "Macarrão", "Bacalhau", "Arroz de pato"] { XCTAssertEqual(counted(name), FoodGoalCounts(), name) }
    }

    func testSoupCoversItsOwnVegetables() {
        for name in ["Sopa de legumes", "Caldo verde", "Canja de galinha", "Soup", "Creme de abóbora"] {
            XCTAssertEqual(counted(name), FoodGoalCounts(soup: 1), name)
        }
        XCTAssertEqual(counted("Soup and salad"), FoodGoalCounts(soup: 1, veg: 1))
    }

    func testVegetablesAndSalad() {
        for name in ["Salada mista", "Legumes", "Brócolos", "Espinafres", "Feijão verde", "Chicken with potatoes and salad", "Salmon with vegetables"] {
            XCTAssertEqual(counted(name), FoodGoalCounts(veg: 1), name)
        }
        for name in ["Arroz de tomate", "Massa com molho de tomate", "Salada russa", "Feijoada"] { XCTAssertEqual(counted(name).veg, 0, name) }
    }

    func testGroupWinsOverName() {
        XCTAssertEqual(FoodGoals.count([food("Bolo de banana", group: "fruit")]), FoodGoalCounts(fruit: 1))
        XCTAssertEqual(FoodGoals.count([food("Salada de frango", group: "meal")]), FoodGoalCounts())
        XCTAssertEqual(FoodGoals.count([food("Meal prep box", group: "veg,veg,soup")]), FoodGoalCounts(soup: 1, veg: 2))
        XCTAssertEqual(FoodGoals.count([food("Maçã", group: "")]), FoodGoalCounts(fruit: 1))
    }

    func testOneTapDefaultsCountForTheirGoal() {
        let foods = [MealBuilder.pieceOfFruit, MealBuilder.mugOfSoup, MealBuilder.vegPortion].map { $0.entry(date: "2026-11-02", minute: 600) }
        XCTAssertEqual(FoodGoals.count(foods), FoodGoalCounts(fruit: 1, soup: 1, veg: 1))
    }

    func testCatalogueFoodsAreClassifiedByName() {
        XCTAssertEqual(counted("Orange"), FoodGoalCounts(fruit: 1))
        XCTAssertEqual(counted("Grapes"), FoodGoalCounts(fruit: 1))
        XCTAssertEqual(counted("Mixed salad with tuna"), FoodGoalCounts(veg: 1))
        XCTAssertEqual(counted("Greek yogurt"), FoodGoalCounts())
        XCTAssertEqual(counted("Scrambled eggs"), FoodGoalCounts())
    }

    func testGoalsMetAndWhatIsLeft() {
        XCTAssertEqual(FoodGoals.goalsMet(FoodGoalCounts()), 0)
        XCTAssertEqual(FoodGoals.goalsMet(FoodGoalCounts(fruit: 2, soup: 0, veg: 3)), 2)
        XCTAssertEqual(FoodGoals.missing(FoodGoalCounts()), ["2 pieces of fruit", "1 mug of soup", "2 portions of veg"])
        XCTAssertEqual(FoodGoals.missing(FoodGoalCounts(fruit: 1, soup: 1, veg: 2)), ["1 piece of fruit"])
        XCTAssertTrue(FoodGoals.missing(FoodGoalCounts(fruit: 5, soup: 1, veg: 2)).isEmpty)
    }

    func testLineRecommendsThenCheersThenCelebrates() {
        XCTAssertTrue(FoodGoals.line(FoodGoalCounts(), minute: 9 * 60).contains("at least 2 pieces of fruit"))
        XCTAssertTrue(FoodGoals.line(FoodGoalCounts(fruit: 1), minute: 18 * 60).contains("soup"))
        XCTAssertTrue(FoodGoals.line(FoodGoalCounts(fruit: 2, soup: 1, veg: 1), minute: 12 * 60).contains("1 portion of veg"))
        XCTAssertTrue(FoodGoals.line(FoodGoalCounts(fruit: 2, soup: 1, veg: 2), minute: 12 * 60).hasPrefix("All done"))
    }

    func testProteinSittingsMergeWithinAnHour() {
        let foods = [food("a", minute: 800, protein: 10), food("b", minute: 480, protein: 25), food("c", minute: 840, protein: 15), food("d", minute: 1200, protein: 5)]
        XCTAssertEqual(FoodGoals.proteinSittings(foods), [25, 25, 5])
    }

    func testProteinHint() {
        XCTAssertTrue(FoodGoals.proteinHint([], target: 160).contains("about 40 g"))
        let one = [food("Eggs", minute: 480, protein: 30)]
        let hint = FoodGoals.proteinHint(one, target: 160)
        XCTAssertTrue(hint.contains("1 of 3"), hint)
        XCTAssertTrue(hint.contains("about 60 g"), hint)
        XCTAssertTrue(FoodGoals.proteinHint([food("Lots", protein: 170)], target: 160).hasPrefix("Protein done"))
    }

    func testOldSavedDataStillDecodes() throws {
        let food = #"{"id":"a","date":"2026-01-01","minute":600,"name":"Maçã","kcal":95,"protein":0.5}"#
        let entry = try JSONDecoder().decode(FoodEntry.self, from: Data(food.utf8))
        XCTAssertNil(entry.group)
        XCTAssertEqual(FoodGoals.count([entry]), FoodGoalCounts(fruit: 1))
        let meal = #"{"id":"m","name":"Old","kcal":500,"protein":30,"uses":2,"lastUsed":0}"#
        let saved = try JSONDecoder().decode(SavedMeal.self, from: Data(meal.utf8))
        XCTAssertNil(saved.group)
        XCTAssertNil(saved.built)
    }

    func testCatalogueLookupsKeepTheirFirstMatch() {
        XCTAssertEqual(FoodSearch.local("banana").first?.name, "Banana")
        XCTAssertEqual(FoodSearch.local("greek yogurt").first?.name, "Greek yogurt")
        XCTAssertEqual(FoodSearch.local("scrambled eggs").first?.name, "Scrambled eggs")
        XCTAssertEqual(FoodSearch.local("egg").first?.name, "Egg, boiled or fried")
        XCTAssertEqual(FoodSearch.local("soup").first?.name, "Soup")
        XCTAssertEqual(Set(commonFoods.map(\.name)).count, commonFoods.count)
    }
}
