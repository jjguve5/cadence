// The rest of the concept: workouts the Air recorded, body progress, the rest-or-train forecast, reading and sleep,
// where your time went, the weather-aware plan, and the money extras (payday plan, round-ups, e-Fatura,
// cost per gram of protein, prep against eating out, travel budgets). And Pip's wardrobe, unlocked by level.
import Foundation
import SwiftUI

struct AirExercise: Codable, Identifiable, Equatable {
    var start: String
    var end: String
    var type: String
    var minutes: Int
    var avgHr: Double?
    var maxHr: Double?
    var calories: Double?
    var distance: Double?
    var id: String { start }
    var startDate: Date { ISO8601DateFormatter.lenient(start) }
    /// The type in words; the type itself stays as the server sends it
    var name: String {
        let words = type.replacingOccurrences(of: "_", with: " ").lowercased()
        return airExerciseNames[words] ?? words.capitalized
    }
}

/// Common Air exercise types in Portuguese; any other type shows as the server spells it
fileprivate let airExerciseNames: [String: String] = [
    "workout": "Treino", "walk": "Caminhada", "walking": "Caminhada", "run": "Corrida", "running": "Corrida",
    "bike": "Bicicleta", "biking": "Bicicleta", "cycling": "Ciclismo", "outdoor bike": "Bicicleta", "spinning": "Spinning",
    "weights": "Musculação", "weightlifting": "Musculação", "weight lifting": "Musculação", "strength training": "Treino de força",
    "hike": "Caminhada na natureza", "hiking": "Caminhada na natureza", "swim": "Natação", "swimming": "Natação",
    "yoga": "Ioga", "pilates": "Pilates", "elliptical": "Elíptica", "treadmill": "Passadeira", "rowing": "Remo",
    "hiit": "HIIT", "interval workout": "Treino intervalado", "dancing": "Dança", "tennis": "Ténis",
    "football": "Futebol", "soccer": "Futebol", "sport": "Desporto", "other": "Outro",
]

extension ISO8601DateFormatter {
    static func lenient(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? Date()
    }
}

@MainActor
final class AirWorkouts: ObservableObject {
    static let shared = AirWorkouts()
    @Published private(set) var list: [AirExercise] = []
    private var last: Date?

    func refresh() async {
        if let last, Date().timeIntervalSince(last) < 20 * 60 { return }
        guard let req = Store.shared.request("health.php?exercise=30"), let (data, _) = try? await URLSession.shared.data(for: req) else { return }
        struct R: Decodable { var exercises: [AirExercise] }
        if let r = try? JSONDecoder().decode(R.self, from: data) { list = r.exercises.sorted { $0.start > $1.start }; last = Date() }
    }

    /// The Air's recording that overlaps a logged session: its heart rate and calories
    func match(_ s: WorkoutSession) -> AirExercise? {
        let start = Date(timeIntervalSince1970: s.start / 1000), end = Date(timeIntervalSince1970: (s.end ?? nowMs()) / 1000)
        return list.first { e in
            let es = e.startDate, ee = es.addingTimeInterval(Double(e.minutes) * 60)
            return es < end.addingTimeInterval(600) && ee > start.addingTimeInterval(-600)
        }
    }
}

struct Measurement: Record, Equatable {
    static let kind = "measure"
    var id: String { date }
    var date = Day.today
    var values: [String: Double] = [:] // waist, chest, hips, arm, thigh, calf, neck, shoulders, forearm, body fat

    init(date: String = Day.today, values: [String: Double] = [:]) { self.date = date; self.values = values }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.value(.date, or: Day.today)
        values = try c.dictionary(.values)
    }
}

let measurementNames = ["Waist", "Chest", "Hips", "Arm", "Thigh", "Calf", "Neck", "Shoulders", "Forearm", "Body fat %"]

/// What each measurement shows; the English names above are the keys saved in Measurement.values
func measurementLabel(_ name: String) -> String {
    ["Waist": "Cintura", "Chest": "Peito", "Hips": "Ancas", "Arm": "Braço", "Thigh": "Coxa", "Calf": "Barriga da perna",
     "Neck": "Pescoço", "Shoulders": "Ombros", "Forearm": "Antebraço", "Body fat %": "Gordura corporal %"][name] ?? name
}

