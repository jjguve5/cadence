// «Agora» on Today (phase 2.4, decision D3): one step at a time. Each step only applies when the one before it doesn't:
//   1. an event that needs you to leave within 45 min («Preparar para sair» · «Adiar 10 min» · «Já não vou»);
//   2. a workout in progress (continue it);
//   3. Antes de sair: a departure within 60 min with something on the list still to see (phase 2.9, Night.swift);
//   4. the routine of the moment still to confirm, in the hours «Agora» asks for it (Store.agoraRoutine);
//   4b. Higiene's reminders (decision D40): the shower at its time, what's overdue from 19:30 (and earlier when no habit is next);
//   5. the next habit (what "A seguir" did before);
//   6. nothing: no card.
// The rule is a pure function over its inputs (NowRule.pick); the Store glue at the end gathers them. Calendar events are
// read only: «Adiar 10 min» and «Já não vou» keep their own record (nowDismiss) and never change the Google event.
import Foundation

/// A calendar event that needs you to leave: it has a place, or a regular trip sets when to leave
struct NowDeparture: Equatable {
    var eventId: String
    var title: String
    var start: Int // the event's start, minutes after midnight
    var leave: Int // when to leave, minutes after midnight
    var place: String?
    var trip: String? // the regular trip whose door-to-door time and margin set `leave`, if one matches
    var lead: Int // minutes between leaving and the start
}

struct NowWorkout: Equatable {
    var id: String
    var name: String
    var start: Double // ms
}

/// A habit due today, as the rule sees it
struct NowHabit: Equatable {
    var promise: PromiseItem
    var time: Int // minutes after midnight
    var answered: Bool
}

/// What comes after the step, for the «Depois» line
struct NowLater: Equatable {
    var title: String
    var minute: Int
}

/// The one step «Agora» shows, in the rule's order
enum NowStep: Equatable {
    case leave(NowDeparture)
    case workout(NowWorkout)
    /// Antes de sair (phase 2.9): a departure within 60 min with items still to see. The card reads the list itself
    /// (Store.leaveEntries), so the step carries nothing.
    case beforeLeaving
    /// The routine of the moment, still to confirm («Começar»): Higiene's routineDueNow() (phase 2.5). The card reads
    /// the routine itself.
    case routine
    /// A reminder from Higiene (decision D40): done, or not today
    case care(NowCare)
    case habit(PromiseItem)

    /// An urgent step takes the place of «Agora» at the top, and the rest shrinks to a line
    var isUrgent: Bool {
        if case .leave = self { return true }
        return false
    }
}

/// A reminder from Higiene for «Agora»: the day's shower, or a grooming item that's overdue
struct NowCare: Equatable {
    var key: String // "shower", or "groom.<id>": what «Hoje não» hides for the day
    var title: String
    var why: String
    var groomingId: String? // nil for the shower
}

/// Everything the rule looks at
struct NowInputs {
    var minute: Int // now, minutes after midnight
    var departures: [NowDeparture] = []
    var dismissals: [String: NowDismiss] = [:] // today's answers to a warning, by event id
    var workout: NowWorkout?
    var beforeLeaving: NowStep? // Store.nowBeforeLeaving (phase 2.9)
    var routine: NowStep? // Store.nowRoutine: Higiene's routine of the moment (phase 2.5)
    var care: NowStep? // Store.nowCare: a Higiene reminder that is due now, before the next habit (decision D40)
    var careWhenFree: NowStep? // what's overdue but can wait: only when no habit is next
    var habits: [NowHabit] = [] // today's, in the order of the day
}

/// Your answer to a leave-by warning, for one event on one day. Its own record: the calendar event is never changed.
/// `action` is a plain string ("snooze" for «Adiar 10 min», "gone" for «Já não vou»), so a value a later build adds
/// can't make an older build protect the file; an action this build doesn't know hides nothing.
struct NowDismiss: Record, Equatable {
    static let kind = "nowDismiss"
    static let snooze = "snooze", gone = "gone"
    var id: String // <day>_<event>, see NowRule.dismissKey
    var date: String
    var event: String
    var action: String
    var until: Int? // snooze: the minute of that day the warning comes back
    var at = nowMs()
}

