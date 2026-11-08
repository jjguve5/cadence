// The numbers Cadence shows, all as plain rules you can read: readiness against your own 14-day baseline, sleep
// need and debt, the daily score, points and levels, and Pip's mood.
import Foundation

struct Baseline {
    var mean: Double
    var sd: Double
    var count: Int
    func z(_ v: Double) -> Double { sd > 0.0001 ? (v - mean) / sd : 0 }
}

struct ReadinessPart: Identifiable {
    var id: String { name }
    var name: String
    var value: String
    var detail: String
    var score: Double
    var good: Bool
}

struct Readiness {
    var score: Int
    var label: String
    var parts: [ReadinessPart]
    var summary: String
    var confidence: Confidence = .moderate
    var notes: [String] = []
}

struct SleepPlan {
    var need: Int // minutes asleep tonight
    var debt: Int // minutes over 14 nights
    var peak: Int // bedtimes, minutes after midnight (may be > 1440)
    var perform: Int
    var getBy: Int
    var windDown: Int
    var after: Busy? = nil // the trip or event that pushed the evening later
}

enum PipMood: String {
    case idle, happy, proud, sleepy, sad, celebrate, eat, levelup, tapped
    var head: String {
        switch self {
        case .idle: return "pip-neutral"
        case .happy, .celebrate: return "pip-happy"
        case .proud: return "pip-proud"
        case .sleepy: return "pip-sleepy"
        case .sad: return "pip-sad"
        case .eat: return "pip-eating"
        case .levelup: return "pip-levelup"
        case .tapped: return "pip-surprised"
        }
    }
    var label: String {
        ["idle": "Calmo", "happy": "Contente", "proud": "Orgulhoso", "sleepy": "Com sono", "sad": "Um pouco triste", "celebrate": "Radiante", "eat": "À espera com a colher", "levelup": "A crescer", "tapped": "Surpreendido"][rawValue]!
    }
}

struct MoodReason: Identifiable {
    var id: String { text }
    var text: String
    var good: Bool?
}

@MainActor
extension Store {
    // MARK: Baselines and readiness

    func healthDays(last n: Int, before day: String = Day.today) -> [HealthDay] {
        (1...n).compactMap { health[Day.add(-$0, to: day)] }
    }

    func baseline(_ value: (HealthDay) -> Double?, before day: String = Day.today) -> Baseline? {
        let values = healthDays(last: 14, before: day).compactMap(value)
        guard values.count >= 4 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return Baseline(mean: mean, sd: max(sqrt(variance), mean * 0.04), count: values.count)
    }

    /// Contextual guidance from the engine: robust 28-day baselines, blended with yesterday, with its confidence
    func readiness(on day: String = Day.today) -> Readiness? {
        if let cached = readinessCache[day] { return cached }
        let r = workOutReadiness(on: day)
        readinessCache[day] = .some(r)
        return r
    }

    private func workOutReadiness(on day: String) -> Readiness? {
        guard let r = readinessResult(on: day), let today = health[day] else { return nil }
        var parts: [ReadinessPart] = []
        if let hrv = today.hrv, let z = r.hrvZ, let b = robust({ $0.hrv }, before: day) {
            let pct = (hrv / b.median - 1) * 100
            parts.append(ReadinessPart(name: "VFC", value: "\(Int(hrv)) ms", detail: String(format: "%+.0f%% face ao habitual (mediana de %d dias)", pct, b.n), score: min(100, max(0, 62 + 16 * z)), good: z > -1))
        }
        if let rhr = today.rhr, let z = r.rhrZ, let b = robust({ $0.rhr }, before: day) {
            parts.append(ReadinessPart(name: "FC em repouso", value: "\(Int(rhr)) bpm", detail: String(format: "%+.0f face ao habitual", rhr - b.median), score: min(100, max(0, 62 - 16 * z)), good: z < 1))
        }
        if let s = today.sleep, let ratio = r.sleepRatio {
            parts.append(ReadinessPart(name: "Sono", value: duration(s.asleep), detail: "\(Int(ratio * 100))% das \(duration(profile.sleepNeed)) de que precisas", score: min(100, max(0, 100 * (ratio - 0.55) / 0.45)), good: ratio >= 0.9))
        }
        if let t = today.temp, abs(t) >= 0.5 {
            parts.append(ReadinessPart(name: "Temperatura da pele", value: String(format: "%+.1f°", t), detail: "Fora da tua base: álcool, um quarto quente, stress ou uma constipação a caminho podem causar isto", score: 50, good: false))
        }
        var notes = r.notes
        let week = (0..<7).compactMap { health[Day.add(-$0, to: day)]?.hrv }
        if week.count >= 5, let b = robust({ $0.hrv }, before: day), Engine.sustainedDecline(week: week, baseline: b) { notes.append("A VFC esteve abaixo do habitual na maior parte da semana") }
        let score = r.score
        let label = score >= 80 ? "Em plena forma" : score >= 65 ? "Tudo a postos" : score >= 50 ? "Estável" : score >= 35 ? "Com calma" : "Poupa-te"
        return Readiness(score: score, label: label, parts: parts, summary: parts.map { "\($0.name) \($0.value)" }.joined(separator: " · "), confidence: r.confidence, notes: notes)
    }

