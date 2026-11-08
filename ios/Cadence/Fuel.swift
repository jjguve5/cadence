// Fuel: food, water, caffeine and weight, and the rules on top: adaptive targets, energy balance, protein catch-up,
// water at your pace and the kitchen closing time. Phase 2.7: the water goal suggested until you choose it, and the
// foods of a meal as they wait on the confirmation (FoodItem) until «Guardar refeição» saves them (Store.saveMeal).
import Foundation

struct FoodEntry: Record, Equatable {
    static let kind = "food"
    var id = UUID().uuidString
    var date = Day.today
    var minute = Day.minuteOfDay()
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double?
    var fat: Double?
    var grams: Double?
    var caffeine: Double? // mg
    var mealId: String?
    var promiseId: String? // logged by ticking a routine
    var group: String? // comma-separated: fruit, soup, veg... Wins over name keywords (FoodGoals). Always saved from phase 2.7
    // Phase 2.7 (decisions 56–58). Optional, so older entries still read and an older build ignores them.
    var quantity: Double? // how much, in `unit`
    var unit: String? // a FoodUnit raw value ("g", "unit", "tbsp", "tsp", "portion"), kept as text: an unknown one never breaks the entry
    var estimated: Bool? // the quantity: true until you confirm it; nil on older entries. Nutrients are always estimates (tables)

    /// The amount as saved ("150 g", "0,7 porção"); nil on older entries, which have none
    var amountText: String? {
        guard let q = quantity, let u = unit.flatMap(FoodUnit.init(rawValue:)) else { return nil }
        return u.amount(q)
    }
}

struct SavedMeal: Record, Equatable {
    static let kind = "meal"
    var id = UUID().uuidString
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double?
    var fat: Double?
    var caffeine: Double?
    var uses = 0
    var lastUsed: Double = 0
    var group: String?
    var built: Bool? // favourite from the meal builder
}

struct WaterEntry: Record, Equatable {
    static let kind = "water"
    var id = UUID().uuidString
    var date = Day.today
    var minute = Day.minuteOfDay()
    var ml: Double
}

struct WeightEntry: Record, Equatable {
    static let kind = "weight"
    var id: String { date }
    var date = Day.today
    var kg: Double
    var source: String? // "health" when it came from Apple Health through the Shortcut; typed ones win
}

/// Common caffeine sources, since there's no coffee to track
let caffeineDrinks: [(name: String, mg: Double, kcal: Double)] = [
    ("Cola 330 ml", 34, 139), ("Cola zero 330 ml", 34, 1), ("Ice tea 330 ml", 25, 60), ("Bebida energética 250 ml", 80, 112),
    ("Chá verde", 30, 0), ("Chá preto", 45, 0), ("Chocolate negro 30 g", 24, 170),
]

struct FuelDay {
    var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0, caffeine = 0.0, water = 0.0
    var lastMeal: Int?
    var lastCaffeine: Int?
}

@MainActor
extension Store {
    func foods(on day: String = Day.today) -> [FoodEntry] { all(FoodEntry.self).filter { $0.date == day }.sorted { $0.minute < $1.minute } }

    func fuel(on day: String = Day.today) -> FuelDay {
        var f = FuelDay()
        for e in foods(on: day) {
            f.kcal += e.kcal; f.protein += e.protein; f.carbs += e.carbs ?? 0; f.fat += e.fat ?? 0
            if let c = e.caffeine, c > 0 { f.caffeine += c; f.lastCaffeine = max(f.lastCaffeine ?? 0, e.minute) }
            if e.kcal > 50 { f.lastMeal = max(f.lastMeal ?? 0, e.minute) }
        }
        f.water = all(WaterEntry.self).filter { $0.date == day }.map(\.ml).reduce(0, +)
        return f
    }

    /// The suggested water goal rises with steps above your goal and on training days (decision 47: a suggestion, until
    /// you accept or adjust it)
    func waterSuggestion(on day: String = Day.today) -> WaterSuggestion {
        WaterGoals.suggestion(base: profile.waterGoalMl, stepGoal: profile.stepGoal, steps: health[day]?.steps, trained: !sessions(on: day).isEmpty)
    }

