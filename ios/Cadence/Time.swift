// Time: calendar events, the energy curve, placed blocks (never moved by the app), focus sessions, tasks, projects,
// books and reading sessions, and the desk events from the VS Code extension.
import Foundation

struct CalendarEvent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var start: String
    var end: String
    var allDay: Bool
    var calendar: String?
    var color: String?
    var location: String?

    private static let iso = ISO8601DateFormatter()
    var startDate: Date { CalendarEvent.iso.date(from: start) ?? Day.date(start) }
    var endDate: Date { CalendarEvent.iso.date(from: end) ?? Day.date(end) }
    var day: String { Day.key(startDate) }
    var startMinute: Int { Day.minuteOfDay(startDate) }
    var endMinute: Int { Day.key(endDate) == day ? Day.minuteOfDay(endDate) : 1440 }
}

@MainActor
final class Agenda: ObservableObject {
    static let shared = Agenda()
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var error: String?
    @Published private(set) var focusShared: [String: JSONValue]?
    /// The days the calendar was read for (phase 2.8): outside them the plan says «sem dados», never «sem eventos»
    @Published private(set) var known: ClosedRange<String>? = nil
    private var last: Date?
    private let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("calendar.json")

    private init() {
        if let d = try? Data(contentsOf: file), let e = try? JSONDecoder().decode([CalendarEvent].self, from: d) {
            events = e
            // the copy kept on the phone covers the days of the read that wrote it
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            if let read = attributes?[.modificationDate] as? Date { known = Agenda.window(from: Day.key(read)) }
        }
    }

    /// UI-test scenarios only: the seeded list is the whole calendar
    func seed(_ list: [CalendarEvent]) {
        events = list
        known = "0000-01-01"..."9999-12-31"
    }

    /// The days one read covers: calendar.php?from=<the day before>&days=9
    nonisolated static func window(from day: String) -> ClosedRange<String> { Day.add(-1, to: day)...Day.add(7, to: day) }

    /// Whether the calendar was read for this day (read with no events is «sem eventos»; not read is «sem dados»)
    func covers(_ day: String) -> Bool { Agenda.covers(day, known: known) }

    nonisolated static func covers(_ day: String, known: ClosedRange<String>?) -> Bool { known?.contains(day) ?? false }

    func events(on day: String) -> [CalendarEvent] { events.filter { !$0.allDay && $0.day == day }.sorted { $0.start < $1.start } }
    func allDay(on day: String) -> [CalendarEvent] { events.filter { $0.allDay && $0.start <= day && $0.end > day } }

    func refresh(force: Bool = false) async {
        if TestMode.active { return }
        if !force, let last, Date().timeIntervalSince(last) < 10 * 60 { return }
        guard let req = Store.shared.request("calendar.php?from=\(Day.add(-1, to: Day.today))&days=9") else { return }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        struct Reply: Decodable { var events: [CalendarEvent] }
        if code == 200, let r = try? JSONDecoder().decode(Reply.self, from: data) {
            events = r.events
            known = Agenda.window(from: Day.today)
            error = nil
            last = Date()
            if let e = try? JSONEncoder().encode(r.events) { try? e.write(to: file, options: .atomic) }
        } else {
            error = code == 403 ? "O calendário precisa da Calendar API ativa e de voltares a ligar o Google" : code == 409 ? nil : "Calendário indisponível"
        }
    }

    // MARK: Focus shared with VS Code