    // MARK: Sleep

    func sleepPlan(for day: String = Day.today) -> SleepPlan {
        if let cached = planCache[day] { return cached }
        let plan = workOutSleepPlan(for: day)
        planCache[day] = plan
        return plan
    }

    private func workOutSleepPlan(for day: String) -> SleepPlan {
        let nights = (0..<7).compactMap { health[Day.add(-$0, to: day)]?.sleep?.asleep }
        let napMinutes = health[day]?.naps?.map(\.asleep).reduce(0, +) ?? 0
        let debt = Engine.sleepDebt(nights: nights, need: profile.sleepNeed)
        // Pay back in 15-minute steps, a little each night
        let repay = debt > 180 ? 30 : debt > 60 ? 15 : 0
        let need = profile.sleepNeed + repay - min(napMinutes, 60)
        let wake = profile.wakeMinute + 1440
        let fallAsleep = 15
        let shift = records("bedshift")[day].flatMap { v -> Int? in if case .number(let n) = v { return Int(n) }; return nil } ?? 0 // "lights out earlier tonight"
        let perform = wake - need - fallAsleep - shift
        let plan = SleepPlan(need: need, debt: debt, peak: perform - 30, perform: perform, getBy: perform + 60, windDown: perform - profile.windDownLead)
        // Still out at wind-down: the evening starts 15 minutes after you're back, and the night is that much shorter
        guard let late = Engine.eveningAfter(windDown: plan.windDown, perform: perform, busy: busy(on: day)) else { return plan }
        let windDown = late.end + 15, lightsOut = windDown + profile.windDownLead
        return SleepPlan(need: min(need, wake - lightsOut - fallAsleep), debt: debt, peak: lightsOut, perform: lightsOut, getBy: lightsOut + 60, windDown: windDown, after: late)
    }

    func shortNightsInARow() -> Int {
        var n = 0
        for i in 0..<7 {
            guard let s = health[Day.add(-i, to: Day.today)]?.sleep, Double(s.asleep) < Double(profile.sleepNeed) * 0.85 else { break }
            n += 1
        }
        return n
    }

    // MARK: Score, points, level

    /// 0–100 from what's switched on: promises, sleep, movement, protein and water, closing the day. Areas you
    /// haven't switched on don't count, so adding one never makes old days look worse.
    func score(on day: String = Day.today) -> Int {
        if isMinimumDay(day) { return minimumScore(on: day) }
        guard !profile.on("fuel") else { return scoreWithFuel(on: day) }
        var got = 0.0
        let due = self.dueCounted(on: day) // «Não se aplica» leaves both sides of the count
        if due.isEmpty { got += 40 } else {
            let done = due.filter { status($0, on: day).map { $0 != .skipped } ?? false }.count
            let tiny = due.filter { status($0, on: day) == .tiny }.count
            got += 40 * (Double(done) - Double(tiny) * 0.4) / Double(due.count)
        }
        if let s = health[day]?.sleep { got += 25 * min(1, Double(s.asleep) / Double(profile.sleepNeed)) }
        if let steps = health[day]?.steps { got += 20 * min(1, steps / Double(profile.stepGoal)) }
        if self.day(day).closedAt != nil { got += 15 }
        return Int(got.rounded())
    }

