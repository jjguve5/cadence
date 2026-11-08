// Phase 2.7 (Comida): the confirmation's rules. Units only where their equivalence is known (tablespoon 15 g, teaspoon
// 5 g), the amount estimated until you confirm it, the group saved for every food, «Guardar refeição» saving once
// («Editar» replaces, Desfazer restores), and the water goal suggested until you accept or adjust it.
// Synthetic data, fixed dates where the code takes a day.
import XCTest
@testable import Cadence

private func common(_ name: String) -> CommonFood {
    guard let f = commonFoods.first(where: { $0.name == name }) else { fatalError("no catalogue food \(name)") }
    return f
}

/// A JSON object as Open Food Facts sends it
private func json(_ text: String) -> [String: Any] {
    guard let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { fatalError("bad JSON: \(text)") }
    return o
}

/// FoodEntry as the build of 2 November (dc04c07) reads it: none of the phase 2.7 fields
private struct PreviousFoodEntry: Decodable {
    var id: String
    var date: String
    var minute: Int
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double?
    var fat: Double?
    var grams: Double?
    var caffeine: Double?
    var mealId: String?
    var promiseId: String?
    var group: String?
}

final class FoodUnitTests: XCTestCase {
    func testPortionTextsGiveOnlyTheUnitsTheySupport() {
        XCTAssertEqual(FoodPortion.grams("1 pote de 170 g"), 170)
        XCTAssertEqual(FoodPortion.grams("um punhado, 30 g"), 30)
        XCTAssertEqual(FoodPortion.grams("1 colher de sopa"), 15, "a tablespoon is 15 g")
        XCTAssertEqual(FoodPortion.grams("2 colheres de chá"), 10, "a teaspoon is 5 g")
        XCTAssertNil(FoodPortion.grams("1 copo de 250 ml"), "millilitres are not grams")
        XCTAssertNil(FoodPortion.grams("1 prato"))
        XCTAssertEqual(FoodPortion.count("2 ovos"), 2)
        XCTAssertEqual(FoodPortion.count("1 média"), 1)
        XCTAssertEqual(FoodPortion.count("8 peças"), 8)
        XCTAssertEqual(FoodPortion.count("1, com molho"), 1)
        for measured in ["1 prato", "1 malga", "1 taça", "1 copo de 250 ml", "330 ml", "um punhado, 30 g", "1 dose média"] {
            XCTAssertNil(FoodPortion.count(measured), measured)
        }
    }

    func testEachFoodOffersOnlyTheUnitsWithAKnownEquivalence() {
        XCTAssertEqual(FoodItem(common: common("Iogurte grego")).units, [.gram, .tablespoon, .teaspoon, .portion])
        XCTAssertEqual(FoodItem(common: common("Banana")).units, [.unit, .portion])
        XCTAssertEqual(FoodItem(common: common("Feijoada")).units, [.portion], "a plate with no weight: only the portion")
        XCTAssertEqual(FoodItem(common: common("Leite")).units, [.portion], "a glass in ml has no gram equivalence")
        XCTAssertEqual(FoodItem(common: common("Manteiga de amendoim")).units, [.gram, .tablespoon, .teaspoon, .portion])
        let noServing = FoodItem(product: OFFProduct(name: "Granola", kcal100: 450, protein100: 10, carbs100: 60, fat100: 18, serving: nil))
        XCTAssertEqual(noServing.units, [.gram, .tablespoon, .teaspoon], "no serving: no portion to offer")
        XCTAssertEqual(FoodItem(drink: "Chá verde", mg: 30, kcal: 0).units, [.portion])
        XCTAssertEqual(FoodItem(manual: "Jantar", kcal: 600, protein: 30).units, [.portion])
    }

    func testSpoonsAndGramsConvertByWeight() {
        let oats = FoodItem(product: OFFProduct(name: "Aveia", kcal100: 380, protein100: 13, carbs100: 60, fat100: 7, serving: nil))
        XCTAssertEqual(oats.unit, .gram)
        XCTAssertEqual(oats.quantity, 100)
        XCTAssertEqual(oats.totalKcal, 380, accuracy: 0.01)
        let spoons = oats.converted(to: .tablespoon)
        XCTAssertEqual(spoons.quantity, 6.5, "100 g is 6,7 tablespoons of 15 g, to the half spoon")
        XCTAssertEqual(spoons.totalKcal, 380 * 6.5 * 15 / 100, accuracy: 0.01)
        let butter = FoodItem(common: common("Manteiga de amendoim")).converted(to: .teaspoon)
        XCTAssertEqual(butter.quantity, 3, "a tablespoon is three teaspoons")
        XCTAssertEqual(butter.totalKcal, 95, accuracy: 0.01)
        XCTAssertEqual(butter.entry(date: Fixed.monday, minute: 600).grams, 15)
    }

