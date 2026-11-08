// Training: templates and sessions, the workout one exercise at a time (the target apart from what you did, the rest
// with its reason, changes of plan with confirmation, pause and the summary), exercise pictures from RepDB, progress
// with projections, and the muscle maps (freshness and "are they growing?").
import Charts
import SwiftUI
import UserNotifications

struct TrainingView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var catalog = Catalog.shared
    @State private var editing: WorkoutTemplate?
    @State private var building = false
    @State private var selected = Set<String>()
    @State private var open: String?
    @State private var previewing: WorkoutTemplate?
    @State private var startAfterPreview: String?

    var body: some View {
        Screen(glow: .train) {
            if let s = store.activeSession {
                Button { open = s.id } label: {
                    Card(tint: .train) {
                        HStack {
                            Eyebrow(text: "Em curso", icon: "flame.fill", color: .train)
                            Spacer()
                            if s.isPaused { StateTag(state: .pending, text: "Em pausa") }
                        }
                        Text(s.name).font(.geist(18, .bold))
                        Text("\(s.sets.filter(\.done).count) \(s.sets.filter(\.done).count == 1 ? "série" : "séries") · \(Int(s.volume).formatted()) kg").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("training.active")
            }
            Card {
                Eyebrow(text: "Começar uma sessão", icon: "play.fill")
                ForEach(store.templates) { t in
                    HStack {
                        // The template itself opens «antes de começar»; the play button starts it straight away
                        Button { previewing = t } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.geist(15, .semibold)).foregroundStyle(Color.ink)
                                Text(t.exercises.map(\.name).prefix(3).joined(separator: " · ")).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Mostra o treino antes de começar")
                        .accessibilityIdentifier("training.template.\(t.name)")
                        Button { editing = t } label: { Image(systemName: "pencil").foregroundStyle(Color.soft) }.buttonStyle(.plain).padding(.trailing, 6)
                        Button { open = start(t) } label: {
                            Image(systemName: "play.fill").font(.geist(13, .bold)).foregroundStyle(Color(hex: 0x2A0610)).frame(width: 36, height: 36).background(Circle().fill(Area.train.gradient))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Começar \(t.name)").accessibilityIdentifier("training.start.\(t.name)")
                    }
                }
                Button { editing = WorkoutTemplate(name: "Novo modelo", exercises: []) } label: { Label("Novo modelo", systemImage: "plus").font(.geist(13, .semibold)) }.tint(.train)
            }
            Card {
                HStack { Eyebrow(text: "Sessão pelo mapa corporal", icon: "figure.strengthtraining.traditional"); Spacer() }
                Text("Toca nos músculos que queres treinar: o Cadence monta uma sessão com exercícios que os trabalham.").font(.geist(12.5)).foregroundStyle(Color.soft)
                MuscleTapper(selected: $selected)
                if !selected.isEmpty {
                    Button { open = startFromMuscles() } label: { Text("Começar: \(selected.compactMap { groupNames[$0] }.sorted().joined(separator: ", "))").font(.geist(14, .semibold)).foregroundStyle(Color.train) }
                }
            }
            NavigationLink { GrowthView() } label: { GrowthCard() }.buttonStyle(.plain)
            RestOrTrainCard()
            AirWorkoutsCard()
            NavigationLink { BodyProgressView() } label: {
                Card {
                    HStack { Eyebrow(text: "Evolução do corpo", icon: "figure.arms.open"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                    Text("Fotografias, dez medidas, força por quilo, mapa de atividade").font(.geist(13)).foregroundStyle(Color.soft)
                }
            }
            .buttonStyle(.plain)
            NavigationLink { ProgressListView() } label: {
                Card {
                    HStack { Eyebrow(text: "Progresso e projeções", icon: "chart.line.uptrend.xyaxis"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                    let last = store.sessions().filter { $0.end != nil }.prefix(3)
                    ForEach(Array(last)) { s in
                        HStack { Text(s.name).font(.geist(13.5)); Spacer(); Text("\(Day.date(s.date).formatted(.dateTime.day().month())) · \(Int(s.volume).formatted()) kg").font(.mono(12)).foregroundStyle(Color.soft) }
                    }
                    if last.isEmpty { Text("Termina uma sessão para veres as curvas de 1RM estimado.").font(.geist(13)).foregroundStyle(Color.soft) }
                }
            }
            .buttonStyle(.plain)
            Text("Dados de exercícios da RepDB (repdb.co) · Mapa corporal baseado no GymMane, de InlitX").font(.geist(10.5)).foregroundStyle(Color.faint)
        }
        .navigationTitle("Treino")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.seedTemplates()
            store.closeExpiredSessions() // a session left open past 23:59 is partial now (phase 2.6)
            await catalog.load()
        }
        .sheet(item: $editing) { TemplateEditor(template: $0) }
        .sheet(item: $previewing, onDismiss: {
            // «Começar treino» in the preview: the workout opens once the preview is gone
            if let id = startAfterPreview { startAfterPreview = nil; open = id }
        }) { t in
            TrainingPreview(template: t) { current in
                startAfterPreview = start(current)
                previewing = nil
            }
        }
        .navigationDestination(item: $open) { WorkoutView(sessionId: $0, showsUndo: false) }
    }

    /// Starts a session from a template, or goes back to the one in progress. The planned sets carry their targets
    /// (none without history) and warm-ups only on the first exercise of each muscle group new in the session; the
    /// suggested weight is never written in as if you had done it.
    private func start(_ t: WorkoutTemplate) -> String {
        store.closeExpiredSessions()
        if let s = store.activeSession { return s.id }
        let session = store.newSession(t, plan: store.plan(t))
        store.save(session)
        return session.id
    }

    private func startFromMuscles() -> String {
        let picks = selected.compactMap { g -> TemplateExercise? in
            let options = catalog.exercises.filter { $0.groups.contains(g) && $0.category == "strength" }
            let known = options.first { !store.lastSets($0.id).isEmpty } ?? options.first { !$0.bodyweight } ?? options.first
            return known.map { TemplateExercise(exerciseId: $0.id, name: $0.name) }
        }
        selected = []
        return start(WorkoutTemplate(name: "Sessão pelo mapa corporal", exercises: picks))
    }
}

/// Treino · antes de começar (design v17, N_Treino): the plan, what's suggested for today, which exercises get a
/// warm-up and why the others don't, and the weights («escolhes tu» while there's no history)
struct TrainingPreview: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var template: WorkoutTemplate
    var onStart: (WorkoutTemplate) -> Void
    @State private var editing: WorkoutTemplate?

    /// The template as saved now (the editor may have changed it)
    private var current: WorkoutTemplate { store.record(WorkoutTemplate.self, template.id) ?? template }

    var body: some View {
        let t = current
        let plan = store.plan(t)
        let today = t.weekdays.contains(Day.weekday(Day.today))
        NavigationStack {
            Screen(glow: .train) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(today ? "Treino de hoje" : "Modelo de treino").font(.geist(13)).foregroundStyle(Color.soft)
                    Text(t.name).font(.geist(26, .bold))
                }
                .padding(.top, 4)
                HStack(spacing: 8) {
                    if today { StateTag(state: .pending, text: "Planeado") }
                    Text("\(t.exercises.count) \(t.exercises.count == 1 ? "exercício" : "exercícios") · cerca de \(t.minutes) min").font(.geist(12)).foregroundStyle(Color.soft)
                }
                if let r = store.readiness(), r.score < 50 {
                    Card(state: .suggested) {
                        HStack { Eyebrow(text: "Para hoje"); Spacer(); StateTag(state: .suggested) }
                        Text("Cargas moderadas e deixa o aquecimento decidir: se pesar, faz menos uma ou duas repetições por série.").font(.geist(14))
                        WhyLine(text: "prontidão \(r.score) hoje, abaixo de 50.")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("training.preview.today")
                }
                PrimaryButton(title: store.activeSession == nil ? "Começar treino" : "Continuar o treino em curso", area: .mint) { onStart(t) }
                    .accessibilityIdentifier("training.preview.start")
                exercises(plan)
                weights(plan)
                TrainingButton(title: "Editar o modelo", icon: "pencil") { editing = t }
                    .accessibilityIdentifier("training.preview.edit")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .sheet(item: $editing) { TemplateEditor(template: $0) }
        }
    }

    private func exercises(_ plan: [PlannedExercise]) -> some View {
        Card {
            HStack { Eyebrow(text: "Exercícios"); Spacer(); Text("AQ = série de aquecimento").font(.geist(11)).foregroundStyle(Color.faint) }
            ForEach(Array(plan.enumerated()), id: \.offset) { i, p in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.mono(13)).foregroundStyle(Color.faint).frame(width: 18, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.exercise.name).font(.geist(14))
                        let sub = subtitle(p)
                        if !sub.isEmpty { Text(sub).font(.geist(12)).foregroundStyle(Color.soft) }
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(TrainingRules.planText(p.exercise)).font(.mono(12))
                        Text(p.target.map { TrainingRules.setText($0.weight, $0.reps) } ?? "escolhes tu").font(.geist(11)).foregroundStyle(p.target == nil ? Color.faint : Color.soft)
                        if !p.warmups.isEmpty { TrainingWarmupBadge(count: p.warmups.count) }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("training.preview.exercise.\(i)")
            }
        }
    }

    /// The muscle groups, and for an exercise without warm-ups, why: «isquiotibiais · já aquecidos no 2»
    private func subtitle(_ p: PlannedExercise) -> String {
        let groups = p.groups.isEmpty ? (Catalog.shared.exercise(p.exercise.exerciseId)?.groups ?? []) : p.groups
        let names = TrainingRules.groupsText(groups)
        guard let by = p.warmedBy, p.warmups.isEmpty else { return names }
        return [names, "já aquecidos no \(by + 1)"].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private func weights(_ plan: [PlannedExercise]) -> some View {
        let without = plan.filter { $0.target == nil }.count
        if without > 0 {
            Card(state: .noData) {
                HStack { Eyebrow(text: "Pesos"); Spacer(); StateTag(state: .noData, text: "Sem histórico") }
                Text(without == plan.count
                     ? "Ainda não há sessões registadas com estes exercícios. Hoje escolhes os pesos; a partir da próxima, a app sugere objetivos com base no que fizeste."
                     : "\(without) \(without == 1 ? "exercício ainda sem histórico" : "exercícios ainda sem histórico"): aí escolhes tu o peso; a partir da próxima, a app sugere objetivos com base no que fizeste.")
                    .font(.geist(13))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("training.preview.nohistory")
        }
    }
}

/// «AQ +1 leve»: the warm-up mark (a word in a box, never colour alone)
struct TrainingWarmupBadge: View {
    var count: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("AQ").font(.mono(10, .medium)).foregroundStyle(Color.soft).padding(.horizontal, 5).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.25), lineWidth: 1))
            Text(count == 1 ? "+1 leve" : "+\(count)").font(.geist(11)).foregroundStyle(Color.faint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "uma série de aquecimento leve" : "\(count) séries de aquecimento")
    }
}

