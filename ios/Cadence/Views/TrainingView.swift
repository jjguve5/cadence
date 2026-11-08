// Training: templates and sessions, the live workout with prefilled sets and the rest ring, exercise pictures from
// RepDB, progress with projections, and the muscle maps (freshness and "are they growing?").
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

    var body: some View {
        Screen(glow: .train) {
            if let s = store.activeSession {
                Button { open = s.id } label: {
                    Card(tint: .train) {
                        Eyebrow(text: "Em curso", icon: "flame.fill", color: .train)
                        Text(s.name).font(.geist(18, .bold))
                        Text("\(s.sets.filter(\.done).count) \(s.sets.filter(\.done).count == 1 ? "série" : "séries") · \(Int(s.volume).formatted()) kg").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }
                .buttonStyle(.plain)
            }
            Card {
                Eyebrow(text: "Começar uma sessão", icon: "play.fill")
                ForEach(store.templates) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(.geist(15, .semibold))
                            Text(t.exercises.map(\.name).prefix(3).joined(separator: " · ")).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1)
                        }
                        Spacer()
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
            Text("Exercise data by RepDB (repdb.co) · Body map based on GymMane by InlitX").font(.geist(10.5)).foregroundStyle(Color.faint)
        }
        .navigationTitle("Treino")
        .navigationBarTitleDisplayMode(.inline)
        .task { store.seedTemplates(); await catalog.load() }
        .sheet(item: $editing) { TemplateEditor(template: $0) }
        .navigationDestination(item: $open) { WorkoutView(sessionId: $0) }
    }

    private func start(_ t: WorkoutTemplate) -> String {
        if let s = store.activeSession { return s.id }
        var session = WorkoutSession(templateId: t.id, name: t.name, order: t.exercises)
        for ex in t.exercises {
            let sug = store.suggestion(for: ex)
            for (w, r) in store.warmups(for: sug.weight) { session.sets.append(SetLog(exerciseId: ex.exerciseId, kind: .warmup, weight: w, reps: r)) }
            for _ in 0..<sug.sets { session.sets.append(SetLog(exerciseId: ex.exerciseId, weight: sug.weight, reps: ex.repHigh)) }
        }
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

struct WorkoutView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var catalog = Catalog.shared
    @Environment(\.dismiss) private var dismiss
    var sessionId: String
    @ObservedObject private var live = LiveWorkout.shared
    @State private var now = Date()
    @State private var picking = false
    @State private var feel: Int?
    @State private var guiding: TempoGuideRequest?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var session: WorkoutSession? { store.record(WorkoutSession.self, sessionId) }

    var body: some View {
        if let session {
            Screen(glow: .train) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(elapsed(session)) · \(Int(session.volume).formatted()) kg").font(.geist(13)).foregroundStyle(Color.soft)
                        Text(session.name).font(.geist(26, .bold))
                    }
                    Spacer()
                }
                if let end = live.restEnd, end > now { restCard(end) }
                ForEach(session.order) { ex in exerciseCard(ex, session) }
                SoftButton(title: "Adicionar exercício", icon: "plus") { picking = true }
                if session.end == nil {
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
                    PrimaryButton(title: "Terminar sessão", area: .train) {
                        var s = session
                        s.feel = feel
                        s.end = nowMs()
                        s.sets.removeAll { !$0.done }
                        store.save(s)
                        Task { await LiveWorkout.shared.end() }
                        dismiss()
                    }
                    .accessibilityIdentifier("workout.finish")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { now = $0 }
            .sheet(isPresented: $picking) {
                ExercisePicker { ex in
                    var s = session
                    let t = TemplateExercise(exerciseId: ex.id, name: ex.name)
                    s.order.append(t)
                    let sug = store.suggestion(for: t, session: s.id)
                    for _ in 0..<sug.sets { s.sets.append(SetLog(exerciseId: ex.id, weight: sug.weight, reps: t.repHigh)) }
                    store.save(s)
                }
            }
            .fullScreenCover(item: $guiding) { g in
                TempoGuideView(exercise: g.exercise.name, weight: g.weight, plan: TempoPlan.forExercise(id: g.exercise.exerciseId, name: g.exercise.name), target: g.target) { reached in
                    completeGuided(g, reps: reached)
                }
            }
            .onAppear {
                store.recordTrainingPrediction(session: session)
                Task { await LiveWorkout.shared.update(session: session) }
            }
        } else {
            Text("Sessão não encontrada").foregroundStyle(Color.soft)
        }
    }

    private func elapsed(_ s: WorkoutSession) -> String {
        let end = s.end.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
        let m = Int(end.timeIntervalSince(Date(timeIntervalSince1970: s.start / 1000)) / 60)
        return duration(m)
    }

    private func restCard(_ end: Date) -> some View {
        let left = end.timeIntervalSince(now)
        return Card(tint: .train) {
            HStack(spacing: 14) {
                ZStack {
                    Ring(progress: left / max(1, live.restTotal), area: .train, width: 7)
                    Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60)).font(.mono(16, .semibold))
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Descanso")
                    HStack {
                        SoftButton(title: "−15") { setRest(end.addingTimeInterval(-15)) }
                        SoftButton(title: "+15") { setRest(end.addingTimeInterval(15)) }
                        SoftButton(title: "Saltar") { setRest(nil) }
                    }
                }
            }
        }
    }

    private func setRest(_ end: Date?) {
        if let s = session { Task { await live.rest(end, session: s) } }
    }

    private func exerciseCard(_ ex: TemplateExercise, _ session: WorkoutSession) -> some View {
        let sets = session.sets.enumerated().filter { $0.element.exerciseId == ex.exerciseId }
        let info = catalog.exercise(ex.exerciseId)
        let sug = store.suggestion(for: ex, session: session.id)
        return Card {
            HStack(alignment: .top, spacing: 10) {
                if let info { ExercisePicture(exercise: info).frame(width: 64, height: 64) }
                VStack(alignment: .leading, spacing: 3) {
                    NavigationLink { ExerciseDetail(exerciseId: ex.exerciseId, name: ex.name) } label: { Text(ex.name).font(.geist(16, .bold)).foregroundStyle(Color.ink).multilineTextAlignment(.leading) }
                    Text("\(ex.repLow)–\(ex.repHigh) reps · descanso \(ex.rest / 60):\(String(format: "%02d", ex.rest % 60))").font(.geist(12)).foregroundStyle(Color.soft)
                    Text(sug.reason).font(.geist(11.5)).foregroundStyle(Color.good)
                }
            }
            ForEach(sets, id: \.element.id) { index, set in
                setRow(set, number: sets.filter { $0.element.kind != .warmup && $0.offset <= index }.count, ex: ex, canGuide: session.end == nil)
            }
            HStack {
                Button { var s = session; let last = sets.last?.element; s.sets.append(SetLog(exerciseId: ex.exerciseId, weight: last?.weight ?? 0, reps: last?.reps ?? ex.repHigh)); store.save(s) } label: { Label("Série", systemImage: "plus").font(.geist(12.5, .semibold)) }
                Spacer()
                if let w = sets.last?.element.weight, w > store.profile.barKg { Text("Discos por lado: " + store.plates(for: w).map(kg).joined(separator: " + ")).font(.geist(11)).foregroundStyle(Color.faint) }
            }
            .tint(.train)
        }
    }

    private func setRow(_ set: SetLog, number: Int, ex: TemplateExercise, canGuide: Bool) -> some View {
        var guide: (() -> Void)?
        if canGuide && !set.done { guide = { startGuide(set, ex) } }
        return SetRow(set: set, number: number, plates: store.plates(for: set.weight), change: { applySet($0, ex: ex) }, guide: guide)
    }

    /// The one path for changing a set: it starts from the session as saved now and finds the set by id, because the
    /// guide can run for minutes while the lock screen or a sync changes the session underneath it.
    private func applySet(_ updated: SetLog, ex: TemplateExercise) {
        guard var s = session, let index = s.sets.firstIndex(where: { $0.id == updated.id }) else { return }
        let wasDone = s.sets[index].done
        s.sets[index] = updated
        store.save(s)
        let saved = s
        if updated.done && !wasDone && updated.kind != .warmup {
            Task { await live.rest(Date().addingTimeInterval(Double(ex.rest)), total: Double(ex.rest), session: saved) }
        } else {
            Task { await live.update(session: saved) }
        }
    }

    private func startGuide(_ set: SetLog, _ ex: TemplateExercise) {
        if live.restEnd != nil { setRest(nil) } // starting the set ends the rest, so its alert can't sound mid-set
        guiding = TempoGuideRequest(id: set.id, exercise: ex, weight: set.weight, target: set.reps > 0 ? set.reps : ex.repHigh)
    }

    private func completeGuided(_ g: TempoGuideRequest, reps: Int) {
        guard var updated = session?.sets.first(where: { $0.id == g.id }) else { return }
        updated.reps = reps
        if !updated.done { updated.done = true; updated.at = nowMs() }
        applySet(updated, ex: g.exercise)
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
            Text("Exercise data by RepDB (repdb.co)").font(.geist(10.5)).foregroundStyle(Color.faint)
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
                    HStack { Text(s.name); Spacer(); Text("\(Day.date(s.date).formatted(.dateTime.day().month())) · \(Int(s.volume).formatted()) kg").font(.caption.monospaced()).foregroundStyle(Color.soft) }
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
