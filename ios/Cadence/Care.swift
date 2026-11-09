// Care: brushing, grooming that learns your rhythm, step-by-step routines, medicines and products with stock,
// and travel (regular trips with leave-by alerts, one-off trips with a jet lag plan and a packing list).
import CoreLocation
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
    var interval: Int // days: the app's starting value until you change it, or accept the one you've learned
    var history: [String] = [] // dates done
    var lastRemind: String?
    /// Phase 2.5: fixed days instead of the interval (Calendar weekdays, 1 = Sunday); nil or empty means the interval.
    /// Optional, so older items read as they are and an older build ignores it.
    var weekdays: [Int]?

    /// Your real average interval once there are three times on record
    var learned: Int? {
        guard history.count >= 3 else { return nil }
        let sorted = history.sorted()
        let gaps = zip(sorted, sorted.dropFirst()).map { Day.between($0, $1) }.filter { $0 > 0 }
        return gaps.isEmpty ? nil : Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
    }
    /// The fixed days, if there are any
    var fixedDays: [Int] { (weekdays ?? []).filter { (1...7).contains($0) } }
    /// How often, in days: the interval you have (the app's at first); with fixed days, about 7 ÷ how many. What you've
    /// learned is only offered as a suggestion (`suggestedInterval`) and never applied by itself (design v17, decision 63).
    var rhythm: Int { fixedDays.isEmpty ? interval : max(1, Int((7 / Double(Set(fixedDays).count)).rounded())) }
    /// The learned interval, offered when it differs from the one set (only for an interval, not fixed days)
    var suggestedInterval: Int? {
        guard fixedDays.isEmpty, let l = learned, l != interval else { return nil }
        return l
    }
    var last: String? { history.max() }
    var daysSince: Int? { last.map { Day.between($0, Day.today) } }
    var freshness: Double { daysSince.map { 1 - min(1, Double($0) / Double(max(1, rhythm))) } ?? 0 }

    /// Due on `day`: with fixed days, when the latest of them (on or before `day`) came after the last time; with an
    /// interval, once it has passed since the last time. Never done is due, as before (shown as «Nunca registado»).
    func isDue(on day: String) -> Bool {
        guard let last = history.filter({ $0 <= day }).max() else { return true }
        let days = Set(fixedDays)
        if days.isEmpty { return Day.between(last, day) >= interval }
        for back in 0..<7 {
            let d = Day.add(-back, to: day)
            if days.contains(Day.weekday(d)) { return last < d }
        }
        return false
    }
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
        if windDown - now < 30 { return (.morning, "Já é tarde para um duche esta noite" + (tightMorning ? ": um rápido antes de saíres às \(clock(leaveTomorrow!))" : ", por isso amanhã de manhã")) }
        if let f = nightFeels, f >= 24 {
            let why = "Esta noite fica à volta dos \(Int(f.rounded()))°, por isso ias transpirar durante a noite"
            return tightMorning ? (.tonight, why + ", mas sais às \(clock(leaveTomorrow!)): um duche fresco esta noite") : (.morning, why + ": duche de manhã")
        }
        if tightMorning { return (.tonight, "Amanhã sais às \(clock(leaveTomorrow!)), por isso a manhã é apertada") }
        if movedToday { return (.tonight, "Depois do treino de hoje") }
        if let a = eveningAfter { return (.morning, "Regressas de \(a) perto da hora de deitar: duche de manhã, em vez de à noite") }
        return (.tonight, "Um duche morno 1–2 h antes de deitar ajuda a adormecer")
    }
}

struct RoutineStep: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var seconds: Int
    /// Phase 2.5: the product of yours this step uses (a CareProduct id), so its uses count. Optional: older steps read
    /// as they are and an older build ignores it.
    var productId: String?
}

struct CareRoutine: Record, Equatable {
    static let kind = "routine"
    var id = UUID().uuidString
    var title: String
    var icon = "sparkles"
    var steps: [RoutineStep]
    /// Phase 2.5: the routine's own time of day (minutes after midnight), if it has one. It decides whether the routine
    /// counts for the morning or the night (see CareRules.moment). Optional, as above.
    var minute: Int?
}

