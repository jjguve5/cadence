// Runs the workout Live Activity and answers its lock-screen buttons.
import ActivityKit
import Foundation
import UserNotifications

@MainActor
final class LiveWorkout: ObservableObject {
    static let shared = LiveWorkout()
    private var activity: Activity<WorkoutAttributes>?
    private var sessionId: String?
    @Published private(set) var restEnd: Date?
    @Published private(set) var restTotal: Double = 120

    /// The next set to do: the first one not ticked
    private func current(_ s: WorkoutSession) -> (index: Int, ex: TemplateExercise)? {
        guard let i = s.sets.firstIndex(where: { !$0.done }) else { return nil }
        let ex = s.order.first { $0.exerciseId == s.sets[i].exerciseId } ?? TemplateExercise(exerciseId: s.sets[i].exerciseId, name: "Exercise")
        return (i, ex)
    }

    private func state(_ s: WorkoutSession) -> WorkoutAttributes.ContentState {
        guard let cur = current(s) else {
            return .init(exercise: "All sets done", setLabel: "", weight: 0, reps: 0, restEnd: nil, next: "Finish in the app", volume: Int(s.volume))
        }
        let (i, ex) = (cur.index, cur.ex)
        let sets = s.sets.filter { $0.exerciseId == ex.exerciseId && $0.kind != .warmup }
        let n = (sets.firstIndex { $0.id == s.sets[i].id } ?? 0) + 1
        let nextEx = s.order.drop { $0.exerciseId != ex.exerciseId }.dropFirst().first
        let nextSets = nextEx.map { e in s.sets.filter { $0.exerciseId == e.exerciseId && $0.kind != .warmup } }
        let nextText = nextEx.map { e in "\(e.name) \(nextSets?.count ?? e.sets) × \(e.repHigh)" + ((nextSets?.first?.weight).map { " · \(kg($0)) kg" } ?? "") } ?? "last exercise"
        let label = s.sets[i].kind == .warmup ? "warm-up" : "set \(n) of \(sets.count)"
        return .init(exercise: ex.name, setLabel: label, weight: s.sets[i].weight, reps: s.sets[i].reps, restEnd: restEnd, next: nextText, volume: Int(s.volume))
    }

    /// Starts or changes the rest countdown (nil skips it), then updates the lock screen
    func rest(_ end: Date?, total: Double? = nil, session: WorkoutSession) async {
        if let total { restTotal = total }
        setRest(end)
        await update(session: session)
    }

    func update(session: WorkoutSession) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, session.end == nil else { return }
        if sessionId != session.id { restEnd = nil }
        sessionId = session.id
        let content = ActivityContent(state: state(session), staleDate: nil)
        if let activity, activity.activityState == .active {
            await activity.update(content)
        } else {
            await PipNudge.shared.end() // the workout takes the island
            activity = try? Activity.request(attributes: WorkoutAttributes(sessionName: session.name, started: Date(timeIntervalSince1970: session.start / 1000), sessionId: session.id), content: content)
        }
    }

    func end() async {
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        sessionId = nil
    }

    func handle(_ action: WorkoutAction) async {
        let store = Store.shared
        guard let id = sessionId ?? store.activeSession?.id, var s = store.record(WorkoutSession.self, id) else { return }
        if let cur = current(s) {
            let (i, ex) = (cur.index, cur.ex)
            switch action {
            case .done:
                s.sets[i].done = true
                s.sets[i].at = nowMs()
                if s.sets[i].kind != .warmup { restTotal = Double(ex.rest); setRest(Date().addingTimeInterval(Double(ex.rest))) }
            case .weightUp: s.sets[i].weight += 2.5
            case .weightDown: s.sets[i].weight = max(0, s.sets[i].weight - 2.5)
            case .repUp: s.sets[i].reps += 1
            case .repDown: s.sets[i].reps = max(0, s.sets[i].reps - 1)
            case .restUp: setRest(restEnd?.addingTimeInterval(15))
            case .restDown: setRest(restEnd?.addingTimeInterval(-15))
            case .restSkip: setRest(nil)
            }
            store.save(s)
        }
        await update(session: s)
    }

    private func setRest(_ end: Date?) {
        restEnd = end
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        guard let end, end > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = "Rest done"
        c.body = "Next set when you're ready."
        c.sound = .default
        center.add(UNNotificationRequest(identifier: "rest", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)))
    }
}
