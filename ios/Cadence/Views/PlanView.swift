// Plan: the day as a timeline. Calendar events are fixed, blocks you place are never moved, and Cadence suggests
// the rest (deep work in your energy peak, the reading slot) for you to accept in one tap.
// Phase 2.8 (design v17: N_Plano, N_PlanoConflito, N_PlanoReorganizar, N_PlanoMes, N_PlanoNovoEvento): Dia, Semana
// and Mês, the day's load in one line, conflicts with the training too (only what Cadence placed moves, with
// Desfazer; Google events never change), and new events from one line that are Cadence's own (decision D2). The
// end-of-day review (N_PlanoFimDoDia) is in CloseDayView.swift; the rules are in Time.swift.
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
            let skipped = logs["\(p.id)|\(day)"]?.notApplicable == true ? "não se aplica" : "saltado" // phase 2.8: «Não se aplica» is a skip with a flag
            items.append(PlanItem(id: p.id, minute: time(of: p, on: day), title: p.title, detail: st == nil ? (time(of: p, on: day) > plan.perform && p.schedule.minute >= 240 ? "depois de apagar as luzes: muda-o em Hábitos" : p.kind == .mustDo ? "essencial" : p.schedule.summary) : st == .skipped ? skipped : "feito", icon: p.icon, color: p.kind == .mustDo ? .warn : .mint, promise: p))
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

/// Something Cadence placed (a block, an event you created in Cadence, or the day's training) that overlaps an event
struct PlanConflict: Identifiable, Equatable {
    var id: String
    var day: String
    var title: String
    var span: PlanSpan
    /// What moves. nil is the training from your plan (a template), which becomes a training block when it's moved.
    var block: PlanBlock?
    var training: Bool
    var other: String
    var otherSpan: PlanSpan
    /// The other side is in the Google calendar, which the app never changes; otherwise it's yours, in Cadence
    var otherIsGoogle: Bool
    var overlap: Int { PlanRules.overlap(span, otherSpan) }
    /// When the clash starts
    var at: Int { max(span.start, otherSpan.start) }
}

@MainActor
extension Store {
    /// The training from your plan on a day when nothing stands in for it: no training block and no session that day
    func templateTraining(on day: String) -> (template: WorkoutTemplate, span: PlanSpan)? {
        guard let t = templates.first(where: { $0.weekdays.contains(Day.weekday(day)) }),
              !all(PlanBlock.self).contains(where: { $0.date == day && $0.type == "training" }),
              sessions(on: day).isEmpty,
              let slot = trainingSlot(on: day) else { return nil }
        return (t, PlanSpan(start: slot.start, end: slot.end))
    }

    /// What Cadence placed that overlaps something else that day (phase 2.8): any block against a calendar event (as
    /// clashes() always did), and the training too, a block or from your plan, against a calendar event or one of your
    /// own blocks and events in Cadence. Only the Cadence side is ever offered a new time.
    func planConflicts(on day: String, events: [CalendarEvent]? = nil) -> [PlanConflict] {
        let calendar = (events ?? Agenda.shared.events(on: day)).map { (title: $0.title, span: PlanSpan(start: $0.startMinute, end: $0.endMinute)) }
        let blocks = all(PlanBlock.self).filter { $0.date == day }.sorted { $0.start < $1.start }
        let mine = blocks.filter { $0.type != "training" }.map { (title: $0.title, span: PlanSpan(start: $0.start, end: $0.start + $0.minutes)) }
        func clash(_ span: PlanSpan, _ list: [(title: String, span: PlanSpan)]) -> (title: String, span: PlanSpan)? {
            list.first { PlanRules.overlap(span, $0.span) > 0 }
        }
        var out: [PlanConflict] = []
        for b in blocks {
            let span = PlanSpan(start: b.start, end: b.start + b.minutes)
            if let e = clash(span, calendar) {
                out.append(PlanConflict(id: "block:\(b.id)", day: day, title: b.title, span: span, block: b, training: b.type == "training", other: e.title, otherSpan: e.span, otherIsGoogle: true))
            } else if b.type == "training", let o = clash(span, mine) {
                out.append(PlanConflict(id: "block:\(b.id)", day: day, title: b.title, span: span, block: b, training: true, other: o.title, otherSpan: o.span, otherIsGoogle: false))
            }
        }
        if let t = templateTraining(on: day) {
            if let e = clash(t.span, calendar) {
                out.append(PlanConflict(id: "train:\(day)", day: day, title: t.template.name, span: t.span, block: nil, training: true, other: e.title, otherSpan: e.span, otherIsGoogle: true))
            } else if let o = clash(t.span, mine) {
                out.append(PlanConflict(id: "train:\(day)", day: day, title: t.template.name, span: t.span, block: nil, training: true, other: o.title, otherSpan: o.span, otherIsGoogle: false))
            }
        }
        return out
    }