    private func scoreWithFuel(on day: String) -> Int {
        var got = 0.0
        let due = self.dueCounted(on: day) // «Não se aplica» leaves both sides of the count
        if due.isEmpty { got += 30 } else {
            let done = due.filter { status($0, on: day).map { $0 != .skipped } ?? false }.count
            let tiny = due.filter { status($0, on: day) == .tiny }.count
            got += 30 * (Double(done) - Double(tiny) * 0.4) / Double(due.count)
        }
        if let s = health[day]?.sleep { got += 20 * min(1, Double(s.asleep) / Double(profile.sleepNeed)) }
        if let steps = health[day]?.steps { got += 15 * min(1, steps / Double(profile.stepGoal)) }
        let f = fuel(on: day)
        got += 10 * min(1, f.protein / profile.proteinTarget)
        got += 10 * min(1, f.water / max(1, waterGoal(on: day)))
        if self.day(day).closedAt != nil { got += 15 }
        return Int(got.rounded())
    }

    var totalPoints: Int {
        let closed = days.values.compactMap(\.points).reduce(0, +)
        return closed + (self.day().closedAt == nil ? score() : 0)
    }

    static func levelFloor(_ level: Int) -> Int { 50 * level * (level - 1) }

    var level: (level: Int, into: Int, span: Int, next: Int) {
        let pts = totalPoints
        var l = 1
        while Store.levelFloor(l + 1) <= pts { l += 1 }
        let floor = Store.levelFloor(l), next = Store.levelFloor(l + 1)
        return (l, pts - floor, next - floor, next)
    }

    // MARK: Pip

    func pipMood(now: Date = Date()) -> PipMood {
        let minute = Day.minuteOfDay(now)
        let plan = sleepPlan()
        let today = Day.today
        let dueToday = self.dueCounted(on: today) // «Não se aplica» isn't a miss and isn't something left to do
        let allDone = !dueToday.isEmpty && dueToday.allSatisfy { status($0, on: today).map { $0 != .skipped } ?? false }
        if minute < 11 * 60, let s = health[today]?.sleep, Double(s.asleep) < Double(profile.sleepNeed) * 0.8 { return .sleepy }
        if minute >= min(plan.windDown, 1439) || minute < 4 * 60 { return openMustDos().isEmpty ? .sleepy : .eat }
        if let m = openMustDos().first, minute >= time(of: m) { return .eat }
        if allDone { return .celebrate }
        let yesterday = Day.add(-1, to: today)
        if !due(on: yesterday).filter({ $0.kind == .mustDo && status($0, on: yesterday) == nil }).isEmpty { return .sad }
        if score() >= 60 { return .happy }
        return .idle
    }

    func pipReasons() -> [MoodReason] {
        var out: [MoodReason] = []
        for p in due().filter({ $0.kind == .mustDo }) {
            let w = week(p)
            out.append(MoodReason(text: "\(p.title) \(w.done)/\(w.total) esta semana", good: w.done >= w.due - (status(p) == nil ? 1 : 0)))
        }
        if let r = readiness() { out.append(MoodReason(text: "Prontidão \(r.score), \(r.label.lowercased())", good: r.score >= 60)) }
        if let s = health[Day.today]?.sleep {
            let short = s.asleep < profile.sleepNeed - 30
            out.append(MoodReason(text: "Sono \(duration(s.asleep))\(short ? ", um pouco curto" : "")", good: !short))
        }
        if let steps = health[Day.today]?.steps { out.append(MoodReason(text: "\(Int(steps).formatted()) passos", good: steps >= Double(profile.stepGoal))) }
        return out
    }

