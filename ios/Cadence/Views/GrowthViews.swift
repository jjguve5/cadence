// Growth: journal and what affects you, mood grid, goals, experiments, weekly review, year in pixels, Cadence age,
// levers, the weekly challenge and badges. And the minute-by-minute signals.
import Charts
import SwiftUI

struct YouGrowthView: View {
    @EnvironmentObject var store: Store
    @State private var addingGoal: LifeGoal?
    @State private var addingExperiment: Experiment?

    var body: some View {
        Screen(glow: .mind) {
            NavigationLink { LearnedView() } label: {
                Card(tint: .mind) {
                    HStack { Eyebrow(text: "O que o Cadence aprendeu", icon: "sparkle.magnifyingglass", color: .mind); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                    Text("Até que ponto as previsões batem certo com os teus dias, com o tamanho das amostras e a incerteza.").font(.geist(12.5)).foregroundStyle(Color.soft)
                }
            }
            .buttonStyle(Pressable())
            .accessibilityIdentifier("growth.learned")
            JournalCard()
            MoodGrid()
            challengeCard
            goalsCard
            experimentsCard
            reviewCard
            ageCard
            leversCard
            PixelsCard()
            badgesCard
        }
        .navigationTitle("Crescimento")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $addingGoal) { GoalForm(goal: $0) }
        .sheet(item: $addingExperiment) { ExperimentForm(experiment: $0) }
    }

    private var challengeCard: some View {
        let c = store.challenge()
        return Card(tint: Color(hex: 0xFFD166)) {
            HStack { Eyebrow(text: "Desafio da semana · \(Self.areaText[c.area] ?? c.area)", icon: "flag.checkered", color: Color(hex: 0xFFD166)); Spacer(); if c.done { Chip(text: "feito", color: .good) } }
            Text(c.text).font(.geist(15, .semibold))
            if !c.done { SoftButton(title: "Já fiz", icon: "checkmark") { var x = c; x.done = true; store.save(x) } }
        }
    }

