// UI-test scenarios for Hoje (2.4). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "today.<case>" and act only on those.
// Each one starts from the normal history TestSeed builds (28 days, a normal night today) and changes one thing.
import Foundation

@MainActor
enum TodaySeeds {
    static func apply(_ store: Store, scenario: String) {
        let today = Day.today
        let now = TestMode.minute ?? Day.minuteOfDay()
        let iso = ISO8601DateFormatter()
        if scenario.hasPrefix("today.") { UndoCenter.shared.seconds = 20 } // UI tests only; the app's 5 s is pinned by StateViewsTests
        switch scenario {
        case "today.urgent":
            // An event with a place in 40 min and no regular trip to it: leave 30 min before, so in 10 min
            Agenda.shared.seed([CalendarEvent(id: "today-urgent-1", title: "Dentista", start: iso.string(from: Day.at(now + 40, on: today)),
                                              end: iso.string(from: Day.at(now + 100, on: today)), allDay: false, location: "Clínica Dentária")])
        case "today.nodata":
            // The band hasn't synced since last night: nothing for today
            store.loadTestHealth([HealthDay(date: today)], device: Device(name: "Fitbit Air", battery: 80, batteryStatus: "High", lastSync: iso.string(from: Date().addingTimeInterval(-11 * 3600))))
        case "today.workout":
            // A workout started 20 min ago and not finished
            store.save(WorkoutSession(id: "today-workout-1", name: "Pernas", start: nowMs() - 20 * 60_000, order: []))
        case "today.waterfirst":
            // Water logged more than food in the last days: it comes first in «Registar»
            for d in 1...3 {
                for i in 0..<3 { store.save(WaterEntry(id: "today-water-\(d)-\(i)", date: Day.add(-d, to: today), minute: 9 * 60 + i * 90, ml: 250)) }
            }
            store.save(FoodEntry(id: "today-food-1", date: Day.add(-1, to: today), minute: 13 * 60, name: "Sopa", kcal: 120, protein: 4))
        default:
            break
        }
    }
}
