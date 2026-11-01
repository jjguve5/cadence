// Body: last night, sleep need and debt, recovery trends and the health signals the API gives.
import Charts
import SwiftUI

struct BodyView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            Screen(glow: .sleep) {
                Title(eyebrow: "Sleep, recovery and signals", title: "Body")
                    .padding(.top, 8)
                NavigationLink { SleepView() } label: { lastNightCard }.buttonStyle(.plain)
                NavigationLink { TrendsView() } label: { trendsCard }.buttonStyle(.plain)
                NavigationLink { SignalsView() } label: { signalsCard }.buttonStyle(.plain)
            }
            .refreshable { await store.refreshHealth(force: true) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var lastNightCard: some View {
        let s = store.health[Day.today]?.sleep
        let plan = store.sleepPlan()
        return Card(tint: .sleep) {
            HStack {
                Eyebrow(text: "Last night", icon: "moon.zzz.fill", color: .sleep)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(s.map { duration($0.asleep) } ?? "–").font(.system(size: 30, weight: .bold))
                    Text("asleep · need \(duration(store.profile.sleepNeed))").font(.system(size: 12)).foregroundStyle(Color.soft)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(duration(plan.debt)).font(.system(size: 22, weight: .bold)).foregroundStyle(plan.debt > 120 ? Color.warn : Color.good)
                    Text("debt · 14 nights").font(.system(size: 12)).foregroundStyle(Color.soft)
                }
            }
            if let s { Hypnogram(sleep: s).frame(height: 70) }
        }
    }

    private var trendsCard: some View {
        let today = store.health[Day.today]
        return Card {
            HStack { Eyebrow(text: "Recovery", icon: "waveform.path.ecg"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
            HStack {
                metric("HRV", today?.hrv.map { "\(Int($0)) ms" })
                metric("Resting HR", today?.rhr.map { "\(Int($0))" })
                metric("Breathing", today?.breathing.map { String(format: "%.1f", $0) })
            }
        }
    }

    private var signalsCard: some View {
        let today = store.health.values.sorted { $0.date > $1.date }
        return Card(tint: .train) {
            HStack { Eyebrow(text: "Health signals", icon: "heart.text.square", color: .train); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
            HStack {
                metric("SpO₂", today.first { $0.spo2 != nil }?.spo2.map { "\(Int($0))%" })
                metric("VO₂ max", today.first { $0.vo2 != nil }?.vo2.map { String(format: "%.0f", $0) })
                metric("Skin temp", today.first { $0.temp != nil }?.temp.map { String(format: "%+.1f°", $0) })
            }
        }
    }

    private func metric(_ name: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "–").font(.system(size: 18, weight: .bold, design: .rounded))
            Text(name).font(.system(size: 11.5)).foregroundStyle(Color.soft)
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
    var body: some View {
        let s = store.health[Day.today]?.sleep
        let plan = store.sleepPlan()
        Screen(glow: .sleep) {
            if let s {
                Card {
                    HStack {
                        Text(s.startDate.formatted(date: .omitted, time: .shortened) + " → " + s.endDate.formatted(date: .omitted, time: .shortened)).font(.system(size: 13)).foregroundStyle(Color.soft)
                        Spacer()
                        Text(duration(s.asleep)).font(.system(size: 22, weight: .bold))
                    }
                    Hypnogram(sleep: s).frame(height: 110)
                    let st = s.stages ?? [:]
                    HStack {
                        ForEach([("Deep", "deep", Color.sleep2), ("REM", "rem", Color.water), ("Light", "light", Color.sleep), ("Awake", "awake", Color.warn)], id: \.1) { name, key, color in
                            VStack(alignment: .leading) {
                                Text(duration(st[key] ?? 0)).font(.system(size: 15, weight: .semibold))
                                HStack(spacing: 4) { Circle().fill(color).frame(width: 6); Text(name).font(.system(size: 11)).foregroundStyle(Color.soft) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                Text("No sleep from last night yet. It appears once the Air syncs.").foregroundStyle(Color.soft).padding(.top, 20)
            }
            Card(tint: .sleep) {
                Eyebrow(text: "Tonight", icon: "bed.double.fill", color: .sleep)
                row("Sleep need", duration(plan.need))
                row("Wind-down", clock(plan.windDown))
                row("Peak bedtime", clock(plan.peak))
                row("Perform", clock(plan.perform))
                row("Get by", clock(plan.getBy))
                Text(plan.debt > 60 ? "\(duration(plan.debt)) of debt over 14 nights: tonight's need includes a 15–30 minute payback." : "No real debt: keep the same rhythm.")
                    .font(.system(size: 12.5)).foregroundStyle(Color.soft)
            }
            Card {
                Eyebrow(text: "Last 14 nights")
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
        .navigationTitle("Recover")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name).font(.system(size: 14)); Spacer(); Text(value).font(.system(size: 14, weight: .semibold, design: .monospaced)) }
    }
}

struct TrendsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let days = (0..<30).reversed().compactMap { store.health[Day.add(-$0, to: Day.today)] }
        Screen(glow: .mint) {
            trend("HRV", unit: "ms", days.compactMap { d in d.hrv.map { (d.date, $0) } }, .mint, higherIsBetter: true)
            trend("Resting heart rate", unit: "bpm", days.compactMap { d in d.rhr.map { (d.date, $0) } }, .train, higherIsBetter: false)
            trend("Breathing rate", unit: "/min", days.compactMap { d in d.breathing.map { (d.date, $0) } }, .water, higherIsBetter: false)
            trend("Steps", unit: "", days.compactMap { d in d.steps.map { (d.date, $0) } }, .fuel, higherIsBetter: true)
        }
        .navigationTitle("Trends · 30 days")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func trend(_ name: String, unit: String, _ points: [(String, Double)], _ area: Area, higherIsBetter: Bool) -> some View {
        let values = points.map(\.1)
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        return Card {
            HStack {
                Eyebrow(text: name)
                Spacer()
                if let last = values.last { Text("\(last.formatted(.number.precision(.fractionLength(0)))) \(unit)").font(.system(size: 14, weight: .semibold, design: .monospaced)) }
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
                Text("Builds up as days arrive.").font(.system(size: 13)).foregroundStyle(Color.soft)
            }
        }
    }
}
