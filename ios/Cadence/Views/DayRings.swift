// The rings on Today: sleep, recovery and strain on top, the day's five below. Every ring has a bar for the target right
// now. On the five a full circle is the whole day; on the top three the circle is a fixed scale and the bar the target.
import SwiftUI

struct RingStat: Identifiable {
    /// Internal and stable: sleep, recovery, strain, calories, protein, water, move, promises. It's the ring's id, its
    /// accessibility identifier (ring.<key>) and what code looks a ring up by. Never shown and never translated: when
    /// `name` changes (a translation, or "Promises" becoming another word), the key stays the same.
    var key: String
    var name: String
    var value: Double
    var target: Double
    var pace: Double? // share of the target due by now
    var area: Area
    var center: String
    var goal: String
    var now: String?
    var id: String { key }
    var progress: Double { value / max(0.001, target) }
    var behind: Bool { pace.map { progress + 0.05 < $0 } ?? false }
}

@MainActor
extension Store {
    /// Today's training: what really happened if it's finished or running, otherwise the block you placed or the
    /// template at 18:00, moved to finish before a trip or event that's in the way
    func trainingSlot(on day: String = Day.today) -> (start: Int, end: Int, title: String, done: Bool)? {
        func minute(_ ms: Double) -> Int { Day.minuteOfDay(Date(timeIntervalSince1970: ms / 1000)) }
        if let s = sessions(on: day).first(where: { $0.end != nil }), let end = s.end { return (minute(s.start), minute(end), s.name, true) }
        let planned = templates.first { $0.weekdays.contains(Day.weekday(day)) }
        if let s = sessions(on: day).first(where: { $0.end == nil && nowMs() - $0.start < 3 * 3600 * 1000 }) {
            let m = minute(s.start)
            return (m, m + (planned?.minutes ?? 70), s.name, false)
        }
        if let b = all(PlanBlock.self).first(where: { $0.date == day && $0.type == "training" }) { return (b.start, b.start + b.minutes, b.title, false) }
        guard let t = planned else { return nil }
        var start = 18 * 60
        if let b = busy(on: day).first(where: { $0.start < start + t.minutes + 15 && $0.end > start }) { start = max(profile.wakeMinute + 60, b.start - t.minutes - 15) }
        return (start, start + t.minutes, t.name, false)
    }

    func kitchenClose(on day: String = Day.today) -> Int {
        Engine.kitchenClose(lightsOut: sleepPlan(for: day).perform, trainingEnd: trainingSlot(on: day)?.end)
    }

    var strainToday: Double {
        let h = health[Day.today]
        let trained = sessions(on: Day.today).compactMap { s in s.end.map { ($0 - s.start) / 60000 } }.reduce(0, +)
        return Engine.strain(azm: h?.azm ?? 0, workoutMinutes: trained, steps: h?.steps ?? 0)
    }

    /// Your typical recovery: the median of the last 14 days, or a good day until there's history
    var usualRecovery: Int {
        let scores = (1...14).compactMap { readiness(on: Day.add(-$0, to: Day.today))?.score }.sorted()
        return scores.count >= 4 ? scores[scores.count / 2] : 67
    }

    var strainTarget: Double { Engine.strainTarget(recovery: readiness()?.score, minimumDay: isMinimumDay()) }

    /// Things Pip is waiting on right now: the only reason for a number on Pip's head
    var pipNotices: Int {
        let m = Day.minuteOfDay(tick)
        return due().filter { status($0) == nil && time(of: $0) <= m }.count
    }

    var gymBagDue: Bool {
        sessions(on: Day.today).contains { $0.end != nil } && records("gymBag")[Day.today] == nil
    }

    func unpackedGymBag(on day: String = Day.today) {
        put("gymBag", day, .bool(true))
        Reminders.shared.reschedule()
    }

    var journalDue: Bool {
        let yesterday = Day.add(-1, to: Day.today)
        guard !TestMode.active, Day.minuteOfDay(tick) < 15 * 60, records("journalLater")[Day.today] == nil else { return false }
        let answered = record(JournalDay.self, yesterday)?.answered.count ?? 0
        return answered < journalQuestions.count
    }

