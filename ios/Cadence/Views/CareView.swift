// Hygiene (brushing mode, showers, grooming freshness, the routine player) and Care (medicines and products).
import AVFoundation
import AudioToolbox
import SwiftUI

struct CareView: View {
    @EnvironmentObject var store: Store
    @State private var editingMed: Medicine?

    var body: some View {
        Screen(glow: Color(hex: 0x5FE3D0)) {
            MedicinesCard(editing: $editingMed)
        }
        .navigationTitle("Medicamentos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingMed) { MedicineEditor(med: $0) }
    }
}

struct HygieneView: View {
    @EnvironmentObject var store: Store
    @State private var playing: CareRoutine?
    @State private var editingRoutine: CareRoutine?

    var body: some View {
        NavigationStack {
        Screen(glow: Color(hex: 0x5FE3D0)) {
            // <name>.screen: how the UI tests know this tab's root is showing. Internal, never translated; if a redesign removes this title, the identifier moves to the new one
            Title(eyebrow: "Dentes, duches, cuidados pessoais e rotinas", title: "Higiene").accessibilityIdentifier("hygiene.screen").padding(.top, 8)
            Card(tint: Color(hex: 0x5FE3D0)) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Escovagem", icon: "mouth.fill", color: Color(hex: 0x5FE3D0))
                        let today = store.brushes()
                        Text(today.isEmpty ? "Hoje ainda não" : "\(today.count)× hoje · \(today.map { duration($0.seconds / 60) }.joined(separator: ", "))").font(.geist(14))
                        if store.brushHeadDue { Text("3 meses com esta cabeça de escova: está na altura de a trocar.").font(.geist(12)).foregroundStyle(Color.warn) }
                    }
                    Spacer()
                    Button { store.brushingOpen = true } label: { Image(systemName: "play.fill").foregroundStyle(Color(hex: 0x032018)).frame(width: 44, height: 44).background(Circle().fill(Color(hex: 0x5FE3D0))) }
                }
                if store.brushHeadDue { SoftButton(title: "Já troquei", icon: "checkmark") { store.put("brushhead", Day.today, .bool(true)) } }
            }
            ShowerCard()
            Card {
                Eyebrow(text: "Cuidados pessoais", icon: "scissors")
                ForEach(store.all(GroomingItem.self).sorted { $0.freshness < $1.freshness }) { g in
                    HStack(spacing: 10) {
                        Image(systemName: g.icon).foregroundStyle(Color.soft).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(g.title).font(.geist(14, .medium))
                                Spacer()
                                Text(g.daysSince.map { "há \($0) d · a cada ~\(g.rhythm) d" } ?? "nunca registado").font(.geist(11.5)).foregroundStyle((g.daysSince ?? 999) >= g.rhythm ? Color.warn : Color.faint)
                            }
                            Bar(progress: g.freshness, area: g.freshness < 0.15 ? .fuel : .mint)
                        }
                        Button { var x = g; x.history.append(Day.today); store.save(x) } label: { Image(systemName: "checkmark.circle").font(.geist(20)).foregroundStyle(Color.mint) }.buttonStyle(.plain)
                    }
                }
                if let trip = store.nextTrip, !store.groomingBefore(trip).isEmpty {
                    Text("Viagem a \(trip.destination), \(Day.date(trip.start).formatted(.dateTime.weekday(.wide))): \(store.groomingBefore(trip).map { $0.title.lowercased() }.joined(separator: ", ")) na véspera.").font(.geist(12.5)).foregroundStyle(Color.fuel)
                }
                Text("Começa com intervalos razoáveis, depois aprende os teus e avisa quando te afastas deles.").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            Card {
                HStack { Eyebrow(text: "Rotinas", icon: "list.number"); Spacer(); Button { editingRoutine = CareRoutine(title: "", steps: []) } label: { Image(systemName: "plus") }.tint(.mint) }
                ForEach(store.all(CareRoutine.self).sorted { $0.title < $1.title }) { r in
                    HStack {
                        Image(systemName: r.icon).foregroundStyle(Color.soft).frame(width: 22)
                        VStack(alignment: .leading) { Text(r.title).font(.geist(14, .medium)); Text("\(r.steps.count) \(r.steps.count == 1 ? "passo" : "passos") · \(duration(r.steps.map(\.seconds).reduce(0, +) / 60))").font(.geist(11.5)).foregroundStyle(Color.faint) }
                        Spacer()
                        Button { editingRoutine = r } label: { Image(systemName: "pencil").foregroundStyle(Color.soft) }.buttonStyle(.plain)
                        Button { playing = r } label: { Image(systemName: "play.circle.fill").font(.geist(26)).foregroundStyle(Color.mint) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { store.seedCare() }
        .fullScreenCover(item: $playing) { RoutinePlayer(routine: $0) }
        .sheet(item: $editingRoutine) { RoutineEditor(routine: $0) }
        }
    }
}

struct MedicinesCard: View {
    @EnvironmentObject var store: Store
    @Binding var editing: Medicine?
    var body: some View {
        Card(tint: .mind) {
            HStack { Eyebrow(text: "Medicamentos e produtos", icon: "pills.fill", color: .mind); Spacer(); Button { editing = Medicine(name: "") } label: { Image(systemName: "plus") }.tint(.mind) }
            let doses = store.doses()
            if doses.isEmpty { Text("Nada marcado para hoje.").font(.geist(13)).foregroundStyle(Color.soft) }
            ForEach(Array(doses.enumerated()), id: \.offset) { _, d in
                HStack {
                    Text(clock(d.minute)).font(.mono(12)).foregroundStyle(Color.faint)
                    VStack(alignment: .leading) {
                        Text(d.med.name).font(.geist(14, .medium))
                        Text([d.med.dose, d.med.how].filter { !$0.isEmpty }.joined(separator: " · ")).font(.geist(11.5)).foregroundStyle(Color.soft)
                    }
                    Spacer()
                    if let log = d.log { Chip(text: log.taken ? "tomado" : "saltado", color: log.taken ? .good : .faint) }
                    else {
                        Button("Saltar") { store.take(d.med, minute: d.minute, taken: false) }.font(.geist(12)).tint(.soft)
                        Button { store.take(d.med, minute: d.minute) } label: { Image(systemName: "checkmark.circle.fill").font(.geist(22)).foregroundStyle(Color.mind) }.buttonStyle(.plain)
                    }
                }
            }
            ForEach(store.all(Medicine.self)) { m in
                if let left = store.dosesLeft(m), Double(left.doses) <= m.refillAt {
                    Text("\(m.name): restam \(left.doses) doses, acaba a \(Day.date(left.runsOut).formatted(.dateTime.day().month())). Adicionado à lista de compras.").font(.geist(12)).foregroundStyle(Color.warn)
                }
            }
            NavigationLink { MedicinesList(editing: $editing) } label: { Text("Todos os produtos e histórico").font(.geist(13, .semibold)).foregroundStyle(Color.mind) }
        }
    }
}

struct MedicinesList: View {
    @EnvironmentObject var store: Store
    @Binding var editing: Medicine?
    var body: some View {
        List {
            ForEach(store.all(Medicine.self).sorted { $0.name < $1.name }) { m in
                Button { editing = m } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).foregroundStyle(Color.ink)
                        Text("\(m.times.map(clock).joined(separator: ", ")) · \(m.schedule.summary)" + (m.end.map { " · até \(Day.date($0).formatted(.dateTime.day().month()))" } ?? " · contínuo")).font(.caption).foregroundStyle(Color.soft)
                        if let a = store.adherence(m) { Text("Tomado em \(Int(a * 100))% dos últimos 30 dias").font(.caption2).foregroundStyle(a > 0.9 ? Color.good : Color.warn) }
                    }
                }
            }
            Section {
                ShareLink(item: medicineCSV(), preview: SharePreview("Histórico de medicamentos")) { Label("Exportar o histórico para o médico", systemImage: "square.and.arrow.up") }
            }
        }
        .cadenceList()
        .navigationTitle("Medicamentos")
    }

    private func medicineCSV() -> String {
        var rows = ["data,hora,produto,dose,tomado"]
        for log in store.all(MedLog.self).sorted(by: { ($0.date, $0.minute) < ($1.date, $1.minute) }) {
            let m = store.record(Medicine.self, log.medId)
            rows.append("\(log.date),\(clock(log.minute)),\(m?.name ?? "?"),\(m?.dose ?? ""),\(log.taken ? "sim" : "não")")
        }
        return rows.joined(separator: "\n")
    }
}

