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

    /// Whether confirming would save anything
    var savesSomething: Bool {
        if case .food(let f, _) = self { return !f.isEmpty }
        if case .move(let k, _) = self { return !k.isEmpty }
        if case .reminder(let t, _, _) = self { return !t.isEmpty }
        if case .task(let t) = self { return !t.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    var summary: String {
        switch self {
        case .food(let foods, let rest):
            if foods.isEmpty { return "Não encontrei nos alimentos comuns: " + rest.joined(separator: ", ") + ". Nada vai ser guardado; usa Registar comida para procurar produtos." }
            let names = foods.map { "\($0.name) (\(Int($0.kcal)) kcal, \(Int($0.protein)) g de proteína)" }
            return "Registar " + names.joined(separator: " e ") + (rest.isEmpty ? "" : ". Não vai ser guardado: " + rest.joined(separator: ", "))
        case .spend(let a, let c, let m): return "Despesa \(euro(a, decimals: true)) · \(Self.categoryLabel(c))" + (m.isEmpty ? "" : " · \(m)")
        case .reminder(let t, let d, let m):
            let day = Day.date(d).formatted(.dateTime.weekday(.wide))
            return m.map { "Lembrete: \(t) · \(day) às \(clock($0))" } ?? "Tarefa para \(day): \(t) (sem hora, por isso sem notificação)"
        case .move(let k, let d): return "Passar «\(k)» para \(Day.date(d).formatted(.dateTime.weekday(.wide).day().month()))"
        case .feeling(let w, _, _): return "Como te sentes: \(Self.feelingLabel(w).lowercased())"
        case .task(let t): return "Nova tarefa: \(t)"
        }
    }

    /// A spending category as shown; the English category is what's saved (and what Money adds up by)
    private static func categoryLabel(_ category: String) -> String {
        let labels: [String: String] = ["Groceries": "Supermercado", "Eating out": "Restaurantes", "Delivery": "Entregas", "Transport": "Transportes", "Clothes": "Roupa",
                                        "Health": "Saúde", "Gym": "Ginásio", "Fun": "Lazer", "Other": "Outros"]
        return labels[category] ?? category
    }

    /// A feeling as shown; the English word is what's saved in the mood entry
    private static func feelingLabel(_ word: String) -> String {
        let labels: [String: String] = ["Drained": "Esgotado", "Tired": "Cansado", "Stressed": "Stressado", "Tense": "Tenso", "Energized": "Enérgico",
                                        "Content": "Satisfeito", "Calm": "Calmo", "Motivated": "Motivado", "Low": "Em baixo"]
        return labels[word] ?? word
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
            // the day is read without accents, like `lower`, so «amanhã» counts as «amanha»; the keyword keeps them
            let target = (parts.count > 1 ? parts.last! : rest.lowercased()).folding(options: .diacriticInsensitive, locale: nil)
            let day = dayWord(in: target, today: today) ?? Day.add(1, to: today)
            let keyword = (parts.count > 1 ? parts.dropLast().joined(separator: " to ") : rest).replacingOccurrences(of: "para amanha", with: "", options: [.caseInsensitive, .diacriticInsensitive]).trimmingCharacters(in: .whitespaces)
            return .move(keyword: keyword, toDay: day)
        }

        // Reminders and tasks
        if let rest = after(["remind me to ", "remind me ", "lembra-me de ", "lembrar de ", "lembra me de "]) {
            let day = dayWord(in: lower, today: today) ?? today
            let minute = timeOfDay(in: lower)
            var what = rest
            for w in [" tomorrow", " today", " amanha", " hoje", " on monday", " on tuesday", " on wednesday", " on thursday", " on friday", " on saturday", " on sunday"] { what = what.replacingOccurrences(of: w, with: "", options: [.caseInsensitive, .diacriticInsensitive]) }
            what = what.replacingOccurrences(of: #" (at|as|às) \d{1,2}([:h]\d{2})?h?"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces)
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
                .components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var found: [CommonFood] = [], missing: [String] = []
            let counts = ["two": 2, "three": 3, "dois": 2, "duas": 2, "tres": 3]
            for raw in pieces {
                // "2 eggs", "two bananas": the count repeats the item, up to 5
                var n = 1, p = raw
                if let first = raw.split(separator: " ").first, let k = Int(first) ?? counts[String(first)] { n = min(5, max(1, k)); p = String(raw.dropFirst(first.count)).trimmingCharacters(in: .whitespaces) }
                p = p.replacingOccurrences(of: #"^(a|an|some|um|uma|of) "#, with: "", options: .regularExpression)
                // "2 eggs" is two of one egg, not two plates of scrambled eggs
                if p.hasSuffix("s"), n > 1 || FoodSearch.local(p).isEmpty, !FoodSearch.local(String(p.dropLast())).isEmpty { p = String(p.dropLast()) }
                if let f = FoodSearch.local(p).first { found += Array(repeating: f, count: n) } else { missing.append(raw) }
            }
            return .food(found, unmatched: missing)
        }
        return .task(text)
    }

    /// "12", "12,50", "12.50", "1.234,56" and "1,234.56"
    static func number(in s: String) -> Double? {
        guard let r = s.range(of: #"\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?"#, options: .regularExpression) else { return nil }
        var t = String(s[r])
        if let last = t.lastIndex(where: { $0 == "," || $0 == "." }), t.distance(from: last, to: t.endIndex) == 4 { t.removeAll { $0 == "," || $0 == "." } } // only thousands
        else if let last = t.lastIndex(where: { $0 == "," || $0 == "." }) {
            let decimals = t[t.index(after: last)...]
            t = t[..<last].filter(\.isNumber) + "." + decimals
        }
        return Double(t)
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
    /// Carries out a confirmed capture; returns what happened and how to undo it
    @discardableResult
    func apply(_ intent: CaptureIntent) -> (message: String, undo: () -> Void) {
        switch intent {
        case .food(let foods, _):
            let entries = foods.map { FoodEntry(name: $0.name, kcal: $0.kcal, protein: $0.protein) }
            entries.forEach(logFood)
            return ("\(foods.count) \(foods.count == 1 ? "alimento registado" : "alimentos registados")", { entries.forEach { self.remove($0) } })
        case .spend(let a, let c, let m):
            let t = Transaction(amount: -a, merchant: m.isEmpty ? moneyCategoryLabel(c) : m.capitalized, category: c, reviewed: true)
            save(t)
            return ("Despesa guardada", { self.remove(t) })
        case .reminder(let t, let d, let m):
            if let m {
                let p = PromiseItem(title: t, icon: "bell", schedule: Schedule(rule: .everyNDays, every: 9999, start: d, minute: m))
                save(p)
                return ("Lembrete criado", { self.delete(p) })
            }
            let task = TaskItem(title: t, due: d)
            save(task)
            return ("Adicionado às tarefas", { self.remove(task) })
        case .move(let k, let d):
            let key = k.lowercased()
            if let b = all(PlanBlock.self).filter({ $0.date >= Day.today && $0.title.lowercased().contains(key) }).min(by: { $0.date < $1.date }) {
                var moved = b; moved.date = d; save(moved)
                return ("Passou para esse dia: \(b.title)", { self.save(b) })
            }
            if let t = all(TaskItem.self).first(where: { !$0.done && $0.title.lowercased().contains(key) }) {
                var moved = t; moved.due = d; save(moved)
                return ("Passou para esse dia: \(t.title)", { self.save(t) })
            }
            let task = TaskItem(title: k.prefix(1).uppercased() + k.dropFirst(), due: d)
            save(task)
            return ("Não encontrei nada, por isso ficou como tarefa para esse dia", { self.remove(task) })
        case .feeling(let w, let e, let p):
            let m = MoodEntry(energy: e, pleasant: p, word: w)
            save(m)
            return ("Estado de espírito guardado", { self.remove(m) })
        case .task(let t):
            let task = TaskItem(title: t)
            save(task)
            return ("Adicionado às tarefas", { self.remove(task) })
        }
    }
}