    func testOneUnitOfACountedPortion() {
        var eggs = FoodItem(common: common("Ovos mexidos")).converted(to: .unit)
        XCTAssertEqual(eggs.quantity, 2, "the portion is 2 eggs")
        XCTAssertEqual(eggs.totalKcal, 200, accuracy: 0.01)
        eggs.change(by: -2)
        XCTAssertEqual(eggs.quantity, 1)
        XCTAssertEqual(eggs.totalKcal, 100, accuracy: 0.01)
        XCTAssertEqual(eggs.entry(date: Fixed.monday, minute: 600).unit, "unit")
    }

    func testAmountsReadAsPortugalWritesThem() {
        XCTAssertEqual(FoodUnit.gram.amount(150), "150 g")
        XCTAssertEqual(FoodUnit.portion.amount(0.7), "0,7 porção")
        XCTAssertEqual(FoodUnit.portion.amount(2), "2 porções")
        XCTAssertEqual(FoodUnit.tablespoon.amount(1), "1 colher de sopa")
        XCTAssertEqual(FoodUnit.teaspoon.amount(1.5), "1,5 colher de chá")
        XCTAssertEqual(FoodUnit.unit.amount(3), "3 unidades")
        XCTAssertEqual(FoodItem(common: common("Banana")).amountText, "1 porção · 1 média")
        XCTAssertEqual(FoodItem(common: common("Banana"), factor: 0.7).amountText, "0,7 porção · normal: 1 média")
    }

    func testTheGroupChoicesKeepAFoodsOwnMix() {
        XCTAssertEqual(FoodGoals.label("veg,veg"), "Legumes ×2")
        XCTAssertEqual(FoodGoals.label("soup,veg"), "Sopa e legumes")
        XCTAssertEqual(FoodGoals.label("fruit,soup,veg"), "Fruta, sopa e legumes")
        XCTAssertEqual(FoodGoals.label("bread"), "Nenhum")
        XCTAssertEqual(FoodGoals.choice(for: "bread"), FoodGoals.noGroup, "bread counts for no goal")
        XCTAssertEqual(FoodGoals.choice(for: "fruit,bread"), FoodGoals.fruit)
        XCTAssertEqual(FoodGoals.choices(current: FoodGoals.fruit).map(\.value), [FoodGoals.noGroup, FoodGoals.fruit, FoodGoals.soup, FoodGoals.veg])
        XCTAssertEqual(FoodGoals.choices(current: "veg,veg").last?.value, "veg,veg", "a plate with two sides keeps them")
    }

    /// The group comes from the food: every catalogue fruit is fruit, and no catalogue food counts for less than its
    /// name did until now
    func testCatalogueFoodsCountForTheirOwnGroup() {
        XCTAssertEqual(common("Tangerina").goals, FoodGoals.fruit)
        XCTAssertEqual(common("Sopa de legumes").goals, FoodGoals.soup)
        XCTAssertEqual(common("Salada mista").goals, FoodGoals.veg)
        XCTAssertEqual(common("Batido de proteína").goals, FoodGoals.noGroup)
        for f in commonFoods {
            let now = FoodGoals.count([FoodItem(common: f).entry(date: Fixed.monday, minute: 600)])
            let byName = FoodGoals.count([FoodEntry(date: Fixed.monday, minute: 600, name: f.name, kcal: f.kcal, protein: f.protein)])
            XCTAssertGreaterThanOrEqual(now.fruit, byName.fruit, f.name)
            XCTAssertGreaterThanOrEqual(now.soup, byName.soup, f.name)
            XCTAssertGreaterThanOrEqual(now.veg, byName.veg, f.name)
        }
    }
}

final class FoodConfirmationTests: RegressionCase {
    func testTheAmountIsEstimatedUntilYouConfirmIt() {
        let before = FoodEntry(date: Fixed.monday, minute: 600, name: "Banana", kcal: 105, protein: 1.3, group: FoodGoals.fruit, quantity: 1, unit: "portion", estimated: false)
        var item = FoodItem.again(before)
        XCTAssertFalse(item.quantityConfirmed, "having it once is not having the same again: a guess until you confirm it")
        XCTAssertEqual(item.entry().estimated, true)
        item.quantityConfirmed = true // «Confirmar quantidade»
        XCTAssertEqual(item.entry().estimated, false)
        item.dontKnow()
        XCTAssertFalse(item.quantityConfirmed, "«Não sei» keeps the estimate, marked as such")
        XCTAssertEqual(item.quantity, 1)
        item.change(by: 1)
        XCTAssertTrue(item.quantityConfirmed, "an amount you change is yours")
        XCTAssertEqual(item.quantity, 1.1)
        item.dontKnow()
        XCTAssertEqual(item.quantity, 1, "«Não sei» goes back to the typical amount")
        XCTAssertEqual(item.entry().estimated, true)
        XCTAssertEqual(FoodItem(common: common("Banana"), factor: 1.4).entry().estimated, false, "a size you picked is yours")
        XCTAssertEqual(FoodItem(drink: "Chá preto", mg: 45, kcal: 0).entry().estimated, true)
    }

