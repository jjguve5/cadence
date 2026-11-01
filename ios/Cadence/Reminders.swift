// Local notifications. iOS keeps at most 64 per app, so Cadence queues the next 48 hours by priority and tops the
// queue up whenever it runs. Must-dos ask at their time, then 90 and 150 minutes later, and at wind-down if still
// open. Each one can be answered from the lock screen: Done, In 30 min, Skip.
import Foundation
import UserNotifications

final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()
    private let center = UNUserNotificationCenter.current()
    static let category = "promise"

    func setUp() {
        center.delegate = self
        let done = UNNotificationAction(identifier: "done", title: "Done ✓", options: [])
        let snooze = UNNotificationAction(identifier: "snooze", title: "In 30 min", options: [])
        let skip = UNNotificationAction(identifier: "skip", title: "Skip", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [done, snooze, skip], intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private struct Planned {
        var id: String
        var at: Date
        var title: String
        var body: String
        var priority: Int // 0 = always gets through
        var promise: Bool
    }

    private var pending: DispatchWorkItem?

    /// Rebuilds the queue (debounced: many changes in a row only reschedule once)
    func reschedule() {
        pending?.cancel()
        let work = DispatchWorkItem { Task { @MainActor in self.rebuild() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    @MainActor private func rebuild() {
        let store = Store.shared
        let now = Date()
        let horizon = now.addingTimeInterval(48 * 3600)
        var planned: [Planned] = []
        let p = store.profile

        func quiet(_ date: Date) -> Bool {
            let m = Day.minuteOfDay(date)
            return p.quietStart > p.quietEnd ? (m >= p.quietStart || m < p.quietEnd) : (m >= p.quietStart && m < p.quietEnd)
        }

        for offset in 0...2 {
            let day = Day.add(offset, to: Day.today)
            for promise in store.due(on: day) where store.status(promise, on: day) == nil {
                let at = Day.at(promise.schedule.minute, on: day)
                if promise.kind == .mustDo {
                    let asks: [(Int, String)] = [(0, "\(promise.title) · now"), (90, "\(promise.title) not taken yet"), (150, "\(promise.title): last ask before wind-down")]
                    for (k, (after, title)) in asks.enumerated() {
                        let w = store.week(promise, upTo: day)
                        planned.append(Planned(id: "p|\(promise.id)|\(day)|\(k)", at: at.addingTimeInterval(Double(after) * 60), title: title, body: "Must-do · \(w.done)/\(w.total) this week", priority: 0, promise: true))
                    }
                } else if !quiet(at) {
                    let body = promise.tiny.map { "Short on time? \($0)." } ?? promise.schedule.summary.capitalized
                    planned.append(Planned(id: "p|\(promise.id)|\(day)|0", at: at, title: promise.title, body: body, priority: 2, promise: true))
                }
            }
            // Wind-down: holds until must-dos are answered
            let plan = store.sleepPlan(for: day)
            let wind = Day.at(plan.windDown, on: day)
            let open = store.openMustDos(on: day)
            let body = open.isEmpty ? "Lights out by \(clock(plan.perform)). Reading slot is next." : "First: \(open.map(\.title).joined(separator: ", ")). Then screens away."
            planned.append(Planned(id: "wind|\(day)", at: wind, title: "Wind-down", body: body, priority: open.isEmpty ? 1 : 0, promise: false))
            planned.append(Planned(id: "close|\(day)", at: wind.addingTimeInterval(-15 * 60), title: "Close the day", body: "Two minutes: how it went and tomorrow's top 3.", priority: 1, promise: false))
            planned.append(Planned(id: "brief|\(day)", at: Day.at(p.wakeMinute + 10, on: day), title: "Your morning brief", body: "Readiness, last night and today's promises.", priority: 1, promise: false))
        }

        // Within the daily budget, must-dos always first
        var perDay: [String: Int] = [:]
        let queue = planned.filter { $0.at > now && $0.at < horizon }.sorted { ($0.priority, $0.at) < ($1.priority, $1.at) }.filter {
            if $0.priority == 0 { return true }
            let d = Day.key($0.at)
            perDay[d, default: 0] += 1
            return perDay[d]! <= p.notificationBudget
        }.prefix(60)

        center.removeAllPendingNotificationRequests()
        for item in queue {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            if item.promise { content.categoryIdentifier = Self.category }
            content.threadIdentifier = item.promise ? "promises" : "day"
            let parts = Day.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.at)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    func clear(promise: String, day: String) {
        let ids = (0...2).map { "p|\(promise)|\(day)|\($0)" } + ["s|\(promise)|\(day)"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: Answers from the lock screen

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let parts = response.notification.request.identifier.split(separator: "|").map(String.init)
        guard parts.count >= 3, parts[0] == "p" || parts[0] == "s" else { return }
        let (promiseId, day) = (parts[1], parts[2])
        await MainActor.run {
            let store = Store.shared
            guard let promise = store.promises[promiseId] else { return }
            switch response.actionIdentifier {
            case "done": store.log(promise, on: day, .done)
            case "skip": store.log(promise, on: day, .skipped)
            case "snooze": self.snooze(promise, day: day)
            default: break
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    private func snooze(_ promise: PromiseItem, day: String) {
        let content = UNMutableNotificationContent()
        content.title = promise.title
        content.body = "Snoozed 30 min ago. Done now?"
        content.sound = .default
        content.categoryIdentifier = Self.category
        center.add(UNNotificationRequest(identifier: "s|\(promise.id)|\(day)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)))
    }
}