// MARK: - Routines kept by day and step (phase 2.5)

/// The half of the day a routine counts for. Not saved: worked out from the routine's own time, or its name and icon.
enum RoutineMoment: Hashable {
    case morning, night
    var label: String { self == .morning ? "manhã" : "noite" }
}

/// The steps of one routine you confirmed on one day, and when. One record per routine and day, id "<routine>_<day>"
/// (see CareRules.logId), whose value is an object, as the server takes. An older build keeps it untouched, as it does
/// any record it doesn't know.
struct RoutineLog: Record, Equatable {
    static let kind = "routinelog"
    var id: String
    var routineId: String
    var date: String
    var steps: [String: Double] = [:] // step id → when you confirmed it (ms since 1970)
}

/// A product of yours used in routines (a cleanser, a sunscreen). How long it lasts is worked out from the uses you
/// confirmed in them, so it is always an estimate; «Muito», «Metade» or «Pouco» recalibrate it.
struct CareProduct: Record, Equatable {
    static let kind = "careproduct"
    var id = UUID().uuidString
    var name: String
    var size: Double? // the pack: 200 (ml)
    var unit = "ml"
    var perUse: Double? // about how much one use takes: 2 (ml)
    var startedAt: Double? // when this pack was started (ms); nil: uses count from the first one on record
    var left: Double? // the share of the pack you said is left (0–1)…
    var leftAt: Double? // …and when you said it (ms)
}

/// The rules of the routines and products, pure so they're testable
enum CareRules {
    /// Morning until 14:00, night from then on (decision for phase 2.5)
    static let middayMinute = 14 * 60
    /// «Agora» stops asking for the morning's at lunchtime, and only asks for the night's from the evening
    static let morningAskedUntil = 12 * 60
    static let nightAskedFrom = 19 * 60 + 30
    /// The shopping suggestion shows when a product runs out within this many days (design: «acaba em cerca de 3 semanas»)
    static let refillWithin = 21
    static let msPerDay: Double = 86_400_000

    /// Whether «Agora» asks for this routine at this minute. With its own time: until 90 minutes after it (morning), from it
    /// (night). Higiene keeps showing what's to confirm all day.
    static func asksInAgora(_ routine: CareRoutine, minute: Int) -> Bool {
        switch moment(of: routine) {
        case .morning: return minute < max(morningAskedUntil, (routine.minute ?? 0) + 90)
        case .night: return minute >= min(nightAskedFrom, routine.minute ?? nightAskedFrom)
        case nil: return false
        }
    }

    /// What «Hoje não» hides for the day, as a NowDismiss
    static func agoraKey(_ routine: CareRoutine) -> String { "routine." + routine.id }

    static func moment(at minute: Int) -> RoutineMoment { ((minute % 1440) + 1440) % 1440 < middayMinute ? .morning : .night }

    /// A routine with its own time counts in the half that time falls in; otherwise its name or icon says which
    /// ("Rotina da manhã", "Morning", ☀︎ / "Rotina da noite", "Night skincare", ☾). Anything else has no moment.
    static func moment(of routine: CareRoutine) -> RoutineMoment? {
        if let m = routine.minute { return moment(at: m) }
        let t = routine.title.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        if ["manha", "morning", "acordar"].contains(where: { t.contains($0) }) { return .morning }
        if ["noite", "night", "evening", "dormir", "deitar"].contains(where: { t.contains($0) }) { return .night }
        if ["sun.max", "sun.max.fill", "sunrise", "sunrise.fill"].contains(routine.icon) { return .morning }
        if ["moon", "moon.fill", "moon.stars", "moon.stars.fill", "moon.zzz", "moon.zzz.fill"].contains(routine.icon) { return .night }
        return nil
    }