    func publishFocus(_ f: FocusSession?) async {
        struct Body: Encodable { var focus: FocusState? }
        struct FocusState: Encodable { var title: String; var start: Double; var end: Double; var project: String? }
        let state = f.map { FocusState(title: $0.intention, start: $0.start, end: $0.start + Double($0.planned) * 60000, project: $0.projectId) }
        guard let body = try? JSONEncoder().encode(Body(focus: state)), let req = Store.shared.request("focus.php", body: body) else { return }
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Desk breaks answered in VS Code become records, then are acknowledged on the server
    func pullDeskEvents() async {
        guard let req = Store.shared.request("focus.php") else { return }
        struct Reply: Decodable { var events: [DeskInput] }
        guard let (data, _) = try? await URLSession.shared.data(for: req), let r = try? JSONDecoder().decode(Reply.self, from: data),
              let last = DeskSync.keep(r.events, in: Store.shared) else { return }
        struct Ack: Encodable { var ack: Double }
        if let body = try? JSONEncoder().encode(Ack(ack: last)), let ack = Store.shared.request("focus.php", body: body) { _ = try? await URLSession.shared.data(for: ack) }
    }
}

/// A desk event as focus.php sends it
struct DeskInput: Decodable, Equatable {
    var kind: String
    var answer: String
    var at: Double
    var minutes: Int?
}

@MainActor
enum DeskSync {
    /// Keeps desk events as records and says what may be acknowledged: the newest time, and only once they're really
    /// on disk. The server deletes what's acknowledged, so a failed save acknowledges nothing and the events come
    /// again next time. Their ids come from their time and kind, so getting them twice (an acknowledgement that
    /// never arrived) adds nothing twice.
    static func keep(_ events: [DeskInput], in store: Store) -> Double? {
        guard let last = events.map(\.at).max(), store.canChange else { return nil }
        for e in events {
            store.save(DeskEvent(id: "\(Int(e.at))-\(e.kind)", date: Day.key(Date(timeIntervalSince1970: e.at / 1000)), kind: e.kind, answer: e.answer, at: e.at, minutes: e.minutes ?? 0))
        }
        return store.commit() ? last : nil
    }
}

struct DeskEvent: Record, Equatable {
    static let kind = "desk"
    var id: String
    var date: String
    var kind: String // eyes, stand, active
    var answer: String // done, skipped
    var at: Double
    var minutes: Int
}

/// A block you placed on the plan. Cadence never moves it; it only suggests a new layout.
struct PlanBlock: Record, Equatable {
    static let kind = "block"
    var id = UUID().uuidString
    var date: String
    var start: Int
    var minutes: Int
    var title: String
    var type: String // deep, admin, reading, training, other
    var projectId: String?
}

struct FocusSession: Record, Equatable {
    static let kind = "focus"
    var id = UUID().uuidString
    var date = Day.today
    var intention: String
    var planned: Int // minutes
    var start = nowMs()
    var end: Double?
    var rating: Int? // 1 drained, 2 neutral, 3 energized
    var depth: Int? // 1-5
    var leftApp = 0
    var chimes = false
    var projectId: String?
    var progress: Double?

    var minutes: Int { Int(((end ?? nowMs()) - start) / 60000) }
}

struct TaskItem: Record, Equatable {
    static let kind = "task"
    var id = UUID().uuidString
    var title: String
    var estimate: Int? // minutes
    var done = false
    var created = nowMs()
    var due: String?
    var projectId: String?
}

struct Milestone: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var due: String
    var done = false
}

struct ProgressLog: Codable, Equatable { var date: String; var amount: Double }

struct Project: Record, Equatable {
    static let kind = "project"
    var id = UUID().uuidString
    var title: String
    var deadline: String
    var unit = "pages" // pages, words, hours
    var target: Double = 100
    var startAmount: Double = 0
    var milestones: [Milestone] = []
    var logs: [ProgressLog] = []
    var archived = false

    var done: Double { startAmount + logs.map(\.amount).reduce(0, +) }
}

struct Book: Record, Equatable {
    static let kind = "book"
    var id = UUID().uuidString
    var title: String
    var author = ""
    var pages = 300
    var page = 0
    var started = Day.today
    var finished: String?
    var hue = 0.58
}

struct ReadingSession: Record, Equatable {
    static let kind = "reading"
    var id = UUID().uuidString
    var date = Day.today
    var bookId: String?
    var start = nowMs()
    var minutes = 0
    var fromPage = 0
    var toPage = 0
    var note: String?
    var quote: String?
}

@MainActor
extension Store {
    // MARK: Energy