struct MedicineEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var med: Medicine
    @State private var newTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $med.name)
                    Picker("Tipo", selection: $med.kind) { ForEach(["medicine", "supplement", "skincare", "drops", "other"], id: \.self) { Text(medicineKindLabel($0)).tag($0) } }
                    TextField("Dose (ex.: 1 comprimido, 2 gotas)", text: $med.dose)
                    TextField("Como (com comida, em jejum…)", text: $med.how)
                    Toggle("Essencial (pergunta outra vez até responderes)", isOn: $med.mustDo)
                }
                Section("Horários") {
                    ForEach(med.times.sorted(), id: \.self) { t in Text(clock(t)).swipeActions { Button("Remover", role: .destructive) { med.times.removeAll { $0 == t } } } }
                    HStack { DatePicker("Adicionar", selection: $newTime, displayedComponents: .hourAndMinute); Button("Adicionar") { let m = Day.minuteOfDay(newTime); if !med.times.contains(m) { med.times.append(m) } } }
                }
                Section("Frequência") {
                    Picker("Repete", selection: $med.schedule.rule) { ForEach(Schedule.Rule.allCases, id: \.self) { Text($0.label).tag($0) } }
                    if med.schedule.rule == .everyNDays { Stepper("A cada \(med.schedule.every) dias", value: $med.schedule.every, in: 1...60) }
                    if med.schedule.rule == .weekdays {
                        HStack {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                                let on = med.schedule.weekdays.contains(wd)
                                Text(["D", "S", "T", "Q", "Q", "S", "S"][wd - 1]).frame(width: 32, height: 32).background(Circle().fill(on ? Color.mind : .white.opacity(0.08)))
                                    .onTapGesture { if on { med.schedule.weekdays.removeAll { $0 == wd } } else { med.schedule.weekdays.append(wd) } }
                            }
                        }
                    }
                    DatePicker("Começa", selection: Binding(get: { Day.date(med.start) }, set: { med.start = Day.key($0) }), displayedComponents: .date)
                    Toggle("Tratamento temporário", isOn: Binding(get: { med.end != nil }, set: { med.end = $0 ? Day.add(7, to: med.start) : nil }))
                    if med.end != nil { DatePicker("Acaba", selection: Binding(get: { Day.date(med.end ?? Day.today) }, set: { med.end = Day.key($0) }), displayedComponents: .date) }
                }
                Section("Stock") {
                    TextField("Unidades restantes (opcional)", value: $med.stock, format: .number).keyboardType(.decimalPad)
                    Stepper("\(kg(med.perDose)) por dose", value: $med.perDose, in: 0.5...10, step: 0.5)
                    Stepper("Avisar quando restarem \(Int(med.refillAt)) doses", value: $med.refillAt, in: 1...60)
                }
                if store.record(Medicine.self, med.id) != nil { Button("Apagar", role: .destructive) { store.remove(med); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(med.name.isEmpty ? "Novo produto" : med.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { med.times.sort(); store.save(med); Reminders.shared.reschedule(); dismiss() }.disabled(med.name.isEmpty || med.times.isEmpty) }
            }
        }
    }
}