    /// "<routine>_<day>", in the characters the server takes ([A-Za-z0-9_.:-], up to 80). The app makes routine ids as
    /// UUIDs, which are kept as they are; any other id is cleaned (anything else becomes "-") and gets a hash of the
    /// original (FNV-1a, as Store.boughtKey), so two routines never share a log.
    static func logId(routine: String, day: String) -> String {
        let safe = String(routine.map { c -> Character in c.isASCII && (c.isLetter || c.isNumber || "_.:-".contains(c)) ? c : "-" })
        let plain = safe + "_" + day
        if safe == routine && plain.count <= 80 { return plain }
        var hash: UInt32 = 2166136261
        for byte in routine.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return String(safe.prefix(max(0, 80 - 9 - 1 - day.count))) + "_" + String(format: "%08x", hash) + "_" + day
    }

    /// The same product however it's written: the shopping list's own key (Store.productKey, in Kitchen.swift), so
    /// Higiene and Compras can never disagree on what counts as the same product
    static func productKey(_ name: String) -> String { Store.productKey(name) }

    /// "2 min", "45 s", "1 min 30 s"
    static func stepLength(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m) min \(s) s"
    }

    /// "seg, qua, sex", Monday first
    static func weekdayNames(_ days: [Int]) -> String {
        let names = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
        return Set(days).filter { (1...7).contains($0) }.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { names[$0 - 1] }.joined(separator: ", ")
    }

    static func weekdayName(_ day: Int) -> String {
        ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"][max(0, min(6, day - 1))]
    }

    /// "a cada 7 dias", "todos os dias" or the fixed days
    static func frequencyText(_ g: GroomingItem) -> String {
        if !g.fixedDays.isEmpty { return weekdayNames(g.fixedDays) }
        return g.interval == 1 ? "todos os dias" : "a cada \(g.interval) dias"
    }

    /// "hoje", "ontem", "há 6 dias" since the last time, or nil when it was never registered
    static func sinceText(_ g: GroomingItem, today: String) -> String? {
        guard let last = g.history.filter({ $0 <= today }).max() else { return nil }
        let n = Day.between(last, today)
        return n <= 0 ? "hoje" : n == 1 ? "ontem" : "há \(n) dias"
    }

    /// Of the steps, how many days had all of them and how many only some. Days with nothing on record count for
    /// neither: no data is not a failure.
    static func consistency(steps: [String], days: [[String: Double]]) -> (full: Int, partial: Int) {
        guard !steps.isEmpty else { return (0, 0) }
        var full = 0, partial = 0
        for done in days {
            let n = steps.filter { done[$0] != nil }.count
            if n == steps.count { full += 1 } else if n > 0 { partial += 1 }
        }
        return (full, partial)
    }

    // MARK: Replenishment

    struct Refill: Equatable {
        var days: Int // about when it runs out
        var low: Int // if each use takes a third more
        var high: Int // if each use takes a third less
    }

    struct Level: Identifiable {
        let id: String
        let label: String
        let share: Double
    }

    /// «Quanto ainda tens?»
    static let levels = [Level(id: "muito", label: "Muito", share: 0.75), Level(id: "metade", label: "Metade", share: 0.5), Level(id: "pouco", label: "Pouco", share: 0.2)]

    /// When the product runs out, from the uses you confirmed: how fast you use it (the last 28 days, at least 3 uses)
    /// and what's left (the pack minus the uses since it was started, or what you said is left minus the uses since).
    /// Nil without the pack's size and the amount per use, or with too few uses: then it shows «Sem dados».
    static func refill(_ p: CareProduct, uses: [Double], now: Double) -> Refill? {
        guard let size = p.size, size > 0, let per = p.perUse, per > 0 else { return nil }
        let recent = uses.filter { $0 > now - 28 * msPerDay && $0 <= now }
        guard recent.count >= 3, let first = recent.min() else { return nil }
        let span = Day.between(Day.key(Date(timeIntervalSince1970: first / 1000)), Day.key(Date(timeIntervalSince1970: now / 1000))) + 1
        let perDay = Double(recent.count) / Double(max(1, span))
        let start: Double, amount: Double
        if let share = p.left, let at = p.leftAt {
            start = at
            amount = max(0, min(1, share)) * size
        } else {
            start = p.startedAt ?? ((uses.min() ?? now) - 1)
            amount = size
        }
        let used = Double(uses.filter { $0 > start && $0 <= now }.count) * per
        let days = max(0, amount - used) / per / perDay
        return Refill(days: Int(days.rounded()), low: Int((days * 2 / 3).rounded()), high: Int((days * 4 / 3).rounded()))
    }

    /// "3 semanas", "5 dias", "1 dia", "2 meses"
    static func spanText(_ days: Int) -> String {
        if days <= 0 { return "menos de 1 dia" }
        if days == 1 { return "1 dia" }
        if days < 14 { return "\(days) dias" }
        if days < 60 { return "\(Int((Double(days) / 7).rounded())) semanas" }
        return "\(Int((Double(days) / 30).rounded())) meses"
    }

    /// "entre 2 e 4 semanas", or nil when both ends read the same
    static func rangeText(_ r: Refill) -> String? {
        let a = spanText(r.low), b = spanText(r.high)
        guard a != b else { return nil }
        for unit in [" semanas", " dias", " meses"] where a.hasSuffix(unit) && b.hasSuffix(unit) {
            return "entre \(a.dropLast(unit.count)) e \(b)"
        }
        return "entre \(a) e \(b)"
    }
}

