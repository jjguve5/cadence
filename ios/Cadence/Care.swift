// Care: brushing, grooming that learns your rhythm, step-by-step routines, medicines and products with stock,
// and travel (regular trips with leave-by alerts, one-off trips with a jet lag plan and a packing list).
import Foundation

// MARK: - Self-care

struct BrushLog: Record, Equatable {
    static let kind = "brush"
    var id = UUID().uuidString
    var date = Day.today
    var minute = Day.minuteOfDay()
    var seconds: Int
    var floss = false
    var mouthwash = false
}

struct GroomingItem: Record, Equatable {
    static let kind = "groom"
    var id = UUID().uuidString
    var title: String
    var icon = "scissors"
    var interval: Int // days, starting value
    var history: [String] = [] // dates done
    var lastRemind: String?

    /// Your real average interval once there are three times on record
    var learned: Int? {
        guard history.count >= 3 else { return nil }
        let sorted = history.sorted()
        let gaps = zip(sorted, sorted.dropFirst()).map { Day.between($0, $1) }.filter { $0 > 0 }
        return gaps.isEmpty ? nil : Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
    }
    var rhythm: Int { learned ?? interval }
    var last: String? { history.max() }
    var daysSince: Int? { last.map { Day.between($0, Day.today) } }
    var freshness: Double { daysSince.map { 1 - min(1, Double($0) / Double(max(1, rhythm))) } ?? 0 }
}

struct Shower: Record, Equatable {
    static let kind = "shower"
    var id = UUID().uuidString
    var at = nowMs()
}

/// One shower a day, taken that evening or the next morning. Pure, so the rules are testable.
enum ShowerRules {
    /// Which days the showers cover, in order: before noon it covers yesterday if yesterday had none, otherwise today
    static func covered(_ times: [Date], calendar cal: Calendar = Day.calendar) -> Set<String> {
        var days = Set<String>()
        for t in times.sorted() {
            let day = Day.key(t), morning = cal.component(.hour, from: t) < 12
            let yesterday = Day.key(cal.date(byAdding: .day, value: -1, to: t) ?? t)
            if morning && !days.contains(yesterday) { days.insert(yesterday) } else { days.insert(day) }
        }
        return days
    }

    enum When: String { case tonight, morning }

    /// Tonight about 90 minutes before lights out (a warm shower 1–2 h before bed helps you fall asleep), unless it's
    /// too late, the evening is taken, or the night is hot enough to sweat through it; then tomorrow morning, unless
    /// you leave too early for one. Returns the choice and why.
    static func suggest(now: Int, windDown: Int, lightsOut: Int, eveningAfter: String?, movedToday: Bool, wake: Int, leaveTomorrow: Int?, nightFeels: Double? = nil) -> (When, String) {
        let tightMorning = leaveTomorrow.map { $0 - wake < 60 } ?? false
        if windDown - now < 30 { return (.morning, "Too late for one tonight" + (tightMorning ? ": a quick one before you leave at \(clock(leaveTomorrow!))" : ", so tomorrow morning")) }
        if let f = nightFeels, f >= 24 {
            let why = "It stays around \(Int(f.rounded()))° tonight, so you'd sweat through the night"
            return tightMorning ? (.tonight, why + ", but you leave at \(clock(leaveTomorrow!)): a cool one tonight") : (.morning, why + ": shower in the morning")
        }
        if tightMorning { return (.tonight, "You leave at \(clock(leaveTomorrow!)) tomorrow, so the morning is tight") }
        if movedToday { return (.tonight, "After today's workout") }
        if let a = eveningAfter { return (.morning, "Back from \(a) close to bedtime: shower in the morning instead") }
        return (.tonight, "About 1–2 h before bed a warm shower helps you fall asleep")
    }
}

struct RoutineStep: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var seconds: Int
}

struct CareRoutine: Record, Equatable {
    static let kind = "routine"
    var id = UUID().uuidString
    var title: String
    var icon = "sparkles"
    var steps: [RoutineStep]
}

// MARK: - Medicines and products

struct Medicine: Record, Equatable {
    static let kind = "med"
    var id = UUID().uuidString
    var name: String
    var kind = "medicine" // medicine, supplement, skincare, drops, other
    var dose = ""
    var how = "" // with food, empty stomach...
    var times: [Int] = [9 * 60] // minutes of the day
    var schedule = Schedule()
    var start = Day.today
    var end: String? // temporary course
    var mustDo = true
    var stock: Double?
    var perDose: Double = 1
    var refillAt: Double = 7 // doses left

    func isActive(on day: String) -> Bool { day >= start && (end.map { day <= $0 } ?? true) && schedule.isDue(on: day) }
}

struct MedLog: Record, Equatable {
    static let kind = "medlog"
    var id: String { "\(medId)|\(date)|\(minute)" }
    var medId: String
    var date: String
    var minute: Int
    var taken: Bool
    var at = nowMs()
}