    /// Every way of logging saves the amount, the unit, whether the amount is an estimate, and a group
    func testEverySavedFoodCarriesItsAmountUnitAndGroup() {
        let product = OFFProduct(name: "Skyr", kcal100: 63, protein100: 11, carbs100: 4, fat100: 0.2, serving: 150)
        var entries: [FoodEntry] = [
            FoodItem(common: common("Banana"), factor: 0.7).entry(date: Fixed.monday, minute: 600),
            FoodItem(drink: "Cola 330 ml", mg: 34, kcal: 139).entry(date: Fixed.monday, minute: 600),
            FoodItem(manual: "Arroz do almoço", kcal: 300, protein: 6).entry(date: Fixed.monday, minute: 600),
            FoodItem(product: product).entry(date: Fixed.monday, minute: 600),
            FoodItem(saved: SavedMeal(name: "Batido antigo", kcal: 260, protein: 34)).entry(date: Fixed.monday, minute: 600),
            MealBuilder.pieceOfFruit.entry(date: Fixed.monday, minute: 600),
        ]
        entries += MealBuilder.entries(MealDraft(bases: ["rice"], protein: "cod", method: .boiled), date: Fixed.monday, minute: 600)
        for e in entries {
            XCTAssertNotNil(e.quantity, e.name)
            XCTAssertNotNil(e.unit, e.name)
            XCTAssertNotNil(e.estimated, e.name)
            XCTAssertFalse((e.group ?? "").isEmpty, "\(e.name): the group is always saved")
        }
        let small = entries[0]
        XCTAssertEqual(small.name, "Banana", "the amount is saved apart, not in the name")
        XCTAssertEqual(small.kcal, 73.5, accuracy: 0.6)
        XCTAssertEqual(small.quantity, 0.7)
        XCTAssertEqual(small.unit, "portion")
        XCTAssertEqual(FoodGoals.count([small]).fruit, 1)
        XCTAssertEqual(entries[1].caffeine, 34)
        XCTAssertEqual(entries[3].grams, 150)
        XCTAssertEqual(entries[3].quantity, 150)
        XCTAssertEqual(entries[3].unit, "g")
    }

    /// Nutrients a food doesn't have are «Sem dados», never 0, in the meal's totals and in what is saved
    func testMissingNutrientsAreNoDataNotZero() {
        let banana = FoodItem(common: common("Banana")) // the catalogue has kcal and protein only
        XCTAssertNil(FoodMeal.totals([banana]).carbs)
        XCTAssertNil(banana.entry().carbs)
        let fruit = FoodItem(addOn: MealBuilder.pieceOfFruit)
        let both = FoodMeal.totals([banana, fruit])
        XCTAssertEqual(both.carbs ?? -1, 19, accuracy: 0.01)
        XCTAssertTrue(both.carbsPartial, "only some foods have it")
        XCTAssertFalse(FoodMeal.totals([fruit]).carbsPartial)
        XCTAssertEqual(both.kcal, 185, accuracy: 0.01)
    }