/// Where the routine player is: the step it's on and the steps you did (the timer ran to the end, or «Feito»). A
/// skipped step stays pending. What was done is saved once, at the end.
struct RoutinePlayback: Equatable {
    var steps: [RoutineStep]
    var index = 0
    var done: [String: Double] = [:]

    var current: RoutineStep? { steps.indices.contains(index) ? steps[index] : nil }
    var finished: Bool { index >= steps.count }

    mutating func complete(at time: Double = nowMs()) {
        guard let s = current else { return }
        done[s.id] = time
        index += 1
    }

    mutating func skip() {
        guard current != nil else { return }
        index += 1
    }
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

/// Medicine.kind stays a stored tag ("medicine", "supplement"…); this is the name shown
func medicineKindLabel(_ kind: String) -> String {
    ["medicine": "Medicamento", "supplement": "Suplemento", "skincare": "Cuidados de pele", "drops": "Gotas", "other": "Outro"][kind] ?? kind.capitalized
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
            for (t, i, icon) in [("Aparar a barba", 7, "scissors"), ("Cortar as unhas das mãos", 10, "hand.raised"), ("Cortar as unhas dos pés", 28, "figure.walk"), ("Cortar o cabelo", 35, "comb"), ("Arranjar as sobrancelhas", 30, "eye")] {
                save(GroomingItem(title: t, icon: icon, interval: i))
            }
        }
        if all(CareRoutine.self).isEmpty {
            save(CareRoutine(title: "Rotina da noite", icon: "moon.stars", steps: [RoutineStep(title: "Gel de limpeza", seconds: 60), RoutineStep(title: "Esperar, depois sérum", seconds: 60), RoutineStep(title: "Hidratante", seconds: 30)]))
            save(CareRoutine(title: "Rotina da manhã", icon: "sun.max", steps: [RoutineStep(title: "Um copo cheio de água", seconds: 30), RoutineStep(title: "Gel de limpeza", seconds: 45), RoutineStep(title: "Protetor solar", seconds: 30)]))
        }
    }

    var groomingDue: [GroomingItem] { all(GroomingItem.self).filter { $0.isDue(on: Day.today) }.sorted { $0.freshness < $1.freshness } }

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
        // your pick wins, and the reason still shows when it differs from what Cadence would do
        let why = picked == nil || picked == auto.0 ? auto.1 : "Escolheste tu. O Cadence diria \(auto.0 == .tonight ? "esta noite" : "amanhã de manhã"): \(auto.1.prefix(1).lowercased() + String(auto.1.dropFirst()))"
        if when == .morning { return (.morning, Day.at(profile.wakeMinute + 20, on: tomorrow), why) }
        // training still to come today: the shower is the one right after it, and that session will count
        if let t = trainingSlot(on: day), !t.done, day != Day.today || t.end > Day.minuteOfDay() {
            return (.tonight, Day.at(t.end, on: day), "Logo depois de \(t.title), que conta como o duche de hoje")
        }
        let m = Engine.outside(min(plan.perform - 90, plan.windDown - 15), busy: busy(on: day))
        return (.tonight, Day.at(max(m, day == Day.today ? Day.minuteOfDay() + 5 : 0), on: day), why)
    }

    /// The warmest it feels outside between lights out and waking, from the forecast
    func nightFeels(from: Int, to: Int) -> Double? {
        WeatherStore.shared.today?.hours.filter { $0.minute >= from && $0.minute <= to }.map(\.feels).max()
    }

    /// Set once in Settings, kept on this phone only: it rings the "unpack the gym bag" reminder on arriving
    var homeCoordinate: CLLocationCoordinate2D? {
        let d = UserDefaults.standard
        guard d.object(forKey: "homeLat") != nil else { return nil }
        return CLLocationCoordinate2D(latitude: d.double(forKey: "homeLat"), longitude: d.double(forKey: "homeLon"))
    }

    func setHomeHere() async {
        let here = await WeatherStore.shared.currentLocation()
        UserDefaults.standard.set(here.coordinate.latitude, forKey: "homeLat")
        UserDefaults.standard.set(here.coordinate.longitude, forKey: "homeLon")
        Reminders.shared.reschedule()
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
        if let cached = busyCache[day] { return cached }
        let list = commutes(on: day).map { Busy(start: $0.leave, end: $0.arrive, title: $0.title) }
            + Agenda.shared.events(on: day).map { Busy(start: $0.startMinute, end: $0.endMinute, title: $0.title) }
        busyCache[day] = list
        return list
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
            out.append((day: d, bedtime: base + shift, note: diff > 0 ? "Luz forte logo de manhã, pouca luz depois do pôr do sol; jantar mais cedo" : "Luz forte ao fim do dia, manhãs com pouca luz"))
        }
        out.append((day: t.start, bedtime: base, note: "No avião: dorme na noite de \(t.destination), água a cada hora, sem álcool"))
        out.append((day: Day.add(1, to: t.start), bedtime: base, note: "Primeiro dia lá: luz natural na manhã local, refeições à hora local"))
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

