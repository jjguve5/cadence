// Phase 2.9 · Noite, Antes de sair e Antes de dormir (design v17: N_AntesDeSair, N_AntesDeSairPronto, N_HojeNoite,
// N_PrepAmanha, N_AntesDeDormir, N_AntesDeDormirTarde, N_Leitura, N_BoaNoite, N_SonoManha; decisions 9–16 and 68–80).
// The records and the rules, pure where they can be (LeaveRules, NightRules), then the Store glue. Every record here
// is new, has an id of [A-Za-z0-9_.:-] up to 80 characters and an object as its value: an older build keeps it as it
// is, like any record it doesn't know, and nothing that was saved before is rewritten.
import Foundation

// MARK: - Antes de sair: records

/// One thing to take when you leave. The three the app starts with (keys and wallet always, the gym bag on training
/// days, the umbrella when rain is forecast) live in code and are saved only when you edit or remove one; yours are
/// saved when you add them. Removing keeps the record with `removed`, so a rule's item never comes back by itself.
struct LeaveItem: Record, Equatable {
    static let kind = "leaveItem"
    /// When it's on the list. Plain strings, so a value a later build adds can't make this one protect the file; a
    /// value this build doesn't know counts as «sempre», so an item is never lost
    static let always = "always", training = "training", rain = "rain"
    var id: String // "keys", "gymBag", "umbrella" for the app's three; "mine-<uuid>" for yours
    var title: String
    var when: String = LeaveItem.always
    var optional: Bool? = nil // «Se quiseres»; nil is «Essencial»
    var removed: Bool? = nil
    var at = nowMs()
}

/// A day's Antes de sair: what you marked as taken, when you said «Concluído», and whether you closed the line left in
/// Today after leaving. One record per day, id = the day.
struct LeaveDay: Record, Equatable {
    static let kind = "leaveDay"
    var id: String
    var date: String
    var seen: [String] = [] // LeaveItem ids
    var ready: Double? = nil // «Concluído» (ms)
    var closed: Bool? = nil // the line in Today after leaving, closed
    var at = nowMs()
}

/// A departure Antes de sair gets you ready for: a calendar event with a place (or one a regular trip goes to), a
/// regular trip on its day, or training (at the gym, so out of the house)
struct LeaveDeparture: Equatable {
    var title: String
    var leave: Int // when to leave, minutes after midnight
}

/// One line of the list as shown today
struct LeaveEntry: Identifiable, Equatable {
    var item: LeaveItem
    var seen: Bool
    var note: String // why it's there today
    var state: DataState? = nil // what the app knows about it (the bag packed last night: still to take)
    var source: String? = nil // where the reason came from ("Open-Meteo")
    var id: String { item.id }
}

// MARK: - Antes de sair: rules

enum LeaveRules {
    /// Antes de sair shows from this many minutes before leaving (decision of phase 2.9)
    static let window = 60
    /// The optional reminder at the time to leave (design: «Lembrar às 8:15»), a setting of this iPhone
    static let reminderKey = "leave.remind"

    static let builtIns: [LeaveItem] = [
        LeaveItem(id: "keys", title: "Chaves e carteira", when: LeaveItem.always, at: 0),
        LeaveItem(id: "gymBag", title: "Saco do ginásio", when: LeaveItem.training, at: 0),
        LeaveItem(id: "umbrella", title: "Guarda-chuva", when: LeaveItem.rain, at: 0),
    ]

    static func isBuiltIn(_ id: String) -> Bool { builtIns.contains { $0.id == id } }

    /// The list you keep: the app's three (as you edited them), then yours in the order you added them. What you
    /// removed is gone, and stays gone.
    static func list(saved: [LeaveItem]) -> [LeaveItem] {
        let byId = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.at >= b.at ? a : b })
        let base = builtIns.map { byId[$0.id] ?? $0 }
        let mine = byId.values.filter { !isBuiltIn($0.id) }.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
        return (base + mine).filter { $0.removed != true }
    }

    /// Whether an item is on today's list: the gym bag only on training days, the umbrella only with rain forecast
    static func applies(_ item: LeaveItem, training: Bool, rain: Bool) -> Bool {
        switch item.when {
        case LeaveItem.training: return training
        case LeaveItem.rain: return rain
        default: return true
        }
    }

    /// The rule as the list shows it: "sempre", "em dias de treino fora de casa", "opcional · quando há chuva prevista"
    static func whenLabel(_ item: LeaveItem) -> String {
        let base: String
        switch item.when {
        case LeaveItem.training: base = "em dias de treino fora de casa"
        case LeaveItem.rain: base = "quando há chuva prevista"
        default: base = "sempre"
        }
        return item.optional == true ? "opcional · " + base : base
    }

    /// The departure to get ready for now: from 60 min before the time to leave until it; the earliest first
    static func next(_ list: [LeaveDeparture], minute: Int) -> LeaveDeparture? {
        list.filter { minute <= $0.leave && $0.leave - minute <= window }.min { ($0.leave, $0.title) < ($1.leave, $1.title) }
    }

    /// The last departure whose time to leave has passed
    static func passed(_ list: [LeaveDeparture], minute: Int) -> LeaveDeparture? {
        list.filter { $0.leave < minute }.max { ($0.leave, $0.title) < ($1.leave, $1.title) }
    }

    /// «Agora», step 3 (decision D3): a departure within 60 min and something on the list still to see
    static func isStep(_ departures: [LeaveDeparture], minute: Int, pending: Int) -> Bool {
        pending > 0 && next(departures, minute: minute) != nil
    }

    /// The one line left in Today after leaving: a departure has passed with something not seen, you haven't closed it
    /// or said «Concluído», and no other departure is coming up within the hour (then the step shows instead). It is a
    /// line, never a notification, and nothing on the list is marked by itself.
    static func showsLine(_ departures: [LeaveDeparture], minute: Int, pending: Int, day: LeaveDay?) -> Bool {
        pending > 0 && passed(departures, minute: minute) != nil && next(departures, minute: minute) == nil
            && day?.closed != true && day?.ready == nil
    }

    /// "guarda-chuva, saco do ginásio e chaves e carteira"
    static func names(_ titles: [String]) -> String {
        let low = titles.map { $0.prefix(1).lowercased() + String($0.dropFirst()) }
        guard let last = low.last else { return "" }
        return low.count == 1 ? last : low.dropLast().joined(separator: ", ") + " e " + last
    }

    /// The reminder's text, or the part it adds to a regular trip's «Sai agora»
    static func reminderBody(_ titles: [String]) -> String { "Antes de sair: " + names(titles) + "." }

    /// On unless you turn it off, as the design shows it
    static var reminderOn: Bool { UserDefaults.standard.object(forKey: reminderKey) as? Bool ?? true }

    /// "1 por ver", "3 por ver"
    static func pendingText(_ n: Int) -> String { "\(n) por ver" }
}

