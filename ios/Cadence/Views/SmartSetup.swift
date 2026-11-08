// Smart setup: a few questions about you, your training and your goal, then targets from published guidance, each
// with its reason. Calories start from your Air's measured burn when there's enough of it, otherwise from the
// Mifflin-St Jeor equation; the weekly check-in then adjusts them to what your weight actually does.
// The answers are kept, so the goal can change anytime (GoalMenu) and every target follows.
import SwiftUI

struct SetupInputs: Codable, Equatable {
    var male = true
    var age = 25
    var height = 178.0
    var weight = 76.0
    var bodyFat: Double?
    var job = "desk" // desk, mixed, feet, physical
    var trainingDays = 4
    var goal = "gain" // lose, gain, recomp, maintain
    var pace = "steady" // gentle, steady, fast
    var sleepHours = 8.0
    var wakeMinute = 7 * 60 + 15
}

struct SetupPlan {
    var kcal: Double
    var protein: Double
    var proteinPerKg: Double
    var fat: Double
    var carbs: Double
    var waterMl: Double
    var steps: Int
    var sleepNeed: Int
    var reasons: [(title: String, value: String, why: String)]
}

let goalNames = ["lose": "Perder gordura", "gain": "Ganhar músculo", "recomp": "Recomposição", "maintain": "Manter"]
/// What each pace shows; the English key is what's saved
fileprivate let paceNames = ["gentle": "suave", "steady": "moderado", "fast": "rápido"]

