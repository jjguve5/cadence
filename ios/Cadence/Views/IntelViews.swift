// Today's intelligence: the focus card (up to three recommendations with why, evidence, confidence, action and
// dismiss), the minimum viable day banner, quick capture, and the monthly "what Cadence has learned" report.
import SwiftUI

struct FocusCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    @State private var expanded: String?
    @State private var focusing = false
    @State private var loggingFood = false
    @State private var training = false

    var body: some View {
        let recs = store.recommendations()
        Group {
            if !recs.isEmpty {
                Card(tint: .mint) {
                    HStack { Eyebrow(text: "Foco de hoje", icon: "scope", color: .mint); Spacer() }
                    ForEach(Array(recs.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Divider().overlay(Color.white.opacity(0.06)) }
                        row(r, open: i == 0 || expanded == r.id)
                    }
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("focus.card")
            } else if let note = store.freshnessNote {
                Card { Label(note, systemImage: "clock.arrow.circlepath").font(.geist(13)).foregroundStyle(Color.soft) }
            }
        }
        .fullScreenCover(isPresented: $focusing) { FocusView() }
        .sheet(isPresented: $loggingFood) { FoodLogSheet() }
        .navigationDestination(isPresented: $training) { TrainingView() }
    }

    private func row(_ r: Recommendation, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { withAnimation(.easeOut(duration: 0.2)) { expanded = expanded == r.id ? nil : r.id } } label: {
                HStack(alignment: .top) {
                    Text(r.title).font(.geist(open ? 16.5 : 14.5, .semibold)).foregroundStyle(Color.ink).multilineTextAlignment(.leading)
                    Spacer()
                    Chip(text: r.confidence.label, color: r.confidence == .high ? .good : r.confidence == .moderate ? .soft : .warn)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rec.\(r.kind)")
            if open {
                Text(r.why).font(.geist(13.5)).foregroundStyle(Color.ink.opacity(0.9))
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(r.evidence, id: \.self) { e in
                        HStack(alignment: .top, spacing: 6) { Circle().fill(Color.mint.opacity(0.6)).frame(width: 4, height: 4).padding(.top, 6); Text(e).font(.geist(12)).foregroundStyle(Color.soft) }
                    }
                }
                HStack(spacing: 8) {
                    if r.action != .none { SoftButton(title: r.actionLabel, icon: icon(r.action)) { act(r) }.accessibilityIdentifier("rec.\(r.kind).action") }
                    Spacer()
                    Button("Não é útil") { store.feedback(r, useful: false) }.font(.geist(12.5)).foregroundStyle(Color.faint)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("rec.\(r.kind).dismiss")
                }
            }
        }
    }

    private func icon(_ a: RecAction) -> String {
        switch a {
        case .doMustDo: return "checkmark"
        case .protectFocus: return "brain.head.profile"
        case .trainByFeel: return "dumbbell.fill"
        case .earlierBedtime: return "moon.fill"
        case .offerMinimumDay: return "leaf"
        case .placeDeepWork: return "calendar.badge.plus"
        case .logFood: return "fork.knife"
        case .syncAir: return "arrow.triangle.2.circlepath"
        default: return "checkmark"
        }
    }

    private func act(_ r: Recommendation) {
        store.feedback(r, useful: true)
        switch r.action {
        case .doMustDo(let title): if let p = store.openMustDos().first(where: { $0.title == title }) { store.log(p, .done) }
        case .protectFocus: focusing = true
        case .trainByFeel: training = true
        case .earlierBedtime(let m): store.put("bedshift", Day.today, .number(Double(m))); Reminders.shared.reschedule()
        case .offerMinimumDay: store.setMinimumDay(true, reasons: r.evidence)
        case .placeDeepWork(let title):
            if let start = store.suggestedDeepWork() {
                let p = store.all(Project.self).first { $0.title == title }
                store.save(PlanBlock(date: Day.today, start: start, minutes: 100, title: "Trabalho focado · \(title)", type: "deep", projectId: p?.id))
            }
        case .logFood: loggingFood = true
        case .syncAir: openURL(URL(string: "fitbit://")!)
        default: break
        }
    }
}

struct MinimumDayBanner: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if store.isMinimumDay() {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill").font(.geist(12)).foregroundStyle(Color.good)
                Text("Dia mínimo: só o essencial").font(.geist(12.5, .medium)).foregroundStyle(Color.ink.opacity(0.9))
                Spacer()
                Button("Desligar") { store.setMinimumDay(false) }.font(.geist(12.5, .semibold)).tint(.soft)
                    .frame(minHeight: 44).accessibilityIdentifier("mvd.off")
            }
            .padding(.horizontal, 14)
            .background(Capsule().fill(Color.good.opacity(0.12)))
            .accessibilityElement(children: .contain).accessibilityIdentifier("mvd.banner")
        }
    }
}

