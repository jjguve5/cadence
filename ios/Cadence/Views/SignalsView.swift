// Health signals: what the Air watches every day, sleep regularity, Google's monthly trends (logged by hand, they
// aren't in the API) and the habits behind them. Wellness information, never a diagnosis.
import Charts
import SwiftUI

struct MonthlyTrend: Codable, Equatable {
    var month: String // yyyy-MM
    var insulin: String?
    var bloodPressure: String?
}

@MainActor
extension Store {
    /// Sleep Regularity Index (0–100): how often you're in the same state (asleep or awake) at the same clock time
    /// on consecutive days, in 5-minute steps over noon-to-noon windows. Windred et al., Sleep 2024.
    func sleepRegularity(nights: Int = 14) -> Int? {
        func window(_ day: String) -> [Bool]? {
            guard let s = health[day]?.sleep else { return nil }
            let noon = Day.at(-12 * 60, on: day)
            var out = [Bool](repeating: false, count: 288)
            func fill(_ lo: Int, _ hi: Int, _ value: Bool) {
                let from = max(0, lo), to = min(288, hi)
                if from < to { for i in from..<to { out[i] = value } }
            }
            let a = Int(s.startDate.timeIntervalSince(noon) / 300), b = Int(s.endDate.timeIntervalSince(noon) / 300)
            fill(a, b, true)
            for seg in s.segments where seg.stage == "awake" { fill(a + seg.from / 5, a + seg.to / 5, false) }
            return out
        }
        var same = 0, total = 0
        for i in 0..<nights {
            let d = Day.add(-i, to: Day.today), prev = Day.add(-i - 1, to: Day.today)
            guard let w1 = window(d), let w0 = window(prev) else { continue }
            for k in 0..<288 { total += 1; if w1[k] == w0[k] { same += 1 } }
        }
        guard total >= 288 * 3 else { return nil }
        return Int((-100 + 200 * Double(same) / Double(total)).rounded())
    }

    /// Resting HR, HRV and breathing against baseline over the last nights, like Fitbit's 2020 illness study
    func illnessSigns() -> [String] {
        guard let t = health[Day.today] else { return [] }
        var signs: [String] = []
        if let v = t.rhr, let b = baseline({ $0.rhr }), v > b.mean + max(3, 1.5 * b.sd) { signs.append("FC em repouso \(Int(v)), \(Int(v - b.mean)) acima do habitual") }
        if let v = t.hrv, let b = baseline({ $0.hrv }), v < b.mean - 1.5 * b.sd { signs.append("VFC \(Int(v)) ms, bem abaixo do habitual") }
        if let v = t.breathing, let b = baseline({ $0.breathing }), v > b.mean + 1 { signs.append(String(format: "Respiração %.1f/min, acima do habitual", v)) }
        if let v = t.temp, v >= 0.7 { signs.append(String(format: "Temperatura da pele %+.1f°", v)) }
        return signs
    }
}

struct SignalsView: View {
    @EnvironmentObject var store: Store
    private var month: String { String(Day.today.prefix(7)) }

