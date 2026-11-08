// Growth and motivation: the morning journal and what affects you, goals with projected dates, two-week
// experiments, the weekly review, mood, Cadence age, levers for a better day, the weekly challenge and badges.
// Plus the minute-by-minute signals: high and low heart rate, heart rate recovery, oxygen dips, stress moments,
// chronotype and social jetlag, training load.
import Foundation

struct JournalDay: Record, Equatable {
    static let kind = "journal"
    var id: String { date }
    var date = Day.today
    var yes: [String] = []
    var answered: [String] = []
    var text = ""
}

/// The journal questions' keys: answers are saved under these exact texts (JournalDay.yes and .answered), so they never
/// change, not even with a translation. What a question says on screen is journalText(_:).
let journalQuestions = ["Caffeine after 14:00", "Alcohol", "Screens in bed", "Late dinner", "Stressful day", "Outside in the morning", "Trained", "Hot or noisy room"]

/// What each journal question says on screen, by key. Phase 2.3 translates these texts; the keys stay.
let journalQuestionText: [String: String] = [
    "Caffeine after 14:00": "Cafeína depois das 14:00",
    "Alcohol": "Álcool",
    "Screens in bed": "Ecrãs na cama",
    "Late dinner": "Jantar tarde",
    "Stressful day": "Dia stressante",
    "Outside in the morning": "Ao ar livre de manhã",
    "Trained": "Treino",
    "Hot or noisy room": "Quarto quente ou barulhento",
]

/// The text shown for a journal question's key (the key itself if it has none)
func journalText(_ key: String) -> String { journalQuestionText[key] ?? key }

struct MoodEntry: Record, Equatable {
    static let kind = "mood"
    var id = UUID().uuidString
    var date = Day.today
    var minute = Day.minuteOfDay()
    var energy: Double // -1 … 1
    var pleasant: Double // -1 … 1
    var word: String
}

struct LifeGoal: Record, Equatable {
    static let kind = "lifegoal"
    var id = UUID().uuidString
    var title: String
    var metric: String // lift, books, sleep, weight, steps
    var target: Double
    var exerciseId: String?
    var by: String?
}

struct Experiment: Record, Equatable {
    static let kind = "experiment"
    var id = UUID().uuidString
    var title: String
    var metric = "sleep" // sleep, readiness, hrv, rhr, steps, mood
    var start = Day.today
    var days = 14
}

struct WeeklyChallenge: Record, Equatable {
    static let kind = "challenge"
    var id: String { week }
    var week: String
    var text: String
    var area: String
    var done = false
}

struct Intraday: Codable, Equatable {
    var date: String
    var hr: [String: Double]
    var steps: [String: Double]
    var spo2: [String: Double]
    var irn: [String]
}

@MainActor
final class IntradayStore: ObservableObject {
    static let shared = IntradayStore()
    @Published private(set) var days: [String: Intraday] = [:]
    private let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

    func day(_ date: String) -> Intraday? {
        if let d = days[date] { return d }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("intraday-\(date).json")), let d = try? JSONDecoder().decode(Intraday.self, from: data) { days[date] = d; return d }
        return nil
    }

    func load(_ date: String, force: Bool = false) async {
        if !force, date < Day.add(-1, to: Day.today), day(date) != nil { return }
        guard let req = Store.shared.request("health.php?intraday=\(date)"), let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let d = try? JSONDecoder().decode(Intraday.self, from: data) else { return }
        days[date] = d
        try? data.write(to: dir.appendingPathComponent("intraday-\(date).json"), options: .atomic)
    }
}

@MainActor
extension Store {
    // MARK: Journal and levers

