// Close the day: open must-dos first, then how it went, tomorrow's top 3. The score and Pip's pose come from here.
// Phase 2.8 adds the end-of-day review the Plano opens («Rever o dia»): Feito, Não fiz or Não se aplica, each chosen by
// you; what stays unanswered is «não confirmado».
import SwiftUI

struct CloseDayView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var entry = DayEntry(date: Day.today)
    @State private var tomorrow = ["", "", ""]
    @State private var done = false

    var body: some View {
        NavigationStack {
            Screen(glow: .sleep) {
                HStack(spacing: 12) {
                    PipAnimation(mood: done ? .celebrate : (store.score() >= 60 ? .proud : .idle)).frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Hoje")
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(store.score())").font(.geist(40, .bold))
                            Text("/ 100").font(.geist(13)).foregroundStyle(Color.soft)
                        }
                        Text("Pip: «\(store.pipLine())»").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }

                let open = store.due().filter { store.status($0) == nil }
                if !open.isEmpty {
                    Card(tint: .warn) {
                        Eyebrow(text: "Ainda por fazer", color: .warn)
                        ForEach(open) { PromiseRow(promise: $0, insideSheet: true) }
                    }
                }

                DisclosureGroup("Diário, se tiveres um minuto") { JournalCard(day: Day.today) }
                    .font(.geist(13.5, .medium)).tint(.soft).padding(.horizontal, 4)
                Card {
                    Eyebrow(text: "Como correu o dia?")
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { n in
                            Button { entry.rating = n } label: {
                                Text("\(n)").font(.geist(16, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(entry.rating == n ? AnyShapeStyle(Area.mind.gradient) : AnyShapeStyle(Color.white.opacity(0.08))))
                                    .foregroundStyle(entry.rating == n ? Color(hex: 0x14082B) : Color.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Text("Energia").font(.geist(13)).foregroundStyle(Color.soft)
                        Spacer()
                        ForEach(1...5, id: \.self) { n in
                            Button { entry.energy = n } label: {
                                Image(systemName: n <= (entry.energy ?? 0) ? "bolt.fill" : "bolt").foregroundStyle(Color.fuel).font(.system(size: 18))
                                    .frame(width: 36, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Energia \(n) de 5").accessibilityAddTraits(n == entry.energy ? .isSelected : [])
                            .accessibilityIdentifier("energy.\(n)")
                        }
                    }
                    TextField("Uma linha sobre hoje (opcional)", text: $entry.note, axis: .vertical).font(.geist(14))
                }

                Card {
                    Eyebrow(text: "3 prioridades de amanhã")
                    ForEach(0..<3, id: \.self) { i in
                        TextField("\(i + 1) · acrescenta uma", text: $tomorrow[i]).font(.geist(14))
                    }
                    let carry = entry.top3.enumerated().filter { $0.offset >= entry.top3Done.count || !entry.top3Done[$0.offset] }.map(\.element)
                    if !carry.isEmpty {
                        Button("Passar o que ficou por fazer: \(carry.joined(separator: ", "))") {
                            for (i, item) in carry.prefix(3).enumerated() where tomorrow[i].isEmpty { tomorrow[i] = item }
                        }
                        .font(.geist(12.5)).foregroundStyle(Color.mint)
                    }
                }

                PrimaryButton(title: done ? "Boa noite" : "Fechar o dia") {
                    if done { dismiss(); return }
                    let score = store.score()
                    entry.score = score
                    entry.points = score
                    entry.closedAt = nowMs()
                    store.save(entry)
                    let next = Day.add(1, to: Day.today)
                    var t = store.day(next)
                    t.top3 = tomorrow.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    t.top3Done = Array(repeating: false, count: t.top3.count)
                    store.save(t)
                    withAnimation { done = true }
                }
                .accessibilityIdentifier("closeday.save")
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mais tarde") { dismiss() } } }
            .onAppear {
                entry = store.day()
                let t = store.day(Day.add(1, to: Day.today)).top3
                for (i, item) in t.prefix(3).enumerated() { tomorrow[i] = item }
            }
        }
    }
}

// MARK: - The end-of-day review (phase 2.8, N_PlanoFimDoDia): «Rever o dia» in the Plano

/// A day's answer to a habit in the review. Only you choose it; nothing is inferred, and «Não confirmado» is no answer
/// at all (never «falhado»)
enum ReviewAnswer: CaseIterable {
    case done, notDone, notApplicable, notConfirmed

    var label: String {
        switch self {
        case .done: return "Feito"
        case .notDone: return "Não fiz"
        case .notApplicable: return "Não se aplica"
        case .notConfirmed: return "Não confirmado"
        }
    }

    /// Part of the UI identifiers (plan.review.<habit>.<key>); internal, never shown
    var key: String {
        switch self {
        case .done: return "done"
        case .notDone: return "notdone"
        case .notApplicable: return "na"
        case .notConfirmed: return "none"
        }
    }
}

enum DayReview {
    /// What a saved answer means: tiny counts as done; a skip with notApplicable is «Não se aplica», any other skip
    /// «Não fiz»; no log is «Não confirmado»
    static func answer(_ log: PromiseLog?) -> ReviewAnswer {
        guard let log else { return .notConfirmed }
        switch log.status {
        case .done, .tiny: return .done
        case .skipped: return log.notApplicable == true ? .notApplicable : .notDone
        }
    }

    /// How an answer is saved (decision 2.8): no new LogStatus value, so an older build keeps reading the file;
    /// «Não se aplica» is a skip with notApplicable. «Não confirmado» saves nothing.
    static func saved(_ answer: ReviewAnswer) -> (status: LogStatus, notApplicable: Bool?)? {
        switch answer {
        case .done: return (.done, nil)
        case .notDone: return (.skipped, nil)
        case .notApplicable: return (.skipped, true)
        case .notConfirmed: return nil
        }
    }

    /// «2 feitos · 1 não feito · 1 não se aplica · 1 não confirmado», leaving out what's none
    static func summary(_ answers: [ReviewAnswer]) -> String {
        let forms: [(ReviewAnswer, String, String)] = [(.done, "feito", "feitos"), (.notDone, "não feito", "não feitos"),
                                                      (.notApplicable, "não se aplica", "não se aplicam"), (.notConfirmed, "não confirmado", "não confirmados")]
        var parts: [String] = []
        for (a, one, many) in forms {
            let n = answers.filter { $0 == a }.count
            if n > 0 { parts.append(ptCount(n, one, many)) }
        }
        return parts.isEmpty ? "Nada para rever neste dia." : parts.joined(separator: " · ")
    }

    /// The day's session as Treino has it: ended (Feito or Parcial), left open past its day (Parcial up to its last
    /// activity, on read, as in Treino: decision D23; nothing is written), or open today (Em curso)
    static func sessionLine(_ sessions: [WorkoutSession], today: String) -> (title: String, sub: String, state: DataState, text: String)? {
        if let s = sessions.first(where: { $0.end != nil || TrainingRules.isExpired($0, today: today) }) {
            let minutes = Int(((s.end ?? TrainingRules.lastActivity(s)) - s.start) / 60000)
            let partial = TrainingRules.isPartial(s, today: today)
            return (s.name, "registado no treino · \(minutes) min", partial ? DataState.partial : DataState.confirmed, partial ? "Parcial" : "Feito")
        }
        if let s = sessions.first(where: { $0.end == nil }) { return (s.name, "no treino", DataState.pending, "Em curso") }
        return nil
    }
}

@MainActor
extension Store {
    func reviewAnswer(_ promise: PromiseItem, on day: String) -> ReviewAnswer { DayReview.answer(logs["\(promise.id)|\(day)"]) }

    /// Saves your answer, as yours (source "you"); «Não confirmado» saves nothing
    func saveReview(_ promise: PromiseItem, on day: String, _ answer: ReviewAnswer) {
        guard let s = DayReview.saved(answer) else { return }
        log(promise, on: day, s.status, notApplicable: s.notApplicable)
    }
}

/// «Como correu o dia»: the training as Treino registered it, and each habit of the day with Feito, Não fiz or Não se
/// aplica. Your answers are kept here until «Concluído», which saves them with Desfazer; «Fechar sem rever» saves
/// nothing. What you leave unanswered stays «não confirmado».
struct DayReviewView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let day: String
    @State private var draft: [String: ReviewAnswer] = [:]

    var body: some View {
        let habits = store.due(on: day).sorted { store.time(of: $0, on: day) < store.time(of: $1, on: day) }
        let answers = habits.map { draft[$0.id] ?? store.reviewAnswer($0, on: day) }
        NavigationStack {
            Screen(glow: .sleep) {
                Title(eyebrow: day == Day.today ? "Plano · revisão" : "Plano · revisão · \(PlanFormat.day(day))", title: "Como correu o dia")
                    .padding(.top, 8)
                (Text("Só tu sabes o que aconteceu. O que não marcares fica ") + Text("não confirmado").foregroundColor(.ink).bold() + Text(", nunca falhado."))
                    .font(.geist(13)).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
                Card {
                    if let t = trainingLine {
                        row(title: t.title, sub: t.sub) { StateTag(state: t.state, text: t.text) }
                        if !habits.isEmpty { Divider().overlay(Color.white.opacity(0.08)) }
                    }
                    ForEach(Array(habits.enumerated()), id: \.element.id) { i, p in
                        habitRow(p)
                        if i < habits.count - 1 { Divider().overlay(Color.white.opacity(0.08)) }
                    }
                    if habits.isEmpty && trainingLine == nil {
                        Text("Sem hábitos nem treino neste dia.").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("plan.review.list")
                Text(DayReview.summary(answers)).font(.geist(12)).foregroundStyle(Color.soft).padding(.horizontal, 4)
                    .accessibilityIdentifier("plan.review.summary")
                PrimaryButton(title: "Concluído") { finish(habits) }
                    .accessibilityIdentifier("plan.review.save")
                Button { dismiss() } label: {
                    Text("Fechar sem rever").font(.geist(13.5, .semibold)).foregroundStyle(Color.soft).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.review.close")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// The training as Treino has it: registered, in progress, or planned with no record («Não confirmado»)
    private var trainingLine: (title: String, sub: String, state: DataState, text: String)? {
        if let line = DayReview.sessionLine(store.sessions(on: day), today: Day.today) { return line }
        if let b = store.all(PlanBlock.self).first(where: { $0.date == day && $0.type == "training" }) { return (b.title, "sem registo no treino", DataState.noData, "Não confirmado") }
        if let t = store.templates.first(where: { $0.weekdays.contains(Day.weekday(day)) }) { return (t.name, "sem registo no treino", DataState.noData, "Não confirmado") }
        return nil
    }

    private func row<Trailing: View>(title: String, sub: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.geist(14, .medium))
                Text(sub).font(.geist(12)).foregroundStyle(Color.soft)
            }
            Spacer(minLength: 6)
            trailing()
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder private func habitRow(_ p: PromiseItem) -> some View {
        let saved = store.reviewAnswer(p, on: day)
        row(title: p.title, sub: "\(store.timeLabel(p, on: day)) · \(p.kind == .mustDo ? "essencial" : "hábito")") {
            if saved != .notConfirmed { answerTag(p, saved) }
        }
        if saved == .notConfirmed {
            HStack(spacing: 8) {
                ForEach([ReviewAnswer.done, ReviewAnswer.notDone, ReviewAnswer.notApplicable], id: \.self) { a in choice(a, for: p) }
                Spacer(minLength: 0)
            }
        }
    }

    /// An answer already there: yours, imported (with its source) or of unknown origin, which is never shown as yours
    private func answerTag(_ p: PromiseItem, _ a: ReviewAnswer) -> some View {
        let origin = store.answerOrigin(p, on: day)
        var state = DataState.noData
        var text = a.label
        switch a {
        case .done:
            if case .imported(let source)? = origin {
                state = .imported
                text = "Feito · " + (source == "apple" ? "Apple Health" : source == "fitbit" ? "Fitbit" : source)
            } else {
                state = origin == .you ? .confirmed : .done
            }
        case .notDone: state = .ignored
        case .notApplicable: state = .unavailable
        case .notConfirmed: state = .noData
        }
        return StateTag(state: state, text: text).accessibilityIdentifier("plan.review.\(p.id).state")
    }

    private func choice(_ a: ReviewAnswer, for p: PromiseItem) -> some View {
        let selected = draft[p.id] == a
        return Button { draft[p.id] = selected ? nil : a } label: {
            Text(a.label).font(.geist(13, .semibold))
                .foregroundStyle(selected ? Color(hex: 0x05140F) : a == .notApplicable ? Color.soft : Color.ink)
                .padding(.horizontal, a == .notApplicable && !selected ? 8 : 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(selected ? AnyShapeStyle(Area.mint.gradient) : AnyShapeStyle(Color.white.opacity(a == .done ? 0.1 : 0))))
                .overlay(Capsule().stroke(Color.white.opacity(a == .notDone && !selected ? 0.18 : 0), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel("\(p.title): \(a.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("plan.review.\(p.id).\(a.key)")
    }

    /// «Concluído»: saves the answers you gave (each one yours), with Desfazer for all of them together
    private func finish(_ habits: [PromiseItem]) {
        let s: Store = store, d = day
        var answered: [PromiseItem] = []
        for p in habits {
            guard let a = draft[p.id], a != .notConfirmed, s.reviewAnswer(p, on: d) == .notConfirmed else { continue }
            s.saveReview(p, on: d, a)
            answered.append(p)
        }
        if !answered.isEmpty {
            let saved = answered
            UndoCenter.shared.show(ptCount(saved.count, "resposta guardada", "respostas guardadas")) { for p in saved { s.undo(p, on: d) } }
        }
        dismiss()
    }
}
