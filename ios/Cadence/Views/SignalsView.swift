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
        if let v = t.rhr, let b = baseline({ $0.rhr }), v > b.mean + max(3, 1.5 * b.sd) { signs.append("Resting HR \(Int(v)), up \(Int(v - b.mean))") }
        if let v = t.hrv, let b = baseline({ $0.hrv }), v < b.mean - 1.5 * b.sd { signs.append("HRV \(Int(v)) ms, well below usual") }
        if let v = t.breathing, let b = baseline({ $0.breathing }), v > b.mean + 1 { signs.append(String(format: "Breathing %.1f/min, up", v)) }
        if let v = t.temp, v >= 0.7 { signs.append(String(format: "Skin temperature %+.1f°", v)) }
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
                HStack { Eyebrow(text: "Every day · from your Air"); Spacer(); Chip(text: illness.count >= 2 ? "watch" : "all calm", color: illness.count >= 2 ? .warn : .good) }
                row("Overnight SpO₂", latest.first { $0.spo2 != nil }?.spo2.map { "\(Int($0))%" })
                row("Breathing rate", latest.first { $0.breathing != nil }?.breathing.map { String(format: "%.1f /min", $0) })
                row("Cardio fitness · VO₂ max", latest.first { $0.vo2 != nil }?.vo2.map { String(format: "%.0f", $0) })
                row("Skin temperature", latest.first { $0.temp != nil }?.temp.map { String(format: "%+.1f° vs baseline", $0) })
                if illness.count >= 2 {
                    Text("Several signals are off together (\(illness.joined(separator: ", "))). This pattern can come 1–2 days before a cold, but alcohol, stress, heat or a late night do it too. A non-specific signal, not a diagnosis.")
                        .font(.geist(12.5)).foregroundStyle(Color.warn)
                }
            }
            IntradayCard()
            MoreSignalsCard()
            Card(tint: .sleep) {
                Eyebrow(text: "Sleep regularity", icon: "clock.arrow.circlepath", color: .sleep)
                if let sri = store.sleepRegularity() {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(sri)").font(.geist(30, .bold))
                        Text("/ 100 · last 14 nights").font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Bar(progress: Double(sri) / 100, area: .sleep)
                    Text(sri >= 80 ? "Very regular. In 60,977 UK Biobank adults, regular sleepers lived longer than irregular ones, more than sleep length predicted." : "Going to bed and waking at the same times matters more than total hours. Aim for the same lights-out within 30 minutes.")
                        .font(.geist(12.5)).foregroundStyle(Color.soft)
                } else {
                    Text("Needs a few nights of sleep data.").font(.geist(13)).foregroundStyle(Color.soft)
                }
            }
            Card {
                HStack { Eyebrow(text: "Monthly · Google Health trends"); Spacer(); Text(Day.date(Day.today).formatted(.dateTime.month(.wide))).font(.geist(12)).foregroundStyle(Color.soft) }
                trendPicker("Insulin resistance trend", ["low", "may be elevated", "elevated"], trend.insulin) { var t = trend; t.insulin = $0; store.put("trend", month, JSONValue.from(t)) }
                trendPicker("Blood pressure trend", ["not elevated", "may be elevated", "elevated"], trend.bloodPressure) { var t = trend; t.bloodPressure = $0; store.put("trend", month, JSONValue.from(t)) }
                Text("Google's own models, not in the API: log the result when the monthly report arrives. If one says elevated, a week of cuff readings tells you more.")
                    .font(.geist(12)).foregroundStyle(Color.faint)
            }
            HealthRecordsCard()
            Card(tint: .fuel) {
                Eyebrow(text: "Habits behind them", color: .fuel)
                let week = (0..<7).compactMap { store.health[Day.add(-$0, to: Day.today)] }
                let steps = week.compactMap(\.steps)
                row("Steps, 7-day average", steps.isEmpty ? nil : "\(Int(steps.reduce(0, +) / Double(steps.count)).formatted())")
                let late = week.compactMap(\.sleep).filter { Day.minuteOfDay($0.startDate) < 12 * 60 && Day.minuteOfDay($0.startDate) > 60 }.count
                row("Asleep after 1:00", "\(late) of \(week.compactMap(\.sleep).count) nights")
                if let rhr = store.baseline({ $0.rhr }) { row("Resting HR, 14-day", "\(Int(rhr.mean)) bpm") }
                Text("Resting heart rate, steps and sleep were the top wearable predictors in Google's WEAR-ME insulin study.").font(.geist(12)).foregroundStyle(Color.faint)
            }
        }
        .navigationTitle("Health signals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ name: String, _ value: String?) -> some View {
        HStack { Text(name).font(.geist(14)); Spacer(); Text(value ?? "–").font(.geist(14, .semibold)).foregroundStyle(Color.ink) }
    }

    private func trendPicker(_ name: String, _ options: [String], _ value: String?, set: @escaping (String?) -> Void) -> some View {
        HStack {
            Text(name).font(.geist(14))
            Spacer()
            Menu {
                ForEach(options, id: \.self) { o in Button(o) { set(o) } }
                Button("Not logged") { set(nil) }
            } label: {
                Chip(text: value ?? "log", color: value == nil ? .soft : value!.contains("elevated") && !value!.hasPrefix("not") ? .warn : .good)
            }
        }
    }
}
