// Plan: the day as a timeline. Calendar events are fixed, blocks you place are never moved, and Cadence suggests
// the rest (deep work in your energy peak, the reading slot) for you to accept in one tap.
import SwiftUI

struct PlanItem: Identifiable {
    var id: String
    var minute: Int
    var end: Int?
    var title: String
    var detail: String
    var icon: String
    var color: Color
    var promise: PromiseItem?
    var block: PlanBlock?
    var event: CalendarEvent?
}

@MainActor
extension Store {
    func planItems(for day: String = Day.today) -> [PlanItem] {
        let plan = sleepPlan(for: day)
        var items: [PlanItem] = [
            PlanItem(id: "wake", minute: profile.wakeMinute, title: "Wake up", detail: "Daylight in the first hour sets tonight's sleep", icon: "sunrise.fill", color: .read),
            PlanItem(id: "wind", minute: plan.windDown, title: "Wind-down", detail: plan.after.map { "Once you're back from \($0.title) · brush, two pages, bed" } ?? "Screens away, lights low, reading slot", icon: "moon.fill", color: .sleep),
            PlanItem(id: "lights", minute: plan.perform, title: "Lights out", detail: "For \(duration(plan.need)) of sleep" + (plan.after.map { " · later than ideal because of \($0.title)" } ?? ""), icon: "bed.double.fill", color: .sleep),
            PlanItem(id: "kitchen", minute: plan.perform - 180, title: "Kitchen closes", detail: "Last meal 3 h before bed", icon: "fork.knife", color: .fuel),
            PlanItem(id: "caffeine", minute: plan.perform - 8 * 60, title: "Last caffeine", detail: "Cola, iced tea, energy drinks", icon: "cup.and.saucer.fill", color: .warn),
        ]
        for e in Agenda.shared.events(on: day) {
            items.append(PlanItem(id: "e" + e.id, minute: e.startMinute, end: e.endMinute, title: e.title, detail: "\(clock(e.startMinute))–\(clock(e.endMinute))" + (e.location.map { " · \($0)" } ?? ""), icon: "calendar", color: .water, event: e))
        }
        for b in all(PlanBlock.self).filter({ $0.date == day }) {
            let icon = ["deep": "brain.head.profile", "admin": "tray.full", "reading": "book.fill", "training": "dumbbell.fill"][b.type] ?? "square.fill"
            items.append(PlanItem(id: "b" + b.id, minute: b.start, end: b.start + b.minutes, title: b.title, detail: "\(duration(b.minutes)) · placed by you", icon: icon, color: .mint, block: b))
        }
        if let t = templates.first(where: { $0.weekdays.contains(Day.weekday(day)) }), !all(PlanBlock.self).contains(where: { $0.date == day && $0.type == "training" }) {
            // 18:00 unless a trip or event is in the way, then finished 15 minutes before it
            var start = 18 * 60
            if let b = busy(on: day).first(where: { $0.start < start + t.minutes + 15 && $0.end > start }) { start = max(profile.wakeMinute + 60, b.start - t.minutes - 15) }
            items.append(PlanItem(id: "train-" + t.id, minute: start, end: start + t.minutes, title: t.name, detail: "\(t.exercises.count) exercises · about \(duration(t.minutes)) · hold a block to move it", icon: "dumbbell.fill", color: .train))
        }
        for c in commutes(on: day) {
            items.append(PlanItem(id: "c" + c.id, minute: c.leave, end: c.arrive, title: "To \(c.title)", detail: "leave \(clock(c.leave)) · \(c.travel) min + \(c.buffer) buffer", icon: "tram.fill", color: Color(hex: 0x6CC4FF)))
        }
        for p in due(on: day) {
            let st = status(p, on: day)
            items.append(PlanItem(id: p.id, minute: time(of: p, on: day), title: p.title, detail: st == nil ? (time(of: p, on: day) > plan.perform && p.schedule.minute >= 240 ? "after lights out: change it in Promises" : p.kind == .mustDo ? "must-do" : p.schedule.summary) : st == .skipped ? "skipped" : "done", icon: p.icon, color: p.kind == .mustDo ? .warn : .mint, promise: p))
        }
        return items.sorted { ($0.minute < 240 ? $0.minute + 1440 : $0.minute) < ($1.minute < 240 ? $1.minute + 1440 : $1.minute) }
    }

