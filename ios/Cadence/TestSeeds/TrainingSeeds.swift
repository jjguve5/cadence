// UI-test scenarios for Treino (2.6). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "training.<case>" and act only on those.
import Foundation

@MainActor
enum TrainingSeeds {
    /// The template every scenario has: two exercises, so a summary can have one done and one left to do
    static let templateName = "Pernas teste"

    static func apply(_ store: Store, scenario: String) {
        guard scenario.hasPrefix("training.") else { return }
        let today = Day.today
        let legs = [
            TemplateExercise(exerciseId: "leg-extension", name: "Leg Extensions", sets: 2, repLow: 8, repHigh: 12, rest: 60),
            TemplateExercise(exerciseId: "leg-curl", name: "Hamstring Curl", sets: 1, repLow: 10, repHigh: 15, rest: 60),
        ]
        store.save(WorkoutTemplate(id: "T-legs", name: templateName, exercises: legs, weekdays: [Day.weekday(today)], minutes: 30))
        switch scenario {
        case "training.history":
            // A week ago both sets of Leg Extensions reached the top of the range (20 kg × 12): today's target is
            // 20 kg × 12, and the summary proposes +2.5 kg. Hamstring Curl has no history («escolhes tu»).
            let day = Day.add(-7, to: today)
            let start = Day.at(18 * 60, on: day).timeIntervalSince1970 * 1000
            store.save(WorkoutSession(id: "S-last", date: day, templateId: "T-legs", name: templateName, start: start, end: start + 3_600_000, order: legs, sets: [
                SetLog(exerciseId: "leg-extension", weight: 20, reps: 12, done: true, at: start + 600_000),
                SetLog(exerciseId: "leg-extension", weight: 20, reps: 12, done: true, at: start + 900_000),
            ]))
        case "training.leftopen":
            // Yesterday's session was never finished: it is partial now, not in progress
            let day = Day.add(-1, to: today)
            let start = Day.at(18 * 60, on: day).timeIntervalSince1970 * 1000
            store.save(WorkoutSession(id: "S-open", date: day, templateId: "T-legs", name: templateName, start: start, order: legs, sets: [
                SetLog(exerciseId: "leg-extension", weight: 20, reps: 12, done: true, at: start + 600_000),
                SetLog(exerciseId: "leg-extension", weight: 0, reps: 0, targetWeight: 20, targetReps: 12),
            ]))
        default:
            break // "training.nohistory": the template alone
        }
    }
}