    /// The goal you accepted or adjusted for that day, if any (and if it is a sensible amount)
    func waterGoalChoice(on day: String = Day.today) -> WaterGoalChoice? {
        guard let c = record(WaterGoalChoice.self, day), WaterGoals.accepted.contains(c.ml) else { return nil }
        return c
    }

    /// The day's water goal: the one you accepted or adjusted, else the suggestion. Rings, pace and reminders use this
    func waterGoal(on day: String = Day.today) -> Double {
        waterGoalChoice(on: day)?.ml ?? waterSuggestion(on: day).total
    }

    /// «Aceitar meta» or «Ajustar»: the goal for that day becomes yours. Returns how to undo it (back to what it was)
    @discardableResult
    func chooseWaterGoal(_ ml: Double, on day: String = Day.today) -> () -> Void {
        let before = record(WaterGoalChoice.self, day)
        let value = min(WaterGoals.accepted.upperBound, max(WaterGoals.accepted.lowerBound, (ml / 50).rounded() * 50))
        save(WaterGoalChoice(date: day, ml: value))
        return {
            if let before { self.save(before) } else { self.remove(WaterGoalChoice(date: day, ml: value)) }
        }
    }

    /// Where water should be by now: a straight line from waking to two hours before bed
    func waterPace(now: Date = Date()) -> Double {
        let start = profile.wakeMinute, end = sleepPlan().perform - 120
        let m = Day.minuteOfDay(now)
        let share = min(1, max(0, Double(m - start) / Double(max(60, end - start))))
        return waterGoal() * share
    }

    func logFood(_ e: FoodEntry) {
        save(e)
        if let id = e.mealId, var meal = record(SavedMeal.self, id) { meal.uses += 1; meal.lastUsed = nowMs(); save(meal) }
    }

    /// Returns the entry, so Desfazer can take it back
    @discardableResult
    func addWater(_ ml: Double) -> WaterEntry {
        let e = WaterEntry(ml: ml)
        save(e)
        return e
    }

    /// Saved meals and recent foods, most used first: the fast log
    var quickFoods: [SavedMeal] {
        let meals = all(SavedMeal.self).sorted { ($0.uses, $0.lastUsed) > ($1.uses, $1.lastUsed) }
        let recent = all(FoodEntry.self).filter { $0.mealId == nil && $0.promiseId == nil }.sorted { ($0.date, $0.minute) > ($1.date, $1.minute) }
        var seen = Set(meals.map { $0.name.lowercased() })
        var out = meals
        for e in recent where !seen.contains(e.name.lowercased()) {
            seen.insert(e.name.lowercased())
            out.append(SavedMeal(id: "recent-" + e.id, name: e.name, kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, caffeine: e.caffeine, group: e.group))
            if out.count > 40 { break }
        }
        return out
    }

    /// Behind on protein in the evening: the saved meal that closes most of the gap
    func proteinCatchUp() -> (gap: Double, meal: SavedMeal?)? {
        let left = profile.proteinTarget - fuel().protein
        guard left > 15, Day.minuteOfDay() >= 16 * 60 else { return nil }
        let meal = all(SavedMeal.self).filter { $0.protein >= 15 }.min { abs($0.protein - left) < abs($1.protein - left) }
        return (left, meal)
    }

    /// Weekly check-in: from the smoothed weight trend and what you ate, the calories that hit your goal
    func adaptiveTarget() -> (kcal: Double, tdee: Double, trendKgPerWeek: Double)? {
        let weights = all(WeightEntry.self).filter { Day.between($0.date, Day.today) <= 28 }.sorted { $0.date < $1.date }
        guard weights.count >= 4, let first = weights.first, let last = weights.last, Day.between(first.date, last.date) >= 10 else { return nil }
        let days = (0..<28).map { Day.add(-$0, to: Day.today) }
        let logged = days.map { fuel(on: $0).kcal }.filter { $0 > 800 }
        guard logged.count >= 10 else { return nil }
        let intake = logged.reduce(0, +) / Double(logged.count)
        // Least squares slope of weight per day
        let xs = weights.map { Double(Day.between(first.date, $0.date)) }, ys = weights.map(\.kg)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let slope = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +) / max(0.001, xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +))
        let tdee = intake - slope * 7700
        let target = profile.goal == "lose" ? tdee - 400 : profile.goal == "gain" ? tdee + 250 : tdee
        return ((target / 10).rounded() * 10, tdee, slope * 7)
    }
}