    /// Placed blocks that now clash with a calendar event: Cadence suggests, you decide
    func clashes(on day: String = Day.today) -> [(PlanBlock, CalendarEvent)] {
        let events = Agenda.shared.events(on: day)
        return all(PlanBlock.self).filter { $0.date == day }.compactMap { b in
            events.first { $0.startMinute < b.start + b.minutes && $0.endMinute > b.start }.map { (b, $0) }
        }
    }
}

struct PlanView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var agenda = Agenda.shared
    @State private var placing: PlanBlock?
    @State private var focusing = false

    var body: some View {
        NavigationStack {
            Screen(glow: .water) {
                Title(eyebrow: store.tick.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Plan")
                    .padding(.top, 8)
                NowCard(focusing: $focusing)
                EnergyRibbon()
                weatherSuggestions
                suggestions
                ForEach(Array(store.clashes().enumerated()), id: \.offset) { _, pair in
                    let (block, event) = pair
                    Card(tint: .warn) {
                        Text("\(block.title) overlaps \(event.title).").font(.geist(14))
                        HStack {
                            SoftButton(title: "Move after it") { var b = block; b.start = event.endMinute + 10; store.save(b) }
                            SoftButton(title: "Keep both") {}
                        }
                    }
                }
                timeline
                if let e = agenda.error { Text(e).font(.geist(12)).foregroundStyle(Color.warn) }
                HStack(spacing: 10) {
                    NavigationLink { TasksView() } label: { tile("Tasks", "tray.full", "\(store.all(TaskItem.self).filter { !$0.done }.count) open") }
                    NavigationLink { ProjectsView() } label: { tile("Projects", "flag.fill", "\(store.all(Project.self).filter { !$0.archived }.count) active") }
                    NavigationLink { BooksView() } label: { tile("Reading", "book.fill", "\(store.readingMinutes()) min today") }
                    NavigationLink { TravelView() } label: { tile("Travel", "airplane", store.nextTrip.map { $0.destination } ?? "\(store.all(RegularTrip.self).count) regular") }
                }
                .buttonStyle(.plain)
            }
            .refreshable { await agenda.refresh(force: true) }
            .task { await agenda.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $placing) { BlockEditor(block: $0) }
            .fullScreenCover(isPresented: $focusing) { FocusView() }
        }
    }

    private func tile(_ title: String, _ icon: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(Color.mint)
            Text(title).font(.geist(14, .semibold))
            Text(detail).font(.geist(11)).foregroundStyle(Color.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.055)))
    }

    private var weatherSuggestions: some View {
        ForEach(store.weatherMoves(), id: \.0.id) { block, minute in
            Card(tint: .water) {
                Eyebrow(text: "Rain during \(block.title.lowercased())", icon: "cloud.rain.fill", color: .water)
                Text("Dry at \(clock(minute)). Move it there?").font(.geist(14))
                SoftButton(title: "Move to \(clock(minute))") { var b = block; b.start = minute; store.save(b) }
            }
        }
    }

    private var suggestions: some View {
        let hasDeep = store.all(PlanBlock.self).contains { $0.date == Day.today && $0.type == "deep" }
        let project = store.all(Project.self).filter { !$0.archived }.min { $0.deadline < $1.deadline }
        return Group {
            if !hasDeep, let start = store.suggestedDeepWork() {
                Card(tint: .mint) {
                    Eyebrow(text: "Suggested · your peak", icon: "sparkles", color: .mint)
                    Text("Deep work \(clock(start))–\(clock(start + 100))" + (project.map { ": \($0.title)" } ?? "")).font(.geist(15, .semibold))
                    HStack {
                        SoftButton(title: "Place it", icon: "plus") { store.save(PlanBlock(date: Day.today, start: start, minutes: 100, title: project.map { "Deep work · \($0.title)" } ?? "Deep work", type: "deep", projectId: project?.id)) }
                        SoftButton(title: "Choose time") { placing = PlanBlock(date: Day.today, start: start, minutes: 100, title: "Deep work", type: "deep", projectId: project?.id) }
                    }
                }
            }
        }
    }

    private var timeline: some View {
        let now = Day.minuteOfDay(store.tick)
        return Card {
            HStack {
                Eyebrow(text: "Today", icon: "calendar")
                Spacer()
                Button { placing = PlanBlock(date: Day.today, start: ((now + 30) / 15) * 15, minutes: 60, title: "", type: "deep") } label: { Label("Block", systemImage: "plus").font(.geist(13, .semibold)) }.tint(.mint)
            }
            ForEach(store.planItems()) { item in
                let end = item.end ?? item.minute
                let past = end < now && item.minute >= 240
                HStack(alignment: .top, spacing: 12) {
                    Text(clock(item.minute)).font(.mono(13, .semibold)).foregroundStyle(Color.soft).frame(width: 48, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 3, height: item.end == nil ? 18 : max(18, CGFloat(end - item.minute) / 3))
                    Image(systemName: item.icon).foregroundStyle(item.color).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.geist(14.5, .semibold))
                        Text(item.detail).font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer()
                    if let p = item.promise, store.status(p) == nil {
                        Button { store.log(p, .done) } label: { Image(systemName: "circle").font(.geist(20)).foregroundStyle(Color.soft) }
                    }
                    if let e = item.event, e.endMinute <= now, store.record(EventFeeling.self, e.id) == nil { FeelingButtons(event: e) }
                }
                .opacity(past ? 0.5 : 1)
                .padding(.vertical, 3)
                .contextMenu {
                    if let b = item.block {
                        Button("Edit", systemImage: "pencil") { placing = b }
                        Button("Remove", systemImage: "trash", role: .destructive) { store.remove(b) }
                    }
                }
            }
        }
    }
}