    /// Energy through the day from your wake time: a rise, a late-morning peak, the afternoon dip, an early-evening
    /// second wind. Sleep debt lowers it; your own focus ratings by hour tune it.
    func energy(at minute: Int) -> Double {
        let h = Double(minute - profile.wakeMinute) / 60
        guard h >= 0 else { return 0.2 }
        let morning = exp(-pow((h - 3.5) / 2.2, 2))
        let evening = 0.75 * exp(-pow((h - 10.5) / 2.0, 2))
        let dip = 0.35 * exp(-pow((h - 7.5) / 1.2, 2))
        var e = max(morning, evening) + 0.25 - dip
        let debt = Double(sleepPlan().debt) / 60
        e -= min(0.25, debt * 0.03)
        let hour = (minute / 60) % 24
        let rated = all(FocusSession.self).filter { Int(Day.minuteOfDay(Date(timeIntervalSince1970: $0.start / 1000)) / 60) == hour }.compactMap(\.rating)
        if rated.count >= 3 { e += (Double(rated.reduce(0, +)) / Double(rated.count) - 2) * 0.15 }
        return min(1, max(0.05, e))
    }

    /// The best free window for deep work today, around calendar events and placed blocks
    func suggestedDeepWork(on day: String = Day.today, length: Int = 100) -> Int? {
        let busy = Agenda.shared.events(on: day).map { ($0.startMinute, $0.endMinute) } + all(PlanBlock.self).filter { $0.date == day }.map { ($0.start, $0.start + $0.minutes) }
        let now = day == Day.today ? Day.minuteOfDay() + 10 : 0
        let end = sleepPlan(for: day).windDown - 60
        var best: (Int, Double)?
        var m = max(profile.wakeMinute + 60, (now / 15 + 1) * 15)
        while m + length <= end {
            let free = !busy.contains { $0.0 < m + length && $0.1 > m }
            if free {
                let score = stride(from: m, to: m + length, by: 15).map { energy(at: $0) }.reduce(0, +)
                if best == nil || score > best!.1 { best = (m, score) }
            }
            m += 15
        }
        return best?.0
    }

    var activeFocus: FocusSession? { all(FocusSession.self).first { $0.end == nil && nowMs() - $0.start < 6 * 3600 * 1000 } }

    // MARK: Projects

    func pace(_ p: Project) -> (perDay: Double, needed: Double, finish: String?) {
        let recent = p.logs.filter { Day.between($0.date, Day.today) <= 14 }.map(\.amount).reduce(0, +)
        let perDay = recent / 14
        let left = max(0, p.target - p.done)
        let daysLeft = max(1, Day.between(Day.today, p.deadline))
        return (perDay, left / Double(daysLeft), perDay > 0 ? Day.add(Int((left / perDay).rounded(.up)), to: Day.today) : nil)
    }

    // MARK: Reading

    func readingPace(_ b: Book) -> (pagesPerDay: Double, finish: String?) {
        let sessions = all(ReadingSession.self).filter { $0.bookId == b.id && Day.between($0.date, Day.today) <= 14 }
        let pages = sessions.map { max(0, $0.toPage - $0.fromPage) }.reduce(0, +)
        let perDay = Double(pages) / 14
        let left = max(0, b.pages - b.page)
        return (perDay, perDay > 0 ? Day.add(Int((Double(left) / perDay).rounded(.up)), to: Day.today) : nil)
    }

    var currentBook: Book? { all(Book.self).filter { $0.finished == nil }.max { $0.started < $1.started } }

    func readingMinutes(on day: String = Day.today) -> Int { all(ReadingSession.self).filter { $0.date == day }.map(\.minutes).reduce(0, +) }
}

// MARK: - Plano (phase 2.8): the day's load, other times for what Cadence placed, the month grid, new events

/// A stretch of a day, in minutes after midnight; the end is not included
struct PlanSpan: Equatable {
    var start: Int
    var end: Int
    var minutes: Int { max(0, end - start) }
}

/// The day's load in one line (decision 2.8): the minutes taken by calendar events, your blocks and events in Cadence,
/// and the training, against the hours awake (wake-up to lights out). What overlaps counts once in `busy`.
struct DayLoad: Equatable {
    var events: Int
    var blocks: Int
    var training: Int
    var busy: Int
    var awake: Int
    var free: Int { max(0, awake - busy) }
    var share: Double { awake > 0 ? min(1, Double(busy) / Double(awake)) : 0 }
    /// How full the day looks in the month grid: 0 (nothing) to 3 (most of the day)
    var level: Int { PlanRules.level(busy: busy, awake: awake) }
}