// MARK: - The water goal: suggested until you accept or adjust it (decision 47)

/// The water goal you accepted or adjusted for one day. Record "watergoal", id = the day (yyyy-MM-dd), an object
/// value; a day without one shows the goal as «Sugerido»
struct WaterGoalChoice: Record, Equatable {
    static let kind = "watergoal"
    var id: String { date }
    var date = Day.today
    var ml: Double
    var at = nowMs()
}

/// The suggestion and what it is made of, for the «Porquê» line
struct WaterSuggestion: Equatable {
    var base: Double // your usual goal (the profile's)
    var steps: Double // added for steps above your step goal
    var training: Double // added on a training day
    var total: Double // rounded to 50 ml
}

enum WaterGoals {
    /// A goal you set is used only within this range; outside it the suggestion stands
    static let accepted = 500.0...8000.0

    static func suggestion(base: Double, stepGoal: Int, steps: Double?, trained: Bool) -> WaterSuggestion {
        var fromSteps = 0.0
        if let steps, steps > Double(stepGoal) { fromSteps = min(1000, (steps - Double(stepGoal)) / 5000 * 500) }
        let fromTraining = trained ? 500.0 : 0
        return WaterSuggestion(base: base, steps: fromSteps, training: fromTraining, total: ((base + fromSteps + fromTraining) / 50).rounded() * 50)
    }

    /// Litres as Portugal writes them, to the nearest 10 ml: "2,8", "2,25", "3"
    static func litres(_ ml: Double) -> String {
        var s = String(format: "%.2f", (ml / 10).rounded() / 100)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",")
    }

    /// "3 L habituais + 0,5 L pelo treino + 0,25 L pelos passos"
    static func why(_ s: WaterSuggestion) -> String {
        var text = "\(litres(s.base)) L habituais"
        if s.training > 0 { text += " + \(litres(s.training)) L pelo treino" }
        if s.steps > 0 { text += " + \(litres(s.steps)) L pelos passos" }
        return text
    }
}

// MARK: - Confirming food before it is saved (phase 2.7, decisions 55–60)

/// The units a food can be measured in (decision 58). Saved as its raw value in a String field (FoodEntry.unit).
enum FoodUnit: String, CaseIterable {
    case gram = "g", unit, tablespoon = "tbsp", teaspoon = "tsp", portion

    /// Phase 2.7 decision: a tablespoon is 15 g and a teaspoon 5 g
    static let tablespoonGrams = 15.0, teaspoonGrams = 5.0

    /// The unit's name on the picker
    var short: String {
        switch self {
        case .gram: return "g"
        case .unit: return "unid."
        case .tablespoon: return "c. sopa"
        case .teaspoon: return "c. chá"
        case .portion: return "porção"
        }
    }

    /// One press of − or +
    var step: Double {
        switch self {
        case .gram: return 5
        case .unit, .tablespoon, .teaspoon: return 0.5
        case .portion: return 0.1
        }
    }

    var maximum: Double { self == .gram ? 3000 : 20 }

    /// "150 g", "1 unidade", "2 colheres de sopa", "1,5 colher de chá", "0,7 porção" (plural from 2, as in Portugal)
    func amount(_ q: Double) -> String {
        let n = FoodItem.number(q), many = q >= 2
        switch self {
        case .gram: return "\(n) g"
        case .unit: return "\(n) \(many ? "unidades" : "unidade")"
        case .tablespoon: return "\(n) \(many ? "colheres" : "colher") de sopa"
        case .teaspoon: return "\(n) \(many ? "colheres" : "colher") de chá"
        case .portion: return "\(n) \(many ? "porções" : "porção")"
        }
    }
}

