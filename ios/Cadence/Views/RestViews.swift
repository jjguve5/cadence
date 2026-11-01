// Rest: the nap planner, breathing and deep rest sessions, blood pressure and lab results, and a doctor summary.
import SwiftUI
import UserNotifications

struct NapCard: View {
    @EnvironmentObject var store: Store
    @State private var set: Date?
    var body: some View {
        let plan = store.sleepPlan()
        let m = Day.minuteOfDay(store.tick)
        let dip = m >= 13 * 60 && m <= 16 * 60
        Card(tint: .sleep) {
            Eyebrow(text: "Nap planner", icon: "powersleep", color: .sleep)
            Text(plan.debt > 60 && dip ? "Sleep debt \(duration(plan.debt)) and you're in the afternoon dip: a 20-minute nap now pays back without hurting tonight." : dip ? "Afternoon dip: a 20-minute nap is fine; 90 minutes only if tonight is late." : "Best nap window: 13:00–16:00. Later naps push bedtime.")
                .font(.geist(13.5))
            HStack {
                SoftButton(title: "20 min", icon: "alarm") { schedule(26) }
                SoftButton(title: "90 min", icon: "alarm") { schedule(96) }
                if let set { Text("Alarm at \(set.formatted(date: .omitted, time: .shortened))").font(.geist(12)).foregroundStyle(Color.soft) }
            }
            Text("Includes 6 minutes to fall asleep. Naps reduce the debt once the Air logs them.").font(.geist(11)).foregroundStyle(Color.faint)
        }
    }
    private func schedule(_ minutes: Int) {
        let c = UNMutableNotificationContent()
        c.title = "Time to get up"
        c.body = "Light, water, and a few steps."
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "nap", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes * 60), repeats: false)))
        set = Date().addingTimeInterval(Double(minutes * 60))
    }
}

/// Box breathing, the physiological sigh, and deep rest with the phone's own vibration and voice
struct BreathingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "box"
    @State private var running = false
    @State private var start = Date()
    @State private var now = Date()
    @State private var length = 5
    @State private var lastPhase = -1
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var phases: [(String, Double)] {
        mode == "box" ? [("In", 4), ("Hold", 4), ("Out", 4), ("Hold", 4)] : mode == "sigh" ? [("In", 2), ("In again", 1), ("Long out", 6)] : [("Rest", 60)]
    }

    private func current(_ elapsed: Double) -> (name: String, scale: Double, index: Int) {
        let list = phases
        let cycle = list.map(\.1).reduce(0, +)
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        var end = 0.0
        for (i, p) in list.enumerated() {
            let begin = end
            end += p.1
            guard t < end else { continue }
            let f = (t - begin) / p.1
            if p.0.hasPrefix("In") { return (p.0, 0.6 + 0.4 * f, i) }
            if p.0 == "Hold" { return (p.0, i == 1 ? 1 : 0.6, i) }
            if p.0.lowercased().contains("out") { return (p.0, 1 - 0.4 * f, i) }
            return (p.0, 0.8, i)
        }
        return (list[0].0, 0.8, 0)
    }

    var body: some View {
        let elapsed = now.timeIntervalSince(start)
        let phase = current(elapsed)
        let scale = phase.scale
        let total = Double(length * 60)
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack { Spacer(); Button("Close") { dismiss() }.foregroundStyle(Color.soft) }
                Picker("", selection: $mode) { Text("Box").tag("box"); Text("Sigh").tag("sigh"); Text("Deep rest").tag("nsdr") }.pickerStyle(.segmented).disabled(running)
                Spacer()
                ZStack {
                    Circle().fill(Area.sleep.gradient).opacity(0.35).scaleEffect(running ? scale : 0.7)
                    Circle().stroke(Color.sleep, lineWidth: 2).scaleEffect(running ? scale : 0.7)
                    Text(running ? (mode == "nsdr" ? "Let your body go heavy" : phase.name) : "Ready").font(.geist(22, .semibold))
                }
                .frame(width: 260, height: 260)
                .animation(.linear(duration: 0.1), value: scale)
                if running { Text(String(format: "%d:%02d left", Int(max(0, total - elapsed)) / 60, Int(max(0, total - elapsed)) % 60)).font(.mono(15)).foregroundStyle(Color.soft) }
                Spacer()
                if !running {
                    Stepper("\(length) minutes", value: $length, in: 1...20).padding(.horizontal, 40)
                    PrimaryButton(title: "Start", area: .sleep) { start = Date(); running = true; UIApplication.shared.isIdleTimerDisabled = true }
                } else {
                    SoftButton(title: "Stop") { running = false; UIApplication.shared.isIdleTimerDisabled = false }
                }
            }
            .padding(24)
        }
        .onReceive(timer) { d in
            now = d
            guard running else { return }
            if d.timeIntervalSince(start) >= total { running = false; UINotificationFeedbackGenerator().notificationOccurred(.success); UIApplication.shared.isIdleTimerDisabled = false; return }
            let i = current(d.timeIntervalSince(start)).index
            if i != lastPhase { lastPhase = i; UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
    }
}