enum NowRule {
    /// A departure is urgent from this many minutes before the time to leave until the event starts
    static let window = 45
    static let snoozeMinutes = 10
    /// With a place but no regular trip there is no travel estimate (no location is used): leave this long before
    static let defaultLead = 30
    /// What's overdue in Higiene comes before the next habit from this time, the time of its notification (decision D40)
    static let careFrom = 19 * 60 + 30

    /// The shower's planned minute has come. The plan never says earlier than five minutes from now, so a plan that has
    /// passed reads as about five minutes away
    static func showerIsDue(at planned: Int, minute: Int) -> Bool { planned <= minute + 6 }

    /// The days whose shower can be asked now: last night's can be planned for this morning, but from noon a shower counts
    /// for today (ShowerRules.covered), so only today's is left
    static func showerDays(day: String, minute: Int) -> [String] { minute < 12 * 60 ? [Day.add(-1, to: day), day] : [day] }

    /// The step to show, or nil for no card
    static func pick(_ i: NowInputs) -> NowStep? {
        if let d = urgent(i.departures, minute: i.minute, dismissals: i.dismissals) { return .leave(d) }
        if let w = i.workout { return .workout(w) }
        if let s = i.beforeLeaving { return s }
        if let s = i.routine { return s }
        if let s = i.care { return s }
        if let h = nextHabit(i.habits, minute: i.minute) { return .habit(h.promise) }
        return i.careWhenFree
    }

    /// The departure to warn about now: the time to leave is at most 45 min away, the event hasn't started, and you
    /// haven't hidden it or put it off. The earliest to leave first.
    static func urgent(_ list: [NowDeparture], minute: Int, dismissals: [String: NowDismiss] = [:]) -> NowDeparture? {
        list.filter { minute < $0.start && $0.leave - minute <= window && !hidden(dismissals[$0.eventId], minute: minute) }
            .min { ($0.leave, $0.start, $0.eventId) < ($1.leave, $1.start, $1.eventId) }
    }

    /// «Já não vou» hides the warning for that day; «Adiar 10 min» hides it until its minute
    static func hidden(_ d: NowDismiss?, minute: Int) -> Bool {
        guard let d else { return false }
        switch d.action {
        case NowDismiss.gone: return true
        case NowDismiss.snooze: return minute < (d.until ?? 0)
        default: return false
        }
    }

    /// An event needs you to leave when it has a place or a regular trip that matches it (its place, or its name);
    /// a trip sets the time from its door-to-door minutes and margin, otherwise it's `defaultLead` before the start.
    /// All-day events and events with neither are not departures.
    static func departure(for e: CalendarEvent, trips: [RegularTrip]) -> NowDeparture? {
        guard !e.allDay else { return nil }
        let place = (e.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = trips.first(where: { matches($0, title: e.title, place: place) }) {
            let lead = t.travel + t.buffer
            return NowDeparture(eventId: e.id, title: e.title, start: e.startMinute, leave: e.startMinute - lead, place: place.isEmpty ? nil : place, trip: t.title, lead: lead)
        }
        guard !place.isEmpty else { return nil }
        return NowDeparture(eventId: e.id, title: e.title, start: e.startMinute, leave: e.startMinute - defaultLead, place: place, trip: nil, lead: defaultLead)
    }

    /// A regular trip goes to an event's place when its destination or its name is that place, or its name is the
    /// event's name (case and accents don't matter)
    static func matches(_ t: RegularTrip, title: String, place: String) -> Bool {
        func norm(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespacesAndNewlines) }
        let destination = norm(t.destination), name = norm(t.title), p = norm(place), event = norm(title)
        if !destination.isEmpty, destination == p { return true }
        return !name.isEmpty && (name == p || name == event)
    }

    /// Today's behaviour, kept: the first habit due today with no answer that isn't more than 90 min past its time
    static func nextHabit(_ habits: [NowHabit], minute: Int) -> NowHabit? {
        habits.first { !$0.answered && $0.time + 90 >= minute }
    }

    /// What comes after the step: the other habits still ahead and the training to come, by time, at most three
    static func later(habits: [NowHabit], training: NowLater?, minute: Int, excluding id: String?, limit: Int = 3) -> [NowLater] {
        var items = habits.filter { !$0.answered && $0.time + 90 >= minute && $0.promise.id != id }.map { NowLater(title: $0.promise.title, minute: $0.time) }
        if let training, training.minute >= minute { items.append(training) }
        return Array(items.sorted { ($0.minute, $0.title) < ($1.minute, $1.title) }.prefix(limit))
    }

