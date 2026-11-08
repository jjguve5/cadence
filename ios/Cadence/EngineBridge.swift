// Feeds the engine from the Store: robust baselines, freshness, the day's context, recommendations and their
// feedback, the minimum viable day, and predictions stored before their outcome is known (for calibration).
import Foundation

struct MinimumDay: Record, Equatable {
    static let kind = "mvd"
    var id: String { date }
    var date: String
    var on: Bool
    var reasons: [String] = []
}

struct RecFeedback: Record, Equatable {
    static let kind = "recfeedback"
    var id: String { "\(date)|\(rec)" }
    var date: String
    var rec: String
    var response: String // useful, dismissed
    var at = nowMs()
}

/// A prediction written down before its outcome is known, so it can be checked fairly later
struct Prediction: Record, Equatable {
    static let kind = "prediction"
    var id: String
    var kind: String // energy, training, focus
    var date: String
    var predicted: Double // on the outcome's own scale
    var made = nowMs()
    var basis: String
}

@MainActor
extension Store {
    // MARK: Baselines and freshness

    func robust(_ value: (HealthDay) -> Double?, before day: String = Day.today) -> RobustBaseline? {
        let values = (1...28).compactMap { health[Day.add(-$0, to: day)] }.compactMap(value)
        return RobustBaseline.of(values, minimum: 4)
    }

    /// Hours since the Air last synced, from the tracker's own timestamp
    var syncAgeHours: Double? {
        guard let s = device?.lastSync else { return nil }
        return Date().timeIntervalSince(ISO8601DateFormatter.lenient(s)) / 3600
    }

    /// What's known about this morning, said plainly
    var freshnessNote: String? {
        let today = health[Day.today]
        if today?.sleep == nil, Clock.minute() < 14 * 60 { return "O sono da última noite ainda não " + (profile.usesBand ? "sincronizou" : "chegou ao Apple Health") + ((profile.usesBand ? syncAgeHours : nil).map { ": o Air sincronizou pela última vez há \(Int($0)) h" } ?? "") + "." }
        if today?.hrv == nil, today?.sleep != nil { return "A VFC de hoje ainda não sincronizou; a prontidão usa o sono e a FC em repouso." }
        return nil
    }

    // MARK: Minimum viable day

    func isMinimumDay(_ day: String = Day.today) -> Bool { record(MinimumDay.self, day)?.on ?? false }

    func setMinimumDay(_ on: Bool, reasons: [String] = [], day: String = Day.today) {
        save(MinimumDay(date: day, on: on, reasons: reasons))
        Reminders.shared.reschedule()
    }

    /// On a minimum viable day only the essentials count: must-dos and medicines, sleep, water. Doing them is a full day.
    func minimumScore(on day: String) -> Int {
        let musts = due(on: day).filter { $0.kind == .mustDo }
        let doses = self.doses(on: day)
        return Engine.minimumScore(essentials: musts.count + doses.count,
                                   essentialsDone: musts.filter { status($0, on: day).map { $0 != .skipped } ?? false }.count + doses.filter { $0.log?.taken == true }.count,
                                   sleep: health[day]?.sleep?.asleep, sleepNeed: profile.sleepNeed, water: fuel(on: day).water, waterGoal: waterGoal(on: day))
    }

    // MARK: Context and recommendations

    func dayContext() -> DayContext {
        let today = Day.today
        let h = health[today]
        let minute = Clock.minute()
        let nights = (0..<7).compactMap { health[Day.add(-$0, to: today)]?.sleep?.asleep }
        let project = all(Project.self).filter { !$0.archived }.min { $0.deadline < $1.deadline }
        let deadline = project.map { p -> (title: String, daysLeft: Int, behind: Bool) in
            let pace = self.pace(p)
            return (p.title, Day.between(today, p.deadline), pace.finish.map { $0 > p.deadline } ?? (p.done < p.target && pace.perDay == 0))
        }
        let meetings = Agenda.shared.events(on: today).map { $0.endMinute - $0.startMinute }.reduce(0, +)
        let mustDos = openMustDos().map { (title: $0.title, late: time(of: $0) + 30 <= minute) }
        let energy = (1...7).compactMap { days[Day.add(-$0, to: today)]?.energy }
        let suppressed = Set(all(RecFeedback.self).filter { Day.between($0.date, today) <= 7 }.reduce(into: [String: [String]]()) { $0[$1.rec, default: []].append($1.response) }
            .filter { $0.value.suffix(5).filter { $0 == "dismissed" }.count >= 3 }.keys)
        let calibration = Engine.calibrate(trainingPairs())
        let gap = profile.on("fuel") ? max(0, profile.proteinTarget - fuel().protein) : nil
        return DayContext(minute: minute, sleepMinutes: h?.sleep?.asleep, sleepNeed: profile.sleepNeed,
                          sleepBaseline: RobustBaseline.of((1...28).compactMap { health[Day.add(-$0, to: today)]?.sleep.map { Double($0.asleep) } }, minimum: 7),
                          sleepDebt: Engine.sleepDebt(nights: nights, need: profile.sleepNeed),
                          hrv: h?.hrv, hrvBaseline: robust { $0.hrv }, rhr: h?.rhr, rhrBaseline: robust { $0.rhr }, readiness: readinessResult(),
                          illnessSigns: illnessSigns(), lastSyncHours: syncAgeHours, trainingToday: profile.on("training") ? todaysTemplate?.name : nil,
                          deepWorkPlanned: all(PlanBlock.self).contains { $0.date == today && $0.type == "deep" }, meetingsMinutes: meetings,
                          deadline: deadline, openMustDos: mustDos, proteinGap: gap, airBattery: device?.battery, recentEnergy: energy,
                          suppressedKinds: suppressed, minimumDay: isMinimumDay(),
                          readinessUseful: calibration.n >= 10 ? (calibration.spearman ?? 0) >= 0.15 : nil,
                          eveningAfter: { let s = sleepPlan(); return s.after.map { (title: $0.title, back: $0.end, lightsOut: s.perform) } }(),
                          usesBand: profile.usesBand)
    }

