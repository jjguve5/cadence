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
            Eyebrow(text: "Planear a sesta", icon: "powersleep", color: .sleep)
            Text(plan.debt > 60 && dip ? "Dívida de sono de \(duration(plan.debt)) e estás na quebra da tarde: uma sesta de 20 minutos agora compensa sem prejudicar esta noite." : dip ? "Quebra da tarde: uma sesta de 20 minutos está bem; de 90 minutos, só se esta noite te deitares tarde." : "Melhor altura para a sesta: 13:00–16:00. Sestas mais tarde atrasam a hora de deitar.")
                .font(.geist(13.5))
            HStack {
                SoftButton(title: "20 min", icon: "alarm") { schedule(26) }
                SoftButton(title: "90 min", icon: "alarm") { schedule(96) }
                if let set { Text("Alarme às \(set.formatted(date: .omitted, time: .shortened))").font(.geist(12)).foregroundStyle(Color.soft) }
            }
            Text("Inclui 6 minutos para adormecer. As sestas reduzem a dívida quando o Air as registar.").font(.geist(11)).foregroundStyle(Color.faint)
        }
    }
    private func schedule(_ minutes: Int) {
        let c = UNMutableNotificationContent()
        c.title = "Hora de levantar"
        c.body = "Luz, água e uns passos."
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

    /// What each phase shows; the English names above stay, because current(_:) reads them
    private func label(_ name: String) -> String {
        ["In": "Inspira", "Hold": "Sustém", "Out": "Expira", "In again": "Inspira mais um pouco", "Long out": "Expira devagar", "Rest": "Descansa"][name] ?? name
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
                HStack { Spacer(); Button("Fechar") { dismiss() }.foregroundStyle(Color.soft) }
                Picker("", selection: $mode) { Text("Quadrada").tag("box"); Text("Suspiro").tag("sigh"); Text("Descanso").tag("nsdr") }.pickerStyle(.segmented).disabled(running)
                Spacer()
                ZStack {
                    Circle().fill(Area.sleep.gradient).opacity(0.35).scaleEffect(running ? scale : 0.7)
                    Circle().stroke(Color.sleep, lineWidth: 2).scaleEffect(running ? scale : 0.7)
                    Text(running ? (mode == "nsdr" ? "Deixa o corpo ficar pesado" : label(phase.name)) : "Quando quiseres").font(.geist(22, .semibold))
                }
                .frame(width: 260, height: 260)
                .animation(.linear(duration: 0.1), value: scale)
                if running { Text(String(format: "faltam %d:%02d", Int(max(0, total - elapsed)) / 60, Int(max(0, total - elapsed)) % 60)).font(.mono(15)).foregroundStyle(Color.soft) }
                Spacer()
                if !running {
                    Stepper("\(length) \(length == 1 ? "minuto" : "minutos")", value: $length, in: 1...20).padding(.horizontal, 40)
                    PrimaryButton(title: "Começar", area: .sleep) { start = Date(); running = true; UIApplication.shared.isIdleTimerDisabled = true }
                } else {
                    SoftButton(title: "Parar") { running = false; UIApplication.shared.isIdleTimerDisabled = false }
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
        var lines = ["Resumo de saúde do Cadence · \(Day.date(Day.today).formatted(date: .long, time: .omitted))", "Dados de bem-estar de um Fitbit Air; não é um dispositivo médico.", ""]
        let months = (0..<180).compactMap { health[Day.add(-$0, to: Day.today)] }
        func avg(_ v: [Double]) -> String { v.isEmpty ? "–" : String(format: "%.1f", v.reduce(0, +) / Double(v.count)) }
        lines.append("Frequência cardíaca em repouso, média de 6 meses: \(avg(months.compactMap(\.rhr))) bpm (últimos 14 dias: \(avg(months.prefix(14).compactMap(\.rhr))))")
        lines.append("VFC (RMSSD), média de 6 meses: \(avg(months.compactMap(\.hrv))) ms")
        lines.append("SpO₂ média durante a noite: \(avg(months.compactMap(\.spo2)))%  · frequência respiratória \(avg(months.compactMap(\.breathing)))/min")
        if let v = months.compactMap(\.vo2).first { lines.append("VO₂ máx. (último valor): \(Int(v))") }
        let nights = months.prefix(30).compactMap { $0.sleep?.asleep }
        if !nights.isEmpty { lines.append("Sono, últimas 30 noites: \(duration(nights.reduce(0, +) / nights.count)) por noite; índice de regularidade \(sleepRegularity(nights: 28).map(String.init) ?? "–")") }
        let irn = IntradayStore.shared.day(Day.today)?.irn ?? []
        lines.append("Alertas de ritmo irregular no último ano: \(irn.isEmpty ? "nenhum" : irn.joined(separator: ", "))")
        let bp = all(BloodPressure.self).sorted { $0.date > $1.date }
        if !bp.isEmpty { lines.append(""); lines.append("Medições da tensão arterial:"); lines += bp.prefix(14).map { "  \($0.date) \(clock($0.minute)): \($0.systolic)/\($0.diastolic)" + ($0.pulse.map { " · pulso \($0)" } ?? "") } }
        let labs = all(LabResult.self).sorted { $0.date > $1.date }
        if !labs.isEmpty { lines.append(""); lines.append("Análises:"); lines += labs.prefix(20).map { "  \($0.date) \(labLabel($0.name)): \(kg($0.value)) \($0.unit)" } }
        if let h = homaIR { lines.append(String(format: "HOMA-IR (%@): %.2f", h.date, h.value)) }
        let meds = all(Medicine.self).filter { $0.end.map { $0 >= Day.today } ?? true }
        if !meds.isEmpty { lines.append(""); lines.append("A tomar: " + meds.map { "\($0.name) \($0.dose)" }.joined(separator: "; ")) }
        return lines.joined(separator: "\n")
    }
}

/// What a lab test shows; the English name is what's saved, and HOMA-IR looks for its words
fileprivate func labLabel(_ name: String) -> String {
    ["Fasting glucose": "Glicose em jejum", "Fasting insulin": "Insulina em jejum", "Triglycerides": "Triglicéridos", "Vitamin D": "Vitamina D", "Ferritin": "Ferritina"][name] ?? name
}

struct HealthRecordsCard: View {
    @EnvironmentObject var store: Store
    @State private var sys = ""
    @State private var dia = ""
    @State private var labName = "Fasting glucose"
    @State private var labValue = ""

    var body: some View {
        Card {
            Eyebrow(text: "Tensão arterial e análises", icon: "stethoscope")
            HStack {
                TextField("Máx", text: $sys).keyboardType(.numberPad).frame(width: 50)
                Text("/")
                TextField("Mín", text: $dia).keyboardType(.numberPad).frame(width: 50)
                Spacer()
                SoftButton(title: "Registar medição") { if let s = Int(sys), let d = Int(dia) { store.save(BloodPressure(systolic: s, diastolic: d)); sys = ""; dia = "" } }
            }
            let bp = store.all(BloodPressure.self).sorted { $0.date > $1.date }
            if !bp.isEmpty {
                let recent = bp.prefix(7)
                let avgS = recent.map(\.systolic).reduce(0, +) / recent.count, avgD = recent.map(\.diastolic).reduce(0, +) / recent.count
                let average = recent.count == 1 ? "A última medição dá \(avgS)/\(avgD)" : "As últimas \(recent.count) medições dão em média \(avgS)/\(avgD)"
                Text(average + (avgS >= 130 || avgD >= 80 ? ", acima de 130/80: vale a pena mostrar a um médico." : ".")).font(.geist(12.5)).foregroundStyle(avgS >= 130 || avgD >= 80 ? Color.warn : Color.soft)
            }
            HStack {
                Picker("", selection: $labName) { ForEach(["Fasting glucose", "Fasting insulin", "HbA1c", "LDL", "HDL", "Triglycerides", "Vitamin D", "Ferritin"], id: \.self) { Text(labLabel($0)).tag($0) } }.labelsHidden()
                TextField("Valor", text: $labValue).keyboardType(.decimalPad).frame(width: 70)
                SoftButton(title: "Adicionar") {
                    let units = ["Fasting glucose": "mg/dL", "Fasting insulin": "µU/mL", "HbA1c": "%", "Vitamin D": "ng/mL", "Ferritin": "ng/mL"]
                    if let v = Double(labValue.replacingOccurrences(of: ",", with: ".")) { store.save(LabResult(name: labName, value: v, unit: units[labName] ?? "mg/dL")); labValue = "" }
                }
            }
            if let h = store.homaIR {
                Text(String(format: "HOMA-IR %.2f, de %@", h.value, Day.date(h.date).formatted(.dateTime.day().month().year())) + (h.value >= 2.9 ? ": acima de 2.9, o limiar de resistência à insulina no estudo WEAR-ME da Google." : ": abaixo de 2.9.")).font(.geist(12.5)).foregroundStyle(h.value >= 2.9 ? Color.warn : Color.good)
            } else {
                Text("Uma análise de glicose e insulina em jejum dá o teu próprio HOMA-IR (glicose × insulina ÷ 405), a base da estimativa de insulina.").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            ShareLink(item: store.doctorSummary(), preview: SharePreview("Resumo de saúde do Cadence")) { Label("Resumo para o médico", systemImage: "doc.text") }.font(.geist(13.5, .semibold)).tint(.mint)
        }
    }
}
