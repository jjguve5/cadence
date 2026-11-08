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
    var mechanic: String? = nil // RepDB's "compound" or "isolation"; nil in a catalogue cached before phase 2.6

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
    "glutes": "Glúteos", "quads": "Quadríceps", "chest": "Peito", "back": "Costas", "shoulders": "Ombros", "abdomen": "Abdominais", "obliques": "Oblíquos",
    "hamstrings": "Isquiotibiais", "triceps": "Tríceps", "lowerback": "Lombar", "biceps": "Bíceps", "forearm": "Antebraços", "trapezius": "Trapézio", "calves": "Gémeos",
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
        guard force || exercises.isEmpty || !exercises.contains(where: { $0.mechanic != nil }), !loading, let url = URL(string: "https://raw.githubusercontent.com/RepDB/exercise-dataset/main/exercises.json") else { return }
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
                                   tips: e["tips_en"] as? [String] ?? [], images: ordered, mechanic: e["mechanic"] as? String)
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
    var userRest: Int? // the rest you changed in the editor; nil follows the rule (optional: older builds ignore it)
}

extension TemplateExercise {
    /// The rest after a set of `reps`: the one you set in the template, if you set one, else the rule (D30 revised)
    func restAfter(reps: Int, mechanic: ExerciseMechanic?) -> (seconds: Int, reason: String) {
        TrainingRules.rest(mechanic, reps: reps, templateRest: rest, chosen: userRest)
    }

    /// What the template editor shows until you change it: the rule's rest for the top of the range, and why
    func defaultRest(mechanic: ExerciseMechanic?) -> (seconds: Int, reason: String) {
        TrainingRules.rest(mechanic, reps: repHigh, templateRest: rest)
    }

    /// You changed the rest in the editor: only then is a value yours. `rest` follows it, for older builds
    mutating func setRest(_ seconds: Int) {
        userRest = seconds
        rest = seconds
    }
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
    var short: String { ["warmup": "AQ", "working": "", "drop": "D", "failure": "F", "restPause": "RP"][rawValue]! }
    /// What the set-type menu shows; the raw value is what's saved
    var label: String { ["warmup": "Aquecimento", "working": "Normal", "drop": "Drop set", "failure": "Até à falha", "restPause": "Rest-pause"][rawValue]! }
}

/// One set. Weight and reps are what you did once it's registered (done); before that they are what you set on the
/// steppers, and 0 × 0 means you haven't touched them. The target the app suggested is kept apart (phase 2.6): it is
/// never written into weight or reps, and correcting what you did never changes it.
struct SetLog: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var exerciseId: String
    var kind: SetKind = .working
    var weight: Double
    var reps: Int
    var rir: Int? // repetitions in reserve, your answer on the last working set (0…3, 4 = four or more)
    var done = false
    var at: Double?
    var targetWeight: Double? // the suggested target (optional fields: older sessions read, older builds ignore them)
    var targetReps: Int?
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
    // Phase 2.6, all optional (older sessions read, older builds ignore them):
    var pausedAt: Double? // paused since (ms)
    var partial: Bool? // ended before the plan was done: «Terminar aqui», or left open past 23:59
    var skipped: [String: String]? // exercise id → why it was skipped (busy, pain, time, other or ""), never "failed"
    var reordered: [String]? // exercises done earlier than planned («trocado de ordem»)
    var swapped: [String: String]? // exercise id → the exercise it replaced

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
        name = try c.value(.name, or: "Treino")
        start = try c.value(.start, or: nowMs())
        end = try c.optional(.end)
        order = try c.list(.order)
        sets = try c.list(.sets)
        notes = try c.dictionary(.notes)
        feel = try c.optional(.feel)
        pausedAt = try c.optional(.pausedAt)
        partial = try c.optional(.partial)
        skipped = try c.optionalDictionary(.skipped)
        reordered = try c.optionalList(.reordered)
        swapped = try c.optionalDictionary(.swapped)
    }
}

private extension KeyedDecodingContainer {
    /// An optional dictionary: missing or null is nil, and an empty list (how PHP writes an empty object) is empty
    func optionalDictionary<V: Decodable>(_ key: Key) throws -> [String: V]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let d: [String: V] = try dictionary(key)
        return d
    }

    /// An optional list: missing or null is nil, and an empty object (an older server's empty list) is empty
    func optionalList<E: Decodable>(_ key: Key) throws -> [E]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let l: [E] = try list(key)
        return l
    }
}