enum SetupPlanner {
    static func plan(_ i: SetupInputs, airBurn: Double?, averageSteps: Double?) -> SetupPlan {
        var reasons: [(title: String, value: String, why: String)] = []
        // Resting burn
        let bmr: Double
        if let bf = i.bodyFat {
            let lean = i.weight * (1 - bf / 100)
            bmr = 370 + 21.6 * lean
            reasons.append(("Gasto em repouso", "\(Int(bmr)) kcal", "Katch-McArdle, a partir da tua massa magra (\(kg((lean * 10).rounded() / 10)) kg)."))
        } else {
            bmr = 10 * i.weight + 6.25 * i.height - 5 * Double(i.age) + (i.male ? 5 : -161)
            reasons.append(("Gasto em repouso", "\(Int(bmr)) kcal", "Mifflin-St Jeor, a mais precisa das equações habituais nos estudos de validação (erro abaixo de 10% para a maioria das pessoas)."))
        }
        // Daily burn: the Air's measurement, else activity factors
        let jobFactor = ["desk": 1.25, "mixed": 1.4, "feet": 1.55, "physical": 1.75][i.job] ?? 1.3
        let training = Double(i.trainingDays) * 300 / 7 // a 60-minute lifting session burns roughly 250–350 kcal
        let formula = bmr * jobFactor + training
        let tdee: Double
        if let burn = airBurn {
            tdee = burn * 0.9 + formula * 0.1 // wrist trackers tend to read a little high; lean on the measurement
            reasons.append(("Gasto diário", "\(Int(tdee).formatted()) kcal", "Pela média do teu Air nos últimos 14 dias (\(Int(burn).formatted()) kcal), com uma pequena correção na direção da equação."))
        } else {
            tdee = formula
            reasons.append(("Gasto diário", "\(Int(tdee).formatted()) kcal", "O teu gasto em repouso × \(String(format: "%.2f", jobFactor)) pelo teu dia, mais cerca de \(Int(training)) kcal por dia de treino."))
        }
        // Calories for the goal
        var kcal = tdee
        switch i.goal {
        case "lose":
            let rate = ["gentle": 0.005, "steady": 0.007, "fast": 0.01][i.pace] ?? 0.007
            let deficit = min(1000, rate * i.weight * 7700 / 7)
            kcal = max(i.male ? 1500 : 1200, tdee - deficit)
            reasons.append(("Calorias", "\(Int(kcal).formatted()) kcal", "Um défice de \(Int(deficit)) kcal por dia faz perder cerca de \(kg((rate * i.weight * 100).rounded() / 100)) kg por semana (cerca de 7700 kcal por kg de gordura), dentro dos 0.5–1% por semana que preservam o músculo (Helms et al. 2014)."))
        case "gain":
            let rate = ["gentle": 0.0025, "steady": 0.005, "fast": 0.01][i.pace] ?? 0.005
            let surplus = max(150, min(500, rate * i.weight * 7700 / 30))
            kcal = tdee + surplus
            reasons.append(("Calorias", "\(Int(kcal).formatted()) kcal", "Um excedente de \(Int(surplus)) kcal por dia, cerca de \(kg((rate * i.weight * 100).rounded() / 100)) kg por mês: um ganho de massa limpo. Em quem já treina, excedentes maiores dão pouco músculo extra e sobretudo gordura (Iraki et al. 2019)."))
        case "recomp":
            kcal = tdee * 0.9
            reasons.append(("Calorias", "\(Int(kcal).formatted()) kcal", "10% abaixo do teu gasto: perda de gordura lenta, enquanto a proteína alta e o treino continuam a construir músculo."))
        default:
            reasons.append(("Calorias", "\(Int(kcal).formatted()) kcal", "Igual ao teu gasto, para manter o peso."))
        }
        // Protein
        let deficit = i.goal == "lose" || i.goal == "recomp"
        let perKg = deficit ? 2.2 : 1.8
        let protein = (i.weight * perKg).rounded()
        reasons.append(("Proteína", "\(Int(protein)) g", deficit
            ? "2.2 g por kg: em défice, mais proteína protege o músculo (Helms et al. 2014 sugerem 2.3–3.1 g por kg de massa magra)."
            : "1.8 g por kg: o ganho de músculo estabiliza perto de 1.6 g por kg na maior meta-análise (Morton et al. 2018), e algumas pessoas beneficiam até 2.2."))
        // Fat and carbs
        let fat = max(i.weight * 0.8, kcal * 0.25 / 9).rounded()
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4).rounded()
        reasons.append(("Gordura e hidratos", "\(Int(fat)) g · \(Int(carbs)) g", "Gordura de pelo menos 0.8 g por kg e 25% das calorias, pelas hormonas; o resto são hidratos, que alimentam o treino intenso."))
        // Water
        let water = max(i.male ? 2000 : 1600, (i.weight * 35 / 50).rounded() * 50 - 500)
        reasons.append(("Água", String(format: "%.1f L", water / 1000), "Cerca de 35 ml por kg no total (EFSA: 2.5 L por dia para homens, 2.0 para mulheres, incluindo os ~20% que vêm da comida). Os dias de treino somam 0.5 L, os dias quentes mais."))
        // Steps
        let current = averageSteps ?? 6000
        let steps = current < 6000 ? Int((current + 1500) / 500) * 500 : current < 8000 ? 8000 : 10000
        reasons.append(("Passos", steps.formatted(), "O benefício dos passos na mortalidade estabiliza perto de 8000–10 000 por dia abaixo dos 60 anos (Paluch et al., Lancet 2022). A meta fica um degrau acima de onde estás agora."))
        // Sleep
        let need = Int(i.sleepHours * 60)
        reasons.append(("Sono", duration(need), "A dormir, não na cama: o que te faz sentir melhor, dentro das 7–9 horas recomendadas para adultos (AASM). A hora de apagar as luzes conta a partir da hora a que acordas."))
        reasons.append(("Creatina", "3–5 g por dia", "Posição da ISSN: 3–5 g por dia mantêm as reservas musculares cheias; a hora quase não importa, a regularidade sim."))
        return SetupPlan(kcal: (kcal / 10).rounded() * 10, protein: protein, proteinPerKg: perKg, fat: fat, carbs: carbs, waterMl: water, steps: steps, sleepNeed: need, reasons: reasons)
    }
}

@MainActor
extension Store {
    var airBurn: Double? {
        let days = (1...14).compactMap { health[Day.add(-$0, to: Day.today)]?.calories }.filter { $0 > 1200 }
        return days.count >= 7 ? days.reduce(0, +) / Double(days.count) : nil
    }

    var averageSteps14: Double? {
        let s = (1...14).compactMap { health[Day.add(-$0, to: Day.today)]?.steps }
        return s.count >= 5 ? s.reduce(0, +) / Double(s.count) : nil
    }

    var setupInputs: SetupInputs {
        if let s = profile.setup { return s }
        var i = SetupInputs()
        i.male = profile.male; i.age = profile.age; i.height = profile.heightCm; i.weight = profile.weightKg
        i.goal = goalNames[profile.goal] == nil ? "gain" : profile.goal
        i.sleepHours = Double(profile.sleepNeed) / 60
        i.wakeMinute = profile.wakeMinute
        i.trainingDays = max(i.trainingDays, templates.flatMap(\.weekdays).count)
        return i
    }

