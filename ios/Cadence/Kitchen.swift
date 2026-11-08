// Meal prep and shopping: recipes, the week's plan against your targets, one guided prep timeline, the fridge with
// eat-by dates, the pantry with run-out forecasts, and a shopping list that builds itself.
import Foundation

struct Ingredient: Codable, Equatable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var qty: Double
    var unit = "g"
    var aisle = "Other"
}

struct PrepStep: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var minutes: Int
    var parallel = false // runs alongside the next steps (oven, rice)
}

struct Recipe: Record, Equatable {
    static let kind = "recipe"
    var id = UUID().uuidString
    var name: String
    var portions = 4
    var kcal: Double = 600 // per portion
    var protein: Double = 40
    var ingredients: [Ingredient] = []
    var steps: [PrepStep] = []
    var keepsDays = 4
    var freezes = true
}

struct MealPlanEntry: Record, Equatable {
    static let kind = "mealplan"
    var id: String { "\(week)|\(recipeId)" }
    var week: String // Monday
    var recipeId: String
    var portions: Int
}

struct Portion: Record, Equatable {
    static let kind = "portion"
    var id = UUID().uuidString
    var recipeId: String
    var name: String
    var made = Day.today
    var eatBy: String
    var frozen = false
    var eaten: String?
}

struct PantryItem: Record, Equatable {
    static let kind = "pantry"
    var id = UUID().uuidString
    var name: String
    var qty: Double
    var unit = "g"
    var usePerDay: Double = 0 // learned or typed: creatine 5 g, whey 30 g
    var lowAt: Double = 0
    var aisle = "Pantry"
    var price: Double?
    var proteinPerPack: Double? // grams, for protein per euro
}

struct ShoppingItem: Record, Equatable {
    static let kind = "shopping"
    var id = UUID().uuidString
    var name: String
    var qty: Double = 1
    var unit = ""
    var aisle = "Other"
    var bought = false
    var reason = "added by you"
}

let aisles = ["Fruit and veg", "Meat and fish", "Dairy", "Bakery", "Pantry", "Frozen", "Drinks", "Household", "Health", "Other"]

struct ListLine: Identifiable {
    var id: String
    var name: String
    var qty: Double
    var unit: String
    var aisle: String
    var reason: String
    var price: Double?
    var manual: ShoppingItem?
}

@MainActor
extension Store {
    var week: String { Day.weekStart(Day.today) }

    func plan(for week: String) -> [(Recipe, Int)] {
        all(MealPlanEntry.self).filter { $0.week == week }.compactMap { e in record(Recipe.self, e.recipeId).map { ($0, e.portions) } }
    }

    /// How much of the week's protein the planned portions cover
    func planCoverage(_ week: String) -> (protein: Double, kcal: Double) {
        let p = plan(for: week).map { $0.0.protein * Double($0.1) }.reduce(0, +)
        let k = plan(for: week).map { $0.0.kcal * Double($0.1) }.reduce(0, +)
        return (p / (profile.proteinTarget * 7), k / (profile.kcal * 7))
    }

    /// One timeline for everything you're cooking: parallel steps (oven, rice) start first and run alongside
    func prepTimeline(_ week: String) -> [(start: Int, step: PrepStep, recipe: String)] {
        var out: [(Int, PrepStep, String)] = []
        var handsFree: [(PrepStep, String)] = [], handsOn: [(PrepStep, String)] = []
        for (r, _) in plan(for: week) { for s in r.steps { if s.parallel { handsFree.append((s, r.name)) } else { handsOn.append((s, r.name)) } } }
        var t = 0
        for (s, r) in handsFree.sorted(by: { $0.0.minutes > $1.0.minutes }) { out.append((t, s, r)); t += 2 }
        for (s, r) in handsOn { out.append((t, s, r)); t += s.minutes }
        return out.map { (start: $0.0, step: $0.1, recipe: $0.2) }
    }

    func finishPrep(_ week: String) {
        for (r, n) in plan(for: week) {
            for i in 0..<n {
                let frozen = r.freezes && i >= r.keepsDays
                save(Portion(recipeId: r.id, name: r.name, eatBy: Day.add(frozen ? 60 : r.keepsDays, to: Day.today), frozen: frozen))
            }
            // What was used comes out of the pantry
            for ing in r.ingredients {
                if var p = all(PantryItem.self).first(where: { $0.name.lowercased() == ing.name.lowercased() }) { p.qty = max(0, p.qty - ing.qty * Double(n) / Double(max(1, r.portions))); save(p) }
            }
        }
    }

    var fridge: [Portion] { all(Portion.self).filter { $0.eaten == nil }.sorted { $0.eatBy < $1.eatBy } }

