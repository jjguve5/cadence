// Care screens: brushing mode, grooming freshness, the routine player, medicines and products.
import AVFoundation
import AudioToolbox
import SwiftUI

struct CareView: View {
    @EnvironmentObject var store: Store
    @State private var brushing = false
    @State private var playing: CareRoutine?
    @State private var editingMed: Medicine?
    @State private var editingRoutine: CareRoutine?

    var body: some View {
        Screen(glow: Color(hex: 0x5FE3D0)) {
            Card(tint: Color(hex: 0x5FE3D0)) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Brushing", icon: "mouth.fill", color: Color(hex: 0x5FE3D0))
                        let today = store.brushes()
                        Text(today.isEmpty ? "Not yet today" : "\(today.count)× today · \(today.map { duration($0.seconds / 60) }.joined(separator: ", "))").font(.system(size: 14))
                        if store.brushHeadDue { Text("3 months on this brush head: time for a new one.").font(.system(size: 12)).foregroundStyle(Color.warn) }
                    }
                    Spacer()
                    Button { brushing = true } label: { Image(systemName: "play.fill").foregroundStyle(Color(hex: 0x032018)).frame(width: 44, height: 44).background(Circle().fill(Color(hex: 0x5FE3D0))) }
                }
                if store.brushHeadDue { SoftButton(title: "Changed it", icon: "checkmark") { store.put("brushhead", Day.today, .bool(true)) } }
            }
            Card {
                Eyebrow(text: "Grooming", icon: "scissors")
                ForEach(store.all(GroomingItem.self).sorted { $0.freshness < $1.freshness }) { g in
                    HStack(spacing: 10) {
                        Image(systemName: g.icon).foregroundStyle(Color.soft).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(g.title).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(g.daysSince.map { "\($0) d ago · every ~\(g.rhythm)" } ?? "never logged").font(.system(size: 11.5)).foregroundStyle((g.daysSince ?? 999) >= g.rhythm ? Color.warn : Color.faint)
                            }
                            Bar(progress: g.freshness, area: g.freshness < 0.15 ? .fuel : .mint)
                        }
                        Button { var x = g; x.history.append(Day.today); store.save(x) } label: { Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(Color.mint) }.buttonStyle(.plain)
                    }
                }
                if let trip = store.nextTrip, !store.groomingBefore(trip).isEmpty {
                    Text("Trip to \(trip.destination) on \(Day.date(trip.start).formatted(.dateTime.weekday(.wide))): \(store.groomingBefore(trip).map { $0.title.lowercased() }.joined(separator: ", ")) the day before.").font(.system(size: 12.5)).foregroundStyle(Color.fuel)
                }
                Text("Starts from sensible intervals, then learns your own and flags drift.").font(.system(size: 11.5)).foregroundStyle(Color.faint)
            }
            Card {
                HStack { Eyebrow(text: "Routines", icon: "list.number"); Spacer(); Button { editingRoutine = CareRoutine(title: "", steps: []) } label: { Image(systemName: "plus") }.tint(.mint) }
                ForEach(store.all(CareRoutine.self).sorted { $0.title < $1.title }) { r in
                    HStack {
                        Image(systemName: r.icon).foregroundStyle(Color.soft).frame(width: 22)
                        VStack(alignment: .leading) { Text(r.title).font(.system(size: 14, weight: .medium)); Text("\(r.steps.count) steps · \(duration(r.steps.map(\.seconds).reduce(0, +) / 60))").font(.system(size: 11.5)).foregroundStyle(Color.faint) }
                        Spacer()
                        Button { editingRoutine = r } label: { Image(systemName: "pencil").foregroundStyle(Color.soft) }.buttonStyle(.plain)
                        Button { playing = r } label: { Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(Color.mint) }.buttonStyle(.plain)
                    }
                }
            }
            MedicinesCard(editing: $editingMed)
        }
        .navigationTitle("Care")
        .navigationBarTitleDisplayMode(.inline)
        .task { store.seedCare() }
        .fullScreenCover(isPresented: $brushing) { BrushingView() }
        .fullScreenCover(item: $playing) { RoutinePlayer(routine: $0) }
        .sheet(item: $editingMed) { MedicineEditor(med: $0) }
        .sheet(item: $editingRoutine) { RoutineEditor(routine: $0) }
    }
}

