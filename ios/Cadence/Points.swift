// Points by difficulty (asked for by the user on 9 Nov): what's harder gives more. A day's points are the sum of what you
// actually did that day; the day's score (0–100, how the day went) stays what it was and is no longer the points.
// Days already closed keep the points they were closed with: nothing in the history is recalculated.
import Foundation

/// How hard a habit is for you. Saved in PromiseItem.effort as its number; none saved counts as medium.
enum HabitEffort: Int, CaseIterable, Identifiable {
    case easy = 1, medium = 2, hard = 3
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .easy: return "Fácil"
        case .medium: return "Média"
        case .hard: return "Difícil"
        }
    }
    var points: Int {
        switch self {
        case .easy: return 5
        case .medium: return 10
        case .hard: return 20
        }
    }
}

/// One thing that gives points on a day, done or still open
struct PointLine: Identifiable, Equatable {
    var id: String
    var title: String
    var icon: String
    var points: Int // what it gives (what it gave, when earned)
    var earned: Bool
}

enum PointRules {
    static let workout = 30
    static let sleep = 10
    static let steps = 10
    static let protein = 10
    static let water = 5
    static let closing = 5

    static func effort(_ p: PromiseItem) -> HabitEffort { p.effort.flatMap(HabitEffort.init(rawValue:)) ?? .medium }

    /// The minimum version is worth half, rounded up
    static func habit(_ p: PromiseItem, status: LogStatus?) -> Int {
        let full = effort(p).points
        switch status {
        case .done?: return full
        case .tiny?: return (full + 1) / 2
        default: return 0
        }
    }
}

@MainActor
extension Store {
    /// Everything that gives points on a day. `closing` counts closing the day before it is saved as closed.
    func pointLines(on day: String = Day.today, closing: Bool = false) -> [PointLine] {
        var lines: [PointLine] = []
        for p in dueCounted(on: day) {
            let got = PointRules.habit(p, status: status(p, on: day))
            lines.append(PointLine(id: "habit." + p.id, title: p.title, icon: p.icon, points: got > 0 ? got : PointRules.effort(p).points, earned: got > 0))
        }
        if profile.on("training") {
            let trained = sessions(on: day).contains { s in s.end != nil && s.sets.contains { $0.done } }
            lines.append(PointLine(id: "workout", title: "Treino completo", icon: "dumbbell.fill", points: PointRules.workout, earned: trained))
        }
        let slept = health[day]?.sleep.map { $0.asleep >= profile.sleepNeed } ?? false
        lines.append(PointLine(id: "sleep", title: "Dormir o que precisas", icon: "bed.double.fill", points: PointRules.sleep, earned: slept))
        let walked = health[day]?.steps.map { $0 >= Double(profile.stepGoal) } ?? false
        lines.append(PointLine(id: "steps", title: "Chegar aos passos", icon: "figure.walk", points: PointRules.steps, earned: walked))
        if profile.on("fuel") {
            let f = fuel(on: day)
            lines.append(PointLine(id: "protein", title: "Chegar à proteína", icon: "fork.knife", points: PointRules.protein, earned: f.protein >= profile.proteinTarget))
            lines.append(PointLine(id: "water", title: "Beber a água do dia", icon: "drop.fill", points: PointRules.water, earned: f.water >= max(1, waterGoal(on: day))))
        }
        lines.append(PointLine(id: "closing", title: "Fechar o dia", icon: "moon.fill", points: PointRules.closing, earned: closing || self.day(day).closedAt != nil))
        return lines
    }

    func points(on day: String = Day.today, closing: Bool = false) -> Int {
        pointLines(on: day, closing: closing).filter(\.earned).map(\.points).reduce(0, +)
    }
}
