// The meal builder and daily food goals, as pure calculation. Values are typical estimates per 100 g as eaten
// (cooked), with a normal portion for each; add-ons and goal defaults are per portion.
import Foundation

struct Macros: Equatable {
    var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }
    static func * (a: Macros, k: Double) -> Macros {
        Macros(kcal: a.kcal * k, protein: a.protein * k, carbs: a.carbs * k, fat: a.fat * k)
    }
    /// Whole kcal and grams, as logged
    var rounded: Macros { Macros(kcal: kcal.rounded(), protein: protein.rounded(), carbs: carbs.rounded(), fat: fat.rounded()) }
}

/// What cooking adds per 100 g of food: mostly the oil it takes up. Plain food has none of this.
enum CookMethod: String, CaseIterable, Codable {
    case grilled, baked, stewed, boiled, fried, breaded, scrambled

    var label: String {
        switch self {
        case .grilled: return "Grilled"
        case .baked: return "Roast"
        case .stewed: return "Stewed"
        case .boiled: return "Boiled"
        case .fried: return "Fried"
        case .breaded: return "Breaded"
        case .scrambled: return "Scrambled"
        }
    }

    var added: Macros {
        switch self {
        case .grilled: return Macros(kcal: 14, fat: 1.5)
        case .baked: return Macros(kcal: 36, fat: 4)
        case .stewed: return Macros(kcal: 45, fat: 5)
        case .boiled: return Macros()
        case .fried: return Macros(kcal: 72, fat: 8)
        case .breaded: return Macros(kcal: 142, protein: 1, carbs: 12, fat: 10)
        case .scrambled: return Macros(kcal: 45, fat: 5)
        }
    }
}

struct FoodPart: Identifiable, Hashable {
    var id: String
    var name: String
    var grams: Double // a normal portion
    var kcal: Double, protein: Double, carbs: Double, fat: Double // per 100 g
    var note: String
    var group: String
    var methods: [CookMethod]

    init(_ id: String, _ name: String, _ grams: Double, _ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double, note: String = "", group: String = "", methods: [CookMethod] = []) {
        self.id = id
        self.name = name
        self.grams = grams
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.note = note
        self.group = group
        self.methods = methods
    }

    func macros(method: CookMethod? = nil) -> Macros {
        let plain = Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
        return (plain + (method?.added ?? Macros())) * (grams / 100)
    }
}

/// A quick extra with a meal, logged as its own food. Values are for the whole portion.
struct AddOn: Identifiable, Hashable {
    var id: String
    var name: String
    var category: String
    var portion: String
    var kcal: Double, protein: Double, carbs: Double, fat: Double
    var group: String
    var caffeine: Double?

    init(_ id: String, _ name: String, _ category: String, _ portion: String, _ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double, group: String, caffeine: Double? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.portion = portion
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.group = group
        self.caffeine = caffeine
    }

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    func entry(date: String = Day.today, minute: Int = Day.minuteOfDay()) -> FoodEntry {
        FoodEntry(date: date, minute: minute, name: name, kcal: kcal, protein: protein, carbs: carbs, fat: fat, caffeine: caffeine, group: group)
    }
}

struct MealDraft: Equatable {
    var bases: Set<String> = []
    var protein: String?
    var method: CookMethod?
    var vegetables: Set<String> = []
    var sauces: Set<String> = []
    var addOns: Set<String> = []
    var factor = 1.0 // the whole plate; sauces and add-ons are counted as they are
}

struct MealDish: Identifiable {
    var id: String { name }
    var name: String
    var draft: MealDraft
}

enum MealBuilder {
    /// From this many kcal a logged food counts as a full meal and is offered add-ons
    static let fullMealKcal = 400.0
    static func isFullMeal(kcal: Double) -> Bool { kcal >= fullMealKcal }

    // MARK: Foods