    func pipLine() -> String {
        let minute = Day.minuteOfDay()
        let open = openMustDos()
        if activeFocus != nil { return Pip.stable(.focusing, store: self) }
        if isMinimumDay() {
            if let first = open.first { return Pip.stable(.minimumDayOpen, store: self, key: first.id, what: first.title) }
            return Pip.stable(.minimumDayDone, store: self)
        }
        // Effort and consistency, noticed: one line, chosen by day so it doesn't repeat
        var noticed: [(situation: PipSituation, lead: String?, key: String)] = []
        if let r = readiness(), r.score < 50, !sessions(on: Day.today).filter({ $0.end != nil }).isEmpty { noticed.append((.trainedLowDay, nil, "")) }
        for p in due().filter({ $0.kind == .mustDo }) {
            let w = week(p)
            if w.due >= 4, w.done == w.due, status(p) != nil { noticed.append((.streak, "\(p.title) \(w.done)/\(w.total) esta semana.", p.id)) }
        }
        if shortNightsInARow() == 0, let s = health[Day.today]?.sleep, s.asleep >= profile.sleepNeed - 15, minute < 12 * 60 { noticed.append((.sleepGood, nil, "")) }
        if !noticed.isEmpty, minute % 3 == 0 || noticed.count == 1 {
            let n = noticed[(Day.between("2026-01-01", Day.today)) % noticed.count]
            return Pip.stable(n.situation, store: self, key: n.key, lead: n.lead)
        }
        if let m = open.first, minute >= time(of: m) { return Pip.stable(.mustDoOpen, store: self, key: m.id, what: m.title) }
        switch pipMood() {
        case .sleepy: return Pip.stable(minute < 12 * 60 ? .sleepShort : .windDown, store: self)
        case .celebrate: return Pip.stable(.promisesDone, store: self)
        case .sad: return Pip.stable(.comeback, store: self)
        case .happy: return Pip.stable(pipTopic(minute: minute) ?? .goodDay, store: self)
        default:
            let next = due().first { status($0) == nil && time(of: $0) >= minute }
            let topic = pipTopic(minute: minute)
            // What's next stays the main thing; every other hour Pip mentions what it has noticed instead
            if let next, topic == nil || (minute / 60) % 2 == 1 {
                return Pip.stable(.generic, store: self, key: "next", lead: "A seguir: \(next.title.lowercased()) às \(timeLabel(next)).")
            }
            return Pip.stable(topic ?? (minute < 12 * 60 ? .morning : .generic), store: self)
        }
    }

    /// Something from today worth mentioning when nothing more pressing is going on
    private func pipTopic(minute: Int) -> PipSituation? {
        let today = Day.today
        if minute < 14 * 60, let r = readiness() {
            if r.score < 50 { return .recoveryLow }
            if r.score >= 80 { return .recoveryHigh }
        }
        if !sessions(on: today).filter({ $0.end != nil }).isEmpty { return .trainingDone }
        let trainingWords = ["train", "gym", "workout"]
        if due().contains(where: { p in status(p) == .skipped && trainingWords.contains { p.title.lowercased().contains($0) } }) { return .trainingSkipped }
        if profile.on("fuel") {
            let f = fuel()
            if f.water + 600 < waterPace() { return .waterBehind }
            if minute >= 18 * 60, f.protein < profile.proteinTarget * 0.65 { return .proteinBehind }
        }
        if minute >= 18 * 60, !showerTimes.isEmpty, showerPlan(for: today) != nil { return .shower }
        if minute >= 20 * 60 {
            if readingMinutes(on: today) == 0, all(Book.self).contains(where: { $0.finished == nil }) { return .reading }
            if day().closedAt == nil { return .eveningClose }
        }
        return minute < 11 * 60 ? .morning : nil
    }

    /// Promises that tick themselves once the Air syncs: a steps goal, a bedtime. Each one is saved as imported from
    /// the health source (PromiseLog.source), not as answered by you. Titles match by the English words the seeded habits
    /// use (they stay in English, decision D10); Portuguese words were not added: «deitar» or «luzes» also name unrelated
    /// habits, and a wrong tick from the band would come back on every refresh.
    func autoComplete() {
        let today = Day.today
        let source = profile.healthSource
        for p in due(on: today) where status(p, on: today) == nil {
            let t = p.title.lowercased()
            if t.contains("steps") || t.contains("walk"), let steps = health[today]?.steps, steps >= Double(profile.stepGoal) { log(p, on: today, .done, source: source) }
        }
        let yesterday = Day.add(-1, to: today)
        for p in due(on: yesterday) where status(p, on: yesterday) == nil {
            let t = p.title.lowercased()
            guard t.contains("bed") || t.contains("lights out"), let s = health[today]?.sleep else { continue }
            let start = Day.minuteOfDay(s.startDate), planned = time(of: p, on: yesterday)
            let a = start < 12 * 60 ? start + 1440 : start, b = planned < 12 * 60 ? planned + 1440 : planned
            if a <= b + 15 { log(p, on: yesterday, .done, source: source) }
        }
    }

