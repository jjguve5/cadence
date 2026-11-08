// Body: last night, sleep need and debt, recovery trends and the health signals the API gives.
import Charts
import SwiftUI

struct BodyView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            Screen(glow: .sleep) {
                Title(eyebrow: "Sono, recuperação e sinais", title: "Corpo")
                    .accessibilityIdentifier("body.screen") // <name>.screen: how the UI tests know this tab's root is showing. Internal, never translated; if a redesign removes this title, the identifier moves to the new one
                    .padding(.top, 8)
                if store.profile.on("fuel") { NavigationLink { FuelView() } label: { fuelCard }.buttonStyle(.plain) }
                if store.profile.on("training") {
                    NavigationLink { TrainingView() } label: { trainingCard }.buttonStyle(.plain).accessibilityIdentifier("body.training")
                    NavigationLink { GrowthView() } label: { GrowthCard() }.buttonStyle(.plain)
                }
                if store.profile.on("care") { NavigationLink { CareView() } label: { careCard }.buttonStyle(.plain) }
                NavigationLink { SleepView() } label: { lastNightCard }.buttonStyle(.plain)
                NavigationLink { TrendsView() } label: { trendsCard }.buttonStyle(.plain)
                NavigationLink { SignalsView() } label: { signalsCard }.buttonStyle(.plain)
            }
            .refreshable { await store.refreshHealth(force: true) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var fuelCard: some View {
        let f = store.fuel(), p = store.profile
        return Card(tint: .fuel) {
            HStack { Eyebrow(text: "Comida", icon: "fork.knife", color: .fuel); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
            HStack(spacing: 14) {
                mini("Calorias", ring: .calories, f.kcal / p.kcal, .fuel, "\(Int(f.kcal))")
                mini("Proteína", ring: .protein, f.protein / p.proteinTarget, .train, "\(Int(f.protein)) g")
                mini("Água", ring: .water, f.water / store.waterGoal(), .water, String(format: "%.1f L", f.water / 1000))
            }
        }
    }

    private var careCard: some View {
        let doses = store.doses().filter { $0.log == nil }.count
        return Card(tint: .mind) {
            HStack { Eyebrow(text: "Medicamentos", icon: "pills.fill", color: .mind); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
            Text(doses == 1 ? "1 dose por tomar" : doses > 0 ? "\(doses) doses por tomar" : "Medicamentos tomados").font(.geist(13.5))
        }
    }

    private var trainingCard: some View {
        let last = store.sessions().first { $0.end != nil }
        return Card(tint: .train) {
            HStack { Eyebrow(text: "Treino", icon: "dumbbell.fill", color: .train); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
            if let a = store.activeSession { Text("Em curso: \(a.name)").font(.geist(15, .semibold)) }
            else if let last { Text("Último: \(last.name) · \(Day.date(last.date).formatted(.dateTime.weekday(.wide)))").font(.geist(14)) }
            else { Text("Modelos, modo de treino, progressão e mapa corporal.").font(.geist(13)).foregroundStyle(Color.soft) }
        }
    }

    /// `ring` is the Today ring's key (RingStat.key), not its name, so a translated name can't lose the pace marker
    private func mini(_ name: String, ring key: RingKey, _ progress: Double, _ area: Area, _ value: String) -> some View {
        HStack(spacing: 8) {
            Ring(progress: progress, area: area, width: 5, marker: store.ringStats().day.first { $0.key == key }?.pace).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.geist(13, .bold))
                Text(name).font(.geist(10.5)).foregroundStyle(Color.soft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lastNightCard: some View {
        let s = store.health[Day.today]?.sleep
        let plan = store.sleepPlan()
        return Card(tint: .sleep) {
            HStack {
                Eyebrow(text: "Última noite", icon: "moon.zzz.fill", color: .sleep)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(s.map { duration($0.asleep) } ?? "–").font(.geist(30, .bold))
                    Text("de sono · precisas de \(duration(store.profile.sleepNeed))").font(.geist(12)).foregroundStyle(Color.soft)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(duration(plan.debt)).font(.geist(22, .bold)).foregroundStyle(plan.debt > 120 ? Color.warn : Color.good)
                    Text("dívida · 14 noites").font(.geist(12)).foregroundStyle(Color.soft)
                }
            }
            if let s { Hypnogram(sleep: s).frame(height: 70) }
        }
    }

    private var trendsCard: some View {
        let today = store.health[Day.today]
        return Card {
            HStack { Eyebrow(text: "Recuperação", icon: "waveform.path.ecg"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
            HStack {
                metric("VFC", today?.hrv.map { "\(Int($0)) ms" })
                metric("FC em repouso", today?.rhr.map { "\(Int($0))" })
                metric("Respiração", today?.breathing.map { String(format: "%.1f", $0) })
            }
        }
    }

    private var signalsCard: some View {
        let today = store.health.values.sorted { $0.date > $1.date }
        return Card(tint: .train) {
            HStack { Eyebrow(text: "Sinais de saúde", icon: "heart.text.square", color: .train); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
            HStack {
                metric("SpO₂", today.first { $0.spo2 != nil }?.spo2.map { "\(Int($0))%" })
                metric("VO₂ máx.", today.first { $0.vo2 != nil }?.vo2.map { String(format: "%.0f", $0) })
                metric("Temp. da pele", today.first { $0.temp != nil }?.temp.map { String(format: "%+.1f°", $0) })
            }
        }
    }

    private func metric(_ name: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "–").font(.geist(18, .bold))
            Text(name).font(.geist(11.5)).foregroundStyle(Color.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Hypnogram: View {
    var sleep: SleepRecord
    private func level(_ stage: String) -> Int { ["awake": 3, "rem": 2, "light": 1, "deep": 0][stage] ?? 1 }
    private func color(_ stage: String) -> Color { ["awake": Color.warn, "rem": Color.water, "light": Color.sleep, "deep": Color.sleep2][stage] ?? Color.sleep }

    var body: some View {
        Chart(sleep.segments) { seg in
            RectangleMark(xStart: .value("from", seg.from), xEnd: .value("to", seg.to), yStart: .value("lo", level(seg.stage)), yEnd: .value("hi", level(seg.stage) + 1))
                .foregroundStyle(color(seg.stage))
                .cornerRadius(2)
        }
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
    }
}

struct SleepView: View {
    @EnvironmentObject var store: Store
    @State private var breathing = false
    var body: some View {
        let s = store.health[Day.today]?.sleep
        let plan = store.sleepPlan()
        Screen(glow: .sleep) {
            if let s {
                Card {
                    HStack {
                        Text(s.startDate.formatted(date: .omitted, time: .shortened) + " → " + s.endDate.formatted(date: .omitted, time: .shortened)).font(.geist(13)).foregroundStyle(Color.soft)
                        Spacer()
                        Text(duration(s.asleep)).font(.geist(22, .bold))
                    }
                    Hypnogram(sleep: s).frame(height: 110)
                    let st = s.stages ?? [:]
                    HStack {
                        ForEach([("Profundo", "deep", Color.sleep2), ("REM", "rem", Color.water), ("Leve", "light", Color.sleep), ("Acordado", "awake", Color.warn)], id: \.1) { name, key, color in
                            VStack(alignment: .leading) {
                                Text(duration(st[key] ?? 0)).font(.geist(15, .semibold))
                                HStack(spacing: 4) { Circle().fill(color).frame(width: 6); Text(name).font(.geist(11)).foregroundStyle(Color.soft) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                Text("Ainda não há sono da última noite. Aparece quando o Air sincronizar.").foregroundStyle(Color.soft).padding(.top, 20)
            }
            Card(tint: .sleep) {
                Eyebrow(text: "Esta noite", icon: "bed.double.fill", color: .sleep)
                row("Sono necessário", duration(plan.need))
                row("Desacelerar", clock(plan.windDown))
                row("Hora de deitar ideal", clock(plan.peak))
                row("Para render bem", clock(plan.perform))
                row("Para aguentar", clock(plan.getBy))
                Text(plan.debt > 60 ? "\(duration(plan.debt)) de dívida em 14 noites: o que precisas esta noite inclui 15–30 minutos para a compensar." : "Sem dívida real: mantém o mesmo ritmo.")
                    .font(.geist(12.5)).foregroundStyle(Color.soft)
            }
            NapCard()
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Respiração e descanso profundo", icon: "wind")
                        Text("Respiração quadrada, suspiro fisiológico, 10–20 minutos de descanso profundo").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                    Spacer()
                    Button { breathing = true } label: { Image(systemName: "play.fill").foregroundStyle(Color(hex: 0x14082B)).frame(width: 40, height: 40).background(Circle().fill(Area.sleep.gradient)) }
                }
            }
            .fullScreenCover(isPresented: $breathing) { BreathingView() }
            Card {
                Eyebrow(text: "Últimas 14 noites")
                let nights = (0..<14).reversed().compactMap { i -> (String, Int)? in
                    let d = Day.add(-i, to: Day.today)
                    return store.health[d]?.sleep.map { (d, $0.asleep) }
                }
                Chart {
                    ForEach(nights, id: \.0) { d, m in
                        BarMark(x: .value("day", Day.date(d), unit: .day), y: .value("hours", Double(m) / 60))
                            .foregroundStyle(m >= store.profile.sleepNeed - 15 ? Color.sleep : Color.warn)
                            .cornerRadius(3)
                    }
                    RuleMark(y: .value("need", Double(store.profile.sleepNeed) / 60)).foregroundStyle(Color.good.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .frame(height: 150)
            }
        }
        .navigationTitle("Recuperação")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name).font(.geist(14)); Spacer(); Text(value).font(.mono(14, .semibold)) }
    }
}

struct TrendsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let days = (0..<30).reversed().compactMap { store.health[Day.add(-$0, to: Day.today)] }
        Screen(glow: .mint) {
            trend("VFC", unit: "ms", days.compactMap { d in d.hrv.map { (d.date, $0) } }, .mint, higherIsBetter: true)
            trend("FC em repouso", unit: "bpm", days.compactMap { d in d.rhr.map { (d.date, $0) } }, .train, higherIsBetter: false)
            trend("Frequência respiratória", unit: "/min", days.compactMap { d in d.breathing.map { (d.date, $0) } }, .water, higherIsBetter: false)
            trend("Passos", unit: "", days.compactMap { d in d.steps.map { (d.date, $0) } }, .fuel, higherIsBetter: true)
        }
        .navigationTitle("Tendências · 30 dias")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func trend(_ name: String, unit: String, _ points: [(String, Double)], _ area: Area, higherIsBetter: Bool) -> some View {
        let values = points.map(\.1)
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        return Card {
            HStack {
                Eyebrow(text: name)
                Spacer()
                if let last = values.last { Text("\(last.formatted(.number.precision(.fractionLength(0)))) \(unit)").font(.mono(14, .semibold)) }
            }
            if points.count >= 2 {
                Chart {
                    ForEach(points, id: \.0) { d, v in
                        LineMark(x: .value("day", Day.date(d), unit: .day), y: .value(name, v)).foregroundStyle(area.gradient).interpolationMethod(.catmullRom)
                    }
                    RuleMark(y: .value("avg", avg)).foregroundStyle(Color.faint).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 110)
            } else {
                Text("Vai aparecendo à medida que os dias chegam.").font(.geist(13)).foregroundStyle(Color.soft)
            }
        }
    }
}