    static let bases: [FoodPart] = [
        FoodPart("rice", "Rice", 180, 130, 2.7, 28, 0.3, note: "arroz"),
        FoodPart("rice-brown", "Brown rice", 180, 123, 2.7, 25.6, 1, note: "arroz integral"),
        FoodPart("rice-tomato", "Arroz de tomate", 200, 140, 2.5, 26, 3, note: "tomato rice"),
        FoodPart("rice-beans", "Arroz de feijão", 200, 150, 5, 27, 2.5, note: "rice and beans"),
        FoodPart("pasta", "Pasta", 200, 158, 5.8, 31, 0.9, note: "massa, esparguete"),
        FoodPart("pasta-whole", "Wholewheat pasta", 200, 150, 6, 30, 1.7, note: "massa integral"),
        FoodPart("pure", "Puré", 200, 105, 2, 15.5, 4.2, note: "mashed potato"),
        FoodPart("potato-boiled", "Boiled potatoes", 220, 87, 1.9, 20, 0.1, note: "batata cozida"),
        FoodPart("potato-roast", "Roast potatoes", 200, 150, 2.5, 24, 5, note: "batata assada"),
        FoodPart("potato-murro", "Batata a murro", 200, 130, 2.5, 22, 4, note: "punched, with oil"),
        FoodPart("potato-fried", "Fries", 150, 300, 3.5, 38, 15, note: "batata frita"),
        FoodPart("sweet-potato", "Sweet potato", 200, 90, 2, 21, 0.1, note: "batata doce"),
        FoodPart("couscous", "Couscous", 180, 110, 3.8, 23, 0.2),
        FoodPart("bread", "Bread", 80, 265, 9, 49, 3.2, note: "pão"),
        FoodPart("broa", "Broa", 80, 240, 6, 48, 3, note: "corn bread"),
    ]

    private static let lean: [CookMethod] = [.grilled, .baked, .stewed, .fried, .breaded]
    private static let fishWays: [CookMethod] = [.grilled, .baked, .boiled, .fried]

    static let proteinGroups = ["Meat", "Fish", "Eggs, veggie"]

