// Screens for the extras: Air workouts, body progress, rest or train, where your time went, money extras, Pip's look.
import Charts
import PhotosUI
import SwiftUI

struct AirWorkoutsCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject var air = AirWorkouts.shared
    var body: some View {
        Card(tint: .train) {
            Eyebrow(text: "Recorded by your Air", icon: "applewatch.radiowaves.left.and.right", color: .train)
            if air.list.isEmpty { Text("Runs, walks and sessions the Air records appear here with heart rate, after it syncs.").font(.system(size: 13)).foregroundStyle(Color.soft) }
            ForEach(air.list.prefix(5)) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.name).font(.system(size: 14, weight: .medium))
                        Text(e.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()) + " · \(e.minutes) min" + (e.distance.map { String(format: " · %.1f km", $0 / 1_000_000) } ?? "")).font(.system(size: 11.5)).foregroundStyle(Color.faint)
                    }
                    Spacer()
                    if let hr = e.avgHr { Text("\(Int(hr)) bpm").font(.system(size: 13, design: .monospaced)) }
                    if let c = e.calories { Text("\(Int(c)) kcal").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.soft) }
                }
            }
        }
        .task { await air.refresh() }
    }
}

struct RestOrTrainCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Group {
            if let f = store.restOrTrain() {
                Card {
                    Eyebrow(text: "Rest or train · next 3 days", icon: "arrow.triangle.branch")
                    Chart {
                        ForEach(Array(f.train.enumerated()), id: \.offset) { i, v in LineMark(x: .value("day", i + 1), y: .value("r", v), series: .value("p", "Train")).foregroundStyle(Color.train) }
                        ForEach(Array(f.rest.enumerated()), id: \.offset) { i, v in LineMark(x: .value("day", i + 1), y: .value("r", v), series: .value("p", "Rest")).foregroundStyle(Color.mint) }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 90)
                    Text("Train today: readiness \(f.train[0]) tomorrow. Rest: \(f.rest[0]). From how your own readiness moved after training and rest days.").font(.system(size: 12.5)).foregroundStyle(Color.soft)
                }
            }
        }
    }
}

struct BodyProgressView: View {
    @EnvironmentObject var store: Store
    @State private var photo: PhotosPickerItem?
    @State private var values: [String: String] = [:]
    @State private var photos = ProgressPhotos.all

    var body: some View {
        Screen(glow: .train) {
            Card {
                HStack { Eyebrow(text: "Progress photos", icon: "camera.fill"); Spacer(); PhotosPicker(selection: $photo, matching: .images) { Label("Add", systemImage: "plus") }.tint(.train) }
                if photos.isEmpty { Text("Same light, same pose, every few weeks. They stay on this phone.").font(.system(size: 13)).foregroundStyle(Color.soft) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(photos, id: \.url) { p in
                            VStack(spacing: 3) {
                                if let img = UIImage(contentsOfFile: p.url.path) { Image(uiImage: img).resizable().scaledToFill().frame(width: 110, height: 150).clipShape(RoundedRectangle(cornerRadius: 12)) }
                                Text(Day.date(p.date).formatted(.dateTime.day().month())).font(.system(size: 11)).foregroundStyle(Color.soft)
                            }
                        }
                    }
                }
            }
            Card {
                Eyebrow(text: "Measurements (cm)", icon: "ruler")
                let history = store.all(Measurement.self).sorted { $0.date > $1.date }
                ForEach(measurementNames, id: \.self) { name in
                    HStack {
                        Text(name).font(.system(size: 14))
                        Spacer()
                        if let last = history.first(where: { $0.values[name] != nil })?.values[name] {
                            let first = history.last(where: { $0.values[name] != nil })?.values[name] ?? last
                            Text("\(kg(last))" + (first != last ? String(format: " (%+.1f)", last - first) : "")).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color.soft)
                        }
                        TextField("–", text: Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })).keyboardType(.decimalPad).frame(width: 60).multilineTextAlignment(.trailing)
                    }
                }
                SoftButton(title: "Save today's", icon: "checkmark") {
                    var m = store.record(Measurement.self, Day.today) ?? Measurement()
                    for (k, v) in values { if let d = Double(v.replacingOccurrences(of: ",", with: ".")) { m.values[k] = d } }
                    store.save(m)
                    values = [:]
                }
            }
            Card {
                Eyebrow(text: "Strength per kilo of bodyweight", icon: "scalemass")
                let bw = store.all(WeightEntry.self).max { $0.date < $1.date }?.kg ?? store.profile.weightKg
                let ids = Array(Set(store.sessions().flatMap { $0.sets.filter(\.done).map(\.exerciseId) }))
                ForEach(ids.compactMap { id in store.e1rmHistory(id).last.map { (id, $0.value) } }.sorted { $0.1 > $1.1 }.prefix(6), id: \.0) { id, v in
                    HStack { Text(Catalog.shared.exercise(id)?.name ?? id).font(.system(size: 13.5)).lineLimit(1); Spacer(); Text(String(format: "%.2f× bodyweight", v / bw)).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color.soft) }
                }
            }
            Card {
                Eyebrow(text: "Activity · 12 weeks", icon: "calendar")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 12), spacing: 3) {
                    ForEach(0..<84, id: \.self) { i in
                        let d = Day.add(-83 + i, to: Day.today)
                        let trained = !store.sessions(on: d).isEmpty, azm = store.health[d]?.azm ?? 0
                        RoundedRectangle(cornerRadius: 3).fill(trained ? Color.train : azm >= 20 ? Color.train.opacity(0.45) : Color.white.opacity(0.06)).aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .navigationTitle("Body progress")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photo) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.7) {
                    ProgressPhotos.save(jpg)
                    photos = ProgressPhotos.all
                }
            }
        }
    }
}