    /// Something had before, again: a new entry, with the nutrients and amount it was saved with
    func testAgainKeepsWhatItWasSavedWith() {
        let skyr = FoodEntry(id: "P", date: Fixed.monday, minute: 500, name: "Skyr Morango", kcal: 95, protein: 16, carbs: 6, fat: 0.3, grams: 150,
                             group: FoodGoals.noGroup, quantity: 150, unit: "g", estimated: false)
        let again = FoodItem.again(skyr)
        XCTAssertNotEqual(again.id, "P", "a new entry")
        XCTAssertNil(again.date, "it takes the day and time it is saved")
        XCTAssertEqual(again.unit, .gram)
        XCTAssertEqual(again.quantity, 150)
        XCTAssertEqual(again.totalKcal, 95, accuracy: 0.01)
        XCTAssertEqual(again.totalCarbs ?? -1, 6, accuracy: 0.01)
        XCTAssertEqual(again.units, [.gram, .tablespoon, .teaspoon])
        XCTAssertEqual(again.group, FoodGoals.noGroup)
        // older entries without a stored group: a catalogue food takes the catalogue's group, anything else what its
        // name counted as until now
        XCTAssertEqual(FoodItem.again(FoodEntry(date: Fixed.monday, minute: 500, name: "Tangerina", kcal: 70, protein: 1)).group, FoodGoals.fruit)
        // logged as "Tangerine" before phase 2.3 renamed it: no catalogue match, and the name rule never counted it
        XCTAssertEqual(FoodItem.again(FoodEntry(date: Fixed.monday, minute: 500, name: "Tangerine", kcal: 70, protein: 1)).group, FoodGoals.noGroup)
        XCTAssertEqual(FoodItem.again(FoodEntry(date: Fixed.monday, minute: 500, name: "Iogurte com banana", kcal: 150, protein: 8)).group, FoodGoals.fruit)
        XCTAssertEqual(FoodItem.again(FoodEntry(date: Fixed.monday, minute: 500, name: "Bacalhau", kcal: 400, protein: 30)).group, FoodGoals.noGroup)
    }

    /// The builder sends the plate and each add-on to the confirmation; nothing is saved by building
    func testTheBuilderConfirmsThePlateAndEachAddOn() {
        let d = MealDraft(bases: ["pure"], protein: "hake", method: .boiled, vegetables: ["salad-mixed", "grelos"], addOns: ["soup-veg", "cola"])
        let items = MealBuilder.items(d)
        XCTAssertEqual(items.map(\.name), [MealBuilder.name(d), "Sopa de legumes", "Cola"])
        XCTAssertEqual(items[0].group, "veg,veg")
        XCTAssertEqual(items[2].caffeine, 34)
        XCTAssertEqual(items.compactMap(\.addOnId), ["soup-veg", "cola"])
        XCTAssertEqual(FoodMeal.goals(items), FoodGoalCounts(soup: 1, veg: 2))
        XCTAssertEqual(FoodMeal.totals(items).kcal, MealBuilder.total(d).kcal, accuracy: 1)
    }

    @MainActor
    func testGuardarSavesTheMealOnceAndDesfazerTakesItBack() throws {
        let store = try makeStore()
        let items = [FoodItem(common: common("Banana")), FoodItem(drink: "Chá verde", mg: 30, kcal: 0)]
        XCTAssertTrue(store.foods(on: Fixed.saturday).isEmpty, "choosing saves nothing")
        let r = store.saveMeal(items, date: Fixed.saturday, minute: 780)
        XCTAssertEqual(Set(store.foods(on: Fixed.saturday).map(\.id)), Set(items.map(\.id)), "each food saved once, with the item's id")
        XCTAssertEqual(r.saved.map(\.minute), [780, 780], "all at the time of the meal")
        let again = store.saveMeal(items, date: Fixed.saturday, minute: 780)
        XCTAssertEqual(store.foods(on: Fixed.saturday).count, 2, "saving the same meal twice doesn't duplicate it")
        again.undo()
        XCTAssertEqual(store.foods(on: Fixed.saturday).count, 2, "undoing the second save leaves the first")
        r.undo()
        XCTAssertTrue(store.foods(on: Fixed.saturday).isEmpty, "Desfazer: nothing left")
    }

    @MainActor
    func testEditarReplacesTheSameEntryAndNeverDuplicates() throws {
        let banana = FoodEntry(id: "E1", date: Fixed.friday, minute: 13 * 60, name: "Banana", kcal: 105, protein: 1.3, group: FoodGoals.fruit, quantity: 1, unit: "portion", estimated: true)
        let soup = FoodEntry(id: "E2", date: Fixed.friday, minute: 13 * 60, name: "Sopa de legumes", kcal: 90, protein: 3, group: FoodGoals.soup, quantity: 1, unit: "portion", estimated: true)
        let store = try makeStore { s in
            s.add(banana)
            s.add(soup)
        }
        var item = FoodItem(editing: banana)
        XCTAssertEqual(item.id, "E1")
        XCTAssertEqual(item.date, Fixed.friday)
        XCTAssertEqual(item.minute, 13 * 60)
        XCTAssertFalse(item.quantityConfirmed)
        item.change(by: 10) // 2 portions
        let r = store.saveMeal([item], reopened: [banana, soup], date: Fixed.saturday, minute: 600)
        let friday = store.foods(on: Fixed.friday)
        XCTAssertEqual(friday.map(\.id), ["E1"], "replaced in place, same day and time; the food taken off the meal is gone")
        XCTAssertEqual(friday.first?.kcal, 210)
        XCTAssertEqual(friday.first?.quantity, 2)
        XCTAssertEqual(friday.first?.estimated, false)
        XCTAssertTrue(store.foods(on: Fixed.saturday).isEmpty, "not added again on the day it was edited")
        r.undo()
        XCTAssertEqual(store.record(FoodEntry.self, "E1"), banana, "Desfazer: back as it was")
        XCTAssertEqual(store.record(FoodEntry.self, "E2"), soup)
    }