    static let proteins: [FoodPart] = [
        // Meat, cooked without added fat
        FoodPart("chicken-breast", "Chicken breast", 150, 165, 31, 0, 3.6, note: "peito de frango", group: "Meat", methods: lean),
        FoodPart("chicken-thigh", "Chicken thigh", 150, 200, 25, 0, 11, note: "frango, perna", group: "Meat", methods: [.grilled, .baked, .stewed, .fried]),
        FoodPart("turkey", "Turkey", 150, 150, 30, 0, 2.5, note: "bife de peru", group: "Meat", methods: lean),
        FoodPart("beef-steak", "Beef steak", 150, 200, 27, 0, 10, note: "bife de vaca", group: "Meat", methods: [.grilled, .fried, .stewed]),
        FoodPart("beef-mince", "Minced beef", 130, 240, 24, 0, 16, note: "carne picada", group: "Meat"),
        FoodPart("burger", "Burger patty", 120, 250, 25, 0, 16.5, note: "hambúrguer", group: "Meat", methods: [.grilled, .fried]),
        FoodPart("pork-loin", "Pork loin", 150, 180, 28, 0, 7.5, note: "lombo", group: "Meat", methods: [.grilled, .baked, .stewed, .fried]),
        FoodPart("bifana", "Bifanas", 120, 195, 26, 1, 10, note: "pork in garlic and wine", group: "Meat"),
        FoodPart("febras", "Febras", 150, 210, 26, 0, 11.5, note: "pork steaks", group: "Meat", methods: [.grilled, .fried]),
        FoodPart("entrecosto", "Entrecosto", 180, 290, 24, 0, 21, note: "pork ribs", group: "Meat", methods: [.grilled, .baked]),
        FoodPart("entremeada", "Entremeada", 100, 380, 20, 0, 33, note: "pork belly", group: "Meat", methods: [.grilled, .fried]),
        FoodPart("sausages", "Sausages", 120, 300, 13, 2, 26, note: "salsichas", group: "Meat", methods: [.grilled, .fried]),
        FoodPart("alheira", "Alheira", 120, 260, 13, 18, 15, note: "1 whole", group: "Meat", methods: [.grilled, .fried]),
        FoodPart("duck", "Duck", 150, 200, 24, 0, 11, note: "pato", group: "Meat", methods: [.baked, .stewed]),
        FoodPart("lamb", "Lamb", 150, 250, 25, 0, 16.5, note: "borrego", group: "Meat", methods: [.grilled, .baked, .stewed]),
        FoodPart("kid", "Cabrito", 180, 160, 25, 0, 6.5, note: "roast kid", group: "Meat", methods: [.baked, .stewed]),
        // Fish
        FoodPart("salmon", "Salmon", 150, 206, 22, 0, 13, note: "salmão", group: "Fish", methods: [.grilled, .baked, .fried]),
        FoodPart("cod", "Bacalhau", 170, 105, 23, 0, 0.9, note: "cod", group: "Fish", methods: [.boiled, .baked, .grilled, .fried, .stewed]),
        FoodPart("tuna-fresh", "Fresh tuna", 120, 132, 28, 0, 1.3, note: "atum", group: "Fish", methods: [.grilled, .stewed]),
        FoodPart("tuna-tin", "Tinned tuna", 80, 190, 26, 0, 9.5, note: "atum em lata", group: "Fish"),
        FoodPart("hake", "Pescada", 170, 90, 18, 0, 1.5, note: "hake", group: "Fish", methods: [.boiled, .grilled, .fried, .breaded]),
        FoodPart("sardines", "Sardines", 150, 190, 24, 0, 10.5, note: "sardinhas", group: "Fish", methods: [.grilled, .fried]),
        FoodPart("sea-bream", "Dourada", 170, 130, 23, 0, 4, note: "sea bream", group: "Fish", methods: fishWays),
        FoodPart("sea-bass", "Robalo", 170, 125, 23, 0, 3.5, note: "sea bass", group: "Fish", methods: fishWays),
        FoodPart("carapau", "Carapau", 150, 135, 22, 0, 5, note: "horse mackerel", group: "Fish", methods: [.grilled, .fried]),
        FoodPart("mackerel", "Cavala", 130, 205, 22, 0, 13, note: "mackerel", group: "Fish", methods: [.grilled, .baked]),
        FoodPart("octopus", "Polvo", 170, 130, 25, 3, 1.5, note: "octopus", group: "Fish", methods: [.boiled, .baked, .grilled, .fried]),
        FoodPart("squid", "Lulas", 170, 110, 20, 3, 1.8, note: "squid", group: "Fish", methods: [.grilled, .stewed, .fried]),
        FoodPart("prawns", "Camarão", 120, 100, 22, 0, 1, note: "prawns", group: "Fish", methods: [.boiled, .grilled, .fried]),
        // Eggs and plants
        FoodPart("eggs", "Eggs", 100, 155, 13, 1, 11, note: "2 ovos", group: "Eggs, veggie", methods: [.boiled, .fried, .scrambled]),
        FoodPart("tofu", "Tofu", 150, 145, 15, 3, 8, group: "Eggs, veggie", methods: [.grilled, .fried, .stewed]),
        FoodPart("beans", "Beans", 180, 127, 8.5, 22, 0.5, note: "feijão", group: "Eggs, veggie"),
        FoodPart("chickpeas", "Chickpeas", 180, 164, 8.9, 27, 2.6, note: "grão", group: "Eggs, veggie"),
        FoodPart("lentils", "Lentils", 180, 116, 9, 20, 0.4, note: "lentilhas", group: "Eggs, veggie"),
    ]

    static let vegetables: [FoodPart] = [
        FoodPart("salad-mixed", "Mixed salad", 120, 20, 1, 3.5, 0.2, note: "alface, tomate"),
        FoodPart("salad-tomato", "Tomato and onion", 150, 25, 1, 4.5, 0.2, note: "salada de tomate"),
        FoodPart("veg-boiled", "Boiled vegetables", 150, 40, 2.5, 7, 0.4, note: "brócolos, cenoura"),
        FoodPart("veg-roast", "Roast vegetables", 150, 80, 2, 10, 3.5, note: "legumes assados"),
        FoodPart("green-beans", "Green beans", 150, 35, 2, 7, 0.2, note: "feijão verde"),
        FoodPart("grelos", "Grelos", 120, 70, 3, 5, 4, note: "sautéed greens"),
        FoodPart("spinach", "Spinach", 120, 60, 3, 3.5, 3.5, note: "espinafres salteados"),
    ]

