// Smart setup: a few questions about you, your training and your goal, then targets from published guidance, each
// with its reason. Calories start from your Air's measured burn when there's enough of it, otherwise from the
// Mifflin-St Jeor equation; the weekly check-in then adjusts them to what your weight actually does.
// The answers are kept, so the goal can change anytime (GoalMenu) and every target follows.
import SwiftUI

struct SetupInputs: Codable, Equatable {
    var male = true
    var age = 25
    var height = 178.0
    var weight = 76.0
    var bodyFat: Double?
    var job = "desk" // desk, mixed, feet, physical
    var trainingDays = 4
    var goal = "gain" // lose, gain, recomp, maintain
    var pace = "steady" // gentle, steady, fast
    var sleepHours = 8.0
    var wakeMinute = 7 * 60 + 15
}

struct SetupPlan {
    var kcal: Double
    var protein: Double
    var proteinPerKg: Double
    var fat: Double
    var carbs: Double
    var waterMl: Double
    var steps: Int
    var sleepNeed: Int
    var reasons: [(title: String, value: String, why: String)]
}

let goalNames = ["lose": "Lose fat", "gain": "Build muscle", "recomp": "Recomposition", "maintain": "Maintain"]

enum SetupPlanner {
    static func plan(_ i: SetupInputs, airBurn: Double?, averageSteps: Double?) -> SetupPlan {
        var reasons: [(title: String, value: String, why: String)] = []
        // Resting burn
        let bmr: Double
        if let bf = i.bodyFat {
            let lean = i.weight * (1 - bf / 100)
            bmr = 370 + 21.6 * lean
            reasons.append(("Resting burn", "\(Int(bmr)) kcal", "Katch-McArdle from your lean mass (\(kg((lean * 10).rounded() / 10)) kg)."))
        } else {
            bmr = 10 * i.weight + 6.25 * i.height - 5 * Double(i.age) + (i.male ? 5 : -161)
            reasons.append(("Resting burn", "\(Int(bmr)) kcal", "Mifflin-St Jeor, the most accurate of the common equations in validation studies (within 10% for most people)."))
        }
        // Daily burn: the Air's measurement, else activity factors
        let jobFactor = ["desk": 1.25, "mixed": 1.4, "feet": 1.55, "physical": 1.75][i.job] ?? 1.3
        let training = Double(i.trainingDays) * 300 / 7 // a 60-minute lifting session burns roughly 250–350 kcal
        let formula = bmr * jobFactor + training
        let tdee: Double
        if let burn = airBurn {
            tdee = burn * 0.9 + formula * 0.1 // wrist trackers tend to read a little high; lean on the measurement
            reasons.append(("Daily burn", "\(Int(tdee).formatted()) kcal", "From your Air's average over the last 14 days (\(Int(burn).formatted()) kcal), with a small correction toward the equation."))
        } else {
            tdee = formula
            reasons.append(("Daily burn", "\(Int(tdee).formatted()) kcal", "Your resting burn × \(String(format: "%.2f", jobFactor)) for your day, plus about \(Int(training)) kcal a day of training."))
        }
        // Calories for the goal
        var kcal = tdee
        switch i.goal {
        case "lose":
            let rate = ["gentle": 0.005, "steady": 0.007, "fast": 0.01][i.pace] ?? 0.007
            let deficit = min(1000, rate * i.weight * 7700 / 7)
            kcal = max(i.male ? 1500 : 1200, tdee - deficit)
            reasons.append(("Calories", "\(Int(kcal).formatted()) kcal", "A deficit of \(Int(deficit)) kcal a day loses about \(kg((rate * i.weight * 100).rounded() / 100)) kg a week (about 7,700 kcal per kg of fat), within the 0.5–1% a week that keeps muscle (Helms et al. 2014)."))
        case "gain":
            let rate = ["gentle": 0.0025, "steady": 0.005, "fast": 0.01][i.pace] ?? 0.005
            let surplus = max(150, min(500, rate * i.weight * 7700 / 30))
            kcal = tdee + surplus
            reasons.append(("Calories", "\(Int(kcal).formatted()) kcal", "A surplus of \(Int(surplus)) kcal a day, about \(kg((rate * i.weight * 100).rounded() / 100)) kg a month: a lean bulk. Trained lifters gain little extra muscle from bigger surpluses, mostly fat (Iraki et al. 2019)."))
        case "recomp":
            kcal = tdee * 0.9
            reasons.append(("Calories", "\(Int(kcal).formatted()) kcal", "10% under your burn: slow fat loss while high protein and training keep building muscle."))
        default:
            reasons.append(("Calories", "\(Int(kcal).formatted()) kcal", "At your burn, to hold your weight."))
        }
        // Protein
        let deficit = i.goal == "lose" || i.goal == "recomp"
        let perKg = deficit ? 2.2 : 1.8
        let protein = (i.weight * perKg).rounded()
        reasons.append(("Protein", "\(Int(protein)) g", deficit
            ? "2.2 g per kg: in a deficit, higher protein protects muscle (Helms et al. 2014 suggest 2.3–3.1 g per kg of lean mass)."
            : "1.8 g per kg: muscle gain levels off around 1.6 g per kg in the largest meta-analysis (Morton et al. 2018), with some people benefiting up to 2.2."))
        // Fat and carbs
        let fat = max(i.weight * 0.8, kcal * 0.25 / 9).rounded()
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4).rounded()
        reasons.append(("Fat and carbs", "\(Int(fat)) g · \(Int(carbs)) g", "Fat at least 0.8 g per kg and 25% of calories for hormones; the rest is carbs, which fuel hard training."))
        // Water
        let water = max(i.male ? 2000 : 1600, (i.weight * 35 / 50).rounded() * 50 - 500)
        reasons.append(("Water", String(format: "%.1f L", water / 1000), "About 35 ml per kg in total (EFSA: 2.5 L a day for men, 2.0 for women, including the ~20% that comes from food). Training days add 0.5 L, hot days more."))
        // Steps
        let current = averageSteps ?? 6000
        let steps = current < 6000 ? Int((current + 1500) / 500) * 500 : current < 8000 ? 8000 : 10000
        reasons.append(("Steps", steps.formatted(), "The mortality benefit of steps levels off around 8,000–10,000 a day under 60 (Paluch et al., Lancet 2022). Set a step above where you are now."))
        // Sleep
        let need = Int(i.sleepHours * 60)
        reasons.append(("Sleep", duration(need), "Asleep, not in bed: what you feel best on, within the 7–9 hours recommended for adults (AASM). Lights out is set from your wake time."))
        reasons.append(("Creatine", "3–5 g a day", "The ISSN position stand: 3–5 g daily keeps muscle stores full; timing barely matters, consistency does."))
        return SetupPlan(kcal: (kcal / 10).rounded() * 10, protein: protein, proteinPerKg: perKg, fat: fat, carbs: carbs, waterMl: water, steps: steps, sleepNeed: need, reasons: reasons)
    }
}