// MARK: - The night: records

/// The gym bag for a training day, packed the night before (Preparar amanhã). Its own record, id = the training day.
/// It reaches Antes de sair as packed: packed is not taken, so the bag stays to see there.
struct GymBagPack: Record, Equatable {
    static let kind = "gymBagPacked"
    var id: String
    var date: String
    var items: [String] = [] // what you put in (BagItem ids)
    var done = false // every item in, or «Pus os N no saco»
    var at = nowMs()
}

/// «Dispensar hoje» on Preparar amanhã: the evening's preparation set aside, id = the evening
struct NightPrep: Record, Equatable {
    static let kind = "nightPrep"
    var id: String
    var date: String
    var dismissed = true
    var at = nowMs()
}

/// «Vou dormir»: the intention to sleep and when you said it, id = the evening. Never the start of sleep (that comes
/// from the band in the morning) and never an answer to a habit.
struct SleepIntent: Record, Equatable {
    static let kind = "sleepIntent"
    var id: String
    var date: String
    var minute: Int // on the evening's clock (past 24:00 after midnight)
    var at = nowMs()
}

/// The reading planned for the evening, saved when you start it from the night. The reading done is a ReadingSession,
/// a different record: planned and done are never the same thing.
struct ReadingPlan: Record, Equatable {
    static let kind = "readingPlan"
    var id: String
    var date: String
    var minutes: Int
    var start: Int // on the evening's clock
    var until: Int
    var at = nowMs()
}

/// The night's times as you gave them («Corrigir», or «Sem pulseira?»), id = the morning (as HealthDay.date). The
/// band's sleep is never changed: this sits next to it, marked as yours.
struct SleepManual: Record, Equatable {
    static let kind = "sleepManual"
    var id: String
    var date: String
    var bed: Int // minutes after midnight
    var wake: Int
    var source = PromiseLog.byYou
    var at = nowMs()
}

/// One thing for the gym bag
struct BagItem: Identifiable, Equatable {
    var id: String
    var title: String
}

/// The night's steps, in the order you prefer them (decision 74)
enum NightStep: String, CaseIterable {
    case teeth, prepare, read, sleep

    var label: String {
        switch self {
        case .teeth: return "Dentes"
        case .prepare: return "Preparar amanhã"
        case .read: return "Ler"
        case .sleep: return "Dormir"
        }
    }
}

/// The night as it stands: the steps that have something to do, the ones resolved, and the one for now. Resolved is
/// not done: `done` moves the sequence on with any answer, and `skipped` keeps the ones answered «Não fiz» or «Não se
/// aplica», which are never shown as «feito».
struct NightStatus: Equatable {
    var steps: [NightStep]
    var done: Set<NightStep>
    var late = false
    var skipped: [NightStep: ReviewAnswer] = [:]

    /// The step for now. After «Vou dormir», none; when it's late, the short version (Dormir) straight away
    var current: NightStep? {
        if done.contains(.sleep) { return nil }
        if late { return .sleep }
        return steps.first { !done.contains($0) }
    }

    /// What VoiceOver says for a step: "Dentes, feito", "Dentes, não fiz", "Dentes, não se aplica", "Ler, agora"
    func spoken(_ step: NightStep) -> String {
        let state: String
        if let answer = skipped[step] { state = answer.label.lowercased() }
        else if done.contains(step) { state = "feito" }
        else if current == step { state = "agora" }
        else { state = "depois" }
        return step.label + ", " + state
    }
}

/// What the day held, for «O dia» on the night card
struct NightDaySummary: Equatable {
    var imported: [String] = [] // answered from the band
    var yours: [String] = [] // answered by you
    var open: [String] = [] // past their time, with no answer: «por confirmar», never «não feito»
    var noWater = false
    var noFood = false
    var isEmpty: Bool { imported.isEmpty && yours.isEmpty && open.isEmpty && !noWater && !noFood }
}