    static let sauces: [FoodPart] = [
        FoodPart("olive-oil", "Olive oil", 12, 884, 0, 0, 100, note: "1 tbsp, azeite"),
        FoodPart("butter", "Butter", 10, 717, 0.9, 0.1, 81, note: "manteiga"),
        FoodPart("mayo", "Mayonnaise", 15, 680, 1, 1, 75, note: "maionese"),
        FoodPart("ketchup", "Ketchup", 15, 110, 1.2, 25, 0.2),
        FoodPart("tomato-sauce", "Tomato sauce", 80, 60, 1.5, 9, 2, note: "molho de tomate"),
        FoodPart("cream-sauce", "Cream sauce", 50, 200, 2, 5, 19, note: "molho de natas"),
        FoodPart("gravy", "Roast gravy", 40, 90, 2, 5, 7, note: "molho do assado"),
        FoodPart("piri-piri", "Piri-piri", 10, 120, 1, 5, 11),
        FoodPart("cheese", "Grated cheese", 20, 400, 25, 1.5, 33, note: "queijo ralado"),
        FoodPart("egg-top", "Fried egg", 50, 196, 13.6, 0.8, 15, note: "ovo a cavalo"),
        FoodPart("chourico", "Chouriço", 50, 400, 24, 2, 33, note: "a few slices"),
    ]

    // MARK: Add-ons and goal defaults

    static let pieceOfFruit = AddOn("fruit", "Piece of fruit", "Fruit", "1 medium", 80, 0.8, 19, 0.3, group: FoodGoals.fruit)
    static let mugOfSoup = AddOn("soup-veg", "Sopa de legumes", "Soup", "1 mug", 90, 3, 12, 3, group: FoodGoals.soup)
    static let vegPortion = AddOn("veg", "Portion of vegetables", "Salad", "1 side", 45, 2.5, 7.5, 0.4, group: FoodGoals.veg)

    static let addOnCategories = ["Fruit", "Soup", "Salad", "Bread", "Dessert", "Drink"]

    static let addOns: [AddOn] = [
        pieceOfFruit,
        AddOn("banana", "Banana", "Fruit", "1 medium", 105, 1.3, 27, 0.4, group: FoodGoals.fruit),
        AddOn("apple", "Maçã", "Fruit", "1 medium", 95, 0.5, 25, 0.3, group: FoodGoals.fruit),
        AddOn("orange", "Laranja", "Fruit", "1 medium", 62, 1.2, 15, 0.2, group: FoodGoals.fruit),
        AddOn("fruit-salad", "Salada de fruta", "Fruit", "1 bowl", 90, 1, 22, 0.3, group: FoodGoals.fruit),
        mugOfSoup,
        AddOn("caldo-verde", "Caldo verde", "Soup", "1 mug", 110, 4, 11, 5.5, group: FoodGoals.soup),
        AddOn("soup-cream", "Creme de legumes", "Soup", "1 mug", 120, 3, 14, 6, group: FoodGoals.soup),
        AddOn("canja", "Canja", "Soup", "1 mug", 100, 7, 12, 2.5, group: FoodGoals.soup),
        AddOn("salad-side", "Salada mista", "Salad", "1 side, with oil", 70, 1.2, 4, 5.5, group: FoodGoals.veg),
        AddOn("salad-tomato-side", "Salada de tomate", "Salad", "1 side, with oil", 50, 1.2, 6, 2.5, group: FoodGoals.veg),
        vegPortion,
        AddOn("bread-roll", "Pão", "Bread", "1 roll", 135, 4.5, 25, 1.5, group: "bread"),
        AddOn("broa-slice", "Broa", "Bread", "1 slice", 145, 3.5, 29, 1.8, group: "bread"),
        AddOn("bread-butter", "Pão with butter", "Bread", "1 roll", 205, 5, 25, 9.5, group: "bread"),
        AddOn("olives", "Azeitonas", "Bread", "a small dish", 50, 0.3, 1, 5, group: "bread"),
        AddOn("arroz-doce", "Arroz doce", "Dessert", "1 dish", 240, 5, 42, 5.5, group: "dessert"),
        AddOn("pudim", "Pudim flan", "Dessert", "1 slice", 170, 4.5, 28, 4.5, group: "dessert"),
        AddOn("mousse", "Mousse de chocolate", "Dessert", "1 pot", 230, 5, 23, 13, group: "dessert"),
        AddOn("nata", "Pastel de nata", "Dessert", "1", 220, 3.5, 26, 11, group: "dessert"),
        AddOn("gelatine", "Gelatina", "Dessert", "1 pot", 70, 1.5, 16, 0, group: "dessert"),
        AddOn("ice-cream", "Gelado", "Dessert", "2 scoops", 270, 5, 32, 14, group: "dessert"),
        AddOn("cake", "Fatia de bolo", "Dessert", "1 slice", 300, 4, 42, 13, group: "dessert"),
        AddOn("wine", "Wine", "Drink", "1 glass", 125, 0, 4, 0, group: "drink"),
        AddOn("beer", "Beer", "Drink", "1 imperial", 85, 0.6, 6.5, 0, group: "drink"),
        AddOn("juice", "Sumo de laranja", "Drink", "1 glass", 110, 2, 25, 0.5, group: "drink"),
        AddOn("cola", "Cola", "Drink", "330 ml", 139, 0, 35, 0, group: "drink", caffeine: 34),
        AddOn("cola-zero", "Cola zero", "Drink", "330 ml", 1, 0, 0, 0, group: "drink", caffeine: 34),
    ]