    func eat(_ portion: Portion) {
        var p = portion
        p.eaten = Day.today
        save(p)
        if let r = record(Recipe.self, p.recipeId) { logFood(FoodEntry(name: r.name, kcal: r.kcal, protein: r.protein)) }
    }

    /// Days until each pantry item runs out, from how fast you use it (routines count: the shake every 2 days uses whey)
    func runOut(_ p: PantryItem) -> Int? {
        var perDay = p.usePerDay
        let name = p.name.lowercased()
        if perDay == 0 {
            for promise in activePromises where promise.title.lowercased().contains(name) || (name.contains("whey") && promise.title.lowercased().contains("shake")) || (name.contains("creatine") && promise.title.lowercased().contains("creatine")) {
                let perWeek = Double(promise.schedule.dueInWeek(of: Day.today))
                perDay += perWeek / 7 * (name.contains("creatine") ? 5 : name.contains("whey") ? 30 : 1)
            }
        }
        guard perDay > 0 else { return nil }
        return Int(p.qty / perDay)
    }

    /// The list: the week's recipes minus what you have, pantry items running low, medicine refills, and your own
    func shoppingList() -> [ListLine] {
        var lines: [String: ListLine] = [:]
        let pantry = all(PantryItem.self)
        for (r, n) in plan(for: week) {
            for ing in r.ingredients {
                let key = ing.name.lowercased()
                var line = lines[key] ?? ListLine(id: key, name: ing.name, qty: 0, unit: ing.unit, aisle: ing.aisle, reason: r.name, price: prices[key])
                line.qty += ing.qty * Double(n) / Double(max(1, r.portions))
                if !line.reason.contains(r.name) { line.reason += ", " + r.name }
                lines[key] = line
            }
        }
        // What you already have comes off the list
        for (key, line) in lines {
            let have = pantry.first { $0.name.lowercased() == key }?.qty ?? 0
            lines[key]?.qty = max(0, line.qty - have)
        }
        for p in pantry {
            let key = p.name.lowercased()
            if let days = runOut(p), days <= 10, lines[key] == nil { lines[key] = ListLine(id: key, name: p.name, qty: 1, unit: "", aisle: p.aisle, reason: "\(days) days left", price: p.price) }
            else if p.lowAt > 0, p.qty <= p.lowAt, lines[key] == nil { lines[key] = ListLine(id: key, name: p.name, qty: 1, unit: "", aisle: p.aisle, reason: "running low", price: p.price) }
        }
        for m in all(Medicine.self) {
            if let left = dosesLeft(m), Double(left.doses) <= m.refillAt { lines["med-" + m.id] = ListLine(id: "med-" + m.id, name: m.name, qty: 1, unit: "", aisle: "Health", reason: "\(left.doses) doses left") }
        }
        if brushHeadDue { lines["brush"] = ListLine(id: "brush", name: "Toothbrush heads", qty: 1, unit: "", aisle: "Health", reason: "3 months") }
        for s in all(ShoppingItem.self) where !s.bought {
            lines["s-" + s.id] = ListLine(id: "s-" + s.id, name: s.name, qty: s.qty, unit: s.unit, aisle: s.aisle, reason: s.reason, price: prices[s.name.lowercased()], manual: s)
        }
        let marks = records("bought")
        let bought = { (id: String) in marks[Store.boughtKey(week: self.week, line: id)] != nil || marks["\(self.week)|\(id)"] != nil }
        return lines.values.filter { $0.qty > 0 && !bought($0.id) }.sorted { ($0.aisle, $0.name) < ($1.aisle, $1.name) }
    }

    var prices: [String: Double] {
        var out: [String: Double] = [:]
        for (k, v) in records("price") { if case .number(let n) = v { out[k] = n } }
        return out
    }

    /// The id a bought mark is saved under: the week, then the line, with only the characters the server takes
    /// (letters and digits, "_", ".", ":" and "-"; accents dropped, anything else becomes "-"), at most 80. The value is
    /// an object for the same reason. Marks saved before phase 2.2 as "<week>|<line>" with a bare true, which the server
    /// skips, are still read.
    nonisolated static func boughtKey(week: String, line: String) -> String {
        let safe = line.folding(options: .diacriticInsensitive, locale: nil).map { c -> Character in
            c.isASCII && (c.isLetter || c.isNumber || "_.:-".contains(c)) ? c : "-"
        }
        return String((week + "_" + String(safe)).prefix(80))
    }

    func tick(_ line: ListLine) {
        if var m = line.manual { m.bought = true; save(m) } else { put("bought", Store.boughtKey(week: week, line: line.id), .object(["at": .number(nowMs())])) }
        if var p = all(PantryItem.self).first(where: { $0.name.lowercased() == line.name.lowercased() }) { p.qty += line.qty; save(p) }
    }
}