// MARK: - The night: rules

enum NightRules {
    /// The night starts an hour before wind-down and ends two hours before you wake
    static let lead = 60
    /// The short version shows 30 min past the planned lights out (decision of phase 2.9)
    static let lateAfter = 30
    /// The gym bag's basics (design N_PrepAmanha), next to the training clothes that are available
    static let bagBasics = [BagItem(id: "towel", title: "Toalha"), BagItem(id: "bottle", title: "Garrafa"),
                            BagItem(id: "lock", title: "Cadeado"), BagItem(id: "headphones", title: "Auscultadores")]

    /// A minute on the evening's clock: after midnight and before noon it counts on from 24:00 (0:30 is 24:30)
    static func evening(_ minute: Int) -> Int { minute < 12 * 60 ? minute + 1440 : minute }

    /// The night: from an hour before wind-down until two hours before waking. `windDown` is the evening plan's
    /// (SleepPlan.windDown, which can pass 24:00); `wake` is your wake time.
    static func isNight(minute: Int, windDown: Int, wake: Int) -> Bool {
        let e = evening(minute)
        return e >= windDown - lead && e < wake + 1440 - 120
    }

    /// Late: more than 30 min past the planned lights out
    static func isLate(minute: Int, lightsOut: Int) -> Bool { evening(minute) > lightsOut + lateAfter }

    /// The morning, for «Como dormiste»: from two hours before you wake until 11:00 (or two hours after a late wake)
    static func isMorning(minute: Int, wake: Int) -> Bool { minute >= wake - 120 && minute < max(11 * 60, wake + 120) }

    /// The night's steps. nil means nothing to do there today, so the step is hidden; sleep is always there. `skipped`
    /// says which resolved steps were answered «Não fiz» or «Não se aplica» instead of done.
    static func status(teeth: Bool?, prepare: Bool?, read: Bool?, sleep: Bool, late: Bool = false, skipped: [NightStep: ReviewAnswer] = [:]) -> NightStatus {
        let all: [(NightStep, Bool?)] = [(.teeth, teeth), (.prepare, prepare), (.read, read), (.sleep, Optional(sleep))]
        var steps: [NightStep] = []
        var done: Set<NightStep> = []
        for (step, maybe) in all {
            guard let state = maybe else { continue }
            steps.append(step)
            if state { done.insert(step) }
        }
        return NightStatus(steps: steps, done: done, late: late, skipped: skipped.filter { done.contains($0.key) })
    }

    /// From when, on its own day, a brushing or a reading counts for the night (audit B3-E4)
    static let teethFrom = 14 * 60, readFrom = 18 * 60
    /// The morning when there's no wake time to go by
    static let morningWithoutWake = 5 * 60

    /// After midnight the night still belongs to the evening before (Store.nightDay). Something you do counts for a
    /// night on the night's own day from `from`, or on the next calendar day before the morning: your wake time, or
    /// 05:00 without one.
    static func inNight(date: String, minute: Int, night: String, from: Int, wake: Int?) -> Bool {
        if date == night { return minute >= from }
        return date == Day.add(1, to: night) && minute < (wake ?? morningWithoutWake)
    }

    /// How a night step ended, from what you did and how its habits were answered. Done when you did it, or when every
    /// habit is answered and one of them «feito»; with every habit answered and none done, «Não se aplica» if all of
    /// them were, otherwise «Não fiz». nil while one is still open, or with nothing to go by.
    static func outcome(did: Bool, answers: [ReviewAnswer]) -> ReviewAnswer? {
        if did { return .done }
        guard !answers.isEmpty, !answers.contains(.notConfirmed) else { return nil }
        if answers.contains(.done) { return .done }
        return answers.allSatisfy { $0 == .notApplicable } ? .notApplicable : .notDone
    }

    /// The tag of an answer that isn't «feito», with the end-of-day review's states (2.8): «Não fiz» or «Não se aplica».
    /// nil for done and for no answer.
    static func skipTag(_ answer: ReviewAnswer?) -> (state: DataState, text: String)? {
        switch answer {
        case .notDone?: return (DataState.ignored, ReviewAnswer.notDone.label)
        case .notApplicable?: return (DataState.unavailable, ReviewAnswer.notApplicable.label)
        default: return nil
        }
    }

    /// «Agora» at night follows the night's steps, except for a departure, a workout in progress or Antes de sair,
    /// which keep their place (decision D3)
    static func takesAgora(_ step: NowStep?) -> Bool {
        switch step {
        case nil, .habit?, .routine?: return true
        default: return false
        }
    }

    /// The reading suggested tonight: until 5 min before lights out, at most 30 min; less than 10 min, none
    static func reading(minute: Int, lightsOut: Int) -> (minutes: Int, until: Int)? {
        let e = evening(minute)
        let m = min(30, lightsOut - 5 - e)
        return m >= 10 ? (m, e + m) : nil
    }

    /// How long you take to fall asleep, from the band's nights (the middle one of at least three), or nil
    static func fallAsleep(_ nights: [Int]) -> Int? {
        guard nights.count >= 3 else { return nil }
        let s = nights.sorted()
        return s[s.count / 2]
    }

