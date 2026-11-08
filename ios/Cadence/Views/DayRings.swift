// The rings on Today: sleep, recovery and strain on top, the day's five below. Every ring has a bar for the target right
// now. On the five a full circle is the whole day; on the top three the circle is a fixed scale and the bar the target.
// No data is not zero (phase 2.4): a ring with nothing from the band is dashed, with no number and «sem dados»; food and
// water with nothing logged keep their number with «sem registos», never as a failure. The source stays in sight.
import SwiftUI

/// The rings' internal keys. A key is the ring's id, its accessibility identifier (ring.<key>) and what code looks a
/// ring up by, so a misspelt one doesn't compile. Never shown and never translated: when a ring's name changes (a
/// translation, or "Promises" becoming another word), its key stays the same.
enum RingKey: String, CaseIterable {
    case sleep, recovery, strain, calories, protein, water, move, promises
}

struct RingStat: Identifiable {
    var key: RingKey
    var name: String
    var value: Double
    var target: Double
    var pace: Double? // share of the target due by now
    var area: Area
    var center: String
    var goal: String
    var now: String?
    /// Nothing to show (no band data): a dashed ring, no number, «sem dados»
    var noData = false
    /// Shown in place of the pace line, never as a failure («sem registos»)
    var note: String? = nil
    var id: String { key.rawValue }
    /// What the UI tests find the ring by
    var accessibilityID: String { "ring.\(key.rawValue)" }
    var progress: Double { value / max(0.001, target) }
    var behind: Bool {
        guard !noData, note == nil else { return false }
        return pace.map { progress + 0.05 < $0 } ?? false
    }

    static let noDataText = "sem dados", noRecordsText = "sem registos"

    /// The rings in one line, when an urgent step takes the top of Today: "Sono 7h 05m · recuperação 58 · esforço 12%"
    static func summary(_ rings: [RingStat]) -> String {
        rings.enumerated().map { i, s in (i == 0 ? s.name : s.name.lowercased()) + " " + (s.noData ? noDataText : s.center) }.joined(separator: " · ")
    }
}

/// How long ago, in the design's words: "há 8 min", "há 2 h", "há 3 dias"
enum TodayFormat {
    static func ago(minutes m: Int) -> String {
        if m < 1 { return "agora mesmo" }
        if m < 60 { return "há \(m) min" }
        if m < 24 * 60 { return "há \(m / 60) h" }
        let d = m / (24 * 60)
        return d == 1 ? "há 1 dia" : "há \(d) dias"
    }
}