/// One food on the confirmation, before anything is saved. Its nutrients are kept for one reference amount (a portion,
/// or the weight of a product with no serving) and scaled by the amount. A unit is offered only where its equivalence
/// is known: grams and spoons when the weight is known, units when the portion can be counted, the portion when there
/// is one (phase 2.7 decision).
struct FoodItem: Identifiable, Equatable {
    /// Also the saved entry's id: saving again (after «Editar») replaces the entry instead of adding another
    var id = UUID().uuidString
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double?
    var fat: Double?
    var caffeine: Double?
    var portionGrams: Double? // the reference amount's weight
    var unitsPerPortion: Double? // countable things in the reference ("2 ovos" → 2)
    var hasPortion: Bool // false for a product with no serving: no «porção» to offer
    var portionText: String? // what a portion is ("1 média"), shown beside the amount
    var unit: FoodUnit = .portion
    var quantity = 1.0
    var defaultUnit: FoodUnit = .portion // the typical amount «Não sei» goes back to
    var defaultQuantity = 1.0
    var quantityConfirmed = false
    var group: String // the goal tokens this food counts for, chosen per item; FoodGoals.noGroup for none
    var mealId: String?
    var promiseId: String?
    var addOnId: String? // an add-on from the meal builder's list
    var date: String? // kept when a saved entry is reopened; a new meal takes the day and time it is saved
    var minute: Int?
    // A product Open Food Facts has no kcal or protein for: «Sem dados», never 0, and the meal can't be saved until you
    // copy the value from the label (per 100 g, as labels give it). Until then kcal or protein above is only a placeholder.
    var kcalMissing = false
    var proteinMissing = false
    var labelKcal100: Double?
    var labelProtein100: Double?

    init(name: String, kcal: Double, protein: Double, carbs: Double? = nil, fat: Double? = nil, caffeine: Double? = nil, group: String,
         portionText: String? = nil, portionGrams: Double? = nil, unitsPerPortion: Double? = nil, hasPortion: Bool = true) {
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.caffeine = caffeine
        self.group = group
        self.portionText = portionText
        self.portionGrams = portionGrams.flatMap { $0 > 0 ? $0 : nil }
        self.unitsPerPortion = unitsPerPortion.flatMap { $0 > 0 ? $0 : nil }
        self.hasPortion = hasPortion
    }

    var kcalKnown: Bool { !kcalMissing || labelKcal100 != nil }
    var proteinKnown: Bool { !proteinMissing || labelProtein100 != nil }
    var nutrientsKnown: Bool { kcalKnown && proteinKnown }

    /// The line under the fields of a product with a value missing: what Open Food Facts doesn't have, and where to get it
    var labelLine: String? {
        switch (kcalMissing, proteinMissing) {
        case (true, true): return "O Open Food Facts não tem as calorias nem a proteína deste produto: copia-as do rótulo."
        case (true, false): return "O Open Food Facts não tem as calorias deste produto: copia-as do rótulo."
        case (false, true): return "O Open Food Facts não tem a proteína deste produto: copia-a do rótulo."
        case (false, false): return nil
        }
    }

    /// The kcal per 100 g you copied from the label (nil: empty again, «Sem dados»). 0 is a value: the label can say 0
    mutating func copyLabel(kcal100: Double?) {
        labelKcal100 = kcal100.flatMap { $0 >= 0 ? $0 : nil }
        kcal = (labelKcal100 ?? 0) * (portionGrams ?? 100) / 100
    }

    /// The protein per 100 g you copied from the label (nil: empty again, «Sem dados»)
    mutating func copyLabel(protein100: Double?) {
        labelProtein100 = protein100.flatMap { $0 >= 0 ? $0 : nil }
        protein = (labelProtein100 ?? 0) * (portionGrams ?? 100) / 100
    }

    /// What you typed in a label field: "12,5" or "12.5"; nothing, or anything that isn't an amount, is no value
    static func labelValue(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v.isFinite, v >= 0 else { return nil }
        return v
    }

    /// The units this food can be measured in
    var units: [FoodUnit] {
        var out: [FoodUnit] = []
        if portionGrams != nil { out.append(.gram) }
        if unitsPerPortion != nil { out.append(.unit) }
        if portionGrams != nil { out += [.tablespoon, .teaspoon] }
        if hasPortion { out.append(.portion) }
        return out
    }