struct TimeAuditCard: View {
    @EnvironmentObject var store: Store
    var week: String
    var body: some View {
        Card {
            Eyebrow(text: "Where your time went", icon: "chart.pie.fill")
            ForEach(store.timeAudit(week: week), id: \.0) { name, actual, planned in
                HStack {
                    Text(name).font(.system(size: 13.5))
                    Spacer()
                    Text(duration(actual) + (planned.map { " of \(duration($0)) planned" } ?? "")).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color.soft)
                }
            }
            Text(store.timeAuditSuggestion(week: week)).font(.system(size: 12.5)).foregroundStyle(Color.mint)
        }
    }
}

struct MoneyExtras: View {
    @EnvironmentObject var store: Store
    @State private var planning = false
    var body: some View {
        let prep = store.prepSavings()
        let protein = store.proteinValue()
        Card {
            Eyebrow(text: "Small wins", icon: "sparkles")
            HStack { Text("Round-ups this month").font(.system(size: 13.5)); Spacer(); Text(euro(store.roundUps(), decimals: true)).font(.system(size: 13.5, weight: .semibold, design: .monospaced)) }
            Text("Move this to savings at the end of the month: it's the change from every purchase.").font(.system(size: 11.5)).foregroundStyle(Color.faint)
            HStack { Text("Eating out and delivery").font(.system(size: 13.5)); Spacer(); Text(euro(prep.eatingOut)).font(.system(size: 13.5, design: .monospaced)) }
            if let per = prep.perPortion { Text("A prepped portion costs about \(euro(per, decimals: true))" + (prep.saved.map { $0 > 0 ? ": prep saved you ~\(euro($0)) this month." : "." } ?? ".")).font(.system(size: 12)).foregroundStyle(Color.good) }
            if !protein.isEmpty {
                Text("Protein per euro").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.soft)
                ForEach(protein.prefix(4), id: \.name) { p in HStack { Text(p.name).font(.system(size: 13)); Spacer(); Text("\(Int(p.perEuro)) g/€").font(.system(size: 12.5, design: .monospaced)) } }
            }
        }
        Card {
            HStack { Eyebrow(text: "Payday plan", icon: "banknote.fill"); Spacer(); SoftButton(title: "Plan this month") { planning = true } }
            if let p = store.record(Payday.self, String(Day.today.prefix(7))) {
                ForEach(p.jobs.sorted { $0.value > $1.value }, id: \.key) { k, v in HStack { Text(k).font(.system(size: 13.5)); Spacer(); Text(euro(v)).font(.system(size: 13.5, design: .monospaced)) } }
            } else { Text("On payday, give every euro a job: bills, groceries, wardrobe, travel, goals.").font(.system(size: 12.5)).foregroundStyle(Color.soft) }
        }
        .sheet(isPresented: $planning) { PaydayPlanner() }
        Card {
            Eyebrow(text: "e-Fatura · \(String(Day.today.prefix(4)))", icon: "doc.plaintext")
            ForEach(store.efatura(), id: \.0) { name, v, rule in
                HStack { VStack(alignment: .leading) { Text(name).font(.system(size: 13.5)); Text(rule).font(.system(size: 10.5)).foregroundStyle(Color.faint) }; Spacer(); Text(euro(v)).font(.system(size: 13.5, design: .monospaced)) }
            }
            Text("Estimates from categorised spending and receipt VAT. Validate pending invoices on e-Fatura before the February deadline.").font(.system(size: 11.5)).foregroundStyle(Color.faint)
        }
    }
}

struct PaydayPlanner: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var jobs: [String: Double] = [:]
    var body: some View {
        let m = store.moneyMonth()
        NavigationStack {
            Form {
                Section("Income \(euro(m.income)) · left to assign \(euro(m.income - jobs.values.reduce(0, +)))") {
                    ForEach(["Fixed bills", "Groceries", "Into goals", "Wardrobe", "Travel", "Fun", "Buffer"], id: \.self) { k in
                        HStack { Text(k); Spacer(); TextField("€", value: Binding(get: { jobs[k] ?? 0 }, set: { jobs[k] = $0 }), format: .number).keyboardType(.decimalPad).frame(width: 90).multilineTextAlignment(.trailing) }
                    }
                }
            }
            .cadenceList()
            .navigationTitle("Payday plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(Payday(month: String(Day.today.prefix(7)), jobs: jobs)); dismiss() } }
            }
            .onAppear {
                if let p = store.record(Payday.self, String(Day.today.prefix(7))) { jobs = p.jobs; return }
                let weeklyShop = store.shoppingList().compactMap(\.price).reduce(0, +)
                jobs = ["Fixed bills": m.fixed, "Into goals": m.goals, "Groceries": weeklyShop > 0 ? weeklyShop * 4.3 : 200]
            }
        }
    }
}

struct BackdropPicker: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Card {
            Eyebrow(text: "Pip's backdrop · unlocked by level", icon: "paintpalette.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(pipBackdrops, id: \.name) { b in
                        let open = b.level <= store.level.level
                        VStack(spacing: 4) {
                            Circle().fill(LinearGradient(colors: b.colors.map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom)).frame(width: 46, height: 46)
                                .overlay(Circle().stroke(store.backdrop.name == b.name ? Color.mint : .clear, lineWidth: 2))
                                .overlay(open ? nil : Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Color.soft))
                            Text(open ? b.name : "Lv \(b.level)").font(.system(size: 10.5)).foregroundStyle(open ? Color.ink : Color.faint)
                        }
                        .onTapGesture { if open { store.put("pipLook", "backdrop", .string(b.name)) } }
                    }
                }
            }
        }
    }
}