    private var goalsCard: some View {
        Card {
            HStack { Eyebrow(text: "Objetivos", icon: "target"); Spacer(); Button { addingGoal = LifeGoal(title: "", metric: "books", target: 24) } label: { Image(systemName: "plus") }.tint(.mind) }
            ForEach(store.all(LifeGoal.self)) { g in
                let p = store.goalProgress(g)
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(g.title).font(.geist(14, .medium)); Spacer(); Text("\(kg((p.current * 10).rounded() / 10)) / \(kg(g.target))").font(.mono(12.5)).foregroundStyle(Color.soft) }
                    Bar(progress: g.metric == "weight" ? 1 - abs(g.target - p.current) / max(1, abs(g.target - store.profile.weightKg) + 1) : p.current / max(0.1, g.target), area: .mind)
                    if let eta = p.eta { Text("A este ritmo: \(Day.date(eta).formatted(.dateTime.day().month().year()))" + (g.by.map { eta <= $0 ? " · a tempo" : " · depois da tua data" } ?? "")).font(.geist(11.5)).foregroundStyle(Color.faint) }
                }
                .contextMenu { Button("Apagar", role: .destructive) { store.remove(g) } }
            }
        }
    }

    private var experimentsCard: some View {
        Card {
            HStack { Eyebrow(text: "Experiências · 14 dias", icon: "flask.fill"); Spacer(); Button { addingExperiment = Experiment(title: "") } label: { Image(systemName: "plus") }.tint(.mind) }
            ForEach(store.all(Experiment.self).sorted { $0.start > $1.start }) { e in
                let r = store.experimentResult(e)
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(e.title).font(.geist(14, .semibold)); Spacer(); Chip(text: r.daysIn >= e.days ? "terminada" : "dia \(r.daysIn) de \(e.days)", color: .mind) }
                    let before = (1...14).compactMap { store.metric(e.metric, on: Day.add(-$0, to: e.start)) }
                    let during = (0..<r.daysIn).compactMap { store.metric(e.metric, on: Day.add($0, to: e.start)) }
                    if let x = Engine.experiment(before: before, during: during) {
                        Text(x.summary).font(.geist(12)).foregroundStyle(Color.faint)
                    }
                    if let b = r.before, let d = r.during {
                        let diff = d - b
                        Text("\(Self.metricText[e.metric] ?? e.metric.capitalized): \(format(e.metric, b)) antes → \(format(e.metric, d)) durante (\(diff >= 0 ? "+" : "")\(format(e.metric, diff, delta: true)))").font(.geist(12.5)).foregroundStyle(Color.soft)
                    }
                }
                .contextMenu { Button("Apagar", role: .destructive) { store.remove(e) } }
            }
            Text("Uma mudança de cada vez, comparada com as tuas duas semanas anteriores.").font(.geist(11.5)).foregroundStyle(Color.faint)
        }
    }

    /// What the challenge's area and an experiment's metric are called on screen. Both are stored keys and stay in
    /// English; only these names are Portuguese.
    private static let areaText = ["sleep": "sono", "protein": "proteína", "water": "água", "steps": "passos", "reading": "leitura"]
    private static let metricText = ["sleep": "Sono", "readiness": "Prontidão", "hrv": "VFC", "rhr": "FC em repouso", "steps": "Passos", "mood": "Humor"]

    private func format(_ metric: String, _ v: Double, delta: Bool = false) -> String {
        switch metric {
        case "sleep": return duration(Int(v.rounded()))
        case "steps": return Int(v).formatted()
        default: return String(format: "%.1f", v)
        }
    }

    private var reviewCard: some View {
        NavigationLink { WeeklyReviewView() } label: {
            Card {
                HStack { Eyebrow(text: "Revisão semanal", icon: "calendar.badge.clock"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                Text(store.weekReview(store.week).prefix(3).map { "\($0.0) \($0.1)" }.joined(separator: " · ")).font(.geist(13)).foregroundStyle(Color.soft)
            }
        }
        .buttonStyle(.plain)
    }

    private var ageCard: some View {
        Group {
            if let a = store.cadenceAge() {
                Card(tint: .mint) {
                    Eyebrow(text: "Idade da forma física · estimativa", icon: "hourglass", color: .mint)
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.1f", a.age)).font(.geist(30, .bold))
                        Text("face aos \(store.profile.age) do calendário").font(.geist(12.5)).foregroundStyle(Color.soft)
                    }
                    ForEach(a.parts, id: \.0) { name, years in HStack { Text(name).font(.geist(13)); Spacer(); Text(String(format: "%+.1f anos", years)).font(.mono(13)).foregroundStyle(years <= 0 ? Color.good : Color.warn) } }
                    Text("Uma estimativa da forma física a partir da FC em repouso, do VO₂ máx., dos passos e da regularidade do sono. Não é a tua idade biológica nem uma medida médica.").font(.geist(11)).foregroundStyle(Color.faint)
                }
            }
        }
    }

    private var leversCard: some View {
        let levers = store.levers(), effects = store.journalEffects()
        return Group {
            if !levers.isEmpty || !effects.isEmpty {
                Card {
                    Eyebrow(text: "O que te afeta", icon: "slider.horizontal.3")
                    ForEach(levers, id: \.self) { Text("Antes dos teus melhores dias: \($0.lowercased())").font(.geist(13.5)) }
                    ForEach(effects, id: \.question) { e in
                        if let s = e.sleep, abs(s) >= 10 { Text("\(journalText(e.question)): \(s > 0 ? "+" : "")\(s) min de sono nessa noite" + (e.readiness.map { ", prontidão \($0 > 0 ? "+" : "")\($0)" } ?? "")).font(.geist(13)).foregroundStyle(Color.soft) }
                    }
                    Text("Padrões dos teus próprios dias, não provas.").font(.geist(11)).foregroundStyle(Color.faint)
                }
            }
        }
    }

    private var badgesCard: some View {
        Card {
            Eyebrow(text: "Medalhas", icon: "rosette")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(store.badges, id: \.0) { name, icon, got in
                    VStack(spacing: 4) {
                        Image(systemName: icon).font(.geist(20)).foregroundStyle(got ? Color(hex: 0xFFD166) : Color.faint).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(got ? 0.1 : 0.04)))
                        Text(name).font(.geist(9.5)).multilineTextAlignment(.center).foregroundStyle(got ? Color.ink : Color.faint)
                    }
                }
            }
        }
    }
}

