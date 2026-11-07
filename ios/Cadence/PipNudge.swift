// Pip on the Dynamic Island: when something is slipping (a must-do past its time, a routine an hour late, water
// well behind, protein short in the evening, wind-down started), Pip shows it with Done and Later. Updated whenever
// the app runs, including its background refreshes, and never during quiet hours or a workout.
import ActivityKit
import Foundation

@MainActor
final class PipNudge {
    static let shared = PipNudge()
    private var activity: Activity<PipAttributes>?
    private var snoozed: [String: Date] = [:]

    struct Nudge { var message: String; var short: String; var promiseId: String?; var icon: String; var startURL: String? = nil }

    /// Brushing and reading start from the island and the lock screen; everything else is Done
    private func startURL(_ p: PromiseItem) -> String? {
        let t = p.title.lowercased()
        return t.contains("brush") ? "cadence://brush" : t.hasPrefix("read") ? "cadence://read" : nil
    }
    private static let messageLength = 90 // the island and the lock screen show two lines

    private func pick() -> Nudge? {
        let store = Store.shared
        let p = store.profile
        let now = Day.minuteOfDay()
        let quiet = p.quietStart > p.quietEnd ? (now >= p.quietStart || now < p.quietEnd) : (now >= p.quietStart && now < p.quietEnd)
        guard !quiet, store.activeSession == nil else { return nil }
        func awake(_ id: String) -> Bool { (snoozed[id] ?? .distantPast) < Date() }
        for m in store.openMustDos() where store.time(of: m) <= now && awake(m.id) {
            return Nudge(message: Pip.stable(.mustDoOpen, store: store, key: m.id, what: m.title, maxLength: Self.messageLength), short: m.title, promiseId: m.id, icon: m.icon, startURL: startURL(m))
        }
        // from the moment it's time: a Live Activity can't start itself while the app isn't running
        for r in store.due() where store.status(r) == nil && store.time(of: r) <= now && store.time(of: r) + 240 > now && awake(r.id) {
            let tiny = r.tiny.map { "Tiny version: \($0.lowercased())." }
            let message = Pip.stable(Pip.situation(forTitle: r.title, fallback: .routineLate), store: store, key: r.id, what: r.title, lead: "\(r.title) was at \(store.timeLabel(r)).", tail: tiny, maxLength: Self.messageLength)
            return Nudge(message: message, short: r.title, promiseId: r.id, icon: r.icon, startURL: startURL(r))
        }
        // coming up within 30 minutes: already on the lock screen when the time comes, even if the app has stopped by then
        if let r = store.due().filter({ store.status($0) == nil && store.time(of: $0) > now && store.time(of: $0) <= now + 30 && awake($0.id) }).min(by: { store.time(of: $0) < store.time(of: $1) }) {
            return Nudge(message: "\(r.title) at \(store.timeLabel(r)).", short: r.title, promiseId: r.id, icon: r.icon, startURL: startURL(r))
        }
        let plan = store.sleepPlan()
        if now >= plan.windDown && now < plan.perform && awake("wind") {
            return Nudge(message: Pip.stable(.windDown, store: store, lead: "Lights out at \(clock(plan.perform)).", maxLength: Self.messageLength), short: "Wind-down", promiseId: nil, icon: "moon.fill")
        }
        let f = store.fuel()
        if store.profile.on("fuel") {
            if f.water + 600 < store.waterPace() && awake("water") { return Nudge(message: Pip.stable(.waterBehind, store: store, maxLength: Self.messageLength), short: "Water", promiseId: nil, icon: "drop.fill") }
            if now >= 18 * 60, f.protein < p.proteinTarget * 0.65, awake("protein") { return Nudge(message: Pip.stable(.proteinBehind, store: store, lead: "\(Int(p.proteinTarget - f.protein)) g protein left today.", maxLength: Self.messageLength), short: "Protein", promiseId: nil, icon: "fork.knife") }
        }
        return nil
    }

    func refresh() async {
        if TestMode.active { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let n = pick() else { await end(); return }
        let state = PipAttributes.ContentState(message: n.message, short: n.short, mood: Store.shared.pipMood() == .sleepy ? "pip-sleepy" : "pip-neutral", promiseId: n.promiseId, icon: n.icon, startURL: n.startURL)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(2 * 3600))
        if let activity, activity.activityState == .active {
            if activity.content.state != state { await activity.update(content) }
        } else {
            activity = try? Activity.request(attributes: PipAttributes(started: Date()), content: content)
        }
    }

    func end() async {
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        for a in Activity<PipAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    func handle(_ action: PipAction, promiseId: String) async {
        let store = Store.shared
        guard store.canChange else { return } // nothing is answered while the data isn't safe
        if action == .done, let p = store.promises[promiseId] {
            store.log(p, .done)
            guard store.commit() else { return } // the nudge stays as it was if the answer couldn't be saved
        } else { snoozed[promiseId] = Date().addingTimeInterval(30 * 60) }
        await refresh()
    }
}