    func recommendations() -> [Recommendation] {
        let answered = Set(all(RecFeedback.self).filter { $0.date == Day.today }.map(\.rec))
        return Engine.recommendations(dayContext()).filter { $0.kind == "mustdo" || !answered.contains($0.kind) }
    }

    func feedback(_ r: Recommendation, useful: Bool) {
        save(RecFeedback(date: Day.today, rec: r.kind, response: useful ? "useful" : "dismissed"))
    }

    // MARK: Readiness through the engine

    func readinessResult(on day: String = Day.today) -> ReadinessResult? {
        guard let h = health[day] else { return nil }
        let yesterday = Day.add(-1, to: day)
        let hb = robust({ $0.hrv }, before: day), rb = robust({ $0.rhr }, before: day)
        let prevH = health[yesterday]?.hrv.flatMap { v in robust({ $0.hrv }, before: yesterday).map { $0.z(v) } }
        let prevR = health[yesterday]?.rhr.flatMap { v in robust({ $0.rhr }, before: yesterday).map { $0.z(v) } }
        return Engine.readiness(hrv: h.hrv, hrvBase: hb, rhr: h.rhr, rhrBase: rb, sleepMinutes: h.sleep?.asleep, sleepNeed: profile.sleepNeed,
                                previousHrvZ: prevH, previousRhrZ: prevR, offset: profile.readinessOffset)
    }

    // MARK: Predictions and calibration

    /// Written once in the morning, before the day can be rated
    func recordMorningPrediction() {
        let id = "energy|\(Day.today)"
        // only in the morning and before the day is rated, so the outcome can't leak into the prediction
        guard Clock.minute() < 14 * 60, day().energy == nil, day().closedAt == nil,
              record(Prediction.self, id) == nil, let r = readinessResult(), r.confidence >= .moderate else { return }
        save(Prediction(id: id, kind: "energy", date: Day.today, predicted: 1 + 4 * Double(r.score) / 100, basis: "readiness \(r.score)"))
    }

    func recordTrainingPrediction(session: WorkoutSession) {
        let id = "training|\(session.id)"
        guard session.end == nil, session.feel == nil, session.date == Day.today, record(Prediction.self, id) == nil, let r = readinessResult() else { return }
        save(Prediction(id: id, kind: "training", date: session.date, predicted: 1 + 4 * Double(r.score) / 100, basis: "readiness \(r.score)"))
    }

    func recordFocusPrediction(session: FocusSession) {
        let minute = Day.minuteOfDay(Date(timeIntervalSince1970: session.start / 1000))
        save(Prediction(id: "focus|\(session.id)", kind: "focus", date: session.date, predicted: 1 + 2 * energy(at: minute), basis: "energy curve at \(clock(minute))"))
    }

    func energyPairs() -> [(predicted: Double, observed: Double)] {
        // matched by day, and only when the prediction was written before the day was rated
        all(Prediction.self).filter { $0.kind == "energy" }.compactMap { p in
            guard let d = days[p.date], p.made <= (d.closedAt ?? .infinity) else { return nil }
            return d.energy.map { (p.predicted, Double($0)) }
        }
    }

    func trainingPairs() -> [(predicted: Double, observed: Double)] {
        let sessions = Dictionary(all(WorkoutSession.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return all(Prediction.self).filter { $0.kind == "training" }.compactMap { p in
            sessions[String(p.id.dropFirst("training|".count))]?.feel.map { (p.predicted, Double($0)) }
        }
    }

    func focusPairs() -> [(predicted: Double, observed: Double)] {
        let sessions = Dictionary(all(FocusSession.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return all(Prediction.self).filter { $0.kind == "focus" }.compactMap { p in
            sessions[String(p.id.dropFirst("focus|".count))]?.rating.map { (p.predicted, Double($0)) }
        }
    }
}