struct BloodPressure: Record, Equatable {
    static let kind = "bp"
    var id = UUID().uuidString
    var date = Day.today
    var minute = Day.minuteOfDay()
    var systolic: Int
    var diastolic: Int
    var pulse: Int?
}

struct LabResult: Record, Equatable {
    static let kind = "lab"
    var id = UUID().uuidString
    var date = Day.today
    var name: String // fasting glucose, insulin, HbA1c, LDL...
    var value: Double
    var unit: String
}

@MainActor
extension Store {
    /// HOMA-IR from a fasting glucose (mg/dL) and insulin (µU/mL) on the same day
    var homaIR: (value: Double, date: String)? {
        let labs = all(LabResult.self)
        for g in labs.filter({ $0.name.lowercased().contains("glucose") }).sorted(by: { $0.date > $1.date }) {
            if let i = labs.first(where: { $0.date == g.date && $0.name.lowercased().contains("insulin") }) { return (g.value * i.value / 405, g.date) }
        }
        return nil
    }

    func doctorSummary() -> String {
        var lines = ["Cadence health summary · \(Day.date(Day.today).formatted(date: .long, time: .omitted))", "Wellness data from a Fitbit Air; not a medical device.", ""]
        let months = (0..<180).compactMap { health[Day.add(-$0, to: Day.today)] }
        func avg(_ v: [Double]) -> String { v.isEmpty ? "–" : String(format: "%.1f", v.reduce(0, +) / Double(v.count)) }
        lines.append("Resting heart rate, 6-month average: \(avg(months.compactMap(\.rhr))) bpm (last 14 days \(avg(months.prefix(14).compactMap(\.rhr))))")
        lines.append("HRV (RMSSD), 6-month average: \(avg(months.compactMap(\.hrv))) ms")
        lines.append("Overnight SpO₂ average: \(avg(months.compactMap(\.spo2)))%  · breathing rate \(avg(months.compactMap(\.breathing)))/min")
        if let v = months.compactMap(\.vo2).first { lines.append("VO₂ max (latest): \(Int(v))") }
        let nights = months.prefix(30).compactMap { $0.sleep?.asleep }
        if !nights.isEmpty { lines.append("Sleep, last 30 nights: \(duration(nights.reduce(0, +) / nights.count)) a night; regularity index \(sleepRegularity(nights: 28).map(String.init) ?? "–")") }
        let irn = IntradayStore.shared.day(Day.today)?.irn ?? []
        lines.append("Irregular rhythm alerts in the last year: \(irn.isEmpty ? "none" : irn.joined(separator: ", "))")
        let bp = all(BloodPressure.self).sorted { $0.date > $1.date }
        if !bp.isEmpty { lines.append(""); lines.append("Blood pressure readings:"); lines += bp.prefix(14).map { "  \($0.date) \(clock($0.minute)): \($0.systolic)/\($0.diastolic)" + ($0.pulse.map { " · pulse \($0)" } ?? "") } }
        let labs = all(LabResult.self).sorted { $0.date > $1.date }
        if !labs.isEmpty { lines.append(""); lines.append("Lab results:"); lines += labs.prefix(20).map { "  \($0.date) \($0.name): \(kg($0.value)) \($0.unit)" } }
        if let h = homaIR { lines.append(String(format: "HOMA-IR (%@): %.2f", h.date, h.value)) }
        let meds = all(Medicine.self).filter { $0.end.map { $0 >= Day.today } ?? true }
        if !meds.isEmpty { lines.append(""); lines.append("Taking: " + meds.map { "\($0.name) \($0.dose)" }.joined(separator: "; ")) }
        return lines.joined(separator: "\n")
    }
}