    /// How many reference amounts one of `unit` is; nil when the unit has no known equivalence for this food
    func portions(per unit: FoodUnit) -> Double? {
        switch unit {
        case .portion: return hasPortion ? 1 : nil
        case .unit: return unitsPerPortion.map { 1 / $0 }
        case .gram: return portionGrams.map { 1 / $0 }
        case .tablespoon: return portionGrams.map { FoodUnit.tablespoonGrams / $0 }
        case .teaspoon: return portionGrams.map { FoodUnit.teaspoonGrams / $0 }
        }
    }

    /// The amount, in reference amounts: what the reference nutrients are multiplied by
    var scale: Double { quantity * (portions(per: unit) ?? 1) }

    var totalKcal: Double { kcal * scale }
    var totalProtein: Double { protein * scale }
    var totalCarbs: Double? { carbs.map { $0 * scale } }
    var totalFat: Double? { fat.map { $0 * scale } }
    var totalCaffeine: Double? { caffeine.map { $0 * scale } }

    /// "1 porção · 1 média", "0,7 porção · normal: 1 média", "150 g"
    var amountText: String {
        let a = unit.amount(quantity)
        guard unit == .portion, let portionText else { return a }
        return abs(quantity - 1) < 0.001 ? a + " · " + portionText : a + " · normal: " + portionText
    }

    /// The same food in another unit, keeping how much is on the plate (rounded to the new unit's step)
    func converted(to new: FoodUnit) -> FoodItem {
        guard new != unit, let per = portions(per: new), per > 0 else { return self }
        var c = self
        c.unit = new
        c.quantity = Self.tidy(max(new.step, (scale / per / new.step).rounded() * new.step))
        return c
    }

    /// − or +: a change you make, so the quantity is yours from then on
    mutating func change(by steps: Int) {
        let s = unit.step
        let next = ((quantity + Double(steps) * s) / s).rounded() * s
        quantity = Self.tidy(min(unit.maximum, max(s, next)))
        quantityConfirmed = true
    }

    /// «Não sei»: back to the typical amount, kept as an estimate
    mutating func dontKnow() {
        unit = defaultUnit
        quantity = defaultQuantity
        quantityConfirmed = false
    }

    /// What «Guardar refeição» saves for this food. The group is always saved; the quantity is marked estimated until
    /// you confirm it (nutrients always are estimates)
    func entry(date: String = Day.today, minute: Int = Day.minuteOfDay()) -> FoodEntry {
        let p = scale
        return FoodEntry(id: id, date: self.date ?? date, minute: self.minute ?? minute, name: name, kcal: (kcal * p).rounded(), protein: Self.tenth(protein * p),
                         carbs: carbs.map { Self.tenth($0 * p) }, fat: fat.map { Self.tenth($0 * p) }, grams: portionGrams.map { ($0 * p).rounded() },
                         caffeine: caffeine.map { Self.tenth($0 * p) }, mealId: mealId, promiseId: promiseId,
                         group: group.isEmpty ? FoodGoals.noGroup : group, quantity: Self.tidy(quantity), unit: unit.rawValue, estimated: !quantityConfirmed)
    }