    /// Sets every target from the setup answers; used by the wizard and by changing the goal anywhere
    func applySetup(_ i: SetupInputs) {
        let p = SetupPlanner.plan(i, airBurn: airBurn, averageSteps: averageSteps14)
        update { pr in
            pr.setup = i
            pr.male = i.male; pr.age = i.age; pr.heightCm = i.height; pr.weightKg = i.weight
            pr.goal = i.goal; pr.kcalTarget = p.kcal; pr.proteinPerKg = p.proteinPerKg
            pr.waterGoalMl = p.waterMl; pr.stepGoal = p.steps; pr.sleepNeed = p.sleepNeed
            pr.wakeMinute = i.wakeMinute
            pr.fatTarget = p.fat; pr.carbTarget = p.carbs; pr.setupDone = true
        }
    }

    func changeGoal(_ goal: String, pace: String? = nil) {
        var i = setupInputs
        i.goal = goal
        if let pace { i.pace = pace }
        if let w = all(WeightEntry.self).max(by: { $0.date < $1.date }) { i.weight = w.kg }
        applySetup(i)
    }
}

/// The goal, changeable in one tap; every target follows
struct GoalMenu: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Menu {
            Menu("Perder gordura") { paces("lose") }
            Menu("Ganhar músculo") { paces("gain") }
            Button("Recomposição") { store.changeGoal("recomp") }
            Button("Manter") { store.changeGoal("maintain") }
        } label: {
            let i = store.setupInputs
            let pace = i.goal == "lose" || i.goal == "gain" ? " · \(paceNames[i.pace] ?? i.pace)" : ""
            Label((goalNames[store.profile.goal] ?? "Objetivo") + pace, systemImage: "target")
                .font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.09)).overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1)))
        }
    }

    @ViewBuilder private func paces(_ goal: String) -> some View {
        Button("Suave") { store.changeGoal(goal, pace: "gentle") }
        Button("Moderado") { store.changeGoal(goal, pace: "steady") }
        Button("Rápido") { store.changeGoal(goal, pace: "fast") }
    }
}