struct EventFeeling: Record, Equatable {
    static let kind = "feeling"
    var id: String
    var title: String
    var value: Int // -1 drained, 0 neutral, 1 energized
    var date = Day.today
}

/// "How did that feel?" after a calendar event, so the plan learns what costs you energy
struct FeelingButtons: View {
    @EnvironmentObject var store: Store
    var event: CalendarEvent
    var body: some View {
        HStack(spacing: 4) {
            ForEach([(-1, "battery.25"), (0, "battery.50"), (1, "battery.100.bolt")], id: \.0) { v, icon in
                Button { store.save(EventFeeling(id: event.id, title: event.title, value: v)) } label: { Image(systemName: icon).font(.geist(13)).foregroundStyle(v < 0 ? Color.warn : v > 0 ? Color.good : Color.soft) }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct EnergyRibbon: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let start = store.profile.wakeMinute, end = store.sleepPlan().perform
        let now = Day.minuteOfDay(store.tick)
        Card(padding: 12) {
            HStack { Eyebrow(text: "Energy today", icon: "bolt.fill"); Spacer(); Text(store.energy(at: now) > 0.7 ? "peak now" : store.energy(at: now) < 0.4 ? "dip: admin time" : "steady").font(.geist(12)).foregroundStyle(Color.soft) }
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                let steps = Array(stride(from: start, through: end, by: 10))
                ZStack(alignment: .topLeading) {
                    Path { p in
                        for (i, m) in steps.enumerated() {
                            let pt = CGPoint(x: w * CGFloat(m - start) / CGFloat(end - start), y: h * (1 - CGFloat(store.energy(at: m))))
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(LinearGradient(colors: [.read, .mint, .sleep], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    if now >= start && now <= end {
                        Circle().fill(Color.ink).frame(width: 8, height: 8)
                            .position(x: w * CGFloat(now - start) / CGFloat(end - start), y: h * (1 - CGFloat(store.energy(at: now))))
                    }
                }
            }
            .frame(height: 46)
            HStack { Text(clock(start)); Spacer(); Text("lights out \(clock(end))") }.font(.mono(10.5)).foregroundStyle(Color.faint)
        }
    }
}

/// The current block with a countdown ring, or the next one
struct NowCard: View {
    @EnvironmentObject var store: Store
    @Binding var focusing: Bool

    var body: some View {
        let now = Day.minuteOfDay(store.tick)
        let items = store.planItems().filter { $0.end != nil }
        let current = items.first { $0.minute <= now && ($0.end ?? 0) > now }
        let next = items.first { $0.minute > now }
        Card(tint: .mint) {
            if let f = store.activeFocus {
                Eyebrow(text: "Focusing", icon: "brain.head.profile", color: .mint)
                Text(f.intention).font(.geist(16, .bold))
                Button("Back to focus") { focusing = true }.font(.geist(14, .semibold)).tint(.mint)
            } else if let c = current {
                HStack(spacing: 14) {
                    let total = Double((c.end ?? now) - c.minute), done = Double(now - c.minute)
                    ZStack { Ring(progress: done / max(1, total), area: .mint, width: 6); Text(duration((c.end ?? now) - now)).font(.geist(11, .semibold)) }.frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Now", color: .mint)
                        Text(c.title).font(.geist(16, .bold))
                        if c.block?.type == "deep" || c.block?.type == "admin" { Button("Start focus") { focusing = true }.font(.geist(13, .semibold)).tint(.mint) }
                    }
                }
            } else {
                Eyebrow(text: "Next", color: .mint)
                Text(next.map { "\($0.title) at \(clock($0.minute))" } ?? "Nothing fixed: a good time to focus").font(.geist(15, .semibold))
                Button("Start a focus session") { focusing = true }.font(.geist(13, .semibold)).tint(.mint)
            }
        }
    }
}

struct BlockEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var block: PlanBlock
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("What", text: $block.title)
                Picker("Type", selection: $block.type) {
                    Text("Deep work").tag("deep"); Text("Admin").tag("admin"); Text("Reading").tag("reading"); Text("Training").tag("training"); Text("Other").tag("other")
                }
                DatePicker("Starts", selection: $time, displayedComponents: .hourAndMinute)
                Stepper("For \(duration(block.minutes))", value: $block.minutes, in: 15...300, step: 15)
                Picker("Project", selection: $block.projectId) {
                    Text("None").tag(String?.none)
                    ForEach(store.all(Project.self).filter { !$0.archived }) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            .cadenceList()
            .navigationTitle("Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        block.start = Day.minuteOfDay(time)
                        if block.title.isEmpty { block.title = block.type == "deep" ? "Deep work" : block.type.capitalized }
                        store.save(block)
                        dismiss()
                    }
                }
            }
            .onAppear { time = Day.at(block.start, on: block.date) }
        }
    }
}