enum ProgressPhotos {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("progress", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static func save(_ data: Data) { try? data.write(to: dir.appendingPathComponent("\(Day.today)-\(Int(Date().timeIntervalSince1970)).jpg")) }
    static var all: [(date: String, url: URL)] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jpg" }.map { (String($0.lastPathComponent.prefix(10)), $0) }.sorted { $0.0 > $1.0 }
    }
}

struct Payday: Record, Equatable {
    static let kind = "payday"
    var id: String { month }
    var month: String
    var jobs: [String: Double] // bucket → euros

    init(month: String, jobs: [String: Double]) { self.month = month; self.jobs = jobs }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = try c.decode(String.self, forKey: .month)
        jobs = try c.dictionary(.jobs)
    }
}

struct PipAccessory: Identifiable {
    var id: String // the image suffix and the Lottie layer "Acc <name>"
    var name: String
    var slot: String // head, face, neck
    var level: Int
    var layer: String
    var icon: String
}

/// Pip's wardrobe, unlocked by level: one piece per slot
let pipAccessories: [PipAccessory] = [
    PipAccessory(id: "scarf", name: "Cachecol", slot: "neck", level: 2, layer: "Acc Scarf", icon: "wind"),
    PipAccessory(id: "sweatband", name: "Fita de testa", slot: "head", level: 3, layer: "Acc Sweatband", icon: "figure.run"),
    PipAccessory(id: "glasses", name: "Óculos de ler", slot: "face", level: 5, layer: "Acc Glasses", icon: "eyeglasses"),
    PipAccessory(id: "bow-tie", name: "Laço", slot: "neck", level: 7, layer: "Acc Bow tie", icon: "sparkles"),
    PipAccessory(id: "sunglasses", name: "Óculos de sol", slot: "face", level: 9, layer: "Acc Sunglasses", icon: "sunglasses.fill"),
    PipAccessory(id: "leaf-crown", name: "Coroa de louro", slot: "head", level: 12, layer: "Acc Leaf crown", icon: "laurel.leading"),
    PipAccessory(id: "headphones", name: "Auscultadores", slot: "head", level: 15, layer: "Acc Headphones", icon: "headphones"),
    PipAccessory(id: "medal", name: "Medalha", slot: "neck", level: 20, layer: "Acc Medal", icon: "medal.fill"),
]

/// What each time-audit row shows; the English names stay, because timeAuditSuggestion(week:) finds rows by them
func timeAuditLabel(_ name: String) -> String {
    ["Focus sessions": "Sessões de foco", "Calendar events": "Eventos do calendário", "VS Code, active": "VS Code, ativo",
     "Training": "Treino", "Reading": "Leitura", "Travelling": "Deslocações"][name] ?? name
}

@MainActor
extension Store {
    // MARK: Rest or train

    /// The next 3 days of readiness if you train today against if you rest, from how your readiness moved after
    /// your own training and rest days
    func restOrTrain() -> (train: [Int], rest: [Int])? {
        guard let now = readiness()?.score else { return nil }
        var afterTrain: [Double] = [], afterRest: [Double] = []
        for i in 1..<45 {
            let d = Day.add(-i, to: Day.today), next = Day.add(1, to: d)
            guard let a = readiness(on: d)?.score, let b = readiness(on: next)?.score else { continue }
            let trained = !sessions(on: d).isEmpty || (health[d]?.azm ?? 0) >= 30
            if trained { afterTrain.append(Double(b - a)) } else { afterRest.append(Double(b - a)) }
        }
        let t = afterTrain.count >= 3 ? afterTrain.reduce(0, +) / Double(afterTrain.count) : -6
        let r = afterRest.count >= 3 ? afterRest.reduce(0, +) / Double(afterRest.count) : 4
        func path(_ first: Double) -> [Int] {
            var v = Double(now), out: [Int] = []
            v += first; out.append(Int(min(100, max(1, v))))
            for _ in 0..<2 { v += (70 - v) * 0.3; out.append(Int(min(100, max(1, v)))) } // drifts back to your normal
            return out
        }
        return (path(t), path(r))
    }