struct SmartSetup: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var i = SetupInputs()
    @State private var wake = Date()
    var startPage = 0

    private let pages = ["Sobre ti", "Os teus dias", "O teu objetivo", "Sono", "O teu plano"]

    var body: some View {
        NavigationStack {
            Form {
                switch page {
                case 0:
                    Section {
                        Picker("Sexo", selection: $i.male) { Text("Masculino").tag(true); Text("Feminino").tag(false) }.pickerStyle(.segmented)
                        Stepper("Idade \(i.age)", value: $i.age, in: 14...90)
                        Stepper("Altura \(Int(i.height)) cm", value: $i.height, in: 130...220)
                        Stepper("Peso \(kg(i.weight)) kg", value: $i.weight, in: 35...200, step: 0.5)
                        Toggle("Sei a minha gordura corporal", isOn: Binding(get: { i.bodyFat != nil }, set: { i.bodyFat = $0 ? 16 : nil }))
                        if let bf = i.bodyFat { Stepper("Gordura corporal \(Int(bf))%", value: Binding(get: { bf }, set: { i.bodyFat = $0 }), in: 4...50) }
                    } footer: { Text("A gordura corporal é opcional: com ela, o gasto em repouso usa a massa magra (Katch-McArdle), que é mais precisa para quem treina.") }
                case 1:
                    Section("Trabalho e dia a dia") {
                        Picker("Na maior parte do dia", selection: $i.job) {
                            Text("À secretária").tag("desk"); Text("Misto, a andar às vezes").tag("mixed"); Text("De pé").tag("feet"); Text("Trabalho físico").tag("physical")
                        }
                        .pickerStyle(.inline)
                    }
                    Section {
                        Stepper("Treino \(i.trainingDays) \(i.trainingDays == 1 ? "dia" : "dias") por semana", value: $i.trainingDays, in: 0...7)
                        if let steps = store.averageSteps14 { LabeledContent("Os teus passos, média de 14 dias", value: Int(steps).formatted()) }
                        if let burn = store.airBurn { LabeledContent("Gasto por dia, pelo teu Air", value: "\(Int(burn).formatted()) kcal") }
                    } footer: { Text(store.airBurn != nil ? "O gasto medido pelo teu Air é o ponto de partida; as respostas afinam o resto." : "Enquanto não há dados suficientes do Air, as respostas sobre atividade definem o gasto.") }
                case 2:
                    Section {
                        Picker("Objetivo", selection: $i.goal) {
                            Text("Perder gordura").tag("lose"); Text("Ganhar músculo").tag("gain"); Text("Recomposição").tag("recomp"); Text("Manter").tag("maintain")
                        }
                        .pickerStyle(.inline)
                        if i.goal == "lose" || i.goal == "gain" {
                            Picker("Ritmo", selection: $i.pace) { Text("Suave").tag("gentle"); Text("Moderado").tag("steady"); Text("Rápido").tag("fast") }.pickerStyle(.segmented)
                        }
                    } footer: { Text(goalHelp) }
                case 3:
                    Section {
                        Stepper("Sinto-me melhor com \(String(format: "%.1f", i.sleepHours)) h", value: $i.sleepHours, in: 6...10, step: 0.25)
                        DatePicker("Acordo às", selection: $wake, displayedComponents: .hourAndMinute)
                        if let real = averageSleep { LabeledContent("A tua média, últimas 14 noites", value: duration(real)) }
                    } footer: { Text("Os adultos precisam de 7 horas ou mais (AASM e Sleep Research Society); os jovens adultos, normalmente 7–9. Se não souberes, 8 é um bom começo; o Cadence aprende com a tua prontidão.") }
                default:
                    let p = SetupPlanner.plan(i, airBurn: store.airBurn, averageSteps: store.averageSteps14)
                    Section("As tuas metas diárias") {
                        row("Calorias", "\(Int(p.kcal).formatted()) kcal")
                        row("Proteína", "\(Int(p.protein)) g")
                        row("Gordura", "\(Int(p.fat)) g")
                        row("Hidratos", "\(Int(p.carbs)) g")
                        row("Água, bebidas", String(format: "%.1f L", p.waterMl / 1000))
                        row("Passos", p.steps.formatted())
                        row("Sono", duration(p.sleepNeed) + " a dormir")
                    }
                    Section("Porquê estes números") {
                        ForEach(p.reasons, id: \.title) { r in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(r.title).font(.geist(14, .semibold)); Spacer(); Text(r.value).font(.mono(13)).foregroundStyle(Color.mint) }
                                Text(r.why).font(.geist(12.5)).foregroundStyle(Color.soft)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Section { Text("Pontos de partida de estudos populacionais, não conselho médico. Todas as semanas o Cadence compara o que comeste com a evolução do teu peso e propõe uma meta de calorias corrigida. Muda o objetivo quando quiseres em Comida; todas as metas acompanham.").font(.footnote).foregroundStyle(Color.faint) }
                }
            }
            .cadenceList()
            .navigationTitle(pages[page])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(page == 0 ? "Cancelar" : "Voltar") { if page == 0 { dismiss() } else { page -= 1 } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(page == pages.count - 1 ? "Usar estas" : "Seguinte") { if page == pages.count - 1 { apply() } else { page += 1 } }.bold()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name); Spacer(); Text(value).font(.mono(15, .medium)) }
    }

    private var goalHelp: String {
        switch i.goal {
        case "lose": return "Suave: cerca de 0.5% do teu peso por semana; moderado 0.7%; rápido 1%. Perdas mais lentas preservam mais músculo (Helms et al. 2014)."
        case "gain": return "Suave: cerca de 0.25% do teu peso por mês, acima da manutenção; moderado 0.5%; rápido 1%. Excedentes maiores somam sobretudo gordura (Iraki et al. 2019)."
        case "recomp": return "Um défice pequeno com proteína alta e treino intenso: a balança muda devagar, a gordura desce e o músculo sobe. Resulta melhor para quem começou há pouco ou regressa de uma pausa."
        default: return "Come o que gastas; a proteína mantém-se alta para preservar o músculo."
        }
    }

    private var averageSleep: Int? {
        let s = (0..<14).compactMap { store.health[Day.add(-$0, to: Day.today)]?.sleep?.asleep }
        return s.count >= 5 ? s.reduce(0, +) / s.count : nil
    }

    private func load() {
        i = store.setupInputs
        if let w = store.all(WeightEntry.self).max(by: { $0.date < $1.date }) { i.weight = w.kg }
        wake = Day.at(i.wakeMinute, on: Day.today)
        page = startPage
    }

    private func apply() {
        i.wakeMinute = Day.minuteOfDay(wake)
        store.applySetup(i)
        store.save(WeightEntry(kg: i.weight))
        dismiss()
    }
}