struct JournalCard: View {
    @EnvironmentObject var store: Store
    var day: String = Day.add(-1, to: Day.today)
    var canPostpone = false
    var body: some View {
        let entry = store.record(JournalDay.self, day) ?? JournalDay(date: day)
        Card(tint: .mind) {
            HStack {
                Eyebrow(text: day == Day.today ? "Hoje, rapidamente" : "Ontem, rapidamente", icon: "book.pages", color: .mind)
                Spacer()
                if canPostpone { Button("Agora não") { store.put("journalLater", Day.today, .bool(true)) }.font(.geist(12)).tint(.soft).accessibilityIdentifier("journal.later") }
            }
            ForEach(journalQuestions, id: \.self) { q in
                HStack {
                    Text(journalText(q)).font(.geist(13.5))
                    Spacer()
                    ForEach([true, false], id: \.self) { yes in
                        let on = entry.answered.contains(q) && entry.yes.contains(q) == yes
                        Button(yes ? "Sim" : "Não") {
                            var e = entry
                            if !e.answered.contains(q) { e.answered.append(q) }
                            e.yes.removeAll { $0 == q }
                            if yes { e.yes.append(q) }
                            store.save(e)
                        }
                        .buttonStyle(.plain).font(.geist(12, .semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(on ? Color.mind.opacity(0.5) : .white.opacity(0.07)))
                    }
                }
            }
            ForEach(store.prompts(), id: \.self) { Text($0).font(.geist(12.5)).foregroundStyle(Color.soft).italic() }
        }
    }
}

/// Energy × pleasantness, with precise feeling words instead of a plain 1–5
struct MoodGrid: View {
    @EnvironmentObject var store: Store
    @State private var picked: (Double, Double)?
    static let words: [[String]] = [
        ["Stressed", "Wired", "Excited", "Energized"],
        ["Tense", "Restless", "Upbeat", "Motivated"],
        ["Low", "Flat", "Calm", "Content"],
        ["Drained", "Tired", "Relaxed", "Peaceful"],
    ]
    /// What each stored word says on screen; MoodEntry.word keeps the English word (QuickCapture saves the same ones)
    static let wordText = ["Stressed": "Stressado", "Wired": "Elétrico", "Excited": "Entusiasmado", "Energized": "Enérgico",
                           "Tense": "Tenso", "Restless": "Inquieto", "Upbeat": "Animado", "Motivated": "Motivado",
                           "Low": "Em baixo", "Flat": "Apático", "Calm": "Calmo", "Content": "Satisfeito",
                           "Drained": "Esgotado", "Tired": "Cansado", "Relaxed": "Relaxado", "Peaceful": "Sereno"]
    var body: some View {
        Card {
            Eyebrow(text: "Como te sentes?", icon: "face.smiling")
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(0..<4, id: \.self) { r in
                    GridRow {
                        ForEach(0..<4, id: \.self) { c in
                            let energy = 1 - Double(r) / 1.5, pleasant = Double(c) / 1.5 - 1
                            Button {
                                store.save(MoodEntry(energy: energy, pleasant: pleasant, word: Self.words[r][c]))
                            } label: {
                                Text(Self.wordText[Self.words[r][c]] ?? Self.words[r][c]).font(.geist(11, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hue: c < 2 ? (r < 2 ? 0.0 : 0.62) : (r < 2 ? 0.12 : 0.38), saturation: 0.55, brightness: 0.35)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let last = store.all(MoodEntry.self).filter({ $0.date == Day.today }).max(by: { $0.minute < $1.minute }) {
                Text("Último registo: \((Self.wordText[last.word] ?? last.word).lowercased()) às \(clock(last.minute))." + strategy(last)).font(.geist(12.5)).foregroundStyle(Color.soft)
            }
        }
    }
    private func strategy(_ m: MoodEntry) -> String {
        if m.energy > 0 && m.pleasant < 0 { return " Experimenta o suspiro fisiológico: duas inspirações, uma expiração longa." }
        if m.energy <= 0 && m.pleasant < 0 { return " Uma caminhada curta lá fora melhora a energia e o humor." }
        if m.energy <= 0 && m.pleasant >= 0 { return " Boa altura para ler ou para te deitares cedo." }
        return " Aproveita: o teu melhor trabalho cabe aqui."
    }
}

struct PixelsCard: View {
    @EnvironmentObject var store: Store
    @State private var metric = "score"
    var body: some View {
        let year = String(Day.today.prefix(4))
        let start = year + "-01-01"
        let count = Day.between(start, Day.today) + 1
        Card {
            HStack {
                Eyebrow(text: "Ano em píxeis", icon: "square.grid.4x3.fill")
                Spacer()
                Picker("", selection: $metric) { Text("Pontuação").tag("score"); Text("Sono").tag("sleep"); Text("Humor").tag("mood"); Text("Treino").tag("training") }.pickerStyle(.menu).tint(.mint)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 14), spacing: 2) {
                ForEach(0..<max(1, count), id: \.self) { i in
                    let d = Day.add(i, to: start)
                    RoundedRectangle(cornerRadius: 2).fill(color(d)).aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }
    private func color(_ d: String) -> Color {
        switch metric {
        case "sleep": return store.health[d]?.sleep.map { Color.sleep.opacity(min(1, Double($0.asleep) / Double(store.profile.sleepNeed))) } ?? .white.opacity(0.05)
        case "mood": return store.days[d]?.rating.map { Color.mind.opacity(Double($0) / 5) } ?? .white.opacity(0.05)
        case "training": return store.sessions(on: d).isEmpty ? .white.opacity(0.05) : Color.train
        default: return store.days[d]?.score.map { Color.mint.opacity(0.15 + Double($0) / 120) } ?? .white.opacity(0.05)
        }
    }
}

struct WeeklyReviewView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let week = store.week
        Screen(glow: .mind) {
            Card {
                Eyebrow(text: "Semana de \(Day.date(week).formatted(.dateTime.day().month(.wide)))")
                ForEach(store.weekReview(week), id: \.0) { k, v in HStack { Text(k).font(.geist(14)); Spacer(); Text(v).font(.geist(14, .semibold)) } }
            }
            TimeAuditCard(week: week)
            Card(tint: .mint) {
                Eyebrow(text: "Uma coisa para experimentar na próxima semana", color: .mint)
                Text(store.challenge().text).font(.geist(15, .semibold))
            }
            let quotes = store.all(ReadingSession.self).filter { $0.date >= week && $0.quote != nil }
            if !quotes.isEmpty { Card { Eyebrow(text: "Citações desta semana"); ForEach(quotes) { Text("«\($0.quote!)»").font(.serif(13)).italic() } } }
            let notes = (0..<7).compactMap { store.days[Day.add($0, to: week)]?.note }.filter { !$0.isEmpty }
            if !notes.isEmpty { Card { Eyebrow(text: "As tuas linhas"); ForEach(notes, id: \.self) { Text($0).font(.geist(13)) } } }
        }
        .navigationTitle("Revisão semanal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GoalForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var goal: LifeGoal
    var body: some View {
        NavigationStack {
            Form {
                TextField("Objetivo (agachamento 120 kg, 24 livros…)", text: $goal.title)
                Picker("Medido por", selection: $goal.metric) { Text("Levantamento (1RM estimado)").tag("lift"); Text("Livros este ano").tag("books"); Text("Média de horas de sono").tag("sleep"); Text("Peso corporal").tag("weight"); Text("Média de passos").tag("steps") }
                if goal.metric == "lift" {
                    Picker("Exercício", selection: $goal.exerciseId) {
                        Text("Escolher").tag(String?.none)
                        let unique = Dictionary(store.sessions().flatMap { $0.order }.map { ($0.exerciseId, $0.name) }, uniquingKeysWith: { a, _ in a })
                        ForEach(unique.sorted { $0.value < $1.value }, id: \.key) { Text($0.value).tag(Optional($0.key)) }
                    }
                }
                TextField("Alvo", value: $goal.target, format: .number).keyboardType(.decimalPad)
                Toggle("Até uma data", isOn: Binding(get: { goal.by != nil }, set: { goal.by = $0 ? Day.add(120, to: Day.today) : nil }))
                if goal.by != nil { DatePicker("Até", selection: Binding(get: { Day.date(goal.by ?? Day.today) }, set: { goal.by = Day.key($0) }), displayedComponents: .date) }
            }
            .cadenceList()
            .navigationTitle("Objetivo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(goal); dismiss() }.disabled(goal.title.isEmpty) }
            }
        }
    }
}

struct ExperimentForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var experiment: Experiment
    var body: some View {
        NavigationStack {
            Form {
                TextField("A mudança (sem cafeína depois das 14:00…)", text: $experiment.title)
                Picker("Observar", selection: $experiment.metric) { Text("Sono").tag("sleep"); Text("Prontidão").tag("readiness"); Text("VFC").tag("hrv"); Text("FC em repouso").tag("rhr"); Text("Passos").tag("steps"); Text("Humor").tag("mood") }
                Stepper("Durante \(experiment.days) dias", value: $experiment.days, in: 7...28, step: 7)
                DatePicker("A partir de", selection: Binding(get: { Day.date(experiment.start) }, set: { experiment.start = Day.key($0) }), displayedComponents: .date)
            }
            .cadenceList()
            .navigationTitle("Experiência")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Começar") { store.save(experiment); dismiss() }.disabled(experiment.title.isEmpty) }
            }
        }
    }
}

/// The minute-by-minute signals for one day
struct IntradayCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject var intraday = IntradayStore.shared
    var day = Day.today

    var body: some View {
        Card(tint: .train) {
            Eyebrow(text: "Minuto a minuto", icon: "waveform.path.ecg.rectangle", color: .train)
            if let d = intraday.day(day) {
                let hr = d.hr.compactMap { k, v in Int(k).map { ($0, v) } }.filter { $0.0 >= 0 }.sorted { $0.0 < $1.0 }
                if hr.count > 10 {
                    Chart {
                        ForEach(hr, id: \.0) { m, v in LineMark(x: .value("min", m), y: .value("bpm", v)).foregroundStyle(Color.train).lineStyle(StrokeStyle(lineWidth: 1)) }
                        ForEach(store.stressMoments(d), id: \.start) { s in RectangleMark(xStart: .value("a", s.start), xEnd: .value("b", s.end)).foregroundStyle(Color.warn.opacity(0.2)) }
                    }
                    .chartXAxis { AxisMarks(values: [360, 720, 1080]) { v in AxisValueLabel { Text(clock(v.as(Int.self) ?? 0)) } } }
                    .frame(height: 120)
                }
                ForEach(store.heartRateEvents(d), id: \.self) { Text($0).font(.geist(12.5)).foregroundStyle(Color.warn) }
                let stress = store.stressMoments(d)
                if !stress.isEmpty { Text("\(stress.count) momentos de stress (coração acelerado, corpo parado): " + stress.prefix(3).map { "\(clock($0.start))" }.joined(separator: ", ")).font(.geist(12.5)).foregroundStyle(Color.soft) }
                if let s = store.sessions(on: day).first(where: { $0.end != nil }), let hrr = store.heartRateRecovery(s, d) {
                    Text("Recuperação da frequência cardíaca depois das séries: −\(hrr) bpm num minuto" + (hrr <= 12 ? " (baixa: mais cardio leve ajuda)" : " (boa)")).font(.geist(12.5)).foregroundStyle(hrr <= 12 ? Color.warn : Color.good)
                }
                if let o = store.oxygenDips(d) {
                    Text(String(format: "Quedas de oxigénio: %.1f por hora, mínimo de %.0f%%", o.perHour, o.lowest) + (o.perHour >= 5 ? ". Se continuar alto durante semanas, fala disto a um médico." : "")).font(.geist(12.5)).foregroundStyle(o.perHour >= 5 ? Color.warn : Color.soft)
                }
                if !d.irn.isEmpty { Text("Alertas de ritmo irregular registados: \(d.irn.count). O último: \(d.irn.max() ?? "").").font(.geist(12.5)).foregroundStyle(Color.warn) }
                else { Text("Sem alertas de ritmo irregular.").font(.geist(12.5)).foregroundStyle(Color.soft) }
            } else {
                Text("A carregar o dia do teu Air…").font(.geist(13)).foregroundStyle(Color.soft)
            }
        }
        .task { await intraday.load(day) }
    }
}

struct MoreSignalsCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Card {
            Eyebrow(text: "Ritmo e carga", icon: "clock.badge.checkmark")
            if let c = store.chronotype() {
                HStack { Text("Cronótipo").font(.geist(14)); Spacer(); Text(c.label).font(.geist(14, .semibold)) }
                Text("Meio do sono às \(clock((c.midFree + 1440) % 1440)) nos dias livres e às \(clock((c.midWork + 1440) % 1440)) nos dias de trabalho: jet lag social de \(duration(c.jetlag)).").font(.geist(12.5)).foregroundStyle(c.jetlag > 60 ? Color.warn : Color.soft)
            }
            if let t = store.trainingLoad() {
                HStack { Text("Carga de treino").font(.geist(14)); Spacer(); Text(String(format: "%.2f", t.ratio)).font(.mono(14, .semibold)).foregroundStyle(t.ratio > 1.5 ? Color.warn : t.ratio < 0.8 ? Color.soft : Color.good) }
                Text(t.ratio > 1.5 ? "Esta semana está muito mais dura do que o último mês: subir depressa demais aumenta o risco de lesão." : t.ratio < 0.8 ? "Mais leve do que o habitual: bom para uma semana de descarga." : "Na zona certa: o suficiente para evoluir.").font(.geist(12.5)).foregroundStyle(Color.soft)
            }
            let steps = (0..<7).compactMap { store.health[Day.add(-$0, to: Day.today)]?.steps }
            if !steps.isEmpty {
                let avg = steps.reduce(0, +) / Double(steps.count)
                HStack { Text("Passos na curva da longevidade").font(.geist(14)); Spacer(); Text(Int(avg).formatted()).font(.mono(14, .semibold)) }
                Bar(progress: min(1, avg / 10000), area: .fuel)
                Text(avg >= 8000 ? "Já passaste o ponto em que o benefício estabiliza (8000 a 10 000 abaixo dos 60 anos, Lancet 2022)." : "Mais \(Int(max(0, 8000 - avg)).formatted()) por dia chegam à parte da curva onde está a maior parte do benefício.").font(.geist(12)).foregroundStyle(Color.soft)
            }
        }
    }
}
