// Smart setup: a few questions about you, your training and your goal, then targets from published guidance, each
// with its reason. Calories start from your Air's measured burn when there's enough of it, otherwise from the
// Mifflin-St Jeor equation; the weekly check-in then adjusts them to what your weight actually does.
import SwiftUI

struct SetupPlan {
    var bmr: Double
    var tdee: Double
    var tdeeSource: String
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

struct SmartSetup: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var male = true
    @State private var age = 25
    @State private var height = 178.0
    @State private var weight = 76.0
    @State private var bodyFat: Double?
    @State private var job = "desk" // desk, mixed, on feet, physical
    @State private var trainingDays = 4
    @State private var goal = "gain" // lose, maintain, gain, recomp
    @State private var pace = "steady" // gentle, steady, fast
    @State private var sleepHours = 8.0
    @State private var wake = Date()

    private let pages = ["You", "Your days", "Your goal", "Sleep", "Your plan"]

    var body: some View {
        NavigationStack {
            Form {
                switch page {
                case 0:
                    Section {
                        Picker("Sex", selection: $male) { Text("Male").tag(true); Text("Female").tag(false) }.pickerStyle(.segmented)
                        Stepper("Age \(age)", value: $age, in: 14...90)
                        Stepper("Height \(Int(height)) cm", value: $height, in: 130...220)
                        Stepper("Weight \(kg(weight)) kg", value: $weight, in: 35...200, step: 0.5)
                        Toggle("I know my body fat", isOn: Binding(get: { bodyFat != nil }, set: { bodyFat = $0 ? 16 : nil }))
                        if let bf = bodyFat { Stepper("Body fat \(Int(bf))%", value: Binding(get: { bf }, set: { bodyFat = $0 }), in: 4...50) }
                    } footer: { Text("Body fat is optional: with it, the resting burn uses lean mass (Katch-McArdle), which is more accurate for trained people.") }
                case 1:
                    Section("Work and daily life") {
                        Picker("Most of the day", selection: $job) {
                            Text("At a desk").tag("desk"); Text("Mixed, some walking").tag("mixed"); Text("On my feet").tag("feet"); Text("Physical work").tag("physical")
                        }
                        .pickerStyle(.inline)
                    }
                    Section {
                        Stepper("Training \(trainingDays) days a week", value: $trainingDays, in: 0...7)
                        if let steps = averageSteps { LabeledContent("Your steps, 14-day average", value: Int(steps).formatted()) }
                        if let burn = airBurn { LabeledContent("Burned per day, your Air", value: "\(Int(burn).formatted()) kcal") }
                    } footer: { Text(airBurn != nil ? "Your Air's measured burn is used as the starting point; the questions refine the rest." : "Without enough Air data yet, the activity answers set the burn.") }
                case 2:
                    Section {
                        Picker("Goal", selection: $goal) {
                            Text("Lose fat").tag("lose"); Text("Build muscle").tag("gain"); Text("Recomposition").tag("recomp"); Text("Maintain").tag("maintain")
                        }
                        .pickerStyle(.inline)
                        if goal == "lose" || goal == "gain" {
                            Picker("Pace", selection: $pace) { Text("Gentle").tag("gentle"); Text("Steady").tag("steady"); Text("Fast").tag("fast") }.pickerStyle(.segmented)
                        }
                    } footer: { Text(goalHelp) }
                case 3:
                    Section {
                        Stepper("I feel best on \(String(format: "%.1f", sleepHours)) h", value: $sleepHours, in: 6...10, step: 0.25)
                        DatePicker("I wake up at", selection: $wake, displayedComponents: .hourAndMinute)
                        if let real = averageSleep { LabeledContent("Your average, last 14 nights", value: duration(real)) }
                    } footer: { Text("Adults need 7 hours or more (AASM and Sleep Research Society); young adults usually 7–9. If you don't know, 8 is a good start; Cadence learns from your readiness.") }
                default:
                    let p = plan
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
                    Section { Text("These are starting points from population research, not medical advice. Every week Cadence compares what you ate with how your weight moved and offers a corrected calorie target.").font(.footnote).foregroundStyle(Color.faint) }
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
        switch goal {
        case "lose": return "Gentle: about 0.5% of your weight a week, steady 0.7%, fast 1%. Slower losses keep more muscle (Helms et al. 2014)."
        case "gain": return "Gentle: about 0.25% of your weight a month above maintenance, steady 0.5%, fast 1%. Trained lifters gain little extra muscle from bigger surpluses, mostly fat (Iraki et al. 2019)."
        case "recomp": return "A small deficit with high protein and hard training: slow scale change, fat down, muscle up. Works best for newer lifters or after a break."
        default: return "Eat at your burn; protein stays high to keep muscle."
        }
    }

    // MARK: Data from the Air

    private var airBurn: Double? {
        let days = (1...14).compactMap { store.health[Day.add(-$0, to: Day.today)]?.calories }.filter { $0 > 1200 }
        return days.count >= 7 ? days.reduce(0, +) / Double(days.count) : nil
    }

    private var averageSteps: Double? {
        let s = (1...14).compactMap { store.health[Day.add(-$0, to: Day.today)]?.steps }
        return s.count >= 5 ? s.reduce(0, +) / Double(s.count) : nil
    }

    private var averageSleep: Int? {
        let s = (0..<14).compactMap { store.health[Day.add(-$0, to: Day.today)]?.sleep?.asleep }
        return s.count >= 5 ? s.reduce(0, +) / s.count : nil
    }

    // MARK: The science

    var plan: SetupPlan {
        var reasons: [(String, String, String)] = []
        // Resting burn
        let bmr: Double
        if let bf = bodyFat {
            let lean = weight * (1 - bf / 100)
            bmr = 370 + 21.6 * lean
            reasons.append(("Resting burn", "\(Int(bmr)) kcal", "Katch-McArdle from your lean mass (\(kg((lean * 10).rounded() / 10)) kg)."))
        } else {
            bmr = 10 * weight + 6.25 * height - 5 * Double(age) + (male ? 5 : -161)
            reasons.append(("Resting burn", "\(Int(bmr)) kcal", "Mifflin-St Jeor, the most accurate of the common equations in validation studies (within 10% for most people)."))
        }
        // Daily burn: the Air's measurement, else activity factors
        let jobFactor = ["desk": 1.25, "mixed": 1.4, "feet": 1.55, "physical": 1.75][job] ?? 1.3
        let training = Double(trainingDays) * 300 / 7 // a 60-minute lifting session burns roughly 250–350 kcal
        let formula = bmr * jobFactor + training
        let tdee: Double
        let source: String
        if let burn = airBurn {
            tdee = burn * 0.9 + formula * 0.1 // wrist trackers tend to read a little high; lean on the measurement
            source = "your Air's average over the last 14 days (\(Int(burn).formatted()) kcal), with a small correction toward the equation"
        } else {
            tdee = formula
            source = "your resting burn × \(String(format: "%.2f", jobFactor)) for your day, plus about \(Int(training)) kcal a day of training"
        }
        reasons.append(("Daily burn", "\(Int(tdee).formatted()) kcal", "From " + source + "."))
        // Goal
        var kcal = tdee
        switch goal {
        case "lose":
            let rate = ["gentle": 0.005, "steady": 0.007, "fast": 0.01][pace] ?? 0.007
            let deficit = min(1000, rate * weight * 7700 / 7)
            kcal = max(male ? 1500 : 1200, tdee - deficit)
            reasons.append(("Calories", "\(Int(kcal).formatted()) kcal", "A deficit of \(Int(deficit)) kcal a day loses about \(kg((rate * weight * 100).rounded() / 100)) kg a week (about 7,700 kcal per kg of fat), within the 0.5–1% a week that keeps muscle."))
        case "gain":
            let rate = ["gentle": 0.0025, "steady": 0.005, "fast": 0.01][pace] ?? 0.005
            let surplus = max(150, min(500, rate * weight * 7700 / 30))
            kcal = tdee + surplus
            reasons.append(("Calories", "\(Int(kcal).formatted()) kcal", "A surplus of \(Int(surplus)) kcal a day, about \(kg((rate * weight * 100).rounded() / 100)) kg a month: a lean bulk, enough to fuel muscle growth without much fat."))
        case "recomp":
            kcal = tdee * 0.9
            reasons.append(("Calories", "\(Int(kcal).formatted()) kcal", "10% under your burn: slow fat loss while high protein and training keep building muscle."))
        default:
            reasons.append(("Calories", "\(Int(kcal).formatted()) kcal", "At your burn, to hold your weight."))
        }
        // Protein
        let perKg = goal == "lose" ? 2.2 : goal == "recomp" ? 2.2 : 1.8
        let protein = (weight * perKg).rounded()
        reasons.append(("Protein", "\(Int(protein)) g", goal == "lose" || goal == "recomp"
            ? "2.2 g per kg: in a deficit, higher protein protects muscle (Helms et al. 2014 suggest 2.3–3.1 g per kg of lean mass)."
            : "1.8 g per kg: muscle gain levels off around 1.6 g per kg in the largest meta-analysis (Morton et al. 2018), with some people benefiting up to 2.2."))
        // Fat and carbs
        let fat = max(weight * 0.8, kcal * 0.25 / 9).rounded()
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4).rounded()
        reasons.append(("Fat and carbs", "\(Int(fat)) g · \(Int(carbs)) g", "Fat at least 0.8 g per kg and 25% of calories for hormones; the rest is carbs, which fuel hard training."))
        // Water
        let water = max(male ? 2000 : 1600, (weight * 35 / 50).rounded() * 50 - 500)
        reasons.append(("Water", String(format: "%.1f L", water / 1000), "About 35 ml per kg in total (EFSA: 2.5 L a day for men, 2.0 for women, including the ~20% that comes from food). Training days add 0.5 L, hot days more."))
        // Steps
        let current = averageSteps ?? 6000
        let steps = current < 6000 ? Int((current + 1500) / 500) * 500 : current < 8000 ? 8000 : 10000
        reasons.append(("Steps", steps.formatted(), "The mortality benefit of steps levels off around 8,000–10,000 a day under 60 (Paluch et al., Lancet 2022). Set a step above where you are now."))
        // Sleep
        let need = Int(sleepHours * 60)
        reasons.append(("Sleep", duration(need), "Asleep, not in bed: what you said you feel best on, within the 7–9 hours recommended for adults. Lights out is set from your wake time."))
        reasons.append(("Creatine", "3–5 g a day", "The ISSN position stand: 3–5 g daily keeps muscle stores full; timing barely matters, consistency does."))
        return SetupPlan(bmr: bmr, tdee: tdee, tdeeSource: source, kcal: (kcal / 10).rounded() * 10, protein: protein, proteinPerKg: perKg, fat: fat, carbs: carbs, waterMl: water, steps: steps, sleepNeed: need, reasons: reasons.map { (title: $0.0, value: $0.1, why: $0.2) })
    }

    private func load() {
        let p = store.profile
        male = p.male; age = p.age; height = p.heightCm; weight = store.all(WeightEntry.self).max { $0.date < $1.date }?.kg ?? p.weightKg
        goal = ["lose": "lose", "gain": "gain", "maintain": "maintain", "recomp": "recomp"][p.goal] ?? "gain"
        sleepHours = Double(p.sleepNeed) / 60
        wake = Day.at(p.wakeMinute, on: Day.today)
        trainingDays = max(trainingDays, store.templates.flatMap(\.weekdays).count)
    }

    private func apply() {
        let p = plan
        store.update { pr in
            pr.male = male; pr.age = age; pr.heightCm = height; pr.weightKg = weight
            pr.goal = goal; pr.kcalTarget = p.kcal; pr.proteinPerKg = p.proteinPerKg
            pr.waterGoalMl = p.waterMl; pr.stepGoal = p.steps; pr.sleepNeed = p.sleepNeed
            pr.wakeMinute = Day.minuteOfDay(wake)
            pr.fatTarget = p.fat; pr.carbTarget = p.carbs; pr.setupDone = true
        }
        store.save(WeightEntry(kg: weight))
        dismiss()
    }
}
