// What Cadence keeps. Synced records (promises, logs, days, profile) go to the server as JSON; health days come
// from the server's health.php and are only cached here.
import Foundation

// MARK: - Days

enum Day {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2 // weeks start on Monday
        return c
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date = Date()) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date { formatter.date(from: key) ?? Date() }
    static var today: String { key() }
    static func add(_ days: Int, to key: String) -> String { Day.key(calendar.date(byAdding: .day, value: days, to: date(key)) ?? date(key)) }
    static func between(_ a: String, _ b: String) -> Int { calendar.dateComponents([.day], from: date(a), to: date(b)).day ?? 0 }
    static func weekday(_ key: String) -> Int { calendar.component(.weekday, from: date(key)) } // 1 = Sunday
    static func weekStart(_ key: String) -> String {
        let wd = weekday(key)
        return add(-((wd + 5) % 7), to: key) // back to Monday
    }
    /// A time of day on a given day, from minutes after midnight (past 1440 is the next day, negative the day before).
    /// Wall-clock time, so 8:00 stays 8:00 on the days the clocks change.
    static func at(_ minute: Int, on key: String) -> Date { at(minute, on: key, in: calendar) }

    static func at(_ minute: Int, on key: String, in cal: Calendar) -> Date {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let noon = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) else { return Date() }
        let days = Int((Double(minute) / 1440).rounded(.down)), m = minute - days * 1440
        let day = cal.date(byAdding: .day, value: days, to: noon) ?? noon
        return cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day) ?? day
    }
    static func minuteOfDay(_ date: Date = Date()) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

func clock(_ minute: Int) -> String {
    let m = ((minute % 1440) + 1440) % 1440
    return String(format: "%d:%02d", m / 60, m % 60)
}

func duration(_ minutes: Int) -> String {
    let m = abs(minutes)
    if m < 60 { return "\(m)m" }
    return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
}

func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

// MARK: - Promises

enum PromiseKind: String, Codable, CaseIterable {
    case mustDo, routine
    var label: String { self == .mustDo ? "Essencial" : "Rotina" }
}

struct Schedule: Codable, Equatable {
    enum Rule: String, Codable, CaseIterable {
        case daily, everyNDays, weekdays
        var label: String { ["daily": "Todos os dias", "everyNDays": "A cada poucos dias", "weekdays": "Dias escolhidos"][rawValue]! }
    }
    var rule: Rule = .daily
    var every: Int = 2
    var start: String = Day.today
    var weekdays: [Int] = [2, 4, 6] // Calendar weekdays: 1 = Sunday
    var minute: Int = 9 * 60
    var weekendMinute: Int? // a different time on Saturday and Sunday
    var anchor: String? // wake, windDown, lightsOut: follows your day instead of a clock time
    var offset: Int? // minutes after (or before, negative) the anchor

    static let anchors = ["wake": "depois de acordar", "windDown": "ao desacelerar", "lightsOut": "antes de apagar as luzes"]

    func isDue(on day: String) -> Bool {
        switch rule {
        case .daily: return true
        case .everyNDays:
            let d = Day.between(start, day)
            return d >= 0 && d % max(1, every) == 0
        case .weekdays: return weekdays.contains(Day.weekday(day))
        }
    }

    var summary: String {
        switch rule {
        case .daily: return "diariamente"
        case .everyNDays: return every == 1 ? "diariamente" : "a cada \(every) dias"
        case .weekdays:
            let names = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
            return weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { names[$0 - 1] }.joined(separator: " ")
        }
    }

    /// How many times it's due Monday to Sunday of the week holding `day`
    func dueInWeek(of day: String) -> Int {
        let start = Day.weekStart(day)
        return (0..<7).filter { isDue(on: Day.add($0, to: start)) }.count
    }
}

struct PromiseItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var icon: String = "checkmark.circle"
    var kind: PromiseKind = .routine
    var schedule = Schedule()
    var active = true
    var tiny: String? // the minimum version, offered before skipping
    var kcal: Double?
    var protein: Double?
    var created: Double = nowMs()

    var timeLabel: String { clock(schedule.minute) }
}

enum LogStatus: String, Codable { case done, skipped, tiny }

/// Where a day's answer to a habit came from (see PromiseLog.source)
enum AnswerOrigin: Equatable {
    case you
    case imported(String)
    case unknown
}

struct PromiseLog: Codable, Identifiable, Equatable {
    var promiseId: String
    var date: String
    var status: LogStatus
    var at: Double = nowMs()
    /// Where the answer came from: "you" when you gave it (a tap, a notification, Pip, the brushing or reading timer);
    /// the data source when it was imported ("fitbit", "apple"). nil means unknown: answers saved before phase 2.2,
    /// and any that went through an older build, which ignores this field and drops it when it saves. A missing source
    /// is never taken as yours (the absence of a label proves no confirmation).
    var source: String? = nil
    /// «Não se aplica» in the end-of-day review (phase 2.8): saved as status skipped with this set to true, so an older
    /// build, which doesn't know the field, reads it as skipped (and drops the field if it saves the log again). nil is a
    /// plain skip («Não fiz»). «Não confirmado» is no log at all. LogStatus gets no new value: an older build would
    /// protect the whole file on meeting one.
    var notApplicable: Bool? = nil
    static let byYou = "you"
    var id: String { "\(promiseId)|\(date)" }
}