/// A secondary action in the training screens: 44 pt tall at least; `prominent` for the one action of its card
struct TrainingButton: View {
    var title: String
    var icon: String? = nil
    var prominent = false
    var wide = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.geist(13.5, .semibold))
            .foregroundStyle(prominent ? Color(hex: 0x05140F) : Color.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 44)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Area.mint.gradient) : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(Capsule().stroke(Color.white.opacity(prominent ? 0 : 0.14), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
    }
}

/// Tap groups on the body map to choose them
struct MuscleTapper: View {
    @Binding var selected: Set<String>
    var body: some View {
        VStack(spacing: 8) {
            BodyMapView(colors: Dictionary(uniqueKeysWithValues: selected.map { ($0, Color.train) })).frame(height: 170)
            FlowChips(items: groupNames.sorted { $0.value < $1.value }.map(\.key), selected: $selected)
        }
    }
}

struct FlowChips: View {
    var items: [String]
    @Binding var selected: Set<String>
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], spacing: 6) {
            ForEach(items, id: \.self) { g in
                let on = selected.contains(g)
                Text(groupNames[g] ?? g).font(.geist(12, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(Capsule().fill(on ? Color.train.opacity(0.85) : .white.opacity(0.08)))
                    .onTapGesture { if on { selected.remove(g) } else { selected.insert(g) } }
            }
        }
    }
}

// MARK: - Live workout