    /// Other times for it that day, nearest first (PlanRules.alternatives): from an hour after waking (and not before
    /// now, today) to the wind-down, around calendar events, regular trips and everything else Cadence placed, keeping 15
    /// minutes either side of a training (as the training slot does) and 10 around a block. None for a day gone by.
    func planAlternatives(for c: PlanConflict, events: [CalendarEvent]? = nil, today: String = Day.today, minute: Int? = nil) -> [PlanAlternative] {
        guard c.day >= today else { return [] }
        var busy = (events ?? Agenda.shared.events(on: c.day)).map { PlanSpan(start: $0.startMinute, end: $0.endMinute) }
        busy += commutes(on: c.day).map { PlanSpan(start: $0.leave, end: $0.arrive) }
        busy += all(PlanBlock.self).filter { $0.date == c.day && $0.id != c.block?.id }.map { PlanSpan(start: $0.start, end: $0.start + $0.minutes) }
        if !c.training, let t = trainingSlot(on: c.day) { busy.append(PlanSpan(start: t.start, end: t.end)) }
        var from = profile.wakeMinute + 60
        if c.day == today { from = max(from, minute ?? Clock.minute()) }
        return PlanRules.alternatives(length: c.span.minutes, original: c.span.start, busy: busy, from: from, to: sleepPlan(for: c.day).windDown, margin: c.training ? 15 : 10)
    }

    /// The block as it would be at the new time: a copy, nothing saved (the training from your plan becomes a block)
    func proposedBlock(_ c: PlanConflict, start: Int) -> PlanBlock {
        if var b = c.block {
            b.start = start
            return b
        }
        return PlanBlock(date: c.day, start: start, minutes: c.span.minutes, title: c.title, type: "training")
    }

    /// «Aplicar»: moves only what Cadence placed; the event it clashed with never changes, and the training plan itself
    /// stays as it is. Returns how to undo it (the block as it was, or no block).
    func applyAlternative(_ c: PlanConflict, start: Int) -> () -> Void {
        let placed = proposedBlock(c, start: start)
        let before = c.block
        save(placed)
        return { [weak self] in
            guard let self else { return }
            if let before { self.save(before) } else { self.remove(placed) }
        }
    }

    /// The day's load (decision 2.8): calendar events, Cadence's blocks and events, and the training, against the
    /// hours from waking to lights out
    func dayLoad(on day: String, events: [CalendarEvent]? = nil) -> DayLoad {
        let calendar = (events ?? Agenda.shared.events(on: day)).map { PlanSpan(start: $0.startMinute, end: $0.endMinute) }
        let blocks = all(PlanBlock.self).filter { $0.date == day && $0.type != "training" }.map { PlanSpan(start: $0.start, end: $0.start + $0.minutes) }
        let training = trainingSlot(on: day).map { PlanSpan(start: $0.start, end: $0.end) }
        return PlanRules.load(events: calendar, blocks: blocks, training: training, wake: profile.wakeMinute, lightsOut: sleepPlan(for: day).perform)
    }

    func trainingPlanned(on day: String) -> Bool {
        templates.contains { $0.weekdays.contains(Day.weekday(day)) } || all(PlanBlock.self).contains { $0.date == day && $0.type == "training" }
    }

    func trainingLogged(on day: String) -> Bool { sessions(on: day).contains { $0.end != nil } }

    /// What marks the month grid as a commitment: calendar events that don't repeat every day, and your blocks and events
    func planCommitments(on day: String, repeating: Set<String>, events: [CalendarEvent]? = nil) -> Int {
        let calendar = (events ?? Agenda.shared.events(on: day)).filter { !repeating.contains(PlanRules.repeatKey($0)) }.count
        let mine = all(PlanBlock.self).filter { $0.date == day && $0.type != "training" }.count
        return calendar + mine
    }

    /// A day of the month grid: its marks, how full it is, and its conflicts (from today on). A conflict with another
    /// time to offer is a suggestion, until you keep it as it is.
    func monthDay(_ day: String, today: String = Day.today, repeating: Set<String>, kept: Set<String>) -> (marks: [PlanMark], level: Int, conflicts: [PlanConflict]) {
        let conflicts = day >= today ? planConflicts(on: day) : []
        let suggestions = conflicts.filter { !kept.contains($0.id) && !planAlternatives(for: $0, today: today).isEmpty }.count
        let marks = PlanRules.marks(trainingPlanned: trainingPlanned(on: day), trainingLogged: trainingLogged(on: day), past: day < today,
                                    commitments: planCommitments(on: day, repeating: repeating), suggestions: suggestions)
        return (marks, dayLoad(on: day).level, conflicts)
    }
}

/// Dia, Semana or Mês (the stored value is this view's own, on this iPhone)
enum PlanMode: String {
    case day, week, month
    /// Where the choice is kept (UserDefaults: a per-iPhone view preference, not data). UI tests keep their own, so a
    /// test never meets the one left on the phone (PlanSeeds clears it for each Plano test).
    static let key = TestMode.active ? "plan.view.uitest" : "plan.view"
}

