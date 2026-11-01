// Fuel: food, water, caffeine and weight, and the rules on top: adaptive targets, energy balance, protein catch-up,
// water at your pace and the kitchen closing time.
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
}

/// Common caffeine sources, since there's no coffee to track
let caffeineDrinks: [(name: String, mg: Double, kcal: Double)] = [
    ("Cola 330 ml", 34, 139), ("Cola zero 330 ml", 34, 1), ("Iced tea 330 ml", 25, 60), ("Energy drink 250 ml", 80, 112),
    ("Green tea", 30, 0), ("Black tea", 45, 0), ("Dark chocolate 30 g", 24, 170),
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

    /// The water goal rises with steps above your goal and on training days
    func waterGoal(on day: String = Day.today) -> Double {
        var goal = profile.waterGoalMl
        if let steps = health[day]?.steps, steps > Double(profile.stepGoal) { goal += min(1000, (steps - Double(profile.stepGoal)) / 5000 * 500) }
        if !sessions(on: day).isEmpty { goal += 500 }
        return (goal / 50).rounded() * 50
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

    func addWater(_ ml: Double) { save(WaterEntry(ml: ml)) }

    /// Saved meals and recent foods, most used first: the fast log
    var quickFoods: [SavedMeal] {
        let meals = all(SavedMeal.self).sorted { ($0.uses, $0.lastUsed) > ($1.uses, $1.lastUsed) }
        let recent = all(FoodEntry.self).filter { $0.mealId == nil && $0.promiseId == nil }.sorted { ($0.date, $0.minute) > ($1.date, $1.minute) }
        var seen = Set(meals.map { $0.name.lowercased() })
        var out = meals
        for e in recent where !seen.contains(e.name.lowercased()) {
            seen.insert(e.name.lowercased())
            out.append(SavedMeal(id: "recent-" + e.id, name: e.name, kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, caffeine: e.caffeine))
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
