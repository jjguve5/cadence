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
    /// Phase 2.10, optional so older builds read and ignore them: where you buy it, what it's for (free text, as you
    /// type it), and the day you bought it (for «comprado por ti hoje»)
    var shop: String?
    var occasion: String?
    var boughtOn: String?
}

let aisles = ["Fruit and veg", "Meat and fish", "Dairy", "Bakery", "Pantry", "Frozen", "Drinks", "Household", "Health", "Other"]

/// An aisle as shown; the English aisle is what's saved on each item and what the list is sorted and grouped by
func shoppingAisleLabel(_ aisle: String) -> String {
    let labels: [String: String] = ["Fruit and veg": "Fruta e legumes", "Meat and fish": "Carne e peixe", "Dairy": "Laticínios", "Bakery": "Padaria", "Pantry": "Mercearia",
                                    "Frozen": "Congelados", "Drinks": "Bebidas", "Household": "Casa", "Health": "Saúde", "Other": "Outros"]
    return labels[aisle] ?? aisle
}

/// A list line's reason as shown; "added by you" stays the saved default of items you add by hand
func shoppingReasonLabel(_ reason: String) -> String {
    reason == "added by you" ? "adicionado por ti" : reason
}

struct ListLine: Identifiable {
    var id: String
    var name: String
    var qty: Double
    var unit: String
    var aisle: String
    var reason: String
    var price: Double?
    var manual: ShoppingItem?
    /// Where the need comes from: "recipe", "pantry", "medicine", "brush" or "manual" (your own item)
    var origin = "manual"
    var shop: String? = nil
    var occasion: String? = nil
    /// The other sources of the same product, folded into this line (one line per product); bought with it
    var merged: [ListLine] = []
    /// Each source's reason, as saved, when the line has more than one
    var reasons: [String] = []

    /// On your list: you added it (alone or with other sources). A line the app works out alone is a suggestion,
    /// which you add, adjust or ignore (phase 2.10)
    var mine: Bool { manual != nil || merged.contains { $0.manual != nil } }

    /// Your own item behind the line, to adjust it
    var yourItem: ShoppingItem? { manual ?? merged.compactMap(\.manual).first }

    /// The shop it's grouped under: yours if you set one; otherwise health products at the pharmacy, the rest at the
    /// supermarket (shown only)
    var shopLabel: String { shop ?? (aisle == "Health" ? "Farmácia ou parafarmácia" : "Supermercado") }

    /// The occasion it's grouped under: yours if you set one; otherwise what the need comes from (shown only)
    var occasionLabel: String {
        if let occasion { return occasion }
        switch origin {
        case "recipe": return "Preparação da semana"
        case "pantry", "medicine", "brush": return "Reposição"
        default: return "Sem ocasião"
        }
    }

