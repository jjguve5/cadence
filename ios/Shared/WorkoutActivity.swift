// The workout Live Activity, shared by the app and the widget extension. Its buttons are App Intents: they run in
// the app's process (LiveActivityIntent), which updates the session and the activity.
import ActivityKit
import AppIntents
import Foundation

struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setLabel: String // "set 3 of 4"
        var weight: Double
        var reps: Int
        var restEnd: Date?
        var next: String
        var volume: Int
    }
    var sessionName: String
    var started: Date
}

enum WorkoutAction: String, AppEnum {
    case done, weightUp, weightDown, repUp, repDown, restUp, restDown, restSkip
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Workout action"
    static var caseDisplayRepresentations: [WorkoutAction: DisplayRepresentation] = [
        .done: "Done", .weightUp: "+2.5 kg", .weightDown: "−2.5 kg", .repUp: "+1 rep", .repDown: "−1 rep",
        .restUp: "+15 s", .restDown: "−15 s", .restSkip: "Skip rest",
    ]
}

struct WorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Workout control"
    @Parameter(title: "Action") var action: WorkoutAction

    init() {}
    init(_ action: WorkoutAction) { self.action = action }

    func perform() async throws -> some IntentResult {
        #if CADENCE_APP
        await LiveWorkout.shared.handle(action)
        #endif
        return .result()
    }
}