struct TasksView: View {
    @EnvironmentObject var store: Store
    @State private var text = ""
    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Capture a task", text: $text).onSubmit(add)
                    Button("Add", action: add).disabled(text.isEmpty)
                }
            }
            Section("Open") {
                ForEach(store.all(TaskItem.self).filter { !$0.done }.sorted { $0.created > $1.created }) { t in
                    HStack {
                        Button { var x = t; x.done = true; store.save(x) } label: { Image(systemName: "circle") }.buttonStyle(.plain)
                        Text(t.title)
                        Spacer()
                        if let e = t.estimate { Text(duration(e)).font(.caption).foregroundStyle(Color.soft) }
                    }
                    .swipeActions {
                        Button("Top 3") {
                            var d = store.day()
                            if d.top3.count < 3 { d.top3.append(t.title); d.top3Done.append(false); store.save(d) }
                        }.tint(.mint)
                        Button("Delete", role: .destructive) { store.remove(t) }
                    }
                    .contextMenu {
                        ForEach([15, 30, 60, 120], id: \.self) { m in Button("About \(duration(m))") { var x = t; x.estimate = m; store.save(x) } }
                    }
                }
            }
            Section("Done") {
                ForEach(store.all(TaskItem.self).filter(\.done).sorted { $0.created > $1.created }.prefix(20)) { t in
                    Text(t.title).strikethrough().foregroundStyle(Color.soft).swipeActions { Button("Delete", role: .destructive) { store.remove(t) } }
                }
            }
        }
        .cadenceList()
        .navigationTitle("Tasks")
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.save(TaskItem(title: t))
        text = ""
    }
}