    /// For each yes/no habit: the next night's sleep and the next morning's readiness with it against without
    func journalEffects() -> [(question: String, sleep: Int?, readiness: Int?, n: Int)] {
        let entries = all(JournalDay.self)
        return journalQuestions.compactMap { q -> (question: String, sleep: Int?, readiness: Int?, n: Int)? in
            var withS: [Int] = [], withoutS: [Int] = [], withR: [Int] = [], withoutR: [Int] = []
            for e in entries where e.answered.contains(q) {
                let next = Day.add(1, to: e.date)
                let yes = e.yes.contains(q)
                if let s = health[next]?.sleep?.asleep { if yes { withS.append(s) } else { withoutS.append(s) } }
                if let r = readiness(on: next)?.score { if yes { withR.append(r) } else { withoutR.append(r) } }
            }
            guard withS.count >= 5, withoutS.count >= 5 else { return nil }
            let avg = { (a: [Int]) in a.isEmpty ? 0 : a.reduce(0, +) / a.count }
            let r = withR.count >= 5 && withoutR.count >= 5 ? avg(withR) - avg(withoutR) : nil
            return (question: q, sleep: avg(withS) - avg(withoutS), readiness: r, n: withS.count)
        }
    }

    /// What most often comes before your best days (top quarter by score), only with enough data
    func levers() -> [String] {
        let scored = days.values.compactMap { d in d.score.map { (d.date, $0) } }
        guard scored.count >= 20 else { return [] }
        let cut = scored.map(\.1).sorted()[scored.count * 3 / 4]
        let best = Set(scored.filter { $0.1 >= cut }.map { Day.add(-1, to: $0.0) })
        var out: [(String, Double)] = []
        for q in journalQuestions {
            let answered = all(JournalDay.self).filter { $0.answered.contains(q) }
            guard answered.count >= 10 else { continue }
            let before = answered.filter { best.contains($0.date) }
            guard before.count >= 4 else { continue }
            let rateBest = Double(before.filter { $0.yes.contains(q) }.count) / Double(before.count)
            let rateAll = Double(answered.filter { $0.yes.contains(q) }.count) / Double(answered.count)
            out.append((q, rateBest - rateAll))
        }
        return out.filter { abs($0.1) >= 0.15 }.sorted { abs($0.1) > abs($1.1) }.prefix(4).map { journalText($0.0) + ($0.1 > 0 ? " (mais vezes)" : " (menos vezes)") }
    }

    func prompts() -> [String] {
        var out: [String] = []
        if let s = sessions(on: Day.today).first(where: { $0.end != nil }) { out.append("Como correu \(s.name) hoje?") }
        if all(Book.self).contains(where: { $0.finished == Day.today }) { out.append("Acabaste um livro. O que vais guardar dele?") }
        if let t = nextTrip, Day.between(Day.today, t.start) <= 2 { out.append("O que queres da viagem a \(t.destination)?") }
        let lastYear = Day.add(-365, to: Day.today)
        if let old = days[lastYear], !old.note.isEmpty { out.append("Há um ano: «\(old.note)»") }
        if out.isEmpty { out.append("O que te deu energia hoje, e o que te cansou?") }
        return out
    }

    // MARK: Goals and experiments