    // MARK: Typical plates as starting points

    private static func dish(_ name: String, _ bases: Set<String>, _ protein: String, _ method: CookMethod?, _ vegetables: Set<String> = [], _ sauces: Set<String> = []) -> MealDish {
        MealDish(name: name, draft: MealDraft(bases: bases, protein: protein, method: method, vegetables: vegetables, sauces: sauces))
    }

    static let dishes: [MealDish] = [
        dish("Bitoque", ["potato-fried", "rice"], "beef-steak", .fried, [], ["egg-top"]),
        dish("Bacalhau à Brás", ["potato-fried"], "cod", .boiled, [], ["egg-top"]),
        dish("Bacalhau com natas", ["potato-fried"], "cod", .boiled, [], ["cream-sauce"]),
        dish("Bacalhau à lagareiro", ["potato-murro"], "cod", .baked, ["grelos"], ["olive-oil"]),
        dish("Frango no churrasco", ["potato-fried"], "chicken-thigh", .grilled, ["salad-mixed"], ["piri-piri"]),
        dish("Febras com arroz", ["rice", "potato-fried"], "febras", .grilled, ["salad-mixed"]),
        dish("Bifanas no prato", ["potato-fried"], "bifana", nil, ["salad-mixed"]),
        dish("Sardinhas assadas", ["potato-boiled"], "sardines", .grilled, ["salad-tomato"], ["olive-oil"]),
        dish("Polvo à lagareiro", ["potato-murro"], "octopus", .baked, ["grelos"], ["olive-oil"]),
        dish("Arroz de pato", ["rice"], "duck", .baked, [], ["chourico"]),
        dish("Feijoada", ["rice"], "beans", nil, [], ["chourico"]),
        dish("Alheira com ovo", ["potato-fried"], "alheira", .fried, ["grelos"], ["egg-top"]),
        dish("Massa com atum", ["pasta"], "tuna-tin", nil, [], ["tomato-sauce"]),
        dish("Esparguete à bolonhesa", ["pasta"], "beef-mince", nil, [], ["tomato-sauce", "cheese"]),
        dish("Salmão com legumes", ["potato-boiled"], "salmon", .grilled, ["veg-boiled"]),
    ]

    // MARK: Calculation

    static func base(_ id: String) -> FoodPart? { bases.first { $0.id == id } }
    static func protein(_ id: String) -> FoodPart? { proteins.first { $0.id == id } }

    /// Two sides share the plate instead of doubling it: rice and fries is 60% of each
    static func baseShare(count: Int) -> Double { count <= 1 ? 1 : 1.2 / Double(count) }

