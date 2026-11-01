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

    struct Nudge { var message: String; var short: String; var promiseId: String?; var icon: String }

    private func pick() -> Nudge? {
        let store = Store.shared
        let p = store.profile
        let now = Day.minuteOfDay()
        let quiet = p.quietStart > p.quietEnd ? (now >= p.quietStart || now < p.quietEnd) : (now >= p.quietStart && now < p.quietEnd)
        guard !quiet, store.activeSession == nil else { return nil }
        func awake(_ id: String) -> Bool { (snoozed[id] ?? .distantPast) < Date() }
        for m in store.openMustDos() where store.time(of: m) <= now && awake(m.id) {
            return Nudge(message: "\(m.title) is still waiting. It only takes a minute.", short: m.title, promiseId: m.id, icon: m.icon)
        }
        for r in store.due() where store.status(r) == nil && store.time(of: r) + 60 <= now && store.time(of: r) + 240 > now && awake(r.id) {
            return Nudge(message: "\(r.title) was at \(store.timeLabel(r)). Still on?" + (r.tiny.map { " Tiny version: \($0.lowercased())." } ?? ""), short: r.title, promiseId: r.id, icon: r.icon)
        }
        let plan = store.sleepPlan()
        if now >= plan.windDown && now < plan.perform && awake("wind") {
            return Nudge(message: "Wind-down time: screens away, lights low. Lights out at \(clock(plan.perform)).", short: "Wind-down", promiseId: nil, icon: "moon.fill")
        }
        let f = store.fuel()
        if store.profile.on("fuel") {
            if f.water + 600 < store.waterPace() && awake("water") { return Nudge(message: "Water is behind: a big glass now gets you back on pace.", short: "Water", promiseId: nil, icon: "drop.fill") }
            if now >= 18 * 60, f.protein < p.proteinTarget * 0.65, awake("protein") { return Nudge(message: "\(Int(p.proteinTarget - f.protein)) g protein left today. A shake or a fridge portion covers most of it.", short: "Protein", promiseId: nil, icon: "fork.knife") }
        }
        return nil
    }

    func refresh() async {
        if TestMode.active { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let n = pick() else { await end(); return }
        let state = PipAttributes.ContentState(message: n.message, short: n.short, mood: Store.shared.pipMood() == .sleepy ? "pip-sleepy" : "pip-neutral", promiseId: n.promiseId, icon: n.icon)
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
        if action == .done, let p = store.promises[promiseId] { store.log(p, .done) }
        else { snoozed[promiseId] = Date().addingTimeInterval(30 * 60) }
        await refresh()
    }
}