struct PlanView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var agenda = Agenda.shared
    @State private var placing: PlanBlock?
    @State private var focusing = false
    /// Opens in Dia (decision 2.8); a view you choose stays until you change it. A per-iPhone view preference, not data.
    @AppStorage(PlanMode.key) private var modeRaw = PlanMode.day.rawValue
    @State private var chosenDay: String? // the day shown in Dia, or a day of the week shown in Semana; nil is today
    @State private var chosenMonth: String? // the first day of the month shown; nil is this month
    @State private var picked: String? // the day chosen in the month; nil is today
    @State private var kept: Set<String> = [] // conflicts kept as they are («Manter assim», «Ignorar»): still shown, with no proposal, and no mark saved
    @State private var showingOthers: Set<String> = []
    @State private var loadOpen = false
    @State private var creating = false
    @State private var reviewing = false

    private var mode: PlanMode { PlanMode(rawValue: modeRaw) ?? .day }
    private var modeBinding: Binding<PlanMode> { Binding(get: { mode }, set: { modeRaw = $0.rawValue }) }

    var body: some View {
        let today = Day.today
        let now = TestMode.minute ?? Day.minuteOfDay(store.tick)
        NavigationStack {
            Screen(glow: .water) {
                Title(eyebrow: store.tick.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Plano")
                    .accessibilityIdentifier("plan.screen") // <name>.screen: how the UI tests know this tab's root is showing. Internal, never translated; if a redesign removes this title, the identifier moves to the new one
                    .padding(.top, 8)
                Segments(options: [(PlanMode.day, "Dia"), (PlanMode.week, "Semana"), (PlanMode.month, "Mês")], selection: modeBinding)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("plan.views")
                switch mode {
                case .day: dayView(today: today, now: now)
                case .week: weekView(today: today)
                case .month: monthView(today: today)
                }
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

    /// Opens a day in Dia (from a row of the week, the month's «Abrir o dia» or a conflict)
    private func openDay(_ day: String, today: String) {
        chosenDay = day == today ? nil : day
        modeRaw = PlanMode.day.rawValue
    }

    // MARK: Dia (N_Plano, N_PlanoConflito)

    @ViewBuilder private func dayView(today: String, now: Int) -> some View {
        let day = chosenDay ?? today
        let isToday = day == today
        VStack(alignment: .leading, spacing: 12) {
            PeriodNav(title: PlanFormat.relative(day, today: today), away: !isToday, prevLabel: "Dia anterior", nextLabel: "Dia seguinte",
                      prev: { chosenDay = Day.add(-1, to: day) }, next: { chosenDay = Day.add(1, to: day) }, home: { chosenDay = nil })
            if isToday {
                NowCard(focusing: $focusing)
                EnergyRibbon()
                weatherSuggestions
                suggestions
            }
            loadLine(day)
            if day >= today {
                ForEach(store.planConflicts(on: day)) { c in conflictCards(c, today: today) }
            }
            timeline(day, isToday: isToday, now: now)
            dayActions(day, today: today)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.day")
    }

    /// The day's load in one line, under the calendar's source; the detail opens on a tap
    private func loadLine(_ day: String) -> some View {
        let load = store.dayLoad(on: day)
        let known = agenda.covers(day)
        let count = agenda.events(on: day).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if known {
                    SourceLine(text: count == 0 ? "Google Calendar · sem eventos" : "Google Calendar · " + ptCount(count, "evento", "eventos"))
                } else {
                    SourceLine(text: "Google Calendar")
                    StateTag(state: .noData)
                }
                Spacer(minLength: 6)
                Button { withAnimation(.easeOut(duration: 0.2)) { loadOpen.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text("carga")
                        EstimatedText(value: "\(duration(load.busy)) de \(duration(load.awake))")
                        Image(systemName: loadOpen ? "chevron.up" : "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.geist(11.5))
                    .foregroundStyle(Color.faint)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Carga do dia, estimada: \(duration(load.busy)) ocupadas de \(duration(load.awake)) acordado")
                .accessibilityHint(loadOpen ? "Esconde o detalhe" : "Mostra o detalhe")
                .accessibilityIdentifier("plan.load")
            }
            LoadBar(load: load).accessibilityHidden(true)
            if loadOpen { loadDetail(day, load, known: known) }
        }
        .padding(.horizontal, 4)
    }

    private func loadDetail(_ day: String, _ load: DayLoad, known: Bool) -> some View {
        let lightsOut = store.sleepPlan(for: day).perform
        let awake = "Acordado das \(clock(store.profile.wakeMinute)) às \(clock(lightsOut)), a hora de apagar as luzes. O que se sobrepõe conta uma vez."
        let note = known ? awake : awake + " Sem dados do Google Calendar para este dia: só conta o que está no Cadence."
        return Card {
            HStack { Eyebrow(text: "Carga do dia"); Spacer(); StateTag(state: .estimated) }
            loadRow("Eventos do calendário", color: .fuel, value: known ? (load.events > 0 ? duration(load.events) : "sem eventos") : nil)
            if load.blocks > 0 { loadRow("Blocos e eventos no Cadence", color: .mint, value: duration(load.blocks)) }
            if load.training > 0 { loadRow("Treino", color: .train, value: duration(load.training)) }
            loadRow("Livre", color: Color.white.opacity(0.3), value: duration(load.free), estimated: true)
            Text(note).font(.geist(12)).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.load.detail")
    }

    /// One part of the load; nil is «Sem dados» (the calendar wasn't read for that day), never a zero
    private func loadRow(_ title: String, color: Color, value: String?, estimated: Bool = false) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(title).font(.geist(13.5))
            Spacer(minLength: 6)
            if let value {
                if estimated { EstimatedText(value: value).font(.geist(13)) } else { Text(value).font(.mono(13)) }
            } else {
                StateTag(state: .noData)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The conflict and, under it, the best other time: «Aplicar» moves only Cadence's side (with Desfazer); «Manter
    /// assim» keeps the conflict in sight with no proposal and saves nothing
    @ViewBuilder private func conflictCards(_ c: PlanConflict, today: String) -> some View {
        let isKept = kept.contains(c.id)
        Card(state: .pending) {
            HStack {
                Eyebrow(text: "Conflito às \(clock(c.at))")
                Spacer()
                StateTag(state: .pending, text: isKept ? "Conflito" : "Precisa de decisão")
            }
            HStack(alignment: .top, spacing: 8) {
                conflictSide(time: "\(clock(c.span.start))–\(clock(c.span.end))", title: c.title, from: c.block == nil ? "do teu plano" : "do Cadence", google: false)
                conflictSide(time: "\(clock(c.otherSpan.start))–\(clock(c.otherSpan.end))", title: c.other, from: c.otherIsGoogle ? "Google Calendar" : "teu, no Cadence", google: c.otherIsGoogle)
            }
            Text(conflictText(c)).font(.geist(13)).fixedSize(horizontal: false, vertical: true)
            if isKept { Text("Mantiveste assim: o conflito fica à vista no dia, na semana e no mês.").font(.geist(12)).foregroundStyle(Color.soft) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.conflict")
        if !isKept { proposalCard(c, store.planAlternatives(for: c, today: today)) }
    }

    private func conflictSide(time: String, title: String, from: String, google: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(time).font(.mono(11)).foregroundStyle(Color.faint)
            Text(title).font(.geist(14, .semibold)).lineLimit(2)
            if google { SourceLine(text: from) } else { Text(from).font(.geist(11)).foregroundStyle(Color.faint) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    private func conflictText(_ c: PlanConflict) -> String {
        let overlap = "Sobrepõem-se \(duration(c.overlap))."
        return c.otherIsGoogle ? "\(overlap) Não mexo em «\(c.other)»: é do teu calendário." : "\(overlap) «\(c.other)» fica onde o marcaste."
    }

    private func moveText(_ c: PlanConflict, to start: Int) -> String {
        let span = "das \(clock(start)) às \(clock(start + c.span.minutes))"
        return c.training ? "Treinar \(span)" : "«\(c.title)» \(span)"
    }

    private func whyText(_ c: PlanConflict, _ o: PlanAlternative) -> String {
        "estás livre das \(clock(o.freeFrom)) às \(clock(o.freeTo)); " + (c.otherIsGoogle ? "o evento do calendário fica como está." : "«\(c.other)» fica como está.")
    }

    @ViewBuilder private func proposalCard(_ c: PlanConflict, _ options: [PlanAlternative]) -> some View {
        if let best = options.first {
            Card(state: .suggested) {
                HStack { Eyebrow(text: "Melhor alternativa"); Spacer(); StateTag(state: .suggested) }
                Text(moveText(c, to: best.start)).font(.geist(15, .semibold))
                WhyLine(text: whyText(c, best))
                HStack(spacing: 6) {
                    PlanButton(title: "Aplicar", style: .go, id: "plan.conflict.apply") { apply(c, best) }
                    if options.count > 1 {
                        PlanButton(title: showingOthers.contains(c.id) ? "Esconder outras" : "Ver outras (\(options.count - 1))", style: .line, id: "plan.conflict.others") { toggleOthers(c.id) }
                    }
                    PlanButton(title: "Manter assim", style: .ghost, id: "plan.conflict.keep") { keep(c.id) }
                    Spacer(minLength: 0)
                }
                if showingOthers.contains(c.id) {
                    ForEach(Array(options.dropFirst()), id: \.start) { o in
                        HStack(spacing: 8) {
                            Text(moveText(c, to: o.start)).font(.geist(13.5))
                            Spacer(minLength: 6)
                            PlanButton(title: "Aplicar", style: .line, id: "plan.conflict.apply.\(o.start)") { apply(c, o) }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan.conflict.proposal")
        } else {
            Card(state: .noData) {
                Text("Não há outra hora livre neste dia antes de desacelerares. Podes mudar à mão.").font(.geist(13)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    PlanButton(title: "Mudar à mão", style: .line, id: "plan.conflict.edit") { placing = store.proposedBlock(c, start: c.span.start) }
                    PlanButton(title: "Manter assim", style: .ghost, id: "plan.conflict.keep") { keep(c.id) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func toggleOthers(_ id: String) {
        if showingOthers.contains(id) {
            showingOthers.remove(id)
        } else {
            showingOthers.insert(id)
        }
    }

    /// «Manter assim» / «Ignorar»: hides the proposal for now and keeps the conflict in sight; nothing is saved
    private func keep(_ id: String) {
        kept.insert(id)
    }

    /// «Aplicar» / «Aceitar»: only Cadence's side moves, with Desfazer
    private func apply(_ c: PlanConflict, _ o: PlanAlternative) {
        let undo = store.applyAlternative(c, start: o.start)
        showingOthers.remove(c.id)
        UndoCenter.shared.show("\(c.title) passou para as \(clock(o.start))", undo: undo)
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

    private func timeline(_ day: String, isToday: Bool, now: Int) -> some View {
        Card {
            HStack {
                Eyebrow(text: isToday ? "Hoje" : PlanFormat.day(day), icon: "calendar")
                Spacer()
                Button { placing = PlanBlock(date: day, start: isToday ? ((now + 30) / 15) * 15 : 9 * 60, minutes: 60, title: "", type: "deep") } label: { Label("Bloco", systemImage: "plus").font(.geist(13, .semibold)) }.tint(.mint)
            }
            ForEach(store.planItems(for: day)) { item in
                let end = item.end ?? item.minute
                let past = isToday && end < now && item.minute >= 240
                HStack(alignment: .top, spacing: 12) {
                    Text(clock(item.minute)).font(.mono(13, .semibold)).foregroundStyle(Color.soft).frame(width: 48, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 3, height: item.end == nil ? 18 : max(18, CGFloat(end - item.minute) / 3))
                    Image(systemName: item.icon).foregroundStyle(item.color).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.geist(14.5, .semibold))
                        Text(item.detail).font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer()
                    if isToday, let p = item.promise, store.status(p) == nil {
                        Button { store.log(p, .done) } label: { Image(systemName: "circle").font(.geist(20)).foregroundStyle(Color.soft) }
                    }
                    if isToday, let e = item.event, e.endMinute <= now, store.record(EventFeeling.self, e.id) == nil { FeelingButtons(event: e) }
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

    /// «+ Novo» opens Criar evento; «Rever o dia» the end-of-day review (today or a day gone by)
    private func dayActions(_ day: String, today: String) -> some View {
        HStack(spacing: 8) {
            PlanButton(title: "+ Novo", style: .go, id: "plan.new.open", label: "Novo evento") { creating = true }
                .sheet(isPresented: $creating) { NewEventSheet(day: day).environmentObject(store) }
            if day <= today {
                PlanButton(title: "Rever o dia", style: .line, id: "plan.review.open") { reviewing = true }
                    .sheet(isPresented: $reviewing) { DayReviewView(day: day).environmentObject(store) }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Semana (N_PlanoReorganizar): only the training's conflicts are proposed (decision 2.8)

    @ViewBuilder private func weekView(today: String) -> some View {
        let start = Day.weekStart(chosenDay ?? today)
        let days = (0..<7).map { Day.add($0, to: start) }
        let proposals = days.filter { $0 >= today }.flatMap { store.planConflicts(on: $0) }.filter { $0.training && !kept.contains($0.id) }
        VStack(alignment: .leading, spacing: 12) {
            PeriodNav(title: PlanFormat.week(from: start), away: start != Day.weekStart(today), prevLabel: "Semana anterior", nextLabel: "Semana seguinte",
                      prev: { chosenDay = Day.add(-7, to: start) }, next: { chosenDay = Day.add(7, to: start) }, home: { chosenDay = nil })
            Card(padding: 10) {
                ForEach(days, id: \.self) { d in weekRow(d, today: today) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan.week")
            if !proposals.isEmpty {
                Text("\(ptCount(proposals.count, "proposta", "propostas")). Nada muda até aceitares; podes aceitar uma a uma.")
                    .font(.geist(13)).foregroundStyle(Color.soft).padding(.horizontal, 4)
                ForEach(proposals) { c in weekProposal(c, today: today) }
            }
        }
    }

    private func weekRow(_ d: String, today: String) -> some View {
        let load = store.dayLoad(on: d)
        let conflicts = d >= today ? store.planConflicts(on: d) : []
        let summary = weekSummary(d)
        let barColor = load.share > 0.85 ? Color.train : load.share > 0.6 ? Color.fuel : Color.mint
        return Button { openDay(d, today: today) } label: {
            HStack(spacing: 10) {
                Text(PlanFormat.short(d)).font(.geist(13, .semibold)).foregroundStyle(d == today ? Color.mint : Color.ink).frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary).font(.geist(13)).foregroundStyle(Color.ink).lineLimit(1)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(barColor).frame(width: load.busy > 0 ? max(4, g.size.width * CGFloat(load.share)) : 0)
                        }
                    }
                    .frame(height: 4)
                }
                if !conflicts.isEmpty { StateTag(state: .pending, text: "Conflito") }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.faint)
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PlanFormat.day(d)): \(summary), carga \(Int((load.share * 100).rounded()))%" + (conflicts.isEmpty ? "" : ", conflito"))
        .accessibilityHint("Abre o dia")
        .accessibilityIdentifier("plan.week.day.\(d)")
    }

    /// «Trabalho · tronco 18:30»: the day's events, your blocks and the training, or «Livre»
    private func weekSummary(_ d: String) -> String {
        var parts = agenda.events(on: d).map(\.title)
        parts += store.all(PlanBlock.self).filter { $0.date == d && $0.type != "training" }.sorted { $0.start < $1.start }.map(\.title)
        if let t = store.trainingSlot(on: d) { parts.append("\(t.title.lowercased()) \(clock(t.start))") }
        let known = agenda.covers(d)
        if parts.isEmpty { return known ? "Livre" : "Sem dados do calendário" }
        if !known { parts.append("calendário sem dados") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func weekProposal(_ c: PlanConflict, today: String) -> some View {
        if let best = store.planAlternatives(for: c, today: today).first {
            Card(state: .suggested) {
                HStack { Eyebrow(text: "Treino"); Spacer(); StateTag(state: .suggested) }
                Text("\(PlanFormat.weekday(c.day)): «\(c.title)» das \(clock(c.span.start)) para as \(clock(best.start))").font(.geist(15, .semibold))
                WhyLine(text: "choca com «\(c.other)» às \(clock(c.at)); estás livre das \(clock(best.freeFrom)) às \(clock(best.freeTo)).")
                HStack(spacing: 6) {
                    PlanButton(title: "Aceitar", style: .go, id: "plan.proposal.accept") { apply(c, best) }
                    PlanButton(title: "Ajustar", style: .line, id: "plan.proposal.adjust") { placing = store.proposedBlock(c, start: best.start) }
                    PlanButton(title: "Ignorar", style: .ghost, id: "plan.proposal.ignore") { keep(c.id) }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan.proposal")
        }
    }

    // MARK: Mês (N_PlanoMes)

    @ViewBuilder private func monthView(today: String) -> some View {
        let month = chosenMonth ?? PlanRules.monthStart(today)
        let pick = picked ?? today
        let repeating = PlanRules.repeating(agenda.events)
        let previous = PlanRules.addMonths(-1, to: month)
        let following = PlanRules.addMonths(1, to: month)
        VStack(alignment: .leading, spacing: 12) {
            PeriodNav(title: PlanFormat.month(month), away: month != PlanRules.monthStart(today),
                      prevLabel: "Mês anterior: \(PlanFormat.monthName(previous))", nextLabel: "Mês seguinte: \(PlanFormat.monthName(following))",
                      prev: { chosenMonth = previous }, next: { chosenMonth = following }, home: { chosenMonth = nil; picked = nil })
            monthGrid(month, today: today, pick: pick, repeating: repeating)
            monthLegend
            monthSummary(pick, today: today, repeating: repeating)
        }
    }

    private func monthGrid(_ month: String, today: String, pick: String, repeating: Set<String>) -> some View {
        let cells = PlanRules.monthCells(month)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(["S", "T", "Q", "Q", "S", "S", "D"].enumerated()), id: \.offset) { _, w in
                Text(w).font(.geist(11)).foregroundStyle(Color.faint).frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let d = cell {
                    monthCell(d, today: today, pick: pick, repeating: repeating)
                } else {
                    Color.clear.frame(height: 50).accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.month.grid")
    }

    /// Today has an outline, the chosen day is filled; a lighter background is a fuller day. Daily-repeating events
    /// don't mark it.
    private func monthCell(_ d: String, today: String, pick: String, repeating: Set<String>) -> some View {
        let info = store.monthDay(d, today: today, repeating: repeating, kept: kept)
        let selected = d == pick
        let isToday = d == today
        let shades: [Double] = [0, 0.045, 0.09, 0.15]
        var label = PlanFormat.dayMonth(d)
        if isToday { label += ", hoje" }
        if selected { label += ", escolhido" }
        for m in info.marks { label += ", " + m.word }
        if !info.conflicts.isEmpty { label += ", conflito" }
        return Button { picked = d } label: {
            VStack(spacing: 4) {
                Text(String(Int(d.suffix(2)) ?? 0)).font(.geist(13, selected || isToday ? .bold : .medium))
                HStack(spacing: 2) {
                    ForEach(info.marks, id: \.self) { MarkShape(mark: $0, onFill: selected) }
                }
                .frame(height: 9)
            }
            .foregroundStyle(selected ? Color(hex: 0x032018) : d < today ? Color.faint : Color.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Color.mint : Color.white.opacity(shades[min(3, max(0, info.level))])))
            .overlay {
                if isToday { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.mint, lineWidth: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("plan.month.day.\(d)")
    }

    private var monthLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ForEach([PlanMark.training, PlanMark.commitment, PlanMark.suggestion], id: \.self) { legendItem($0) }
            }
            HStack(spacing: 12) {
                legendItem(.trainingLogged, word: "registado")
                legendItem(.trainingNoRecord, word: "sem registo")
            }
            Text("Fundo mais claro: dia mais cheio.").font(.geist(11)).foregroundStyle(Color.soft)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ m: PlanMark, word: String? = nil) -> some View {
        HStack(spacing: 4) {
            MarkShape(mark: m)
            Text(word ?? m.word).font(.geist(11)).foregroundStyle(Color.soft)
        }
    }

    /// The chosen day under the grid, with «Abrir o dia»; its conflicts below it
    private func monthSummary(_ d: String, today: String, repeating: Set<String>) -> some View {
        let events = agenda.events(on: d)
        let blocks = store.all(PlanBlock.self).filter { $0.date == d && $0.type != "training" }.sorted { $0.start < $1.start }
        let training = store.trainingSlot(on: d)
        let info = store.monthDay(d, today: today, repeating: repeating, kept: kept)
        let proposals: [(PlanConflict, PlanAlternative)] = info.conflicts.filter { !kept.contains($0.id) }.compactMap { c in
            store.planAlternatives(for: c, today: today).first.map { (c, $0) }
        }
        let known = agenda.covers(d)
        let count = events.count + blocks.count
        var parts: [String] = [count == 0 ? (known ? "sem compromissos" : "sem dados do calendário") : ptCount(count, "compromisso", "compromissos")]
        if training != nil { parts.append("treino") }
        if !proposals.isEmpty { parts.append(ptCount(proposals.count, "sugestão", "sugestões")) }
        if count > 0 && !known { parts.append("sem dados do calendário") }
        return VStack(alignment: .leading, spacing: 8) {
            Card {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PlanFormat.day(d)).font(.geist(15, .semibold))
                        Text(parts.joined(separator: " · ")).font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 6)
                    PlanButton(title: "Abrir o dia", style: .go, id: "plan.month.open") { openDay(d, today: today) }
                }
                ForEach(events) { e in
                    summaryRow(clock(e.startMinute), e.title, "até às \(clock(e.endMinute))") { SourceLine(text: "Google") }
                }
                ForEach(blocks) { b in
                    summaryRow(clock(b.start), b.title, "\(duration(b.minutes)) · marcado por ti") { EmptyView() }
                }
                if let t = training {
                    summaryRow(clock(t.start), t.title, t.done ? "registado no treino" : "treino até às \(clock(t.end))") {
                        if t.done { StateTag(state: .confirmed, text: "Feito") }
                    }
                }
                ForEach(proposals, id: \.0.id) { c, o in
                    summaryRow(clock(o.start), "\(c.title): passar para as \(clock(o.start))", "proposta · ainda não está no plano") { StateTag(state: .suggested) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan.month.summary")
            ForEach(info.conflicts) { c in
                Button { openDay(c.day, today: today) } label: {
                    HStack(spacing: 8) {
                        Text("\(PlanFormat.relative(c.day, today: today)): «\(c.title)» das \(clock(c.span.start)) choca com «\(c.other)»")
                            .font(.geist(13)).foregroundStyle(Color.ink).frame(maxWidth: .infinity, alignment: .leading)
                        StateTag(state: .pending, text: "Conflito")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.faint)
                    }
                    .padding(.horizontal, 4)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.month.conflict")
            }
        }
    }

    private func summaryRow<Trailing: View>(_ time: String, _ title: String, _ sub: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(time).font(.mono(12.5, .semibold)).foregroundStyle(Color.soft).frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.geist(14))
                Text(sub).font(.geist(12)).foregroundStyle(Color.soft)
            }
            Spacer(minLength: 6)
            trailing()
        }
        .frame(minHeight: 40)
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

// MARK: - Plano's own pieces (phase 2.8)

/// ‹ and › change the day, the week or the month; «Hoje» comes back when you're away from it
private struct PeriodNav: View {
    var title: String
    var away: Bool
    var prevLabel: String
    var nextLabel: String
    var prev: () -> Void
    var next: () -> Void
    var home: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            arrow("chevron.left", prevLabel, "plan.prev", prev)
            Text(title).font(.geist(16, .semibold)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
            if away {
                Button(action: home) {
                    Text("Hoje").font(.geist(13, .semibold)).foregroundStyle(Color.mint)
                        .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.today")
            }
            arrow("chevron.right", nextLabel, "plan.next", next)
        }
    }

    private func arrow(_ icon: String, _ label: String, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// A button in the design's three weights (go, line, ghost), at least 44 pt tall, with its identifier
private struct PlanButton: View {
    enum Weight { case go, line, ghost }
    var title: String
    var style: Weight = .line
    var id: String
    var label: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.geist(13, .semibold)).lineLimit(1)
                .foregroundStyle(style == .go ? Color(hex: 0x05140F) : style == .ghost ? Color.soft : Color.ink)
                .padding(.horizontal, style == .ghost ? 8 : 14)
                .frame(minHeight: 44)
                .background { capsule }
                .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(label ?? title)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var capsule: some View {
        switch style {
        case .go: Capsule().fill(Area.mint.gradient)
        case .line: Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
        case .ghost: EmptyView()
        }
    }
}

/// The day's load as one bar over the hours awake: calendar events, Cadence's blocks and events, the training
private struct LoadBar: View {
    var load: DayLoad

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(segments, id: \.0) { _, share, color in
                    Capsule().fill(color).frame(width: max(3, g.size.width * share))
                }
                Spacer(minLength: 0)
            }
            .frame(width: g.size.width, alignment: .leading)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .frame(height: 6)
    }

    /// Each part's share of the hours awake; together never more than what's busy (what overlaps counts once)
    private var segments: [(Int, CGFloat, Color)] {
        let parts: [(Int, Int, Color)] = [(0, load.events, Color.fuel), (1, load.blocks, Color.mint), (2, load.training, Color.train)]
        let sum = parts.map { $0.1 }.reduce(0, +)
        guard sum > 0, load.awake > 0 else { return [] }
        let scale = min(1, Double(load.busy) / Double(sum))
        return parts.filter { $0.1 > 0 }.map { ($0.0, CGFloat(Double($0.1) * scale / Double(load.awake)), $0.2) }
    }
}

/// A month grid mark: the shape says what it is (filled confirmed, hollow suggested, dashed with no record)
private struct MarkShape: View {
    var mark: PlanMark
    var onFill = false

    var body: some View {
        let dark = Color(hex: 0x032018)
        Group {
            switch mark {
            case .training:
                Rectangle().fill(onFill ? dark : Color.train).frame(width: 6, height: 6).rotationEffect(.degrees(45))
            case .trainingNoRecord:
                Rectangle().stroke(onFill ? dark : Color.faint, style: StrokeStyle(lineWidth: 1.2, dash: [2, 1.4])).frame(width: 6, height: 6).rotationEffect(.degrees(45))
            case .trainingLogged:
                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(onFill ? dark : Color.mint)
            case .commitment:
                Circle().fill(onFill ? dark : Color.fuel).frame(width: 7, height: 7)
            case .suggestion:
                Circle().stroke(onFill ? dark : DataState.suggested.color, lineWidth: 1.6).frame(width: 6.5, height: 6.5)
            }
        }
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
    }
}

// MARK: - Criar evento (N_PlanoNovoEvento)

/// «+ Novo»: one line as you'd say it, read back into a form you check. Nothing is saved before Guardar, which waits
/// until nothing is ambiguous. The event is Cadence's own, a PlanBlock (decision D2: the Google calendar is only read),
/// and happens once (decision 2.8: repeats come later).
struct NewEventSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var title = ""
    @State private var day: String
    @State private var minute: Int?
    @State private var options: [Int] = []
    @State private var minutes = 60
    @State private var lengthChanged = false
    @State private var heard = false
    @State private var dayHeard = false

    init(day: String) {
        _day = State(initialValue: day)
    }

    var body: some View {
        NavigationStack {
            Screen(glow: .water) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Novo").font(.geist(24, .bold))
                    Text("Escreve como dirias").font(.geist(13)).foregroundStyle(Color.soft)
                }
                .padding(.top, 4)
                TextField("dentista quinta às 3", text: $text)
                    .font(.geist(15))
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
                    .accessibilityLabel("Escreve como dirias")
                    .accessibilityIdentifier("plan.new.text")
                    .onChange(of: text) { _, new in read(new) }
                if heard {
                    Text("Percebi isto. Confirma ou muda antes de guardar.").font(.geist(12)).foregroundStyle(Color.soft).padding(.horizontal, 4)
                }
                field("Título") {
                    TextField("O quê", text: $title).font(.geist(15)).frame(minHeight: 30).accessibilityIdentifier("plan.new.title")
                }
                field("Dia") {
                    DatePicker("Dia", selection: dayBinding, displayedComponents: .date).labelsHidden().accessibilityIdentifier("plan.new.day")
                    if heard && !dayHeard {
                        Text("Não disseste o dia: fica \(PlanFormat.relative(day, today: Day.today).lowercased()).").font(.geist(11)).foregroundStyle(Color.faint)
                    }
                }
                timeField
                field("Duração") {
                    Stepper(value: $minutes, in: 15...600, step: 15) {
                        if lengthChanged { Text(duration(minutes)).font(.geist(15)) } else { EstimatedText(value: duration(minutes)).font(.geist(15)) }
                    }
                    .onChange(of: minutes) { _, _ in lengthChanged = true }
                    if !lengthChanged { Text("Estimativa: muda se precisares.").font(.geist(11)).foregroundStyle(Color.faint) }
                }
                field("Repete") {
                    Text("Não se repete").font(.geist(15))
                }
                field("Calendário") {
                    Text("Cadence").font(.geist(15))
                    Text("Fica no Cadence: o Google Calendar não muda.").font(.geist(11)).foregroundStyle(Color.faint)
                }
                if let line = duplicateLine {
                    Text(line).font(.geist(12)).foregroundStyle(Color.faint).padding(.horizontal, 4)
                }
                PrimaryButton(title: "Guardar") { save() }
                    .disabled(missing != nil)
                    .opacity(missing == nil ? 1 : 0.45)
                    .accessibilityIdentifier("plan.new.save")
                if let why = missing {
                    Text(why).font(.geist(12)).foregroundStyle(Color.faint).frame(maxWidth: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.accessibilityIdentifier("plan.new.cancel") }
            }
        }
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { Day.date(day) }, set: { day = Day.key($0) })
    }

    @ViewBuilder private var timeField: some View {
        if let m = minute {
            field("Hora") {
                DatePicker("Hora", selection: Binding(get: { Day.at(m, on: day) }, set: { minute = Day.minuteOfDay($0) }), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityIdentifier("plan.new.time")
            }
        } else {
            Card(state: .pending) {
                HStack { Eyebrow(text: "Hora"); Spacer(); StateTag(state: .pending, text: "Escolhe") }
                if options.count == 2 {
                    Text(ambiguity).font(.geist(13))
                    HStack(spacing: 8) {
                        ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                            PlanButton(title: clock(o), style: .line, id: "plan.new.time.\(i)") { minute = o }
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Text(heard ? "Não percebi a hora." : "A que horas?").font(.geist(13))
                    PlanButton(title: "Escolher hora", style: .line, id: "plan.new.time.pick") { minute = defaultMinute }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan.new.time.pending")
        }
    }

    /// «"às 3" pode ser de tarde ou de madrugada»: the two readings of an hour from 1 to 11
    private var ambiguity: String {
        let h = (options.last ?? 0) / 60
        let when = h <= 5 ? "de tarde ou de madrugada" : h <= 7 ? "de manhã ou ao fim da tarde" : "de manhã ou à noite"
        return "«às \(h)» pode ser \(when)."
    }

    private var defaultMinute: Int {
        day == Day.today ? min(23 * 60, (Clock.minute() / 60 + 1) * 60) : 9 * 60
    }

    private var missing: String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return "Guardar fica disponível depois de dares um título." }
        if minute == nil { return "Guardar fica disponível depois de escolheres a hora." }
        return nil
    }

    /// Something with the same name that week, or that there's none (only what's known: a week the calendar wasn't
    /// read for is said so)
    private var duplicateLine: String? {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let calendar = Agenda.shared.events.filter { !$0.allDay }.map { PlanEntry(title: $0.title, day: $0.day, minute: $0.startMinute) }
        let mine = store.all(PlanBlock.self).map { PlanEntry(title: $0.title, day: $0.date, minute: $0.start) }
        if let same = PlanRules.similar(to: name, on: day, among: calendar + mine) {
            return "Já tens «\(same.title)» nessa semana: \(PlanFormat.day(same.day).lowercased()) às \(clock(same.minute))."
        }
        return Agenda.shared.covers(day) ? "Nada parecido nessa semana: sem duplicados." : "Sem dados do calendário para esse dia: só comparei com o que está no Cadence."
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.geist(11, .semibold)).foregroundStyle(Color.faint)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    /// What was typed, read back into the form (nothing is saved)
    private func read(_ new: String) {
        let d = EventDraft.parse(new, today: Day.today)
        heard = !new.trimmingCharacters(in: .whitespaces).isEmpty
        title = d.title
        if let parsed = d.day { day = parsed }
        dayHeard = d.day != nil
        minute = d.minute
        options = d.options
    }

    private func save() {
        guard missing == nil, let m = minute else { return }
        let block = PlanBlock(date: day, start: m, minutes: minutes, title: title.trimmingCharacters(in: .whitespaces), type: "other")
        let s: Store = store
        s.save(block)
        UndoCenter.shared.show("Evento guardado: \(block.title)") { s.remove(block) }
        dismiss()
    }
}