    static func tidy(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    static func tenth(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    /// A number as Portugal writes it: whole when it is, else one decimal with a comma ("0,7", "150")
    static func number(_ x: Double) -> String {
        let r = tenth(x)
        if r == r.rounded() { return String(Int(r)) }
        return String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }
}

extension FoodItem {
    /// A catalogue food at the size you picked (normal 1, small 0.7 … double 2), counted for the catalogue food's group
    init(common f: CommonFood, factor: Double = 1, confirmed: Bool = true) {
        self.init(name: f.name, kcal: f.kcal, protein: f.protein, group: f.goals, portionText: f.portion,
                  portionGrams: FoodPortion.grams(f.portion), unitsPerPortion: FoodPortion.count(f.portion))
        quantity = Self.tidy(factor)
        quantityConfirmed = confirmed
    }

    /// A saved meal or favourite as it was saved. The amount is taken as typical until you confirm it; one saved before
    /// groups were kept counts as its name counted until now
    init(saved m: SavedMeal) {
        let stored = m.group ?? ""
        self.init(name: m.name, kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat, caffeine: m.caffeine,
                  group: stored.isEmpty ? FoodGoals.legacyGroup(name: m.name) : stored)
        mealId = m.id
    }

    /// A caffeine drink from the list: no goal group
    init(drink name: String, mg: Double, kcal: Double) {
        self.init(name: name, kcal: kcal, protein: 0, caffeine: mg, group: FoodGoals.noGroup)
    }

    /// A packaged product, from its values per 100 g: one serving when it has one, else 100 g. It counts for no group
    /// until you choose one (the group comes from the food, not from words in its name). Kcal or protein it doesn't
    /// have stay missing until you copy them from the label
    init(product p: OFFProduct) {
        let serving = p.serving.flatMap { $0 > 0 ? $0 : nil }
        let g = serving ?? 100
        self.init(name: p.name, kcal: (p.kcal100 ?? 0) * g / 100, protein: (p.protein100 ?? 0) * g / 100, carbs: p.carbs100.map { $0 * g / 100 }, fat: p.fat100.map { $0 * g / 100 },
                  group: FoodGoals.noGroup, portionText: serving.map { "\(FoodItem.number($0)) g" }, portionGrams: g, hasPortion: serving != nil)
        kcalMissing = p.kcal100 == nil
        proteinMissing = p.protein100 == nil
        unit = .gram
        quantity = Self.tidy(g)
        defaultUnit = .gram
        defaultQuantity = quantity
    }

    /// Typed by hand: what you wrote is what you had; no group until you choose one
    init(manual name: String, kcal: Double, protein: Double) {
        self.init(name: name, kcal: kcal, protein: protein, group: FoodGoals.noGroup)
        quantityConfirmed = true
    }

    /// An add-on (fruit, soup, bread…), with its own group
    init(addOn a: AddOn) {
        self.init(name: a.name, kcal: a.kcal, protein: a.protein, carbs: a.carbs, fat: a.fat, caffeine: a.caffeine, group: a.group, portionText: a.portion,
                  portionGrams: FoodPortion.grams(a.portion), unitsPerPortion: FoodPortion.count(a.portion))
        addOnId = a.id
    }

    /// Something you had before, again: the same food and amount, with the nutrients it was saved with, but as a new
    /// entry whose amount is only a guess until you confirm it (having it once doesn't mean you had the same again)
    static func again(_ e: FoodEntry) -> FoodItem {
        let unit = e.unit.flatMap(FoodUnit.init(rawValue:))
        let q = e.quantity.flatMap { $0 > 0 ? $0 : nil }
        let stored: String? = (e.group ?? "").isEmpty ? nil : e.group
        var item: FoodItem
        if let f = commonFoods.first(where: { $0.name == e.name }) {
            // a catalogue food keeps the catalogue's portion, units and group
            item = FoodItem(common: f, factor: 1, confirmed: false)
            item.group = stored ?? f.goals
        } else if let g = e.grams, g > 0 {
            // a weighed food: the reference is what was saved, at its weight
            item = FoodItem(name: e.name, kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, caffeine: e.caffeine,
                            group: stored ?? FoodGoals.legacyGroup(name: e.name), portionGrams: g, hasPortion: false)
            item.unit = .gram
            item.quantity = FoodItem.tidy(g)
        } else {
            // anything else: the reference is what was saved, counted in units when it was
            item = FoodItem(name: e.name, kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, caffeine: e.caffeine,
                            group: stored ?? FoodGoals.legacyGroup(name: e.name), unitsPerPortion: unit == .unit ? q : nil)
        }
        // the amount as it was saved, when the food can still be measured that way
        if let unit, let q, item.portions(per: unit) != nil {
            item.unit = unit
            item.quantity = q
        }
        // the nutrients as they were saved: the same amount gives the same numbers
        let p = item.scale
        if p > 0 {
            item.kcal = e.kcal / p
            item.protein = e.protein / p
            item.carbs = e.carbs.map { $0 / p }
            item.fat = e.fat.map { $0 / p }
            item.caffeine = e.caffeine.map { $0 / p }
        }
        item.defaultUnit = item.unit
        item.defaultQuantity = item.quantity
        item.quantityConfirmed = false
        return item
    }

    /// A saved entry reopened by «Editar»: the same record (same id, day and time), so saving replaces it
    init(editing e: FoodEntry) {
        self = FoodItem.again(e)
        id = e.id
        date = e.date
        minute = e.minute
        mealId = e.mealId
        promiseId = e.promiseId
        quantityConfirmed = e.estimated == false
    }
}

/// The meal on the confirmation, added up
enum FoodMeal {
    struct Totals: Equatable {
        var kcal = 0.0, protein = 0.0, caffeine = 0.0
        var carbs: Double? // nil when no food in the meal has it: «Sem dados», never 0
        var fat: Double?
        var carbsPartial = false // some foods have it, some don't
        var fatPartial = false
        var kcalNoData = false // no food in the meal has it yet (a product waiting for its label): «Sem dados», never 0
        var proteinNoData = false
        var kcalPartial = false // some foods don't have it yet
        var proteinPartial = false
    }

    /// «Guardar refeição» needs at least one food, and every value Open Food Facts didn't have copied from the label
    static func canSave(_ items: [FoodItem]) -> Bool { !items.isEmpty && items.allSatisfy(\.nutrientsKnown) }

    static func totals(_ items: [FoodItem]) -> Totals {
        var t = Totals()
        var carbsKnown = 0, fatKnown = 0
        for i in items {
            t.kcal += i.totalKcal
            t.protein += i.totalProtein
            t.caffeine += i.totalCaffeine ?? 0
            if let c = i.totalCarbs { t.carbs = (t.carbs ?? 0) + c; carbsKnown += 1 }
            if let f = i.totalFat { t.fat = (t.fat ?? 0) + f; fatKnown += 1 }
        }
        t.carbsPartial = t.carbs != nil && carbsKnown < items.count
        t.fatPartial = t.fat != nil && fatKnown < items.count
        let kcalMissing = items.filter { !$0.kcalKnown }.count
        let proteinMissing = items.filter { !$0.proteinKnown }.count
        t.kcalNoData = !items.isEmpty && kcalMissing == items.count
        t.proteinNoData = !items.isEmpty && proteinMissing == items.count
        t.kcalPartial = kcalMissing > 0 && kcalMissing < items.count
        t.proteinPartial = proteinMissing > 0 && proteinMissing < items.count
        return t
    }

    /// What the meal counts for, as the day's goals count it
    static func goals(_ items: [FoodItem]) -> FoodGoalCounts { FoodGoals.count(items.map { $0.entry(date: Day.today, minute: 0) }) }
}

@MainActor
extension Store {
    /// «Guardar refeição»: saves every food of the meal together, and nothing before it. An entry reopened by «Editar»
    /// keeps its id, so it is replaced, never duplicated; one of `reopened` that was taken off the meal is removed.
    /// Returns what was saved and how to undo it (back to exactly what was there before).
    @discardableResult
    func saveMeal(_ items: [FoodItem], reopened: [FoodEntry] = [], date: String = Day.today, minute: Int = Day.minuteOfDay()) -> (saved: [FoodEntry], undo: () -> Void) {
        guard items.allSatisfy(\.nutrientsKnown) else { return ([], {}) } // a missing value is never saved as 0
        let entries = items.map { $0.entry(date: date, minute: minute) }
        let ids = Set(entries.map(\.id))
        var touched = ids
        for old in reopened { touched.insert(old.id) }
        let before = touched.sorted().compactMap { record(FoodEntry.self, $0) }
        let existed = Set(before.map(\.id))
        let mealsBefore = Set(entries.compactMap(\.mealId)).sorted().compactMap { record(SavedMeal.self, $0) }
        for old in before where !ids.contains(old.id) { remove(old) }
        for e in entries {
            if existed.contains(e.id) { save(e) } else { logFood(e) } // a saved meal counts one more use only the first time
        }
        let undo = {
            for e in entries { self.remove(e) }
            for old in before { self.save(old) }
            for m in mealsBefore { self.save(m) }
        }
        return (entries, undo)
    }
}