@MainActor
extension Store {
    /// Today's training: what really happened if it's finished or running, otherwise the block you placed or the
    /// template at 18:00, moved to finish before a trip or event that's in the way
    func trainingSlot(on day: String = Day.today) -> (start: Int, end: Int, title: String, done: Bool)? {
        func minute(_ ms: Double) -> Int { Day.minuteOfDay(Date(timeIntervalSince1970: ms / 1000)) }
        // Finished, or left open past its day: then it's partial up to its last activity, as in Treino (decision D23; nothing is written)
        if let s = sessions(on: day).first(where: { $0.end != nil || TrainingRules.leftPartial($0, today: Day.today) }) { return (minute(s.start), minute(s.end ?? TrainingRules.lastActivity(s)), s.name, true) }
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
        let due = self.dueCounted() // «Não se aplica» leaves both sides of the count
        let done = due.filter { status($0).map { $0 != .skipped } ?? false }.count
        let dueNow = due.filter { time(of: $0) <= minute }.count
        let steps = h?.steps ?? 0
        let r = readiness()
        let asleep = h?.sleep?.asleep
        let strain = strainToday, strainGoal = strainTarget
        let sleepScale = Double(max(600, p.sleepNeed + 60)), usual = usualRecovery
        // No data is not zero: sleep, recovery and strain with nothing from the band (a workout logged here counts
        // for strain), and steps with no count, are «sem dados». Food and water with nothing logged today keep their
        // number, with «sem registos» instead of the pace line.
        let strainKnown = h?.azm != nil || h?.steps != nil || sessions(on: Day.today).contains { $0.end != nil }
        let stepsKnown = h?.steps != nil
        let foodLogged = !foods().isEmpty
        let waterLogged = all(WaterEntry.self).contains { $0.date == Day.today }
        let none = RingStat.noDataText
        let foodNote: String? = foodLogged ? nil : RingStat.noRecordsText
        let waterNote: String? = waterLogged ? nil : RingStat.noRecordsText
        func k(_ v: Double) -> String { v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))" }
        func litres(_ v: Double) -> String { String(format: "%.1fL", v / 1000) }
        let sleepGoal: String = asleep == nil ? none : "precisas de \(duration(p.sleepNeed))"
        let recoveryGoal: String = r == nil ? none : "habitual \(usual)"
        let strainAim: String = "alvo \(Int(strainGoal / Engine.strainMax * 100))%" + (strain >= strainGoal ? " ✓" : "")
        let strainCenter: String = strainKnown ? "\(Int(strain / Engine.strainMax * 100))%" : "—"
        let stepsCenter: String = stepsKnown ? k(steps) : "—"
        let stepsGoal: String = stepsKnown ? "de \(k(Double(p.stepGoal)))" : none
        let stepsNow: String? = stepsKnown ? "agora \(k(Double(p.stepGoal) * walk))" : nil
        let main: [RingStat] = [
            // sleep and recovery run on a fixed scale too, with the bar on what you need and what's usual for you
            RingStat(key: .sleep, name: "Sono", value: Double(asleep ?? 0), target: sleepScale, pace: Double(p.sleepNeed) / sleepScale, area: .sleep, center: asleep.map { duration($0) } ?? "—", goal: sleepGoal, noData: asleep == nil),
            RingStat(key: .recovery, name: "Recuperação", value: Double(r?.score ?? 0), target: 100, pace: Double(usual) / 100, area: .mint, center: r.map { "\($0.score)" } ?? "—", goal: recoveryGoal, noData: r == nil),
            // strain runs on a fixed 0–100% scale, so the circle is the maximum and the bar is today's target on it
            RingStat(key: .strain, name: "Esforço", value: strain, target: Engine.strainMax, pace: strainGoal / Engine.strainMax, area: .train, center: strainCenter, goal: strainKnown ? strainAim : none, noData: !strainKnown),
        ]
        let day: [RingStat] = [
            RingStat(key: .calories, name: "Calorias", value: f.kcal, target: p.kcal, pace: eat, area: .fuel, center: k(f.kcal), goal: "de \(k(p.kcal))", now: "agora \(k(p.kcal * eat))", note: foodNote),
            RingStat(key: .protein, name: "Proteína", value: f.protein, target: p.proteinTarget, pace: eat, area: .train, center: "\(Int(f.protein))g", goal: "de \(Int(p.proteinTarget))g", now: "agora \(Int(p.proteinTarget * eat))g", note: foodNote),
            RingStat(key: .water, name: "Água", value: f.water, target: goal, pace: drink, area: .water, center: litres(f.water), goal: "de \(litres(goal))", now: "agora \(litres(goal * drink))", note: waterNote),
            RingStat(key: .move, name: "Passos", value: steps, target: Double(p.stepGoal), pace: walk, area: .mint, center: stepsCenter, goal: stepsGoal, now: stepsNow, noData: !stepsKnown),
            RingStat(key: .promises, name: "Hábitos", value: Double(done), target: Double(max(1, due.count)), pace: due.isEmpty ? 0 : Double(dueNow) / Double(due.count), area: .mind, center: "\(done)/\(due.count)", goal: "de \(due.count)", now: "agora \(dueNow)"),
        ]
        return (main, day)
    }

    /// Where the rings' band data came from and when, for the source line: "Fitbit Air · há 8 min". Nil when nothing
    /// has come yet.
    var ringsSource: String? {
        if profile.usesBand {
            guard let s = device?.lastSync else { return nil }
            let minutes = Int(Date().timeIntervalSince(ISO8601DateFormatter.lenient(s)) / 60)
            return "\(device?.name ?? "Fitbit") · \(TodayFormat.ago(minutes: minutes))"
        }
        guard let last = lastHealth else { return nil }
        return "Apple Health · \(TodayFormat.ago(minutes: Int(Date().timeIntervalSince(last) / 60)))"
    }
}