/// The packing items stay stored in Trip.packed as the English words above (so what's ticked stays ticked); this is
/// the text shown for each
func packingLabel(_ item: String) -> String {
    let fixed = ["Passport / ID": "Passaporte / cartão de cidadão", "Phone charger": "Carregador do telemóvel", "Fitbit Air charger": "Carregador da Fitbit Air",
                 "Toothbrush and paste": "Escova e pasta de dentes", "Gym clothes": "Roupa de treino", "Trainers": "Ténis",
                 "Eye mask and earplugs": "Máscara de dormir e tampões para os ouvidos"]
    if let pt = fixed[item] { return pt }
    for (en, pt) in [(" × underwear", " × roupa interior"), (" × socks", " × meias"), (" × T-shirts", " × t-shirts")] where item.hasSuffix(en) {
        return String(item.dropLast(en.count)) + pt
    }
    return item // a medicine's line ("name: 4 doses") reads the same in Portuguese
}

// MARK: - Higiene (phase 2.5): routines by day and step, the routine of the moment, frequencies and products

@MainActor
extension Store {
    // MARK: Routines

    func routineLog(_ routine: CareRoutine, on day: String = Day.today) -> RoutineLog? {
        record(RoutineLog.self, CareRules.logId(routine: routine.id, day: day))
    }

    /// The steps of the routine you confirmed that day, and when (only steps it still has)
    func doneSteps(_ routine: CareRoutine, on day: String = Day.today) -> [String: Double] {
        let known = Set(routine.steps.map(\.id))
        return (routineLog(routine, on: day)?.steps ?? [:]).filter { known.contains($0.key) }
    }