    /// When a promise happens on a day: its anchor (wake, wind-down, lights out), its weekend time, or its clock time
    func time(of p: PromiseItem, on day: String = Day.today) -> Int {
        let s = p.schedule
        if let a = s.anchor {
            let plan = sleepPlan(for: day)
            let base = a == "wake" ? profile.wakeMinute : a == "lightsOut" ? plan.perform : plan.windDown
            return Engine.outside(base + (s.offset ?? 0), busy: busy(on: day))
        }
        let wd = Day.weekday(day)
        if wd == 1 || wd == 7, let w = s.weekendMinute { return Engine.outside(w, busy: busy(on: day)) }
        return Engine.outside(s.minute, busy: busy(on: day))
    }

    func timeLabel(_ p: PromiseItem, on day: String = Day.today) -> String { clock(time(of: p, on: day)) }

    /// Promises seeded with fixed evening times now follow wind-down and lights out
    func migrateAnchors() {
        guard !UserDefaults.standard.bool(forKey: "anchors1") else { return }
        UserDefaults.standard.set(true, forKey: "anchors1")
        for var p in promises.values where p.schedule.anchor == nil {
            let t = p.title.lowercased()
            if t.hasPrefix("read") && p.schedule.minute >= 22 * 60 { p.schedule.anchor = "windDown"; p.schedule.offset = 0; save(p) }
            else if t.contains("brush") && p.schedule.minute >= 22 * 60 { p.schedule.anchor = "lightsOut"; p.schedule.offset = -10; save(p) }
        }
    }

    /// Brushing at the start of wind-down, then reading until lights out; brushing after waking too
    func migrateEvenings() {
        guard !UserDefaults.standard.bool(forKey: "evenings2") else { return }
        UserDefaults.standard.set(true, forKey: "evenings2")
        for var p in promises.values {
            let t = p.title.lowercased()
            if t.contains("brush") && (t.contains("night") || p.schedule.anchor == "lightsOut") { p.schedule.anchor = "windDown"; p.schedule.offset = 0; save(p) }
            else if t.hasPrefix("read") && p.schedule.anchor == "windDown" { p.schedule.offset = 5; save(p) }
        }
        if !promises.values.contains(where: { $0.title.lowercased().contains("brush") && $0.schedule.anchor == "wake" }) {
            save(PromiseItem(title: "Brush teeth, morning", icon: "mouth.fill", schedule: Schedule(rule: .daily, minute: 7 * 60 + 30, anchor: "wake", offset: 10)))
        }
        if profile.windDownLead == 30 { update { $0.windDownLead = 35 } } // 5 minutes brushing + 30 reading
    }

