// Quick capture: one line, understood by simple rules (no AI service), always shown back for confirmation.
// "Ate Greek yogurt and a banana", "Spent 12 euros on groceries", "Remind me to wash my clothes tomorrow at 18:00",
// "Move studying to tomorrow", "Felt exhausted after lunch". Portuguese works for the common words too.
import Foundation

enum CaptureIntent: Equatable {
    case food([CommonFood], unmatched: [String])
    case spend(amount: Double, category: String, merchant: String)
    case reminder(text: String, day: String, minute: Int?)
    case move(keyword: String, toDay: String)
    case feeling(word: String, energy: Double, pleasant: Double)
    case task(String)

    var summary: String {
        switch self {
        case .food(let foods, let rest):
            let names = foods.map { "\($0.name) (\(Int($0.kcal)) kcal, \(Int($0.protein)) g protein)" }
            return "Log " + (names + rest.map { "\($0) (needs numbers)" }).joined(separator: " and ")
        case .spend(let a, let c, let m): return "Spending \(euro(a, decimals: true)) · \(c)" + (m.isEmpty ? "" : " · \(m)")
        case .reminder(let t, let d, let m): return "Reminder: \(t) · \(Day.date(d).formatted(.dateTime.weekday(.wide)))" + (m.map { " at \(clock($0))" } ?? "")
        case .move(let k, let d): return "Move “\(k)” to \(Day.date(d).formatted(.dateTime.weekday(.wide).day().month()))"
        case .feeling(let w, _, _): return "Feeling: \(w.lowercased())"
        case .task(let t): return "New task: \(t)"
        }
    }
}

enum QuickCapture {
    static func parse(_ raw: String, today: String = Day.today) -> CaptureIntent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        func after(_ prefixes: [String]) -> String? {
            for p in prefixes where lower.hasPrefix(p) { return String(text.dropFirst(p.count)).trimmingCharacters(in: .whitespaces) }
            return nil
        }