// MARK: - Travel

struct RegularTrip: Record, Equatable {
    static let kind = "commute"
    var id = UUID().uuidString
    var title: String
    var destination = ""
    var weekdays: [Int] = [2, 3, 4, 5, 6]
    var arrive = 9 * 60 // be there by
    var travel = 30 // minutes door to door
    var buffer = 10
    var returnAt: Int? // leave to come back

    var leave: Int { arrive - travel - buffer }
}

struct Trip: Record, Equatable {
    static let kind = "trip"
    var id = UUID().uuidString
    var destination: String
    var start: String
    var end: String
    var hoursAhead = 0 // time difference: + east, − west
    var packed: [String] = []
    var budget: Double?
    var notes = ""

    var nights: Int { max(0, Day.between(start, end)) }
}

@MainActor
extension Store {
    // Seeds so the care area is useful at once
    func seedCare() {
        if all(GroomingItem.self).isEmpty {
            for (t, i, icon) in [("Trim beard", 7, "scissors"), ("Cut hand nails", 10, "hand.raised"), ("Cut toenails", 28, "figure.walk"), ("Haircut", 35, "comb"), ("Eyebrows", 30, "eye")] {
                save(GroomingItem(title: t, icon: icon, interval: i))
            }
        }
        if all(CareRoutine.self).isEmpty {
            save(CareRoutine(title: "Night skincare", icon: "moon.stars", steps: [RoutineStep(title: "Cleanser", seconds: 60), RoutineStep(title: "Wait, then serum", seconds: 60), RoutineStep(title: "Moisturiser", seconds: 30)]))
            save(CareRoutine(title: "Morning", icon: "sun.max", steps: [RoutineStep(title: "Water, a full glass", seconds: 30), RoutineStep(title: "Cleanser", seconds: 45), RoutineStep(title: "Sunscreen", seconds: 30)]))
        }
    }

    var groomingDue: [GroomingItem] { all(GroomingItem.self).filter { ($0.daysSince ?? 999) >= $0.rhythm }.sorted { $0.freshness < $1.freshness } }

    /// "Trip on Friday: beard and nails on Thursday"
    func groomingBefore(_ trip: Trip) -> [GroomingItem] {
        let days = Day.between(Day.today, trip.start)
        guard days >= 0, days <= 4 else { return [] }
        return all(GroomingItem.self).filter { ($0.daysSince ?? 999) + days >= $0.rhythm - 2 }
    }

    func brushes(on day: String = Day.today) -> [BrushLog] { all(BrushLog.self).filter { $0.date == day } }

    var brushHeadDue: Bool {
        let first = all(BrushLog.self).map(\.date).min() ?? Day.today
        let changed = records("brushhead").keys.max() ?? first
        return Day.between(changed, Day.today) >= 90
    }

    // MARK: Medicines

    func doses(on day: String = Day.today) -> [(med: Medicine, minute: Int, log: MedLog?)] {
        all(Medicine.self).filter { $0.isActive(on: day) }.flatMap { m in m.times.map { (med: m, minute: $0, log: record(MedLog.self, "\(m.id)|\(day)|\($0)")) } }.sorted { $0.minute < $1.minute }
    }

    func take(_ med: Medicine, minute: Int, on day: String = Day.today, taken: Bool = true) {
        save(MedLog(medId: med.id, date: day, minute: minute, taken: taken))
        if taken, var m = record(Medicine.self, med.id), let s = m.stock { m.stock = max(0, s - m.perDose); save(m) }
        Reminders.shared.reschedule()
    }

    func dosesLeft(_ m: Medicine) -> (doses: Int, runsOut: String)? {
        guard let s = m.stock, m.perDose > 0 else { return nil }
        let doses = Int(s / m.perDose)
        let perDay = Double(m.times.count) * Double(m.schedule.dueInWeek(of: Day.today)) / 7
        return (doses, Day.add(Int(Double(doses) / max(0.1, perDay)), to: Day.today))
    }

    func adherence(_ m: Medicine, days: Int = 30) -> Double? {
        var due = 0, taken = 0
        for i in 1...days {
            let d = Day.add(-i, to: Day.today)
            guard m.isActive(on: d) else { continue }
            for t in m.times { due += 1; if record(MedLog.self, "\(m.id)|\(d)|\(t)")?.taken == true { taken += 1 } }
        }
        return due == 0 ? nil : Double(taken) / Double(due)
    }

    // MARK: Showers

    /// Logged showers plus finished gym sessions (you shower there), as times
    var showerTimes: [Date] {
        all(Shower.self).map { Date(timeIntervalSince1970: $0.at / 1000) }
            + sessions().filter { $0.end != nil && records("noGymShower")[$0.id] == nil }.map { Date(timeIntervalSince1970: $0.end! / 1000) }
    }

    func showered(_ day: String) -> Bool { ShowerRules.covered(showerTimes).contains(day) }