    /// The «Porquê» of tonight's plan: what you need and how long you take to fall asleep, when the band says
    static func planWhy(need: Int, fallAsleep: Int?) -> String {
        let asleep = fallAsleep.map { "costumas adormecer cerca de \($0) min depois de apagar a luz" } ?? "contamos 15 min para adormecer"
        return "precisas de \(duration(need)); \(asleep)."
    }

    /// "23:00", "23h00", "23h", "2300", "7" → minutes after midnight. Anything else is nil: an hour is never guessed.
    static func parseClock(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "h", with: ":").replacingOccurrences(of: ".", with: ":")
        var parts = t.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1, let only = parts.first, (3...4).contains(only.count), only.allSatisfy({ $0.isASCII && $0.isNumber }) {
            parts = [String(only.dropLast(2)), String(only.suffix(2))]
        }
        guard (1...2).contains(parts.count), let h = Int(parts[0]), (0...23).contains(h) else { return nil }
        let minutes: Int? = parts.count == 2 ? (parts[1].isEmpty ? 0 : Int(parts[1])) : 0
        guard let m = minutes, (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Minutes between going to bed and waking, across midnight
    static func span(bed: Int, wake: Int) -> Int { ((wake - bed) % 1440 + 1440) % 1440 }

    /// Tomorrow's weather from the forecast: rain and the temperatures over the hours you're out (from waking to
    /// 22:00), and the layers, as the outfit counts them. `offset` is how many days after the forecast's first day
    /// tomorrow is (1, or 0 after midnight). Nil without those hours.
    static func tomorrowWeather(_ hours: [HourWeather], wake: Int, offset: Int = 1) -> (rain: Bool, layers: Int, text: String)? {
        let base = offset * 1440
        let out = hours.filter { $0.minute >= base + wake && $0.minute < base + 22 * 60 }
        guard let low = out.map(\.temp).min(), let high = out.map(\.temp).max() else { return nil }
        let wet = out.filter { $0.rain >= 50 }
        let feels = out.map(\.feels).min() ?? 15
        let layers = feels >= 22 ? 1 : feels >= 16 ? 2 : feels >= 9 ? 3 : 4
        let lo = Int(low.rounded()), hi = Int(high.rounded())
        let temps = lo == hi ? "\(lo) °C" : "\(lo)–\(hi) °C"
        guard let first = wet.first, let last = wet.last else { return (false, layers, "sem chuva prevista · " + temps) }
        let from = first.minute - base, to = last.minute - base + 60
        let rain = from <= wake + 60 ? "chuva até às \(clock(to))" : "chuva das \(clock(from)) às \(clock(to))"
        return (true, layers, rain + " · " + temps)
    }

    /// Where a habit's answer came from, as its label shows it: «Importado» from the band, «Confirmado» when it was
    /// yours. An answer with no source has no label: no label never means confirmed.
    static func answerState(_ origin: AnswerOrigin?) -> DataState? {
        switch origin {
        case .you?: return .confirmed
        case .imported?: return .imported
        default: return nil
        }
    }

    /// A bedtime habit's label in the morning: where the answer came from, unless it was «Não fiz» or «Não se aplica»,
    /// which is what it then says (never «Confirmado»). nil without a known source, as answerState.
    static func answerTag(_ origin: AnswerOrigin?, _ answer: ReviewAnswer) -> (state: DataState, text: String?)? {
        guard let state = answerState(origin) else { return nil }
        if let skip = skipTag(answer) { return (skip.state, skip.text) }
        return (state, nil)
    }

    /// About how long the short version takes: brushing (2 min) if it's still to do, and the night routine's step
    static func shortMinutes(teeth: Bool, stepSeconds: Int?) -> Int {
        let s = (teeth ? 120 : 0) + (stepSeconds ?? 0)
        return max(1, Int((Double(s) / 60).rounded(.up)))
    }

    /// "Amanhã: trabalho às 9:00 · treino às 18:30 · saco pronto"
    static func tomorrowText(_ parts: [String]) -> String {
        parts.isEmpty ? "Amanhã: nada marcado" : "Amanhã: " + parts.joined(separator: " · ")
    }

    /// "hoje às 21:52", "ontem às 21:52", or the date, for a time (ms) seen from `day`
    static func whenText(_ ms: Double, from day: String) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000)
        let key = Day.key(date), time = clock(Day.minuteOfDay(date))
        if key == day { return "hoje às \(time)" }
        if key == Day.add(-1, to: day) { return "ontem às \(time)" }
        return date.formatted(.dateTime.day().month()) + " às \(time)"
    }

    /// The formal words the outfit looks for in the calendar (Store.outfit)
    static let formal = ["seminar", "meeting", "presentation", "interview", "defesa", "reunião"]
}

// MARK: - Store glue

@MainActor
extension Store {
    // MARK: Antes de sair

    /// Your list: the app's three as you left them, then yours, without what you removed
    var leaveItems: [LeaveItem] { LeaveRules.list(saved: all(LeaveItem.self)) }