    /// The area the need comes from, for a suggestion's «Porquê»
    var originLabel: String {
        switch origin {
        case "recipe": return "da Cozinha, para"
        case "pantry": return "da despensa:"
        case "medicine": return "dos medicamentos:"
        case "brush": return "da Higiene:"
        default: return ""
        }
    }
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
            // The Portuguese words count alongside the English ones (a pantry item or routine named in Portuguese)
            let isCreatine = name.contains("creatine") || name.contains("creatina")
            for promise in activePromises where promise.title.lowercased().contains(name) || (name.contains("whey") && (promise.title.lowercased().contains("shake") || promise.title.lowercased().contains("batido")))
                || (isCreatine && (promise.title.lowercased().contains("creatine") || promise.title.lowercased().contains("creatina"))) {
                let perWeek = Double(promise.schedule.dueInWeek(of: Day.today))
                perDay += perWeek / 7 * (isCreatine ? 5 : name.contains("whey") ? 30 : 1)
            }
        }
        guard perDay > 0 else { return nil }
        return Int(p.qty / perDay)
    }

    /// The list: the week's recipes minus what you have, pantry items running low, medicine refills, and your own.
    /// One line per product, wherever the need comes from (phase 2.10): the same product from several places is one
    /// line whose reason names each source. What the app works out comes first, so the line keeps its computed id
    /// (and its bought mark); your own items fold into it.
    func shoppingList() -> [ListLine] {
        var lines: [String: ListLine] = [:]
        let pantry = all(PantryItem.self)
        for (r, n) in plan(for: week) {
            for ing in r.ingredients {
                let key = ing.name.lowercased()
                var line = lines[key] ?? ListLine(id: key, name: ing.name, qty: 0, unit: ing.unit, aisle: ing.aisle, reason: r.name, price: prices[key], origin: "recipe")
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
            if let days = runOut(p), days <= 10, lines[key] == nil { lines[key] = ListLine(id: key, name: p.name, qty: 1, unit: "", aisle: p.aisle, reason: days == 1 ? "acaba em 1 dia" : "acaba em \(days) dias", price: p.price, origin: "pantry") }
            else if p.lowAt > 0, p.qty <= p.lowAt, lines[key] == nil { lines[key] = ListLine(id: key, name: p.name, qty: 1, unit: "", aisle: p.aisle, reason: "a acabar", price: p.price, origin: "pantry") }
        }
        for m in all(Medicine.self) {
            if let left = dosesLeft(m), Double(left.doses) <= m.refillAt { lines["med-" + m.id] = ListLine(id: "med-" + m.id, name: m.name, qty: 1, unit: "", aisle: "Health", reason: left.doses == 1 ? "resta 1 dose" : "restam \(left.doses) doses", origin: "medicine") }
        }
        if brushHeadDue { lines["brush"] = ListLine(id: "brush", name: "Cabeças de escova de dentes", qty: 1, unit: "", aisle: "Health", reason: "3 meses de uso", origin: "brush") }
        let marks = records("bought")
        let bought = { (id: String) in marks[Store.boughtKey(week: self.week, line: id)] != nil || marks["\(self.week)|\(id)"] != nil }
        let worked = lines.values.filter { $0.qty > 0 && !bought($0.id) }.sorted { $0.id < $1.id }
        let yours = all(ShoppingItem.self).filter { !$0.bought }.sorted { $0.id < $1.id }.map { s in
            ListLine(id: "s-" + s.id, name: s.name, qty: s.qty, unit: s.unit, aisle: s.aisle, reason: s.reason, price: prices[s.name.lowercased()], manual: s, origin: "manual", shop: s.shop, occasion: s.occasion)
        }.filter { $0.qty > 0 && !bought($0.id) }
        var out: [ListLine] = []
        for line in worked + yours {
            if let i = out.firstIndex(where: { Store.productKey($0.name) == Store.productKey(line.name) }) { out[i] = Store.fold(line, into: out[i]) } else { out.append(line) }
        }
        return out.sorted { ($0.aisle, $0.name) < ($1.aisle, $1.name) }
    }

    /// The same product, whatever the source: the name without case or surrounding spaces
    nonisolated static func productKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// One line for two sources of the same product: the first line's id, name and aisle; the larger quantity when
    /// the units agree (otherwise the first one's); every source's reason, each once
    nonisolated static func fold(_ other: ListLine, into line: ListLine) -> ListLine {
        var out = line
        var reasons: [String] = []
        for r in (line.reasons.isEmpty ? [line.reason] : line.reasons) + (other.reasons.isEmpty ? [other.reason] : other.reasons) where !reasons.contains(r) {
            reasons.append(r)
        }
        out.reasons = reasons
        out.reason = reasons.count == 1 ? reasons[0] : reasons.map(shoppingReasonLabel).joined(separator: " · ")
        if other.unit == line.unit { out.qty = max(line.qty, other.qty) }
        out.price = line.price ?? other.price
        out.shop = line.shop ?? other.shop
        out.occasion = line.occasion ?? other.occasion
        var single = other
        single.merged = []
        single.reasons = []
        out.merged = line.merged + [single] + other.merged
        return out
    }

    /// Buying a line (the circle): what tick(_:) does, plus every other source folded into the line, so none comes
    /// back on its own; your items keep the day. Returns the Desfazer: the marks come off and the pantry goes back
    @discardableResult
    func buy(_ line: ListLine) -> () -> Void {
        let week: String = self.week // the Monday of this week (Store also has a week(_:upTo:) method)
        let pantryBefore = all(PantryItem.self).first { $0.name.lowercased() == line.name.lowercased() }
        tick(line)
        for other in line.merged {
            if var m = other.manual { m.bought = true; save(m) } else { put("bought", Store.boughtKey(week: week, line: other.id), .object(["at": .number(nowMs())])) }
        }
        for item in ([line] + line.merged).compactMap(\.manual) {
            if var m = record(ShoppingItem.self, item.id) { m.boughtOn = Day.today; save(m) }
        }
        return { [weak self] in
            guard let self else { return }
            for l in [line] + line.merged {
                if let m = l.manual { self.save(m) } else { self.put("bought", Store.boughtKey(week: week, line: l.id), nil) }
            }
            if let p = pantryBefore { self.save(p) }
        }
    }

    /// Your items bought today, shown crossed out («comprado por ti hoje»)
    var boughtToday: [ShoppingItem] {
        all(ShoppingItem.self).filter { $0.bought && $0.boughtOn == Day.today }.sorted { $0.name < $1.name }
    }

    var prices: [String: Double] {
        var out: [String: Double] = [:]
        for (k, v) in records("price") { if case .number(let n) = v { out[k] = n } }
        return out
    }

    /// The id a bought mark is saved under: the week, then the line, with only the characters the server takes
    /// (letters and digits, "_", ".", ":" and "-"; accents dropped, anything else becomes "-"), at most 80. When cleaning
    /// or the length changed the line, a hash of the original line (FNV-1a, 8 hex digits) goes at the end, so two lines
    /// that clean to the same text ("café", "cafe") never share a mark. A line already in those characters keeps its
    /// plain id, which builds before phase 2.2 also recognise. The value is an object for the same reason. Marks saved
    /// before phase 2.2 as "<week>|<line>" with a bare true, which the server skips, are still read.
    nonisolated static func boughtKey(week: String, line: String) -> String {
        let safe = String(line.folding(options: .diacriticInsensitive, locale: nil).map { c -> Character in
            c.isASCII && (c.isLetter || c.isNumber || "_.:-".contains(c)) ? c : "-"
        })
        let plain = week + "_" + safe
        if safe == line && plain.count <= 80 { return plain }
        var hash: UInt32 = 2166136261
        for byte in line.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return String(plain.prefix(80 - 9)) + "_" + String(format: "%08x", hash)
    }

    func tick(_ line: ListLine) {
        if var m = line.manual { m.bought = true; save(m) } else { put("bought", Store.boughtKey(week: week, line: line.id), .object(["at": .number(nowMs())])) }
        if var p = all(PantryItem.self).first(where: { $0.name.lowercased() == line.name.lowercased() }) { p.qty += line.qty; save(p) }
    }
}
