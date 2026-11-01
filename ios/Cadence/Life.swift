// Home, documents, people and learning: freshness bars for chores, plants indoors and out, expiry dates checked
// against your trips, keeping in touch (only with the people you choose), birthdays and gift ideas, review cards.
import Foundation

struct Chore: Record, Equatable {
    static let kind = "chore"
    var id = UUID().uuidString
    var title: String
    var room = "Home"
    var everyDays = 7
    var minutes = 10
    var history: [String] = []

    var daysSince: Int? { history.max().map { Day.between($0, Day.today) } }
    var freshness: Double { daysSince.map { 1 - min(1, Double($0) / Double(max(1, everyDays))) } ?? 0 }
}

struct Plant: Record, Equatable {
    static let kind = "plant"
    var id = UUID().uuidString
    var name: String
    var outdoor = false
    var everyDays = 7
    var watered: String?

    var daysSince: Int? { watered.map { Day.between($0, Day.today) } }
}

struct DocumentItem: Record, Equatable {
    static let kind = "document"
    var id = UUID().uuidString
    var title: String
    var kind = "document" // document, checkup, warranty, car
    var expires: String
    var leadDays = 60
    var notes = ""
}

struct Person: Record, Equatable {
    static let kind = "person"
    var id = UUID().uuidString
    var name: String
    var keepInTouch = false // off unless you set it up for this person
    var everyWeeks = 4
    var lastContact: String?
    var birthday: String? // MM-dd
    var gifts: [String] = []
    var notes: [String] = []
}

struct ReviewCard: Record, Equatable {
    static let kind = "card"
    var id = UUID().uuidString
    var front: String
    var back: String
    var due = Day.today
    var stability: Double = 1 // days
    var difficulty: Double = 5 // 1–10
    var reps = 0
    var deck = "General"
}

struct SkillLog: Record, Equatable {
    static let kind = "skill"
    var id = UUID().uuidString
    var date = Day.today
    var skill: String
    var minutes: Int
}

@MainActor
extension Store {
    /// Watering that knows the weather: rain since the last watering counts for outdoor plants, heat brings it forward
    func plantDue(_ p: Plant) -> (due: Bool, note: String) {
        let since = p.daysSince ?? 999
        guard p.outdoor else { return (since >= p.everyDays, since >= p.everyDays ? "Water today" : "in \(p.everyDays - since) days") }
        let w = WeatherStore.shared.today
        let rainedToday = (w?.hours.filter { $0.minute < 1440 && $0.rain >= 70 }.count ?? 0) >= 2
        let hot = (w?.high ?? 20) >= 28
        if rainedToday { return (false, "Rain today waters it") }
        let interval = hot ? max(1, p.everyDays - 2) : p.everyDays
        return (since >= interval, since >= interval ? (hot ? "Hot day: water it" : "Water today") : "in \(interval - since) days")
    }

    var documentsSoon: [DocumentItem] {
        all(DocumentItem.self).filter { Day.between(Day.today, $0.expires) <= $0.leadDays }.sorted { $0.expires < $1.expires }
    }

    /// A document that expires before or during a planned trip
    func documentWarnings() -> [String] {
        var out: [String] = []
        for t in all(Trip.self) where t.end >= Day.today {
            for d in all(DocumentItem.self) where d.kind == "document" && d.expires <= Day.add(180, to: t.end) {
                out.append("\(d.title) expires \(Day.date(d.expires).formatted(.dateTime.day().month().year())): within 6 months of your trip to \(t.destination).")
            }
        }
        return out
    }

    var tidyQueue: [Chore] { all(Chore.self).filter { $0.minutes <= 10 }.sorted { $0.freshness < $1.freshness }.prefix(3).map { $0 } }

    var keepInTouchDue: [Person] {
        all(Person.self).filter { $0.keepInTouch && ($0.lastContact.map { Day.between($0, Day.today) } ?? 999) >= $0.everyWeeks * 7 }
    }

    /// Birthdays in the next 30 days, from people you added and the calendar's birthdays
    var birthdaysSoon: [(name: String, date: String, person: Person?)] {
        var out: [(String, String, Person?)] = []
        let year = Int(Day.today.prefix(4)) ?? 2026
        for p in all(Person.self) {
            guard let b = p.birthday else { continue }
            var d = "\(year)-\(b)"
            if d < Day.today { d = "\(year + 1)-\(b)" }
            if Day.between(Day.today, d) <= 30 { out.append((p.name, d, p)) }
        }
        for e in Agenda.shared.events where e.allDay && e.title.lowercased().contains("birthday") && Day.between(Day.today, e.start) <= 30 && e.start >= Day.today {
            let name = e.title.replacingOccurrences(of: "'s birthday", with: "").replacingOccurrences(of: "Birthday", with: "").trimmingCharacters(in: .whitespaces)
            if !out.contains(where: { $0.0 == name }) { out.append((name, e.start, nil)) }
        }
        return out.sorted { $0.1 < $1.1 }.map { (name: $0.0, date: $0.1, person: $0.2) }
    }

    // MARK: Review cards (a light FSRS: stability grows with each good recall, shrinks with a lapse)

    func dueCards() -> [ReviewCard] {
        let limit = (readiness()?.score ?? 70) < 50 ? 10 : 30 // fewer on low-readiness days
        return all(ReviewCard.self).filter { $0.due <= Day.today }.sorted { $0.due < $1.due }.prefix(limit).map { $0 }
    }

    func review(_ c: ReviewCard, grade: Int) { // 1 again, 2 hard, 3 good, 4 easy
        var x = c
        x.reps += 1
        x.difficulty = min(10, max(1, x.difficulty + Double(3 - grade) * 0.8))
        if grade == 1 { x.stability = max(1, x.stability * 0.3) }
        else {
            let growth = 1 + (11 - x.difficulty) / 4 * (grade == 2 ? 0.6 : grade == 4 ? 1.6 : 1)
            x.stability = max(1, x.stability * growth)
        }
        x.due = Day.add(grade == 1 ? 1 : Int(x.stability.rounded()), to: Day.today)
        save(x)
    }

    /// Book quotes become cards
    func quotesToCards() {
        let existing = Set(all(ReviewCard.self).map(\.back))
        for s in all(ReadingSession.self) {
            guard let q = s.quote, !existing.contains(q) else { continue }
            let book = s.bookId.flatMap { record(Book.self, $0) }?.title ?? "a book"
            save(ReviewCard(front: "A quote from \(book)", back: q, deck: "Quotes"))
        }
    }
}