/// Another time for something Cadence placed, and the free window it sits in (for the «Porquê» line)
struct PlanAlternative: Equatable {
    var start: Int
    var freeFrom: Int
    var freeTo: Int
}

/// The month grid's marks. Their shape tells them apart, not only their colour: what is confirmed is filled, a
/// suggestion is hollow, a training with no record is dashed, a day the calendar wasn't read for has a dashed circle
/// («Sem dados», never «livre»)
enum PlanMark: String, CaseIterable {
    case training, trainingLogged, trainingNoRecord, commitment, suggestion, noData
    var word: String {
        switch self {
        case .training: return "treino"
        case .trainingLogged: return "treino registado"
        case .trainingNoRecord: return "treino sem registo"
        case .commitment: return "compromisso"
        case .suggestion: return "sugestão"
        case .noData: return "sem dados do calendário"
        }
    }
}

/// Something on the plan by name, day and time (a calendar event or one of Cadence's own)
struct PlanEntry: Equatable {
    var title: String
    var day: String
    var minute: Int
}

enum PlanRules {
    /// The minutes two stretches share
    static func overlap(_ a: PlanSpan, _ b: PlanSpan) -> Int { max(0, min(a.end, b.end) - max(a.start, b.start)) }

    /// The minutes the stretches cover inside [from, to), what overlaps counted once
    static func covered(_ spans: [PlanSpan], from: Int, to: Int) -> Int {
        let clipped = spans.map { PlanSpan(start: max(from, $0.start), end: min(to, $0.end)) }.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var total = 0
        var current: PlanSpan?
        for s in clipped {
            if let c = current, s.start <= c.end {
                current = PlanSpan(start: c.start, end: max(c.end, s.end))
            } else {
                total += current?.minutes ?? 0
                current = s
            }
        }
        return total + (current?.minutes ?? 0)
    }

    /// Events, blocks and training against the hours awake, each part on its own and all of them together
    static func load(events: [PlanSpan], blocks: [PlanSpan], training: PlanSpan?, wake: Int, lightsOut: Int) -> DayLoad {
        let t: [PlanSpan] = training.map { [$0] } ?? []
        return DayLoad(events: covered(events, from: wake, to: lightsOut), blocks: covered(blocks, from: wake, to: lightsOut),
                       training: covered(t, from: wake, to: lightsOut), busy: covered(events + blocks + t, from: wake, to: lightsOut),
                       awake: max(0, lightsOut - wake))
    }

    /// Nothing is 0; under a quarter of the hours awake is 1; under 60% is 2; more is 3
    static func level(busy: Int, awake: Int) -> Int {
        guard busy > 0, awake > 0 else { return 0 }
        let share = Double(busy) / Double(awake)
        return share < 0.25 ? 1 : share < 0.6 ? 2 : 3
    }