@MainActor
extension Store {
    var airBurn: Double? {
        let days = (1...14).compactMap { health[Day.add(-$0, to: Day.today)]?.calories }.filter { $0 > 1200 }
        return days.count >= 7 ? days.reduce(0, +) / Double(days.count) : nil
    }

    var averageSteps14: Double? {
        let s = (1...14).compactMap { health[Day.add(-$0, to: Day.today)]?.steps }
        return s.count >= 5 ? s.reduce(0, +) / Double(s.count) : nil
    }

    var setupInputs: SetupInputs {
        if let s = profile.setup { return s }
        var i = SetupInputs()
        i.male = profile.male; i.age = profile.age; i.height = profile.heightCm; i.weight = profile.weightKg
        i.goal = goalNames[profile.goal] == nil ? "gain" : profile.goal
        i.sleepHours = Double(profile.sleepNeed) / 60
        i.wakeMinute = profile.wakeMinute
        i.trainingDays = max(i.trainingDays, templates.flatMap(\.weekdays).count)
        return i
    }

    /// Sets every target from the setup answers; used by the wizard and by changing the goal anywhere
    func applySetup(_ i: SetupInputs) {
        let p = SetupPlanner.plan(i, airBurn: airBurn, averageSteps: averageSteps14)
        update { pr in
            pr.setup = i
            pr.male = i.male; pr.age = i.age; pr.heightCm = i.height; pr.weightKg = i.weight
            pr.goal = i.goal; pr.kcalTarget = p.kcal; pr.proteinPerKg = p.proteinPerKg
            pr.waterGoalMl = p.waterMl; pr.stepGoal = p.steps; pr.sleepNeed = p.sleepNeed
            pr.wakeMinute = i.wakeMinute
            pr.fatTarget = p.fat; pr.carbTarget = p.carbs; pr.setupDone = true
        }
    }