    func ringStats() -> (main: [RingStat], day: [RingStat]) {
        let minute = TestMode.minute ?? Day.minuteOfDay(tick)
        let p = profile, plan = sleepPlan(), h = health[Day.today], f = fuel()
        let eat = Engine.paceShare(minute: minute, wake: p.wakeMinute, end: kitchenClose())
        let walk = Engine.paceShare(minute: minute, wake: p.wakeMinute, end: plan.windDown)
        let drink = Engine.paceShare(minute: minute, wake: p.wakeMinute, end: plan.perform - 120)
        let goal = waterGoal()
        let due = self.due()
        let done = due.filter { status($0).map { $0 != .skipped } ?? false }.count
        let dueNow = due.filter { time(of: $0) <= minute }.count
        let steps = h?.steps ?? 0
        let r = readiness()
        let asleep = h?.sleep?.asleep
        let strain = strainToday, strainGoal = strainTarget
        let sleepScale = Double(max(600, p.sleepNeed + 60)), usual = usualRecovery
        func k(_ v: Double) -> String { v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))" }
        func litres(_ v: Double) -> String { String(format: "%.1fL", v / 1000) }
        let main = [
            // sleep and recovery run on a fixed scale too, with the bar on what you need and what's usual for you
            RingStat(key: "sleep", name: "Sleep", value: Double(asleep ?? 0), target: sleepScale, pace: Double(p.sleepNeed) / sleepScale, area: .sleep, center: asleep.map { duration($0) } ?? "–", goal: "need \(duration(p.sleepNeed))"),
            RingStat(key: "recovery", name: "Recovery", value: Double(r?.score ?? 0), target: 100, pace: Double(usual) / 100, area: .mint, center: r.map { "\($0.score)" } ?? "–", goal: "usual \(usual)"),
            // strain runs on a fixed 0–100% scale, so the circle is the maximum and the bar is today's target on it
            RingStat(key: "strain", name: "Strain", value: strain, target: Engine.strainMax, pace: strainGoal / Engine.strainMax, area: .train, center: "\(Int(strain / Engine.strainMax * 100))%", goal: "target \(Int(strainGoal / Engine.strainMax * 100))%" + (strain >= strainGoal ? " ✓" : "")),
        ]
        let day = [
            RingStat(key: "calories", name: "Calories", value: f.kcal, target: p.kcal, pace: eat, area: .fuel, center: k(f.kcal), goal: "of \(k(p.kcal))", now: "now \(k(p.kcal * eat))"),
            RingStat(key: "protein", name: "Protein", value: f.protein, target: p.proteinTarget, pace: eat, area: .train, center: "\(Int(f.protein))g", goal: "of \(Int(p.proteinTarget))g", now: "now \(Int(p.proteinTarget * eat))g"),
            RingStat(key: "water", name: "Water", value: f.water, target: goal, pace: drink, area: .water, center: litres(f.water), goal: "of \(litres(goal))", now: "now \(litres(goal * drink))"),
            RingStat(key: "move", name: "Move", value: steps, target: Double(p.stepGoal), pace: walk, area: .mint, center: k(steps), goal: "of \(k(Double(p.stepGoal)))", now: "now \(k(Double(p.stepGoal) * walk))"),
            RingStat(key: "promises", name: "Promises", value: Double(done), target: Double(max(1, due.count)), pace: due.isEmpty ? 0 : Double(dueNow) / Double(due.count), area: .mind, center: "\(done)/\(due.count)", goal: "of \(due.count)", now: "now \(dueNow)"),
        ]
        return (main, day)
    }
}

struct DayRings: View {
    @EnvironmentObject var store: Store
    @Binding var loggingFood: Bool