struct RoutineEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var routine: CareRoutine
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $routine.title)
                ForEach($routine.steps) { $s in
                    HStack { TextField("Passo", text: $s.title); Stepper("\(s.seconds) s", value: $s.seconds, in: 5...900, step: 5).fixedSize() }
                }
                .onDelete { routine.steps.remove(atOffsets: $0) }
                .onMove { routine.steps.move(fromOffsets: $0, toOffset: $1) }
                Button("Adicionar passo") { routine.steps.append(RoutineStep(title: "", seconds: 30)) }
                if store.record(CareRoutine.self, routine.id) != nil { Button("Apagar rotina", role: .destructive) { store.remove(routine); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(routine.title.isEmpty ? "Nova rotina" : routine.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(routine); dismiss() }.disabled(routine.title.isEmpty) }
            }
        }
    }
}

/// One step of brushing: which teeth, which surface, how long, and how
struct BrushStep {
    var area: String // upper-right, upper-front, upper-left, lower-left, lower-front, lower-right, upper, lower, all
    var surface: String // outer, inner, chewing, all
    var seconds: Double
    var title: String
    var tip: String
}

enum BrushPlan: String, CaseIterable {
    case sextants, thorough, quadrants
    var label: String { ["sextants": "6 zonas · 2 min", "thorough": "12 passos · 2 min", "quadrants": "4 zonas · 2 min"][rawValue]! }