    /// The cooking method in effect: none when the food has no choice, the first way when none was picked
    static func effectiveMethod(_ d: MealDraft) -> CookMethod? {
        guard let id = d.protein, let p = protein(id), !p.methods.isEmpty else { return nil }
        if let m = d.method, p.methods.contains(m) { return m }
        return p.methods.first
    }

    /// The plate, scaled by the portion, plus sauces as they are
    static func plate(_ d: MealDraft) -> Macros {
        var scaled = Macros()
        let share = baseShare(count: d.bases.count)
        for b in bases where d.bases.contains(b.id) { scaled = scaled + b.macros() * share }
        if let id = d.protein, let p = protein(id) { scaled = scaled + p.macros(method: effectiveMethod(d)) }
        for v in vegetables where d.vegetables.contains(v.id) { scaled = scaled + v.macros() }
        var total = scaled * d.factor
        for s in sauces where d.sauces.contains(s.id) { total = total + s.macros() }
        return total
    }

    /// Plate and add-ons: what the estimate shows
    static func total(_ d: MealDraft) -> Macros {
        var t = plate(d)
        for a in addOns where d.addOns.contains(a.id) { t = t + a.macros }
        return t
    }

    static func isEmpty(_ d: MealDraft) -> Bool { d.bases.isEmpty && d.protein == nil && d.vegetables.isEmpty && d.sauces.isEmpty && d.addOns.isEmpty }

    /// The typical plate this draft still is, ignoring portion and add-ons
    static func matchingDish(_ d: MealDraft) -> MealDish? {
        dishes.first { x in
            x.draft.bases == d.bases && x.draft.protein == d.protein && effectiveMethod(x.draft) == effectiveMethod(d)
                && x.draft.vegetables == d.vegetables && x.draft.sauces == d.sauces
        }
    }

    /// The name of the plate: the dish it matches, or what's on it
    static func name(_ d: MealDraft) -> String {
        var text: String
        if let m = matchingDish(d) {
            text = m.name
        } else {
            var parts: [String] = []
            if let id = d.protein, let p = protein(id) {
                let method = effectiveMethod(d).map { " " + $0.label.lowercased() } ?? ""
                parts.append(p.name + method)
            }
            for b in bases where d.bases.contains(b.id) { parts.append(b.name) }
            for v in vegetables where d.vegetables.contains(v.id) { parts.append(v.name) }
            if parts.isEmpty { for s in sauces where d.sauces.contains(s.id) { parts.append(s.name) } }
            let later = parts.dropFirst().map { $0.lowercased() }
            text = parts.isEmpty ? "Custom meal" : ([parts[0]] + later).joined(separator: ", ")
        }
        if abs(d.factor - 1) > 0.001 { text += " (\(Int((d.factor * 100).rounded()))%)" }
        return text
    }

    /// One group token per vegetable side, so salad and greens count as two portions
    static func plateGroup(_ d: MealDraft) -> String {
        let tokens = vegetables.filter { d.vegetables.contains($0.id) }.map { _ in FoodGoals.veg }
        return tokens.isEmpty ? FoodGoals.meal : tokens.joined(separator: ",")
    }

    /// What Save logs: the plate, then each add-on as its own food
    static func entries(_ d: MealDraft, date: String = Day.today, minute: Int = Day.minuteOfDay()) -> [FoodEntry] {
        var out: [FoodEntry] = []
        let p = plate(d).rounded
        if p.kcal > 0 {
            out.append(FoodEntry(date: date, minute: minute, name: name(d), kcal: p.kcal, protein: p.protein, carbs: p.carbs, fat: p.fat, group: plateGroup(d)))
        }
        for a in addOns where d.addOns.contains(a.id) { out.append(a.entry(date: date, minute: minute)) }
        return out
    }