    /// "Creatina 17:00 · Pernas 18:00"
    static func laterText(_ items: [NowLater]) -> String {
        items.map { "\($0.title) \(clock($0.minute))" }.joined(separator: " · ")
    }

    /// The record id for a day's answer to an event's warning: `<day>_<event>`, only [A-Za-z0-9_.:-] and at most 80
    /// characters, as the server takes them. An event id that had to be cleaned or cut gets an 8-hex hash of the
    /// original, so two events never share an answer.
    static func dismissKey(day: String, event: String) -> String {
        let safe = String(event.map { c -> Character in
            c.isASCII && (c.isLetter || c.isNumber || "_.:-".contains(c)) ? c : "-"
        })
        let plain = day + "_" + safe
        if safe == event && plain.count <= 80 { return plain }
        var hash: UInt32 = 2166136261
        for byte in event.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return String(plain.prefix(80 - 9)) + "_" + String(format: "%08x", hash)
    }
}

// MARK: - Store glue

@MainActor
extension Store {
    /// The minute Today's rules see: the UI test's fixed minute, or the clock (`tick` redraws Today every minute)
    var nowMinute: Int { TestMode.minute ?? Day.minuteOfDay(tick) }

    /// The day's calendar events that need you to leave. `events` is for tests; the app reads the calendar.
    func nowDepartures(events: [CalendarEvent]? = nil, day: String = Day.today) -> [NowDeparture] {
        let list = events ?? Agenda.shared.events(on: day)
        let trips = all(RegularTrip.self)
        return list.compactMap { NowRule.departure(for: $0, trips: trips) }
    }

    func nowHabits(on day: String = Day.today) -> [NowHabit] {
        due(on: day).map { NowHabit(promise: $0, time: time(of: $0, on: day), answered: status($0, on: day) != nil) }
    }

    /// Step 3, Antes de sair (phase 2.9): a departure within 60 min (an event with a place, a regular trip, training)
    /// and something on the day's list still to see. `events` is for tests; the app reads the calendar.
    func nowBeforeLeaving(minute: Int, events: [CalendarEvent]? = nil, day: String = Day.today) -> NowStep? {
        let pending = leaveEntries(on: day).filter { !$0.seen }.count
        return LeaveRules.isStep(leaveDepartures(on: day, events: events), minute: minute, pending: pending) ? .beforeLeaving : nil
    }

    /// Step 4, the routine of the moment still to confirm, unless its hours are over or you put it away today
    func nowRoutine(minute: Int, day: String = Day.today) -> NowStep? {
        agoraRoutine(minute: minute, day: day) == nil ? nil : .routine
    }

    /// Step 4b (decision D40), what Higiene is already saying: the shower at its planned time, and what's overdue among
    /// what you've done before (as «A seguir» in Higiene: never registered stays in Frequências). `now` comes before the
    /// next habit; `whenFree` is the overdue item earlier in the day, only when no habit is next.
    func nowCare(minute: Int, day: String = Day.today) -> (now: NowStep?, whenFree: NowStep?) {
        guard profile.on("care") else { return (nil, nil) }
        let open = { (key: String) -> Bool in self.record(NowDismiss.self, NowRule.dismissKey(day: day, event: key)) == nil }
        // the plan reads the real clock, so it only means something for the real minute
        if !TestMode.active, abs(minute - Day.minuteOfDay()) <= 1, open("shower"), !showerTimes.isEmpty {
            for d in NowRule.showerDays(day: day, minute: minute) {
                if let s = showerPlan(for: d), Day.key(s.at) == day, NowRule.showerIsDue(at: Day.minuteOfDay(s.at), minute: minute) {
                    return (.care(NowCare(key: "shower", title: "Tomar duche", why: s.why, groomingId: nil)), nil)
                }
            }
        }
        let overdue = all(GroomingItem.self).filter { $0.last != nil && $0.isDue(on: day) && open("groom." + $0.id) }.sorted { $0.freshness < $1.freshness }
        guard let g = overdue.first else { return (nil, nil) }
        let since = g.last.map { Day.between($0, day) } ?? 0
        let step = NowStep.care(NowCare(key: "groom." + g.id, title: g.title, why: "há \(ptCount(since, "dia", "dias")) desde a última vez; o ritmo é a cada \(ptCount(g.rhythm, "dia", "dias")).", groomingId: g.id))
        if minute >= NowRule.careFrom { return (step, nil) }
        return (nil, step)
    }