    /// A day's departures, earliest first: calendar events you leave for (a place, or a regular trip that matches),
    /// except one you answered «Já não vou», regular trips, and training (out of the house, 30 min before it starts).
    /// `events` is for tests.
    func leaveDepartures(on day: String = Day.today, events: [CalendarEvent]? = nil) -> [LeaveDeparture] {
        var out = nowDepartures(events: events, day: day)
            .filter { record(NowDismiss.self, NowRule.dismissKey(day: day, event: $0.eventId))?.action != NowDismiss.gone }
            .map { LeaveDeparture(title: $0.title, leave: $0.leave) }
        out += commutes(on: day).map { LeaveDeparture(title: $0.title, leave: $0.leave) }
        if profile.on("training"), gymBag(on: day).needed, let t = trainingSlot(on: day), !t.done {
            out.append(LeaveDeparture(title: t.title, leave: t.start - NowRule.defaultLead))
        }
        return out.sorted { ($0.leave, $0.title) < ($1.leave, $1.title) }
    }

    func leaveDay(_ day: String = Day.today) -> LeaveDay? { record(LeaveDay.self, day) }

    func gymBagPack(for day: String) -> GymBagPack? { record(GymBagPack.self, day) }

    /// The day's list: what applies (the gym bag on training days; the umbrella when rain is forecast, which is only
    /// known for today), what you've seen, and why each is there
    func leaveEntries(on day: String = Day.today) -> [LeaveEntry] {
        let training = profile.on("training") && gymBag(on: day).needed
        let call = day == Day.today ? weatherCall() : nil
        let rain = call?.umbrella ?? false
        let seen = Set(leaveDay(day)?.seen ?? [])
        let pack = gymBagPack(for: day)
        return leaveItems.filter { LeaveRules.applies($0, training: training, rain: rain) }.map { item -> LeaveEntry in
            var entry = LeaveEntry(item: item, seen: seen.contains(item.id), note: item.optional == true ? "opcional" : "")
            if item.id == "keys" { entry.note = "o que levas sempre · confirmas tu" }
            switch item.when {
            case LeaveItem.rain:
                entry.note = "chuva" + (call?.rainWindow.map { " \($0)" } ?? " prevista")
                entry.source = "Open-Meteo"
            case LeaveItem.training:
                if item.id == "gymBag", let pack, pack.done {
                    entry.note = "preparado \(NightRules.whenText(pack.at, from: day)) · falta levá-lo"
                    entry.state = .pending
                } else if entry.note.isEmpty {
                    entry.note = "dia de treino"
                }
            default: break
            }
            return entry
        }
    }

    /// The line left in Today after leaving (see LeaveRules.showsLine)
    func leaveLineShows(minute: Int, day: String = Day.today) -> Bool {
        let pending = leaveEntries(on: day).filter { !$0.seen }.count
        return LeaveRules.showsLine(leaveDepartures(on: day), minute: minute, pending: pending, day: leaveDay(day))
    }

    /// Tapping an item marks it as taken; tapping it again, as not yet. Desfazer puts the day back as it was.
    func toggleLeaveSeen(_ entry: LeaveEntry, on day: String = Day.today) {
        guard canChange else { return }
        let before = leaveDay(day)
        var d = before ?? LeaveDay(id: day, date: day)
        if let i = d.seen.firstIndex(of: entry.id) { d.seen.remove(at: i) } else { d.seen.append(entry.id) }
        d.at = nowMs()
        save(d)
        UndoCenter.shared.show(entry.seen ? "\(entry.item.title) · por ver" : "\(entry.item.title) · levado") { [weak self] in
            self?.restoreLeaveDay(before, day: day)
        }
    }

    /// «Concluído»: what's left is marked as taken, and the list shows «Pronto para sair». Desfazer undoes both.
    func finishLeaving(on day: String = Day.today) {
        guard canChange else { return }
        let before = leaveDay(day)
        var d = before ?? LeaveDay(id: day, date: day)
        let left = leaveEntries(on: day).filter { !$0.seen }.map(\.id)
        for id in left where !d.seen.contains(id) { d.seen.append(id) }
        d.ready = nowMs()
        d.at = nowMs()
        save(d)
        UndoCenter.shared.show(left.count == 1 ? "1 item marcado como levado" : "\(left.count) itens marcados como levados") { [weak self] in
            self?.restoreLeaveDay(before, day: day)
        }
    }

    /// Closes the line left in Today after leaving; it doesn't come back that day
    func closeLeaveLine(on day: String = Day.today) {
        guard canChange else { return }
        let before = leaveDay(day)
        var d = before ?? LeaveDay(id: day, date: day)
        d.closed = true
        d.at = nowMs()
        save(d)
        UndoCenter.shared.show("Linha fechada") { [weak self] in self?.restoreLeaveDay(before, day: day) }
    }

    func restoreLeaveDay(_ before: LeaveDay?, day: String) {
        if let before { save(before) } else if record(LeaveDay.self, day) != nil { put(LeaveDay.kind, day, nil) }
    }

    /// Adds or edits an item of the list, with Desfazer
    func saveLeaveItem(_ item: LeaveItem) {
        guard canChange else { return }
        let before = record(LeaveItem.self, item.id)
        var x = item
        x.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !x.title.isEmpty else { return }
        save(x)
        let added = before == nil && !LeaveRules.isBuiltIn(item.id)
        UndoCenter.shared.show(added ? "\(x.title) · adicionado à lista" : "\(x.title) · guardado") { [weak self] in
            self?.restoreLeaveItem(before, id: item.id)
        }
    }

