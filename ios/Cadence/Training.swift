// Training: the RepDB exercise catalogue (downloaded to the phone, never bundled), templates, sessions with every
// set type, progression rules, estimated 1RM projections, warm-ups and plates, and the muscle maps.
import Foundation

// MARK: - Catalogue (RepDB, fetched at runtime: "Exercise data by RepDB (repdb.co)")

struct CatalogExercise: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var category: String?
    var bodyPart: String?
    var primary: [String]
    var secondary: [String]
    var bodyweight: Bool
    var instructions: [String]
    var tips: [String]
    var images: [String] // start, peak or main, as repo paths

    var groups: Set<String> { Set(primary.compactMap { muscleGroup[$0] }) }
    var secondaryGroups: Set<String> { Set(secondary.compactMap { muscleGroup[$0] }).subtracting(groups) }
    var imageURLs: [URL] { images.compactMap { URL(string: "https://raw.githubusercontent.com/RepDB/exercise-dataset/main/" + $0) } }
}

/// RepDB muscles onto GymMane's 14 body-map groups
let muscleGroup: [String: String] = [
    "gluteus_maximus": "glutes", "gluteus_medius": "glutes", "abductors": "glutes",
    "quadriceps": "quads", "hip_flexors": "quads", "adductors": "quads",
    "pectoralis_major": "chest", "latissimus_dorsi": "back", "rhomboids": "back", "infraspinatus_teres_minor": "back",
    "anterior_deltoid": "shoulders", "lateral_deltoid": "shoulders", "posterior_deltoid": "shoulders",
    "rectus_abdominis": "abdomen", "transverse_abdominis": "abdomen", "obliques": "obliques",
    "hamstrings": "hamstrings", "triceps_brachii": "triceps", "erector_spinae": "lowerback", "quadratus_lumborum": "lowerback",
    "biceps_brachii": "biceps", "brachialis": "biceps", "brachioradialis": "forearm", "forearm_flexors": "forearm", "forearm_extensors": "forearm",
    "trapezius": "trapezius", "gastrocnemius": "calves", "soleus": "calves", "tibialis_anterior": "calves",
]

let groupNames: [String: String] = [
    "glutes": "Glutes", "quads": "Quads", "chest": "Chest", "back": "Back", "shoulders": "Shoulders", "abdomen": "Abs", "obliques": "Obliques",
    "hamstrings": "Hamstrings", "triceps": "Triceps", "lowerback": "Lower back", "biceps": "Biceps", "forearm": "Forearms", "trapezius": "Traps", "calves": "Calves",
]

@MainActor
final class Catalog: ObservableObject {
    static let shared = Catalog()
    @Published private(set) var exercises: [CatalogExercise] = []
    @Published private(set) var loading = false
    private var byId: [String: CatalogExercise] = [:]
    private let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("repdb.json")

    private init() {
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([CatalogExercise].self, from: data) { set(list) }
    }

    private func set(_ list: [CatalogExercise]) {
        exercises = list.sorted { $0.name < $1.name }
        byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func exercise(_ id: String) -> CatalogExercise? { byId[id] }

    func load(force: Bool = false) async {
        if TestMode.active { return }
        guard force || exercises.isEmpty, !loading, let url = URL(string: "https://raw.githubusercontent.com/RepDB/exercise-dataset/main/exercises.json") else { return }
        loading = true
        defer { loading = false }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["exercises"] as? [[String: Any]] else { return }
        let list: [CatalogExercise] = raw.compactMap { e in
            guard let id = e["id"] as? String, let name = e["name_en"] as? String else { return nil }
            let imgs = (e["images"] as? [String: Any])?["flat"] as? [String: String] ?? [:]
            let ordered = ["start", "peak", "main"].compactMap { imgs[$0] }
            return CatalogExercise(id: id, name: name, category: e["category"] as? String, bodyPart: e["body_part"] as? String,
                                   primary: e["primary_muscles"] as? [String] ?? [], secondary: e["secondary_muscles"] as? [String] ?? [],
                                   bodyweight: e["is_bodyweight"] as? Bool ?? false, instructions: e["instructions_en"] as? [String] ?? [],
                                   tips: e["tips_en"] as? [String] ?? [], images: ordered)
        }
        guard !list.isEmpty else { return }
        set(list)
        if let out = try? JSONEncoder().encode(list) { try? out.write(to: file, options: .atomic) }
    }
}

// MARK: - Templates and sessions

struct TemplateExercise: Codable, Equatable, Identifiable, Hashable {
    var id = UUID().uuidString
    var exerciseId: String
    var name: String
    var sets = 3
    var repLow = 8
    var repHigh = 10
    var rest = 120 // seconds
    var increment = 2.5
}

struct WorkoutTemplate: Record, Equatable {
    static let kind = "template"
    var id = UUID().uuidString
    var name: String
    var exercises: [TemplateExercise]
    var weekdays: [Int] = []
    var minutes = 60
}

enum SetKind: String, Codable, CaseIterable {
    case warmup, working, drop, failure, restPause
    var short: String { ["warmup": "W", "working": "", "drop": "D", "failure": "F", "restPause": "RP"][rawValue]! }
}

struct SetLog: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var exerciseId: String
    var kind: SetKind = .working
    var weight: Double
    var reps: Int
    var rir: Int?
    var done = false
    var at: Double?
}