    // MARK: Reading and sleep

    func readingAndSleep() -> (with: Int, without: Int, nights: Int)? {
        var with: [Int] = [], without: [Int] = []
        for i in 1..<60 {
            let d = Day.add(-i, to: Day.today)
            guard let s = health[Day.add(1, to: d)]?.sleep else { continue }
            let evening = all(ReadingSession.self).filter { $0.date == d && Day.minuteOfDay(Date(timeIntervalSince1970: $0.start / 1000)) >= 20 * 60 }.map(\.minutes).reduce(0, +)
            if evening >= 15 { with.append(s.asleep) } else { without.append(s.asleep) }
        }
        guard with.count >= 4, without.count >= 4 else { return nil }
        return (with.reduce(0, +) / with.count, without.reduce(0, +) / without.count, with.count)
    }

    // MARK: Where your time went

    func timeAudit(week: String) -> [(String, Int, Int?)] { // name, actual minutes, planned minutes
        let days = (0..<7).map { Day.add($0, to: week) }
        let events = Agenda.shared.events.filter { days.contains($0.day) && !$0.allDay }
        let meetings = events.map { $0.endMinute - $0.startMinute }.reduce(0, +)
        let focus = all(FocusSession.self).filter { days.contains($0.date) }
        let plannedDeep = all(PlanBlock.self).filter { days.contains($0.date) && $0.type == "deep" }.map(\.minutes).reduce(0, +)
        let desk = all(DeskEvent.self).filter { days.contains($0.date) && $0.kind == "active" }.map(\.minutes).reduce(0, +)
        let training = sessions().filter { days.contains($0.date) && $0.end != nil }.map { Int((($0.end ?? $0.start) - $0.start) / 60000) }.reduce(0, +)
        let reading = days.map { readingMinutes(on: $0) }.reduce(0, +)
        let travel = days.flatMap { commutes(on: $0) }.map { $0.travel * 2 }.reduce(0, +)
        var out: [(String, Int, Int?)] = [("Focus sessions", focus.map(\.minutes).reduce(0, +), plannedDeep > 0 ? plannedDeep : nil), ("Calendar events", meetings, nil), ("VS Code, active", desk, nil), ("Training", training, nil), ("Reading", reading, days.count * 30), ("Travelling", travel, nil)]
        for (project, list) in Dictionary(grouping: focus.filter { $0.projectId != nil }, by: { $0.projectId! }) {
            out.append(("· " + (record(Project.self, project)?.title ?? "Projeto"), list.map(\.minutes).reduce(0, +), nil))
        }
        return out
    }

    func timeAuditSuggestion(week: String) -> String {
        let a = timeAudit(week: week)
        let focus = a.first { $0.0 == "Focus sessions" }
        if let f = focus, let p = f.2, f.1 < p / 2 { return "Só aconteceu metade do trabalho focado que planeaste. Experimenta pô-lo antes da primeira reunião." }
        if let m = a.first(where: { $0.0 == "Calendar events" }), let f = focus, m.1 > f.1 * 2 { return "As reuniões ocuparam o dobro do teu tempo de foco. Protege um bloco de manhã na próxima semana." }
        return "Bom equilíbrio. Mantém os mesmos horários de trabalho focado na próxima semana."
    }

    // MARK: Weather-aware plan

    /// An outdoor block (run, walk) inside a rain window: the nearest dry hour instead
    func weatherMoves(on day: String = Day.today) -> [(PlanBlock, Int)] {
        guard day == Day.today, let w = WeatherStore.shared.today else { return [] }
        let words = ["run", "walk", "bike", "outside", "corrida", "caminhada"]
        let outdoor = all(PlanBlock.self).filter { b in b.date == day && words.contains { b.title.lowercased().contains($0) } }
        return outdoor.compactMap { b -> (PlanBlock, Int)? in
            let wet = w.hours.filter { $0.minute >= b.start - 30 && $0.minute < b.start + b.minutes && $0.rain >= 50 }
            guard !wet.isEmpty else { return nil }
            let dry = w.hours.filter { $0.minute < 1440 && $0.minute >= Day.minuteOfDay() && $0.rain < 30 && $0.minute + b.minutes <= sleepPlan().windDown }.min { abs($0.minute - b.start) < abs($1.minute - b.start) }
            return dry.map { (b, $0.minute) }
        }
    }