    func goalProgress(_ g: LifeGoal) -> (current: Double, eta: String?) {
        switch g.metric {
        case "lift":
            guard let id = g.exerciseId else { return (0, nil) }
            return (e1rmHistory(id).last?.value ?? 0, projection(id, goal: g.target)?.date)
        case "books":
            let year = String(Day.today.prefix(4))
            let done = Double(all(Book.self).filter { $0.finished?.hasPrefix(year) ?? false }.count)
            let dayOfYear = Double(Day.between(year + "-01-01", Day.today) + 1)
            let perDay = done / dayOfYear
            return (done, perDay > 0 ? Day.add(Int((g.target - done) / perDay), to: Day.today) : nil)
        case "sleep":
            let nights = (0..<14).compactMap { health[Day.add(-$0, to: Day.today)]?.sleep?.asleep }
            return (nights.isEmpty ? 0 : Double(nights.reduce(0, +) / nights.count) / 60, nil)
        case "weight":
            let w = all(WeightEntry.self).sorted { $0.date < $1.date }
            guard let last = w.last else { return (profile.weightKg, nil) }
            if let a = adaptiveTarget(), abs(a.trendKgPerWeek) > 0.05, (g.target - last.kg) / a.trendKgPerWeek > 0 { return (last.kg, Day.add(Int((g.target - last.kg) / a.trendKgPerWeek * 7), to: Day.today)) }
            return (last.kg, nil)
        default:
            let s = (0..<7).compactMap { health[Day.add(-$0, to: Day.today)]?.steps }
            return (s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count), nil)
        }
    }

    func metric(_ m: String, on day: String) -> Double? {
        switch m {
        case "sleep": return health[day]?.sleep.map { Double($0.asleep) }
        case "readiness": return readiness(on: day).map { Double($0.score) }
        case "hrv": return health[day]?.hrv
        case "rhr": return health[day]?.rhr
        case "steps": return health[day]?.steps
        default: return self.days[day]?.rating.map(Double.init)
        }
    }

    func experimentResult(_ e: Experiment) -> (before: Double?, during: Double?, daysIn: Int) {
        let daysIn = min(e.days, max(0, Day.between(e.start, Day.today) + 1))
        let before = (1...14).compactMap { metric(e.metric, on: Day.add(-$0, to: e.start)) }
        let during = (0..<daysIn).compactMap { metric(e.metric, on: Day.add($0, to: e.start)) }
        let avg = { (a: [Double]) -> Double? in a.count >= 3 ? a.reduce(0, +) / Double(a.count) : nil }
        return (avg(before), avg(during), daysIn)
    }

    // MARK: Weekly review and challenge

    func weekReview(_ week: String) -> [(String, String)] {
        let days = (0..<7).map { Day.add($0, to: week) }.filter { $0 <= Day.today }
        let focus = all(FocusSession.self).filter { days.contains($0.date) }.map(\.minutes).reduce(0, +)
        let workouts = sessions().filter { days.contains($0.date) && $0.end != nil }.count
        let proteinDays = days.filter { fuel(on: $0).protein >= profile.proteinTarget * 0.9 }.count
        let nights = days.compactMap { health[$0]?.sleep?.asleep }
        let due = days.flatMap { d in self.due(on: d).map { (d, $0) } }
        let kept = due.filter { status($0.1, on: $0.0).map { $0 != .skipped } ?? false }.count
        let reading = days.map { readingMinutes(on: $0) }.reduce(0, +)
        return [
            ("Foco", duration(focus)), ("Treinos", "\(workouts)"), ("Proteína", "\(proteinDays) de \(days.count) dias"),
            ("Sono", nights.isEmpty ? "–" : duration(nights.reduce(0, +) / nights.count) + " por noite"),
            ("Hábitos cumpridos", due.isEmpty ? "–" : "\(Int(Double(kept) / Double(due.count) * 100))%"), ("Leitura", duration(reading)),
        ]
    }

    /// One small challenge from your weakest area this week
    func challenge() -> WeeklyChallenge {
        if let c = record(WeeklyChallenge.self, week) { return c }
        let days = (1...7).map { Day.add(-$0, to: Day.today) }
        var areas: [(String, Double, String)] = []
        let nights = days.compactMap { health[$0]?.sleep?.asleep }
        if !nights.isEmpty { areas.append(("sleep", Double(nights.reduce(0, +) / nights.count) / Double(profile.sleepNeed), "Apagar as luzes até às \(clock(sleepPlan().perform)) em 5 noites")) }
        areas.append(("protein", Double(days.filter { fuel(on: $0).protein >= profile.proteinTarget * 0.9 }.count) / 7, "Chegar à proteína em 6 de 7 dias"))
        areas.append(("water", Double(days.filter { fuel(on: $0).water >= waterGoal(on: $0) * 0.9 }.count) / 7, "Meta de água em 5 dias"))
        let steps = days.compactMap { health[$0]?.steps }
        if !steps.isEmpty { areas.append(("steps", steps.reduce(0, +) / Double(steps.count) / Double(profile.stepGoal), "Uma caminhada de 15 minutos depois do almoço, 5 dias")) }
        areas.append(("reading", Double(days.map { readingMinutes(on: $0) }.reduce(0, +)) / (7 * 30), "Ler 20 minutos em 5 noites"))
        let weakest = areas.min { $0.1 < $1.1 } ?? ("sleep", 0, "Apagar as luzes a horas em 5 noites")
        let c = WeeklyChallenge(week: week, text: weakest.2, area: weakest.0)
        save(c)
        return c
    }

    var badges: [(String, String, Bool)] {
        let lifts = Set(sessions().flatMap(\.sets).filter(\.done).map(\.exerciseId)).map { e1rmHistory($0).map(\.value).max() ?? 0 }
        let books = all(Book.self).filter { $0.finished != nil }.count
        let goodNights = health.values.filter { ($0.sleep?.asleep ?? 0) >= 420 }.count
        let mustDos = logs.values.filter { l in promises[l.promiseId]?.kind == .mustDo && l.status == .done }.count
        let focusHours = all(FocusSession.self).map(\.minutes).reduce(0, +) / 60
        return [
            ("100 kg de uma vez", "dumbbell.fill", lifts.contains { $0 >= 100 }), ("10 livros", "books.vertical.fill", books >= 10),
            ("30 noites de 7 h", "moon.stars.fill", goodNights >= 30), ("100 essenciais", "checkmark.seal.fill", mustDos >= 100),
            ("50 horas de foco", "brain.head.profile", focusHours >= 50), ("Primeira sessão de cozinha", "frying.pan.fill", !all(Portion.self).isEmpty),
            ("Nível 10", "leaf.fill", level.level >= 10), ("Um mês de creatina", "pills.fill", mustDos >= 30),
        ]
    }

    // MARK: Cadence age

    /// A monthly trend in the spirit of WHOOP's healthspan: your age, moved by resting HR, cardio fitness, steps and
    /// sleep regularity against typical values. An estimate, not a medical measure.
    func cadenceAge() -> (age: Double, parts: [(String, Double)])? {
        let rhr = baseline({ $0.rhr })?.mean
        let vo2 = health.values.sorted { $0.date > $1.date }.compactMap(\.vo2).first
        let steps = (0..<30).compactMap { health[Day.add(-$0, to: Day.today)]?.steps }
        guard rhr != nil || vo2 != nil || !steps.isEmpty else { return nil }
        var parts: [(String, Double)] = []
        if let rhr { parts.append(("FC em repouso", max(-4, min(6, (rhr - 62) / 5)))) }
        if let vo2 { let typical = (profile.male ? 48.0 : 40.0) - Double(max(0, profile.age - 25)) * 0.35; parts.append(("Condição cardiovascular", max(-6, min(6, (typical - vo2) / 3)))) }
        if !steps.isEmpty { let s = steps.reduce(0, +) / Double(steps.count); parts.append(("Passos", s >= 10000 ? -2 : s >= 8000 ? -1 : s >= 6000 ? 0 : s >= 4000 ? 1.5 : 3)) }
        if let sri = sleepRegularity(nights: 28) { parts.append(("Regularidade do sono", sri >= 85 ? -1.5 : sri >= 75 ? 0 : sri >= 65 ? 1.5 : 3)) }
        return (Double(profile.age) + parts.map(\.1).reduce(0, +), parts)
    }

    // MARK: Minute-by-minute signals

    /// Above or below your limits for 10+ minutes while still (no steps), like Fitbit's notifications
    func heartRateEvents(_ d: Intraday) -> [String] {
        let rest = baseline({ $0.rhr })?.mean ?? 60
        let high = max(110, rest + 50), low = min(40, rest - 15)
        var out: [String] = []
        var run: (start: Int, kind: String)?
        for m in (0..<1440) {
            let hr = d.hr[String(m)], still = (d.steps[String(m)] ?? 0) < 5
            let kind = hr.map { $0 > high && still ? "high" : $0 < low && still ? "low" : "" } ?? ""
            if kind.isEmpty || run?.kind != kind {
                if let r = run, m - r.start >= 10 { out.append("Frequência cardíaca \(r.kind == "high" ? "alta" : "baixa") sem movimento, \(clock(r.start))–\(clock(m))") }
                run = kind.isEmpty ? nil : (m, kind)
            }
        }
        return out
    }

    /// Heart rate well above resting with almost no movement, 5+ minutes: a stress moment
    func stressMoments(_ d: Intraday) -> [(start: Int, end: Int)] {
        let rest = baseline({ $0.rhr })?.mean ?? 60
        var out: [(Int, Int)] = []
        var start: Int?
        let wake = profile.wakeMinute, bed = sleepPlan().perform
        guard wake < min(1440, bed) else { return [] }
        for m in wake..<min(1440, bed) {
            let hr = d.hr[String(m)] ?? 0, still = (d.steps[String(m)] ?? 0) < 10
            if hr > rest + 25 && still { if start == nil { start = m } } else {
                if let s = start, m - s >= 5 { out.append((s, m)) }
                start = nil
            }
        }
        return out.map { (start: $0.0, end: $0.1) }
    }

    /// The drop in the first minute after the last set of each exercise (12 bpm or less was linked to higher risk)
    func heartRateRecovery(_ s: WorkoutSession, _ d: Intraday) -> Int? {
        let midnight = Day.at(0, on: s.date).timeIntervalSince1970
        var drops: [Double] = []
        for ex in s.order {
            guard let last = s.sets.filter({ $0.exerciseId == ex.exerciseId && $0.done }).compactMap(\.at).max() else { continue }
            let m = Int((last / 1000 - midnight) / 60)
            if let peak = d.hr[String(m)], let after = d.hr[String(m + 1)] ?? d.hr[String(m + 2)] { drops.append(peak - after) }
        }
        return drops.isEmpty ? nil : Int((drops.reduce(0, +) / Double(drops.count)).rounded())
    }

    /// Drops of 3% or more below the rolling level, per hour of sleep (the oxygen desaturation index)
    func oxygenDips(_ d: Intraday) -> (perHour: Double, lowest: Double)? {
        let values = d.spo2.compactMap { k, v in Int(k).map { ($0, v) } }.sorted { $0.0 < $1.0 }
        guard values.count >= 60 else { return nil }
        var dips = 0, i = 0
        while i < values.count {
            let window = values[max(0, i - 10)..<i].map(\.1)
            let base = window.isEmpty ? values[i].1 : window.reduce(0, +) / Double(window.count)
            if base - values[i].1 >= 3 { dips += 1; i += 5 } else { i += 1 }
        }
        return (Double(dips) / (Double(values.count) / 60), values.map(\.1).min() ?? 0)
    }

    /// Mid-sleep on free days against workdays: your chronotype and the weekly gap
    func chronotype() -> (midFree: Int, midWork: Int, jetlag: Int, label: String)? {
        var free: [Int] = [], work: [Int] = []
        for i in 0..<28 {
            let d = Day.add(-i, to: Day.today)
            guard let s = health[d]?.sleep else { continue }
            var mid = Day.minuteOfDay(s.startDate.addingTimeInterval(s.endDate.timeIntervalSince(s.startDate) / 2))
            if mid > 12 * 60 { mid -= 1440 }
            let wd = Day.weekday(d)
            if wd == 1 || wd == 7 { free.append(mid) } else { work.append(mid) }
        }
        guard free.count >= 3, work.count >= 5 else { return nil }
        let f = free.reduce(0, +) / free.count, w = work.reduce(0, +) / work.count
        let label = f < 3 * 60 ? "Madrugador" : f < 4 * 60 + 30 ? "Intermédio" : "Noctívago"
        return (f, w, abs(f - w), label)
    }

    /// Acute (7-day) against chronic (28-day) load from active zone minutes: above 1.5 is ramping too fast
    func trainingLoad() -> (acute: Double, chronic: Double, ratio: Double)? {
        let azm = (0..<28).map { health[Day.add(-$0, to: Day.today)]?.azm ?? 0 }
        guard azm.filter({ $0 > 0 }).count >= 10 else { return nil }
        let acute = azm.prefix(7).reduce(0, +) / 7, chronic = azm.reduce(0, +) / 28
        return (acute, chronic, chronic > 0 ? acute / chronic : 0)
    }
}
