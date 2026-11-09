// A habit that is also food (a shake with its kcal): logging that food in Comida didn't tell the habit, so it kept asking.
// Nothing is assumed from a name: the first time, «Agora» asks whether that food is the habit. «É este» remembers the
// food's name, and from then on logging it answers the habit by itself. Either way only within an hour of the habit's
// time (the user's rule, 9 Nov). The food is already in the day, so answering this way never adds the habit's own kcal again.
import Foundation

enum HabitFoodRules {
    /// How near the habit's time a food has to be, either way. Outside this it neither asks nor answers
    static let near = 60
    /// PromiseLog.source of an answer that came from a food you had already said was this habit
    static let fromFood = "food"
    /// Words that name the same thing in a habit and on a product's label
    private static let sameThing: Set<String> = ["protein", "proteina", "proteinas", "whey", "shake", "batido"]

    static func folded(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func words(_ text: String) -> Set<String> {
        Set(folded(text).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 })
    }

    static func resembles(food: String, habit: String) -> Bool {
        let f = words(food), h = words(habit)
        if !f.isDisjoint(with: h) { return true }
        return !f.isDisjoint(with: sameThing) && !h.isDisjoint(with: sameThing)
    }

    static func isNear(_ minute: Int, habitTime: Int) -> Bool { abs(minute - habitTime) <= near }

    static func dismissEvent(_ promise: String) -> String { "food." + promise }
}

@MainActor
extension Store {
    /// The food of `day` to ask about: the habit logs food, has no answer, you haven't said no today, and a similar food was
    /// logged within an hour of its time. nil when there's nothing to ask.
    func foodToAsk(about p: PromiseItem, on day: String = Day.today) -> FoodEntry? {
        guard p.kcal != nil || p.protein != nil, status(p, on: day) == nil,
              record(NowDismiss.self, NowRule.dismissKey(day: day, event: HabitFoodRules.dismissEvent(p.id))) == nil else { return nil }
        let at = time(of: p, on: day)
        return foods(on: day).last { $0.promiseId == nil && HabitFoodRules.isNear($0.minute, habitTime: at) && HabitFoodRules.resembles(food: $0.name, habit: p.title) }
    }

    /// «É este»: the habit is done with the food already logged, and that food's name is remembered. With Desfazer.
    func acceptHabitFood(_ p: PromiseItem, _ food: FoodEntry) {
        guard canChange else { return }
        var taught = p
        taught.foods = (p.foods ?? []) + [HabitFoodRules.folded(food.name)]
        save(taught)
        log(taught, on: food.date, .done, addFood: false)
        UndoCenter.shared.show("\(p.title) · concluído") { [weak self] in
            self?.save(p)
            self?.undo(p, on: food.date)
        }
    }

    /// «Não é»: this habit stops asking about food today and goes back to asking as usual. With Desfazer.
    func rejectHabitFood(_ p: PromiseItem, on day: String = Day.today) {
        guard canChange else { return }
        let event = HabitFoodRules.dismissEvent(p.id)
        let id = NowRule.dismissKey(day: day, event: event)
        let before = records(NowDismiss.kind)[id]
        save(NowDismiss(id: id, date: day, event: event, action: NowDismiss.gone))
        UndoCenter.shared.show("Não conta para \(p.title)") { [weak self] in self?.put(NowDismiss.kind, id, before) }
    }

    /// A food was saved: a name you taught answers the habit; a food worth asking about stops its notification
    func habitsHear(saved food: FoodEntry) {
        guard food.promiseId == nil else { return }
        let name = HabitFoodRules.folded(food.name)
        var asks = false
        for p in due(on: food.date) where status(p, on: food.date) == nil {
            if (p.foods ?? []).contains(name) && HabitFoodRules.isNear(food.minute, habitTime: time(of: p, on: food.date)) {
                log(p, on: food.date, .done, source: HabitFoodRules.fromFood, addFood: false)
            } else if foodToAsk(about: p, on: food.date) != nil {
                asks = true
            }
        }
        if asks { Reminders.shared.reschedule() }
    }

    /// A food was removed: an answer that only existed because of it goes too
    func habitsHear(removed food: FoodEntry) {
        guard food.promiseId == nil else { return }
        let name = HabitFoodRules.folded(food.name)
        for p in due(on: food.date) where (p.foods ?? []).contains(name) && answerOrigin(p, on: food.date) == .imported(HabitFoodRules.fromFood) {
            let at = time(of: p, on: food.date)
            let stillThere = foods(on: food.date).contains { HabitFoodRules.folded($0.name) == name && HabitFoodRules.isNear($0.minute, habitTime: at) }
            if !stillThere { undo(p, on: food.date) }
        }
    }
}
