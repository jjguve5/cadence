// UI-test scenarios for Noite, Antes de sair e Antes de dormir (2.9). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "night.<case>" and act only on those.
//   night.leave — a regular trip leaving 40 min after the test's minute and one item of yours: Antes de sair is the step
//   night.prep  — tonight's brushing done; tomorrow a training day, two clean pieces, training clothes clean and drying
//   night.late  — the same evening, for a test minute past lights out + 30 (the short version)
//   night.skipped — the same evening, with the night's brushing answered «Não fiz»
import Foundation

@MainActor
enum NightSeeds {
    static func apply(_ store: Store, scenario: String) {
        guard scenario.hasPrefix("night.") else { return }
        // Desfazer keeps its normal 5 s here: the UI tests wait for the bar to go before tapping what it may cover
        let today = Day.today
        let now = TestMode.minute ?? Day.minuteOfDay()
        // The evening's plan, whatever the history: wake 7:15, 7h 45m asleep, wind-down 30 min before lights out, so
        // lights out at about 23:15, the night from about 21:45 and the short version after about 23:45
        store.update { $0.wakeMinute = 7 * 60 + 15; $0.sleepNeed = 465; $0.windDownLead = 30 }
        switch scenario {
        case "night.leave":
            let leave = now + 40
            store.save(RegularTrip(id: "night-trip", title: "Faculdade", destination: "Rua do Instituto, 5", weekdays: [Day.weekday(today)], arrive: leave + 35, travel: 25, buffer: 10))
            store.save(LeaveItem(id: "mine-night-pass", title: "Passe", at: 1))
        case "night.prep", "night.late", "night.skipped":
            if scenario == "night.skipped" {
                store.save(PromiseItem(id: "night-brush", title: "Brush teeth, night", schedule: Schedule(rule: .daily, start: "2026-01-01", minute: 22 * 60)))
                for p in store.nightBrushHabits(on: today) { store.log(p, on: today, .skipped) }
            } else {
                for p in store.nightBrushHabits(on: today) { store.log(p, on: today, .done) }
            }
            store.save(Garment(id: "night-top", name: "T-shirt cinzenta", type: "top", colors: ["9AA3B2"]))
            store.save(Garment(id: "night-bottom", name: "Calças de ganga", type: "bottom", colors: ["3E5C8A"]))
            store.save(Garment(id: "night-shorts", name: "Calções de treino", type: "gym", washGroup: "gym 30°", wearsBeforeWash: 1))
            store.save(Garment(id: "night-gymtee", name: "T-shirt de treino cinzenta", type: "gym", washGroup: "gym 30°", wearsBeforeWash: 1, wears: 1, state: "drying"))
            store.save(WorkoutTemplate(id: "night-tpl", name: "Tronco", exercises: [], weekdays: [Day.weekday(Day.add(1, to: today))], minutes: 60))
        default:
            break
        }
    }
}