// MARK: - Days you close

struct DayEntry: Codable, Equatable {
    var date: String
    var rating: Int?
    var note = ""
    var top3: [String] = []
    var top3Done: [Bool] = []
    var closedAt: Double?
    var score: Int?
    var points: Int?
    var energy: Int? // 1–5, how much energy the day had: the outcome readiness is checked against
}

// MARK: - Profile (synced) and this phone's connection (not synced)

struct Profile: Codable, Equatable {
    var name = ""
    var wakeMinute = 7 * 60 + 15
    var sleepNeed = 7 * 60 + 45 // minutes asleep a night
    var windDownLead = 30 // minutes before bedtime
    var stepGoal = 8000
    var readinessOffset = 0.0 // learned from "feels wrong"
    var quietStart = 23 * 60 + 30
    var quietEnd = 7 * 60
    var notificationBudget = 12
    // Fuel
    var goal = "maintain" // lose, maintain, gain
    var weightKg = 76.0
    var heightCm = 178.0
    var age = 25
    var male = true
    var kcalTarget: Double? // set by the weekly check-in; nil = estimate
    var proteinPerKg = 1.8
    var waterGoalMl = 3000.0
    // Training
    var barKg = 20.0
    var plates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    var fatTarget: Double?
    var carbTarget: Double?
    var setupDone = false
    var setup: SetupInputs? // the smart setup answers, so a goal change recalculates everything
    var healthSource = "fitbit" // fitbit: the Air through the server, plus weight and water from Apple Health; apple: Apple Health only
    var areasOff: [String] = [] // areas switched off: fuel, training, care, money, wardrobe, kitchen, home, people, travel, learning

    init() {}

    func on(_ area: String) -> Bool { !areasOff.contains(area) }

    // A field an older file doesn't have yet takes its default; a field that is there must read, or the whole profile
    // fails to read and the app protects the file, instead of quietly putting a default in place of what was saved
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()
        name = try c.value(.name, or: d.name); wakeMinute = try c.value(.wakeMinute, or: d.wakeMinute); sleepNeed = try c.value(.sleepNeed, or: d.sleepNeed)
        windDownLead = try c.value(.windDownLead, or: d.windDownLead); stepGoal = try c.value(.stepGoal, or: d.stepGoal)
        readinessOffset = try c.value(.readinessOffset, or: d.readinessOffset)
        quietStart = try c.value(.quietStart, or: d.quietStart); quietEnd = try c.value(.quietEnd, or: d.quietEnd)
        notificationBudget = try c.value(.notificationBudget, or: d.notificationBudget)
        goal = try c.value(.goal, or: d.goal); weightKg = try c.value(.weightKg, or: d.weightKg); heightCm = try c.value(.heightCm, or: d.heightCm)
        age = try c.value(.age, or: d.age); male = try c.value(.male, or: d.male)
        kcalTarget = try c.optional(.kcalTarget)
        proteinPerKg = try c.value(.proteinPerKg, or: d.proteinPerKg); waterGoalMl = try c.value(.waterGoalMl, or: d.waterGoalMl)
        barKg = try c.value(.barKg, or: d.barKg); plates = try c.value(.plates, or: d.plates); areasOff = try c.value(.areasOff, or: d.areasOff)
        fatTarget = try c.optional(.fatTarget)
        carbTarget = try c.optional(.carbTarget)
        setupDone = try c.value(.setupDone, or: d.setupDone); healthSource = try c.value(.healthSource, or: d.healthSource)
        setup = try c.optional(.setup)
    }

    /// Mifflin-St Jeor, times a light activity factor; the weekly check-in replaces it with what your weight shows
    var estimatedKcal: Double {
        let bmr = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (male ? 5 : -161)
        let tdee = bmr * 1.5
        return (goal == "lose" ? tdee - 400 : goal == "gain" ? tdee + 250 : tdee).rounded()
    }
    var kcal: Double { kcalTarget ?? estimatedKcal }
    var proteinTarget: Double { (weightKg * proteinPerKg).rounded() }
    var usesBand: Bool { healthSource != "apple" }
}

struct OpenSession: Identifiable, Equatable { var id: String }

struct Connection: Codable, Equatable {
    var server = ""
    var token = ""
    var configured: Bool { !server.isEmpty && !token.isEmpty }
}

struct ReadinessFeedback: Codable, Equatable {
    var date: String
    var score: Int
    var felt: Int // -1 worse than shown, +1 better
}