    /// Removes an item: it's kept as removed, so the rule never puts it back. Desfazer brings it back.
    func removeLeaveItem(_ item: LeaveItem) {
        guard canChange else { return }
        let before = record(LeaveItem.self, item.id)
        var x = item
        x.removed = true
        save(x)
        UndoCenter.shared.show("\(item.title) · removido da lista") { [weak self] in self?.restoreLeaveItem(before, id: item.id) }
    }

    func restoreLeaveItem(_ before: LeaveItem?, id: String) {
        if let before { save(before) } else if record(LeaveItem.self, id) != nil { put(LeaveItem.kind, id, nil) }
    }

    // MARK: The gym bag

    /// What goes in the bag for a training day: the training clothes that are available (clean, not in the wash), then
    /// the basics; and the training clothes that aren't available, to show where they are
    func bagItems(for day: String) -> (items: [BagItem], unavailable: [Garment]) {
        let kit = garments.filter { $0.type == "gym" }.sorted { $0.name < $1.name }
        let available = kit.filter { $0.stage == .available }
        return (available.map { BagItem(id: "g." + $0.id, title: $0.name) } + NightRules.bagBasics, kit.filter { $0.stage != .available })
    }

    /// Puts one item in the bag, or takes it out; with every item in, the bag is ready. Desfazer as always.
    func toggleBagItem(_ item: BagItem, of items: [BagItem], for day: String) {
        guard canChange else { return }
        let before = gymBagPack(for: day)
        var p = before ?? GymBagPack(id: day, date: day)
        let wasIn = p.items.contains(item.id)
        if wasIn { p.items.removeAll { $0 == item.id } } else { p.items.append(item.id) }
        p.done = items.allSatisfy { p.items.contains($0.id) }
        p.at = nowMs()
        save(p)
        UndoCenter.shared.show(wasIn ? "\(item.title) · fora do saco" : "\(item.title) · no saco") { [weak self] in self?.restoreBag(before, day: day) }
    }

    /// «Pus os N no saco»: every item in, the bag ready
    func packBag(_ items: [BagItem], for day: String) {
        guard canChange else { return }
        let before = gymBagPack(for: day)
        var p = before ?? GymBagPack(id: day, date: day)
        for i in items where !p.items.contains(i.id) { p.items.append(i.id) }
        p.done = true
        p.at = nowMs()
        save(p)
        UndoCenter.shared.show("Saco preparado") { [weak self] in self?.restoreBag(before, day: day) }
    }

    func restoreBag(_ before: GymBagPack?, day: String) {
        if let before { save(before) } else if record(GymBagPack.self, day) != nil { put(GymBagPack.kind, day, nil) }
    }

    // MARK: Tomorrow

    /// Tomorrow's forecast, when the forecast held covers it
    func tomorrowWeather(_ day: String) -> (rain: Bool, layers: Int, text: String)? {
        guard let w = WeatherStore.shared.today else { return nil }
        let offset = Day.between(w.date, day)
        guard (0...1).contains(offset) else { return nil }
        return NightRules.tomorrowWeather(w.hours, wake: profile.wakeMinute, offset: offset)
    }

    /// Tomorrow's outfit: what you chose, or a suggestion from the pieces that are clean and available, for tomorrow's
    /// forecast when there is one
    func tomorrowOutfit(_ day: String) -> [Garment] {
        let w = tomorrowWeather(day)
        return outfit(for: day, availableOnly: true, weather: w.map { (layers: $0.layers, rain: $0.rain) })
    }

    /// Whether the calendar has something formal that day, as the outfit sees it
    func formalDay(_ day: String) -> Bool {
        Agenda.shared.events(on: day).contains { e in NightRules.formal.contains { e.title.lowercased().contains($0) } }
    }

    /// What a day holds, in a few words: the first thing you go to, training, and what's ready
    func dayParts(_ day: String) -> [String] {
        var parts: [String] = []
        let event = Agenda.shared.events(on: day).first.map { (title: $0.title, minute: $0.startMinute) }
        let trip = commutes(on: day).min { $0.arrive < $1.arrive }.map { (title: $0.title, minute: $0.arrive) }
        if let first = [event, trip].compactMap({ $0 }).min(by: { $0.minute < $1.minute }) { parts.append("\(first.title) às \(clock(first.minute))") }
        if profile.on("training"), gymBag(on: day).needed, let t = trainingSlot(on: day) { parts.append("treino às \(clock(t.start))") }
        if gymBagPack(for: day)?.done == true { parts.append("saco pronto") }
        if let o = record(OutfitLog.self, day), !o.worn { parts.append("roupa escolhida") }
        return parts
    }

    func nightPrep(_ day: String) -> NightPrep? { record(NightPrep.self, day) }

    /// «Dispensar hoje»: the preparation set aside for the evening, with Desfazer. Nothing else changes.
    func dismissPrep(on day: String) {
        guard canChange else { return }
        let before = nightPrep(day)
        save(NightPrep(id: day, date: day))
        UndoCenter.shared.show("Preparação dispensada hoje") { [weak self] in
            guard let self else { return }
            if let before { self.save(before) } else { self.put(NightPrep.kind, day, nil) }
        }
    }

    // MARK: The night

