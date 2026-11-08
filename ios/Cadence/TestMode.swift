// UI-testing mode. When launched with CADENCE_UITEST=<scenario> (only the UI test runner does this), the app uses its
// own data file in a temporary folder, makes no network calls, asks for no permissions, and loads a known scenario.
// Real data in Documents/cadence.json is never opened in this mode.
import Foundation

enum TestMode {
    private static let env = ProcessInfo.processInfo.environment
    static let scenario: String? = env["CADENCE_UITEST"]
    static var active: Bool { scenario != nil }
    /// A fixed time of day for rules that depend on it (minutes after midnight)
    static let minute: Int? = env["CADENCE_UITEST_MINUTE"].flatMap(Int.init)
    static let reset = env["CADENCE_UITEST_RESET"] == "1"
    /// Areas the scenario starts with switched off (comma-separated, e.g. "care"), as if turned off in You
    static let areasOff: [String] = env["CADENCE_UITEST_AREAS_OFF"].map { $0.split(separator: ",").map(String.init) } ?? []
    static let storeFile = FileManager.default.temporaryDirectory.appendingPathComponent("cadence-uitest.json")
}

/// The time of day the rules see: the real clock, or the test's fixed minute
enum Clock {
    static func minute() -> Int { TestMode.minute ?? Day.minuteOfDay() }
}

/// Deterministic data for each scenario: 28 days of history, then today's situation
@MainActor
enum TestSeed {
    static func apply(_ store: Store, scenario: String) {
        let today = Day.today
        let iso = ISO8601DateFormatter()
        if !TestMode.areasOff.isEmpty { store.update { $0.areasOff = TestMode.areasOff } }
        // A first day: set up, but no band data and nothing learned yet
        if scenario == "empty" { store.update { $0.setupDone = true }; return }
        func night(_ day: String, minutes: Int) -> SleepRecord {
            let end = Day.at(7 * 60 + 15, on: day)
            let start = end.addingTimeInterval(-Double(minutes + 20) * 60)
            return SleepRecord(start: iso.string(from: start), end: iso.string(from: end), offset: 0, asleep: minutes, awake: 20, inBed: minutes + 20, toFallAsleep: 10,
                               stages: ["deep": minutes / 6, "rem": minutes / 5, "light": minutes / 2, "awake": 20], timeline: nil)
        }
        var days: [HealthDay] = []
        for i in 1...28 {
            let d = Day.add(-i, to: today)
            if scenario == "stale" && i <= 2 { continue }
            days.append(HealthDay(date: d, sleep: night(d, minutes: 455 + (i % 5) * 6), steps: Double(8000 + (i * 37) % 2000), azm: 30, calories: 2600,
                                  rhr: Double(55 + i % 3 - 1), hrv: Double(60 + i % 7 - 3), spo2: 97, breathing: 14.5, temp: 0.1))
        }
        var lastSync = Date().addingTimeInterval(-30 * 60)
        switch scenario {
        case "poorSleep":
            days.append(HealthDay(date: today, sleep: night(today, minutes: 300), steps: 1200, rhr: 56, hrv: 57))
        case "lowReadiness":
            days.append(HealthDay(date: today, sleep: night(today, minutes: 440), steps: 900, rhr: 63, hrv: 40))
        case "missingToday":
            lastSync = Date().addingTimeInterval(-10 * 3600)
        case "stale":
            lastSync = Date().addingTimeInterval(-74 * 3600)
        default:
            days.append(HealthDay(date: today, sleep: night(today, minutes: 470), steps: 2400, rhr: 55, hrv: 61))
        }
        store.loadTestHealth(days, device: Device(name: "Fitbit Air", battery: 80, batteryStatus: "High", lastSync: iso.string(from: lastSync)))
        store.update { $0.setupDone = true; $0.sleepNeed = 465 }
        // A session planned for today where the scenario is about training
        if ["poorSleep", "lowReadiness", "normal", "minimumDay"].contains(scenario) {
            store.save(WorkoutTemplate(name: "Test session", exercises: [TemplateExercise(exerciseId: "squat", name: "Barbell Back Squat", sets: 2, repLow: 5, repHigh: 8, rest: 60)], weekdays: [Day.weekday(today)], minutes: 30))
        }
        if scenario == "poorSleep" {
            store.save(PlanBlock(date: today, start: 10 * 60, minutes: 90, title: "Deep work · Thesis", type: "deep"))
        }
        if scenario == "workload" {
            Agenda.shared.seed([CalendarEvent(id: "t1", title: "Workshop", start: iso.string(from: Day.at(9 * 60, on: today)), end: iso.string(from: Day.at(17 * 60, on: today)), allDay: false)])
        }
        if scenario == "minimumDay" { store.setMinimumDay(true, reasons: ["Test"]) }
        if scenario == "calibration" {
            for i in 1...14 {
                let d = Day.add(-i, to: today)
                let energy = 1 + i % 5
                store.save(Prediction(id: "energy|\(d)", kind: "energy", date: d, predicted: Double(energy) + 0.2, basis: "test"))
                var entry = store.day(d)
                entry.energy = energy
                entry.closedAt = nowMs()
                entry.score = 60
                store.save(entry)
            }
        }
    }
}