struct MedicinesCard: View {
    @EnvironmentObject var store: Store
    @Binding var editing: Medicine?
    var body: some View {
        Card(tint: .mind) {
            HStack { Eyebrow(text: "Medicines and products", icon: "pills.fill", color: .mind); Spacer(); Button { editing = Medicine(name: "") } label: { Image(systemName: "plus") }.tint(.mind) }
            let doses = store.doses()
            if doses.isEmpty { Text("Nothing scheduled today.").font(.system(size: 13)).foregroundStyle(Color.soft) }
            ForEach(Array(doses.enumerated()), id: \.offset) { _, d in
                HStack {
                    Text(clock(d.minute)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.faint)
                    VStack(alignment: .leading) {
                        Text(d.med.name).font(.system(size: 14, weight: .medium))
                        Text([d.med.dose, d.med.how].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11.5)).foregroundStyle(Color.soft)
                    }
                    Spacer()
                    if let log = d.log { Chip(text: log.taken ? "taken" : "skipped", color: log.taken ? .good : .faint) }
                    else {
                        Button("Skip") { store.take(d.med, minute: d.minute, taken: false) }.font(.system(size: 12)).tint(.soft)
                        Button { store.take(d.med, minute: d.minute) } label: { Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color.mind) }.buttonStyle(.plain)
                    }
                }
            }
            ForEach(store.all(Medicine.self)) { m in
                if let left = store.dosesLeft(m), Double(left.doses) <= m.refillAt {
                    Text("\(m.name): \(left.doses) doses left, runs out \(Day.date(left.runsOut).formatted(.dateTime.day().month())). Added to shopping.").font(.system(size: 12)).foregroundStyle(Color.warn)
                }
            }
            NavigationLink { MedicinesList(editing: $editing) } label: { Text("All products and history").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mind) }
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
                        Text("\(m.times.map(clock).joined(separator: ", ")) · \(m.schedule.summary)" + (m.end.map { " · until \(Day.date($0).formatted(.dateTime.day().month()))" } ?? " · ongoing")).font(.caption).foregroundStyle(Color.soft)
                        if let a = store.adherence(m) { Text("Taken \(Int(a * 100))% of the last 30 days").font(.caption2).foregroundStyle(a > 0.9 ? Color.good : Color.warn) }
                    }
                }
            }
            Section {
                ShareLink(item: medicineCSV(), preview: SharePreview("Medicine history")) { Label("Export history for a doctor", systemImage: "square.and.arrow.up") }
            }
        }
        .cadenceList()
        .navigationTitle("Medicines")
    }

    private func medicineCSV() -> String {
        var rows = ["date,time,product,dose,taken"]
        for log in store.all(MedLog.self).sorted(by: { ($0.date, $0.minute) < ($1.date, $1.minute) }) {
            let m = store.record(Medicine.self, log.medId)
            rows.append("\(log.date),\(clock(log.minute)),\(m?.name ?? "?"),\(m?.dose ?? ""),\(log.taken ? "yes" : "no")")
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
                    TextField("Name", text: $med.name)
                    Picker("Kind", selection: $med.kind) { ForEach(["medicine", "supplement", "skincare", "drops", "other"], id: \.self) { Text($0.capitalized).tag($0) } }
                    TextField("Dose (e.g. 1 tablet, 2 drops)", text: $med.dose)
                    TextField("How (with food, empty stomach…)", text: $med.how)
                    Toggle("Must-do (asks again until answered)", isOn: $med.mustDo)
                }
                Section("Times per day") {
                    ForEach(med.times.sorted(), id: \.self) { t in Text(clock(t)).swipeActions { Button("Remove", role: .destructive) { med.times.removeAll { $0 == t } } } }
                    HStack { DatePicker("Add", selection: $newTime, displayedComponents: .hourAndMinute); Button("Add") { let m = Day.minuteOfDay(newTime); if !med.times.contains(m) { med.times.append(m) } } }
                }
                Section("Schedule") {
                    Picker("Repeats", selection: $med.schedule.rule) { ForEach(Schedule.Rule.allCases, id: \.self) { Text($0.label).tag($0) } }
                    if med.schedule.rule == .everyNDays { Stepper("Every \(med.schedule.every) days", value: $med.schedule.every, in: 1...60) }
                    if med.schedule.rule == .weekdays {
                        HStack {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                                let on = med.schedule.weekdays.contains(wd)
                                Text(["S", "M", "T", "W", "T", "F", "S"][wd - 1]).frame(width: 32, height: 32).background(Circle().fill(on ? Color.mind : .white.opacity(0.08)))
                                    .onTapGesture { if on { med.schedule.weekdays.removeAll { $0 == wd } } else { med.schedule.weekdays.append(wd) } }
                            }
                        }
                    }
                    DatePicker("Starts", selection: Binding(get: { Day.date(med.start) }, set: { med.start = Day.key($0) }), displayedComponents: .date)
                    Toggle("Temporary course", isOn: Binding(get: { med.end != nil }, set: { med.end = $0 ? Day.add(7, to: med.start) : nil }))
                    if med.end != nil { DatePicker("Ends", selection: Binding(get: { Day.date(med.end ?? Day.today) }, set: { med.end = Day.key($0) }), displayedComponents: .date) }
                }
                Section("Stock") {
                    TextField("Units left (optional)", value: $med.stock, format: .number).keyboardType(.decimalPad)
                    Stepper("\(kg(med.perDose)) per dose", value: $med.perDose, in: 0.5...10, step: 0.5)
                    Stepper("Remind at \(Int(med.refillAt)) doses left", value: $med.refillAt, in: 1...60)
                }
                if store.record(Medicine.self, med.id) != nil { Button("Delete", role: .destructive) { store.remove(med); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(med.name.isEmpty ? "New product" : med.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { med.times.sort(); store.save(med); Reminders.shared.reschedule(); dismiss() }.disabled(med.name.isEmpty || med.times.isEmpty) }
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
                TextField("Name", text: $routine.title)
                ForEach($routine.steps) { $s in
                    HStack { TextField("Step", text: $s.title); Stepper("\(s.seconds) s", value: $s.seconds, in: 5...900, step: 5).fixedSize() }
                }
                .onDelete { routine.steps.remove(atOffsets: $0) }
                .onMove { routine.steps.move(fromOffsets: $0, toOffset: $1) }
                Button("Add step") { routine.steps.append(RoutineStep(title: "", seconds: 30)) }
                if store.record(CareRoutine.self, routine.id) != nil { Button("Delete routine", role: .destructive) { store.remove(routine); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(routine.title.isEmpty ? "New routine" : routine.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(routine); dismiss() }.disabled(routine.title.isEmpty) }
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
    case quadrants, thorough, sextants
    var label: String { ["quadrants": "2 min · 4 zones", "thorough": "2 min · 12 steps", "sextants": "3 min · 6 zones"][rawValue]! }

    var steps: [BrushStep] {
        let outer = "Bristles at 45° to the gumline, small gentle circles."
        let inner = "Tilt the brush, short strokes along the gums."
        let chew = "Scrub back and forth over the tops."
        switch self {
        case .quadrants:
            return [("upper-right", "Upper right"), ("upper-left", "Upper left"), ("lower-left", "Lower left"), ("lower-right", "Lower right")].map {
                BrushStep(area: $0.0, surface: "all", seconds: 30, title: $0.1, tip: "Outside, inside, then the tops. " + outer)
            }
        case .thorough:
            var out: [BrushStep] = []
            for (a, name) in [("upper-right", "Upper right"), ("upper-left", "Upper left"), ("lower-left", "Lower left"), ("lower-right", "Lower right")] {
                out.append(BrushStep(area: a, surface: "outer", seconds: 10, title: "\(name) · outside", tip: outer))
                out.append(BrushStep(area: a, surface: "inner", seconds: 10, title: "\(name) · inside", tip: inner))
                out.append(BrushStep(area: a, surface: "chewing", seconds: 10, title: "\(name) · tops", tip: chew))
            }
            return out
        case .sextants:
            return [("upper-right", "Upper right"), ("upper-front", "Upper front"), ("upper-left", "Upper left"), ("lower-left", "Lower left"), ("lower-front", "Lower front"), ("lower-right", "Lower right")].map {
                BrushStep(area: $0.0, surface: "all", seconds: 30, title: $0.1, tip: $0.0.hasSuffix("front") ? "Brush upright for the backs of the front teeth. " + outer : "Outside, inside, then the tops. " + outer)
            }
        }
    }
}

/// Brushing mode: a tooth chart that lights the teeth and the surface to brush now, a vibration and chime at
/// each switch, then floss and mouthwash
struct BrushingView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("brushPlan") private var planName = BrushPlan.thorough.rawValue
    @State private var start: Date?
    @State private var now = Date()
    @State private var lastStep = -1
    @State private var floss = false
    @State private var mouthwash = false
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private var plan: BrushPlan { BrushPlan(rawValue: planName) ?? .thorough }
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
                HStack { Spacer(); Button("Close") { dismiss() }.foregroundStyle(Color.soft) }
                Text(finished ? "Done" : step?.title ?? "Brush").font(.system(size: 26, weight: .bold))
                ToothChart(area: step?.area, surface: step?.surface).frame(maxHeight: 340)
                if let step {
                    Text(step.tip).font(.system(size: 14)).foregroundStyle(Color.soft).multilineTextAlignment(.center).frame(minHeight: 40)
                    HStack(spacing: 4) {
                        ForEach(steps.indices, id: \.self) { i in
                            Capsule().fill(i < index ? Color(hex: 0x5FE3D0) : i == index ? Color.ink : Color.white.opacity(0.12)).frame(height: 5)
                        }
                    }
                }
                Text(start == nil ? timeText(total) : finished ? "0:00" : timeText(stepLeft) + "  ·  " + timeText(total - elapsed) + " left")
                    .font(.system(size: start == nil ? 44 : 22, weight: .medium, design: .monospaced))
                if start == nil {
                    Picker("", selection: $planName) { ForEach(BrushPlan.allCases, id: \.self) { Text($0.label).tag($0.rawValue) } }.pickerStyle(.segmented)
                    PrimaryButton(title: "Start") { start = Date(); UIApplication.shared.isIdleTimerDisabled = true }
                } else if finished {
                    Toggle("Floss", isOn: $floss).tint(.mint)
                    Toggle("Mouthwash", isOn: $mouthwash).tint(.mint)
                    PrimaryButton(title: "Save") {
                        store.save(BrushLog(seconds: Int(total), floss: floss, mouthwash: mouthwash))
                        if let p = store.due().first(where: { $0.title.lowercased().contains("brush") && store.status($0) == nil && abs(store.time(of: $0) - Day.minuteOfDay()) < 180 }) { store.log(p, .done) }
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
                if finished { UIApplication.shared.isIdleTimerDisabled = false }
            }
        }
    }

    private func timeText(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// A dental chart drawn like the body map: 16 teeth per arch along a U-shaped curve, sized by type (molars,
/// premolars, canine, incisors), seen as in a mirror. The teeth to brush light up; the outer or inner side gets a band.
struct ToothChart: View {
    var area: String?
    var surface: String?
    var sextants = UserDefaults.standard.string(forKey: "brushPlan") == BrushPlan.sextants.rawValue

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
            for t in list {
                let on = active(t)
                let shape = place(CGRect(x: -t.w / 2, y: -t.d / 2, width: t.w, height: t.d), corner: min(t.w, t.d) * 0.32, t)
                let sideOnly = surface == "inner" || surface == "outer"
                let fill = on ? (sideOnly ? Color(hex: 0xDFF7F2) : mint) : Color(hex: 0xF4EFE6)
                ctx.fill(shape, with: .color(fill))
                ctx.stroke(shape, with: .color(on ? mint : Color(hex: 0x3C3240)), lineWidth: on ? 2 : 1)
                if t.index >= 3 {
                    let groove = place(CGRect(x: -t.w * 0.28, y: -0.75, width: t.w * 0.56, height: 1.5), corner: 0.75, t)
                    ctx.fill(groove, with: .color(Color(hex: 0x3C3240, opacity: 0.35)))
                }
                if on, sideOnly {
                    let dir: CGFloat = surface == "outer" ? 1 : -1
                    let band = place(CGRect(x: -t.w / 2, y: -3, width: t.w, height: 6), corner: 3, t, offset: dir * (t.d / 2 + 5))
                    ctx.fill(band, with: .color(mint))
                }
            }
            ctx.draw(Text("your right").font(.system(size: 11)).foregroundColor(Color.faint), at: CGPoint(x: size.width - 36, y: size.height / 2))
            ctx.draw(Text("your left").font(.system(size: 11)).foregroundColor(Color.faint), at: CGPoint(x: 34, y: size.height / 2))
            ctx.draw(Text("upper").font(.system(size: 11)).foregroundColor(Color.faint), at: CGPoint(x: size.width / 2, y: size.height * 0.24))
            ctx.draw(Text("lower").font(.system(size: 11)).foregroundColor(Color.faint), at: CGPoint(x: size.width / 2, y: size.height * 0.76))
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
                HStack { Text(routine.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.soft); Spacer(); Button("Close") { dismiss() }.foregroundStyle(Color.soft) }
                Spacer()
                if let step {
                    Text("Step \(index + 1) of \(routine.steps.count)").font(.system(size: 13)).foregroundStyle(Color.soft)
                    Text(step.title).font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
                    ZStack {
                        Ring(progress: 1 - max(0, left) / Double(max(1, step.seconds)), area: .mint, width: 9)
                        Text(String(format: "%d:%02d", Int(max(0, left)) / 60, Int(max(0, left)) % 60)).font(.system(size: 36, design: .monospaced))
                    }
                    .frame(width: 200, height: 200)
                    Text("Done by \(Date().addingTimeInterval(Double(remaining)).formatted(date: .omitted, time: .shortened))").font(.system(size: 13)).foregroundStyle(Color.soft)
                } else {
                    PipAnimation(mood: .celebrate).frame(width: 160, height: 160)
                    Text("Routine done").font(.system(size: 26, weight: .bold))
                }
                Spacer()
                HStack {
                    SoftButton(title: paused == nil ? "Pause" : "Resume") { if let p = paused { stepStart = stepStart.addingTimeInterval(Date().timeIntervalSince(p)); paused = nil } else { paused = Date() } }
                    SoftButton(title: "+30 s") { stepStart = stepStart.addingTimeInterval(30) }
                    SoftButton(title: "Skip") { advance() }
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
        say(routine.steps.indices.contains(index) ? "Next: " + routine.steps[index].title : "All done")
    }

    private func say(_ text: String?) {
        guard let text else { return }
        speech.speak(AVSpeechUtterance(string: text))
    }
}