struct WorkoutSession: Record, Equatable {
    static let kind = "session"
    var id = UUID().uuidString
    var date = Day.today
    var templateId: String?
    var name: String
    var start = nowMs()
    var end: Double?
    var order: [TemplateExercise]
    var sets: [SetLog] = []
    var notes: [String: String] = [:]
    var feel: Int? // 1–5 after the session: the outcome readiness is checked against

    var volume: Double { sets.filter { $0.done && $0.kind != .warmup }.map { $0.weight * Double($0.reps) }.reduce(0, +) }

    init(id: String = UUID().uuidString, date: String = Day.today, templateId: String? = nil, name: String, start: Double = nowMs(), end: Double? = nil, order: [TemplateExercise], sets: [SetLog] = [], notes: [String: String] = [:]) {
        self.id = id; self.date = date; self.templateId = templateId; self.name = name; self.start = start; self.end = end; self.order = order; self.sets = sets; self.notes = notes
    }

    // A field an older record doesn't have takes its default, and an empty notes object the server sent back as [] is
    // empty; anything else that is there must read. A session with sets that can't be read is not shown with no sets
    // (which a save would make permanent): it isn't read at all, and its stored record stays as it is.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.value(.date, or: Day.today)
        templateId = try c.optional(.templateId)
        name = try c.value(.name, or: "Workout")
        start = try c.value(.start, or: nowMs())
        end = try c.optional(.end)
        order = try c.value(.order, or: [])
        sets = try c.value(.sets, or: [])
        notes = try c.dictionary(.notes)
        feel = try c.optional(.feel)
    }
}

/// Epley estimated one-rep max
func e1rm(_ weight: Double, _ reps: Int) -> Double { reps <= 1 ? weight : weight * (1 + Double(reps) / 30) }