    /// A favourite holds the whole meal in one tap: plate and add-ons together, with every group they count for
    static func favourite(_ d: MealDraft, name custom: String? = nil) -> SavedMeal {
        let t = total(d).rounded
        let chosen = addOns.filter { d.addOns.contains($0.id) }
        var fallback = name(d)
        for a in chosen { fallback += " + " + a.name.lowercased() }
        var tokens: [String] = plateGroup(d) == FoodGoals.meal ? [] : [plateGroup(d)]
        tokens += chosen.map(\.group)
        let typed = (custom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let caffeine = chosen.compactMap(\.caffeine).reduce(0, +)
        return SavedMeal(name: typed.isEmpty ? fallback : typed, kcal: t.kcal, protein: t.protein, carbs: t.carbs, fat: t.fat, caffeine: caffeine > 0 ? caffeine : nil,
                         group: tokens.isEmpty ? FoodGoals.meal : tokens.joined(separator: ","), built: true)
    }
}

// MARK: - Daily food goals

struct FoodGoalCounts: Equatable {
    var fruit = 0, soup = 0, veg = 0
}

enum FoodGoals {
    static let fruit = "fruit", soup = "soup", veg = "veg", meal = "meal"
    static let fruitTarget = 2, soupTarget = 1, vegTarget = 2
    static let proteinMealGrams = 20.0, proteinMeals = 3

    private static let fruitWords = ["fruta", "fruit", "maca", "apple", "banana", "laranja", "orange", "pera", "pear", "pessego", "peach", "ameixa", "plum", "kiwi", "uva", "grape",
                                     "morango", "strawberry", "strawberries", "melao", "meloes", "meloa", "melon", "melancia", "watermelon", "ananas", "pineapple", "tangerina", "clementina", "mandarin",
                                     "cereja", "cherry", "cherries", "figo", "fig", "manga", "mango", "diospiro", "mirtilo", "blueberry", "blueberries", "framboesa", "raspberry", "raspberries", "nectarina", "damasco", "papaia", "papaya"]
    /// Fruit by name but not a piece of fruit
    private static let notWholeFruit = ["sumo", "juice", "bolo", "cake", "tarte", "pie", "compota", "jam", "doce", "batido", "smoothie", "gelado", "ice cream", "sorbet", "mousse", "muffin", "banana bread", "pao de banana",
                                        "barra", "bar", "cereais", "bolacha", "biscuit", "chocolate"]
    private static let soupWords = ["sopa", "soup", "caldo verde", "caldo", "canja", "creme de legumes", "creme de cenoura", "creme de abobora", "creme de ervilhas", "gaspacho", "gazpacho"]
    private static let saladWords = ["salada", "salad"]
    private static let vegWords = ["legume", "vegetal", "vegetais", "vegetable", "veggie", "verdura", "hortalica", "brocolo", "broccoli", "espinafre", "spinach", "couve", "cabbage", "kale", "grelo", "nabica",
                                   "feijao verde", "green bean", "cenoura", "carrot", "courgette", "curgete", "beringela", "aubergine", "pepino", "cucumber", "alface", "lettuce", "tomate", "tomato",
                                   "espargo", "asparagus", "pimento", "cogumelo", "mushroom", "ervilha", "abobora"]
    /// Phrases that look like a group but don't count for it
    private static let notVeg = ["molho de tomate", "tomato sauce", "arroz de tomate", "tomato rice", "salada russa", "russian salad", "salada de batata", "potato salad"]
    private static let fruitSalad = ["salada de fruta", "salada de frutas", "fruit salad"]

    /// Lowercase, no accents, words separated by single spaces, padded so whole words can be matched
    static func normalize(_ s: String) -> String {
        let folded = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        let cleaned = folded.map { (c: Character) -> Character in c.isLetter || c.isNumber ? c : " " }
        return " " + String(cleaned).split(separator: " ").joined(separator: " ") + " "
    }

    private static func has(_ hay: String, _ words: [String]) -> Bool {
        words.contains { hay.contains(" \($0) ") || hay.contains(" \($0)s ") }
    }

    private static func without(_ hay: String, _ phrases: [String]) -> String {
        var out = hay
        for p in phrases { out = out.replacingOccurrences(of: " \(p) ", with: " ") }
        return out
    }

    /// What a food's name counts for. Soup covers its own vegetables, so only a salad beside it adds a veg portion.
    static func groups(name: String) -> [String] {
        let hay = normalize(name)
        var out: [String] = []
        let isFruitSalad = has(hay, fruitSalad)
        let rest = without(without(hay, fruitSalad), notVeg)
        let isSoup = has(rest, soupWords)
        if isFruitSalad || isWholeFruit(hay) { out.append(fruit) }
        if isSoup { out.append(soup) }
        if has(rest, saladWords) || (!isSoup && has(rest, vegWords)) { out.append(veg) }
        return out
    }

