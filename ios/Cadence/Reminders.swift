// Local notifications. iOS keeps at most 64 per app, so Cadence queues the next 48 hours by priority and tops the
// queue up whenever it runs. Must-dos ask at their time, then 90 and 150 minutes later, and at wind-down if still
// open. Each one can be answered from the lock screen: Done, In 30 min, Skip.
import CoreLocation
import Foundation
import UserNotifications

final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()
    private let center = UNUserNotificationCenter.current()
    static let category = "promise"
    /// What a laundry notification calls each wash group. The groups are stored values (Garment.washGroup) and stay
    /// in English; only the name on screen is Portuguese.
    private static let washGroupText = ["darks 30°": "Escuros 30°", "whites 40°": "Brancos 40°", "colours 30°": "Cores 30°", "delicates": "Delicados", "towels 60°": "Toalhas 60°", "gym 30°": "Treino 30°"]

    func setUp() {
        center.delegate = self
        let done = UNNotificationAction(identifier: "done", title: "Concluído ✓", options: [])
        let snooze = UNNotificationAction(identifier: "snooze", title: "Em 30 min", options: []) // the same words as the Pip Live Activity
        let skip = UNNotificationAction(identifier: "skip", title: "Saltar", options: [.destructive])
        let start = UNNotificationAction(identifier: "start", title: "Começar ▶", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "startable", actions: [start, snooze, skip], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "gymbag", actions: [UNNotificationAction(identifier: "done", title: "Esvaziado ✓", options: [])], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: Self.category, actions: [done, snooze, skip], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "info", actions: [], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "shower", actions: [UNNotificationAction(identifier: "done", title: "Duche tomado ✓", options: []), UNNotificationAction(identifier: "morning", title: "Amanhã de manhã", options: [])], intentIdentifiers: [], options: [.customDismissAction]),
        ])
        if !TestMode.active { center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in } }
    }

    private struct Planned {
        var id: String
        var at: Date
        var title: String
        var body: String
        var priority: Int // 0 = always gets through
        var promise: Bool
        var category: String?
        var arriving: CLLocationCoordinate2D? // ring on getting there rather than at a time
    }

    private var pending: DispatchWorkItem?

    /// Rebuilds the queue (debounced: many changes in a row only reschedule once)
    func reschedule() {
        pending?.cancel()
        let work = DispatchWorkItem { Task { @MainActor in self.rebuild() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// The queue must be right before the app stops running
    @MainActor func flush() {
        guard let work = pending, !work.isCancelled else { return }
        work.cancel()
        pending = nil
        rebuild()
    }

    @MainActor private func rebuild() {
        let store = Store.shared
        // Protected or a failed save: the data in memory isn't the real data, so the queue stays as it was instead of
        // being rebuilt from nothing (which would cancel every reminder)
        guard store.canChange else { return }
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
            let first = planned.count
            let plan = store.sleepPlan(for: day)
            let wind = Day.at(plan.windDown, on: day)
            for promise in store.due(on: day) where store.status(promise, on: day) == nil {
                let at = Day.at(store.time(of: promise, on: day), on: day)
                if promise.kind == .mustDo {
                    let asks: [(Int, String)] = [(0, "\(promise.title) · agora"), (90, "\(promise.title) ainda por fazer"), (150, "\(promise.title): último aviso antes de desacelerar")]
                    // the follow-ups stop at wind-down, which names what's still open
                    for (k, (after, title)) in asks.enumerated() where k == 0 || at.addingTimeInterval(Double(after) * 60) < wind {
                        let w = store.week(promise, upTo: day)
                        planned.append(Planned(id: "p|\(promise.id)|\(day)|\(k)", at: at.addingTimeInterval(Double(after) * 60), title: title, body: "Essencial · \(w.done)/\(w.total) esta semana", priority: 0, promise: true))
                    }
                } else if !quiet(at) {
                    let body = promise.tiny.map { "Pouco tempo? \($0)." } ?? { () -> String in let s = promise.schedule.summary; return s.prefix(1).uppercased() + s.dropFirst() }() // only the first letter: .capitalized gave "Todos Os Dias"
                    let startable = promise.title.lowercased().contains("brush") || promise.title.lowercased().hasPrefix("read")
                    planned.append(Planned(id: "p|\(promise.id)|\(day)|0", at: at, title: promise.title, body: body, priority: 2, promise: true, category: startable ? "startable" : nil))
                }
            }
            // Medicines and products: always get through when they're must-dos
            for d in store.doses(on: day) where d.log == nil {
                planned.append(Planned(id: "m|\(d.med.id)|\(day)|\(d.minute)", at: Day.at(d.minute, on: day), title: d.med.name, body: [d.med.dose, d.med.how].filter { !$0.isEmpty }.joined(separator: " · "), priority: d.med.mustDo ? 0 : 2, promise: true))
            }
            // Leave-by alerts for regular trips
            for c in store.commutes(on: day) {
                planned.append(Planned(id: "leave|\(c.id)|\(day)", at: Day.at(c.leave, on: day), title: "Sai agora para \(c.title)", body: "\(c.travel) min porta a porta; chegas às \(clock(c.arrive)).", priority: 0, promise: false))
            }
            // Grooming that's due, in the evening
            if offset == 0 || offset == 1, let g = store.groomingDue.first {
                planned.append(Planned(id: "groom|\(day)", at: Day.at(19 * 60 + 30, on: day), title: g.title, body: "Há \(g.daysSince ?? 0) dias desde a última vez; costumas fazê-lo a cada \(g.rhythm) dias.", priority: 2, promise: false))
            }
            // Life admin, each within the budget
            if offset == 0 {
                let f = store.fuel(on: day)
                if f.protein < store.profile.proteinTarget * 0.6 {
                    let gap = Int(store.profile.proteinTarget - f.protein)
                    planned.append(Planned(id: "protein|\(day)", at: Day.at(18 * 60, on: day), title: "Proteína em falta", body: "Faltam \(gap) g hoje. Um batido ou uma porção do frigorífico resolve a maior parte.", priority: 2, promise: false))
                }
                for m in [15 * 60, 19 * 60] where store.fuel(on: day).water + 300 < store.waterGoal(on: day) * Double(m - store.profile.wakeMinute) / Double(max(60, store.sleepPlan().perform - 120 - store.profile.wakeMinute)) {
                    planned.append(Planned(id: "water|\(day)|\(m)", at: Day.at(m, on: day), title: "Água", body: "Abaixo do ritmo: um copo agora.", priority: 3, promise: false))
                }
                for (g, at) in store.records("laundry").compactMap({ k, v -> (String, Double)? in if case .number(let t) = v, k.hasPrefix(day) { return (String(k.dropFirst(11)), t) }; return nil }) {
                    planned.append(Planned(id: "dry|\(day)|\(g)", at: Date(timeIntervalSince1970: at / 1000 + 2 * 3600), title: "Lavagem concluída", body: "\(Self.washGroupText[g] ?? g.capitalized): estender ou pôr na máquina de secar.", priority: 2, promise: false))
                }
            }
            for p in store.all(Plant.self) where store.plantDue(p).due && offset == 0 {
                planned.append(Planned(id: "plant|\(p.id)|\(day)", at: Day.at(19 * 60, on: day), title: "Regar \(p.name)", body: store.plantDue(p).note, priority: 3, promise: false))
            }
            for b in store.birthdaysSoon where b.date == Day.add(1, to: day) {
                planned.append(Planned(id: "bday|\(b.name)|\(day)", at: Day.at(19 * 60, on: day), title: "Amanhã é o aniversário de \(b.name)", body: b.person?.gifts.first.map { "Ideia de prenda: \($0)" } ?? "Boa altura para uma mensagem ou uma prenda.", priority: 1, promise: false))
            }
            for (r, d) in store.upcomingRenewals where Day.between(day, d) == r.remindDays && r.amount < 0 {
                planned.append(Planned(id: "renew|\(r.id)|\(day)", at: Day.at(10 * 60, on: day), title: "\(r.title) renova daqui a \(ptCount(r.remindDays, "dia", "dias"))", body: "\(euro(-r.amount, decimals: true))" + (r.cancelBy.map { " · cancela até \(Day.date($0).formatted(.dateTime.day().month())) se não precisares" } ?? ""), priority: 1, promise: false))
            }
            for d in store.all(DocumentItem.self) where Day.between(day, d.expires) == d.leadDays || Day.between(day, d.expires) == 7 {
                planned.append(Planned(id: "doc|\(d.id)|\(day)", at: Day.at(10 * 60, on: day), title: "\(d.title) expira em breve", body: Day.date(d.expires).formatted(.dateTime.day().month().year()), priority: 1, promise: false))
            }
            if Day.weekday(day) == 1, offset <= 1, !store.keepInTouchDue.isEmpty {
                planned.append(Planned(id: "touch|\(day)", at: Day.at(18 * 60, on: day), title: "Manter o contacto", body: "Já passou algum tempo: " + store.keepInTouchDue.prefix(3).map(\.name).joined(separator: ", "), priority: 3, promise: false))
            }
            // Fixed-time nudges that fall while you're out (a trip, an event) wait until you're back; promises already
            // moved in time(of:), and medicines and leave-by keep their times
            let busy = store.busy(on: day)
            for i in planned.indices.dropFirst(first) where !["leave", "m"].contains(planned[i].id.split(separator: "|").first.map(String.init) ?? "") && !planned[i].promise {
                let m = Day.minuteOfDay(planned[i].at), moved = Engine.outside(m, busy: busy)
                if moved != m { planned[i].at = Day.at(moved, on: day) }
            }
            // Home from the gym: when you arrive if Cadence knows where home is, otherwise 45 minutes after finishing
            if offset == 0, store.gymBagDue, let end = store.sessions(on: day).compactMap(\.end).max() {
                let arrival = CLLocationManager().authorizationStatus == .authorizedWhenInUse || CLLocationManager().authorizationStatus == .authorizedAlways ? store.homeCoordinate : nil
                let at = max(now.addingTimeInterval(60), Date(timeIntervalSince1970: end / 1000).addingTimeInterval(45 * 60))
                planned.append(Planned(id: "gymbag|\(day)", at: at, title: "Esvaziar o saco do ginásio", body: "Roupa para lavar, toalha a secar.", priority: 1, promise: false, category: "gymbag", arriving: arrival))
            }
            // The day's shower, tonight or tomorrow morning
            if offset <= 1, let s = store.showerPlan(for: day) {
                planned.append(Planned(id: "shower|\(day)|\(s.when.rawValue)", at: s.at, title: s.when == .morning ? "Duche (conta para ontem)" : "Duche", body: s.why + ".", priority: 1, promise: false, category: s.when == .tonight ? "shower" : "info"))
            }
            // Wind-down: holds until must-dos are answered
            let open = store.openMustDos(on: day)
            var body = open.isEmpty ? "Apagar as luzes até às \(clock(plan.perform)). A seguir, tempo de leitura." : "Primeiro: \(open.map(\.title).joined(separator: ", ")). Depois, ecrãs de lado."
            if let a = plan.after { body = "De volta de \(a.title): " + body.prefix(1).lowercased() + String(body.dropFirst()) }
            planned.append(Planned(id: "wind|\(day)", at: wind, title: "Desacelerar", body: body, priority: open.isEmpty ? 1 : 0, promise: false))
            // after a late trip, closing the day waits until you're in the door
            let close = plan.after.map { Day.at($0.end + 5, on: day) } ?? wind.addingTimeInterval(-15 * 60)
            planned.append(Planned(id: "close|\(day)", at: close, title: "Fechar o dia", body: "Dois minutos: como correu e as 3 prioridades de amanhã.", priority: 1, promise: false))
            planned.append(Planned(id: "brief|\(day)", at: Day.at(p.wakeMinute + 10, on: day), title: "O teu resumo da manhã", body: "Prontidão, a última noite e os hábitos de hoje.", priority: 1, promise: false))
        }

        // Within the daily budget, must-dos always first
        // Kinds you keep swiping away drop in priority, then stop; priority 0 (must-dos, medicines, leave-by) never does
        planned = planned.compactMap { item in
            guard item.priority > 0 else { return item }
            var x = item
            let kind = String(item.id.split(separator: "|").first ?? "")
            switch NotificationLearning.dismissRate(kind) {
            case let r? where r >= 0.9: return nil
            case let r? where r >= 0.7: x.priority += 1
            default: break
            }
            // On a minimum viable day only the essentials ring
            if store.isMinimumDay(Day.key(item.at)), item.priority >= 2 { return nil }
            return x
        }
        let picked = NotificationPlanner.select(planned.map { NotificationPlanner.Item(id: $0.id, at: $0.at, priority: $0.priority) }, now: now, horizon: horizon, budget: p.notificationBudget)
        let byId = Dictionary(planned.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let queue = picked.compactMap { byId[$0.id] }

        center.removeAllPendingNotificationRequests()
        for item in queue {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = item.category ?? (item.promise ? Self.category : "info")
            content.threadIdentifier = item.promise ? "promises" : "day"
            let parts = Day.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.at)
            var trigger: UNNotificationTrigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            if let place = item.arriving {
                let region = CLCircularRegion(center: place, radius: 150, identifier: item.id)
                region.notifyOnEntry = true
                region.notifyOnExit = false
                trigger = UNLocationNotificationTrigger(region: region, repeats: false)
            }
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    /// iOS reports a dismissal only when you clear a notification yourself; one that's simply ignored produces no
    /// callback. So on each launch, notifications still sitting unanswered after 2 hours count as ignored, then go.
    func collectIgnored() {
        center.getDeliveredNotifications { list in
            let old = list.filter { Date().timeIntervalSince($0.date) > 2 * 3600 }
            for n in old { NotificationLearning.record(String(n.request.identifier.split(separator: "|").first ?? ""), engaged: false) }
            self.center.removeDeliveredNotifications(withIdentifiers: old.map(\.request.identifier))
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
        NotificationLearning.record(parts.first ?? "", engaged: response.actionIdentifier != UNNotificationDismissActionIdentifier)
        if response.actionIdentifier == UNNotificationDismissActionIdentifier { return }
        // While the data isn't safe (protected or a failed save), actions from the lock screen change nothing
        guard await MainActor.run(body: { Store.shared.canChange }) else { return }
        if parts.count == 4, parts[0] == "m", let minute = Int(parts[3]) {
            await MainActor.run {
                let store = Store.shared
                guard let med = store.record(Medicine.self, parts[1]) else { return }
                switch response.actionIdentifier {
                case "done": store.take(med, minute: minute, on: parts[2])
                case "skip": store.take(med, minute: minute, on: parts[2], taken: false)
                default: break
                }
                store.commit() // a save that fails now shows when the app opens, instead of passing for saved
            }
            return
        }
        if parts.count == 2, parts[0] == "gymbag" {
            if response.actionIdentifier == "done" { await MainActor.run { Store.shared.unpackedGymBag(on: parts[1]); Store.shared.commit() } }
            return
        }
        if parts.count == 3, parts[0] == "shower" {
            await MainActor.run {
                switch response.actionIdentifier {
                case "done": Store.shared.logShower()
                case "morning": Store.shared.pickShower(.morning, for: parts[1])
                default: break
                }
                Store.shared.commit()
            }
            return
        }
        guard parts.count >= 3, parts[0] == "p" || parts[0] == "s" else { return }
        let (promiseId, day) = (parts[1], parts[2])
        await MainActor.run {
            let store = Store.shared
            guard let promise = store.promises[promiseId] else { return }
            switch response.actionIdentifier {
            case "done": store.log(promise, on: day, .done); store.commit()
            case "skip": store.log(promise, on: day, .skipped); store.commit()
            case "snooze": self.snooze(promise, day: day)
            case "start", UNNotificationDefaultActionIdentifier:
                // Start, or tapping the notification: brushing and reading open ready to go
                if promise.title.lowercased().contains("brush") { store.brushingOpen = true }
                else if promise.title.lowercased().hasPrefix("read") { store.readingOpen = true }
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
        content.body = "Adiado há 30 min. Já está feito?"
        content.sound = .default
        content.categoryIdentifier = Self.category
        center.add(UNNotificationRequest(identifier: "s|\(promise.id)|\(day)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)))
    }
}

/// What happens to each kind of notification: answered or opened counts as useful, swiped away as not.
/// Kept on this phone only; the last 10 of each kind.
enum NotificationLearning {
    private static func key(_ kind: String) -> String { "notif.\(kind)" }

    static func record(_ kind: String, engaged: Bool) {
        guard !kind.isEmpty else { return }
        var list = UserDefaults.standard.array(forKey: key(kind)) as? [Int] ?? []
        list.append(engaged ? 1 : 0)
        UserDefaults.standard.set(Array(list.suffix(10)), forKey: key(kind))
    }

    /// Share swiped away, once there are at least 6 answers
    static func dismissRate(_ kind: String) -> Double? {
        let list = UserDefaults.standard.array(forKey: key(kind)) as? [Int] ?? []
        guard list.count >= 6 else { return nil }
        return Double(list.filter { $0 == 0 }.count) / Double(list.count)
    }

    static var summary: [(kind: String, rate: Double, n: Int)] {
        let names = ["p", "wind", "close", "brief", "protein", "water", "plant", "dry", "bday", "renew", "doc", "touch", "groom", "m", "leave", "shower", "gymbag"]
        return names.compactMap { k in
            let list = UserDefaults.standard.array(forKey: key(k)) as? [Int] ?? []
            return list.isEmpty ? nil : (k, Double(list.filter { $0 == 0 }.count) / Double(list.count), list.count)
        }
    }
}

/// Which notifications get scheduled: priority 0 (must-dos, medicines, leave-by) always, the rest by priority within
/// the daily budget, everything inside the next 48 hours and under iOS's 64-request limit (60, leaving room).
enum NotificationPlanner {
    struct Item: Equatable { var id: String; var at: Date; var priority: Int }

    static func select(_ items: [Item], now: Date, horizon: Date, budget: Int, limit: Int = 60) -> [Item] {
        var perDay: [String: Int] = [:]
        let sorted = items.filter { $0.at > now && $0.at < horizon }.sorted { ($0.priority, $0.at) < ($1.priority, $1.at) }
        let essentials = sorted.filter { $0.priority == 0 }
        var rest: [Item] = []
        for i in sorted where i.priority > 0 {
            let d = Day.key(i.at)
            perDay[d, default: 0] += 1
            if perDay[d]! <= budget { rest.append(i) }
        }
        return Array((essentials + rest).prefix(limit))
    }
}