    /// The training plan you sent: four days, Monday and Friday swapped
    func seedPlan() {
        guard !UserDefaults.standard.bool(forKey: "plan1") else { return }
        UserDefaults.standard.set(true, forKey: "plan1")
        func t(_ id: String, _ name: String, _ sets: Int = 3, _ lo: Int = 8, _ hi: Int = 12, _ rest: Int = 90, _ inc: Double = 2.5) -> TemplateExercise {
            TemplateExercise(exerciseId: id, name: name, sets: sets, repLow: lo, repHigh: hi, rest: rest, increment: inc)
        }
        let plan = [
            WorkoutTemplate(name: "Segunda · peito, costas, braços", exercises: [
                t("incline-bench-press", "Incline Bench Press", 3, 6, 10, 150), t("pec-deck", "Pec Deck Fly", 3, 10, 15), t("lat-pulldown", "Lat Pulldown", 4, 8, 12, 120),
                t("zottman-curl", "Zottman Hammer Curl", 3, 10, 12, 75, 1), t("cable-overhead-tricep-extension", "Cable Overhead Extension", 3, 10, 15, 75),
                t("seated-dumbbell-lateral-raise", "Front & Back Seated DB Lateral Raises", 3, 12, 15, 60, 1),
            ], weekdays: [2], minutes: 70),
            WorkoutTemplate(name: "Quarta · pernas e core, baixa intensidade", exercises: [
                t("squat", "High Bar Squat", 3, 6, 10, 150), t("db-shrug", "Shrugs", 3, 10, 15, 75), t("reverse-curl", "Reverse Grip Curl", 3, 10, 15, 60, 1),
                t("dragon-flag", "Dragon Flags", 3, 5, 10, 90, 0), t("treadmill-running", "Corrida e caminhada, ritmo baixo e alto, 20–30 min", 1, 1, 1, 0, 0),
            ], weekdays: [4], minutes: 70),
            WorkoutTemplate(name: "Sexta · costas, peito, braços", exercises: [
                t("pull-up", "Pull Ups", 3, 6, 10, 150, 1.25), t("chest-supported-db-row", "Chest Supported Row", 3, 8, 12, 120), t("incline-db-press", "Inclined DB Press", 3, 8, 12, 120, 2),
                t("tricep-pushdown", "Cable Press Down", 3, 10, 15, 75), t("cable-curl", "Cable Curl / Face-Away Cable Curl", 3, 10, 15, 75),
                t("cable-lateral-raise", "Cable Lateral Raises", 3, 12, 15, 60, 1),
            ], weekdays: [6], minutes: 70),
            WorkoutTemplate(name: "Sábado · pernas", exercises: [
                t("treadmill-running", "Corrida, 7 min de aquecimento", 1, 1, 1, 0, 0), t("stiff-leg-deadlift", "DB Stiff-Legged Deadlift (glute bias)", 3, 8, 12, 120),
                t("leg-extension", "Leg Extensions", 4, 10, 15, 75), t("standing-calf-raise", "Standing Calf Raise", 3, 10, 15, 60),
                t("leg-curl", "Hamstring Curl", 3, 10, 15, 75), t("hip-abduction", "Abductors", 2, 12, 20, 60), t("hip-adduction", "Adductors", 2, 12, 20, 60),
            ], weekdays: [7], minutes: 75),
        ]
        // The starter templates go unless you've trained with them
        let used = Set(sessions().compactMap(\.templateId))
        for old in templates where ["Legs A", "Push A", "Pull A"].contains(old.name) && !used.contains(old.id) { remove(old) }
        for p in plan { save(p) }
    }

    var todaysTemplate: WorkoutTemplate? { templates.first { $0.weekdays.contains(Day.weekday(Day.today)) } }

    /// Feeds the widgets; does nothing when the App Group isn't available (free signing may not allow it)
    func writeSnapshot() {
        let minute = Day.minuteOfDay()
        let next = due().first { status($0) == nil && time(of: $0) + 60 >= minute }
        let f = fuel()
        let r = readiness()
        let s = Snapshot(score: score(), readiness: r?.score, readinessLabel: r?.label, next: next?.title, nextTime: next.map { timeLabel($0) },
                         mustDos: openMustDos().map(\.title), water: f.water, waterGoal: waterGoal(), protein: f.protein, proteinGoal: profile.proteinTarget,
                         mood: pipMood().head, level: level.level, updated: Date())
        if SharedBox.write(s) { WidgetReload.now() }
    }

    var widgetsAvailable: Bool { SharedBox.container() != nil }

    // MARK: Brief and check-ins

    func briefLines() -> [MoodReason] {
        var out: [MoodReason] = []
        let plan = sleepPlan()
        if shortNightsInARow() >= 3 { out.append(MoodReason(text: "Três noites curtas seguidas. Esta noite: apagar as luzes até às \(clock(plan.perform)).", good: false)) }
        else if plan.debt > 120 { out.append(MoodReason(text: "Dívida de sono de \(duration(plan.debt)). Deitar 15 min mais cedo esta noite ajuda a recuperá-la.", good: false)) }
        if let b = device?.battery, b <= 20 { out.append(MoodReason(text: "Bateria do Air a \(b)%: carrega-o durante o duche.", good: false)) }
        if let r = readiness(), r.score < 45 { out.append(MoodReason(text: "Prontidão baixa: treino mais leve e deitar cedo.", good: false)) }
        if let t = health[Day.today]?.temp, t >= 0.8, let rhr = health[Day.today]?.rhr, let b = baseline({ $0.rhr }), rhr > b.mean + 4 {
            out.append(MoodReason(text: "A temperatura e a FC em repouso estão ambas acima do normal: podes estar a ficar doente. Vai com calma.", good: false))
        }
        for m in openMustDos() { out.append(MoodReason(text: "\(m.title): essencial hoje, às \(timeLabel(m)).", good: nil)) }
        return out
    }
}