    static func fold(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An event by its name and start time, the same on every day it repeats
    static func repeatKey(_ e: CalendarEvent) -> String { fold(e.title) + "|" + String(e.startMinute) }

    /// Events that repeat every day (work, a daily stand-up): the same name at the same time on every working day the
    /// calendar was read for, except at most one (a Monday/Wednesday/Friday class is not one). The board N_PlanoMes:
    /// «Trabalho e outros eventos que se repetem todos os dias não marcam a grelha». `window` is the days of the read
    /// (Agenda.known). They don't mark the month grid; they still show in the day and count in its load.
    static func repeating(_ events: [CalendarEvent], window: ClosedRange<String>?) -> Set<String> {
        guard let window else { return [] }
        let covered = Day.between(window.lowerBound, window.upperBound) + 1
        let workdays = Set((0..<covered).map { Day.add($0, to: window.lowerBound) }.filter { ![1, 7].contains(Day.weekday($0)) }) // 1 = Sunday, 7 = Saturday
        var days: [String: Set<String>] = [:]
        for e in events where !e.allDay && workdays.contains(e.day) { days[repeatKey(e), default: []].insert(e.day) }
        return Set(days.filter { $0.value.count >= max(2, workdays.count - 1) }.keys)
    }

    /// The word in the day's load line: partial when the calendar wasn't read for that day
    static func loadWord(known: Bool) -> String { known ? "carga" : "carga parcial" }

    private static func floor15(_ m: Int) -> Int { m >= 0 ? (m / 15) * 15 : -(((-m) + 14) / 15) * 15 }
    private static func ceil15(_ m: Int) -> Int { -floor15(-m) }

    /// Where something of `length` minutes can go instead, nearest to where it was: one start per free window between
    /// the busy stretches (keeping `margin` minutes from each), on the quarter hour, inside [from, to]. Nearest first.
    /// Only what Cadence placed is ever moved: the busy stretches stay where they are.
    static func alternatives(length: Int, original: Int, busy: [PlanSpan], from: Int, to: Int, margin: Int, limit: Int = 3) -> [PlanAlternative] {
        guard length > 0, to > from else { return [] }
        var merged: [PlanSpan] = []
        for s in busy.filter({ $0.end > from && $0.start < to }).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, s.start <= last.end { merged[merged.count - 1].end = max(last.end, s.end) } else { merged.append(s) }
        }
        var found: [PlanAlternative] = []
        var cursor = from
        var afterBusy = false
        for i in 0...merged.count {
            let beforeBusy = i < merged.count
            let freeTo = beforeBusy ? merged[i].start : to
            if freeTo > cursor {
                let lo = ceil15(cursor + (afterBusy ? margin : 0))
                let hi = floor15(freeTo - (beforeBusy ? margin : 0) - length)
                if lo <= hi { found.append(PlanAlternative(start: min(hi, max(lo, floor15(original + 7))), freeFrom: cursor, freeTo: freeTo)) }
            }
            if beforeBusy {
                cursor = max(cursor, merged[i].end)
                afterBusy = true
            }
        }
        let sorted = found.sorted { a, b in
            let da = abs(a.start - original), db = abs(b.start - original)
            return da == db ? a.start < b.start : da < db
        }
        return Array(sorted.prefix(limit))
    }

    /// The month grid's marks for a day: the training (registered, planned, or planned in the past with no record:
    /// «sem registo», never «falhado»), then commitments, then suggestions; last, «sem dados» when the calendar wasn't
    /// read for that day, so an empty cell never reads as free
    static func marks(trainingPlanned: Bool, trainingLogged: Bool, past: Bool, commitments: Int, suggestions: Int, calendarKnown: Bool = true) -> [PlanMark] {
        var m: [PlanMark] = []
        if trainingLogged { m.append(.trainingLogged) } else if trainingPlanned { m.append(past ? .trainingNoRecord : .training) }
        if commitments > 0 { m.append(.commitment) }
        if suggestions > 0 { m.append(.suggestion) }
        if !calendarKnown { m.append(.noData) }
        return m
    }

    static func monthStart(_ key: String) -> String { String(key.prefix(8)) + "01" }

    /// The day the month's summary shows: the one you picked, or today, and only if it's in the month on screen; nil
    /// when it isn't (the summary never shows a day of another month)
    static func monthPick(_ picked: String?, month: String, today: String) -> String? {
        let day = picked ?? today
        return monthStart(day) == monthStart(month) ? day : nil
    }

    static func addMonths(_ n: Int, to key: String) -> String {
        let first = Day.date(monthStart(key))
        return Day.key(Day.calendar.date(byAdding: .month, value: n, to: first) ?? first)
    }

    /// The month's days in weeks from Monday; nil where a week starts before or ends after the month
    static func monthCells(_ key: String) -> [String?] {
        let first = monthStart(key)
        let count = Day.calendar.range(of: .day, in: .month, for: Day.date(first))?.count ?? 30
        var cells: [String?] = Array(repeating: nil, count: (Day.weekday(first) + 5) % 7)
        for i in 0..<count { cells.append(Day.add(i, to: first)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// Something with the same name in the same week (Monday to Sunday), so a new event isn't a duplicate by mistake
    static func similar(to title: String, on day: String, among entries: [PlanEntry]) -> PlanEntry? {
        let key = fold(title)
        guard !key.isEmpty else { return nil }
        let week = Day.weekStart(day)
        return entries.filter { fold($0.title) == key && Day.weekStart($0.day) == week }.min { ($0.day, $0.minute) < ($1.day, $1.minute) }
    }
}

/// Dates in the Plano's words, in European Portuguese whatever the phone's settings («Quinta, 12 de novembro»)
enum PlanFormat {
    static let weekdays = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"] // by Calendar weekday, 1 = Sunday
    static let shortWeekdays = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
    static let months = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]

    private static func parts(_ key: String) -> (year: Int, month: Int, day: Int)? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return nil }
        return (p[0], p[1], p[2])
    }

