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
    private var last: Date?
    private let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("calendar.json")

    private init() {
        if let d = try? Data(contentsOf: file), let e = try? JSONDecoder().decode([CalendarEvent].self, from: d) { events = e }
    }

    func events(on day: String) -> [CalendarEvent] { events.filter { !$0.allDay && $0.day == day }.sorted { $0.start < $1.start } }
    func allDay(on day: String) -> [CalendarEvent] { events.filter { $0.allDay && $0.start <= day && $0.end > day } }

    func refresh(force: Bool = false) async {
        if !force, let last, Date().timeIntervalSince(last) < 10 * 60 { return }
        guard let req = Store.shared.request("calendar.php?from=\(Day.add(-1, to: Day.today))&days=9") else { return }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        struct Reply: Decodable { var events: [CalendarEvent] }
        if code == 200, let r = try? JSONDecoder().decode(Reply.self, from: data) {
            events = r.events
            error = nil
            last = Date()
            if let e = try? JSONEncoder().encode(r.events) { try? e.write(to: file, options: .atomic) }
        } else {
            error = code == 403 ? "Calendar needs the Calendar API enabled and Google connected again" : code == 409 ? nil : "Calendar unavailable"
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
        struct Event: Decodable { var kind: String; var answer: String; var at: Double; var minutes: Int? }
        struct Reply: Decodable { var events: [Event] }
        guard let (data, _) = try? await URLSession.shared.data(for: req), let r = try? JSONDecoder().decode(Reply.self, from: data), let last = r.events.map(\.at).max() else { return }
        let store = Store.shared
        for e in r.events {
            store.save(DeskEvent(id: "\(Int(e.at))-\(e.kind)", date: Day.key(Date(timeIntervalSince1970: e.at / 1000)), kind: e.kind, answer: e.answer, at: e.at, minutes: e.minutes ?? 0))
        }
        struct Ack: Encodable { var ack: Double }
        if let body = try? JSONEncoder().encode(Ack(ack: last)), let ack = Store.shared.request("focus.php", body: body) { _ = try? await URLSession.shared.data(for: ack) }
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