    // MARK: Money extras

    /// Each purchase rounded up to the next euro, saved toward a goal this month
    func roundUps() -> Double {
        let (start, end) = monthRange()
        return spending(from: start, to: end).map { t in let a = -t.amount; return (a.rounded(.up) - a) }.reduce(0, +)
    }

    /// Prepped portions against eating out and delivery: what prep saved this month
    func prepSavings() -> (eatingOut: Double, perPortion: Double?, saved: Double?) {
        let (start, end) = monthRange()
        let out = spending(from: start, to: end).filter { ["Eating out", "Delivery"].contains(category(for: $0)) }.map { -$0.amount }.reduce(0, +)
        let groceries = spending(from: start, to: end).filter { category(for: $0) == "Groceries" }.map { -$0.amount }.reduce(0, +)
        let portions = all(Portion.self).filter { $0.made >= start && $0.made <= end }.count
        guard portions > 0 else { return (out, nil, nil) }
        let per = groceries / Double(portions)
        let restaurant = 12.0 // a typical lunch out in Portugal
        return (out, per, Double(all(Portion.self).filter { ($0.eaten ?? "") >= start }.count) * max(0, restaurant - per))
    }

    /// Protein per euro from the pantry prices you've entered (protein per pack in grams)
    func proteinValue() -> [(name: String, perEuro: Double)] {
        all(PantryItem.self).compactMap { p -> (String, Double)? in
            guard let price = p.price, price > 0, let protein = p.proteinPerPack, protein > 0 else { return nil }
            return (p.name, protein / price)
        }.sorted { $0.1 > $1.1 }.map { (name: $0.0, perEuro: $0.1) }
    }

    /// e-Fatura: what this year's receipts could deduct, by IRS category (an estimate; the Finanças portal decides)
    func efatura(year: String = String(Day.today.prefix(4))) -> [(String, Double, String)] {
        let tx = transactions.filter { $0.date.hasPrefix(year) && $0.amount < 0 }
        func total(_ cats: [String]) -> Double { tx.filter { cats.contains(category(for: $0)) }.map { -$0.amount }.reduce(0, +) }
        let vat = { (cats: [String]) -> Double in tx.filter { cats.contains(self.category(for: $0)) }.compactMap(\.vat).reduce(0, +) }
        let general = min(250, total(["Groceries", "Clothes", "Other", "Fun", "Subscriptions", "Bills"]) * 0.35)
        let health = min(1000, total(["Health"]) * 0.15)
        let housing = min(502, total(["Rent / house"]) * 0.15)
        let iva = vat(["Eating out", "Gym"]) * 0.15
        return [("Despesas gerais familiares", general, "35% até 250 €"), ("Saúde", health, "15% até 1000 €"), ("Habitação (renda)", housing, "15% até 502 €"), ("IVA: restauração, ginásio, cabeleireiro", iva, "15% do IVA")]
    }

    /// Spending during a trip against its budget
    func tripSpending(_ t: Trip) -> (spent: Double, perDay: Double?) {
        let spent = transactions.filter { $0.date >= t.start && $0.date <= t.end && $0.amount < 0 }.map { -$0.amount }.reduce(0, +)
        return (spent, t.budget.map { $0 / Double(max(1, t.nights)) })
    }

    // MARK: Pip

    /// What Pip is wearing: one unlocked piece per slot
    var pipOutfit: [PipAccessory] {
        let look = records("pipLook")
        return pipAccessories.filter { a in
            guard a.level <= level.level, case .string(let id)? = look[a.slot] else { return false }
            return id == a.id
        }
    }

    func wear(_ a: PipAccessory?, slot: String) {
        put("pipLook", slot, a.map { .string($0.id) })
    }
}