    static func weekday(_ key: String) -> String { weekdays[Day.weekday(key) - 1] }
    static func short(_ key: String) -> String { shortWeekdays[Day.weekday(key) - 1] }

    /// Whether the time is in the hour 1, the only singular one in Portuguese («à 1», «da 1:00»; 13:00 is «às 13:00»)
    private static func oneOClock(_ minute: Int) -> Bool { (((minute % 1440) + 1440) % 1440) / 60 == 1 }

    /// «às 15:00», «à 1:00»
    static func at(_ minute: Int) -> String { (oneOClock(minute) ? "à " : "às ") + clock(minute) }

    /// «das 15:00», «da 1:00»
    static func from(_ minute: Int) -> String { (oneOClock(minute) ? "da " : "das ") + clock(minute) }

    /// «as 15:00», «a 1:00», after «para»
    static func article(_ minute: Int) -> String { (oneOClock(minute) ? "a " : "as ") + clock(minute) }

    /// «às 3», «à 1»: the hour on its own, as you'd say it
    static func atHour(_ hour: Int) -> String { hour == 1 ? "à 1" : "às \(hour)" }

    /// «12 de novembro»
    static func dayMonth(_ key: String) -> String {
        guard let p = parts(key) else { return key }
        return "\(p.day) de \(months[p.month - 1])"
    }

    /// «Quinta, 12 de novembro»
    static func day(_ key: String) -> String { "\(weekday(key)), \(dayMonth(key))" }

    /// «novembro»
    static func monthName(_ key: String) -> String {
        guard let p = parts(key) else { return key }
        return months[p.month - 1]
    }

    /// «Novembro de 2026»
    static func month(_ key: String) -> String {
        guard let p = parts(key) else { return key }
        let m = months[p.month - 1]
        return "\(m.prefix(1).uppercased())\(m.dropFirst()) de \(p.year)"
    }

    /// «9 a 15 de novembro», «30 de novembro a 6 de dezembro»
    static func week(from start: String) -> String {
        guard let a = parts(start), let b = parts(Day.add(6, to: start)) else { return start }
        return a.month == b.month ? "\(a.day) a \(b.day) de \(months[b.month - 1])" : "\(a.day) de \(months[a.month - 1]) a \(b.day) de \(months[b.month - 1])"
    }

    /// «Hoje», «Amanhã», «Ontem», or the day
    static func relative(_ key: String, today: String) -> String {
        switch Day.between(today, key) {
        case 0: return "Hoje"
        case 1: return "Amanhã"
        case -1: return "Ontem"
        default: return day(key)
        }
    }
}

/// A new event as understood from one line («dentista quinta às 3»), always shown back in the form before anything is
/// saved. The day words are QuickCapture's (and its reminder text, for «lembra-me de…»); a time needs «às» («à» for
/// the hour 1: «à 1») or a written form (15:30, 18h). An hour from 1 to 11 with nothing saying morning or afternoon has
/// two readings, to choose from before saving (decisions 29–30: ambiguities are settled before Guardar).
struct EventDraft: Equatable {
    var title: String
    var day: String?
    var minute: Int?
    var options: [Int] = []

    static func parse(_ raw: String, today: String) -> EventDraft {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = PlanRules.fold(text)
        var minute: Int?
        var options: [Int] = []
        if let t = clock(in: lower) {
            let m = t.hour * 60 + t.minute
            if let later = t.afternoon {
                minute = later && t.hour < 12 ? m + 720 : m
            } else if (1...11).contains(t.hour) && !t.leadingZero {
                options = [m + 720, m]
            } else {
                minute = m
            }
        }
        var base = text
        if case .reminder(let what, _, _) = QuickCapture.parse(text, today: today), !what.isEmpty { base = what }
        return EventDraft(title: cleanTitle(base), day: QuickCapture.dayWord(in: lower, today: today), minute: minute, options: options)
    }