    /// A saved meal counts one more use when it is eaten, not when its entry is edited; Desfazer gives the use back
    @MainActor
    func testASavedMealCountsAUseWhenSavedNotWhenEdited() throws {
        let meal = SavedMeal(id: "M1", name: "Batido", kcal: 260, protein: 34, group: FoodGoals.noGroup)
        let store = try makeStore { $0.add(meal) }
        let first = store.saveMeal([FoodItem(saved: meal)], date: Fixed.saturday, minute: 600)
        XCTAssertEqual(store.record(SavedMeal.self, "M1")?.uses, 1)
        let e = try XCTUnwrap(first.saved.first)
        XCTAssertEqual(e.mealId, "M1")
        store.saveMeal([FoodItem(editing: e)], reopened: [e])
        XCTAssertEqual(store.record(SavedMeal.self, "M1")?.uses, 1, "editing isn't eating it again")
        XCTAssertEqual(store.foods(on: Fixed.saturday).count, 1)
        first.undo()
        XCTAssertEqual(store.record(SavedMeal.self, "M1")?.uses, 0)
        XCTAssertTrue(store.foods(on: Fixed.saturday).isEmpty)
    }

    /// Quick capture's confirmation saves each food with the catalogue's group and a typical portion, as an estimate
    @MainActor
    func testQuickCaptureSavesTheGroupAndAnEstimatedPortion() throws {
        let store = try makeStore()
        let r = store.apply(.food([common("Banana"), common("Iogurte grego")], unmatched: []))
        let saved = store.foods()
        XCTAssertEqual(saved.count, 2)
        for e in saved {
            XCTAssertEqual(e.estimated, true, e.name)
            XCTAssertEqual(e.unit, "portion", e.name)
            XCTAssertEqual(e.quantity, 1, e.name)
        }
        XCTAssertEqual(saved.first { $0.name == "Banana" }?.group, FoodGoals.fruit)
        XCTAssertEqual(saved.first { $0.name == "Iogurte grego" }?.group, FoodGoals.noGroup)
        XCTAssertEqual(r.message, "2 alimentos registados")
        r.undo()
        XCTAssertTrue(store.foods().isEmpty)
    }

    /// Older entries still read; a new entry still reads in the build of 2 November, which doesn't know the new fields;
    /// a unit this build doesn't know never makes an entry unreadable
    func testFoodEntriesStayReadableBothWays() throws {
        let old = #"{"id":"a","date":"2026-01-01","minute":600,"name":"Maçã","kcal":95,"protein":0.5}"#
        let e = try JSONDecoder().decode(FoodEntry.self, from: Data(old.utf8))
        XCTAssertNil(e.quantity)
        XCTAssertNil(e.unit)
        XCTAssertNil(e.estimated)
        XCTAssertNil(e.amountText)
        let new = FoodItem(common: common("Banana"), factor: 1.4).entry(date: Fixed.monday, minute: 600)
        let previous = try JSONDecoder().decode(PreviousFoodEntry.self, from: JSONEncoder().encode(new))
        XCTAssertEqual(previous.id, new.id)
        XCTAssertEqual(previous.name, "Banana")
        XCTAssertEqual(previous.kcal, new.kcal)
        XCTAssertEqual(previous.group, FoodGoals.fruit)
        let future = #"{"id":"b","date":"2026-01-01","minute":600,"name":"X","kcal":10,"protein":0,"unit":"cup","quantity":1}"#
        let f = try JSONDecoder().decode(FoodEntry.self, from: Data(future.utf8))
        XCTAssertEqual(f.unit, "cup")
        XCTAssertNil(f.amountText)
        XCTAssertEqual(FoodItem.again(f).unit, .portion)
        XCTAssertEqual(FoodItem.again(f).totalKcal, 10, accuracy: 0.01)
    }
}