struct HealthRecordsCard: View {
    @EnvironmentObject var store: Store
    @State private var sys = ""
    @State private var dia = ""
    @State private var labName = "Fasting glucose"
    @State private var labValue = ""

    var body: some View {
        Card {
            Eyebrow(text: "Blood pressure and lab results", icon: "stethoscope")
            HStack {
                TextField("Sys", text: $sys).keyboardType(.numberPad).frame(width: 50)
                Text("/")
                TextField("Dia", text: $dia).keyboardType(.numberPad).frame(width: 50)
                Spacer()
                SoftButton(title: "Log reading") { if let s = Int(sys), let d = Int(dia) { store.save(BloodPressure(systolic: s, diastolic: d)); sys = ""; dia = "" } }
            }
            let bp = store.all(BloodPressure.self).sorted { $0.date > $1.date }
            if !bp.isEmpty {
                let recent = bp.prefix(7)
                let avgS = recent.map(\.systolic).reduce(0, +) / recent.count, avgD = recent.map(\.diastolic).reduce(0, +) / recent.count
                Text("Last \(recent.count) readings average \(avgS)/\(avgD)" + (avgS >= 130 || avgD >= 80 ? ": above 130/80, worth showing a doctor." : ".")).font(.geist(12.5)).foregroundStyle(avgS >= 130 || avgD >= 80 ? Color.warn : Color.soft)
            }
            HStack {
                Picker("", selection: $labName) { ForEach(["Fasting glucose", "Fasting insulin", "HbA1c", "LDL", "HDL", "Triglycerides", "Vitamin D", "Ferritin"], id: \.self) { Text($0).tag($0) } }.labelsHidden()
                TextField("Value", text: $labValue).keyboardType(.decimalPad).frame(width: 70)
                SoftButton(title: "Add") {
                    let units = ["Fasting glucose": "mg/dL", "Fasting insulin": "µU/mL", "HbA1c": "%", "Vitamin D": "ng/mL", "Ferritin": "ng/mL"]
                    if let v = Double(labValue.replacingOccurrences(of: ",", with: ".")) { store.save(LabResult(name: labName, value: v, unit: units[labName] ?? "mg/dL")); labValue = "" }
                }
            }
            if let h = store.homaIR {
                Text(String(format: "HOMA-IR %.2f from %@", h.value, Day.date(h.date).formatted(.dateTime.day().month().year())) + (h.value >= 2.9 ? ": above 2.9, the insulin-resistance line in Google's WEAR-ME study." : ": below 2.9.")).font(.geist(12.5)).foregroundStyle(h.value >= 2.9 ? Color.warn : Color.good)
            } else {
                Text("One fasting glucose and insulin test gives your own HOMA-IR (glucose × insulin ÷ 405), the anchor for the insulin estimate.").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            ShareLink(item: store.doctorSummary(), preview: SharePreview("Cadence health summary")) { Label("Doctor summary", systemImage: "doc.text") }.font(.geist(13.5, .semibold)).tint(.mint)
        }
    }
}