    var steps: [BrushStep] {
        let outer = "Cerdas a 45° da linha da gengiva, pequenos círculos suaves."
        let inner = "Inclina a escova, movimentos curtos ao longo das gengivas."
        let chew = "Para a frente e para trás nas superfícies de mastigação."
        switch self {
        case .quadrants:
            return [("upper-right", "Em cima à direita"), ("upper-left", "Em cima à esquerda"), ("lower-left", "Em baixo à esquerda"), ("lower-right", "Em baixo à direita")].map {
                BrushStep(area: $0.0, surface: "all", seconds: 30, title: $0.1, tip: "Por fora, por dentro e depois por cima. " + outer)
            }
        case .thorough:
            var out: [BrushStep] = []
            for (a, name) in [("upper-right", "Em cima à direita"), ("upper-left", "Em cima à esquerda"), ("lower-left", "Em baixo à esquerda"), ("lower-right", "Em baixo à direita")] {
                out.append(BrushStep(area: a, surface: "outer", seconds: 10, title: "\(name) · por fora", tip: outer))
                out.append(BrushStep(area: a, surface: "inner", seconds: 10, title: "\(name) · por dentro", tip: inner))
                out.append(BrushStep(area: a, surface: "chewing", seconds: 10, title: "\(name) · por cima", tip: chew))
            }
            return out
        case .sextants:
            return [("upper-right", "Em cima à direita"), ("upper-front", "Em cima à frente"), ("upper-left", "Em cima à esquerda"), ("lower-left", "Em baixo à esquerda"), ("lower-front", "Em baixo à frente"), ("lower-right", "Em baixo à direita")].map {
                BrushStep(area: $0.0, surface: "all", seconds: 20, title: $0.1, tip: $0.0.hasSuffix("front") ? "Escova na vertical a parte de trás dos dentes da frente. " + outer : "Por fora, por dentro e depois por cima. " + outer)
            }
        }
    }
}