/// Kcal or protein Open Food Facts doesn't have: never 0. «Sem dados», empty, and the meal waits until you copy the
/// value from the label (rule «ausência ≠ zero»)
final class FoodMissingValueTests: RegressionCase {
    func testAMissingValueFromOpenFoodFactsIsNeverZero() {
        let none = OFFProduct.parse(json(#"{"product_name":"Bolachas","nutriments":{"carbohydrates_100g":60}}"#), code: "1")
        XCTAssertEqual(none.name, "Bolachas")
        XCTAssertNil(none.kcal100, "not 0")
        XCTAssertNil(none.protein100, "not 0")
        XCTAssertEqual(none.carbs100, 60)
        let full = OFFProduct.parse(json(#"{"product_name":"Skyr","nutriments":{"energy-kcal_100g":63,"proteins_100g":"11"},"serving_quantity":150}"#), code: "2")
        XCTAssertEqual(full.kcal100, 63, "values present are used as before")
        XCTAssertEqual(full.protein100, 11)
        XCTAssertEqual(full.serving, 150)
        let zero = OFFProduct.parse(json(#"{"nutriments":{"proteins_100g":0}}"#), code: "3")
        XCTAssertEqual(zero.protein100, 0, "a real 0 on the label stays 0")
        XCTAssertEqual(zero.name, "Produto 3")

        let found = FoodSearch.result(json(#"{"product_name":"Barra","code":"9","nutriments":{"energy-kcal_100g":400}}"#))
        XCTAssertNotNil(found)
        XCTAssertNil(found?.protein100, "not 0")
        XCTAssertEqual(found?.perHundred, "400 kcal /100 g · proteína: sem dados")
        let both = FoodSearch.result(json(#"{"product_name":"Barra","code":"9","nutriments":{"energy-kcal_100g":400,"proteins_100g":20}}"#))
        XCTAssertEqual(both?.perHundred, "400 kcal · 20 g /100 g")
        XCTAssertNil(FoodSearch.result(json(#"{"product_name":"Barra","nutriments":{"proteins_100g":10}}"#)), "with no kcal it isn't listed")
    }

    func testAProductWithAValueMissingCantBeSavedUntilYouTypeIt() {
        var item = FoodItem(product: OFFProduct(name: "Bolachas", kcal100: nil, protein100: 7.5, carbs100: 60, fat100: nil, serving: 50))
        XCTAssertTrue(item.kcalMissing)
        XCTAssertFalse(item.kcalKnown)
        XCTAssertFalse(item.proteinMissing)
        XCTAssertEqual(item.totalProtein, 3.75, accuracy: 0.001, "what it has is used as before")
        XCTAssertEqual(item.labelLine, "O Open Food Facts não tem as calorias deste produto: copia-as do rótulo.")
        XCTAssertFalse(FoodMeal.canSave([item]), "not until you type it")
        XCTAssertTrue(FoodMeal.totals([item]).kcalNoData, "«Sem dados», never 0")
        XCTAssertFalse(FoodMeal.totals([item]).proteinNoData)

        item.copyLabel(kcal100: 480) // per 100 g, as the label gives it, for the 50 g serving
        XCTAssertTrue(item.kcalKnown)
        XCTAssertEqual(item.totalKcal, 240, accuracy: 0.001)
        XCTAssertTrue(FoodMeal.canSave([item]))
        XCTAssertEqual(item.entry(date: Fixed.monday, minute: 600).kcal, 240)
        XCTAssertFalse(FoodMeal.totals([item]).kcalNoData)

        item.copyLabel(kcal100: nil) // the field emptied again
        XCTAssertFalse(item.kcalKnown)
        XCTAssertFalse(FoodMeal.canSave([item]))
        item.copyLabel(kcal100: 0)
        XCTAssertTrue(item.kcalKnown, "the label can say 0: that is a value you typed")
    }

    func testTheMealSaysWhatIsStillMissing() {
        let waiting = FoodItem(product: OFFProduct(name: "X", kcal100: nil, protein100: nil, carbs100: nil, fat100: nil, serving: nil))
        let banana = FoodItem(common: common("Banana"))
        let mixed = FoodMeal.totals([waiting, banana])
        XCTAssertFalse(mixed.kcalNoData)
        XCTAssertTrue(mixed.kcalPartial, "some foods don't have it yet")
        XCTAssertTrue(mixed.proteinPartial)
        XCTAssertEqual(mixed.kcal, banana.totalKcal, accuracy: 0.001)
        let alone = FoodMeal.totals([waiting])
        XCTAssertTrue(alone.kcalNoData)
        XCTAssertTrue(alone.proteinNoData)
        XCTAssertFalse(alone.kcalPartial)
        XCTAssertEqual(waiting.labelLine, "O Open Food Facts não tem as calorias nem a proteína deste produto: copia-as do rótulo.")
        XCTAssertNil(banana.labelLine)
        XCTAssertFalse(FoodMeal.canSave([banana, waiting]), "one food waiting holds the meal")
        XCTAssertTrue(FoodMeal.canSave([banana]))
        XCTAssertFalse(FoodMeal.canSave([]))
    }

    @MainActor
    func testAFoodWaitingForItsLabelIsNotSavedAsZero() throws {
        let store = try makeStore()
        var item = FoodItem(product: OFFProduct(name: "Bolachas", kcal100: nil, protein100: 7, carbs100: nil, fat100: nil, serving: nil))
        let refused = store.saveMeal([item], date: Fixed.saturday, minute: 600)
        XCTAssertTrue(refused.saved.isEmpty)
        XCTAssertTrue(store.foods(on: Fixed.saturday).isEmpty, "never saved as 0")
        item.copyLabel(kcal100: 450)
        store.saveMeal([item], date: Fixed.saturday, minute: 600)
        XCTAssertEqual(store.foods(on: Fixed.saturday).first?.kcal, 450)
    }

    func testWhatYouTypeInALabelField() {
        XCTAssertEqual(FoodItem.labelValue("12,5"), 12.5)
        XCTAssertEqual(FoodItem.labelValue(" 12.5 "), 12.5)
        XCTAssertEqual(FoodItem.labelValue("0"), 0, "the label can say 0")
        XCTAssertNil(FoodItem.labelValue(""), "empty is no value, not 0")
        XCTAssertNil(FoodItem.labelValue("abc"))
        XCTAssertNil(FoodItem.labelValue("-3"))
    }
}

/// «Comer» in the kitchen: the portion leaves the fridge and one estimated entry is logged, with its group; Desfazer
/// puts it all back
final class KitchenEatTests: RegressionCase {
    private let soup = Recipe(id: "R1", name: "Sopa de legumes", kcal: 90, protein: 3)
    private let rice = Recipe(id: "R2", name: "Frango com arroz", kcal: 600, protein: 45)

    private func portion(_ id: String, of r: Recipe) -> Portion {
        Portion(id: id, recipeId: r.id, name: r.name, eatBy: Fixed.sunday)
    }

    @MainActor
    func testComerSavesAGroupByTheNameRuleAndAnEstimate() throws {
        let p = portion("P1", of: soup), q = portion("P2", of: rice)
        let store = try makeStore { s in
            s.add(self.soup)
            s.add(self.rice)
            s.add(p)
            s.add(q)
        }
        _ = store.eat(p)
        let soupEntry = try XCTUnwrap(store.foods().first { $0.name == "Sopa de legumes" })
        XCTAssertEqual(soupEntry.kcal, 90)
        XCTAssertEqual(soupEntry.protein, 3)
        XCTAssertEqual(soupEntry.group, FoodGoals.legacyGroup(name: "Sopa de legumes"), "the rule other foods with no group of their own use")
        XCTAssertEqual(soupEntry.group, FoodGoals.soup)
        XCTAssertEqual(FoodGoals.count([soupEntry]).soup, 1)
        XCTAssertEqual(soupEntry.estimated, true, "marked estimated, as the other estimates")
        XCTAssertEqual(soupEntry.quantity, 1)
        XCTAssertEqual(soupEntry.unit, FoodUnit.portion.rawValue)
        XCTAssertEqual(store.record(Portion.self, "P1")?.eaten, Day.today)

        _ = store.eat(q)
        let riceEntry = try XCTUnwrap(store.foods().first { $0.name == "Frango com arroz" })
        XCTAssertEqual(riceEntry.group, FoodGoals.noGroup, "a group is always saved, also when it counts for none")
    }

    @MainActor
    func testDesfazerDeComerPutsThePortionBackAndRemovesTheEntry() throws {
        let p = portion("P1", of: rice)
        let store = try makeStore { s in
            s.add(self.rice)
            s.add(p)
        }
        let undo = store.eat(p)
        XCTAssertTrue(store.fridge.isEmpty, "the portion left the fridge")
        XCTAssertEqual(store.foods().count, 1, "and was logged")
        undo()
        XCTAssertEqual(store.fridge.map(\.id), ["P1"], "the portion is back")
        XCTAssertEqual(store.record(Portion.self, "P1"), p, "exactly as it was")
        XCTAssertTrue(store.foods().isEmpty, "and the entry is gone")
    }
}

/// One product however it's written: the list and Higiene compare names the same way
final class ProductKeyTests: RegressionCase {
    func testAccentsCaseAndExtraSpacesDontCount() {
        XCTAssertEqual(Store.productKey("  Maçã   Gala "), "maca gala")
        XCTAssertEqual(Store.productKey("Bioderma  SÉBIUM\tgel"), "bioderma sebium gel")
        XCTAssertEqual(Store.productKey("  Bioderma  SÉBIUM gel "), CareRules.productKey("  Bioderma  SÉBIUM gel "), "the comparison Higiene makes")
        XCTAssertEqual(Store.productKey("Protetor Solar"), Store.productKey("protetor  solar"))
        XCTAssertNotEqual(Store.productKey("Gel"), Store.productKey("Gel 2"))
    }

    @MainActor
    func testTwoSpellingsOfOneProductAreOneLine() throws {
        let a = ShoppingItem(id: "a", name: "Café  moído"), b = ShoppingItem(id: "b", name: "cafe moido")
        let store = try makeStore { s in
            s.add(a)
            s.add(b)
        }
        XCTAssertEqual(store.shoppingList().filter { Store.productKey($0.name) == "cafe moido" }.count, 1)
    }
}

final class WaterGoalTests: RegressionCase {
    func testTheSuggestionAndWhatItIsMadeOf() {
        let s = WaterGoals.suggestion(base: 3000, stepGoal: 8000, steps: 13000, trained: true)
        XCTAssertEqual(s, WaterSuggestion(base: 3000, steps: 500, training: 500, total: 4000))
        XCTAssertEqual(WaterGoals.why(s), "3 L habituais + 0,5 L pelo treino + 0,5 L pelos passos")
        XCTAssertEqual(WaterGoals.why(WaterGoals.suggestion(base: 2250, stepGoal: 8000, steps: nil, trained: false)), "2,25 L habituais")
        XCTAssertEqual(WaterGoals.litres(2250), "2,25")
        XCTAssertEqual(WaterGoals.litres(2800), "2,8")
        XCTAssertEqual(WaterGoals.litres(3000), "3")
    }

    @MainActor
    func testAnAcceptedGoalIsUsedForThatDayOnlyAndDesfazerGoesBackToTheSuggestion() throws {
        let store = try makeStore { s in
            s.profile.waterGoalMl = 3000
            s.profile.stepGoal = 8000
            s.health[Fixed.saturday] = HealthDay(date: Fixed.saturday, steps: 13000)
        }
        XCTAssertNil(store.waterGoalChoice(on: Fixed.saturday), "suggested until you accept or adjust it")
        XCTAssertEqual(store.waterGoal(on: Fixed.saturday), 3500)
        let undo = store.chooseWaterGoal(2800, on: Fixed.saturday)
        XCTAssertEqual(store.waterGoalChoice(on: Fixed.saturday)?.ml, 2800)
        XCTAssertEqual(store.waterGoal(on: Fixed.saturday), 2800, "the goal you chose is the day's goal")
        XCTAssertEqual(store.waterSuggestion(on: Fixed.saturday).total, 3500, "the suggestion itself doesn't change")
        XCTAssertEqual(store.waterGoal(on: Fixed.sunday), 3000, "another day keeps its suggestion")
        undo()
        XCTAssertNil(store.waterGoalChoice(on: Fixed.saturday))
        XCTAssertEqual(store.waterGoal(on: Fixed.saturday), 3500)
    }

    /// Adjusting twice and undoing the second goes back to the first; a goal outside the sensible range is never used
    @MainActor
    func testAdjustingAgainAndOutOfRangeGoals() throws {
        let store = try makeStore { $0.add(WaterGoalChoice(date: Fixed.sunday, ml: 0)) }
        XCTAssertNil(store.waterGoalChoice(on: Fixed.sunday), "0 ml is not a goal")
        XCTAssertEqual(store.waterGoal(on: Fixed.sunday), 3000)
        _ = store.chooseWaterGoal(2800, on: Fixed.saturday) // the Desfazer closure isn't needed here
        let undo = store.chooseWaterGoal(3210, on: Fixed.saturday)
        XCTAssertEqual(store.waterGoal(on: Fixed.saturday), 3200, "to the nearest 50 ml")
        undo()
        XCTAssertEqual(store.waterGoal(on: Fixed.saturday), 2800)
    }

    /// The choice is a record the server takes: an id of [A-Za-z0-9_.:-] up to 80 characters and an object value
    @MainActor
    func testTheChoiceIsARecordTheServerTakes() throws {
        let store = try makeStore()
        _ = store.chooseWaterGoal(2800, on: Fixed.saturday) // the Desfazer closure isn't needed here
        let records = store.records(WaterGoalChoice.kind)
        XCTAssertEqual(Array(records.keys), [Fixed.saturday])
        let server = try NSRegularExpression(pattern: "^[A-Za-z0-9_.:-]{1,80}$")
        for (id, value) in records {
            XCTAssertNotNil(server.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)), id)
            guard case .object(let o) = value else { return XCTFail("\(id): the server skips values that aren't objects") }
            XCTAssertEqual(o["ml"], .number(2800))
        }
    }
}