    /// The evening a minute belongs to: before noon, the night that started yesterday
    func nightDay(minute: Int) -> String { minute < 12 * 60 ? Day.add(-1, to: Day.today) : Day.today }

    func nightActive(minute: Int) -> Bool {
        NightRules.isNight(minute: minute, windDown: sleepPlan(for: nightDay(minute: minute)).windDown, wake: profile.wakeMinute)
    }

    func nightLate(minute: Int) -> Bool {
        NightRules.isLate(minute: minute, lightsOut: sleepPlan(for: nightDay(minute: minute)).perform)
    }

    /// The night's brushing: today's habits about teeth from midday on
    func nightBrushHabits(on day: String) -> [PromiseItem] {
        due(on: day).filter { p in
            let t = p.title.lowercased()
            return (t.contains("brush") || t.contains("dentes")) && time(of: p, on: day) >= 12 * 60
        }
    }

    func readHabits(on day: String) -> [PromiseItem] {
        due(on: day).filter { let t = $0.title.lowercased(); return t.hasPrefix("read") || t.hasPrefix("ler ") || t == "ler" }
    }

    /// The bedtime habits the band can tick, matched as autoComplete matches them (English words only, decision D22:
    /// «deitar» or «luzes» also name unrelated habits)
    func bedtimeHabits(on day: String) -> [PromiseItem] {
        due(on: day).filter { let t = $0.title.lowercased(); return t.contains("bed") || t.contains("lights out") }
    }

    /// The night's Higiene routine (phase 2.5): the one with steps still to confirm, or the first
    func nightRoutine(on day: String) -> CareRoutine? {
        guard profile.on("care") else { return nil }
        let list = routinesOfTheMoment(minute: 20 * 60)
        return list.first { !pendingSteps($0, on: day).isEmpty } ?? list.first
    }

    /// The night's last brushing, on the evening's clock (past 24:00 after midnight), or nil: from 14:00 on the night's
    /// day, or on the next day before you wake
    func nightBrushMinute(on day: String) -> Int? {
        let wake = profile.wakeMinute
        return (brushes(on: day) + brushes(on: Day.add(1, to: day)))
            .filter { NightRules.inNight(date: $0.date, minute: $0.minute, night: day, from: NightRules.teethFrom, wake: wake) }
            .map { $0.date == day ? $0.minute : $0.minute + 1440 }
            .max()
    }

    /// How the night's teeth ended: done when brushed or answered «feito», or «Não fiz» / «Não se aplica»; nil while open
    func nightTeethAnswer(on day: String) -> ReviewAnswer? {
        NightRules.outcome(did: nightBrushMinute(on: day) != nil, answers: nightBrushHabits(on: day).map { reviewAnswer($0, on: day) })
    }

    /// Teeth: nil without a brushing habit or a brushing tonight; resolved once brushed or answered, whatever the answer
    func nightTeeth(on day: String) -> Bool? {
        guard !nightBrushHabits(on: day).isEmpty || nightBrushMinute(on: day) != nil else { return nil }
        return nightTeethAnswer(on: day) != nil
    }

    /// The habit the brushing timer answers when you save: after midnight and before you wake, the night's open brushing
    /// habit (the evening before); otherwise, or with none open, today's brushing habit within 3 h of now. With the day
    /// to answer it on.
    func brushingHabit(minute: Int, today: String = Day.today) -> (promise: PromiseItem, day: String)? {
        let night = Day.add(-1, to: today)
        if NightRules.inNight(date: today, minute: minute, night: night, from: NightRules.teethFrom, wake: profile.wakeMinute),
           let p = nightBrushHabits(on: night).first(where: { status($0, on: night) == nil }) {
            return (p, night)
        }
        guard let p = due(on: today).first(where: { $0.title.lowercased().contains("brush") && status($0, on: today) == nil && abs(time(of: $0, on: today) - minute) < 180 }) else { return nil }
        return (p, today)
    }

    /// The brushing timer's «Guardar»: saves the brushing and answers the habit it belongs to, as yours
    func saveBrushing(_ brush: BrushLog) {
        save(brush)
        if let habit = brushingHabit(minute: brush.minute, today: brush.date) { log(habit.promise, on: habit.day, .done) }
    }

    /// Preparar amanhã: nil when there's nothing to prepare (no wardrobe, no training tomorrow); done once the outfit
    /// is chosen (or there's nothing available to choose) and the bag is ready, or when you set it aside today
    func nightPrepare(on day: String) -> Bool? {
        let tomorrow = Day.add(1, to: day)
        let outfit = profile.on("wardrobe") && garments.contains { $0.type != "gym" }
        let bag = profile.on("training") && gymBag(on: tomorrow).needed
        guard outfit || bag else { return nil }
        if nightPrep(day)?.dismissed == true { return true }
        let outfitDone = !outfit || record(OutfitLog.self, tomorrow) != nil || tomorrowOutfit(tomorrow).isEmpty
        let bagDone = !bag || gymBagPack(for: tomorrow)?.done == true
        return outfitDone && bagDone
    }

    /// Whether you read that night: from 18:00 on the night's day, or on the next day before you wake
    func nightReadingDone(on day: String) -> Bool {
        let next = Day.add(1, to: day), wake = profile.wakeMinute
        return all(ReadingSession.self).contains { s in
            (s.date == day || s.date == next) && NightRules.inNight(date: s.date, minute: Day.minuteOfDay(Date(timeIntervalSince1970: s.start / 1000)), night: day, from: NightRules.readFrom, wake: wake)
        }
    }