/// Brushing mode: a tooth chart that lights the teeth and the surface to brush now, a vibration and chime at
/// each switch, then floss and mouthwash
struct BrushingView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("brushPlan2") private var planName = BrushPlan.sextants.rawValue
    @AppStorage("brushStart") private var startedAt = 0.0 // survives the screen locking and the view being rebuilt
    @AppStorage("brushFloss") private var floss = false
    @AppStorage("brushMouthwash") private var mouthwash = false
    @State private var now = Date()
    @State private var lastStep = -1
    private var start: Date? { startedAt > 0 ? Date(timeIntervalSince1970: startedAt) : nil }
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private var plan: BrushPlan { BrushPlan(rawValue: planName) ?? .sextants }
    private var steps: [BrushStep] { plan.steps }
    private var total: Double { steps.map(\.seconds).reduce(0, +) }
    private var elapsed: Double { start.map { now.timeIntervalSince($0) } ?? 0 }
    private var finished: Bool { start != nil && elapsed >= total }
    private var index: Int {
        var t = 0.0
        for (i, s) in steps.enumerated() { t += s.seconds; if elapsed < t { return i } }
        return steps.count - 1
    }
    private var stepLeft: Double {
        let end = steps.prefix(index + 1).map(\.seconds).reduce(0, +)
        return max(0, end - elapsed)
    }

    var body: some View {
        let step = start == nil || finished ? nil : steps[index]
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack { Spacer(); Button("Fechar") { clear(); dismiss() }.foregroundStyle(Color.soft) }
                Text(finished ? "Concluído" : step?.title ?? "Lavar os dentes").font(.geist(26, .bold))
                ToothChart(area: step?.area, surface: step?.surface, sextants: plan == .sextants).frame(maxHeight: 340)
                if let step {
                    Text(step.tip).font(.geist(14)).foregroundStyle(Color.soft).multilineTextAlignment(.center).frame(minHeight: 40)
                    HStack(spacing: 4) {
                        ForEach(steps.indices, id: \.self) { i in
                            Capsule().fill(i < index ? Color(hex: 0x5FE3D0) : i == index ? Color.ink : Color.white.opacity(0.12)).frame(height: 5)
                        }
                    }
                }
                Text(start == nil ? timeText(total) : finished ? "0:00" : timeText(stepLeft) + "  ·  " + timeText(total - elapsed) + " em falta")
                    .font(.system(size: start == nil ? 44 : 22, weight: .medium, design: .monospaced))
                if start == nil {
                    Picker("", selection: $planName) { ForEach(BrushPlan.allCases, id: \.self) { Text($0.label).tag($0.rawValue) } }.pickerStyle(.segmented)
                    PrimaryButton(title: "Começar") { startedAt = Date().timeIntervalSince1970; now = Date() }
                } else if finished {
                    Toggle("Fio dentário", isOn: $floss).tint(.mint)
                    Toggle("Elixir", isOn: $mouthwash).tint(.mint)
                    PrimaryButton(title: "Guardar") {
                        store.save(BrushLog(seconds: Int(total), floss: floss, mouthwash: mouthwash))
                        if let p = store.due().first(where: { $0.title.lowercased().contains("brush") && store.status($0) == nil && abs(store.time(of: $0) - Day.minuteOfDay()) < 180 }) { store.log(p, .done) }
                        clear()
                        dismiss()
                    }
                }
            }
            .padding(22)
        }
        .onReceive(timer) { t in
            now = t
            guard start != nil else { return }
            let i = finished ? steps.count : index
            if i != lastStep {
                if lastStep >= 0 { UINotificationFeedbackGenerator().notificationOccurred(.success); AudioServicesPlaySystemSound(1057) }
                lastStep = i
            }
        }
        // awake from opening until saved or closed, so the last two questions don't get lost behind the lock screen
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; now = Date(); if !BrushingView.pending { clear() } }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func clear() { startedAt = 0; floss = false; mouthwash = false }

    /// A session that was started and never saved, recent enough to come back to
    static var pending: Bool {
        let t = UserDefaults.standard.double(forKey: "brushStart")
        return t > 0 && Date().timeIntervalSince1970 - t < 20 * 60
    }

    private func timeText(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// A dental chart drawn like the body map: 16 teeth per arch along a U-shaped curve, sized by type (molars,
/// premolars, canine, incisors), seen as in a mirror. The teeth to brush light up; the outer or inner side gets a band.
struct ToothChart: View {
    var area: String?
    var surface: String?
    var sextants = true

    // From the middle to the back: 2 incisors, canine, 2 premolars, 3 molars (width, depth relative to a molar)
    private static let types: [(w: CGFloat, d: CGFloat)] = [(0.72, 0.55), (0.6, 0.55), (0.66, 0.82), (0.74, 0.9), (0.74, 0.9), (1, 1.05), (1, 1.05), (1, 1.05)]
    private static let sweep = 92.0 * Double.pi / 180

    private struct Tooth { var center: CGPoint; var angle: Double; var w: CGFloat; var d: CGFloat; var upper: Bool; var right: Bool; var index: Int; var normal: CGVector }

    private func point(_ t: Double, _ size: CGSize, upper: Bool) -> CGPoint {
        let rx = size.width * 0.31, ry = size.height * 0.33
        let y0 = upper ? size.height * 0.07 : size.height * 0.93
        let y = ry * CGFloat(1 - cos(t))
        return CGPoint(x: rx * CGFloat(sin(t)), y: upper ? y0 + y : y0 - y)
    }

    private func teeth(in size: CGSize) -> ([Tooth], CGFloat) {
        var out: [Tooth] = []
        var unit: CGFloat = 0
        for upper in [true, false] {
            var table: [(Double, CGFloat)] = [(0, 0)]
            var length: CGFloat = 0
            var prev = point(0, size, upper: upper)
            for i in 1...400 {
                let t = Self.sweep * Double(i) / 400
                let p = point(t, size, upper: upper)
                length += hypot(p.x - prev.x, p.y - prev.y)
                table.append((t, length))
                prev = p
            }
            let gap: CGFloat = 0.06
            let widths = Self.types.map { $0.w }.reduce(0, +)
            unit = length / (widths + gap * CGFloat(Self.types.count))
            for right in [true, false] {
                var s = gap * unit / 2
                for (k, type) in Self.types.enumerated() {
                    let w = type.w * unit, d = type.d * unit
                    let c = s + w / 2
                    s += w + gap * unit
                    let t = table.first { $0.1 >= c }?.0 ?? Self.sweep
                    let p = point(t, size, upper: upper), q = point(t + 0.002, size, upper: upper)
                    let sx: CGFloat = right ? 1 : -1 // mirror view: your right is on the right
                    let dx = sx * (q.x - p.x), dy = q.y - p.y
                    let len = max(0.0001, hypot(dx, dy))
                    var normal = CGVector(dx: -dy / len, dy: dx / len)
                    let inside = CGPoint(x: size.width / 2, y: upper ? size.height * 0.3 : size.height * 0.7)
                    let center = CGPoint(x: size.width / 2 + sx * p.x, y: p.y)
                    if (center.x - inside.x) * normal.dx + (center.y - inside.y) * normal.dy < 0 { normal = CGVector(dx: -normal.dx, dy: -normal.dy) }
                    out.append(Tooth(center: center, angle: atan2(Double(dy), Double(dx)), w: w, d: d, upper: upper, right: right, index: k, normal: normal))
                }
            }
        }
        return (out, unit)
    }

    private func active(_ t: Tooth) -> Bool {
        guard let area else { return false }
        let front = t.index <= 2 // incisors and canine
        let side = !sextants || !front // in six zones the side zones stop before the canines
        switch area {
        case "all": return true
        case "upper-right": return t.upper && t.right && side
        case "upper-left": return t.upper && !t.right && side
        case "lower-left": return !t.upper && !t.right && side
        case "lower-right": return !t.upper && t.right && side
        case "upper-front": return t.upper && front
        case "lower-front": return !t.upper && front
        default: return false
        }
    }

    private func place(_ rect: CGRect, corner: CGFloat, _ t: Tooth, offset: CGFloat = 0) -> Path {
        Path(roundedRect: rect, cornerRadius: corner)
            .applying(CGAffineTransform(rotationAngle: CGFloat(t.angle)))
            .applying(CGAffineTransform(translationX: t.center.x + t.normal.dx * offset, y: t.center.y + t.normal.dy * offset))
    }

    var body: some View {
        Canvas { ctx, size in
            let (list, unit) = teeth(in: size)
            let mint = Color(hex: 0x5FE3D0)
            for upper in [true, false] {
                var gum = Path()
                let steps = 60
                for i in 0...(2 * steps) {
                    let f = Double(i - steps) / Double(steps)
                    let p = point(abs(f) * Self.sweep, size, upper: upper)
                    let pt = CGPoint(x: size.width / 2 + (f < 0 ? -p.x : p.x), y: p.y)
                    if i == 0 { gum.move(to: pt) } else { gum.addLine(to: pt) }
                }
                ctx.stroke(gum, with: .color(Color(hex: 0x6E2D3E)), style: StrokeStyle(lineWidth: unit * 1.4, lineCap: .round, lineJoin: .round))
            }
            let kinds = ["incisor", "incisor", "canine", "premolar", "premolar", "molar", "molar", "molar"]
            var images: [String: GraphicsContext.ResolvedImage] = [:]
            for k in Set(kinds) {
                images[k] = ctx.resolve(Image("tooth-\(k)"))
                images[k + "-on"] = ctx.resolve(Image("tooth-\(k)-on"))
            }
            for t in list {
                let on = active(t)
                let sideOnly = surface == "inner" || surface == "outer"
                let name = kinds[t.index] + (on ? "-on" : "")
                if let img = images[name] {
                    ctx.drawLayer { layer in
                        layer.translateBy(x: t.center.x, y: t.center.y)
                        layer.rotate(by: .radians(t.angle))
                        if on && sideOnly { layer.opacity = 0.75 }
                        layer.draw(img, in: CGRect(x: -t.w * 0.66, y: -t.d * 0.66, width: t.w * 1.32, height: t.d * 1.32))
                    }
                }
                if on, sideOnly {
                    let dir: CGFloat = surface == "outer" ? 1 : -1
                    let band = place(CGRect(x: -t.w / 2, y: -3, width: t.w, height: 6), corner: 3, t, offset: dir * (t.d / 2 + 5))
                    ctx.fill(band, with: .color(mint))
                }
            }
            ctx.draw(Text("tua direita").font(.geist(11)).foregroundColor(Color.faint), at: CGPoint(x: size.width - 36, y: size.height / 2))
            ctx.draw(Text("tua esquerda").font(.geist(11)).foregroundColor(Color.faint), at: CGPoint(x: 34, y: size.height / 2))
            ctx.draw(Text("em cima").font(.geist(11)).foregroundColor(Color.faint), at: CGPoint(x: size.width / 2, y: size.height * 0.24))
            ctx.draw(Text("em baixo").font(.geist(11)).foregroundColor(Color.faint), at: CGPoint(x: size.width / 2, y: size.height * 0.76))
        }
        .aspectRatio(360.0 / 420.0, contentMode: .fit)
    }
}

/// Step-by-step routine player: a timer per step, the next step spoken aloud, a projected done-by time
struct RoutinePlayer: View {
    @Environment(\.dismiss) private var dismiss
    var routine: CareRoutine
    @State private var index = 0
    @State private var stepStart = Date()
    @State private var now = Date()
    @State private var paused: Date?
    @State private var speech = AVSpeechSynthesizer()
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        let step = routine.steps.indices.contains(index) ? routine.steps[index] : nil
        let left = step.map { Double($0.seconds) - (paused ?? now).timeIntervalSince(stepStart) } ?? 0
        let remaining = routine.steps.dropFirst(index + 1).map(\.seconds).reduce(0, +) + Int(max(0, left))
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack { Text(routine.title).font(.geist(15, .semibold)).foregroundStyle(Color.soft); Spacer(); Button("Fechar") { dismiss() }.foregroundStyle(Color.soft) }
                Spacer()
                if let step {
                    Text("Passo \(index + 1) de \(routine.steps.count)").font(.geist(13)).foregroundStyle(Color.soft)
                    Text(step.title).font(.geist(30, .bold)).multilineTextAlignment(.center)
                    ZStack {
                        Ring(progress: 1 - max(0, left) / Double(max(1, step.seconds)), area: .mint, width: 9)
                        Text(String(format: "%d:%02d", Int(max(0, left)) / 60, Int(max(0, left)) % 60)).font(.mono(36))
                    }
                    .frame(width: 200, height: 200)
                    Text("Termina às \(Date().addingTimeInterval(Double(remaining)).formatted(date: .omitted, time: .shortened))").font(.geist(13)).foregroundStyle(Color.soft)
                } else {
                    PipAnimation(mood: .celebrate).frame(width: 160, height: 160)
                    Text("Rotina concluída").font(.geist(26, .bold))
                }
                Spacer()
                HStack {
                    SoftButton(title: paused == nil ? "Pausa" : "Retomar") { if let p = paused { stepStart = stepStart.addingTimeInterval(Date().timeIntervalSince(p)); paused = nil } else { paused = Date() } }
                    SoftButton(title: "+30 s") { stepStart = stepStart.addingTimeInterval(30) }
                    SoftButton(title: "Saltar") { advance() }
                }
            }
            .padding(24)
        }
        .onAppear { say(routine.steps.first?.title) }
        .onReceive(timer) { t in
            now = t
            if paused == nil, let step, t.timeIntervalSince(stepStart) >= Double(step.seconds) { advance() }
        }
    }

    private func advance() {
        index += 1
        stepStart = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        say(routine.steps.indices.contains(index) ? "A seguir: " + routine.steps[index].title : "Tudo feito")
    }

    private func say(_ text: String?) {
        guard let text else { return }
        speech.speak(AVSpeechUtterance(string: text))
    }
}