func kg(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

@MainActor
extension Store {
    func sessions(on day: String? = nil) -> [WorkoutSession] {
        let all = self.all(WorkoutSession.self).sorted { $0.start > $1.start }
        return day.map { d in all.filter { $0.date == d } } ?? all
    }

    var activeSession: WorkoutSession? { sessions().first { $0.end == nil && Day.between($0.date, Day.today) <= 1 } }

    var templates: [WorkoutTemplate] { all(WorkoutTemplate.self).sorted { $0.name < $1.name } }

    /// Last finished working sets of an exercise
    func lastSets(_ exerciseId: String, before session: String? = nil) -> [SetLog] {
        for s in sessions() where s.id != session && s.end != nil {
            let sets = s.sets.filter { $0.exerciseId == exerciseId && $0.kind == .working && $0.done }
            if !sets.isEmpty { return sets }
        }
        return []
    }

    /// The progression rules: all sets at the top of the range → add the increment; low readiness → same weight,
    /// one set less; three sessions without progress → a 10% deload.
    func suggestion(for t: TemplateExercise, session: String? = nil) -> (weight: Double, sets: Int, reason: String) {
        let last = lastSets(t.exerciseId, before: session)
        guard let top = last.map(\.weight).max() else { return (0, t.sets, "First time: pick a weight you could do for \(t.repHigh + 2)") }
        let readiness = self.readiness()?.score ?? 70
        let lowNote = readiness < 50 ? " · readiness \(readiness): let the warm-up decide" : ""
        let hitTop = last.count >= t.sets && last.allSatisfy { $0.reps >= t.repHigh }
        if hitTop { return (top + t.increment, t.sets, "+\(kg(t.increment)) kg: you hit \(last.count) × \(t.repHigh) at \(kg(top)) last time" + lowNote) }
        let history = sessions().filter { $0.end != nil }.compactMap { s in s.sets.filter { $0.exerciseId == t.exerciseId && $0.kind == .working && $0.done }.map { e1rm($0.weight, $0.reps) }.max() }.prefix(4)
        if history.count == 4, let newest = history.first, history.dropFirst().allSatisfy({ $0 >= newest - 0.5 }) {
            return (((top * 0.9) / 2.5).rounded() * 2.5, t.sets, "Stalled for 3 sessions: a 10% deload, then build back")
        }
        return (top, t.sets, "Same weight: aim for \(t.repHigh) on every set" + lowNote)
    }

    /// Best estimated 1RM per session date for one exercise, oldest first
    func e1rmHistory(_ exerciseId: String) -> [(date: String, value: Double)] {
        sessions().reversed().compactMap { s in
            s.sets.filter { $0.exerciseId == exerciseId && $0.done && $0.kind != .warmup }.map { e1rm($0.weight, $0.reps) }.max().map { (s.date, $0) }
        }
    }

    /// A straight-line fit over the last 8 weeks, projected to a goal
    func projection(_ exerciseId: String, goal: Double) -> (date: String, perWeek: Double)? {
        let points = e1rmHistory(exerciseId).filter { Day.between($0.date, Day.today) <= 56 }
        guard points.count >= 3, let first = points.first else { return nil }
        let xs = points.map { Double(Day.between(first.date, $0.date)) }, ys = points.map(\.value)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let slope = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +) / max(0.001, xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +))
        guard slope > 0.01, let current = ys.last, goal > current else { return nil }
        let days = Int(((goal - current) / slope).rounded())
        return (Day.add(days, to: Day.today), slope * 7)
    }

    // MARK: Muscles

    /// Groups trained in a session (primary muscles of done sets)
    func groups(of session: WorkoutSession) -> Set<String> {
        Set(session.sets.filter { $0.done && $0.kind != .warmup }.flatMap { Catalog.shared.exercise($0.exerciseId)?.groups ?? [] })
    }

    /// Days since each group was last trained
    func freshness() -> [String: Int] {
        var out: [String: Int] = [:]
        for s in sessions() where s.end != nil {
            for g in groups(of: s) where out[g] == nil { out[g] = Day.between(s.date, Day.today) }
        }
        return out
    }

    enum Growth { case growing, underRested, underFed }

    /// For 48 hours after a session: is each trained muscle getting the protein and sleep to grow?
    func growthCheck() -> (session: WorkoutSession, status: [String: Growth], protein: (got: Double, need: Double), sleep: (got: Int, need: Int))? {
        guard let s = sessions().first(where: { $0.end != nil && Day.between($0.date, Day.today) <= 2 }) else { return nil }
        let days = (0...Day.between(s.date, Day.today)).map { Day.add($0, to: s.date) }
        let protein = days.map { fuel(on: $0).protein }.reduce(0, +)
        let todayShare = days.last == Day.today ? min(1, Double(Day.minuteOfDay()) / 1260) : 1 // by 21:00 the full day counts
        let proteinNeed = profile.proteinTarget * (Double(days.count - 1) + todayShare)
        let nights = days.dropFirst().compactMap { health[$0]?.sleep?.asleep }
        let sleepGot = nights.reduce(0, +), sleepNeed = profile.sleepNeed * max(1, nights.count)
        let fed = protein >= proteinNeed * 0.85, rested = nights.isEmpty || Double(sleepGot) >= Double(sleepNeed) * 0.9
        var status: [String: Growth] = [:]
        for g in groups(of: s) { status[g] = !fed ? .underFed : !rested ? .underRested : .growing }
        return (s, status, (protein, proteinNeed), (sleepGot, sleepNeed))
    }

    func plates(for total: Double) -> [Double] {
        var side = max(0, (total - profile.barKg) / 2)
        var out: [Double] = []
        for p in profile.plates.sorted(by: >) { while side >= p - 0.001 { out.append(p); side -= p } }
        return out
    }

    func warmups(for working: Double) -> [(weight: Double, reps: Int)] {
        guard working > profile.barKg + 10 else { return [] }
        return [(0.4, 8), (0.6, 5), (0.8, 3)].map { (max(profile.barKg, ((working * $0.0) / 2.5).rounded() * 2.5), $0.1) }
    }

    /// Default templates so training works before you build your own
    func seedTemplates() {
        seedPlan()
        guard templates.isEmpty else { return }
        func t(_ id: String, _ name: String, _ sets: Int = 3, _ lo: Int = 8, _ hi: Int = 10, _ rest: Int = 120, _ inc: Double = 2.5) -> TemplateExercise {
            TemplateExercise(exerciseId: id, name: name, sets: sets, repLow: lo, repHigh: hi, rest: rest, increment: inc)
        }
        let all = [
            WorkoutTemplate(name: "Legs A", exercises: [t("squat", "Barbell Back Squat", 4, 6, 8, 180), t("romanian-deadlift", "Romanian Deadlift", 3, 8, 10, 150), t("leg-press", "Leg Press", 3, 10, 12, 120, 5), t("leg-curl", "Lying Leg Curl", 3, 10, 12, 90), t("standing-calf-raise", "Standing Calf Raise", 4, 10, 15, 60)]),
            WorkoutTemplate(name: "Push A", exercises: [t("bench-press", "Barbell Bench Press", 4, 6, 8, 180), t("ohp", "Barbell Overhead Press", 3, 6, 8, 150), t("incline-bench-press", "Incline Barbell Bench Press", 3, 8, 10, 120)]),
            WorkoutTemplate(name: "Pull A", exercises: [t("deadlift", "Deadlift", 3, 4, 6, 210, 5), t("pull-up", "Pull-Up", 3, 6, 10, 150, 1.25)]),
        ]
        for x in all { save(x) }
    }
}