/// The workout (design v17: N_TreinoSerie, N_TreinoDescanso, N_TreinoPausa, N_TreinoResumo): one exercise at a time
/// with the target and what you did side by side, the rest with its reason, pause, and the summary that «Concluído»
/// closes. «Registar série» saves what the steppers show as done; the target is never written as done.
struct WorkoutView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var catalog = Catalog.shared
    @Environment(\.dismiss) private var dismiss
    var sessionId: String
    var showsUndo = true // the tabs show Desfazer themselves; opened from the lock screen, this view shows its own
    @ObservedObject private var live = LiveWorkout.shared
    @State private var now = Date()
    @State private var picking = false
    @State private var feel: Int?
    @State private var guiding: TempoGuideRequest?
    @State private var finishing: Double? // «Terminar»: the summary shows, and «Concluído» ends the session at this time
    @State private var rir: Int? // the effort answer for the set `rirSet`, optional
    @State private var rirSet: String?
    @State private var typing: SetField?
    @State private var changing: TemplateExercise? // «Trocar ou reordenar»
    @State private var editingSets: TemplateExercise? // «Editar séries»
    @State private var adjusting: NextProposal? // «Ajustar» on «Próxima vez»
    @State private var ignored = Set<String>() // proposals ignored on this summary: no mark anywhere
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var session: WorkoutSession? { store.record(WorkoutSession.self, sessionId) }

    var body: some View {
        if let session {
            Screen(glow: .train) {
                content(session)
            }
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { now = $0 }
            .overlay(alignment: .bottom) { if showsUndo { UndoBar() } }
            .sheet(isPresented: $picking) { ExercisePicker { addExercise($0) } }
            .sheet(item: $typing) { field in
                if let s = self.session, let c = s.currentSet() {
                    SetValueEntry(field: field, set: draft(s, c.index, c.exercise), change: { applySet($0) })
                }
            }
            .sheet(item: $changing) { ex in
                TrainingChangeSheet(sessionId: sessionId, exercise: ex) { finishing = nowMs() }
            }
            .sheet(item: $editingSets) { ex in TrainingEditSetsSheet(sessionId: sessionId, exercise: ex) }
            .sheet(item: $adjusting) { p in
                TrainingTargetSheet(proposal: p) { w, r in
                    if let s = self.session { accept(p, s, weight: w, reps: r) }
                }
            }
            .fullScreenCover(item: $guiding) { g in
                TempoGuideView(exercise: g.exercise.name, weight: g.weight, plan: TempoPlan.forExercise(id: g.exercise.exerciseId, name: g.exercise.name), target: g.target) { reached in
                    completeGuided(g, reps: reached)
                }
            }
            .onAppear {
                store.closeExpiredSessions() // left open past 23:59: partial now, so it opens as a summary
                if feel == nil { feel = session.feel }
                store.recordTrainingPrediction(session: session)
                Task { await LiveWorkout.shared.update(session: session) }
            }
        } else {
            Text("Sessão não encontrada").foregroundStyle(Color.soft)
        }
    }

    @ViewBuilder private func content(_ s: WorkoutSession) -> some View {
        if s.end != nil || TrainingRules.isExpired(s, today: Day.today) {
            summary(s, closing: nil)
        } else if let at = finishing {
            summary(s, closing: at)
        } else if s.isPaused {
            paused(s)
        } else {
            inProgress(s)
        }
    }

    // MARK: In progress (N_TreinoSerie)

    @ViewBuilder private func inProgress(_ s: WorkoutSession) -> some View {
        let current = s.currentSet()
        header(s, current: current?.exercise)
        Bar(progress: progress(s), area: .train)
        if let end = live.restEnd, end > now, let current {
            restCard(end, s, next: current.index)
        } else if let current {
            currentCard(current.exercise, index: current.index, s)
        } else {
            Card {
                Text("Todas as séries registadas").font(.geist(16, .semibold))
                Text("Quando quiseres, termina o treino para veres o resumo.").font(.geist(13)).foregroundStyle(Color.soft)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workout.alldone")
        }
        exerciseList(s, current: current?.exercise.exerciseId)
        SoftButton(title: "Adicionar exercício", icon: "plus") { picking = true }
        feelCard
        TrainingButton(title: "Terminar treino", wide: true) { finishTapped(s) }
            .accessibilityIdentifier("workout.finish")
    }

    private func header(_ s: WorkoutSession, current: TemplateExercise?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.name) · \(elapsed(s))").font(.geist(13)).foregroundStyle(Color.soft)
                Text(position(s, current)).font(.geist(17, .semibold))
            }
            Spacer()
            TrainingButton(title: "Pausa", icon: "pause.fill") { pause(s) }
                .accessibilityIdentifier("workout.pause")
        }
    }

    private func position(_ s: WorkoutSession, _ current: TemplateExercise?) -> String {
        guard let current, let i = s.order.firstIndex(where: { $0.exerciseId == current.exerciseId }) else { return "Todas as séries registadas" }
        return "Exercício \(i + 1) de \(s.order.count)"
    }

    private func currentCard(_ ex: TemplateExercise, index: Int, _ s: WorkoutSession) -> some View {
        let info = catalog.exercise(ex.exerciseId)
        let rows = s.sets.indices.filter { s.sets[$0].exerciseId == ex.exerciseId }
        let values = s.startingValues(at: index, repHigh: ex.repHigh)
        let setId = s.sets[index].id
        return VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack(alignment: .top, spacing: 10) {
                    if let info { ExercisePicture(exercise: info).frame(width: 56, height: 56) }
                    VStack(alignment: .leading, spacing: 3) {
                        NavigationLink { ExerciseDetail(exerciseId: ex.exerciseId, name: ex.name) } label: {
                            Text(ex.name).font(.geist(20, .bold)).foregroundStyle(Color.ink).multilineTextAlignment(.leading)
                        }
                        Text(exerciseLine(ex, s)).font(.geist(12)).foregroundStyle(Color.soft)
                    }
                }
                HStack(spacing: 6) {
                    Color.clear.frame(width: 34, height: 1)
                    StateTag(state: .suggested, text: "Objetivo").frame(maxWidth: .infinity, alignment: .leading)
                    StateTag(state: .confirmed, text: "Feito").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 24, height: 1)
                }
                .padding(.horizontal, 6)
                .accessibilityHidden(true)
                ForEach(rows, id: \.self) { i in setLine(s, i, current: i == index) }
                WhyLine(text: why(ex, s, index: index))
                if values.weight > store.profile.barKg {
                    Text("Discos por lado: " + store.plates(for: values.weight).map(kg).joined(separator: " + ")).font(.geist(11)).foregroundStyle(Color.faint)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout.current")
            HStack(spacing: 8) {
                bigStepper("kg", kg(values.weight), field: .weight,
                           minus: { adjust(index, ex) { $0.weight = max(0, $0.weight - 2.5) } },
                           plus: { adjust(index, ex) { $0.weight += 2.5 } })
                bigStepper("repetições", "\(values.reps)", field: .reps,
                           minus: { adjust(index, ex) { $0.reps = max(1, $0.reps - 1) } },
                           plus: { adjust(index, ex) { $0.reps += 1 } })
            }
            if s.isLastWorking(index) { rirCard(setId) }
            PrimaryButton(title: "Registar série", area: .mint) { register(index, ex: ex) }
                .accessibilityIdentifier("workout.log")
            HStack(spacing: 8) {
                TrainingButton(title: "Trocar ou reordenar") { changing = ex }
                    .accessibilityIdentifier("workout.change")
                TrainingButton(title: "Editar séries") { editingSets = ex }
                    .accessibilityIdentifier("workout.edit")
            }
            .frame(maxWidth: .infinity)
            TrainingButton(title: "Ritmo guiado", icon: "metronome.fill", wide: true) { startGuide(index, ex) }
                .accessibilityIdentifier("workout.guide")
        }
    }

    /// The muscle groups, the plan, and for an exercise with no warm-up of its own, why
    private func exerciseLine(_ ex: TemplateExercise, _ s: WorkoutSession) -> String {
        var parts = [TrainingRules.groupsText(catalog.exercise(ex.exerciseId)?.groups ?? []), TrainingRules.planText(ex)]
        let hasWarmup = s.sets.contains { $0.exerciseId == ex.exerciseId && $0.kind == .warmup }
        if !hasWarmup, let i = s.order.firstIndex(where: { $0.exerciseId == ex.exerciseId }) {
            let warmed = TrainingRules.warmedBy(s.order.map { TrainingRules.warmupGroups(catalog.exercise($0.exerciseId)) })
            if let by = warmed[i] { parts.append("já aquecidos no \(by + 1)") }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// One set: its mark, the target, what you did and a check once registered
    private func setLine(_ s: WorkoutSession, _ i: Int, current: Bool) -> some View {
        let set = s.sets[i]
        return HStack(spacing: 6) {
            TrainingSetMark(text: set.kind == .working ? "\(workingNumber(s, i))" : set.kind.short, warmup: set.kind == .warmup)
                .frame(width: 34, alignment: .leading)
            Text(targetText(set)).font(.geist(13)).foregroundStyle(set.kind == .warmup ? Color.faint : Color.soft)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(doneText(set, current: current)).font(.geist(14, .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "checkmark").font(.geist(12, .bold)).foregroundStyle(Color.good).opacity(set.done ? 1 : 0).frame(width: 24)
        }
        .frame(minHeight: 40)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(current ? Color.mint.opacity(0.1) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(current ? Color.mint.opacity(0.4) : Color.clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(s, i, current: current))
    }

    private func workingNumber(_ s: WorkoutSession, _ i: Int) -> Int {
        let set = s.sets[i]
        return s.sets.indices.filter { $0 <= i && s.sets[$0].exerciseId == set.exerciseId && s.sets[$0].kind != .warmup }.count
    }

    private func setTitle(_ s: WorkoutSession, _ i: Int) -> String {
        let set = s.sets[i]
        if set.kind == .warmup { return "Aquecimento" }
        let all = s.sets.filter { $0.exerciseId == set.exerciseId && $0.kind != .warmup }.count
        return "Série \(workingNumber(s, i)) de \(all)"
    }

    /// The suggested target of a set, or what stands for it: «leve» for a warm-up you choose, «escolhes tu» with no history
    private func targetText(_ set: SetLog) -> String {
        if let w = set.targetWeight { return set.targetReps.map { TrainingRules.setText(w, $0) } ?? "\(kg(w)) kg" }
        if set.kind == .warmup { return set.targetReps.map { "leve × \($0)" } ?? "leve" }
        return "escolhes tu"
    }

    private func doneText(_ set: SetLog, current: Bool) -> String {
        if set.done { return TrainingRules.setText(set.weight, set.reps) + (set.rir.map { " · RIR \($0 >= 4 ? "4+" : "\($0)")" } ?? "") }
        return current ? "…" : ""
    }

    private func rowLabel(_ s: WorkoutSession, _ i: Int, current: Bool) -> String {
        let set = s.sets[i]
        let state = set.done ? "feito: \(TrainingRules.setText(set.weight, set.reps))" : current ? "agora" : "por fazer"
        return "\(setTitle(s, i)), objetivo \(targetText(set)), \(state)"
    }

    /// «Porquê» for the current exercise: the warm-up, where the target came from, or the first time
    private func why(_ ex: TemplateExercise, _ s: WorkoutSession, index: Int) -> String {
        if s.sets[index].kind == .warmup {
            let groups = TrainingRules.groupsText(TrainingRules.warmupGroups(catalog.exercise(ex.exerciseId)))
            return groups.isEmpty ? "aquecimento leve antes das séries de trabalho." : "aquecimento leve: é o primeiro exercício de \(groups) neste treino."
        }
        guard let w = s.sets.first(where: { $0.exerciseId == ex.exerciseId && $0.kind != .warmup && $0.targetWeight != nil })?.targetWeight else {
            return store.lastSession(with: ex.exerciseId, before: s.id) == nil
                ? "primeira vez: escolhe um peso com que conseguirias fazer \(ex.repHigh + 2) repetições."
                : "este treino começou sem objetivo para este exercício: escolhes tu."
        }
        if let t = store.target(for: ex, session: s.id), t.weight == w { return t.reason + "." }
        return "o objetivo definido quando o treino começou."
    }

    private func bigStepper(_ label: String, _ value: String, field: SetField, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.geist(11, .semibold)).foregroundStyle(Color.soft)
            HStack(spacing: 4) {
                Button(action: minus) {
                    Image(systemName: "minus").font(.geist(15, .bold)).frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.08)))
                }
                .accessibilityLabel("Menos \(label)")
                Button { typing = field } label: {
                    Text(value).font(.mono(24, .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("\(value) \(label)")
                .accessibilityHint("Toca para escrever um valor")
                .accessibilityIdentifier("workout.\(field.rawValue)")
                Button(action: plus) {
                    Image(systemName: "plus").font(.geist(15, .bold)).frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.08)))
                }
                .accessibilityLabel("Mais \(label)")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    /// The effort question, only on the last working set of each exercise, optional: 0, 1, 2, 3 or 4 or more
    private func rirCard(_ setId: String) -> some View {
        Card {
            Text("Na última série, quantas repetições ainda conseguias?").font(.geist(14))
            HStack(spacing: 6) {
                ForEach(0...4, id: \.self) { n in
                    let on = rirSet == setId && rir == n
                    Button {
                        if on { rir = nil; rirSet = nil } else { rir = n; rirSet = setId }
                    } label: {
                        HStack(spacing: 3) {
                            if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                            Text(n == 4 ? "4 ou mais" : "\(n)").lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.train.opacity(0.5) : Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(n == 4 ? "4 ou mais" : "\(n)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("workout.rir.\(n)")
                }
            }
            Text("Opcional. Só pergunto na última série de cada exercício, e fica guardado como resposta tua.").font(.geist(11)).foregroundStyle(Color.faint)
        }
    }

    private func exerciseList(_ s: WorkoutSession, current: String?) -> some View {
        Card {
            Eyebrow(text: "Exercícios")
            ForEach(Array(s.order.enumerated()), id: \.offset) { i, ex in
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(.mono(12)).foregroundStyle(Color.faint).frame(width: 18, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(.geist(14, ex.exerciseId == current ? .semibold : .regular))
                        let marks = marksText(s, ex)
                        if !marks.isEmpty { Text(marks).font(.geist(11.5)).foregroundStyle(Color.soft) }
                    }
                    Spacer(minLength: 6)
                    exerciseState(s, ex, current: current)
                }
                .frame(minHeight: 36)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func exerciseState(_ s: WorkoutSession, _ ex: TemplateExercise, current: String?) -> some View {
        let sets = s.sets.filter { $0.exerciseId == ex.exerciseId }
        let done = sets.filter(\.done).count
        if s.isSkipped(ex.exerciseId) {
            StateTag(state: .ignored, text: "Saltado")
        } else if !sets.isEmpty && done == sets.count {
            StateTag(state: .confirmed, text: "Feito")
        } else if ex.exerciseId == current {
            StateTag(state: .pending, text: "Agora")
        } else if done > 0 {
            Text("\(done) de \(sets.count)").font(.mono(12)).foregroundStyle(Color.soft)
        }
    }

    /// «trocado de ordem», «em vez de …», «saltado: pouco tempo»
    private func marksText(_ s: WorkoutSession, _ ex: TemplateExercise) -> String {
        marks(s, ex).joined(separator: " · ")
    }

    private func marks(_ s: WorkoutSession, _ ex: TemplateExercise) -> [String] {
        var out: [String] = []
        if s.reordered?.contains(ex.exerciseId) == true { out.append("trocado de ordem") }
        if let old = s.swapped?[ex.exerciseId] {
            let planned = store.sessions().lazy.flatMap(\.order).first { $0.exerciseId == old }
            let name = Catalog.shared.exercise(old)?.name ?? planned?.name ?? old
            out.append("em vez de \(name)")
        }
        if let why = s.skipped?[ex.exerciseId] {
            out.append(ExerciseSkipReason(rawValue: why).map { "saltado: \($0.label.lowercased())" } ?? "saltado")
        }
        return out
    }

    private var feelCard: some View {
        Card {
            Eyebrow(text: "Como correu?", icon: "bolt.heart")
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button { feel = n } label: {
                        Text(["Péssimo", "Pesado", "OK", "Bom", "Ótimo"][n - 1]).font(.geist(12, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10).fill(feel == n ? Color.train.opacity(0.5) : .white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(feel == n ? .isSelected : []).accessibilityIdentifier("workout.feel.\(n)")
                }
            }
            Text("Serve para ver se a prontidão prevê as tuas sessões.").font(.geist(11)).foregroundStyle(Color.faint)
        }
    }

    // MARK: Rest (N_TreinoDescanso)

    private func restCard(_ end: Date, _ s: WorkoutSession, next: Int) -> some View {
        let left = max(0, end.timeIntervalSince(now))
        let total = max(1, live.restTotal)
        let last = s.sets.indices.filter { s.sets[$0].done }.max { (s.sets[$0].at ?? 0) < (s.sets[$1].at ?? 0) }
        let nextExercise = s.order.first { $0.exerciseId == s.sets[next].exerciseId }
        return VStack(alignment: .leading, spacing: 12) {
            Card(tint: .water) {
                Eyebrow(text: "Descanso", icon: "timer", color: .water)
                ZStack {
                    Ring(progress: left / total, area: .water, width: 12)
                    VStack(spacing: 2) {
                        Text(TrainingRules.restClock(left)).font(.mono(44, .semibold))
                        Text("de \(TrainingRules.restClock(total))").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }
                .frame(width: 200, height: 200)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Descanso: faltam \(TrainingRules.restClock(left)) de \(TrainingRules.restClock(total))")
                if let reason = live.restReason { WhyLine(text: reason, label: "Porque \(TrainingRules.restClock(total))") }
                HStack(spacing: 8) {
                    TrainingButton(title: "+30 s") { setRest(end.addingTimeInterval(30), total: total + 30) }
                        .accessibilityIdentifier("workout.rest.more")
                    Menu {
                        ForEach([60, 75, 90, 120, 150, 180], id: \.self) { sec in
                            Button(TrainingRules.restClock(Double(sec))) { adjustRest(to: sec, end: end, total: total) }
                        }
                    } label: {
                        Text("Ajustar").font(.geist(13.5, .semibold)).foregroundStyle(Color.ink).padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(0.08))).overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .accessibilityHint("Muda só este descanso")
                    .accessibilityIdentifier("workout.rest.adjust")
                    Spacer(minLength: 0)
                    TrainingButton(title: "Saltar descanso", prominent: true) { setRest(nil) }
                        .accessibilityIdentifier("workout.rest.skip")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout.rest")
            Card {
                Eyebrow(text: "A seguir")
                VStack(alignment: .leading, spacing: 2) {
                    Text(setTitle(s, next) + (nextExercise.map { " · \($0.name)" } ?? "")).font(.geist(15))
                    Text(s.sets[next].targetWeight == nil ? targetText(s.sets[next]) : "objetivo \(targetText(s.sets[next]))").font(.geist(12)).foregroundStyle(Color.soft)
                }
                if let last {
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack(spacing: 8) {
                        Text("\(setTitle(s, last)) · \(TrainingRules.setText(s.sets[last].weight, s.sets[last].reps))").font(.geist(13)).foregroundStyle(Color.soft)
                        Spacer(minLength: 4)
                        StateTag(state: .confirmed, text: "Registada")
                        TrainingButton(title: "Editar") { editingSets = s.order.first { $0.exerciseId == s.sets[last].exerciseId } }
                            .accessibilityIdentifier("workout.rest.edit")
                    }
                }
            }
            Text("Também no ecrã de bloqueio e na Dynamic Island.").font(.geist(12)).foregroundStyle(Color.faint).frame(maxWidth: .infinity)
        }
    }

    private func setRest(_ end: Date?, total: Double? = nil, reason: String? = nil) {
        if let s = session { Task { await live.rest(end, total: total, reason: reason, session: s) } }
    }

    /// «Ajustar» changes this rest only: it lasts `seconds` from when it started; the template keeps its own
    private func adjustRest(to seconds: Int, end: Date, total: Double) {
        let started = end.addingTimeInterval(-total)
        setRest(started.addingTimeInterval(Double(seconds)), total: Double(seconds), reason: "ajustado por ti, só neste descanso.")
    }

    // MARK: Pause (N_TreinoPausa)

    @ViewBuilder private func paused(_ s: WorkoutSession) -> some View {
        let done = s.exercisesDone
        VStack(alignment: .leading, spacing: 2) {
            Text("Treino em pausa").font(.geist(26, .bold))
            Text("\(s.name) · \(done.count) de \(s.order.count) exercícios · \(elapsed(s))").font(.geist(13)).foregroundStyle(Color.soft)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout.paused")
        HStack(spacing: 8) {
            StateTag(state: .partial)
            Text("o que fizeste está guardado").font(.geist(12)).foregroundStyle(Color.soft)
        }
        doneCard(s)
        PrimaryButton(title: "Retomar", area: .mint) { resume(s) }
            .accessibilityIdentifier("workout.resume")
        HStack(spacing: 8) {
            TrainingButton(title: "Terminar aqui") { finishing = s.pausedAt ?? nowMs() }
                .accessibilityIdentifier("workout.endhere")
            TrainingButton(title: "Retomar mais tarde") { dismiss() }
                .accessibilityIdentifier("workout.later")
        }
        Text(endHereText(done.count) + " Se retomares mais tarde, o treino fica aberto até às 23:59; depois passa a parcial.")
            .font(.geist(12)).foregroundStyle(Color.faint)
    }

    private func endHereText(_ n: Int) -> String {
        switch n {
        case 0: return "Terminar aqui fecha o treino; não há séries de trabalho registadas."
        case 1: return "Terminar aqui guarda o exercício feito como treino parcial. Nada é apagado."
        default: return "Terminar aqui guarda os \(n) exercícios feitos como treino parcial. Nada é apagado."
        }
    }

    private func doneCard(_ s: WorkoutSession) -> some View {
        let done = s.exercisesDone
        return Card {
            HStack { Eyebrow(text: "Feito"); Spacer(); StateTag(state: .confirmed, text: "Registado") }
            if done.isEmpty { Text("Ainda sem séries de trabalho registadas.").font(.geist(13)).foregroundStyle(Color.soft) }
            ForEach(done) { ex in
                HStack(alignment: .top, spacing: 8) {
                    Text(ex.name).font(.geist(14))
                    Spacer(minLength: 8)
                    Text(([TrainingRules.setsText(TrainingRules.working(ex.exerciseId, in: s))] + marks(s, ex)).joined(separator: " · "))
                        .font(.geist(12.5)).foregroundStyle(Color.soft).multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func pause(_ s: WorkoutSession) {
        var p = s
        p.pausedAt = nowMs()
        store.save(p)
        setRest(nil)
    }

    private func resume(_ s: WorkoutSession) {
        var r = s
        r.pausedAt = nil
        store.save(r)
        let saved = r
        Task { await live.update(session: saved) }
    }

    // MARK: Summary (N_TreinoResumo)

    /// `closing`: the time «Terminar» was tapped; nil for a session that has ended already (read only)
    @ViewBuilder private func summary(_ s: WorkoutSession, closing: Double?) -> some View {
        let endAt = closing ?? s.end ?? TrainingRules.lastActivity(s)
        let partial = closing == nil ? TrainingRules.isPartial(s, today: Day.today) : s.hasSetsLeft
        let done = s.exercisesDone
        VStack(alignment: .leading, spacing: 2) {
            Text(partial ? "Treino parcial" : "Treino terminado").font(.geist(26, .bold))
            Text("\(s.name) · \(timeRange(s.start, endAt))").font(.geist(13)).foregroundStyle(Color.soft)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout.summary")
        HStack(spacing: 8) {
            StateTag(state: partial ? .partial : .confirmed, text: "\(done.count) de \(s.order.count)")
            let skipped = skippedText(s)
            if !skipped.isEmpty { Text(skipped).font(.geist(12)).foregroundStyle(Color.soft) }
        }
        progressCard(s, done: done)
        if closing != nil { feelCard }
        if closing != nil || store.sessions().first(where: { $0.end != nil })?.id == s.id { nextCard(s) }
        if closing != nil {
            PrimaryButton(title: "Concluído", area: .mint) { close(s, at: endAt) }
                .accessibilityIdentifier("workout.done")
            TrainingButton(title: "Voltar ao treino", wide: true) { finishing = nil }
                .accessibilityIdentifier("workout.summary.back")
        }
        allSets(s)
    }

    private func timeRange(_ start: Double, _ end: Double) -> String {
        let a = Day.minuteOfDay(Date(timeIntervalSince1970: start / 1000)), b = Day.minuteOfDay(Date(timeIntervalSince1970: end / 1000))
        return "\(clock(a))–\(clock(b)) · \(duration(max(0, Int((end - start) / 60000))))"
    }

    private func skippedText(_ s: WorkoutSession) -> String {
        s.order.filter { s.isSkipped($0.exerciseId) }.map { ex -> String in
            let why = ExerciseSkipReason(rawValue: s.skipped?[ex.exerciseId] ?? "").map { ": \($0.label.lowercased())" } ?? ""
            return "\(ex.name) saltado\(why)"
        }
        .joined(separator: " · ")
    }

    private func progressCard(_ s: WorkoutSession, done: [TemplateExercise]) -> some View {
        Card {
            HStack { Eyebrow(text: "Progresso"); Spacer(); StateTag(state: .confirmed, text: "Registado") }
            if done.isEmpty { Text("Sem séries de trabalho registadas neste treino.").font(.geist(13)).foregroundStyle(Color.soft) }
            ForEach(done) { ex in
                let sets = TrainingRules.working(ex.exerciseId, in: s)
                let change = TrainingRules.change(now: sets, before: store.previousWorking(ex.exerciseId, before: s))
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(.geist(14))
                        Text(([TrainingRules.setsText(sets)] + [TrainingRules.belowTarget(sets)].compactMap { $0 } + marks(s, ex)).joined(separator: " · "))
                            .font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 8)
                    Text(change).font(.geist(13, .semibold)).foregroundStyle(change.hasPrefix("+") ? Color.mint : Color.soft)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// «Próxima vez»: what the progression rules propose. It changes the next session's target only if you accept it
    /// (or adjust it); Ignorar leaves no mark.
    @ViewBuilder private func nextCard(_ s: WorkoutSession) -> some View {
        let all = store.proposals(after: s)
        let changes = all.filter { $0.changes && !ignored.contains($0.id) }
        let same = all.filter { !$0.changes }
        if !changes.isEmpty || !same.isEmpty {
            Card(state: changes.isEmpty ? .plain : .suggested) {
                HStack { Eyebrow(text: "Próxima vez"); Spacer(); if !changes.isEmpty { StateTag(state: .suggested) } }
                ForEach(changes) { p in proposalRow(p, s) }
                ForEach(same) { p in
                    Text("\(p.exercise.name) fica igual: \(TrainingRules.sentence(p.reason)).").font(.geist(12)).foregroundStyle(Color.soft)
                }
                Text("O objetivo da próxima sessão só muda se aceitares.").font(.geist(11)).foregroundStyle(Color.faint)
            }
        }
    }

    private func proposalRow(_ p: NextProposal, _ s: WorkoutSession) -> some View {
        let accepted = store.record(TrainingTarget.self, TrainingRules.targetId(p.exercise.exerciseId)).flatMap { $0.session == s.id ? $0 : nil }
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(p.exercise.name) a \(TrainingRules.setText(accepted?.weight ?? p.weight, accepted?.reps ?? p.reps))").font(.geist(15))
            WhyLine(text: TrainingRules.sentence(p.reason))
            if accepted != nil {
                HStack(spacing: 8) {
                    StateTag(state: .confirmed, text: "Aceite")
                    Text("vale para a próxima sessão").font(.geist(11)).foregroundStyle(Color.faint)
                }
            } else {
                DecisionButtons(onAccept: { accept(p, s) }, onAdjust: { adjusting = p }, onIgnore: { _ = ignored.insert(p.id) })
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workout.next.\(p.exercise.exerciseId)")
            }
        }
    }

    private func accept(_ p: NextProposal, _ s: WorkoutSession, weight: Double? = nil, reps: Int? = nil) {
        let before = store.acceptTarget(p, weight: weight, reps: reps, from: s)
        let st = store
        let exerciseId = p.exercise.exerciseId
        UndoCenter.shared.show("Próxima vez: \(p.exercise.name) a \(TrainingRules.setText(weight ?? p.weight, reps ?? p.reps))") {
            st.restoreTarget(exerciseId, to: before)
        }
    }

    private func allSets(_ s: WorkoutSession) -> some View {
        let done = s.sets.filter(\.done)
        let warm = done.filter { $0.kind == .warmup }.count
        let exercises = s.order.filter { ex in done.contains { $0.exerciseId == ex.exerciseId } }
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(exercises) { ex in
                    HStack {
                        Text(ex.name).font(.geist(13, .semibold))
                        Spacer()
                        TrainingButton(title: "Editar") { editingSets = ex }
                    }
                    ForEach(done.filter { $0.exerciseId == ex.exerciseId }) { set in
                        HStack {
                            Text(set.kind == .working ? "Série" : set.kind.label).foregroundStyle(set.kind == .warmup ? Color.faint : Color.soft)
                            Spacer()
                            Text(TrainingRules.setText(set.weight, set.reps) + (set.rir.map { " · RIR \($0 >= 4 ? "4+" : "\($0)")" } ?? ""))
                        }
                        .font(.geist(12.5))
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Todas as séries · \(done.count) \(done.count == 1 ? "série" : "séries")" + (warm > 0 ? " · \(warm) de aquecimento" : ""))
                .font(.geist(13.5, .semibold)).foregroundStyle(Color.ink)
        }
        .tint(Color.soft)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.055)))
        .accessibilityIdentifier("workout.allsets")
    }

    // MARK: Actions

    private func elapsed(_ s: WorkoutSession) -> String {
        let endMs = s.end ?? s.pausedAt
        let end = endMs.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
        let m = Int(end.timeIntervalSince(Date(timeIntervalSince1970: s.start / 1000)) / 60)
        return duration(max(0, m))
    }

    private func progress(_ s: WorkoutSession) -> Double {
        let planned = s.sets.filter { $0.done || !s.isSkipped($0.exerciseId) }
        guard !planned.isEmpty else { return 0 }
        return Double(planned.filter(\.done).count) / Double(planned.count)
    }

    /// The set as the steppers show it: a set not yet registered gets its starting values (your own, else the target)
    private func draft(_ s: WorkoutSession, _ index: Int, _ ex: TemplateExercise) -> SetLog {
        var set = s.sets[index]
        if !set.done {
            let v = s.startingValues(at: index, repHigh: ex.repHigh)
            set.weight = v.weight
            set.reps = max(1, v.reps)
        }
        return set
    }

    /// Changes what you're about to register on the current set; both values are written, so the set keeps them
    private func adjust(_ index: Int, _ ex: TemplateExercise, _ change: (inout SetLog) -> Void) {
        guard let s = session, s.sets.indices.contains(index) else { return }
        var set = draft(s, index, ex)
        change(&set)
        applySet(set)
    }

    /// The one path for changing a set: it starts from the session as saved now and finds the set by id, because the
    /// guide can run for minutes while the lock screen or a sync changes the session underneath it.
    private func applySet(_ updated: SetLog) {
        guard var s = session, let index = s.sets.firstIndex(where: { $0.id == updated.id }) else { return }
        s.sets[index] = updated
        store.save(s)
        let saved = s
        Task { await live.update(session: saved) }
    }

    /// «Registar série»: what the steppers show is saved as done (the target stays apart), with your effort answer if
    /// you gave one, then the rest starts, as long as the exercise and the set just done ask for
    private func register(_ index: Int, ex: TemplateExercise, reps: Int? = nil) {
        guard var s = session, s.sets.indices.contains(index), !s.sets[index].done else { return }
        let v = s.startingValues(at: index, repHigh: ex.repHigh)
        let answer = rirSet == s.sets[index].id ? rir : nil
        s.register(index, weight: v.weight, reps: reps ?? max(1, v.reps), rir: answer)
        store.save(s)
        rir = nil
        rirSet = nil
        let saved = s
        let set = s.sets[index]
        if set.kind != .warmup && s.hasSetsLeft {
            let r = TrainingRules.rest(catalog.exercise(ex.exerciseId).map { TrainingRules.mechanic($0) }, reps: set.reps, templateRest: ex.rest)
            if r.seconds > 0 {
                Task { await live.rest(Date().addingTimeInterval(Double(r.seconds)), total: Double(r.seconds), reason: r.reason, session: saved) }
                return
            }
        }
        Task { await live.update(session: saved) }
    }

    private func startGuide(_ index: Int, _ ex: TemplateExercise) {
        guard let s = session, s.sets.indices.contains(index) else { return }
        if live.restEnd != nil { setRest(nil) } // starting the set ends the rest, so its alert can't sound mid-set
        let v = s.startingValues(at: index, repHigh: ex.repHigh)
        guiding = TempoGuideRequest(id: s.sets[index].id, exercise: ex, weight: v.weight, target: v.reps > 0 ? v.reps : ex.repHigh)
    }

    private func completeGuided(_ g: TempoGuideRequest, reps: Int) {
        guard let s = session, let index = s.sets.firstIndex(where: { $0.id == g.id }) else { return }
        if s.sets[index].done {
            var set = s.sets[index]
            set.reps = reps
            applySet(set)
        } else {
            register(index, ex: g.exercise, reps: reps)
        }
    }

    private func addExercise(_ info: CatalogExercise) {
        guard var s = session else { return }
        let t = TemplateExercise(exerciseId: info.id, name: info.name)
        let groups = s.order.map { TrainingRules.warmupGroups(catalog.exercise($0.exerciseId)) } + [TrainingRules.warmupGroups(info)]
        let decisions = TrainingRules.warmedBy(groups)
        let warm = (decisions.last ?? nil) == nil && !TrainingRules.isConditioning(info)
        let target = store.target(for: t, session: s.id)
        s.order.append(t)
        s.sets += TrainingRules.sets(for: PlannedExercise(exercise: t, target: target, warmups: warm ? store.warmupSets(for: target) : [], warmedBy: nil, groups: info.groups))
        store.save(s)
    }

    /// «Terminar treino»: the summary, which «Concluído» closes. With nothing registered there's nothing to sum up,
    /// so it closes as it always has.
    private func finishTapped(_ s: WorkoutSession) {
        if !s.sets.contains(where: { $0.done }) {
            close(s, at: nowMs())
            return
        }
        finishing = nowMs()
    }

    /// «Concluído» closes the training: every registered set stays, what wasn't done goes from the plan
    private func close(_ s: WorkoutSession, at: Double) {
        guard let current = session else { return }
        var c = current
        c.feel = feel
        c.finish(at: at)
        store.save(c)
        finishing = nil
        let saved = c
        Task {
            await live.rest(nil, session: saved)
            await LiveWorkout.shared.end()
        }
        dismiss()
    }
}

/// The set's mark: its number, or the kind in a box («AQ» for a warm-up), never colour alone
struct TrainingSetMark: View {
    var text: String
    var warmup: Bool
    var body: some View {
        if warmup {
            Text("AQ").font(.mono(10, .medium)).foregroundStyle(Color.soft).padding(.horizontal, 5).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.25), lineWidth: 1))
        } else {
            Text(text).font(.mono(13, .semibold)).foregroundStyle(Color.ink)
        }
    }
}

/// «Trocar ou reordenar» (design v17, N_TreinoSubstituir): every change only once you confirm it, with Desfazer; with
/// pain the app doesn't suggest carrying on. «Saltar exercício» marks it skipped, never failed.
struct TrainingChangeSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var sessionId: String
    var exercise: TemplateExercise
    var endWorkout: () -> Void
    @State private var reason: ExerciseSkipReason?

    var body: some View {
        NavigationStack {
            Screen(glow: .train) {
                if let s = store.record(WorkoutSession.self, sessionId) {
                    Text([exercise.name, TrainingRules.groupsText(Catalog.shared.exercise(exercise.exerciseId)?.groups ?? [])].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.geist(13)).foregroundStyle(Color.soft)
                    reasonCard
                    if reason != .pain && reason != .time {
                        if let next = s.next(after: exercise.exerciseId) { reorderCard(s, next) }
                        if let alt = store.alternatives(to: exercise, in: s).first { replaceCard(s, alt) }
                    }
                    stopCard(s)
                }
            }
            .navigationTitle("Trocar ou reordenar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
    }

    private var reasonCard: some View {
        Card {
            Eyebrow(text: "O que se passa")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(ExerciseSkipReason.allCases, id: \.self) { r in
                    let on = reason == r
                    Button { reason = on ? nil : r } label: {
                        HStack(spacing: 4) {
                            if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                            Text(r.label).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .font(.geist(13, .semibold)).foregroundStyle(on ? Color(hex: 0x2A0610) : Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(on ? Color.train : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("change.reason.\(r.rawValue)")
                }
            }
        }
    }

    private func reorderCard(_ s: WorkoutSession, _ next: TemplateExercise) -> some View {
        Card(state: .suggested) {
            HStack { Eyebrow(text: "Melhor opção"); Spacer(); StateTag(state: .suggested) }
            Text("Fazer já o \(next.name) e voltar ao \(exercise.name) a seguir").font(.geist(15))
            WhyLine(text: reason == .busy ? "a máquina pode libertar-se; o treino fica igual, só muda a ordem." : "o treino fica igual, só muda a ordem.")
            HStack {
                TrainingButton(title: "Confirmar", prominent: true) { reorder(s, next) }
                    .accessibilityIdentifier("change.reorder")
                Spacer()
            }
        }
    }

    private func replaceCard(_ s: WorkoutSession, _ alt: CatalogExercise) -> some View {
        let known = !store.lastSets(alt.id).isEmpty
        return Card(state: .suggested) {
            HStack { Eyebrow(text: "Outra opção"); Spacer(); StateTag(state: .suggested) }
            Text("Trocar por \(alt.name)").font(.geist(15))
            Text("mesmo grupo · \(TrainingRules.planText(exercise)) · \(known ? "já o fizeste antes" : "sem histórico: começa leve")").font(.geist(12)).foregroundStyle(Color.soft)
            HStack {
                TrainingButton(title: "Trocar") { replace(s, with: alt) }
                    .accessibilityIdentifier("change.swap")
                Spacer()
            }
        }
    }

    private func stopCard(_ s: WorkoutSession) -> some View {
        Card(state: .pending) {
            Eyebrow(text: reason == .pain ? "Com dor" : reason == .time ? "Com pouco tempo" : "Se for dor")
            Text(reason == .time
                 ? "Podes saltar este exercício ou terminar aqui. O que já fizeste fica guardado."
                 : "Para este exercício. A app não sugere continuar a treinar com dor: podes saltá-lo ou terminar o treino. O que já fizeste fica guardado.")
                .font(.geist(13))
            HStack(spacing: 8) {
                TrainingButton(title: "Saltar exercício") { skip(s) }
                    .accessibilityIdentifier("change.skip")
                TrainingButton(title: "Terminar treino") {
                    dismiss()
                    endWorkout()
                }
                .accessibilityIdentifier("change.end")
            }
        }
    }

    private func reorder(_ s: WorkoutSession, _ next: TemplateExercise) {
        var c = s
        c.moveUp(next.exerciseId, before: exercise.exerciseId)
        store.save(c)
        undoable("\(next.name) passa para agora", before: s)
        dismiss()
    }

    private func replace(_ s: WorkoutSession, with alt: CatalogExercise) {
        let new = TemplateExercise(exerciseId: alt.id, name: alt.name, sets: exercise.sets, repLow: exercise.repLow, repHigh: exercise.repHigh, rest: exercise.rest, increment: exercise.increment)
        // The new exercise takes the old one's warm-up if that one hadn't done it yet
        let warmupLeft = s.sets.contains { $0.exerciseId == exercise.exerciseId && $0.kind == .warmup && !$0.done }
        let target = store.target(for: new, session: s.id)
        let planned = TrainingRules.sets(for: PlannedExercise(exercise: new, target: target, warmups: warmupLeft ? store.warmupSets(for: target) : [], warmedBy: nil, groups: alt.groups))
        var c = s
        c.replace(exercise, with: new, sets: planned)
        store.save(c)
        undoable("Trocado por \(alt.name)", before: s)
        dismiss()
    }

    private func skip(_ s: WorkoutSession) {
        var c = s
        c.skip(exercise.exerciseId, reason: reason?.rawValue ?? "")
        store.save(c)
        undoable("\(exercise.name) saltado", before: s)
        dismiss()
    }

    /// Desfazer puts the plan back as it was, keeping any set registered since
    private func undoable(_ text: String, before: WorkoutSession) {
        let st = store
        let id = sessionId
        UndoCenter.shared.show(text) {
            guard let now = st.record(WorkoutSession.self, id) else { return }
            st.save(now.restoringPlan(from: before))
        }
    }
}

/// «Editar séries»: corrects what you did, set by set. The target of each set never changes here.
struct TrainingEditSetsSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var sessionId: String
    var exercise: TemplateExercise

    var body: some View {
        NavigationStack {
            Screen(glow: .train) {
                Text("Corrige o que fizeste. O objetivo de cada série não muda.").font(.geist(13)).foregroundStyle(Color.soft)
                if let s = store.record(WorkoutSession.self, sessionId) {
                    let rows = s.sets.indices.filter { s.sets[$0].exerciseId == exercise.exerciseId }
                    if rows.isEmpty { Text("Sem séries deste exercício.").font(.geist(13)).foregroundStyle(Color.soft) }
                    ForEach(rows, id: \.self) { i in
                        let shown = shownSet(s, i)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(caption(s, i)).font(.geist(11.5)).foregroundStyle(Color.faint)
                            SetRow(set: shown, number: number(s, i), plates: store.plates(for: shown.weight), change: { apply($0) })
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
                    }
                    if s.end == nil {
                        TrainingButton(title: "Adicionar série", icon: "plus") { addSet(s) }
                            .accessibilityIdentifier("workout.edit.add")
                    }
                }
            }
            .navigationTitle("Editar séries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } } }
        }
    }

    /// A set not yet registered shows where its steppers start (your values, else the target)
    private func shownSet(_ s: WorkoutSession, _ i: Int) -> SetLog {
        var set = s.sets[i]
        if !set.done {
            let v = s.startingValues(at: i, repHigh: exercise.repHigh)
            set.weight = v.weight
            set.reps = max(1, v.reps)
        }
        return set
    }

    private func number(_ s: WorkoutSession, _ i: Int) -> Int {
        s.sets.indices.filter { $0 <= i && s.sets[$0].exerciseId == exercise.exerciseId && s.sets[$0].kind != .warmup }.count
    }

    private func caption(_ s: WorkoutSession, _ i: Int) -> String {
        let set = s.sets[i]
        let target = set.targetWeight.map { w in "objetivo " + (set.targetReps.map { TrainingRules.setText(w, $0) } ?? "\(kg(w)) kg") }
            ?? (set.kind == .warmup ? "aquecimento leve" : "sem objetivo: escolhes tu")
        return (set.done ? "Registada" : "Por fazer") + " · " + target
    }

    private func apply(_ updated: SetLog) {
        guard var s = store.record(WorkoutSession.self, sessionId), let i = s.sets.firstIndex(where: { $0.id == updated.id }) else { return }
        s.sets[i] = updated
        store.save(s)
        let saved = s
        Task { await LiveWorkout.shared.update(session: saved) }
    }

    /// One more working set, with the same target as the last one (nothing in weight or reps until you set it)
    private func addSet(_ s: WorkoutSession) {
        var c = s
        let last = s.sets.last { $0.exerciseId == exercise.exerciseId && $0.kind != .warmup }
        c.sets.append(SetLog(exerciseId: exercise.exerciseId, weight: 0, reps: 0, targetWeight: last?.targetWeight, targetReps: last?.targetReps))
        store.save(c)
    }
}

/// «Ajustar» on «Próxima vez»: the target for next time, set by you; it applies once you save it
struct TrainingTargetSheet: View {
    var proposal: NextProposal
    var save: (Double, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double
    @State private var reps: Int

    init(proposal: NextProposal, save: @escaping (Double, Int) -> Void) {
        self.proposal = proposal
        self.save = save
        _weight = State(initialValue: proposal.weight)
        _reps = State(initialValue: proposal.reps)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(kg(weight)) kg", value: $weight, in: 0...500, step: proposal.exercise.increment > 0 ? proposal.exercise.increment : 2.5)
                    Stepper("\(reps) repetições", value: $reps, in: 1...50)
                } footer: {
                    Text("Vale só para a próxima sessão de \(proposal.exercise.name).")
                }
            }
            .cadenceList()
            .navigationTitle("Próxima vez")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        save(weight, reps)
                        dismiss()
                    }
                    .accessibilityIdentifier("workout.next.save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

enum SetField: String, Identifiable {
    case weight, reps
    var id: String { rawValue }
}

struct SetRow: View {
    var set: SetLog
    var number: Int
    var plates: [Double]
    var change: (SetLog) -> Void
    var guide: (() -> Void)? = nil
    @State private var typing: SetField?

    var body: some View {
        VStack(spacing: 6) {
            controls
            if let guide {
                Button(action: guide) {
                    Label("Ritmo guiado", systemImage: "metronome.fill").font(.geist(13, .semibold)).foregroundStyle(Color.train)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.train.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workout.guide")
            }
        }
        .sheet(item: $typing) { field in SetValueEntry(field: field, set: set, change: change) }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(SetKind.allCases, id: \.self) { k in Button(k.label) { var s = set; s.kind = k; change(s) } }
            } label: {
                Text(set.kind == .working ? "\(number)" : set.kind.short).font(.geist(12, .bold)).frame(width: 26).foregroundStyle(set.kind == .warmup ? Color.faint : Color.soft)
            }
            stepper(kg(set.weight) + " kg", field: .weight, minus: { var s = set; s.weight = max(0, s.weight - 2.5); change(s) }, plus: { var s = set; s.weight += 2.5; change(s) })
            stepper("\(set.reps)", field: .reps, minus: { var s = set; s.reps = max(0, s.reps - 1); change(s) }, plus: { var s = set; s.reps += 1; change(s) })
            Button { var s = set; s.done.toggle(); s.at = s.done ? nowMs() : nil; change(s) } label: {
                Image(systemName: "checkmark").opacity(set.done ? 1 : 0).font(.geist(13, .bold)).foregroundStyle(Color(hex: 0x04210F))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9).fill(set.done ? Color.good : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(set.done ? Color.clear : Color.white.opacity(0.25), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .opacity(set.kind == .warmup && !set.done ? 0.7 : 1)
    }

    private func stepper(_ text: String, field: SetField, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: minus) { Image(systemName: "minus").frame(width: 28, height: 32) }
            Button { typing = field } label: {
                Text(text).font(.mono(14, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
            }
            .accessibilityHint("Toca para escrever um valor")
            .accessibilityIdentifier("workout.\(field.rawValue)")
            Button(action: plus) { Image(systemName: "plus").frame(width: 28, height: 32) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.ink)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
    }
}

/// Type a weight or reps. The field starts empty with the current value behind it, so typing replaces it, and the set
/// is written once when editing ends: on Set or on swiping the sheet away, and only if the value changed.
struct SetValueEntry: View {
    var field: SetField
    var set: SetLog
    var change: (SetLog) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var closed = false
    @FocusState private var focused: Bool

    private var isWeight: Bool { field == .weight }
    private var valid: Bool { isWeight ? NumberInput.weight(draft) != nil : NumberInput.reps(draft) != nil }

    var body: some View {
        VStack(spacing: 12) {
            Eyebrow(text: isWeight ? "Peso em kg" : "Repetições")
            TextField("Valor", text: $draft, prompt: Text(isWeight ? kg(set.weight) : "\(set.reps)"))
                .keyboardType(isWeight ? .decimalPad : .numberPad)
                .font(.mono(38, .semibold))
                .multilineTextAlignment(.center)
                .focused($focused)
                .onSubmit { finish() }
                .accessibilityIdentifier("workout.entry")
            HStack(spacing: 10) {
                SoftButton(title: "Cancelar") { closed = true; dismiss() }
                PrimaryButton(title: "Definir", area: .train) { finish() }
                    .disabled(!valid)
                    .opacity(valid ? 1 : 0.4)
                    .accessibilityIdentifier("workout.entry.set")
            }
        }
        .padding(16)
        .presentationDetents([.height(210)])
        .presentationDragIndicator(.visible)
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000) // the sheet takes focus only once it's on screen
            focused = true
        }
        .onDisappear { if !closed { commit() } }
    }

    private func finish() {
        guard valid else { return }
        closed = true
        commit()
        dismiss()
    }

    private func commit() {
        var s = set
        if isWeight, let v = NumberInput.weight(draft), v != s.weight {
            s.weight = v
            change(s)
        } else if !isWeight, let v = NumberInput.reps(draft), v != s.reps {
            s.reps = v
            change(s)
        }
    }
}

/// RepDB's start and end pictures, cross-faded into a motion loop
struct ExercisePicture: View {
    var exercise: CatalogExercise
    @State private var peak = false

    var body: some View {
        let urls = exercise.imageURLs
        ZStack {
            Color.white
            if let a = urls.first { AsyncImage(url: a) { $0.resizable().scaledToFill() } placeholder: { ProgressView() } }
            if urls.count > 1 { AsyncImage(url: urls[1]) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.opacity(peak ? 1 : 0) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { if urls.count > 1 { withAnimation(.easeInOut(duration: 1.1).repeatForever()) { peak = true } } }
    }
}

struct ExerciseDetail: View {
    @EnvironmentObject var store: Store
    var exerciseId: String
    var name: String
    @State private var goal = ""

    var body: some View {
        let ex = Catalog.shared.exercise(exerciseId)
        let history = store.e1rmHistory(exerciseId)
        Screen(glow: .train) {
            if let ex { ExercisePicture(exercise: ex).frame(height: 240) }
            if let ex {
                Card {
                    Eyebrow(text: "Músculos")
                    BodyMapView(colors: Dictionary(uniqueKeysWithValues: ex.groups.map { ($0, Color.train) } + ex.secondaryGroups.map { ($0, Color.train.opacity(0.45)) }), idle: .white.opacity(0.15)).frame(height: 150)
                    Text(ex.groups.compactMap { groupNames[$0] }.sorted().joined(separator: ", ")).font(.geist(13)).foregroundStyle(Color.soft)
                }
            }
            if history.count >= 2 {
                Card {
                    HStack { Eyebrow(text: "1RM estimado"); Spacer(); Text("\(kg(history.last!.value)) kg").font(.mono(15, .bold)) }
                    Chart {
                        ForEach(history, id: \.date) { p in
                            LineMark(x: .value("day", Day.date(p.date), unit: .day), y: .value("1RM", p.value)).foregroundStyle(Area.train.gradient)
                            PointMark(x: .value("day", Day.date(p.date), unit: .day), y: .value("1RM", p.value)).foregroundStyle(Color.ink).symbolSize(16)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 150)
                    HStack {
                        TextField("Objetivo kg", text: $goal).keyboardType(.decimalPad).frame(width: 90)
                        if let g = Double(goal), let p = store.projection(exerciseId, goal: g) {
                            Text("~\(Day.date(p.date).formatted(.dateTime.day().month())) a \(String(format: "%+.1f", p.perWeek)) kg/semana").font(.geist(13)).foregroundStyle(Color.good)
                        }
                    }
                }
            }
            if let ex, !ex.instructions.isEmpty {
                Card {
                    Eyebrow(text: "Como fazer")
                    ForEach(Array(ex.instructions.enumerated()), id: \.offset) { i, s in Text("\(i + 1). \(s)").font(.geist(13.5)) }
                    ForEach(ex.tips, id: \.self) { t in Text("• \(t)").font(.geist(12.5)).foregroundStyle(Color.soft) }
                }
            }
            Text("Dados de exercícios da RepDB (repdb.co)").font(.geist(10.5)).foregroundStyle(Color.faint)
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ExercisePicker: View {
    @ObservedObject var catalog = Catalog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var group: String?
    var pick: (CatalogExercise) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(groupNames.sorted { $0.value < $1.value }, id: \.key) { k, v in
                                Chip(text: v, color: group == k ? Color(hex: 0x2A0610) : .ink, fill: group == k ? Color.train : .white.opacity(0.08)).onTapGesture { group = group == k ? nil : k }
                            }
                        }
                    }
                }
                if catalog.exercises.isEmpty { Text(catalog.loading ? "A descarregar os exercícios…" : "Sem ligação: a lista de exercícios descarrega-se uma vez.").foregroundStyle(Color.soft) }
                ForEach(catalog.exercises.filter { (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && (group == nil || $0.groups.contains(group!)) }.prefix(80)) { ex in
                    Button { pick(ex); dismiss() } label: {
                        HStack(spacing: 10) {
                            ExercisePicture(exercise: ex).frame(width: 44, height: 44)
                            VStack(alignment: .leading) {
                                Text(ex.name).foregroundStyle(Color.ink)
                                Text(ex.groups.compactMap { groupNames[$0] }.sorted().joined(separator: ", ")).font(.caption).foregroundStyle(Color.soft)
                            }
                        }
                    }
                }
            }
            .cadenceList()
            .searchable(text: $search, prompt: "Procurar em 700 exercícios")
            .navigationTitle("Adicionar exercício")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .task { await catalog.load() }
        }
    }
}

struct TemplateEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var template: WorkoutTemplate
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $template.name)
                Stepper("Cerca de \(template.minutes) min", value: $template.minutes, in: 15...150, step: 5)
                ForEach($template.exercises) { $ex in
                    Section(ex.name) {
                        Stepper("\(ex.sets) \(ex.sets == 1 ? "série" : "séries")", value: $ex.sets, in: 1...10)
                        Stepper("De \(ex.repLow) repetições", value: $ex.repLow, in: 1...30)
                        Stepper("Até \(ex.repHigh) repetições", value: $ex.repHigh, in: ex.repLow...40)
                        Stepper("Descanso \(ex.rest) s", value: $ex.rest, in: 30...360, step: 15)
                        Stepper("Subir \(kg(ex.increment)) kg quando conseguires", value: $ex.increment, in: 0.5...10, step: 0.5)
                        Button("Remover", role: .destructive) { template.exercises.removeAll { $0.id == ex.id } }
                    }
                }
                Button("Adicionar exercício") { picking = true }
                if store.record(WorkoutTemplate.self, template.id) != nil {
                    Button("Apagar modelo", role: .destructive) { store.remove(template); dismiss() }
                }
            }
            .cadenceList()
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(template); dismiss() } }
            }
            .sheet(isPresented: $picking) { ExercisePicker { template.exercises.append(TemplateExercise(exerciseId: $0.id, name: $0.name)) } }
        }
    }
}

// MARK: - Progress and growth

struct ProgressListView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let ids = Array(Set(store.sessions().flatMap { $0.sets.filter(\.done).map(\.exerciseId) }))
        List {
            ForEach(ids, id: \.self) { id in
                let h = store.e1rmHistory(id)
                let name = Catalog.shared.exercise(id)?.name ?? store.sessions().lazy.flatMap(\.order).first { $0.exerciseId == id }?.name ?? id
                NavigationLink { ExerciseDetail(exerciseId: id, name: name) } label: {
                    HStack {
                        Text(name)
                        Spacer()
                        if let first = h.first, let last = h.last { Text("\(kg(last.value)) kg").font(.callout.monospaced()); Text(String(format: "%+.0f", last.value - first.value)).font(.caption).foregroundStyle(last.value >= first.value ? Color.good : Color.warn) }
                    }
                }
            }
            Section("Sessões") {
                ForEach(store.sessions().filter { $0.end != nil }.prefix(30)) { s in
                    HStack {
                        Text(s.name)
                        if TrainingRules.isPartial(s, today: Day.today) { StateTag(state: .partial) } // ended before the plan was done
                        Spacer()
                        Text("\(Day.date(s.date).formatted(.dateTime.day().month())) · \(Int(s.volume).formatted()) kg").font(.caption.monospaced()).foregroundStyle(Color.soft)
                    }
                    .swipeActions { Button("Apagar", role: .destructive) { store.remove(s) } }
                }
            }
        }
        .cadenceList()
        .navigationTitle("Progresso")
    }
}

struct GrowthCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let check = store.growthCheck()
        let short = check.map { c in c.status.values.contains { $0 != .growing } } ?? false
        Card(tint: short ? .fuel : nil) {
            HStack { Eyebrow(text: "Estão a crescer?", icon: "leaf.fill", color: short ? .fuel : .soft); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
            if let c = check {
                let names = c.status.filter { $0.value != .growing }.keys.compactMap { groupNames[$0] }.sorted()
                Text(names.isEmpty ? "Tudo o que treinaste em \(c.session.name) está alimentado e descansado." : "\(names.joined(separator: ", ")): proteína ou sono abaixo do que a recuperação precisa.").font(.geist(14))
            } else {
                Text("Nas 48 horas a seguir a uma sessão, vê se os músculos que treinaste têm proteína e sono suficientes.").font(.geist(13)).foregroundStyle(Color.soft)
            }
        }
    }
}

struct GrowthView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Screen(glow: .fuel) {
            if let c = store.growthCheck() {
                Card(tint: .fuel) {
                    Eyebrow(text: "\(c.session.name) · \(Day.date(c.session.date).formatted(.dateTime.weekday(.wide)))")
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text("Proteína desde o treino").font(.geist(13.5)); Spacer(); Text("\(Int(c.protein.got)) / \(Int(c.protein.need)) g").font(.mono(13.5)) }
                        Bar(progress: c.protein.got / max(1, c.protein.need), area: .fuel)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text("Sono desde o treino").font(.geist(13.5)); Spacer(); Text("\(duration(c.sleep.got)) / \(duration(c.sleep.need))").font(.mono(13.5)) }
                        Bar(progress: Double(c.sleep.got) / Double(max(1, c.sleep.need)), area: .sleep)
                    }
                }
                Card {
                    Eyebrow(text: "Treinados · frente e costas")
                    BodyMapView(colors: c.status.mapValues { $0 == .growing ? Color.good : $0 == .underRested ? Color.warn : Color.bad }).frame(height: 200)
                    HStack(spacing: 12) {
                        legend(.bad, "falta comida"); legend(.warn, "falta descanso"); legend(.good, "a crescer bem")
                    }
                    .frame(maxWidth: .infinity)
                }
                Card(tint: .mint) {
                    Eyebrow(text: "Corrige hoje à noite", icon: "moon.fill", color: .mint)
                    let gap = c.protein.need - c.protein.got
                    if gap > 10 {
                        let meal = store.all(SavedMeal.self).filter { $0.protein >= 15 }.min { abs($0.protein - gap) < abs($1.protein - gap) }
                        Text(meal.map { "\($0.name): +\(Int($0.protein)) g de proteína" } ?? "Mais \(Int(gap)) g de proteína antes de dormir").font(.geist(14))
                    }
                    Text("Apagar as luzes até às \(clock(store.sleepPlan().perform))").font(.geist(14))
                }
            } else {
                Text("Nada treinado nas últimas 48 horas.").foregroundStyle(Color.soft).padding(.top, 20)
            }
            Card {
                Eyebrow(text: "Frescura · dias desde o treino")
                let f = store.freshness()
                BodyMapView(colors: f.mapValues { d in d <= 1 ? Color.train : d <= 3 ? Color.fuel : Color.good.opacity(0.7) }).frame(height: 170)
                Text("Vermelho: treinado no último dia · âmbar: 2–3 dias · verde: fresco").font(.geist(11.5)).foregroundStyle(Color.soft)
            }
        }
        .navigationTitle("Estão a crescer?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); Text(text).font(.geist(11)).foregroundStyle(Color.soft) }
    }
}