/// One shower a day: that evening or the next morning. A finished gym session counts.
struct ShowerCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let covered = ShowerRules.covered(store.showerTimes)
        let week = (0..<7).reversed().map { Day.add(-$0, to: Day.today) }
        let yesterdayOpen = Day.minuteOfDay() < 12 * 60 && !covered.contains(Day.add(-1, to: Day.today))
        Card {
            HStack {
                Eyebrow(text: "Duche", icon: "shower.fill")
                Spacer()
                Text("\(week.dropLast().filter(covered.contains).count) dos últimos 6 dias").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            HStack(spacing: 6) {
                ForEach(week, id: \.self) { d in
                    VStack(spacing: 3) {
                        Circle().fill(covered.contains(d) ? Color.water : Color.white.opacity(0.08)).frame(width: 14, height: 14)
                        Text(Day.date(d).formatted(.dateTime.weekday(.narrow))).font(.geist(10)).foregroundStyle(Color.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement().accessibilityLabel("\(Day.date(d).formatted(.dateTime.weekday(.wide))): \(covered.contains(d) ? "duche tomado" : "sem duche")")
                }
            }
            if covered.contains(Day.today) {
                Text("Feito por hoje").font(.geist(14)).foregroundStyle(Color.good)
            } else if yesterdayOpen {
                Text("O duche de ontem ainda está em aberto: um esta manhã conta para ontem.").font(.geist(13.5))
            } else if let s = store.showerPlan() {
                Text(s.when == .tonight ? "Esta noite, por volta das \(clock(Day.minuteOfDay(s.at)))" : "Amanhã de manhã, por volta das \(clock(Day.minuteOfDay(s.at)))").font(.geist(14, .medium))
                Text(s.why).font(.geist(12)).foregroundStyle(Color.soft)
                Picker("Quando", selection: Binding(get: { s.when }, set: { store.pickShower($0) })) {
                    Text("Esta noite").tag(ShowerRules.When.tonight)
                    Text("Amanhã de manhã").tag(ShowerRules.When.morning)
                }
                .pickerStyle(.segmented)
            }
            if !covered.contains(Day.today) || yesterdayOpen {
                SoftButton(title: "Já tomei duche", icon: "checkmark") { store.logShower() }.accessibilityIdentifier("shower.log")
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("shower.card")
    }
}
