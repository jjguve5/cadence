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

/// Brushing mode: four 30-second zones (or six for 3 minutes), a vibration and chime at each switch
struct BrushingView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var zones = 4
    @State private var start: Date?
    @State private var now = Date()
    @State private var lastZone = -1
    @State private var floss = false
    @State private var mouthwash = false
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var elapsed: Double { start.map { now.timeIntervalSince($0) } ?? 0 }
    private var total: Double { Double(zones * 30) }
    private var zone: Int { min(zones - 1, Int(elapsed / 30)) }
    private var finished: Bool { elapsed >= total }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack { Spacer(); Button("Close") { dismiss() }.foregroundStyle(Color.soft) }
                Text(finished ? "Done" : start == nil ? "Brush" : zoneName).font(.system(size: 26, weight: .bold))
                MouthDiagram(zones: zones, current: start == nil || finished ? -1 : zone).frame(width: 220, height: 260)
                Text(start == nil ? "\(zones * 30 / 60):\(String(format: "%02d", zones * 30 % 60))" : String(format: "%d:%02d", Int(max(0, total - elapsed)) / 60, Int(max(0, total - elapsed)) % 60))
                    .font(.system(size: 44, weight: .medium, design: .monospaced))
                if start == nil {
                    Picker("", selection: $zones) { Text("2 min · 4 zones").tag(4); Text("3 min · 6 zones").tag(6) }.pickerStyle(.segmented)
                    PrimaryButton(title: "Start") { start = Date(); UIApplication.shared.isIdleTimerDisabled = true }
                } else if finished {
                    Toggle("Floss", isOn: $floss).tint(.mint)
                    Toggle("Mouthwash", isOn: $mouthwash).tint(.mint)
                    PrimaryButton(title: "Save") {
                        store.save(BrushLog(seconds: Int(total), floss: floss, mouthwash: mouthwash))
                        if let p = store.due().first(where: { $0.title.lowercased().contains("brush") && store.status($0) == nil && abs($0.schedule.minute - Day.minuteOfDay()) < 180 }) { store.log(p, .done) }
                        dismiss()
                    }
                }
            }
            .padding(24)
        }
        .onReceive(timer) { t in
            now = t
            guard start != nil else { return }
            if zone != lastZone || (finished && lastZone != zones) {
                if lastZone >= 0 { UINotificationFeedbackGenerator().notificationOccurred(.success); AudioServicesPlaySystemSound(1057) }
                lastZone = finished ? zones : zone
                if finished { UIApplication.shared.isIdleTimerDisabled = false }
            }
        }
    }

    private var zoneName: String {
        zones == 4 ? ["Upper right", "Upper left", "Lower left", "Lower right"][zone]
            : ["Upper right", "Upper front", "Upper left", "Lower left", "Lower front", "Lower right"][zone]
    }
}

struct MouthDiagram: View {
    var zones: Int
    var current: Int
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let per = zones / 2
            let r = w / 2 - 24
            let step = 180.0 / Double(per)
            // Clockwise from the upper right: the upper arch right to left, then the lower arch left to right
            for i in 0..<zones {
                var p = Path()
                if i < per {
                    let a1 = 360 - Double(i) * step, a0 = a1 - step
                    p.addArc(center: CGPoint(x: w / 2, y: h / 2 - 8), radius: r, startAngle: .degrees(a0 + 3), endAngle: .degrees(a1 - 3), clockwise: false)
                } else {
                    let j = i - per
                    let a1 = 180 - Double(j) * step, a0 = a1 - step
                    p.addArc(center: CGPoint(x: w / 2, y: h / 2 + 8), radius: r, startAngle: .degrees(a0 + 3), endAngle: .degrees(a1 - 3), clockwise: false)
                }
                let on = i == current
                ctx.stroke(p, with: .color(on ? Color.mint : Color.white.opacity(0.14)), style: StrokeStyle(lineWidth: on ? 30 : 24, lineCap: .round))
            }
        }
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