/// «Como estás»: the rings and where their data came from. The quick logs that were at the bottom are their own card
/// on Today now («Registar», ordered by use).
struct DayRings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let stats = store.ringStats()
        let nothingTonight = stats.main.filter { $0.key == .sleep || $0.key == .recovery }.allSatisfy(\.noData)
        Card {
            HStack(spacing: 8) {
                Eyebrow(text: "Como estás")
                if nothingTonight { StateTag(state: .noData, text: "Sem dados desta noite") }
                else if let source = store.ringsSource { SourceLine(text: source).lineLimit(1) }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("today.rings.source")
            HStack(spacing: 8) {
                ForEach(stats.main) { mainRing($0) }
            }
            Divider().overlay(Color.white.opacity(0.06))
            HStack(alignment: .top, spacing: 2) {
                ForEach(stats.day) { smallRing($0) }
            }
            HStack {
                Text("Barra: o teu alvo neste momento. No sono, o que precisas; na recuperação, o teu habitual; no esforço, o alvo de hoje (uma estimativa). Nos restantes: onde devias estar agora, com o círculo completo para o dia inteiro.").font(.geist(10.5)).foregroundStyle(Color.faint)
                Spacer()
            }
        }
    }

    @ViewBuilder private func mainRing(_ s: RingStat) -> some View {
        if s.key == .sleep {
            NavigationLink { SleepView() } label: { mainLabel(s) }.buttonStyle(.plain).frame(maxWidth: .infinity)
        } else if s.key == .recovery {
            NavigationLink { ReadinessView() } label: { mainLabel(s) }.buttonStyle(.plain).frame(maxWidth: .infinity)
        } else {
            mainLabel(s).frame(maxWidth: .infinity)
        }
    }

    private func mainLabel(_ s: RingStat) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Ring(progress: s.progress, area: s.area, width: 9, marker: s.pace, noData: s.noData)
                Text(s.center).font(.geist(15, .bold)).foregroundStyle(s.noData ? Color.faint : Color.primary).minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12)
                    .accessibilityHidden(s.noData) // no number: VoiceOver reads the name and «sem dados»
            }
            .frame(width: 88, height: 88)
            Text(s.name).font(.geist(13, .semibold))
            Text(s.goal).font(.geist(11)).foregroundStyle(Color.soft).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier(s.accessibilityID)
    }

    private func smallRing(_ s: RingStat) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Ring(progress: s.progress, area: s.area, width: 5, marker: s.pace, noData: s.noData)
                Text(s.center).font(.geist(10.5, .semibold)).foregroundStyle(s.noData ? Color.faint : Color.primary).minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 6)
                    .accessibilityHidden(s.noData)
            }
            .frame(width: 52, height: 52)
            Text(s.name).font(.geist(10.5)).foregroundStyle(Color.soft).lineLimit(1).minimumScaleFactor(0.7)
            Text(s.goal).font(.geist(10)).foregroundStyle(Color.faint).lineLimit(1).minimumScaleFactor(0.7)
            if let note = s.note { Text(note).font(.geist(10)).foregroundStyle(Color.faint).lineLimit(1).minimumScaleFactor(0.7) }
            else if let now = s.now { Text(now).font(.geist(10, s.behind ? .semibold : .regular)).foregroundStyle(s.behind ? Color.warn : Color.faint).lineLimit(1).minimumScaleFactor(0.7) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine).accessibilityIdentifier(s.accessibilityID)
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
                        Text(s.when == .tonight ? "Duche esta noite, por volta das \(clock(Day.minuteOfDay(s.at)))" : "Duche amanhã de manhã, por volta das \(clock(Day.minuteOfDay(s.at)))").font(.geist(14, .semibold))
                        Text(s.why).font(.geist(12)).foregroundStyle(Color.soft)
                        Button(s.when == .tonight ? "Prefiro amanhã de manhã" : "Prefiro esta noite") { store.pickShower(s.when == .tonight ? .morning : .tonight) }
                            .font(.geist(12, .semibold)).tint(.water).accessibilityIdentifier("shower.switch")
                    }
                    Spacer()
                    Button { store.logShower() } label: { Image(systemName: "checkmark").font(.geist(15, .bold)).foregroundStyle(Color(hex: 0x03202A)).frame(width: 44, height: 44).background(Circle().fill(Area.water.gradient)) }
                        .buttonStyle(Pressable()).accessibilityLabel("Já tomei duche").accessibilityIdentifier("shower.done")
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
                        Text("Esvaziar o saco do ginásio").font(.geist(14, .semibold))
                        Text("Roupa para lavar, toalha a secar.").font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer()
                    Button { store.unpackedGymBag() } label: { Image(systemName: "checkmark").font(.geist(15, .bold)).foregroundStyle(Color(hex: 0x032018)).frame(width: 44, height: 44).background(Circle().fill(Area.mint.gradient)) }
                        .buttonStyle(Pressable()).accessibilityLabel("Saco esvaziado").accessibilityIdentifier("gymbag.done")
                }
            }
        }
    }
}
