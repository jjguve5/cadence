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
}

struct SleepPlan {
    var need: Int // minutes asleep tonight
    var debt: Int // minutes over 14 nights
    var peak: Int // bedtimes, minutes after midnight (may be > 1440)
    var perform: Int
    var getBy: Int
    var windDown: Int
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
        ["idle": "Calm", "happy": "Happy", "proud": "Proud", "sleepy": "Sleepy", "sad": "A little sad", "celebrate": "Thrilled", "eat": "Waiting with the scoop", "levelup": "Growing", "tapped": "Surprised"][rawValue]!
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

    func readiness(on day: String = Day.today) -> Readiness? {
        guard let today = health[day] else { return nil }
        var parts: [ReadinessPart] = []
        var weighted = 0.0, weights = 0.0
        if let hrv = today.hrv, let b = baseline({ $0.hrv }, before: day) {
            let pct = (hrv / b.mean - 1) * 100
            let s = min(100, max(0, 60 + 18 * b.z(hrv)))
            parts.append(ReadinessPart(name: "HRV", value: "\(Int(hrv)) ms", detail: String(format: "%+.0f%% vs your 14-day average", pct), score: s, good: pct >= -5))
            weighted += s * 0.4; weights += 0.4
        }
        if let rhr = today.rhr, let b = baseline({ $0.rhr }, before: day) {
            let diff = rhr - b.mean
            let s = min(100, max(0, 60 - 18 * b.z(rhr)))
            parts.append(ReadinessPart(name: "Resting HR", value: "\(Int(rhr)) bpm", detail: String(format: "%+.0f vs average", diff), score: s, good: diff <= 2))
            weighted += s * 0.3; weights += 0.3
        }
        if let sleep = today.sleep {
            let ratio = Double(sleep.asleep) / Double(max(1, profile.sleepNeed))
            let s = min(100, max(0, 100 * (ratio - 0.55) / 0.45))
            parts.append(ReadinessPart(name: "Sleep", value: duration(sleep.asleep), detail: "\(Int(ratio * 100))% of your \(duration(profile.sleepNeed)) need", score: s, good: ratio >= 0.9))
            weighted += s * 0.3; weights += 0.3
        }
        if let t = today.temp, abs(t) >= 0.5 {
            parts.append(ReadinessPart(name: "Skin temp", value: String(format: "%+.1f°", t), detail: "Off your baseline: a sign of strain or illness", score: 40, good: false))
            weighted -= 6 * weights
        }
        guard weights > 0 else { return nil }
        let score = Int(min(100, max(1, weighted / weights + profile.readinessOffset)).rounded())
        let label = score >= 80 ? "Primed" : score >= 65 ? "Good to go" : score >= 50 ? "Steady" : score >= 35 ? "Go easy" : "Rest day"
        let summary = parts.map { "\($0.name) \($0.value)" }.joined(separator: " · ")
        return Readiness(score: score, label: label, parts: parts, summary: summary)
    }

    // MARK: Sleep