    func changeGoal(_ goal: String, pace: String? = nil) {
        var i = setupInputs
        i.goal = goal
        if let pace { i.pace = pace }
        if let w = all(WeightEntry.self).max(by: { $0.date < $1.date }) { i.weight = w.kg }
        applySetup(i)
    }
}

/// The goal, changeable in one tap; every target follows
struct GoalMenu: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Menu {
            Menu("Lose fat") { paces("lose") }
            Menu("Build muscle") { paces("gain") }
            Button("Recomposition") { store.changeGoal("recomp") }
            Button("Maintain") { store.changeGoal("maintain") }
        } label: {
            let i = store.setupInputs
            let pace = i.goal == "lose" || i.goal == "gain" ? " · \(i.pace)" : ""
            Label((goalNames[store.profile.goal] ?? "Goal") + pace, systemImage: "target")
                .font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.09)).overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1)))
        }
    }

    @ViewBuilder private func paces(_ goal: String) -> some View {
        Button("Gentle") { store.changeGoal(goal, pace: "gentle") }
        Button("Steady") { store.changeGoal(goal, pace: "steady") }
        Button("Fast") { store.changeGoal(goal, pace: "fast") }
    }
}

struct SmartSetup: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var i = SetupInputs()
    @State private var wake = Date()
    var startPage = 0

    private let pages = ["You", "Your days", "Your goal", "Sleep", "Your plan"]

    var body: some View {
        NavigationStack {
            Form {
                switch page {
                case 0:
                    Section {
                        Picker("Sex", selection: $i.male) { Text("Male").tag(true); Text("Female").tag(false) }.pickerStyle(.segmented)
                        Stepper("Age \(i.age)", value: $i.age, in: 14...90)
                        Stepper("Height \(Int(i.height)) cm", value: $i.height, in: 130...220)
                        Stepper("Weight \(kg(i.weight)) kg", value: $i.weight, in: 35...200, step: 0.5)
                        Toggle("I know my body fat", isOn: Binding(get: { i.bodyFat != nil }, set: { i.bodyFat = $0 ? 16 : nil }))
                        if let bf = i.bodyFat { Stepper("Body fat \(Int(bf))%", value: Binding(get: { bf }, set: { i.bodyFat = $0 }), in: 4...50) }
                    } footer: { Text("Body fat is optional: with it, the resting burn uses lean mass (Katch-McArdle), which is more accurate for trained people.") }
                case 1:
                    Section("Work and daily life") {
                        Picker("Most of the day", selection: $i.job) {
                            Text("At a desk").tag("desk"); Text("Mixed, some walking").tag("mixed"); Text("On my feet").tag("feet"); Text("Physical work").tag("physical")
                        }
                        .pickerStyle(.inline)
                    }
                    Section {
                        Stepper("Training \(i.trainingDays) days a week", value: $i.trainingDays, in: 0...7)
                        if let steps = store.averageSteps14 { LabeledContent("Your steps, 14-day average", value: Int(steps).formatted()) }
                        if let burn = store.airBurn { LabeledContent("Burned per day, your Air", value: "\(Int(burn).formatted()) kcal") }
                    } footer: { Text(store.airBurn != nil ? "Your Air's measured burn is the starting point; the answers refine the rest." : "Without enough Air data yet, the activity answers set the burn.") }
                case 2:
                    Section {
                        Picker("Goal", selection: $i.goal) {
                            Text("Lose fat").tag("lose"); Text("Build muscle").tag("gain"); Text("Recomposition").tag("recomp"); Text("Maintain").tag("maintain")
                        }
                        .pickerStyle(.inline)
                        if i.goal == "lose" || i.goal == "gain" {
                            Picker("Pace", selection: $i.pace) { Text("Gentle").tag("gentle"); Text("Steady").tag("steady"); Text("Fast").tag("fast") }.pickerStyle(.segmented)
                        }
                    } footer: { Text(goalHelp) }
                case 3:
                    Section {
                        Stepper("I feel best on \(String(format: "%.1f", i.sleepHours)) h", value: $i.sleepHours, in: 6...10, step: 0.25)
                        DatePicker("I wake up at", selection: $wake, displayedComponents: .hourAndMinute)
                        if let real = averageSleep { LabeledContent("Your average, last 14 nights", value: duration(real)) }
                    } footer: { Text("Adults need 7 hours or more (AASM and Sleep Research Society); young adults usually 7–9. If you don't know, 8 is a good start; Cadence learns from your readiness.") }
                default:
                    let p = SetupPlanner.plan(i, airBurn: store.airBurn, averageSteps: store.averageSteps14)
                    Section("Your daily targets") {
                        row("Calories", "\(Int(p.kcal).formatted()) kcal")
                        row("Protein", "\(Int(p.protein)) g")
                        row("Fat", "\(Int(p.fat)) g")
                        row("Carbs", "\(Int(p.carbs)) g")
                        row("Water, drinks", String(format: "%.1f L", p.waterMl / 1000))
                        row("Steps", p.steps.formatted())
                        row("Sleep", duration(p.sleepNeed) + " asleep")
                    }
                    Section("Why these numbers") {
                        ForEach(p.reasons, id: \.title) { r in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(r.title).font(.geist(14, .semibold)); Spacer(); Text(r.value).font(.mono(13)).foregroundStyle(Color.mint) }
                                Text(r.why).font(.geist(12.5)).foregroundStyle(Color.soft)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Section { Text("Starting points from population research, not medical advice. Every week Cadence compares what you ate with how your weight moved and offers a corrected calorie target. Change the goal anytime from Fuel; every target follows.").font(.footnote).foregroundStyle(Color.faint) }
                }
            }
            .cadenceList()
            .navigationTitle(pages[page])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(page == 0 ? "Cancel" : "Back") { if page == 0 { dismiss() } else { page -= 1 } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(page == pages.count - 1 ? "Use these" : "Next") { if page == pages.count - 1 { apply() } else { page += 1 } }.bold()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name); Spacer(); Text(value).font(.mono(15, .medium)) }
    }

    private var goalHelp: String {
        switch i.goal {
        case "lose": return "Gentle: about 0.5% of your weight a week, steady 0.7%, fast 1%. Slower losses keep more muscle (Helms et al. 2014)."
        case "gain": return "Gentle: about 0.25% of your weight a month above maintenance, steady 0.5%, fast 1%. Bigger surpluses add mostly fat (Iraki et al. 2019)."
        case "recomp": return "A small deficit with high protein and hard training: slow scale change, fat down, muscle up. Works best for newer lifters or after a break."
        default: return "Eat at your burn; protein stays high to keep muscle."
        }
    }

    private var averageSleep: Int? {
        let s = (0..<14).compactMap { store.health[Day.add(-$0, to: Day.today)]?.sleep?.asleep }
        return s.count >= 5 ? s.reduce(0, +) / s.count : nil
    }

    private func load() {
        i = store.setupInputs
        if let w = store.all(WeightEntry.self).max(by: { $0.date < $1.date }) { i.weight = w.kg }
        wake = Day.at(i.wakeMinute, on: Day.today)
        page = startPage
    }

    private func apply() {
        i.wakeMinute = Day.minuteOfDay(wake)
        store.applySetup(i)
        store.save(WeightEntry(kg: i.weight))
        dismiss()
    }
}