    private struct ClockWords {
        var hour: Int
        var minute: Int
        var leadingZero: Bool
        var afternoon: Bool?
    }

    private static let timeExpression = try? NSRegularExpression(pattern: #"(?:\b(as|at|a|pelas)\s+)?\b(\d{1,2})(?:([:h])(\d{2})?)?\b"#)

    /// The first time of day in the (lowercased, accent-free) text: after «às», «at» or «pelas», after «à» for the hour 1
    /// (the only singular hour: «a 2 amigos» isn't a time), or written 15:30 / 18h
    private static func clock(in lower: String) -> ClockWords? {
        guard let re = timeExpression else { return nil }
        let ns = lower as NSString
        for m in re.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
            let prefix = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ""
            let prefixed = !prefix.isEmpty
            let written = m.range(at: 3).location != NSNotFound
            guard prefixed || written else { continue }
            let hourText = ns.substring(with: m.range(at: 2))
            if prefix == "a", !written, hourText != "1" { continue }
            if prefix == "a", !written, ns.substring(from: NSMaxRange(m.range)).range(of: #"^\s+de\s+(?!manha|tarde|noite|madrugada)"#, options: .regularExpression) != nil { continue } // «a 1 de dezembro» is a date
            guard let h = Int(hourText), h < 24 else { continue }
            var mins = 0
            if m.range(at: 4).location != NSNotFound {
                guard let v = Int(ns.substring(with: m.range(at: 4))), v < 60 else { continue }
                mins = v
            }
            let later = ["da tarde", "de tarde", "a tarde", "da noite", "de noite", "a noite"].contains { lower.contains($0) }
            let earlier = ["da manha", "de manha", "da madrugada", "de madrugada"].contains { lower.contains($0) }
            let period: Bool? = later ? true : (earlier ? false : nil)
            return ClockWords(hour: h, minute: mins, leadingZero: hourText.count == 2 && hourText.hasPrefix("0"), afternoon: period)
        }
        return nil
    }

    private static let dayWords: Set<String> = ["hoje", "amanha", "today", "tomorrow", "domingo", "segunda", "terca", "quarta", "quinta", "sexta", "sabado",
                                                "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let connectors: Set<String> = ["na", "no", "de", "do", "da", "a", "as", "at", "on", "para", "em", "pelas"]
    private static let periods: Set<String> = ["manha", "tarde", "noite", "madrugada"]

    /// The name without the day and time words («Dentista quinta às 3» → «Dentista»)
    static func cleanTitle(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        let folded = words.map { PlanRules.fold($0).trimmingCharacters(in: .punctuationCharacters) }
        var keep = Array(repeating: true, count: words.count)
        for i in folded.indices {
            let w = folded[i]
            let before = i > 0 ? folded[i - 1] : ""
            let isDay = dayWords.contains(w) || w.hasSuffix("-feira") || w == "feira"
            let looksLikeTime = w.range(of: #"^\d{1,2}([:h]\d{0,2})?$"#, options: .regularExpression) != nil
            let next = i + 1 < folded.count ? folded[i + 1] : "", afterNext = i + 2 < folded.count ? folded[i + 2] : ""
            let hourOne = before == "a" && String(w.prefix(while: { $0.isNumber })) == "1" && !(next == "de" && !periods.contains(afterNext)) // «à 1», the singular hour; «a 1 de dezembro» is a date
            let isTime = looksLikeTime && (["as", "at", "pelas"].contains(before) || w.contains(":") || w.contains("h") || hourOne)
            let isPeriod = periods.contains(w) && ["da", "de", "a"].contains(before)
            let isHours = (w == "horas" || w == "h") && i > 0 && !keep[i - 1]
            guard isDay || isTime || isPeriod || isHours else { continue }
            keep[i] = false
            if i > 0, connectors.contains(before) { keep[i - 1] = false }
        }
        var out: [String] = []
        for i in words.indices where keep[i] { out.append(words[i]) }
        while let last = out.last, connectors.contains(PlanRules.fold(last)) { out.removeLast() }
        while out.count > 1, let first = out.first, connectors.contains(PlanRules.fold(first)) { out.removeFirst() }
        let t = out.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}