        // Spending: a number with euros or a spending verb
        if lower.range(of: #"(spent|paid|gastei|paguei|€|euro)"#, options: .regularExpression) != nil, let amount = number(in: lower) {
            let cats: [(String, [String])] = [("Groceries", ["grocer", "supermerc", "mercado", "continente", "pingo", "lidl", "aldi"]), ("Eating out", ["lunch", "dinner", "restaurant", "almoco", "jantar", "cafe", "restaurante"]),
                                              ("Delivery", ["uber eats", "glovo", "bolt food", "delivery"]), ("Transport", ["uber", "bolt", "bus", "train", "fuel", "gas", "combustivel", "comboio", "autocarro"]),
                                              ("Clothes", ["clothes", "shirt", "shoes", "roupa"]), ("Health", ["pharmacy", "farmacia", "doctor", "medico"]), ("Gym", ["gym", "ginasio"]), ("Fun", ["cinema", "concert", "game", "bar", "drinks"])]
            let cat = cats.first { $0.1.contains { lower.contains($0) } }?.0 ?? "Other"
            let merchant = lower.range(of: #"(?:at|no|na|em) ([a-z0-9 ]+)$"#, options: .regularExpression).map { String(text[$0]).components(separatedBy: " ").dropFirst().joined(separator: " ") } ?? ""
            return .spend(amount: amount, category: cat, merchant: merchant)
        }

        // Moving something on the plan
        if let rest = after(["move ", "mover ", "muda ", "mudar "]) {
            let parts = rest.lowercased().components(separatedBy: " to ")
            let target = parts.count > 1 ? parts.last! : rest.lowercased()
            let day = dayWord(in: target, today: today) ?? Day.add(1, to: today)
            let keyword = (parts.count > 1 ? parts.dropLast().joined(separator: " to ") : rest).replacingOccurrences(of: "para amanha", with: "").trimmingCharacters(in: .whitespaces)
            return .move(keyword: keyword, toDay: day)
        }

        // Reminders and tasks
        if let rest = after(["remind me to ", "remind me ", "lembra-me de ", "lembrar de ", "lembra me de "]) {
            let day = dayWord(in: lower, today: today) ?? today
            let minute = timeOfDay(in: lower)
            var what = rest
            for w in [" tomorrow", " today", " amanha", " hoje", " on monday", " on tuesday", " on wednesday", " on thursday", " on friday", " on saturday", " on sunday"] { what = what.replacingOccurrences(of: w, with: "", options: .caseInsensitive) }
            what = what.replacingOccurrences(of: #" at \d{1,2}([:h]\d{2})?"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            return .reminder(text: what.prefix(1).uppercased() + what.dropFirst(), day: day, minute: minute)
        }

        // Feelings
        let feelings: [(String, String, Double, Double)] = [
            ("exhaust", "Drained", -1, -0.6), ("tired", "Tired", -0.8, -0.2), ("cansad", "Tired", -0.8, -0.2), ("stress", "Stressed", 0.7, -0.8), ("anxious", "Tense", 0.5, -0.7),
            ("great", "Energized", 0.9, 0.9), ("energ", "Energized", 0.9, 0.8), ("happy", "Content", 0.2, 0.9), ("calm", "Calm", -0.2, 0.7), ("focused", "Motivated", 0.6, 0.6), ("sad", "Low", -0.6, -0.8), ("triste", "Low", -0.6, -0.8),
        ]
        if lower.hasPrefix("felt") || lower.hasPrefix("feel") || lower.hasPrefix("senti") || lower.hasPrefix("estou") || lower.hasPrefix("i'm") || lower.hasPrefix("im ") {
            if let f = feelings.first(where: { lower.contains($0.0) }) { return .feeling(word: f.1, energy: f.2, pleasant: f.3) }
        }

        // Food: "ate ...", "had ...", "comi ..."
        if let rest = after(["ate ", "had ", "eaten ", "comi ", "bebi ", "drank "]) {
            let pieces = rest.lowercased().replacingOccurrences(of: " and ", with: ",").replacingOccurrences(of: " e ", with: ",").replacingOccurrences(of: " with ", with: ",")
                .components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^(a|an|some|um|uma|two|2) "#, with: "", options: .regularExpression) }.filter { !$0.isEmpty }
            var found: [CommonFood] = [], missing: [String] = []
            for p in pieces {
                if let f = FoodSearch.local(p).first { found.append(f) } else { missing.append(p) }
            }
            return .food(found, unmatched: missing)
        }
        return .task(text)
    }

    static func number(in s: String) -> Double? {
        guard let r = s.range(of: #"\d+([.,]\d{1,2})?"#, options: .regularExpression) else { return nil }
        return Double(s[r].replacingOccurrences(of: ",", with: "."))
    }

    static func dayWord(in s: String, today: String) -> String? {
        if s.contains("tomorrow") || s.contains("amanha") { return Day.add(1, to: today) }
        if s.contains("today") || s.contains("hoje") { return today }
        let names = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
                     "domingo": 1, "segunda": 2, "terca": 3, "quarta": 4, "quinta": 5, "sexta": 6, "sabado": 7]
        for (n, wd) in names where s.contains(n) {
            for i in 1...7 { let d = Day.add(i, to: today); if Day.weekday(d) == wd { return d } }
        }
        return nil
    }

    static func timeOfDay(in s: String) -> Int? {
        guard let r = s.range(of: #"(?:at|as|às) (\d{1,2})(?:[:h](\d{2}))?"#, options: .regularExpression) else { return nil }
        let digits = s[r].components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.compactMap { Int($0) }
        guard let h = digits.first, h < 24 else { return nil }
        return h * 60 + (digits.count > 1 ? digits[1] : 0)
    }
}

@MainActor
extension Store {
    /// Carries out a confirmed capture; returns what happened, for the undo line
    @discardableResult
    func apply(_ intent: CaptureIntent) -> String {
        switch intent {
        case .food(let foods, _):
            for f in foods { logFood(FoodEntry(name: f.name, kcal: f.kcal, protein: f.protein)) }
            return "Logged \(foods.count) food\(foods.count == 1 ? "" : "s")"
        case .spend(let a, let c, let m):
            save(Transaction(amount: -a, merchant: m.isEmpty ? c : m.capitalized, category: c, reviewed: true))
            return "Spending saved"
        case .reminder(let t, let d, let m):
            if let m {
                save(PromiseItem(title: t, icon: "bell", schedule: Schedule(rule: .everyNDays, every: 9999, start: d, minute: m)))
                return "Reminder set"
            }
            save(TaskItem(title: t, due: d))
            return "Added to tasks"
        case .move(let k, let d):
            let key = k.lowercased()
            if var b = all(PlanBlock.self).filter({ $0.date >= Day.today && $0.title.lowercased().contains(key) }).min(by: { $0.date < $1.date }) { b.date = d; save(b); return "Moved \(b.title)" }
            if var t = all(TaskItem.self).first(where: { !$0.done && $0.title.lowercased().contains(key) }) { t.due = d; save(t); return "Moved \(t.title)" }
            save(TaskItem(title: k.prefix(1).uppercased() + k.dropFirst(), due: d))
            return "Nothing matched, so it's a task for that day"
        case .feeling(let w, let e, let p):
            save(MoodEntry(energy: e, pleasant: p, word: w))
            return "Feeling saved"
        case .task(let t):
            save(TaskItem(title: t))
            return "Added to tasks"
        }
    }
}