    /// «Feito» on a Higiene reminder, with Desfazer
    func finishNowCare(_ c: NowCare, day: String = Day.today) {
        guard canChange else { return }
        if let id = c.groomingId {
            guard let g = record(GroomingItem.self, id), let before = markGroomingDone(g, on: day) else { return }
            UndoCenter.shared.show("\(g.title) · feito") { [weak self] in self?.save(before) }
        } else {
            let shower = Shower()
            save(shower)
            Reminders.shared.reschedule()
            UndoCenter.shared.show("Duche registado") { [weak self] in
                self?.remove(shower)
                Reminders.shared.reschedule()
            }
        }
    }

    /// «Hoje não»: not asked again today, with Desfazer. Nothing else changes
    func skipNowCare(_ c: NowCare, day: String = Day.today) {
        guard canChange else { return }
        let id = NowRule.dismissKey(day: day, event: c.key)
        let before = records(NowDismiss.kind)[id]
        save(NowDismiss(id: id, date: day, event: c.key, action: NowDismiss.gone))
        UndoCenter.shared.show("Hoje já não pergunto") { [weak self] in self?.put(NowDismiss.kind, id, before) }
    }

    func nowInputs(minute: Int, events: [CalendarEvent]? = nil, day: String = Day.today) -> NowInputs {
        let departures = nowDepartures(events: events, day: day)
        var dismissals: [String: NowDismiss] = [:]
        for d in departures {
            if let answer = record(NowDismiss.self, NowRule.dismissKey(day: day, event: d.eventId)) { dismissals[d.eventId] = answer }
        }
        let care = nowCare(minute: minute, day: day)
        return NowInputs(minute: minute, departures: departures, dismissals: dismissals,
                         workout: activeSession.map { NowWorkout(id: $0.id, name: $0.name, start: $0.start) },
                         beforeLeaving: nowBeforeLeaving(minute: minute, events: events, day: day), routine: nowRoutine(minute: minute, day: day),
                         care: care.now, careWhenFree: care.whenFree, habits: nowHabits(on: day))
    }

    /// The step «Agora» shows now, or nil for no card
    func nowStep(minute: Int? = nil, events: [CalendarEvent]? = nil) -> NowStep? {
        NowRule.pick(nowInputs(minute: minute ?? nowMinute, events: events))
    }

    /// The «Depois» line: the rest of today, after the step
    func nowLater(after step: NowStep?, minute: Int, day: String = Day.today) -> [NowLater] {
        var shown: String?
        if case .habit(let p)? = step { shown = p.id }
        var training: NowLater?
        if profile.on("training"), activeSession == nil, let t = trainingSlot(on: day), !t.done { training = NowLater(title: t.title, minute: t.start) }
        return NowRule.later(habits: nowHabits(on: day), training: training, minute: minute, excluding: shown)
    }

    /// «Adiar 10 min» (snooze) or «Já não vou»: saves the answer for that event today and offers Desfazer, which puts
    /// back what was there before. The calendar event itself is never touched.
    func answerNow(_ d: NowDeparture, snooze: Bool, minute: Int, day: String = Day.today) {
        guard canChange else { return }
        let id = NowRule.dismissKey(day: day, event: d.eventId)
        let before = records(NowDismiss.kind)[id]
        save(NowDismiss(id: id, date: day, event: d.eventId, action: snooze ? NowDismiss.snooze : NowDismiss.gone, until: snooze ? minute + NowRule.snoozeMinutes : nil))
        UndoCenter.shared.show(snooze ? "Aviso adiado \(NowRule.snoozeMinutes) min" : "Aviso escondido · o evento do Google fica igual") { [weak self] in
            self?.put(NowDismiss.kind, id, before)
        }
    }

    /// Marks the step's habit done, with Desfazer
    func markNowDone(_ p: PromiseItem) {
        guard canChange else { return }
        log(p, .done)
        UndoCenter.shared.show("\(p.title) · concluído") { [weak self] in self?.undo(p) }
    }
}