    /// Today's shower: done, or when it's planned (your pick, else the suggestion) and why
    func showerPlan(for day: String = Day.today) -> (when: ShowerRules.When, at: Date, why: String)? {
        guard !showered(day) else { return nil }
        let plan = sleepPlan(for: day)
        let tomorrow = Day.add(1, to: day)
        // training right now: the gym shower will count
        if sessions(on: day).contains(where: { $0.end == nil && nowMs() - $0.start < 3 * 3600 * 1000 }) { return nil }
        let picked: ShowerRules.When? = { if case .string(let t) = records("showerWhen")[day] { return ShowerRules.When(rawValue: t) }; return nil }()
        let auto = ShowerRules.suggest(now: day == Day.today ? Day.minuteOfDay() : 0, windDown: plan.windDown, lightsOut: plan.perform, eveningAfter: plan.after?.title,
                                       movedToday: (health[day]?.azm ?? 0) >= 20, wake: profile.wakeMinute, leaveTomorrow: commutes(on: tomorrow).map(\.leave).min(),
                                       nightFeels: day == Day.today ? nightFeels(from: plan.perform, to: profile.wakeMinute + 1440) : nil)
        let when = picked ?? auto.0
        let why = picked == nil ? auto.1 : (when == .tonight ? "You picked tonight" : "You picked tomorrow morning")
        if when == .morning { return (.morning, Day.at(profile.wakeMinute + 20, on: tomorrow), why) }
        let m = Engine.outside(min(plan.perform - 90, plan.windDown - 15), busy: busy(on: day))
        return (.tonight, Day.at(max(m, day == Day.today ? Day.minuteOfDay() + 5 : 0), on: day), why)
    }

    /// The warmest it feels outside between lights out and waking, from the forecast
    func nightFeels(from: Int, to: Int) -> Double? {
        WeatherStore.shared.today?.hours.filter { $0.minute >= from && $0.minute <= to }.map(\.feels).max()
    }

    func logShower() {
        save(Shower())
        Reminders.shared.reschedule()
    }

    func pickShower(_ when: ShowerRules.When, for day: String = Day.today) {
        put("showerWhen", day, .string(when.rawValue))
        Reminders.shared.reschedule()
    }

    // MARK: Travel

    func commutes(on day: String = Day.today) -> [RegularTrip] { all(RegularTrip.self).filter { $0.weekdays.contains(Day.weekday(day)) && !onTrip(day) } }

    /// Regular trips door to door and timed calendar events: the plan keeps promises and the evening out of them
    func busy(on day: String = Day.today) -> [Busy] {
        commutes(on: day).map { Busy(start: $0.leave, end: $0.arrive, title: $0.title) }
            + Agenda.shared.events(on: day).map { Busy(start: $0.startMinute, end: $0.endMinute, title: $0.title) }
    }

    func onTrip(_ day: String) -> Bool { all(Trip.self).contains { day >= $0.start && day <= $0.end } }

    var nextTrip: Trip? { all(Trip.self).filter { $0.end >= Day.today }.min { $0.start < $1.start } }

    /// Shift bedtime 30–60 minutes a day before flying, in the direction of travel; light and meal timing to match
    func jetLagPlan(_ t: Trip) -> [(day: String, bedtime: Int, note: String)] {
        let diff = t.hoursAhead
        guard abs(diff) >= 2 else { return [] }
        let base = sleepPlan().perform
        let stepMinutes = diff > 0 ? -45 : 60 // east: earlier, west: later
        let days = abs(diff) > 3 ? 3 : 2
        var out: [(day: String, bedtime: Int, note: String)] = []
        for i in (1...days).reversed() {
            let d = Day.add(-i, to: t.start)
            let shift = stepMinutes * (days - i + 1)
            out.append((day: d, bedtime: base + shift, note: diff > 0 ? "Bright light early morning, dim after sunset; dinner earlier" : "Bright light in the evening, keep mornings dim"))
        }
        out.append((day: t.start, bedtime: base, note: "On the plane: sleep on \(t.destination)'s night, water every hour, no alcohol"))
        out.append((day: Day.add(1, to: t.start), bedtime: base, note: "First day there: outdoor light in the local morning, meals on local time"))
        return out
    }

    func packingList(_ t: Trip) -> [String] {
        var items = ["Passport / ID", "Phone charger", "Fitbit Air charger", "Toothbrush and paste"]
        let n = max(1, t.nights)
        items += ["\(n + 1) × underwear", "\(n + 1) × socks", "\(max(1, (n + 1) / 2)) × T-shirts"]
        for m in all(Medicine.self) where m.end.map({ $0 >= t.start }) ?? true {
            items.append("\(m.name): \(Int(Double(m.times.count * (n + 1)) * m.perDose)) doses")
        }
        if !templates.isEmpty { items += ["Gym clothes", "Trainers"] }
        if t.hoursAhead != 0 { items.append("Eye mask and earplugs") }
        return items
    }
}