// MARK: - Health (from the server)

struct SleepRecord: Codable, Equatable {
    var start: String
    var end: String
    var offset: Int?
    var asleep: Int
    var awake: Int?
    var inBed: Int?
    var toFallAsleep: Int?
    var stages: [String: Int]?
    var timeline: [[JSONValue]]?

    private static let iso = ISO8601DateFormatter()
    var startDate: Date { Self.iso.date(from: start) ?? Date() }
    var endDate: Date { Self.iso.date(from: end) ?? Date() }

    struct Segment: Identifiable { let id: Int; let stage: String; let from: Int; let to: Int }
    var segments: [Segment] {
        (timeline ?? []).enumerated().compactMap { i, row in
            guard row.count == 3, case .string(let s) = row[0], case .number(let a) = row[1], case .number(let b) = row[2] else { return nil }
            return Segment(id: i, stage: s, from: Int(a), to: Int(b))
        }
    }
}

struct Nap: Codable, Equatable { var start: String; var end: String; var asleep: Int }

extension HealthDay {
    /// A sleep this short that starts in the daytime is a nap, whatever mark it came with (decision D39)
    static func isDaytimeNap(start: String, asleep: Int) -> Bool {
        guard asleep < 180, let date = ISO8601DateFormatter().date(from: start) else { return false }
        return (9 * 60..<20 * 60).contains(Day.minuteOfDay(date))
    }

    /// The day's sleep is its main one, and the rest stay naps; they are never added up. The server goes by the «main
    /// sleep» mark from Google, which can land on a nap: a one-hour nap then read as the whole night. So the longest sleep
    /// that isn't a daytime nap is the night, and a day with only a daytime nap has no night («Sem dados», not «1 h»). Worked
    /// out each time the days arrive from the server; a day that needs no change is returned as it came, stages included.
    func mainSleepFirst() -> HealthDay {
        let others = naps ?? []
        let mainIsNap = sleep.map { HealthDay.isDaytimeNap(start: $0.start, asleep: $0.asleep) } ?? false
        let current = mainIsNap ? nil : sleep
        let longer = others.filter { !HealthDay.isDaytimeNap(start: $0.start, asleep: $0.asleep) && $0.asleep > (current?.asleep ?? 0) }
            .max { $0.asleep < $1.asleep }
        guard mainIsNap || longer != nil else { return self }
        var day = self
        var rest = others
        if let longer {
            rest.removeAll { $0 == longer }
            day.sleep = SleepRecord(start: longer.start, end: longer.end, offset: sleep?.offset, asleep: longer.asleep)
        } else {
            day.sleep = nil
        }
        if let old = sleep { rest.append(Nap(start: old.start, end: old.end, asleep: old.asleep)) }
        day.naps = rest.isEmpty ? nil : rest.sorted { $0.start < $1.start }
        return day
    }
}

struct HealthDay: Codable, Equatable, Identifiable {
    var date: String
    var sleep: SleepRecord?
    var naps: [Nap]?
    var steps: Double?
    var azm: Double?
    var calories: Double?
    var rhr: Double?
    var hrv: Double?
    var spo2: Double?
    var breathing: Double?
    var temp: Double?
    var vo2: Double?
    var id: String { date }
}

struct Device: Codable, Equatable {
    var name: String?
    var battery: Int?
    var batteryStatus: String?
    var lastSync: String?
}

struct HealthReply: Codable {
    var device: Device?
    var days: [HealthDay]
    var errors: [String: String]?
}

// MARK: - Any JSON, for sync records

extension KeyedDecodingContainer {
    /// A field missing from an older file takes its default. A field that is there must read: a wrong value or a wrong
    /// type throws instead of being quietly replaced, so the caller can protect what was saved.
    func value<T: Decodable>(_ key: Key, or fallback: @autoclosure () -> T) throws -> T {
        guard contains(key) else { return fallback() }
        return try decode(T.self, forKey: key)
    }

    /// An optional field: missing or null is nil; anything else must read
    func optional<T: Decodable>(_ key: Key) throws -> T? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decode(T.self, forKey: key)
    }

    /// A list that older servers may have sent back as an empty object ({} for an empty []); a non-empty object is an error
    func list<E: Decodable>(_ key: Key) throws -> [E] {
        guard contains(key) else { return [] }
        if let empty = try? decode([String: JSONValue].self, forKey: key), empty.isEmpty { return [] }
        return try decode([E].self, forKey: key)
    }

    /// A dictionary that older servers may have sent back as an empty list ([] is how PHP writes an empty object)
    func dictionary<V: Decodable>(_ key: Key, or fallback: [String: V] = [:]) throws -> [String: V] {
        guard contains(key) else { return fallback }
        if let empty = try? decode([JSONValue].self, forKey: key), empty.isEmpty { return [:] }
        return try decode([String: V].self, forKey: key)
    }
}

enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    static func from<T: Encodable>(_ value: T) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