    /// How the night's reading ended: done when you read or answered «feito», or «Não fiz» / «Não se aplica»; nil while open
    func nightReadAnswer(on day: String) -> ReviewAnswer? {
        NightRules.outcome(did: nightReadingDone(on: day), answers: readHabits(on: day).map { reviewAnswer($0, on: day) })
    }

    /// Reading: nil with no reading habit and no book; resolved once you read that night or answered the habit
    func nightRead(on day: String) -> Bool? {
        guard !readHabits(on: day).isEmpty || currentBook != nil else { return nil }
        return nightReadAnswer(on: day) != nil
    }

    func sleepIntent(_ day: String) -> SleepIntent? { record(SleepIntent.self, day) }

    func nightStatus(minute: Int) -> NightStatus {
        let day = nightDay(minute: minute)
        var skipped: [NightStep: ReviewAnswer] = [:]
        if let a = nightTeethAnswer(on: day), a != .done { skipped[.teeth] = a }
        if let a = nightReadAnswer(on: day), a != .done { skipped[.read] = a }
        return NightRules.status(teeth: nightTeeth(on: day), prepare: nightPrepare(on: day), read: nightRead(on: day),
                                 sleep: sleepIntent(day) != nil, late: nightLate(minute: minute), skipped: skipped)
    }

    /// The reading suggested tonight, from the evening's plan
    func readingSuggestion(minute: Int) -> (minutes: Int, until: Int)? {
        NightRules.reading(minute: minute, lightsOut: sleepPlan(for: nightDay(minute: minute)).perform)
    }

    /// How long you usually take to fall asleep, from the band's last 14 nights
    var usualFallAsleep: Int? {
        NightRules.fallAsleep((0..<14).compactMap { health[Day.add(-$0, to: Day.today)]?.sleep?.toFallAsleep })
    }

    /// «Vou dormir»: the intention and its time, nothing more. Desfazer takes it back.
    func goingToSleep(minute: Int, on day: String) {
        guard canChange else { return }
        let before = sleepIntent(day)
        save(SleepIntent(id: day, date: day, minute: minute))
        UndoCenter.shared.show("Intenção registada às \(clock(minute))") { [weak self] in
            guard let self else { return }
            if let before { self.save(before) } else { self.put(SleepIntent.kind, day, nil) }
        }
    }

    /// The reading planned, saved when you start it
    func planReading(minutes: Int, from minute: Int, on day: String) {
        guard canChange else { return }
        save(ReadingPlan(id: day, date: day, minutes: minutes, start: minute, until: minute + minutes))
    }

    /// Marks the night's brushing habits done, with Desfazer
    func markTeethDone(on day: String) {
        guard canChange else { return }
        let open = nightBrushHabits(on: day).filter { status($0, on: day) == nil }
        guard !open.isEmpty else { return }
        for p in open { log(p, on: day, .done) }
        UndoCenter.shared.show("Dentes · feito") { [weak self] in for p in open { self?.undo(p, on: day) } }
    }

    /// Confirms one step of the night routine, with Desfazer
    func confirmNightStep(_ step: RoutineStep, of routine: CareRoutine, on day: String) {
        guard canChange else { return }
        let before = confirmSteps([step.id: nowMs()], of: routine, on: day)
        UndoCenter.shared.show("\(step.title) · feito") { [weak self] in self?.restoreRoutineLog(before, routine: routine, on: day) }
    }

    /// «O dia»: what was answered from the band and by you, what's past its time with no answer, and food and water
    /// with nothing logged. The night's own habits (teeth, reading, bedtime) are left to the night's steps.
    func nightDaySummary(on day: String, minute: Int) -> NightDaySummary {
        var s = NightDaySummary()
        let night = Set((nightBrushHabits(on: day) + readHabits(on: day) + bedtimeHabits(on: day)).map(\.id))
        let now = NightRules.evening(minute)
        for p in due(on: day) where !night.contains(p.id) {
            switch answerOrigin(p, on: day) {
            case .imported?: s.imported.append(p.title)
            case .you?: if status(p, on: day) != .skipped { s.yours.append(p.title) }
            case nil: if time(of: p, on: day) < now { s.open.append(p.title) }
            default: break
            }
        }
        s.noWater = !all(WaterEntry.self).contains { $0.date == day }
        s.noFood = foods(on: day).isEmpty
        return s
    }

    // MARK: The morning

    func sleepManual(_ day: String) -> SleepManual? { record(SleepManual.self, day) }

    /// «Corrigir» or «Sem pulseira?»: the night's times saved as yours, next to the band's (never over them)
    func saveSleepManual(bed: Int, wake: Int, on day: String) {
        guard canChange else { return }
        let before = sleepManual(day)
        save(SleepManual(id: day, date: day, bed: bed, wake: wake))
        UndoCenter.shared.show("Horas guardadas como registo teu") { [weak self] in
            guard let self else { return }
            if let before { self.save(before) } else { self.put(SleepManual.kind, day, nil) }
        }
    }

    /// Where the band's sleep came from, as the source line names it
    var sleepSourceName: String { profile.usesBand ? (device?.name ?? "Fitbit") : "Apple Health" }
}
