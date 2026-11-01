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
    /// A time of day on a given day, from minutes after midnight
    static func at(_ minute: Int, on key: String) -> Date {
        calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: date(key))) ?? Date()
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
    var label: String { self == .mustDo ? "Must-do" : "Routine" }
}

struct Schedule: Codable, Equatable {
    enum Rule: String, Codable, CaseIterable {
        case daily, everyNDays, weekdays
        var label: String { ["daily": "Every day", "everyNDays": "Every few days", "weekdays": "Chosen days"][rawValue]! }
    }
    var rule: Rule = .daily
    var every: Int = 2
    var start: String = Day.today
    var weekdays: [Int] = [2, 4, 6] // Calendar weekdays: 1 = Sunday
    var minute: Int = 9 * 60
    var weekendMinute: Int? // a different time on Saturday and Sunday
    var anchor: String? // wake, windDown, lightsOut: follows your day instead of a clock time
    var offset: Int? // minutes after (or before, negative) the anchor

    static let anchors = ["wake": "after waking", "windDown": "at wind-down", "lightsOut": "before lights out"]

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
        case .daily: return "daily"
        case .everyNDays: return every == 1 ? "daily" : "every \(every) days"
        case .weekdays:
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
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

struct PromiseLog: Codable, Identifiable, Equatable {
    var promiseId: String
    var date: String
    var status: LogStatus
    var at: Double = nowMs()
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
    var areasOff: [String] = [] // areas switched off: fuel, training, care, money, wardrobe, kitchen, home, people, travel, learning

    init() {}

    func on(_ area: String) -> Bool { !areasOff.contains(area) }

    // Every field optional on the way in, so adding a field never loses saved data
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        name = v(.name, d.name); wakeMinute = v(.wakeMinute, d.wakeMinute); sleepNeed = v(.sleepNeed, d.sleepNeed)
        windDownLead = v(.windDownLead, d.windDownLead); stepGoal = v(.stepGoal, d.stepGoal); readinessOffset = v(.readinessOffset, d.readinessOffset)
        quietStart = v(.quietStart, d.quietStart); quietEnd = v(.quietEnd, d.quietEnd); notificationBudget = v(.notificationBudget, d.notificationBudget)
        goal = v(.goal, d.goal); weightKg = v(.weightKg, d.weightKg); heightCm = v(.heightCm, d.heightCm); age = v(.age, d.age); male = v(.male, d.male)
        kcalTarget = (try? c.decodeIfPresent(Double.self, forKey: .kcalTarget)) ?? nil
        proteinPerKg = v(.proteinPerKg, d.proteinPerKg); waterGoalMl = v(.waterGoalMl, d.waterGoalMl)
        barKg = v(.barKg, d.barKg); plates = v(.plates, d.plates); areasOff = v(.areasOff, d.areasOff)
    }

    /// Mifflin-St Jeor, times a light activity factor; the weekly check-in replaces it with what your weight shows
    var estimatedKcal: Double {
        let bmr = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (male ? 5 : -161)
        let tdee = bmr * 1.5
        return (goal == "lose" ? tdee - 400 : goal == "gain" ? tdee + 250 : tdee).rounded()
    }
    var kcal: Double { kcalTarget ?? estimatedKcal }
    var proteinTarget: Double { (weightKg * proteinPerKg).rounded() }
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

    var startDate: Date { ISO8601DateFormatter().date(from: start) ?? Date() }
    var endDate: Date { ISO8601DateFormatter().date(from: end) ?? Date() }

    struct Segment: Identifiable { let id: Int; let stage: String; let from: Int; let to: Int }
    var segments: [Segment] {
        (timeline ?? []).enumerated().compactMap { i, row in
            guard row.count == 3, case .string(let s) = row[0], case .number(let a) = row[1], case .number(let b) = row[2] else { return nil }
            return Segment(id: i, stage: s, from: Int(a), to: Int(b))
        }
    }
}

struct Nap: Codable, Equatable { var start: String; var end: String; var asleep: Int }

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