    private static func isWholeFruit(_ hay: String) -> Bool {
        guard has(hay, fruitWords), !has(hay, notWholeFruit) else { return false }
        // "Iogurte de morango" is a yogurt; "iogurte com banana" has a banana in it
        if has(hay, ["iogurte", "yogurt", "yoghurt"]) { return has(hay, ["com", "with", "and", "e"]) }
        return true
    }

    /// A set group wins over the name; old entries have none and are read from the name
    static func groups(of e: FoodEntry) -> [String] {
        if let g = e.group, !g.isEmpty { return g.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        return groups(name: e.name)
    }

    static func count(_ foods: [FoodEntry]) -> FoodGoalCounts {
        var c = FoodGoalCounts()
        for e in foods {
            for g in groups(of: e) {
                if g == fruit { c.fruit += 1 } else if g == soup { c.soup += 1 } else if g == veg { c.veg += 1 }
            }
        }
        return c
    }

    static func goalsMet(_ c: FoodGoalCounts) -> Int {
        (c.fruit >= fruitTarget ? 1 : 0) + (c.soup >= soupTarget ? 1 : 0) + (c.veg >= vegTarget ? 1 : 0)
    }

    /// What's left, in words: ["1 piece of fruit", "1 mug of soup", "2 portions of veg"]
    static func missing(_ c: FoodGoalCounts) -> [String] {
        var out: [String] = []
        let f = fruitTarget - c.fruit, s = soupTarget - c.soup, v = vegTarget - c.veg
        if f > 0 { out.append(f == 1 ? "1 piece of fruit" : "\(f) pieces of fruit") }
        if s > 0 { out.append(s == 1 ? "1 mug of soup" : "\(s) mugs of soup") }
        if v > 0 { out.append(v == 1 ? "1 portion of veg" : "\(v) portions of veg") }
        return out
    }

    static func line(_ c: FoodGoalCounts, minute: Int) -> String {
        let left = missing(c)
        if left.isEmpty { return "All done today. This is what a good week is made of." }
        if c == FoodGoalCounts() { return minute < 17 * 60 ? "Today, aim for at least 2 pieces of fruit, 1 mug of soup and 2 portions of veg." : "Still time: a mug of soup and some veg with dinner gets you going." }
        if minute >= 17 * 60, c.soup < soupTarget { return "A mug of soup with dinner ticks one off. Left: " + joined(left) + "." }
        return "Good going. Left: " + joined(left) + "."
    }

    private static func joined(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Protein per eating occasion: foods within an hour of the occasion's start are one sitting
    static func proteinSittings(_ foods: [FoodEntry]) -> [Double] {
        var out: [Double] = []
        var start = Int.min
        for e in foods.sorted(by: { $0.minute < $1.minute }) {
            if let last = out.indices.last, e.minute - start <= 60 {
                out[last] += e.protein
            } else {
                out.append(e.protein)
                start = e.minute
            }
        }
        return out
    }

    /// Spreading protein over meals: how many had enough, and what to aim for next
    static func proteinHint(_ foods: [FoodEntry], target: Double) -> String {
        let got = foods.map(\.protein).reduce(0, +)
        let strong = proteinSittings(foods).filter { $0 >= proteinMealGrams }.count
        if target > 0, got >= target { return "Protein done: \(Int(got)) g today." }
        if foods.isEmpty || strong == 0 && got == 0 { return "Protein: spread it, about \(fives(target / 4)) g at each of 3 to 4 meals." }
        let mealsLeft = max(1, proteinMeals - strong)
        let next = fives(min(60, max(proteinMealGrams, (target - got) / Double(mealsLeft))))
        return "Protein: \(strong) of \(proteinMeals) meals at \(Int(proteinMealGrams)) g+. Aim for about \(next) g next."
    }

    private static func fives(_ x: Double) -> Int { Int((x / 5).rounded()) * 5 }
}
