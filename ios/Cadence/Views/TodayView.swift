// Today: «Agora» (one step at a time, Now.swift), how you are (the rings with their source), quick logs ordered by use,
// readiness with its reasons, today's habits, closing the day. Phase 2.9: Antes de sair and the routine of the moment
// in «Agora» (steps 3 and 4), «Preparar para sair» on an urgent departure, the line left after leaving, the night's
// sequence in place of «Agora» at night, and last night's sleep in the morning (NightViews.swift, LeaveView.swift).
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var agenda = Agenda.shared // the calendar feeds «Agora»: redraw when it changes
    @State private var closing = false
    @State private var editing: PromiseItem?
    @State private var briefHidden = false
    @State private var loggingFood = false
    @State private var settingUp = false
    @State private var capturing = false
    @State private var showingYou = false
    @State private var ringsOpen = false // an urgent step shrinks the rings to a line; tapping it opens them
    @State private var leaving = false // Antes de sair
    @State private var playing: CareRoutine? // the routine of the moment, in Higiene's player
    @State private var nightPage: NightSheetPage? // Preparar amanhã or Antes de dormir
    @State private var readingStart: ReadingStart? // a reading started from the night
    @State private var sleepOpen = false // Como dormiste

    private var greeting: String {
        let m = Day.minuteOfDay(store.tick)
        return m < 12 * 60 ? "Bom dia" : m < 18 * 60 ? "Boa tarde" : "Boa noite"
    }

    var body: some View {
        let minute = store.nowMinute
        let step = store.nowStep(minute: minute)
        let urgent = step?.isUrgent ?? false
        let later = store.nowLater(after: step, minute: minute)
        let night = !urgent && store.nightActive(minute: minute) && NightRules.takesAgora(step)
        NavigationStack {
            ScrollViewReader { proxy in
                Screen(glow: .mint) {
                    header
                    // An urgent step takes the place of «Agora» at the top; the rings and the rest of the day shrink to a line
                    if urgent, let step { TodayNowCard(step: step, minute: minute, later: later, showLater: false, openLeave: { leaving = true }) }
                    if store.needsGoogle { googleCard }
                    if store.health.isEmpty, store.device == nil, !TestMode.active { sourceCard }
                    if !store.profile.setupDone {
                        Button { settingUp = true } label: {
                            Card(tint: .mint) {
                                Eyebrow(text: "Configuração inteligente · 1 minuto", icon: "wand.and.stars", color: .mint)
                                Text("Responde a umas perguntas e o Cadence define as tuas calorias, proteína, água, passos e sono com base na investigação, com a razão de cada um.").font(.geist(13.5)).foregroundStyle(Color.ink)
                            }
                        }
                        .buttonStyle(Pressable())
                    }
                    if store.journalDue { JournalCard(canPostpone: true) }
                    MinimumDayBanner()
                    if urgent && !ringsOpen { ringsLine } else { DayRings() }
                    if NightRules.isMorning(minute: minute, wake: store.profile.wakeMinute) { SleepMorningLine { sleepOpen = true } }
                    if urgent, !later.isEmpty { laterLine(later) { showHabits(proxy) } }
                    if urgent { quickLogs }
                    FocusCard()
                    // «Agora» where "A seguir" was, so the cards above it keep their place. At night it follows the
                    // night's sequence instead (unless a departure, a workout or Antes de sair comes first)
                    if night {
                        if case .care(let c)? = step { TodayNowCard(step: .care(c), minute: minute, later: [], showLater: false) } // above the night's sequence (D40)
                        TodayNightCard(minute: minute, open: { nightPage = $0 }, read: { startReading($0) })
                    } else if !urgent, let step {
                        TodayNowCard(step: step, minute: minute, later: later, openLater: { showHabits(proxy) }, openLeave: { leaving = true }, play: { playing = $0 })
                    }
                    if !night { LeaveLaterLine(minute: minute) { leaving = true } } // the night doesn't bring the day's leftovers back
                    if !urgent { quickLogs }
                    unsentCard
                    FoodGoalsCard()
                    ShowerTodayCard()
                    GymBagCard()
                    readinessCard
                    if Day.minuteOfDay(store.tick) < 11 * 60 || store.weatherCall()?.umbrella == true { WeatherCard() }
                    promisesCard.id(TodayView.habitsAnchor)
                    top3Card
                    closeCard
                    syncLine
                }
            }
            .refreshable { await store.refreshAll(force: true) }
            .sheet(isPresented: $closing) { CloseDayView() }
            .sheet(item: $editing) { PromiseEditor(promise: $0) }
            .sheet(isPresented: $loggingFood) { FoodLogSheet() }
            .sheet(isPresented: $settingUp) { SmartSetup() }
            .sheet(isPresented: $capturing) { QuickCaptureSheet() }
            .sheet(isPresented: $showingYou) { YouView() }
            .sheet(isPresented: $leaving) { LeaveView().environmentObject(store) }
            .sheet(item: $nightPage) { NightSheet(page: $0).environmentObject(store) }
            .sheet(isPresented: $sleepOpen) { SleepMorningView().environmentObject(store) }
            .fullScreenCover(item: $playing) { RoutinePlayer(routine: $0).environmentObject(store) }
            .fullScreenCover(item: $readingStart) { ReadingMode(planned: $0.minutes).environmentObject(store) }
            .onChange(of: store.captureOpen) { _, open in if open { capturing = true; store.captureOpen = false } }
            .onAppear { store.recordMorningPrediction() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Title(eyebrow: store.tick.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: greeting)
                .accessibilityIdentifier("today.screen") // <name>.screen: how the UI tests know this tab's root is showing. Internal, never translated; if a redesign removes this title, the identifier moves to the new one
            Spacer()
            Button { capturing = true } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink)
                    .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.09)).overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1)))
            }
            .buttonStyle(Pressable())
            .accessibilityLabel("Registo rápido").accessibilityIdentifier("capture.open")
            .padding(.trailing, 6)
            Button { showingYou = true } label: {
                Image(systemName: "person.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                    .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.09)).overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1)))
            }
            .buttonStyle(Pressable())
            .accessibilityLabel("Perfil").accessibilityIdentifier("you.open")
            .padding(.trailing, 6)
            NavigationLink { PipPage() } label: {
                ZStack(alignment: .topTrailing) {
                    PipHead(mood: store.pipMood(), size: 50)
                    // only a number when Pip is waiting on something, like any other notification badge
                    if store.pipNotices > 0 {
                        Text("\(store.pipNotices)").font(.geist(11, .bold)).foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18).background(Circle().fill(Color.red)).offset(x: 4, y: -2)
                    }
                }
            }
            .accessibilityLabel(store.pipNotices > 0 ? "Pip, \(store.pipNotices) à espera" : "Pip")
        }
        .padding(.top, 8)
    }

    /// First run with no data yet: a Fitbit through the server, or Apple Health on its own
    private var sourceCard: some View {
        Card(tint: .sleep) {
            Eyebrow(text: "Dados de sono e coração", icon: "heart.text.square", color: .sleep)
            Text("De onde deve o Cadence ler o teu sono, VFC e passos?").font(.geist(14))
            HStack {
                NavigationLink { SettingsView() } label: { Chip(text: "Fitbit", color: .sleep) }
                Button { store.update { $0.healthSource = "apple" }; Task { await store.refreshHealth(force: true) } } label: { Chip(text: "Apple Health", color: .sleep) }
            }
            if let p = store.appleHealthProblem { Text(p).font(.geist(12)).foregroundStyle(Color.warn) }
        }
    }

    private var googleCard: some View {
        Card(tint: .warn) {
            Eyebrow(text: "Dados do Fitbit em pausa", icon: "exclamationmark.triangle.fill", color: .warn)
            Text("A sessão do Google expirou (dura 7 dias enquanto a app está em teste). Volta a ligar para manteres a prontidão e o sono atualizados.").font(.geist(14))
            NavigationLink { SettingsView() } label: { Chip(text: "Ligar o Google", color: .warn) }
        }
    }

    private var brief: some View {
        Card(tint: .sleep) {
            HStack {
                Eyebrow(text: "Resumo da manhã", icon: "sunrise.fill", color: .sleep)
                Spacer()
                Button { briefHidden = true } label: { Image(systemName: "xmark").font(.geist(11, .bold)).foregroundStyle(Color.faint) }
            }
            ForEach(store.briefLines()) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(line.good == false ? Color.warn : Color.soft).frame(width: 6, height: 6).padding(.top, 6)
                    Text(line.text).font(.geist(14))
                }
            }
        }
    }

    private var readinessCard: some View {
        NavigationLink { ReadinessView() } label: {
            Card {
                if let r = store.readiness() {
                    HStack(spacing: 12) {
                        ZStack {
                            Ring(progress: Double(r.score) / 100, area: .mint, width: 5, marker: Double(store.usualRecovery) / 100)
                            Text("\(r.score)").font(.geist(15, .bold))
                        }
                        .frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Prontidão · \(r.label)").font(.geist(14.5, .semibold))
                                Chip(text: "confiança " + r.confidence.label, color: r.confidence == .high ? .good : .soft)
                            }
                            Text(store.freshnessNote ?? r.summary).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
                    }
                } else {
                    Label(store.freshnessNote ?? (store.health.isEmpty ? "À espera da primeira sincronização do Air." : "A prontidão aparece quando chegarem os dados da última noite."), systemImage: "clock.arrow.circlepath")
                        .font(.geist(13)).foregroundStyle(Color.soft)
                }
            }
        }
        .buttonStyle(Pressable())
    }

    static let habitsAnchor = "today.habits"

    /// Reading from the night: the plan is saved when you start it (ReadingPlan); the reading done is saved at the end
    private func startReading(_ minutes: Int?) {
        let minute = store.nowMinute
        if let minutes { store.planReading(minutes: minutes, from: NightRules.evening(minute), on: store.nightDay(minute: minute)) }
        readingStart = ReadingStart(minutes: minutes)
    }

    /// «Depois» and the rings' line take you to the rest of today
    private func showHabits(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(TodayView.habitsAnchor, anchor: .top) }
    }

    /// With an urgent step, the rings in one line; a tap opens them again
    private var ringsLine: some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { ringsOpen = true } } label: {
            Card {
                HStack(spacing: 8) {
                    Text(RingStat.summary(store.ringStats().main)).font(.geist(13)).foregroundStyle(Color.soft).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(Color.faint)
                }
                .frame(minHeight: 20)
            }
        }
        .buttonStyle(Pressable())
        .accessibilityHint("Mostra os anéis").accessibilityIdentifier("today.rings.line")
    }

    /// With an urgent step, the rest of the day in one line; a tap shows today's habits
    private func laterLine(_ later: [NowLater], open: @escaping () -> Void) -> some View {
        Button(action: open) {
            Card {
                HStack(spacing: 8) {
                    Text("Depois: " + NowRule.laterText(later)).font(.geist(13)).foregroundStyle(Color.soft).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(Color.faint)
                }
                .frame(minHeight: 20)
            }
        }
        .buttonStyle(Pressable())
        .accessibilityHint("Mostra os hábitos de hoje").accessibilityIdentifier("now.later")
    }

    /// «Registar»: the quick logs, the one you use most first (TodayQuickLog)
    private var quickLogs: some View {
        Card {
            HStack(spacing: 8) {
                Eyebrow(text: "Registar")
                Text("pela ordem que mais usas").font(.geist(11)).foregroundStyle(Color.faint).lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(TodayQuickLog.ordered(uses: store.quickLogUses()), id: \.self) { quickButton($0) }
            }
        }
    }

    @ViewBuilder private func quickButton(_ q: TodayQuickLog) -> some View {
        switch q {
        case .food:
            Button { loggingFood = true } label: {
                Label("Comida", systemImage: "plus").font(.geist(13, .semibold)).foregroundStyle(Color(hex: 0x2B1A05))
                    .frame(maxWidth: .infinity, minHeight: 44).background(Capsule().fill(Area.fuel.gradient))
            }
            .buttonStyle(Pressable())
            .accessibilityLabel("Registar comida").accessibilityIdentifier("today.quick.food")
        case .water:
            Button { store.logWaterNow(250) } label: {
                Label("250 ml", systemImage: "drop.fill").font(.geist(13, .semibold)).foregroundStyle(Color(hex: 0x03202A))
                    .frame(maxWidth: .infinity, minHeight: 44).background(Capsule().fill(Area.water.gradient))
            }
            .buttonStyle(Pressable())
            .accessibilityLabel("Registar 250 ml de água").accessibilityIdentifier("today.quick.water")
        }
    }

    /// Records the server hasn't taken yet, when sending is failing: «Ver o que falta» opens them in Perfil
    @ViewBuilder private var unsentCard: some View {
        let pending = store.pendingSendableCount // only what the server can take: the rest stays on this iPhone by design
        if TodayRules.showsUnsent(pending: pending, failing: store.syncError != nil || store.syncHold != nil || !store.syncRefusedSendable.isEmpty) {
            Card(tint: DataState.error.color) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        StateTag(state: .error, text: "Precisa de ação")
                        Text(TodayRules.unsentText(pending)).font(.geist(13)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    NavigationLink { SettingsView() } label: {
                        Text("Ver o que falta").font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                            .padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(Pressable())
                    .accessibilityIdentifier("today.unsent.open")
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("today.unsent")
        }
    }

    private var promisesCard: some View {
        Card {
            HStack {
                Eyebrow(text: "Hábitos de hoje", icon: "bell")
                Spacer()
                NavigationLink { PromisesView() } label: { Text("Todos").font(.geist(13, .semibold)).foregroundStyle(Color.mint) }
            }
            let due = store.due()
            if due.isEmpty { Text("Nada para hoje.").foregroundStyle(Color.soft).font(.geist(14)) }
            ForEach(due) { p in PromiseRow(promise: p, edit: { editing = p }) }
        }
    }

    private var top3Card: some View {
        let entry = store.day()
        return Group {
            if !entry.top3.isEmpty {
                Card {
                    Eyebrow(text: "3 prioridades de hoje", icon: "list.number")
                    ForEach(Array(entry.top3.enumerated()), id: \.offset) { i, item in
                        let done = i < entry.top3Done.count && entry.top3Done[i]
                        Button {
                            var e = entry
                            while e.top3Done.count < e.top3.count { e.top3Done.append(false) }
                            e.top3Done[i].toggle()
                            store.save(e)
                        } label: {
                            HStack {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Color.good : Color.soft)
                                Text(item).strikethrough(done).foregroundStyle(done ? Color.soft : Color.ink).font(.geist(14))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var closeCard: some View {
        let closed = store.day().closedAt != nil
        let late = (TestMode.minute ?? Day.minuteOfDay(store.tick)) >= 19 * 60
        return Group {
            if closed {
                Card { HStack { Image(systemName: "moon.stars.fill").foregroundStyle(Color.sleep); Text("Dia fechado · \(store.day().score ?? store.score()) / 100").font(.geist(14, .semibold)) }.accessibilityElement(children: .combine).accessibilityIdentifier("closeday.closed") }
            } else if late {
                PrimaryButton(title: "Fechar o dia") { closing = true }.accessibilityIdentifier("closeday.open")
            }
        }
    }

    @Environment(\.openURL) private var openURL

    /// The Air only syncs through the Fitbit app; tapping here opens it so it syncs, then pull to refresh
    private var syncLine: some View {
        Button { openURL(URL(string: "fitbit://")!) } label: { syncLabel }.buttonStyle(.plain)
    }

    private var syncLabel: some View {
        HStack(spacing: 6) {
            Circle().fill(store.syncError == nil && !store.needsGoogle ? Color.good : Color.warn).frame(width: 7, height: 7)
            Text(syncText + " · toca para sincronizar o Air").font(.geist(11.5)).foregroundStyle(Color.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var syncText: String {
        var parts: [String] = []
        if let s = store.device?.lastSync, let d = ISO8601DateFormatter().date(from: s) { parts.append("Air sincronizado \(d.formatted(.relative(presentation: .named)))") }
        if let b = store.device?.battery { parts.append("bateria \(b)%") }
        if let e = store.syncError { parts.append(e) }
        if store.syncing { parts.append("a sincronizar…") }
        return parts.isEmpty ? "Ainda não sincronizado" : parts.joined(separator: " · ")
    }
}

struct PromiseRow: View {
    @EnvironmentObject var store: Store
    var promise: PromiseItem
    var day: String = Day.today
    var edit: () -> Void = {}
    var insideSheet = false // a sheet is already up, so brushing and reading open from here instead of the root
    @State private var brushing = false
    @State private var reading = false

    var body: some View {
        let status = store.status(promise, on: day)
        let notApplicable = store.isNotApplicable(promise, on: day) // «Não se aplica» isn't «Não fiz»: its own look and label
        let w = store.week(promise, upTo: day)
        HStack(spacing: 10) {
            Button {
                if status == nil { store.log(promise, on: day, .done) } else { store.undo(promise, on: day) }
            } label: {
                Image(systemName: TodayRules.habitIcon(status, notApplicable: notApplicable))
                    .font(.geist(22)).foregroundStyle(status == nil ? Color.soft : status == .skipped ? Color.faint : Color.good)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodayRules.habitLabel(promise.title, status, notApplicable: notApplicable))
            .accessibilityHint(status == nil ? "Marca como feito" : "Desfaz a resposta")
            Image(systemName: promise.icon).foregroundStyle(Color.soft).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(promise.title).font(.geist(14.5, .medium)).strikethrough(status == .skipped && !notApplicable)
                Text("\(store.timeLabel(promise, on: day)) · \(w.done)/\(w.total) esta semana").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            Spacer()
            // Phase 2.9: an answer from the band shows as «Importado», never as yours
            if NightRules.answerState(store.answerOrigin(promise, on: day)) == .imported {
                StateTag(state: .imported).accessibilityIdentifier("habit.imported.\(promise.id)")
            } else if notApplicable {
                StateTag(state: .unavailable, text: "Não se aplica").accessibilityIdentifier("habit.na.\(promise.id)")
            } else if status == nil, promise.title.lowercased().contains("brush") {
                Button { if insideSheet { brushing = true } else { store.brushingOpen = true } } label: { Image(systemName: "play.circle.fill").font(.geist(24)).foregroundStyle(Color(hex: 0x5FE3D0)) }.buttonStyle(.plain)
            } else if status == nil, promise.title.lowercased().hasPrefix("read") {
                Button { if insideSheet { reading = true } else { store.readingOpen = true } } label: { Image(systemName: "play.circle.fill").font(.geist(24)).foregroundStyle(Color.read) }.buttonStyle(.plain)
            } else if promise.kind == .mustDo { Chip(text: "essencial", color: status == nil ? .warn : .good) }
            else if store.isMinimumDay(day) { Chip(text: "opcional hoje", color: .faint) }
            else { Chip(text: promise.schedule.summary, color: .soft) }
        }
        .fullScreenCover(isPresented: $brushing) { BrushingView() }
        .fullScreenCover(isPresented: $reading) { ReadingMode() }
        .contentShape(Rectangle())
        .contextMenu {
            if let tiny = promise.tiny, status == nil { Button("Versão mínima: \(tiny)", systemImage: "leaf") { store.log(promise, on: day, .tiny) } }
            if status == nil { Button("Saltar hoje", systemImage: "forward") { store.log(promise, on: day, .skipped) } }
            if status != nil { Button("Desfazer", systemImage: "arrow.uturn.backward") { store.undo(promise, on: day) } }
            Button("Editar", systemImage: "pencil") { edit() }
        }
    }
}

/// Readiness with each part against your baseline, and the "feels wrong" button
struct ReadinessView: View {
    @EnvironmentObject var store: Store
    @State private var sent = false

    var body: some View {
        Screen(glow: .mint) {
            if let r = store.readiness() {
                HStack(spacing: 16) {
                    ZStack { Ring(progress: Double(r.score) / 100, area: .mint, width: 10, marker: Double(store.usualRecovery) / 100); Text("\(r.score)").font(.geist(34, .bold)) }.frame(width: 110, height: 110)
                    VStack(alignment: .leading) {
                        Text(r.label).font(.geist(24, .bold))
                        Text("Comparada com a tua base dos últimos 14 dias").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }
                .padding(.top, 10)
                Card {
                    Eyebrow(text: "De que é feita")
                    ForEach(r.parts) { part in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(part.name).font(.geist(14, .semibold))
                                Spacer()
                                Text(part.value).font(.mono(14)).foregroundStyle(part.good ? Color.good : Color.warn)
                            }
                            Text(part.detail).font(.geist(12.5)).foregroundStyle(Color.soft)
                            Bar(progress: part.score / 100, area: part.good ? .mint : .fuel)
                        }
                        .padding(.vertical, 3)
                    }
                }
                Card {
                    Eyebrow(text: "Parece-te errado?", icon: "bubble.left")
                    Text("Diz ao Cadence como te sentes de facto. A pontuação vai-se ajustando com o tempo.").font(.geist(13)).foregroundStyle(Color.soft)
                    if sent { Text("Obrigado, registado.").font(.geist(14, .semibold)).foregroundStyle(Color.good) }
                    else {
                        HStack {
                            SoftButton(title: "Sinto-me pior", icon: "arrow.down") { store.addFeedback(ReadinessFeedback(date: Day.today, score: r.score, felt: -1)); sent = true }
                            SoftButton(title: "Sinto-me melhor", icon: "arrow.up") { store.addFeedback(ReadinessFeedback(date: Day.today, score: r.score, felt: 1)); sent = true }
                        }
                    }
                }
            } else {
                Text("Ainda sem prontidão: precisa de uma noite de dados do Air e de quatro dias de base.").foregroundStyle(Color.soft).padding(.top, 20)
            }
        }
        .navigationTitle("Prontidão")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - «Agora»

/// «Agora»: the one step the rule picks (NowRule.pick, decision D3). The rest of today stays a tap away («Depois»).
/// Its main button is "next.action", as "A seguir"'s was.
struct TodayNowCard: View {
    @EnvironmentObject var store: Store
    var step: NowStep
    var minute: Int
    var later: [NowLater]
    var showLater = true
    var openLater: () -> Void = {}
    var openLeave: () -> Void = {} // Antes de sair
    var play: (CareRoutine) -> Void = { _ in } // the routine of the moment, in the player

    var body: some View {
        switch step {
        case .leave(let d): leave(d)
        case .workout(let w): workout(w)
        case .beforeLeaving: beforeLeaving
        case .routine: routine
        case .care(let c): care(c)
        case .habit(let p): habit(p)
        }
    }

    /// A reminder from Higiene: done, or not today (decision D40)
    private func care(_ c: NowCare) -> some View {
        Card {
            HStack(spacing: 8) {
                Eyebrow(text: "Agora", color: .mint)
                StateTag(state: .suggested)
                Spacer(minLength: 0)
            }
            Text(c.title).font(.geist(16, .bold)).fixedSize(horizontal: false, vertical: true)
            WhyLine(text: c.why)
            DecisionButtons(accept: "Feito", adjust: nil, ignore: "Hoje não", onAccept: { store.finishNowCare(c) }, onIgnore: { store.skipNowCare(c) })
            laterRow
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("now.care")
    }

    /// An event to leave for: when to leave, from what, and the two answers. Neither changes the Google event.
    private func leave(_ d: NowDeparture) -> some View {
        let left = d.leave - minute
        let tag: String = left > 0 ? "Daqui a \(left) min" : "Hora de sair"
        let title: String = left > 0 ? "Sair até \(PlanFormat.at(d.leave)) para \(d.title)" : "Sair agora para \(d.title)"
        let place: String = d.place.map { " · " + $0 } ?? ""
        let when: String = PlanFormat.at(d.start) + place
        let reason: String
        if let trip = d.trip { reason = "\(d.lead) min porta a porta, com margem (\(trip))" } else { reason = "Sem estimativa de viagem: saída \(d.lead) min antes" }
        return Card(state: .pending) {
            HStack(spacing: 8) {
                Eyebrow(text: "Agora", color: DataState.pending.color)
                StateTag(state: .pending, text: tag)
                Spacer(minLength: 0)
            }
            Text(title).font(.geist(17, .semibold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(when).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1)
                SourceLine(text: "Google Calendar").layoutPriority(1)
            }
            Text(reason).font(.geist(11.5)).foregroundStyle(Color.faint).fixedSize(horizontal: false, vertical: true)
            // «Preparar para sair», the main button, opens Antes de sair
            Button(action: openLeave) {
                Text("Preparar para sair").font(.geist(14, .semibold)).foregroundStyle(Color(hex: 0x2B1A05))
                    .padding(.horizontal, 18).frame(minHeight: 44).background(Capsule().fill(DataState.pending.color))
            }
            .buttonStyle(Pressable())
            .accessibilityIdentifier("next.action")
            HStack(spacing: 8) {
                Button { store.answerNow(d, snooze: true, minute: minute) } label: {
                    Text("Adiar \(NowRule.snoozeMinutes) min").font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                .accessibilityIdentifier("now.snooze")
                Button { store.answerNow(d, snooze: false, minute: minute) } label: {
                    Text("Já não vou").font(.geist(13, .semibold)).foregroundStyle(Color.soft).padding(.horizontal, 8).frame(minHeight: 44)
                }
                .accessibilityHint("Esconde este aviso. O evento do Google não muda.").accessibilityIdentifier("now.gone")
                Spacer(minLength: 0)
            }
            .buttonStyle(Pressable())
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("now.leave")
    }

    /// Antes de sair (D3, step 3): a departure within the hour and what's still to see; the list opens from here
    @ViewBuilder private var beforeLeaving: some View {
        let pending = store.leaveEntries().filter { !$0.seen }
        let next = LeaveRules.next(store.leaveDepartures(), minute: minute)
        Card(state: .pending) {
            HStack(spacing: 8) {
                Eyebrow(text: "Agora", color: DataState.pending.color)
                StateTag(state: .pending, text: LeaveRules.pendingText(pending.count))
                Spacer(minLength: 0)
            }
            Text("Antes de sair").font(.geist(17, .semibold))
            if let next { Text("Sair \(PlanFormat.at(next.leave)) · \(next.title)").font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1) }
            let names = LeaveRules.names(pending.map { $0.item.title })
            Text(names.prefix(1).uppercased() + String(names.dropFirst())).font(.geist(12.5)).foregroundStyle(Color.faint).lineLimit(2)
            HStack(spacing: 8) {
                Button(action: openLeave) {
                    Text("Ver a lista").font(.geist(14, .semibold)).foregroundStyle(Color(hex: 0x2B1A05))
                        .padding(.horizontal, 18).frame(minHeight: 44).background(Capsule().fill(DataState.pending.color))
                }
                .buttonStyle(Pressable())
                .accessibilityIdentifier("next.action")
                Spacer(minLength: 0)
            }
            laterRow
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("now.beforeleaving")
    }

    /// The routine of the moment (D3, step 4): Higiene's routine still to confirm; «Começar» opens its player with the
    /// steps left, which confirms each as you go
    @ViewBuilder private var routine: some View {
        if let r = store.routineDueNow(minute: minute) {
            let pending = store.pendingSteps(r)
            let seconds = pending.map { $0.seconds }.reduce(0, +)
            Card {
                HStack(spacing: 8) {
                    Eyebrow(text: "Agora", color: .mint)
                    StateTag(state: .pending, text: "\(pending.count) por confirmar")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.title).font(.geist(16, .bold))
                        Text(ptCount(pending.count, "passo", "passos") + " · cerca de \(max(1, (seconds + 59) / 60)) min").font(.geist(12.5)).foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 8)
                    Button {
                        var left = r
                        left.steps = pending // the player goes through what's still to do
                        play(left)
                    } label: {
                        Label("Começar", systemImage: "play.fill").font(.geist(14, .semibold)).foregroundStyle(Color(hex: 0x05140F))
                            .padding(.horizontal, 16).frame(minHeight: 44).background(Capsule().fill(Area.mint.gradient))
                    }
                    .buttonStyle(Pressable())
                    .accessibilityLabel("Começar \(r.title)").accessibilityIdentifier("next.action")
                }
                laterRow
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("now.routine")
        }
    }

    private func workout(_ w: NowWorkout) -> some View {
        let started = Day.minuteOfDay(Date(timeIntervalSince1970: w.start / 1000))
        return Card {
            Eyebrow(text: "Agora", color: .mint)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(w.name).font(.geist(17, .semibold))
                    Text("Treino em curso · começou \(PlanFormat.at(started))").font(.geist(12)).foregroundStyle(Color.soft)
                }
                Spacer(minLength: 8)
                Button { store.openWorkout = OpenSession(id: w.id) } label: {
                    Label("Continuar", systemImage: "play.fill").font(.geist(14, .semibold)).foregroundStyle(Color(hex: 0x05140F))
                        .padding(.horizontal, 16).frame(minHeight: 44).background(Capsule().fill(Area.mint.gradient))
                }
                .buttonStyle(Pressable())
                .accessibilityLabel("Continuar \(w.name)").accessibilityIdentifier("next.action")
            }
            laterRow
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("now.workout")
    }

    /// The next habit, as "A seguir" showed it: brushing and reading start their player, the rest is marked done (with
    /// Desfazer)
    private func habit(_ p: PromiseItem) -> some View {
        let brush = p.title.lowercased().contains("brush"), read = p.title.lowercased().hasPrefix("read")
        return Card {
            Eyebrow(text: "Agora", color: .mint)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title).font(.geist(16, .bold))
                    Text("\(store.timeLabel(p)) · \(p.kind == .mustDo ? "essencial" : p.schedule.summary)").font(.geist(12.5)).foregroundStyle(Color.soft)
                }
                Spacer()
                Button { if brush { store.brushingOpen = true } else if read { store.readingOpen = true } else { store.markNowDone(p) } } label: {
                    Image(systemName: brush || read ? "play.fill" : "checkmark").font(.geist(17, .bold)).foregroundStyle(Color(hex: 0x032018))
                        .frame(width: 44, height: 44).background(Circle().fill(Area.mint.gradient))
                }
                .accessibilityLabel(brush || read ? "Começar \(p.title)" : "Marcar \(p.title) como feito").accessibilityIdentifier("next.action")
            }
            laterRow
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("now.habit")
    }

    /// «Depois»: what comes after, in one line; a tap shows today's habits
    @ViewBuilder private var laterRow: some View {
        if showLater, !later.isEmpty {
            Divider().overlay(Color.white.opacity(0.06))
            Button(action: openLater) {
                HStack(spacing: 8) {
                    Text("Depois: " + NowRule.laterText(later)).font(.geist(12.5)).foregroundStyle(Color.soft).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(Color.faint)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Mostra os hábitos de hoje").accessibilityIdentifier("now.later")
        }
    }
}

// MARK: - Quick logs and records not sent

/// The quick logs on Today, ordered by use (decision of phase 2.4): how many times each was used in the 14 days before
/// today, so the order doesn't move under your finger during the day. A tie keeps today's order, the order of the cases.
enum TodayQuickLog: String, CaseIterable {
    case food, water

    static func ordered(uses: [TodayQuickLog: Int]) -> [TodayQuickLog] {
        allCases.enumerated().sorted { a, b in
            let ua = uses[a.element] ?? 0, ub = uses[b.element] ?? 0
            return ua != ub ? ua > ub : a.offset < b.offset
        }.map { $0.element }
    }
}

enum TodayRules {
    /// «Ver o que falta» only when something is waiting and sending it is failing: a technical warning only when
    /// there is something to see
    static func showsUnsent(pending: Int, failing: Bool) -> Bool { pending > 0 && failing }

    static func unsentText(_ n: Int) -> String {
        n == 1 ? "1 registo ainda não chegou ao servidor. Está guardado neste iPhone." : "\(n) registos ainda não chegaram ao servidor. Estão guardados neste iPhone."
    }

    /// A habit's circle: done, «Não se aplica» (not the same as a skip or «Não fiz», which is a miss), skipped, or open
    static func habitIcon(_ status: LogStatus?, notApplicable: Bool) -> String {
        if notApplicable { return DataState.unavailable.icon }
        switch status {
        case .done?, .tiny?: return "checkmark.circle.fill"
        case .skipped?: return "minus.circle"
        case nil: return "circle"
        }
    }

    /// What VoiceOver says for a habit's circle: its name and its answer
    static func habitLabel(_ title: String, _ status: LogStatus?, notApplicable: Bool) -> String {
        if notApplicable { return "\(title), não se aplica" }
        switch status {
        case .done?, .tiny?: return "\(title), feito"
        case .skipped?: return "\(title), não fiz"
        case nil: return "\(title), por responder"
        }
    }
}

@MainActor
extension Store {
    /// How many times each quick log was used in the 14 days before `today`: food you logged yourself (not what a
    /// routine adds when you tick it) and water, each moment counted once (a meal of three foods is one use)
    func quickLogUses(today: String = Day.today) -> [TodayQuickLog: Int] {
        let days = Set((1...14).map { Day.add(-$0, to: today) })
        let food = Set(all(FoodEntry.self).filter { $0.promiseId == nil && days.contains($0.date) }.map { "\($0.date) \($0.minute)" })
        let water = Set(all(WaterEntry.self).filter { days.contains($0.date) }.map { "\($0.date) \($0.minute)" })
        return [.food: food.count, .water: water.count]
    }

    /// The water quick log: logs at once and shows Desfazer, which removes just what it added
    func logWaterNow(_ ml: Double) {
        guard canChange else { return }
        let before = Set(records(WaterEntry.kind).keys)
        addWater(ml)
        let added = records(WaterEntry.kind).keys.filter { !before.contains($0) }
        guard !added.isEmpty else { return }
        UndoCenter.shared.show("Água +\(Int(ml)) ml") { [weak self] in
            for id in added { self?.put(WaterEntry.kind, id, nil) }
        }
    }
}
