// Today: the morning brief, readiness with its reasons, what's next, rings, today's promises, closing the day.
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var closing = false
    @State private var editing: PromiseItem?
    @State private var briefHidden = false
    @State private var loggingFood = false
    @State private var settingUp = false
    @State private var capturing = false
    @State private var showingYou = false

    private var greeting: String {
        let m = Day.minuteOfDay(store.tick)
        return m < 12 * 60 ? "Bom dia" : m < 18 * 60 ? "Boa tarde" : "Boa noite"
    }

    var body: some View {
        NavigationStack {
            Screen(glow: .mint) {
                header
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
                DayRings(loggingFood: $loggingFood)
                FocusCard()
                nextUp
                FoodGoalsCard()
                ShowerTodayCard()
                GymBagCard()
                readinessCard
                if Day.minuteOfDay(store.tick) < 11 * 60 || store.weatherCall()?.umbrella == true { WeatherCard() }
                promisesCard
                top3Card
                closeCard
                syncLine
            }
            .refreshable { await store.refreshAll(force: true) }
            .sheet(isPresented: $closing) { CloseDayView() }
            .sheet(item: $editing) { PromiseEditor(promise: $0) }
            .sheet(isPresented: $loggingFood) { FoodLogSheet() }
            .sheet(isPresented: $settingUp) { SmartSetup() }
            .sheet(isPresented: $capturing) { QuickCaptureSheet() }
            .sheet(isPresented: $showingYou) { YouView() }
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

    private var nextUp: some View {
        let minute = Day.minuteOfDay(store.tick)
        let next = store.due().first { store.status($0) == nil && store.time(of: $0) + 90 >= minute }
        return Group {
            if let next {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Eyebrow(text: "A seguir", icon: "play")
                            Text(next.title).font(.geist(16, .bold))
                            Text("\(store.timeLabel(next)) · \(next.kind == .mustDo ? "essencial" : next.schedule.summary)").font(.geist(12.5)).foregroundStyle(Color.soft)
                        }
                        Spacer()
                        let brush = next.title.lowercased().contains("brush"), read = next.title.lowercased().hasPrefix("read")
                        Button { if brush { store.brushingOpen = true } else if read { store.readingOpen = true } else { store.log(next, .done) } } label: {
                            Image(systemName: brush || read ? "play.fill" : "checkmark").font(.geist(17, .bold)).foregroundStyle(Color(hex: 0x032018))
                                .frame(width: 44, height: 44).background(Circle().fill(Area.mint.gradient))
                        }
                        .accessibilityLabel(brush || read ? "Começar \(next.title)" : "Marcar \(next.title) como feito").accessibilityIdentifier("next.action")
                    }
                }
            }
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
        let w = store.week(promise, upTo: day)
        HStack(spacing: 10) {
            Button {
                if status == nil { store.log(promise, on: day, .done) } else { store.undo(promise, on: day) }
            } label: {
                Image(systemName: status == .done || status == .tiny ? "checkmark.circle.fill" : status == .skipped ? "minus.circle" : "circle")
                    .font(.geist(22)).foregroundStyle(status == nil ? Color.soft : status == .skipped ? Color.faint : Color.good)
            }
            .buttonStyle(.plain)
            Image(systemName: promise.icon).foregroundStyle(Color.soft).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(promise.title).font(.geist(14.5, .medium)).strikethrough(status == .skipped)
                Text("\(store.timeLabel(promise, on: day)) · \(w.done)/\(w.total) esta semana").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            Spacer()
            if status == nil, promise.title.lowercased().contains("brush") {
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
