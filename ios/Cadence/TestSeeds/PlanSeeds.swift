// UI-test scenarios for Plano (2.8). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "plan.<case>" and act only on those.
import Foundation

@MainActor
enum PlanSeeds {
    static func apply(_ store: Store, scenario: String) {
        guard scenario.hasPrefix("plan.") else { return }
        // Each Plano test starts as a fresh install would, in Dia (the view choice is the test mode's own key)
        UserDefaults.standard.removeObject(forKey: PlanMode.key)
        let today = Day.today
        let iso = ISO8601DateFormatter()
        switch scenario {
        case "plan.conflict":
            // A training you placed today at 18:30 (75 min) and a dinner in the Google calendar at 19:00: 45 min overlap.
            // From 12:00 (the test's minute) the nearest free time is 17:30, 15 min clear of the dinner.
            store.save(PlanBlock(id: "plan-train", date: today, start: 18 * 60 + 30, minutes: 75, title: "Treino de teste", type: "training"))
            Agenda.shared.seed([CalendarEvent(id: "plan-dinner", title: "Jantar de anos", start: iso.string(from: Day.at(19 * 60, on: today)),
                                              end: iso.string(from: Day.at(22 * 60, on: today)), allDay: false, calendar: "Pessoal")])
        case "plan.review":
            // A habit due today with no answer yet
            store.save(PromiseItem(id: "plan-review-shake", title: "Batido de proteína", schedule: Schedule(rule: .daily, start: Day.add(-30, to: today), minute: 17 * 60)))
        case "plan.month", "plan.new":
            // The calendar was read and has nothing: «sem eventos», not «sem dados»
            Agenda.shared.seed([])
        default:
            break
        }
    }
}