    /// What's still to confirm. Nothing is marked because the hour passed: a step you didn't confirm stays pending.
    func pendingSteps(_ routine: CareRoutine, on day: String = Day.today) -> [RoutineStep] {
        let done = doneSteps(routine, on: day)
        return routine.steps.filter { done[$0.id] == nil }
    }

    /// Confirms steps, one or several at once, each with its time; a step already confirmed keeps its first time.
    /// Returns the day's log as it was before, for Desfazer (restoreRoutineLog).
    @discardableResult
    func confirmSteps(_ times: [String: Double], of routine: CareRoutine, on day: String = Day.today) -> RoutineLog? {
        let id = CareRules.logId(routine: routine.id, day: day)
        let before = record(RoutineLog.self, id)
        var log = before ?? RoutineLog(id: id, routineId: routine.id, date: day)
        let known = Set(routine.steps.map(\.id))
        for (step, time) in times where known.contains(step) && log.steps[step] == nil { log.steps[step] = time }
        if !log.steps.isEmpty && log != before { save(log) }
        return before
    }

    /// «Não fiz»: takes one step's confirmation away (the log goes when nothing is left in it). Returns the log before.
    @discardableResult
    func unconfirmStep(_ step: String, of routine: CareRoutine, on day: String = Day.today) -> RoutineLog? {
        let id = CareRules.logId(routine: routine.id, day: day)
        guard let before = record(RoutineLog.self, id) else { return nil }
        guard before.steps[step] != nil else { return before }
        var log = before
        log.steps[step] = nil
        if log.steps.isEmpty { put(RoutineLog.kind, id, nil) } else { save(log) }
        return before
    }

    /// Desfazer: the routine's day goes back to exactly how it was (that log, or none)
    func restoreRoutineLog(_ previous: RoutineLog?, routine: CareRoutine, on day: String) {
        let id = CareRules.logId(routine: routine.id, day: day)
        if let previous { save(previous) } else if record(RoutineLog.self, id) != nil { put(RoutineLog.kind, id, nil) }
    }

    /// The routines of the moment (the morning's before 14:00, the night's from then; a routine with its own time counts
    /// in the half that time falls in), earliest first
    func routinesOfTheMoment(minute: Int = Clock.minute()) -> [CareRoutine] {
        let now = CareRules.moment(at: minute)
        return all(CareRoutine.self).filter { !$0.steps.isEmpty && CareRules.moment(of: $0) == now }
            .sorted { ($0.minute ?? -1, $0.title) < ($1.minute ?? -1, $1.title) }
    }

    /// The routine of the moment that still has steps to confirm today, or nil. Phase 2.9 shows it in «Agora».
    func routineDueNow(minute: Int = Clock.minute(), day: String = Day.today) -> CareRoutine? {
        guard profile.on("care") else { return nil }
        return routinesOfTheMoment(minute: minute).first { !pendingSteps($0, on: day).isEmpty }
    }

    /// The routine «Agora» asks for: of the moment, in its hours, with steps to confirm, and not put away today
    func agoraRoutine(minute: Int, day: String = Day.today) -> CareRoutine? {
        guard profile.on("care") else { return nil }
        return routinesOfTheMoment(minute: minute).first {
            CareRules.asksInAgora($0, minute: minute) && !pendingSteps($0, on: day).isEmpty
                && record(NowDismiss.self, NowRule.dismissKey(day: day, event: CareRules.agoraKey($0))) == nil
        }
    }

    /// «Hoje não», or finishing it with steps skipped: «Agora» stops asking today. Nothing is confirmed: Higiene still has it to do.
    func skipRoutineToday(_ routine: CareRoutine, day: String = Day.today, undoable: Bool = true) {
        guard canChange else { return }
        let event = CareRules.agoraKey(routine)
        let id = NowRule.dismissKey(day: day, event: event)
        let before = records(NowDismiss.kind)[id]
        save(NowDismiss(id: id, date: day, event: event, action: NowDismiss.gone))
        guard undoable else { return }
        UndoCenter.shared.show("Hoje já não pergunto") { [weak self] in self?.put(NowDismiss.kind, id, before) }
    }