/// Epley estimated one-rep max
func e1rm(_ weight: Double, _ reps: Int) -> Double { reps <= 1 ? weight : weight * (1 + Double(reps) / 30) }

func kg(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

// MARK: - Phase 2.6: targets apart from what you did, warm-ups, rest, changes of plan and interruptions

/// What a session asks of one exercise: the weight and reps to aim for, and why
struct SetTarget: Equatable {
    var weight: Double
    var reps: Int
    var reason: String
}

/// A warm-up set as planned; no weight means a light one you choose
struct WarmupSet: Equatable {
    var weight: Double?
    var reps: Int
}

/// One exercise of a session about to start
struct PlannedExercise: Equatable {
    var exercise: TemplateExercise
    var target: SetTarget? // nil: no history, you choose
    var warmups: [WarmupSet]
    var warmedBy: Int? // the earlier exercise (its place in the session) that already warmed its muscle groups
    var groups: Set<String>
}

/// The summary's «Próxima vez» for one exercise
struct NextProposal: Equatable, Identifiable {
    var exercise: TemplateExercise
    var weight: Double
    var reps: Int
    var reason: String
    var changes: Bool // false: the next target is this anyway
    var id: String { exercise.exerciseId }
}

/// The target you accepted for the next session of one exercise (record "trainingTarget", id "next:<exercise id>").
/// Only Aceitar or Ajustar in the summary writes it. It applies to the next session of that exercise, whose sets then
/// carry it as their target.
struct TrainingTarget: Record, Equatable {
    static let kind = "trainingTarget"
    var id: String
    var exerciseId: String
    var weight: Double
    var reps: Int
    var reason: String
    var session: String // the session whose summary proposed it
    var at: Double
}

enum ExerciseMechanic: Equatable { case compound, isolation }

/// Why an exercise was skipped: saved as its code in WorkoutSession.skipped (a plain string, so a code an older or
/// newer build doesn't know still reads), shown in words
enum ExerciseSkipReason: String, CaseIterable {
    case busy, pain, time, other
    var label: String {
        switch self {
        case .busy: return "Máquina ocupada"
        case .pain: return "Desconforto ou dor"
        case .time: return "Pouco tempo"
        case .other: return "Outro"
        }
    }
}

enum TrainingRules {
    /// The done working sets of an exercise in a session
    static func working(_ exerciseId: String, in s: WorkoutSession) -> [SetLog] {
        s.sets.filter { $0.exerciseId == exerciseId && $0.kind == .working && $0.done }
    }

    static func bestE1rm(_ exerciseId: String, in s: WorkoutSession) -> Double? {
        working(exerciseId, in: s).map { e1rm($0.weight, $0.reps) }.max()
    }

    /// The progression rules on their own. `last`: the done working sets of the latest session; `history`: the best
    /// e1RM of each finished session, newest first. nil without history. `readinessNote`: where low readiness adds a note.
    static func progression(_ t: TemplateExercise, last: [SetLog], history: [Double]) -> (weight: Double, reason: String, readinessNote: Bool)? {
        guard let top = last.map(\.weight).max() else { return nil }
        let hitTop = last.count >= t.sets && last.allSatisfy { $0.reps >= t.repHigh }
        // Your answer on the last set feeds the next suggestion: nothing left in reserve, the load doesn't go up
        if hitTop && last.contains(where: { $0.rir == 0 }) {
            return (top, "Mesmo peso: chegaste ao topo sem repetições em reserva, por isso a carga não sobe", true)
        }
        if hitTop { return (top + t.increment, "+\(kg(t.increment)) kg: da última vez fizeste \(last.count) × \(t.repHigh) com \(kg(top))", true) }
        let recent = history.prefix(4)
        if recent.count == 4, let newest = recent.first, recent.dropFirst().allSatisfy({ $0 >= newest - 0.5 }) {
            return (((top * 0.9) / 2.5).rounded() * 2.5, "Sem progresso há 3 sessões: desce 10% e volta a subir", false)
        }
        return (top, "Mesmo peso: tenta \(t.repHigh) em todas as séries", true)
    }

    /// The next target when nothing new was accepted: last session's target as it was, else what you did then
    static func carry(_ done: [SetLog], repHigh: Int) -> SetTarget? {
        guard let top = done.map(\.weight).max() else { return nil }
        if let w = done.compactMap(\.targetWeight).max() {
            let reps = done.first { $0.targetWeight == w }?.targetReps ?? repHigh
            return SetTarget(weight: w, reps: reps, reason: "o mesmo objetivo da última vez; só muda quando aceitas uma sugestão no fim do treino")
        }
        return SetTarget(weight: top, reps: repHigh, reason: "da última vez fizeste \(setsText(done))")
    }

    /// For each exercise, nil when it gets warm-ups: the first one of a muscle group new in the session, or one whose
    /// groups aren't known. Otherwise the place of the earlier exercise that warmed its groups.
    static func warmedBy(_ groups: [Set<String>]) -> [Int?] {
        var first: [String: Int] = [:]
        var out: [Int?] = []
        for (i, g) in groups.enumerated() {
            let warmed = g.compactMap { first[$0] }
            out.append(g.isEmpty || warmed.count < g.count ? nil : warmed.min())
            for x in g where first[x] == nil { first[x] = i }
        }
        return out
    }

    /// The groups an exercise warms: its main muscle groups; none for cardio or stretching, or when it isn't known
    static func warmupGroups(_ e: CatalogExercise?) -> Set<String> {
        guard let e, !isConditioning(e) else { return [] }
        return e.groups
    }

    /// Cardio and stretching: no warm-up sets of their own, and they don't warm a group for the exercises after them
    static func isConditioning(_ e: CatalogExercise) -> Bool { ["cardio", "stretching"].contains(e.category ?? "") }

    /// Compound or isolation: RepDB's own field, else from the muscles (two main groups, or three with the secondary
    /// ones, is compound)
    static func mechanic(_ e: CatalogExercise) -> ExerciseMechanic {
        if e.mechanic == "compound" { return .compound }
        if e.mechanic == "isolation" { return .isolation }
        return e.groups.count >= 2 || e.groups.union(e.secondaryGroups).count >= 3 ? .compound : .isolation
    }

    /// The rest after a working set. One you set in the template (`chosen`) prevails for that exercise; otherwise it
    /// comes from the exercise and the set just done: compound and heavy 2:30, compound with 8 or more reps 2:00,
    /// isolation and heavy (6 or fewer reps) 1:30, light isolation 1:15. An exercise that isn't known keeps its
    /// template's rest.
    static func rest(_ mechanic: ExerciseMechanic?, reps: Int, templateRest: Int, chosen: Int? = nil) -> (seconds: Int, reason: String) {
        if let chosen { return (chosen, "o descanso que definiste no modelo para este exercício.") }
        let r = reps == 1 ? "1 repetição" : "\(reps) repetições"
        switch mechanic {
        case .compound?: return reps >= 8 ? (120, "exercício composto, série de \(r).") : (150, "exercício composto e pesado, série de \(r).")
        case .isolation?: return reps <= 6 ? (90, "isolamento pesado, série de \(r).") : (75, "isolamento leve, série de \(r).")
        case nil: return (templateRest, "o descanso do modelo para este exercício.")
        }
    }

    /// A rest as the ring shows it: "2:30"
    static func restClock(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Where the steppers start for a set not yet registered: what you set on it, else its target, else the set you
    /// registered before it, else nothing on the bar and the top of the range
    static func startingValues(_ set: SetLog, previous: SetLog?, repHigh: Int) -> (weight: Double, reps: Int) {
        if set.done || set.reps > 0 { return (set.weight, set.reps) }
        return (set.targetWeight ?? previous?.weight ?? set.weight, set.targetReps ?? previous?.reps ?? repHigh)
    }

    /// The planned sets of an exercise: warm-ups, then working sets, each with its target and nothing in weight or reps
    static func sets(for p: PlannedExercise) -> [SetLog] {
        let id = p.exercise.exerciseId
        let warm = p.warmups.map { SetLog(exerciseId: id, kind: .warmup, weight: 0, reps: 0, targetWeight: $0.weight, targetReps: $0.reps) }
        let work = (0..<max(0, p.exercise.sets)).map { _ in SetLog(exerciseId: id, weight: 0, reps: 0, targetWeight: p.target?.weight, targetReps: p.target?.reps) }
        return warm + work
    }

    /// "20 kg × 11, 10, 10" with one weight, "20 kg × 11, 17.5 kg × 10" with several; without weight, reps only
    static func setsText(_ sets: [SetLog]) -> String {
        guard let first = sets.first else { return "" }
        if sets.allSatisfy({ $0.weight == first.weight }) {
            let reps = sets.map { "\($0.reps)" }.joined(separator: ", ")
            return first.weight == 0 ? "\(reps) reps" : "\(kg(first.weight)) kg × \(reps)"
        }
        return sets.map { setText($0.weight, $0.reps) }.joined(separator: ", ")
    }

    static func setText(_ weight: Double, _ reps: Int) -> String { weight == 0 ? "\(reps) reps" : "\(kg(weight)) kg × \(reps)" }

    /// The summary's comparison with the last time: "+2 kg", "−2.5 kg", "+2 reps", "igual", or "1.ª vez"
    static func change(now: [SetLog], before: [SetLog]) -> String {
        guard let top = now.map(\.weight).max() else { return "" }
        guard let was = before.map(\.weight).max() else { return "1.ª vez" }
        if top != was { return (top > was ? "+" : "−") + "\(kg(abs(top - was))) kg" }
        let reps = now.map(\.reps).reduce(0, +) - before.map(\.reps).reduce(0, +)
        return reps == 0 ? "igual" : (reps > 0 ? "+" : "−") + "\(abs(reps)) reps"
    }

    /// Left open past 23:59 of its day
    static func isExpired(_ s: WorkoutSession, today: String) -> Bool { s.end == nil && s.date < today }

    /// Left open past 23:59 with at least one set registered: what counts as a partial session when it's read. One
    /// started and left empty recorded nothing, so it counts as nothing («ausência ≠ zero»)
    static func leftPartial(_ s: WorkoutSession, today: String) -> Bool { isExpired(s, today: today) && s.sets.contains(where: \.done) }

    static func isPartial(_ s: WorkoutSession, today: String) -> Bool { s.partial == true || leftPartial(s, today: today) }

    /// Over, for everything that reads past sessions (progression, goals, history): finished, or left open past 23:59,
    /// which counts as partial. Worked out when it is read; nothing is written to the session (D23)
    static func isEnded(_ s: WorkoutSession, today: String) -> Bool { s.end != nil || leftPartial(s, today: today) }

    /// The last thing done in a session: its last registered set, or when it was paused, or its start
    static func lastActivity(_ s: WorkoutSession) -> Double {
        max(s.start, s.sets.compactMap { $0.done ? $0.at : nil }.max() ?? 0, s.pausedAt ?? 0)
    }

    /// A target's record id, for saving and for reading: "next:" and the exercise id, only [A-Za-z0-9_.:-], up to 80
    /// characters. When cleaning or the length changed the exercise id, a hash of the original (FNV-1a, 8 hex digits, as
    /// Store.boughtKey) goes at the end, so two exercises that clean to the same text never share a target.
    static func targetId(_ exerciseId: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-")
        let original = "next:" + exerciseId
        let chars: [Character] = original.map { allowed.contains($0) ? $0 : "_" }
        let plain = String(chars)
        if plain == original && plain.count <= 80 { return plain }
        var hash: UInt32 = 2166136261
        for byte in exerciseId.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return String(plain.prefix(80 - 9)) + "_" + String(format: "%08x", hash)
    }

    /// A reason as it reads after «Porquê»: first letter in lower case
    static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// The working sets below their target, for the summary: "a 3.ª abaixo do objetivo", "2 séries abaixo do objetivo"
    static func belowTarget(_ sets: [SetLog]) -> String? {
        let below = sets.indices.filter { i in
            let s = sets[i]
            guard let tr = s.targetReps else { return false }
            return s.reps < tr || s.weight < (s.targetWeight ?? 0)
        }
        if below.isEmpty { return nil }
        return below.count == 1 ? "a \(below[0] + 1).ª abaixo do objetivo" : "\(below.count) séries abaixo do objetivo"
    }

    /// Muscle groups in words: "quadríceps", "isquiotibiais e glúteos", "costas, bíceps e ombros"
    static func groupsText(_ groups: Set<String>) -> String {
        let names = groups.compactMap { groupNames[$0]?.lowercased() }.sorted()
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " e " + last
    }

    /// "3 × 8–12", or "3 × 10" when the range is one number
    static func planText(_ t: TemplateExercise) -> String {
        t.repLow == t.repHigh ? "\(t.sets) × \(t.repHigh)" : "\(t.sets) × \(t.repLow)–\(t.repHigh)"
    }

    /// Exercises that can replace this one: strength, sharing a main muscle group, not in the session; the ones you've
    /// done before first, then the ones with weights
    static func alternatives(to e: CatalogExercise, from all: [CatalogExercise], excluding: Set<String>, known: Set<String>) -> [CatalogExercise] {
        let same = all.filter { $0.id != e.id && !excluding.contains($0.id) && $0.category == "strength" && !$0.groups.isDisjoint(with: e.groups) }
        return same.filter { known.contains($0.id) } + same.filter { !known.contains($0.id) && !$0.bodyweight } + same.filter { !known.contains($0.id) && $0.bodyweight }
    }
}

extension WorkoutSession {
    func isSkipped(_ exerciseId: String) -> Bool { skipped?[exerciseId] != nil }

    var isPaused: Bool { end == nil && pausedAt != nil }

    /// The set to do now: the first one not registered, following the order of the exercises, skipped ones left out
    func currentSet() -> (exercise: TemplateExercise, index: Int)? {
        for ex in order where !isSkipped(ex.exerciseId) {
            if let i = sets.firstIndex(where: { $0.exerciseId == ex.exerciseId && !$0.done }) { return (ex, i) }
        }
        return nil
    }

    /// Where the steppers start for the set at `index`
    func startingValues(at index: Int, repHigh: Int) -> (weight: Double, reps: Int) {
        let set = sets[index]
        let previous = sets.filter { $0.exerciseId == set.exerciseId && $0.kind == set.kind && $0.done && $0.id != set.id }.last
        return TrainingRules.startingValues(set, previous: previous, repHigh: repHigh)
    }

    /// The last working set of its exercise still to do: where the effort question (RIR) goes
    func isLastWorking(_ index: Int) -> Bool {
        guard sets.indices.contains(index) else { return false }
        let set = sets[index]
        guard set.kind == .working, !set.done else { return false }
        // the last set of kind .working of its exercise in the session's order, the sets the progression reads (spec:
        // «só na última série de trabalho»), not a drop, failure or rest-pause set after it, whether or not the earlier
        // ones are registered yet
        return sets.indices.last(where: { sets[$0].exerciseId == set.exerciseId && sets[$0].kind == .working }) == index
    }

    /// Registers what you did: the values become the set's; its target stays as it was. Registering resumes a pause.
    mutating func register(_ index: Int, weight: Double, reps: Int, rir: Int?, at: Double = nowMs()) {
        guard sets.indices.contains(index) else { return }
        sets[index].weight = weight
        sets[index].reps = reps
        if let rir { sets[index].rir = rir }
        sets[index].done = true
        sets[index].at = at
        pausedAt = nil
    }

    /// Something still to do after the set just registered (so a rest makes sense)
    var hasSetsLeft: Bool { sets.contains { !$0.done && !isSkipped($0.exerciseId) } }

    /// Exercises with a registered working set
    var exercisesDone: [TemplateExercise] {
        var seen = Set<String>()
        return order.filter { ex in seen.insert(ex.exerciseId).inserted && !TrainingRules.working(ex.exerciseId, in: self).isEmpty }
    }

    mutating func skip(_ exerciseId: String, reason: String) {
        var all = skipped ?? [:]
        all[exerciseId] = reason
        skipped = all
    }

    /// The next exercise still to do after this one (not skipped, with a set to do)
    func next(after exerciseId: String) -> TemplateExercise? {
        guard let i = order.firstIndex(where: { $0.exerciseId == exerciseId }) else { return nil }
        return order[(i + 1)...].first { e in !isSkipped(e.exerciseId) && sets.contains { $0.exerciseId == e.exerciseId && !$0.done } }
    }

    /// Moves an exercise to just before another (done now, the other right after), marked «trocado de ordem»
    mutating func moveUp(_ exerciseId: String, before other: String) {
        guard let from = order.firstIndex(where: { $0.exerciseId == exerciseId }), let to = order.firstIndex(where: { $0.exerciseId == other }), from > to else { return }
        let ex = order.remove(at: from)
        order.insert(ex, at: to)
        var marks = reordered ?? []
        if !marks.contains(exerciseId) { marks.append(exerciseId) }
        reordered = marks
    }

    /// Replaces an exercise by another. Its registered sets stay (and so does it, if it has any); its sets still to do
    /// go, and the new one's planned sets come in.
    mutating func replace(_ old: TemplateExercise, with new: TemplateExercise, sets planned: [SetLog]) {
        guard let i = order.firstIndex(where: { $0.exerciseId == old.exerciseId }) else { return }
        let hasDone = sets.contains { $0.exerciseId == old.exerciseId && $0.done }
        sets.removeAll { $0.exerciseId == old.exerciseId && !$0.done }
        if hasDone { order.insert(new, at: i + 1) } else { order[i] = new }
        sets.append(contentsOf: planned)
        var marks = swapped ?? [:]
        marks[new.exerciseId] = old.exerciseId
        swapped = marks
    }

    /// Ends the session at `at`. Sets not registered go (they were only the plan); every registered one stays.
    /// Partial when something planned and not skipped was left to do.
    mutating func finish(at: Double) {
        let left = hasSetsLeft
        sets.removeAll { !$0.done }
        end = at
        partial = left ? true : nil
    }

    /// Desfazer for a change of plan (skip, reorder, swap): the plan as it was, keeping every set registered since
    func restoringPlan(from before: WorkoutSession) -> WorkoutSession {
        var s = self
        s.order = before.order
        s.skipped = before.skipped
        s.reordered = before.reordered
        s.swapped = before.swapped
        var merged = before.sets
        for set in sets where set.done {
            if let i = merged.firstIndex(where: { $0.id == set.id }) { merged[i] = set } else { merged.append(set) }
        }
        s.sets = merged
        return s
    }
}

@MainActor
extension Store {
    func sessions(on day: String? = nil) -> [WorkoutSession] {
        let all = self.all(WorkoutSession.self).sorted { $0.start > $1.start }
        return day.map { d in all.filter { $0.date == d } } ?? all
    }

    /// The session in progress: open and from today. One left open past 23:59 of its day is partial, not in progress
    /// (phase 2.6), even before closeExpiredSessions() marks it as ended.
    var activeSession: WorkoutSession? { sessions().first { $0.end == nil && !TrainingRules.isExpired($0, today: Day.today) } }

    var templates: [WorkoutTemplate] { all(WorkoutTemplate.self).sorted { $0.name < $1.name } }

    /// Last working sets of an exercise, from a session that's over (finished, or left open past 23:59: partial)
    func lastSets(_ exerciseId: String, before session: String? = nil) -> [SetLog] {
        for s in sessions() where s.id != session && TrainingRules.isEnded(s, today: Day.today) {
            let sets = s.sets.filter { $0.exerciseId == exerciseId && $0.kind == .working && $0.done }
            if !sets.isEmpty { return sets }
        }
        return []
    }

    /// The latest session that's over with done working sets of an exercise (the one lastSets reads)
    func lastSession(with exerciseId: String, before session: String? = nil) -> WorkoutSession? {
        sessions().first { s in s.id != session && TrainingRules.isEnded(s, today: Day.today) && !TrainingRules.working(exerciseId, in: s).isEmpty }
    }

    /// Best estimated 1RM of the done working sets of each session that's over, newest first
    func bestE1rms(_ exerciseId: String) -> [Double] {
        sessions().filter { TrainingRules.isEnded($0, today: Day.today) }.compactMap { TrainingRules.bestE1rm(exerciseId, in: $0) }
    }

    /// The progression rules: all sets at the top of the range → add the increment (not when the last set had no
    /// repetitions in reserve, phase 2.6); three sessions without progress → a 10% deload; low readiness adds a note
    /// and never removes a set. This is what the app proposes; the target of a session only changes when you accept it.
    func suggestion(for t: TemplateExercise, session: String? = nil) -> (weight: Double, sets: Int, reason: String) {
        let last = lastSets(t.exerciseId, before: session)
        guard let p = TrainingRules.progression(t, last: last, history: bestE1rms(t.exerciseId)) else {
            return (0, t.sets, "Primeira vez: escolhe um peso com que conseguirias fazer \(t.repHigh + 2) repetições")
        }
        let readiness = self.readiness()?.score ?? 70
        let lowNote = readiness < 50 ? " · prontidão \(readiness): deixa o aquecimento decidir" : ""
        return (p.weight, t.sets, p.reason + (p.readinessNote ? lowNote : ""))
    }

    // MARK: Targets (phase 2.6: the suggested target and what you did are kept apart)

    /// The target of an exercise for a new session. No history: none («escolhes tu»). Otherwise the target you accepted
    /// at the end of the last session, else last session's target as it was, else what you did last time. A
    /// proposal (suggestion) never changes it by itself.
    func target(for t: TemplateExercise, session: String? = nil) -> SetTarget? {
        guard let last = lastSession(with: t.exerciseId, before: session) else { return nil }
        if let a = record(TrainingTarget.self, TrainingRules.targetId(t.exerciseId)), a.at > last.start {
            return SetTarget(weight: a.weight, reps: a.reps, reason: "aceitaste no fim do último treino · " + TrainingRules.sentence(a.reason))
        }
        return TrainingRules.carry(TrainingRules.working(t.exerciseId, in: last), repHigh: t.repHigh)
    }

    /// The light sets before the working ones: the 40/60/80% ramp when the target is heavy enough for it, else one
    /// light set (half the target, or a weight you choose)
    func warmupSets(for target: SetTarget?) -> [WarmupSet] {
        if let w = target?.weight {
            let ramp = warmups(for: w)
            if !ramp.isEmpty { return ramp.map { WarmupSet(weight: $0.weight, reps: $0.reps) } }
            let light = ((w * 0.5) / 2.5).rounded() * 2.5
            return [WarmupSet(weight: light > 0 ? light : nil, reps: 10)]
        }
        return [WarmupSet(weight: nil, reps: 10)]
    }

    /// A template as it will start: each exercise's target and its warm-ups, which only the first exercise of each muscle
    /// group new in the session gets
    func plan(_ t: WorkoutTemplate) -> [PlannedExercise] {
        plan(t.exercises, info: t.exercises.map { Catalog.shared.exercise($0.exerciseId) })
    }

    /// `info` is each exercise's catalogue entry (nil when it isn't known), in the same order
    func plan(_ exercises: [TemplateExercise], info: [CatalogExercise?]) -> [PlannedExercise] {
        let entries: [CatalogExercise?] = exercises.indices.map { i in i < info.count ? info[i] : nil }
        let groups: [Set<String>] = entries.map { TrainingRules.warmupGroups($0) }
        let warmed = TrainingRules.warmedBy(groups)
        return exercises.indices.map { i -> PlannedExercise in
            let ex = exercises[i]
            let target = self.target(for: ex)
            let conditioning = entries[i].map { TrainingRules.isConditioning($0) } ?? false
            let warm = warmed[i] == nil && !conditioning
            return PlannedExercise(exercise: ex, target: target, warmups: warm ? warmupSets(for: target) : [], warmedBy: warmed[i], groups: groups[i])
        }
    }

    /// A new session from a template: the planned sets carry their targets and nothing in weight or reps
    func newSession(_ t: WorkoutTemplate, plan: [PlannedExercise]) -> WorkoutSession {
        WorkoutSession(templateId: t.id, name: t.name, order: t.exercises, sets: plan.flatMap { TrainingRules.sets(for: $0) })
    }

    /// What the summary proposes for the next session of each exercise you did: the progression rules on this session
    /// as the latest one. `changes` is false when the next target would be the same anyway.
    func proposals(after s: WorkoutSession) -> [NextProposal] {
        var seen = Set<String>()
        return s.order.compactMap { ex -> NextProposal? in
            guard seen.insert(ex.exerciseId).inserted else { return nil }
            let done = TrainingRules.working(ex.exerciseId, in: s)
            guard let base = TrainingRules.carry(done, repHigh: ex.repHigh), let best = TrainingRules.bestE1rm(ex.exerciseId, in: s) else { return nil }
            let earlier = sessions().filter { TrainingRules.isEnded($0, today: Day.today) && $0.id != s.id && $0.start < s.start }.compactMap { TrainingRules.bestE1rm(ex.exerciseId, in: $0) }
            guard let p = TrainingRules.progression(ex, last: done, history: [best] + earlier) else { return nil }
            return NextProposal(exercise: ex, weight: p.weight, reps: ex.repHigh, reason: p.reason, changes: p.weight != base.weight)
        }
    }

    /// The working sets of an exercise in the last session that's over before this one (for «+2 kg», «igual»)
    func previousWorking(_ exerciseId: String, before s: WorkoutSession) -> [SetLog] {
        let earlier = sessions().first { TrainingRules.isEnded($0, today: Day.today) && $0.id != s.id && $0.start < s.start && !TrainingRules.working(exerciseId, in: $0).isEmpty }
        return earlier.map { TrainingRules.working(exerciseId, in: $0) } ?? []
    }

    /// Saves the target you accepted (or adjusted) for the next session of an exercise and returns what was there
    /// before, so Desfazer can put it back
    @discardableResult
    func acceptTarget(_ p: NextProposal, weight: Double? = nil, reps: Int? = nil, from session: WorkoutSession, at: Double = nowMs()) -> TrainingTarget? {
        let id = TrainingRules.targetId(p.exercise.exerciseId)
        let before = record(TrainingTarget.self, id)
        let adjusted = weight != nil || reps != nil
        save(TrainingTarget(id: id, exerciseId: p.exercise.exerciseId, weight: weight ?? p.weight, reps: reps ?? p.reps,
                            reason: adjusted ? "ajustado por ti" : p.reason, session: session.id, at: at))
        return before
    }

    /// Desfazer for acceptTarget: the earlier target back, or none
    func restoreTarget(_ exerciseId: String, to before: TrainingTarget?) {
        if let before { save(before) } else if let now = record(TrainingTarget.self, TrainingRules.targetId(exerciseId)) { remove(now) }
    }

    /// The exercises that can take this one's place: same main muscle group, strength, not in the session already;
    /// the ones you've done before first, then the ones with weights
    func alternatives(to ex: TemplateExercise, in s: WorkoutSession) -> [CatalogExercise] {
        guard let info = Catalog.shared.exercise(ex.exerciseId) else { return [] }
        let known = Set(sessions().filter { TrainingRules.isEnded($0, today: Day.today) }.flatMap { x in x.sets.filter { $0.done && $0.kind == .working }.map(\.exerciseId) })
        return TrainingRules.alternatives(to: info, from: Catalog.shared.exercises, excluding: Set(s.order.map(\.exerciseId)), known: known)
    }

    // MARK: Left open past 23:59 (phase 2.6)

    /// A session left open past 23:59 of its day passes to partial: it is marked as ended, at the last thing done in it,
    /// and as partial. Nothing else in it changes (its sets stay as they are). Idempotent: an ended session is never
    /// touched again. Returns how many it closed.
    /// Not called by the app (decision D23): nothing writes to a workout by itself; an expired one is partial when it
    /// is read. Kept, with its tests, for an explicit «Terminar» on such a session if a later phase adds one.
    @discardableResult
    func closeExpiredSessions(today: String = Day.today) -> Int {
        guard canChange else { return 0 }
        var closed = 0
        for var s in all(WorkoutSession.self) where TrainingRules.isExpired(s, today: today) {
            s.end = TrainingRules.lastActivity(s)
            s.partial = true
            save(s)
            closed += 1
        }
        return closed
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
        for s in sessions() where TrainingRules.isEnded(s, today: Day.today) {
            for g in groups(of: s) where out[g] == nil { out[g] = Day.between(s.date, Day.today) }
        }
        return out
    }

    enum Growth { case growing, underRested, underFed }

    /// For 48 hours after a session: is each trained muscle getting the protein and sleep to grow?
    func growthCheck() -> (session: WorkoutSession, status: [String: Growth], protein: (got: Double, need: Double), sleep: (got: Int, need: Int))? {
        guard let s = sessions().first(where: { TrainingRules.isEnded($0, today: Day.today) && Day.between($0.date, Day.today) <= 2 }) else { return nil }
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
