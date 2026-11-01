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
        .navigationTitle("Growth")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $addingGoal) { GoalForm(goal: $0) }
        .sheet(item: $addingExperiment) { ExperimentForm(experiment: $0) }
    }

    private var challengeCard: some View {
        let c = store.challenge()
        return Card(tint: Color(hex: 0xFFD166)) {
            HStack { Eyebrow(text: "This week's challenge · \(c.area)", icon: "flag.checkered", color: Color(hex: 0xFFD166)); Spacer(); if c.done { Chip(text: "done", color: .good) } }
            Text(c.text).font(.geist(15, .semibold))
            if !c.done { SoftButton(title: "I did it", icon: "checkmark") { var x = c; x.done = true; store.save(x) } }
        }
    }

    private var goalsCard: some View {
        Card {
            HStack { Eyebrow(text: "Goals", icon: "target"); Spacer(); Button { addingGoal = LifeGoal(title: "", metric: "books", target: 24) } label: { Image(systemName: "plus") }.tint(.mind) }
            ForEach(store.all(LifeGoal.self)) { g in
                let p = store.goalProgress(g)
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(g.title).font(.geist(14, .medium)); Spacer(); Text("\(kg((p.current * 10).rounded() / 10)) / \(kg(g.target))").font(.mono(12.5)).foregroundStyle(Color.soft) }
                    Bar(progress: g.metric == "weight" ? 1 - abs(g.target - p.current) / max(1, abs(g.target - store.profile.weightKg) + 1) : p.current / max(0.1, g.target), area: .mind)
                    if let eta = p.eta { Text("At this pace: \(Day.date(eta).formatted(.dateTime.day().month().year()))" + (g.by.map { eta <= $0 ? " · on time" : " · after your date" } ?? "")).font(.geist(11.5)).foregroundStyle(Color.faint) }
                }
                .contextMenu { Button("Delete", role: .destructive) { store.remove(g) } }
            }
        }
    }

    private var experimentsCard: some View {
        Card {
            HStack { Eyebrow(text: "Experiments · 14 days", icon: "flask.fill"); Spacer(); Button { addingExperiment = Experiment(title: "") } label: { Image(systemName: "plus") }.tint(.mind) }
            ForEach(store.all(Experiment.self).sorted { $0.start > $1.start }) { e in
                let r = store.experimentResult(e)
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(e.title).font(.geist(14, .semibold)); Spacer(); Chip(text: r.daysIn >= e.days ? "finished" : "day \(r.daysIn) of \(e.days)", color: .mind) }
                    if let b = r.before, let d = r.during {
                        let diff = d - b
                        Text("\(e.metric.capitalized): \(format(e.metric, b)) before → \(format(e.metric, d)) during (\(diff >= 0 ? "+" : "")\(format(e.metric, diff, delta: true)))").font(.geist(12.5)).foregroundStyle(Color.soft)
                    }
                }
                .contextMenu { Button("Delete", role: .destructive) { store.remove(e) } }
            }
            Text("One change at a time, measured against your own two weeks before.").font(.geist(11.5)).foregroundStyle(Color.faint)
        }
    }

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
                HStack { Eyebrow(text: "Weekly review", icon: "calendar.badge.clock"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                Text(store.weekReview(store.week).prefix(3).map { "\($0.0) \($0.1)" }.joined(separator: " · ")).font(.geist(13)).foregroundStyle(Color.soft)
            }
        }
        .buttonStyle(.plain)
    }

    private var ageCard: some View {
        Group {
            if let a = store.cadenceAge() {
                Card(tint: .mint) {
                    Eyebrow(text: "Cadence age", icon: "hourglass", color: .mint)
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.1f", a.age)).font(.geist(30, .bold))
                        Text("vs \(store.profile.age) on the calendar").font(.geist(12.5)).foregroundStyle(Color.soft)
                    }
                    ForEach(a.parts, id: \.0) { name, years in HStack { Text(name).font(.geist(13)); Spacer(); Text(String(format: "%+.1f y", years)).font(.mono(13)).foregroundStyle(years <= 0 ? Color.good : Color.warn) } }
                    Text("An estimate from resting HR, VO₂ max, steps and sleep regularity, in the spirit of WHOOP's healthspan. Not a medical measure.").font(.geist(11)).foregroundStyle(Color.faint)
                }
            }
        }
    }

    private var leversCard: some View {
        let levers = store.levers(), effects = store.journalEffects()
        return Group {
            if !levers.isEmpty || !effects.isEmpty {
                Card {
                    Eyebrow(text: "What affects you", icon: "slider.horizontal.3")
                    ForEach(levers, id: \.self) { Text("Before your best days: \($0.lowercased())").font(.geist(13.5)) }
                    ForEach(effects, id: \.question) { e in
                        if let s = e.sleep, abs(s) >= 10 { Text("\(e.question): \(s > 0 ? "+" : "")\(s) min sleep that night" + (e.readiness.map { ", readiness \($0 > 0 ? "+" : "")\($0)" } ?? "")).font(.geist(13)).foregroundStyle(Color.soft) }
                    }
                    Text("Patterns from your own days, not proof.").font(.geist(11)).foregroundStyle(Color.faint)
                }
            }
        }
    }

    private var badgesCard: some View {
        Card {
            Eyebrow(text: "Badges", icon: "rosette")
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
    var body: some View {
        let day = Day.add(-1, to: Day.today)
        let entry = store.record(JournalDay.self, day) ?? JournalDay(date: day)
        Card(tint: .mind) {
            Eyebrow(text: "Yesterday, quickly", icon: "book.pages", color: .mind)
            ForEach(journalQuestions, id: \.self) { q in
                HStack {
                    Text(q).font(.geist(13.5))
                    Spacer()
                    ForEach([true, false], id: \.self) { yes in
                        let on = entry.answered.contains(q) && entry.yes.contains(q) == yes
                        Button(yes ? "Yes" : "No") {
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
    var body: some View {
        Card {
            Eyebrow(text: "How do you feel?", icon: "face.smiling")
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(0..<4, id: \.self) { r in
                    GridRow {
                        ForEach(0..<4, id: \.self) { c in
                            let energy = 1 - Double(r) / 1.5, pleasant = Double(c) / 1.5 - 1
                            Button {
                                store.save(MoodEntry(energy: energy, pleasant: pleasant, word: Self.words[r][c]))
                            } label: {
                                Text(Self.words[r][c]).font(.geist(11, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hue: c < 2 ? (r < 2 ? 0.0 : 0.62) : (r < 2 ? 0.12 : 0.38), saturation: 0.55, brightness: 0.35)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let last = store.all(MoodEntry.self).filter({ $0.date == Day.today }).max(by: { $0.minute < $1.minute }) {
                Text("Last: \(last.word.lowercased()) at \(clock(last.minute))." + strategy(last)).font(.geist(12.5)).foregroundStyle(Color.soft)
            }
        }
    }
    private func strategy(_ m: MoodEntry) -> String {
        if m.energy > 0 && m.pleasant < 0 { return " Try the physiological sigh: two breaths in, one long out." }
        if m.energy <= 0 && m.pleasant < 0 { return " A short walk outside lifts both energy and mood." }
        if m.energy <= 0 && m.pleasant >= 0 { return " Good moment for reading or an early night." }
        return " Use it: your best work fits here."
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
                Eyebrow(text: "Year in pixels", icon: "square.grid.4x3.fill")
                Spacer()
                Picker("", selection: $metric) { Text("Score").tag("score"); Text("Sleep").tag("sleep"); Text("Mood").tag("mood"); Text("Training").tag("training") }.pickerStyle(.menu).tint(.mint)
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
                Eyebrow(text: "Week of \(Day.date(week).formatted(.dateTime.day().month(.wide)))")
                ForEach(store.weekReview(week), id: \.0) { k, v in HStack { Text(k).font(.geist(14)); Spacer(); Text(v).font(.geist(14, .semibold)) } }
            }
            TimeAuditCard(week: week)
            Card(tint: .mint) {
                Eyebrow(text: "One thing to try next week", color: .mint)
                Text(store.challenge().text).font(.geist(15, .semibold))
            }
            let quotes = store.all(ReadingSession.self).filter { $0.date >= week && $0.quote != nil }
            if !quotes.isEmpty { Card { Eyebrow(text: "Quotes this week"); ForEach(quotes) { Text("“\($0.quote!)”").font(.serif(13)).italic() } } }
            let notes = (0..<7).compactMap { store.days[Day.add($0, to: week)]?.note }.filter { !$0.isEmpty }
            if !notes.isEmpty { Card { Eyebrow(text: "Your lines"); ForEach(notes, id: \.self) { Text($0).font(.geist(13)) } } }
        }
        .navigationTitle("Weekly review")
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
                TextField("Goal (Squat 120 kg, 24 books…)", text: $goal.title)
                Picker("Measured by", selection: $goal.metric) { Text("Lift (estimated 1RM)").tag("lift"); Text("Books this year").tag("books"); Text("Sleep hours average").tag("sleep"); Text("Bodyweight").tag("weight"); Text("Steps average").tag("steps") }
                if goal.metric == "lift" {
                    Picker("Exercise", selection: $goal.exerciseId) {
                        Text("Choose").tag(String?.none)
                        let unique = Dictionary(store.sessions().flatMap { $0.order }.map { ($0.exerciseId, $0.name) }, uniquingKeysWith: { a, _ in a })
                        ForEach(unique.sorted { $0.value < $1.value }, id: \.key) { Text($0.value).tag(Optional($0.key)) }
                    }
                }
                TextField("Target", value: $goal.target, format: .number).keyboardType(.decimalPad)
                Toggle("By a date", isOn: Binding(get: { goal.by != nil }, set: { goal.by = $0 ? Day.add(120, to: Day.today) : nil }))
                if goal.by != nil { DatePicker("By", selection: Binding(get: { Day.date(goal.by ?? Day.today) }, set: { goal.by = Day.key($0) }), displayedComponents: .date) }
            }
            .cadenceList()
            .navigationTitle("Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(goal); dismiss() }.disabled(goal.title.isEmpty) }
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
                TextField("The change (no caffeine after 14:00…)", text: $experiment.title)
                Picker("Watch", selection: $experiment.metric) { Text("Sleep").tag("sleep"); Text("Readiness").tag("readiness"); Text("HRV").tag("hrv"); Text("Resting HR").tag("rhr"); Text("Steps").tag("steps"); Text("Mood").tag("mood") }
                Stepper("For \(experiment.days) days", value: $experiment.days, in: 7...28, step: 7)
                DatePicker("Starting", selection: Binding(get: { Day.date(experiment.start) }, set: { experiment.start = Day.key($0) }), displayedComponents: .date)
            }
            .cadenceList()
            .navigationTitle("Experiment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Start") { store.save(experiment); dismiss() }.disabled(experiment.title.isEmpty) }
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
            Eyebrow(text: "Minute by minute", icon: "waveform.path.ecg.rectangle", color: .train)
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
                if !stress.isEmpty { Text("\(stress.count) stress moments (heart up, body still): " + stress.prefix(3).map { "\(clock($0.start))" }.joined(separator: ", ")).font(.geist(12.5)).foregroundStyle(Color.soft) }
                if let s = store.sessions(on: day).first(where: { $0.end != nil }), let hrr = store.heartRateRecovery(s, d) {
                    Text("Heart rate recovery after sets: −\(hrr) bpm in a minute" + (hrr <= 12 ? " (low: more easy cardio helps)" : " (good)")).font(.geist(12.5)).foregroundStyle(hrr <= 12 ? Color.warn : Color.good)
                }
                if let o = store.oxygenDips(d) {
                    Text(String(format: "Oxygen dips: %.1f an hour, lowest %.0f%%", o.perHour, o.lowest) + (o.perHour >= 5 ? ". If this stays high for weeks, mention it to a doctor." : "")).font(.geist(12.5)).foregroundStyle(o.perHour >= 5 ? Color.warn : Color.soft)
                }
                if !d.irn.isEmpty { Text("Irregular rhythm alerts on record: \(d.irn.count). The last: \(d.irn.max() ?? "").").font(.geist(12.5)).foregroundStyle(Color.warn) }
                else { Text("No irregular rhythm alerts.").font(.geist(12.5)).foregroundStyle(Color.soft) }
            } else {
                Text("Loading the day from your Air…").font(.geist(13)).foregroundStyle(Color.soft)
            }
        }
        .task { await intraday.load(day) }
    }
}

struct MoreSignalsCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Card {
            Eyebrow(text: "Rhythm and load", icon: "clock.badge.checkmark")
            if let c = store.chronotype() {
                HStack { Text("Chronotype").font(.geist(14)); Spacer(); Text(c.label).font(.geist(14, .semibold)) }
                Text("Mid-sleep \(clock((c.midFree + 1440) % 1440)) on free days, \(clock((c.midWork + 1440) % 1440)) on workdays: social jetlag \(duration(c.jetlag)).").font(.geist(12.5)).foregroundStyle(c.jetlag > 60 ? Color.warn : Color.soft)
            }
            if let t = store.trainingLoad() {
                HStack { Text("Training load").font(.geist(14)); Spacer(); Text(String(format: "%.2f", t.ratio)).font(.mono(14, .semibold)).foregroundStyle(t.ratio > 1.5 ? Color.warn : t.ratio < 0.8 ? Color.soft : Color.good) }
                Text(t.ratio > 1.5 ? "This week is much harder than your last month: ramping too fast raises injury risk." : t.ratio < 0.8 ? "Lighter than usual: fine for a deload week." : "In the sweet spot: enough to grow.").font(.geist(12.5)).foregroundStyle(Color.soft)
            }
            let steps = (0..<7).compactMap { store.health[Day.add(-$0, to: Day.today)]?.steps }
            if !steps.isEmpty {
                let avg = steps.reduce(0, +) / Double(steps.count)
                HStack { Text("Steps on the longevity curve").font(.geist(14)); Spacer(); Text(Int(avg).formatted()).font(.mono(14, .semibold)) }
                Bar(progress: min(1, avg / 10000), area: .fuel)
                Text(avg >= 8000 ? "Past the point where the benefit levels off (8,000–10,000 under 60, Lancet 2022)." : "\(Int(max(0, 8000 - avg)).formatted()) more a day reaches the part of the curve where most of the benefit is.").font(.geist(12)).foregroundStyle(Color.soft)
            }
        }
    }
}