    func sleepPlan(for day: String = Day.today) -> SleepPlan {
        let nights = (0..<14).compactMap { health[Day.add(-$0, to: day)]?.sleep?.asleep }
        let napMinutes = health[day]?.naps?.map(\.asleep).reduce(0, +) ?? 0
        let debt = max(0, nights.map { profile.sleepNeed - $0 }.reduce(0, +))
        // Pay back in 15-minute steps, a little each night
        let repay = debt > 180 ? 30 : debt > 60 ? 15 : 0
        let need = profile.sleepNeed + repay - min(napMinutes, 60)
        let wake = profile.wakeMinute + 1440
        let fallAsleep = 15
        let perform = wake - need - fallAsleep
        return SleepPlan(need: need, debt: debt, peak: perform - 30, perform: perform, getBy: perform + 60, windDown: perform - profile.windDownLead)
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
        guard !profile.on("fuel") else { return scoreWithFuel(on: day) }
        var got = 0.0
        let due = self.due(on: day)
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
        let due = self.due(on: day)
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
        let dueToday = self.due(on: today)
        let allDone = !dueToday.isEmpty && dueToday.allSatisfy { status($0, on: today).map { $0 != .skipped } ?? false }
        if minute < 11 * 60, let s = health[today]?.sleep, Double(s.asleep) < Double(profile.sleepNeed) * 0.8 { return .sleepy }
        if minute >= min(plan.windDown, 1439) || minute < 4 * 60 { return openMustDos().isEmpty ? .sleepy : .eat }
        if !openMustDos().isEmpty && minute >= (openMustDos().first?.schedule.minute ?? 0) { return .eat }
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
            out.append(MoodReason(text: "\(p.title) \(w.done)/\(w.total) this week", good: w.done >= w.due - (status(p) == nil ? 1 : 0)))
        }
        if let r = readiness() { out.append(MoodReason(text: "Readiness \(r.score), \(r.label.lowercased())", good: r.score >= 60)) }
        if let s = health[Day.today]?.sleep {
            let short = s.asleep < profile.sleepNeed - 30
            out.append(MoodReason(text: "Sleep \(duration(s.asleep))\(short ? ", a bit short" : "")", good: !short))
        }
        if let steps = health[Day.today]?.steps { out.append(MoodReason(text: "\(Int(steps).formatted()) steps", good: steps >= Double(profile.stepGoal))) }
        return out
    }

    func pipLine() -> String {
        let minute = Day.minuteOfDay()
        let open = openMustDos()
        if let m = open.first, minute >= m.schedule.minute { return "\(m.title) first, then we rest." }
        switch pipMood() {
        case .sleepy: return minute < 12 * 60 ? "Short night. Let's keep today gentle." : "Wind-down time. Screens away, book out."
        case .celebrate: return "Everything done. Proud of you."
        case .sad: return "Yesterday slipped. One small thing today and we're back."
        case .happy: return "Good day so far. Keep it rolling."
        default:
            let next = due().first { status($0) == nil && $0.schedule.minute >= minute }
            return next.map { "Next: \($0.title.lowercased()) at \($0.timeLabel)." } ?? "Morning! Let's make today count."
        }
    }

    /// Promises that tick themselves once the Air syncs: a steps goal, a bedtime
    func autoComplete() {
        let today = Day.today
        for p in due(on: today) where status(p, on: today) == nil {
            let t = p.title.lowercased()
            if t.contains("steps") || t.contains("walk"), let steps = health[today]?.steps, steps >= Double(profile.stepGoal) { log(p, on: today, .done) }
        }
        let yesterday = Day.add(-1, to: today)
        for p in due(on: yesterday) where status(p, on: yesterday) == nil {
            let t = p.title.lowercased()
            guard t.contains("bed") || t.contains("lights out"), let s = health[today]?.sleep else { continue }
            let start = Day.minuteOfDay(s.startDate), planned = p.schedule.minute
            let a = start < 12 * 60 ? start + 1440 : start, b = planned < 12 * 60 ? planned + 1440 : planned
            if a <= b + 15 { log(p, on: yesterday, .done) }
        }
    }

    // MARK: Brief and check-ins

    func briefLines() -> [MoodReason] {
        var out: [MoodReason] = []
        let plan = sleepPlan()
        if shortNightsInARow() >= 3 { out.append(MoodReason(text: "Three short nights in a row. Tonight: lights out by \(clock(plan.perform)).", good: false)) }
        else if plan.debt > 120 { out.append(MoodReason(text: "Sleep debt \(duration(plan.debt)). Bed 15 min earlier tonight pays it back.", good: false)) }
        if let b = device?.battery, b <= 20 { out.append(MoodReason(text: "Air battery \(b)%: charge it during your shower.", good: false)) }
        if let r = readiness(), r.score < 45 { out.append(MoodReason(text: "Readiness is low: lighter training and an early night.", good: false)) }
        if let t = health[Day.today]?.temp, t >= 0.8, let rhr = health[Day.today]?.rhr, let b = baseline({ $0.rhr }), rhr > b.mean + 4 {
            out.append(MoodReason(text: "Temperature and resting HR are both up: you may be getting sick. Take it easy.", good: false))
        }
        for m in openMustDos() { out.append(MoodReason(text: "\(m.title) is a must-do today, at \(m.timeLabel).", good: nil)) }
        return out
    }
}