struct QuickCaptureSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var done: String?
    @State private var undo: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Comi uma banana · gastei 12 € no supermercado · lembra-me…", text: $text, axis: .vertical)
                    .font(.geist(17)).focused($focused)
                    .padding(14).background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.07)))
                    .accessibilityIdentifier("capture.field")
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    let intent = QuickCapture.parse(text)
                    Card {
                        Eyebrow(text: "Percebido como", icon: "text.magnifyingglass")
                        Text(intent.summary).font(.geist(15, .medium)).accessibilityIdentifier("capture.summary")
                    }
                    PrimaryButton(title: "Confirmar") {
                        let r = store.apply(intent)
                        done = r.message
                        undo = r.undo
                        text = ""
                    }
                    .disabled(!intent.savesSomething).opacity(intent.savesSomething ? 1 : 0.4)
                    .accessibilityIdentifier("capture.confirm")
                }
                if let done {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.good).accessibilityHidden(true)
                        Text(done).font(.geist(14)).foregroundStyle(Color.good).accessibilityIdentifier("capture.done")
                        Spacer()
                        if let undo {
                            Button("Desfazer") { undo(); self.undo = nil; self.done = "Desfeito" }
                                .font(.geist(14, .semibold)).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("capture.undo")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Experimenta").font(.geist(12, .semibold)).foregroundStyle(Color.faint)
                    ForEach(["Comi iogurte grego e uma banana", "Gastei 12 euros no supermercado", "Lembra-me de lavar a roupa amanhã às 18:00", "Mudar estudo para amanhã", "Senti-me cansado depois do almoço"], id: \.self) { s in
                        Button(s) { text = s }.font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }
                Spacer()
            }
            .padding(18)
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Registo rápido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() }.accessibilityIdentifier("capture.close") } }
            .onAppear { focused = true }
        }
    }
}

/// The monthly report: what Cadence has learned about you, with sample sizes, and where it's still unsure
struct LearnedView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Screen(glow: .mind) {
            Text("Cada previsão fica registada antes de o dia acontecer e depois é comparada com o que indicaste. Com menos de 10 pares, o Cadence diz isso em vez de adivinhar.")
                .font(.geist(13)).foregroundStyle(Color.soft).padding(.top, 6).accessibilityIdentifier("learned.screen")
            calibration("Prontidão da manhã → a tua energia nessa noite", store.energyPairs())
            calibration("Prontidão → como correu o treino", store.trainingPairs())
            calibration("Curva de energia → qualidade da sessão de foco", store.focusPairs())
            let effects = store.journalEffects()
            Card {
                Eyebrow(text: "Hábitos e o teu sono", icon: "moon.stars")
                if effects.isEmpty { Text("Responde ao diário da manhã durante algumas semanas; cada hábito precisa de 5 dias com ele e 5 sem ele.").font(.geist(12.5)).foregroundStyle(Color.soft) }
                ForEach(effects, id: \.question) { e in
                    HStack { Text(journalText(e.question)).font(.geist(13.5)); Spacer(); Text(e.sleep.map { "\($0 > 0 ? "+" : "")\($0) min" } ?? "–").font(.mono(12.5)).foregroundStyle(Color.soft) }
                }
                Text("Associações nos teus próprios dias. Outras coisas mudam ao mesmo tempo, por isso nada disto prova uma causa.").font(.geist(11)).foregroundStyle(Color.faint)
            }
            Card {
                Eyebrow(text: "Notificações a que respondes", icon: "bell.badge")
                let n = NotificationLearning.summary
                if n.isEmpty { Text("Vai-se formando à medida que respondes aos lembretes ou os descartas.").font(.geist(12.5)).foregroundStyle(Color.soft) }
                ForEach(n, id: \.kind) { k in
                    HStack { Text(kindName(k.kind)).font(.geist(13.5)); Spacer(); Text("\(Int((1 - k.rate) * 100))% respondidas · \(k.n)").font(.mono(12)).foregroundStyle(k.rate >= 0.7 ? Color.warn : Color.soft) }
                }
                Text("Os tipos que descartas 70% das vezes descem de prioridade; a 90% deixam de aparecer. Essenciais, medicamentos e avisos de saída nunca.").font(.geist(11)).foregroundStyle(Color.faint)
            }
        }
        .navigationTitle("O que o Cadence aprendeu")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func kindName(_ k: String) -> String {
        ["p": "Hábitos", "wind": "Desacelerar", "close": "Fechar o dia", "brief": "Resumo da manhã", "protein": "Proteína em falta", "water": "Água", "plant": "Plantas",
         "dry": "Lavandaria", "bday": "Aniversários", "renew": "Renovações", "doc": "Documentos", "touch": "Manter o contacto", "groom": "Cuidados pessoais", "m": "Medicamentos", "leave": "Hora de sair", "shower": "Duche", "gymbag": "Saco do ginásio"][k] ?? k
    }

    private func calibration(_ title: String, _ pairs: [(predicted: Double, observed: Double)]) -> some View {
        let c = Engine.calibrate(pairs)
        return Card {
            Eyebrow(text: title)
            HStack(alignment: .firstTextBaseline) {
                Text(c.spearman.map { String(format: "%.2f", $0) } ?? "–").font(.mono(24, .medium))
                Text("correlação de ordem · \(c.n) pares").font(.geist(12)).foregroundStyle(Color.soft).accessibilityIdentifier("calibration.pairs")
            }
            Text(c.verdict).font(.geist(13.5, .semibold)).foregroundStyle(c.verdict.hasPrefix("Útil") ? Color.good : Color.soft) // "Útil" starts Engine.calibrate's useful verdict (was "Useful" before phase 2.3)
            if let m = c.modelError, let b = c.baselineError { Text(String(format: "Erro médio de %.2f pontos, contra %.2f se adivinhasse pela tua média", m, b)).font(.geist(11.5)).foregroundStyle(Color.faint) }
        }
    }
}
