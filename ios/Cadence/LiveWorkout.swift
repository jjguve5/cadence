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
    @Published private(set) var restReason: String? // why this rest lasts what it does (phase 2.6)

    /// The next set to do: the first one not registered, in the order of the exercises, skipped ones left out
    private func current(_ s: WorkoutSession) -> (index: Int, ex: TemplateExercise)? {
        guard let c = s.currentSet() else { return nil }
        return (c.index, c.exercise)
    }

    private func state(_ s: WorkoutSession) -> WorkoutAttributes.ContentState {
        guard let cur = current(s) else {
            return .init(exercise: "Todas as séries feitas", setLabel: "", weight: 0, reps: 0, restEnd: nil, next: "Termina na app", volume: Int(s.volume))
        }
        let (i, ex) = (cur.index, cur.ex)
        let sets = s.sets.filter { $0.exerciseId == ex.exerciseId && $0.kind != .warmup }
        let n = (sets.firstIndex { $0.id == s.sets[i].id } ?? 0) + 1
        let nextEx = s.next(after: ex.exerciseId)
        let nextSets = nextEx.map { e in s.sets.filter { $0.exerciseId == e.exerciseId && $0.kind != .warmup } }
        // The next exercise's weight is its target (or what you set on it), never a made-up 0
        let nextWeight: Double? = nextSets?.first.flatMap { x in x.done || x.reps > 0 ? Optional(x.weight) : x.targetWeight }
        let nextText = nextEx.map { e in "\(e.name) \(nextSets?.count ?? e.sets) × \(e.repHigh)" + (nextWeight.map { " · \(kg($0)) kg" } ?? "") } ?? "último exercício"
        let label = s.isPaused ? "em pausa" : s.sets[i].kind == .warmup ? "aquecimento" : "série \(n) de \(sets.count)"
        // What the lock screen shows is what «Feito» registers: the steppers' values, which start from the target
        let values = s.startingValues(at: i, repHigh: ex.repHigh)
        return .init(exercise: ex.name, setLabel: label, weight: values.weight, reps: values.reps, restEnd: restEnd, next: nextText, volume: Int(s.volume))
    }

    /// Starts or changes the rest countdown (nil skips it), then updates the lock screen. `reason` says why it lasts
    /// what it does; changing the length without one keeps the reason there was.
    func rest(_ end: Date?, total: Double? = nil, reason: String? = nil, session: WorkoutSession) async {
        if let total { restTotal = total }
        if let reason { restReason = reason }
        if end == nil { restReason = nil }
        setRest(end)
        await update(session: session)
    }

    func update(session: WorkoutSession) async {
        if TestMode.active { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled, session.end == nil, !TrainingRules.isExpired(session, today: Day.today) else { return }
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
        // While the data isn't safe, the lock screen must not show a set as done that was never saved
        guard store.canChange else { return }
        guard let id = sessionId ?? store.activeSession?.id, var s = store.record(WorkoutSession.self, id) else { return }
        // A session that ended, or was left open past 23:59 (partial now), takes nothing more from the lock screen
        if s.end != nil || TrainingRules.isExpired(s, today: Day.today) {
            store.closeExpiredSessions()
            setRest(nil)
            await end()
            return
        }
        if let cur = current(s) {
            let (i, ex) = (cur.index, cur.ex)
            let values = s.startingValues(at: i, repHigh: ex.repHigh)
            var changed = true
            var rest: Date?? = .none // .some(nil) clears the rest timer
            var restSeconds = 0
            var restWhy: String?
            switch action {
            case .done:
                // «Feito» registers what the lock screen shows; the target stays apart
                s.register(i, weight: values.weight, reps: values.reps, rir: nil)
                if s.sets[i].kind != .warmup && s.hasSetsLeft {
                    let mechanic = Catalog.shared.exercise(ex.exerciseId).map { TrainingRules.mechanic($0) }
                    let r = TrainingRules.rest(mechanic, reps: values.reps, templateRest: ex.rest)
                    if r.seconds > 0 {
                        rest = .some(Date().addingTimeInterval(Double(r.seconds)))
                        restSeconds = r.seconds
                        restWhy = r.reason
                    }
                }
            // The steppers: both values are written, so the set keeps what you set from here on
            case .weightUp: s.sets[i].weight = values.weight + 2.5; s.sets[i].reps = max(1, values.reps)
            case .weightDown: s.sets[i].weight = max(0, values.weight - 2.5); s.sets[i].reps = max(1, values.reps)
            case .repUp: s.sets[i].weight = values.weight; s.sets[i].reps = values.reps + 1
            case .repDown: s.sets[i].weight = values.weight; s.sets[i].reps = max(1, values.reps - 1)
            case .restUp: changed = false; rest = .some(restEnd?.addingTimeInterval(15))
            case .restDown: changed = false; rest = .some(restEnd?.addingTimeInterval(-15))
            case .restSkip: changed = false; rest = .some(nil)
            }
            // A set shows as done on the lock screen, and its rest starts, only once it's really saved. If saving fails,
            // the activity keeps its previous state and the app opens on what happened.
            if changed {
                store.save(s)
                guard store.commit() else { return }
            }
            if case .some(let end) = rest {
                if action == .done {
                    restTotal = Double(restSeconds)
                    restReason = restWhy
                }
                if end == nil { restReason = nil }
                setRest(end)
            }
        }
        await update(session: s)
    }

    private func setRest(_ end: Date?) {
        restEnd = end
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        guard let end, end > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = "Descanso terminado"
        c.body = "Próxima série quando quiseres."
        c.sound = .default
        center.add(UNNotificationRequest(identifier: "rest", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)))
    }
}