    /// Of the last `days` days up to `day`: how many had every step confirmed and how many only some
    func routineConsistency(_ routine: CareRoutine, days: Int = 14, upTo day: String = Day.today) -> (full: Int, partial: Int) {
        CareRules.consistency(steps: routine.steps.map(\.id), days: (0..<max(1, days)).map { doneSteps(routine, on: Day.add(-$0, to: day)) })
    }

    // MARK: Grooming

    /// What's due today or tomorrow, among what you've done before (never registered shows in Frequências)
    var groomingSoon: [GroomingItem] {
        let today = Day.today, tomorrow = Day.add(1, to: Day.today)
        return all(GroomingItem.self).filter { $0.last != nil && ($0.isDue(on: today) || $0.isDue(on: tomorrow)) }.sorted { $0.freshness < $1.freshness }
    }

    /// Concluído: done today, so the interval starts again from today. Returns the item before, for Desfazer.
    @discardableResult
    func markGroomingDone(_ g: GroomingItem, on day: String = Day.today) -> GroomingItem? {
        guard var x = record(GroomingItem.self, g.id), !x.history.contains(day) else { return nil }
        let before = x
        x.history.append(day)
        save(x)
        return before
    }

    /// Aceitar on the learned interval: only then does the frequency change. Returns the item before, for Desfazer.
    @discardableResult
    func acceptInterval(_ days: Int, for g: GroomingItem) -> GroomingItem? {
        guard var x = record(GroomingItem.self, g.id), days > 0 else { return nil }
        let before = x
        x.interval = days
        x.weekdays = nil
        save(x)
        return before
    }

    // MARK: Products

    /// Each use of a product you confirmed: the confirmed steps that use it, with when
    func productUses(_ p: CareProduct) -> [Double] {
        let routines = Dictionary(all(CareRoutine.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Double] = []
        for log in all(RoutineLog.self) {
            guard let r = routines[log.routineId] else { continue }
            for s in r.steps where s.productId == p.id {
                if let t = log.steps[s.id] { out.append(t) }
            }
        }
        return out.sorted()
    }

    func refillEstimate(_ p: CareProduct, now: Double = nowMs()) -> CareRules.Refill? { CareRules.refill(p, uses: productUses(p), now: now) }

    /// The routines a product is in
    func routines(using p: CareProduct) -> [CareRoutine] {
        all(CareRoutine.self).filter { r in r.steps.contains { $0.productId == p.id } }.sorted { $0.title < $1.title }
    }

    /// "Manhã e noite", "Manhã", "Noite", or the routines' names when they have no moment; "" when it's in none
    func productMoments(_ p: CareProduct) -> String {
        let rs = routines(using: p)
        let moments = Set(rs.compactMap { CareRules.moment(of: $0) })
        if moments.count == 2 { return "Manhã e noite" }
        if moments.contains(.morning) { return "Manhã" }
        if moments.contains(.night) { return "Noite" }
        return rs.map(\.title).joined(separator: ", ")
    }

    /// «Muito», «Metade» or «Pouco»: what's left now, which the estimate then starts from. Returns the product before.
    @discardableResult
    func setLevel(_ share: Double, of p: CareProduct, at time: Double = nowMs()) -> CareProduct? {
        guard var x = record(CareProduct.self, p.id) else { return nil }
        let before = x
        x.left = share
        x.leftAt = time
        save(x)
        return before
    }

    /// Whether the product is really on your shopping list, by name (Store.productKey): an item of yours not yet
    /// bought, which is also what a suggestion you accepted becomes. A line the app only works out (pantry, recipes,
    /// medicines, the brush head) is a suggestion until you accept it (D27) and doesn't count, so «Adicionar às compras»
    /// stays on offer. addToShopping (Kitchen.swift) checks it, and the suggestion to add hides while it's true.
    func isOnShoppingList(_ name: String) -> Bool {
        let key = Store.productKey(name)
        guard !key.isEmpty else { return false }
        return all(ShoppingItem.self).contains { !$0.bought && Store.productKey($0.name) == key }
    }
}
