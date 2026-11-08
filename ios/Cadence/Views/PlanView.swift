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
            PlanItem(id: "wake", minute: profile.wakeMinute, title: "Acordar", detail: "Luz do dia na primeira hora prepara o sono desta noite", icon: "sunrise.fill", color: .read),
            PlanItem(id: "wind", minute: plan.windDown, title: "Desacelerar", detail: plan.after.map { "Quando voltares de \($0.title) · dentes, duas páginas, cama" } ?? "Ecrãs de lado, luz baixa, tempo de leitura", icon: "moon.fill", color: .sleep),
            PlanItem(id: "lights", minute: plan.perform, title: "Apagar as luzes", detail: "Para \(duration(plan.need)) de sono" + (plan.after.map { " · mais tarde do que o ideal por causa de \($0.title)" } ?? ""), icon: "bed.double.fill", color: .sleep),
            PlanItem(id: "kitchen", minute: kitchenClose(on: day), title: "A cozinha fecha", detail: kitchenClose(on: day) > plan.perform - 180 ? "Mais tarde hoje: tempo para treinar, tomar duche e comer" : "Última refeição 3 h antes de deitar", icon: "fork.knife", color: .fuel),
            PlanItem(id: "caffeine", minute: plan.perform - 8 * 60, title: "Última cafeína", detail: "Cola, chá gelado, bebidas energéticas", icon: "cup.and.saucer.fill", color: .warn),
        ]
        for e in Agenda.shared.events(on: day) {
            items.append(PlanItem(id: "e" + e.id, minute: e.startMinute, end: e.endMinute, title: e.title, detail: "\(clock(e.startMinute))–\(clock(e.endMinute))" + (e.location.map { " · \($0)" } ?? ""), icon: "calendar", color: .water, event: e))
        }
        for b in all(PlanBlock.self).filter({ $0.date == day }) {
            let icon = ["deep": "brain.head.profile", "admin": "tray.full", "reading": "book.fill", "training": "dumbbell.fill"][b.type] ?? "square.fill"
            items.append(PlanItem(id: "b" + b.id, minute: b.start, end: b.start + b.minutes, title: b.title, detail: "\(duration(b.minutes)) · marcado por ti", icon: icon, color: .mint, block: b))
        }
        if let t = templates.first(where: { $0.weekdays.contains(Day.weekday(day)) }), !all(PlanBlock.self).contains(where: { $0.date == day && $0.type == "training" }) {
            let start = trainingSlot(on: day)?.start ?? 18 * 60
            items.append(PlanItem(id: "train-" + t.id, minute: start, end: start + t.minutes, title: t.name, detail: "\(t.exercises.count) exercícios · cerca de \(duration(t.minutes)) · mantém premido um bloco para o mover", icon: "dumbbell.fill", color: .train))
        }
        if let s = showerPlan(for: day), s.when == .tonight {
            items.append(PlanItem(id: "shower", minute: Day.minuteOfDay(s.at), title: "Duche", detail: s.why, icon: "shower.fill", color: .water))
        }
        for c in commutes(on: day) {
            items.append(PlanItem(id: "c" + c.id, minute: c.leave, end: c.arrive, title: "Para \(c.title)", detail: "sair às \(clock(c.leave)) · \(c.travel) min + \(c.buffer) de margem", icon: "tram.fill", color: Color(hex: 0x6CC4FF)))
        }
        for p in due(on: day) {
            let st = status(p, on: day)
            items.append(PlanItem(id: p.id, minute: time(of: p, on: day), title: p.title, detail: st == nil ? (time(of: p, on: day) > plan.perform && p.schedule.minute >= 240 ? "depois de apagar as luzes: muda-o em Hábitos" : p.kind == .mustDo ? "essencial" : p.schedule.summary) : st == .skipped ? "saltado" : "feito", icon: p.icon, color: p.kind == .mustDo ? .warn : .mint, promise: p))
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
                Title(eyebrow: store.tick.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Plano")
                    .accessibilityIdentifier("plan.screen") // <name>.screen: how the UI tests know this tab's root is showing. Internal, never translated; if a redesign removes this title, the identifier moves to the new one
                    .padding(.top, 8)
                NowCard(focusing: $focusing)
                EnergyRibbon()
                weatherSuggestions
                suggestions
                ForEach(Array(store.clashes().enumerated()), id: \.offset) { _, pair in
                    let (block, event) = pair
                    Card(tint: .warn) {
                        Text("\(block.title) sobrepõe-se a \(event.title).").font(.geist(14))
                        HStack {
                            SoftButton(title: "Mover para depois") { var b = block; b.start = event.endMinute + 10; store.save(b) }
                            SoftButton(title: "Manter os dois") {}
                        }
                    }
                }
                timeline
                if let e = agenda.error { Text(e).font(.geist(12)).foregroundStyle(Color.warn) }
                HStack(spacing: 10) {
                    NavigationLink { TasksView() } label: { tile("Tarefas", "tray.full", "\(store.all(TaskItem.self).filter { !$0.done }.count) por fazer") }
                    NavigationLink { ProjectsView() } label: { tile("Projetos", "flag.fill", ptCount(store.all(Project.self).filter { !$0.archived }.count, "ativo", "ativos")) }
                    NavigationLink { BooksView() } label: { tile("Leitura", "book.fill", "\(store.readingMinutes()) min hoje") }
                    NavigationLink { TravelView() } label: { tile("Viagens", "airplane", store.nextTrip.map { $0.destination } ?? ptCount(store.all(RegularTrip.self).count, "habitual", "habituais")) }
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
                Eyebrow(text: "Chuva durante \(block.title.lowercased())", icon: "cloud.rain.fill", color: .water)
                Text("Seco às \(clock(minute)). Mudar para essa hora?").font(.geist(14))
                SoftButton(title: "Mover para as \(clock(minute))") { var b = block; b.start = minute; store.save(b) }
            }
        }
    }

    private var suggestions: some View {
        let hasDeep = store.all(PlanBlock.self).contains { $0.date == Day.today && $0.type == "deep" }
        let project = store.all(Project.self).filter { !$0.archived }.min { $0.deadline < $1.deadline }
        return Group {
            if !hasDeep, let start = store.suggestedDeepWork() {
                Card(tint: .mint) {
                    Eyebrow(text: "Sugerido · o teu pico", icon: "sparkles", color: .mint)
                    Text("Trabalho focado \(clock(start))–\(clock(start + 100))" + (project.map { ": \($0.title)" } ?? "")).font(.geist(15, .semibold))
                    HStack {
                        SoftButton(title: "Adicionar ao plano", icon: "plus") { store.save(PlanBlock(date: Day.today, start: start, minutes: 100, title: project.map { "Trabalho focado · \($0.title)" } ?? "Trabalho focado", type: "deep", projectId: project?.id)) }
                        SoftButton(title: "Escolher hora") { placing = PlanBlock(date: Day.today, start: start, minutes: 100, title: "Trabalho focado", type: "deep", projectId: project?.id) }
                    }
                }
            }
        }
    }

    private var timeline: some View {
        let now = Day.minuteOfDay(store.tick)
        return Card {
            HStack {
                Eyebrow(text: "Hoje", icon: "calendar")
                Spacer()
                Button { placing = PlanBlock(date: Day.today, start: ((now + 30) / 15) * 15, minutes: 60, title: "", type: "deep") } label: { Label("Bloco", systemImage: "plus").font(.geist(13, .semibold)) }.tint(.mint)
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
                        Button("Editar", systemImage: "pencil") { placing = b }
                        Button("Remover", systemImage: "trash", role: .destructive) { store.remove(b) }
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
            HStack { Eyebrow(text: "Energia hoje", icon: "bolt.fill"); Spacer(); Text(store.energy(at: now) > 0.7 ? "pico agora" : store.energy(at: now) < 0.4 ? "quebra: trabalho administrativo" : "estável").font(.geist(12)).foregroundStyle(Color.soft) }
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
            HStack { Text(clock(start)); Spacer(); Text("luzes às \(clock(end))") }.font(.mono(10.5)).foregroundStyle(Color.faint)
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
                Eyebrow(text: "Em foco", icon: "brain.head.profile", color: .mint)
                Text(f.intention).font(.geist(16, .bold))
                Button("Voltar ao foco") { focusing = true }.font(.geist(14, .semibold)).tint(.mint)
            } else if let c = current {
                HStack(spacing: 14) {
                    let total = Double((c.end ?? now) - c.minute), done = Double(now - c.minute)
                    ZStack { Ring(progress: done / max(1, total), area: .mint, width: 6); Text(duration((c.end ?? now) - now)).font(.geist(11, .semibold)) }.frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Agora", color: .mint)
                        Text(c.title).font(.geist(16, .bold))
                        if c.block?.type == "deep" || c.block?.type == "admin" { Button("Começar foco") { focusing = true }.font(.geist(13, .semibold)).tint(.mint) }
                    }
                }
            } else {
                Eyebrow(text: "A seguir", color: .mint)
                Text(next.map { "\($0.title) às \(clock($0.minute))" } ?? "Nada marcado: boa altura para te focares").font(.geist(15, .semibold))
                Button("Começar uma sessão de foco") { focusing = true }.font(.geist(13, .semibold)).tint(.mint)
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
                TextField("O quê", text: $block.title)
                Picker("Tipo", selection: $block.type) { // the tags are stored values and stay; only the labels are Portuguese
                    Text("Trabalho focado").tag("deep"); Text("Trabalho administrativo").tag("admin"); Text("Leitura").tag("reading"); Text("Treino").tag("training"); Text("Outro").tag("other")
                }
                DatePicker("Começa", selection: $time, displayedComponents: .hourAndMinute)
                Stepper("Durante \(duration(block.minutes))", value: $block.minutes, in: 15...300, step: 15)
                Picker("Projeto", selection: $block.projectId) {
                    Text("Nenhum").tag(String?.none)
                    ForEach(store.all(Project.self).filter { !$0.archived }) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            .cadenceList()
            .navigationTitle("Bloco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        block.start = Day.minuteOfDay(time)
                        if block.title.isEmpty { block.title = ["deep": "Trabalho focado", "admin": "Trabalho administrativo", "reading": "Leitura", "training": "Treino", "other": "Outro"][block.type] ?? block.type.capitalized } // block.type is stored and stays; only the default title is Portuguese
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
                    TextField("Escreve uma tarefa", text: $text).onSubmit(add)
                    Button("Adicionar", action: add).disabled(text.isEmpty)
                }
            }
            Section("Por fazer") {
                ForEach(store.all(TaskItem.self).filter { !$0.done }.sorted { $0.created > $1.created }) { t in
                    HStack {
                        Button { var x = t; x.done = true; store.save(x) } label: { Image(systemName: "circle") }.buttonStyle(.plain)
                        Text(t.title)
                        Spacer()
                        if let e = t.estimate { Text(duration(e)).font(.caption).foregroundStyle(Color.soft) }
                    }
                    .swipeActions {
                        Button("Prioridade") {
                            var d = store.day()
                            if d.top3.count < 3 { d.top3.append(t.title); d.top3Done.append(false); store.save(d) }
                        }.tint(.mint)
                        Button("Apagar", role: .destructive) { store.remove(t) }
                    }
                    .contextMenu {
                        ForEach([15, 30, 60, 120], id: \.self) { m in Button("Cerca de \(duration(m))") { var x = t; x.estimate = m; store.save(x) } }
                    }
                }
            }
            Section("Feitas") {
                ForEach(store.all(TaskItem.self).filter(\.done).sorted { $0.created > $1.created }.prefix(20)) { t in
                    Text(t.title).strikethrough().foregroundStyle(Color.soft).swipeActions { Button("Apagar", role: .destructive) { store.remove(t) } }
                }
            }
        }
        .cadenceList()
        .navigationTitle("Tarefas")
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.save(TaskItem(title: t))
        text = ""
    }
}