    var body: some View {
        let latest = store.health.values.sorted { $0.date > $1.date }
        let trend = store.records("trend")[month]?.decode(MonthlyTrend.self) ?? MonthlyTrend(month: month)
        let illness = store.illnessSigns()
        Screen(glow: .train) {
            Card(tint: illness.count >= 2 ? .warn : nil) {
                HStack { Eyebrow(text: "Todos os dias · do teu Air"); Spacer(); Chip(text: illness.count >= 2 ? "atenção" : "tudo calmo", color: illness.count >= 2 ? .warn : .good) }
                row("SpO₂ durante a noite", latest.first { $0.spo2 != nil }?.spo2.map { "\(Int($0))%" })
                row("Frequência respiratória", latest.first { $0.breathing != nil }?.breathing.map { String(format: "%.1f /min", $0) })
                row("Aptidão cardiovascular · VO₂ máx.", latest.first { $0.vo2 != nil }?.vo2.map { String(format: "%.0f", $0) })
                row("Temperatura da pele", latest.first { $0.temp != nil }?.temp.map { String(format: "%+.1f° face ao habitual", $0) })
                if illness.count >= 2 {
                    Text("Vários sinais estão fora do habitual ao mesmo tempo (\(illness.joined(separator: ", "))). Este padrão pode surgir 1–2 dias antes de uma constipação, mas álcool, stress, calor ou uma noite tardia também o provocam. É um sinal inespecífico, não um diagnóstico.")
                        .font(.geist(12.5)).foregroundStyle(Color.warn)
                }
            }
            IntradayCard()
            MoreSignalsCard()
            Card(tint: .sleep) {
                Eyebrow(text: "Regularidade do sono", icon: "clock.arrow.circlepath", color: .sleep)
                if let sri = store.sleepRegularity() {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(sri)").font(.geist(30, .bold))
                        Text("/ 100 · últimas 14 noites").font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Bar(progress: Double(sri) / 100, area: .sleep)
                    Text(sri >= 80 ? "Muito regular. Em 60 977 adultos do UK Biobank, quem dormia com horários regulares viveu mais do que quem tinha horários irregulares, mais do que a duração do sono fazia prever." : "Deitar e acordar às mesmas horas conta mais do que o total de horas. Tenta apagar as luzes sempre à mesma hora, com 30 minutos de margem.")
                        .font(.geist(12.5)).foregroundStyle(Color.soft)
                } else {
                    Text("Precisa de algumas noites de dados de sono.").font(.geist(13)).foregroundStyle(Color.soft)
                }
            }
            Card {
                HStack { Eyebrow(text: "Mensal · tendências do Google Health"); Spacer(); Text(Day.date(Day.today).formatted(.dateTime.month(.wide))).font(.geist(12)).foregroundStyle(Color.soft) }
                trendPicker("Tendência de resistência à insulina", ["low", "may be elevated", "elevated"], trend.insulin) { var t = trend; t.insulin = $0; store.put("trend", month, JSONValue.from(t)) }
                trendPicker("Tendência da tensão arterial", ["not elevated", "may be elevated", "elevated"], trend.bloodPressure) { var t = trend; t.bloodPressure = $0; store.put("trend", month, JSONValue.from(t)) }
                Text("Modelos próprios da Google, fora da API: regista o resultado quando chegar o relatório mensal. Se algum disser elevada, uma semana de medições com braçadeira diz-te mais.")
                    .font(.geist(12)).foregroundStyle(Color.faint)
            }
            HealthRecordsCard()
            Card(tint: .fuel) {
                Eyebrow(text: "Os hábitos por trás", color: .fuel)
                let week = (0..<7).compactMap { store.health[Day.add(-$0, to: Day.today)] }
                let steps = week.compactMap(\.steps)
                row("Passos, média de 7 dias", steps.isEmpty ? nil : "\(Int(steps.reduce(0, +) / Double(steps.count)).formatted())")
                let late = week.compactMap(\.sleep).filter { Day.minuteOfDay($0.startDate) < 12 * 60 && Day.minuteOfDay($0.startDate) > 60 }.count
                row("Adormeceste depois da 1:00", "\(late) de \(week.compactMap(\.sleep).count) noites")
                if let rhr = store.baseline({ $0.rhr }) { row("FC em repouso, 14 dias", "\(Int(rhr.mean)) bpm") }
                Text("Frequência cardíaca em repouso, passos e sono foram os melhores preditores de wearables no estudo WEAR-ME da Google sobre a insulina.").font(.geist(12)).foregroundStyle(Color.faint)
            }
        }
        .navigationTitle("Sinais de saúde")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ name: String, _ value: String?) -> some View {
        HStack { Text(name).font(.geist(14)); Spacer(); Text(value ?? "–").font(.geist(14, .semibold)).foregroundStyle(Color.ink) }
    }

    /// What a monthly trend shows; the English value is what's saved, and the chip colour reads it
    private func trendLabel(_ value: String) -> String {
        ["low": "baixa", "may be elevated": "pode estar elevada", "elevated": "elevada", "not elevated": "não elevada"][value] ?? value
    }

    private func trendPicker(_ name: String, _ options: [String], _ value: String?, set: @escaping (String?) -> Void) -> some View {
        HStack {
            Text(name).font(.geist(14))
            Spacer()
            Menu {
                ForEach(options, id: \.self) { o in Button(trendLabel(o)) { set(o) } }
                Button("Sem registo") { set(nil) }
            } label: {
                Chip(text: value.map { trendLabel($0) } ?? "registar", color: value == nil ? .soft : value!.contains("elevated") && !value!.hasPrefix("not") ? .warn : .good)
            }
        }
    }
}