    var body: some View {
        let stats = store.ringStats()
        Card {
            HStack(spacing: 8) {
                ForEach(stats.main) { mainRing($0) }
            }
            Divider().overlay(Color.white.opacity(0.06))
            HStack(alignment: .top, spacing: 2) {
                ForEach(stats.day) { smallRing($0) }
            }
            HStack {
                Text("Bar: your target right now. Sleep shows what you need, recovery what's usual for you, strain today's target (an estimate). The rest: where you should be by now, with a full circle for the whole day.").font(.geist(10.5)).foregroundStyle(Color.faint)
                Spacer()
            }
            HStack {
                Button { loggingFood = true } label: {
                    Label("Food", systemImage: "plus").font(.geist(12.5, .semibold)).foregroundStyle(Color(hex: 0x2B1A05))
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(Area.fuel.gradient))
                }
                .buttonStyle(Pressable())
                Button { store.addWater(250) } label: {
                    Label("250 ml", systemImage: "drop.fill").font(.geist(12.5, .semibold)).foregroundStyle(Color(hex: 0x03202A))
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(Area.water.gradient))
                }
                .buttonStyle(Pressable())
                Spacer()
            }
        }
    }

    @ViewBuilder private func mainRing(_ s: RingStat) -> some View {
        if s.key == "sleep" {
            NavigationLink { SleepView() } label: { mainLabel(s) }.buttonStyle(.plain).frame(maxWidth: .infinity)
        } else if s.key == "recovery" {
            NavigationLink { ReadinessView() } label: { mainLabel(s) }.buttonStyle(.plain).frame(maxWidth: .infinity)
        } else {
            mainLabel(s).frame(maxWidth: .infinity)
        }
    }

    private func mainLabel(_ s: RingStat) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Ring(progress: s.progress, area: s.area, width: 9, marker: s.pace)
                Text(s.center).font(.geist(15, .bold)).minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12)
            }
            .frame(width: 88, height: 88)
            Text(s.name).font(.geist(13, .semibold))
            Text(s.goal).font(.geist(11)).foregroundStyle(Color.soft).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("ring.\(s.key)")
    }

    private func smallRing(_ s: RingStat) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Ring(progress: s.progress, area: s.area, width: 5, marker: s.pace)
                Text(s.center).font(.geist(10.5, .semibold)).minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 6)
            }
            .frame(width: 52, height: 52)
            Text(s.name).font(.geist(10.5)).foregroundStyle(Color.soft).lineLimit(1).minimumScaleFactor(0.7)
            Text(s.goal).font(.geist(10)).foregroundStyle(Color.faint).lineLimit(1).minimumScaleFactor(0.7)
            if let now = s.now { Text(now).font(.geist(10, s.behind ? .semibold : .regular)).foregroundStyle(s.behind ? Color.warn : Color.faint).lineLimit(1).minimumScaleFactor(0.7) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine).accessibilityIdentifier("ring.\(s.key)")
    }
}

/// Today's shower and the reason for the suggestion, with a one-tap log
struct ShowerTodayCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if store.profile.on("care"), let s = store.showerPlan() {
            Card {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "shower.fill").foregroundStyle(Color.water).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.when == .tonight ? "Shower tonight around \(clock(Day.minuteOfDay(s.at)))" : "Shower tomorrow morning around \(clock(Day.minuteOfDay(s.at)))").font(.geist(14, .semibold))
                        Text(s.why).font(.geist(12)).foregroundStyle(Color.soft)
                        Button(s.when == .tonight ? "Rather tomorrow morning" : "Rather tonight") { store.pickShower(s.when == .tonight ? .morning : .tonight) }
                            .font(.geist(12, .semibold)).tint(.water).accessibilityIdentifier("shower.switch")
                    }
                    Spacer()
                    Button { store.logShower() } label: { Image(systemName: "checkmark").font(.geist(15, .bold)).foregroundStyle(Color(hex: 0x03202A)).frame(width: 44, height: 44).background(Circle().fill(Area.water.gradient)) }
                        .buttonStyle(Pressable()).accessibilityLabel("Showered").accessibilityIdentifier("shower.done")
                }
            }
            .accessibilityIdentifier("shower.today")
        }
    }
}

/// After a workout: the bag doesn't unpack itself
struct GymBagCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if store.gymBagDue {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "bag.fill").foregroundStyle(Color.train).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unpack the gym bag").font(.geist(14, .semibold))
                        Text("Clothes in the wash, towel out to dry.").font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer()
                    Button { store.unpackedGymBag() } label: { Image(systemName: "checkmark").font(.geist(15, .bold)).foregroundStyle(Color(hex: 0x032018)).frame(width: 44, height: 44).background(Circle().fill(Area.mint.gradient)) }
                        .buttonStyle(Pressable()).accessibilityLabel("Unpacked").accessibilityIdentifier("gymbag.done")
                }
            }
        }
    }
}
