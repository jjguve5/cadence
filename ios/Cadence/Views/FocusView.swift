// Focus mode: an intention first, then the timer (with overflow when you're in flow), then a two-tap rating that
// also teaches Cadence your peak hours. Leaving the app gets a 10-second grace and a nudge back, never a penalty.
// VS Code shows the same session and runs the desk breaks while it lasts.
import AudioToolbox
import SwiftUI
import UserNotifications

struct FocusView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var intention = ""
    @State private var planned = 50
    @State private var projectId: String?
    @State private var chimes = false
    @State private var sessionId: String?
    @State private var ending = false
    @State private var rating = 2
    @State private var depth = 3
    @State private var progress = ""
    @State private var now = Date()
    @State private var lastChime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var session: FocusSession? { sessionId.flatMap { store.record(FocusSession.self, $0) } }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            RadialGradient(colors: [Color.mint.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 400).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "chevron.down").font(.geist(17, .semibold)).foregroundStyle(Color.soft).padding(10) } }
                if let s = session, !ending { running(s) } else if ending { finish } else { setup }
                Spacer()
            }
            .padding(20)
        }
        .onAppear { if let f = store.activeFocus { sessionId = f.id } }
        .onReceive(timer) { t in
            now = t
            if let s = session, s.chimes, t.timeIntervalSince(lastChime) >= 7 * 60 { AudioServicesPlaySystemSound(1113); lastChime = t }
        }
        .onChange(of: phase) { _, p in
            guard let s = session, !ending else { return }
            let center = UNUserNotificationCenter.current()
            if p == .background {
                let c = UNMutableNotificationContent()
                c.title = "Back to focus?"
                c.body = "Pip is still growing: \(s.intention)"
                c.sound = .default
                center.add(UNNotificationRequest(identifier: "focus-nudge", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
            } else if p == .active {
                center.removePendingNotificationRequests(withIdentifiers: ["focus-nudge"])
                center.getDeliveredNotifications { list in
                    if list.contains(where: { $0.request.identifier == "focus-nudge" }) {
                        Task { @MainActor in
                            guard var latest = Store.shared.record(FocusSession.self, s.id) else { return }
                            latest.leftApp += 1
                            Store.shared.save(latest)
                        }
                    }
                }
                center.removeDeliveredNotifications(withIdentifiers: ["focus-nudge"])
            }
        }
    }

    private var setup: some View {
        VStack(spacing: 16) {
            PipAnimation(mood: .idle).frame(width: 150, height: 150)
            Text("What will you focus on?").font(.geist(22, .bold))
            TextField("One clear intention", text: $intention).font(.geist(17)).padding(14).background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.07)))
            HStack {
                ForEach([25, 50, 90], id: \.self) { m in
                    Button("\(m) min") { planned = m }.buttonStyle(.plain).font(.geist(15, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(planned == m ? Color.mint.opacity(0.85) : .white.opacity(0.08)))
                        .foregroundStyle(planned == m ? Color(hex: 0x032018) : Color.ink)
                }
            }
            let projects = store.all(Project.self).filter { !$0.archived }
            if !projects.isEmpty {
                Picker("Project", selection: $projectId) {
                    Text("No project").tag(String?.none)
                    ForEach(projects) { Text($0.title).tag(Optional($0.id)) }
                }
                .tint(.mint)
            }
            Toggle("Drift chimes every 7 minutes", isOn: $chimes).tint(.mint).font(.geist(14))
            PrimaryButton(title: "Start") {
                let s = FocusSession(intention: intention.isEmpty ? "Focus" : intention, planned: planned, chimes: chimes, projectId: projectId)
                store.save(s)
                store.recordFocusPrediction(session: s)
                sessionId = s.id
                lastChime = Date()
                UIApplication.shared.isIdleTimerDisabled = true
                Task { await Agenda.shared.publishFocus(s) }
                // Move nudge after 50 minutes, unless VS Code is running the desk breaks
                let atDesk = store.all(DeskEvent.self).contains { nowMs() - $0.at < 30 * 60 * 1000 }
                if !atDesk, s.planned > 50 {
                    let c = UNMutableNotificationContent()
                    c.title = "Time to move"
                    c.body = "50 minutes in: stand up and walk for two minutes, then back to it."
                    c.sound = .default
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "move-\(s.id)", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 50 * 60, repeats: false)))
                }
            }
            Text("Turn on Do Not Disturb or your Focus mode now; desk breaks appear in VS Code while it's open.").font(.geist(12)).foregroundStyle(Color.faint).multilineTextAlignment(.center)
        }
    }

    private func running(_ s: FocusSession) -> some View {
        let elapsed = now.timeIntervalSince(Date(timeIntervalSince1970: s.start / 1000))
        let total = Double(s.planned * 60)
        let over = elapsed > total
        return VStack(spacing: 18) {
            Text(s.intention).font(.geist(20, .semibold)).multilineTextAlignment(.center)
            ZStack {
                Ring(progress: over ? 1 : elapsed / total, area: .mint, width: 10).frame(width: 230, height: 230)
                VStack(spacing: 4) {
                    PipHead(mood: over ? .proud : .idle, size: 70)
                    Text(over ? "+" + timeText(elapsed - total) : timeText(total - elapsed)).font(.mono(40, .semibold))
                    Text(over ? "in flow · overflow" : "of \(s.planned) min").font(.geist(13)).foregroundStyle(Color.soft)
                }
            }
            Text("Pip's sprout grows while you stay. \(s.leftApp == 0 ? "" : "Left \(s.leftApp)× , that's fine.")").font(.geist(13)).foregroundStyle(Color.soft)
            PrimaryButton(title: "End session") { ending = true }
        }
    }

    private var finish: some View {
        VStack(spacing: 16) {
            PipAnimation(mood: .celebrate).frame(width: 140, height: 140)
            Text("How did that feel?").font(.geist(22, .bold))
            HStack {
                ForEach([(1, "Drained", "battery.25"), (2, "Neutral", "battery.50"), (3, "Energized", "battery.100.bolt")], id: \.0) { v, name, icon in
                    Button { rating = v } label: {
                        VStack(spacing: 6) { Image(systemName: icon).font(.geist(20)); Text(name).font(.geist(12, .semibold)) }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(rating == v ? Color.mint.opacity(0.3) : .white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text("Depth").font(.geist(14)).foregroundStyle(Color.soft)
                ForEach(1...5, id: \.self) { n in Image(systemName: n <= depth ? "circle.fill" : "circle").foregroundStyle(Color.mint).onTapGesture { depth = n } }
            }
            if let pid = session?.projectId, let p = store.record(Project.self, pid) {
                TextField("\(p.unit.capitalized) done for \(p.title)", text: $progress).keyboardType(.decimalPad).padding(12).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
            }
            PrimaryButton(title: "Save") {
                guard var s = session else { dismiss(); return }
                s.end = nowMs()
                s.rating = rating
                s.depth = depth
                if let amount = Double(progress.replacingOccurrences(of: ",", with: ".")), let pid = s.projectId, var p = store.record(Project.self, pid) {
                    s.progress = amount
                    p.logs.append(ProgressLog(date: Day.today, amount: amount))
                    store.save(p)
                } else if let pid = s.projectId, var p = store.record(Project.self, pid), p.unit == "hours" {
                    p.logs.append(ProgressLog(date: Day.today, amount: (Double(s.minutes) / 60 * 10).rounded() / 10))
                    store.save(p)
                }
                store.save(s)
                UIApplication.shared.isIdleTimerDisabled = false
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["move-\(s.id)"])
                Task { await Agenda.shared.publishFocus(nil) }
                dismiss()
            }
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
