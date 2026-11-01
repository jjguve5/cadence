// Fuel: calories, protein and water at a glance, the fast log (saved meals and recents first, barcode, quick add),
// caffeine, weight and the weekly target check-in.
import SwiftUI
import VisionKit

struct FuelView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var weighing = false
    @State private var weightText = ""

    var body: some View {
        let f = store.fuel()
        let p = store.profile
        Screen(glow: .fuel) {
            Card {
                HStack(spacing: 16) {
                    ZStack {
                        Ring(progress: f.kcal / p.kcal, area: .fuel, width: 8).frame(width: 92, height: 92)
                        Ring(progress: f.protein / p.proteinTarget, area: .train, width: 7).frame(width: 66, height: 66)
                        Text("\(Int(f.protein)) g").font(.system(size: 14, weight: .bold))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        row("Calories", "\(Int(f.kcal)) / \(Int(p.kcal))")
                        row("Protein", "\(Int(f.protein)) / \(Int(p.proteinTarget)) g")
                        if let burned = store.health[Day.today]?.calories { row("Burned", "\(Int(burned).formatted())") }
                        if f.caffeine > 0 { row("Caffeine", "\(Int(f.caffeine)) mg") }
                    }
                }
            }
            if let c = store.proteinCatchUp() {
                Card(tint: .fuel) {
                    Eyebrow(text: "Protein catch-up", icon: "fork.knife", color: .fuel)
                    Text("\(Int(c.gap)) g protein left today." + (c.meal.map { " Your \($0.name.lowercased()) covers \(Int($0.protein)) g." } ?? "")).font(.system(size: 14))
                    if let m = c.meal { SoftButton(title: "Log \(m.name)", icon: "plus") { store.logFood(FoodEntry(name: m.name, kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat, mealId: m.id)) } }
                }
            }
            WaterCard()
            Card {
                HStack { Eyebrow(text: "Today", icon: "list.bullet"); Spacer(); Button { adding = true } label: { Label("Log food", systemImage: "plus").font(.system(size: 13, weight: .semibold)) }.tint(.fuel) }
                let foods = store.foods()
                if foods.isEmpty { Text("Nothing logged yet.").font(.system(size: 14)).foregroundStyle(Color.soft) }
                ForEach(foods) { e in
                    HStack {
                        Text(clock(e.minute)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.faint)
                        Text(e.name).font(.system(size: 14)).lineLimit(1)
                        Spacer()
                        Text("\(Int(e.kcal)) · \(Int(e.protein)) g").font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color.soft)
                    }
                    .contextMenu {
                        Button("Save as a meal", systemImage: "star") { store.save(SavedMeal(name: e.name, kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, caffeine: e.caffeine)) }
                        Button("Delete", systemImage: "trash", role: .destructive) { store.remove(e) }
                    }
                }
                let plan = store.sleepPlan()
                if let last = f.lastMeal, last > plan.perform - 180 { Text("Late meal: the kitchen closed at \(clock(plan.perform - 180)). Late eating raises night heart rate.").font(.system(size: 12)).foregroundStyle(Color.warn) }
            }
            Card {
                HStack { Eyebrow(text: "Weight and targets", icon: "scalemass"); Spacer(); Button("Log weight") { weighing = true }.font(.system(size: 13, weight: .semibold)).tint(.fuel) }
                let w = store.all(WeightEntry.self).sorted { $0.date > $1.date }
                row("Weight", w.first.map { "\(kg($0.kg)) kg · \(Day.date($0.date).formatted(.dateTime.day().month()))" } ?? "\(kg(p.weightKg)) kg (profile)")
                if let a = store.adaptiveTarget() {
                    row("Trend", String(format: "%+.2f kg / week", a.trendKgPerWeek))
                    row("Maintenance", "\(Int(a.tdee)) kcal")
                    if abs(a.kcal - p.kcal) >= 50 {
                        SoftButton(title: "Use \(Int(a.kcal)) kcal from your data", icon: "arrow.triangle.2.circlepath") { store.update { $0.kcalTarget = a.kcal } }
                    }
                } else {
                    Text("Log your weight a few times a week and food for 10 days: the target then adjusts to what your weight actually does.").font(.system(size: 12)).foregroundStyle(Color.soft)
                }
            }
        }
        .navigationTitle("Fuel")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { FoodLogSheet() }
        .alert("Weight today", isPresented: $weighing) {
            TextField("kg", text: $weightText).keyboardType(.decimalPad)
            Button("Save") {
                if let v = Double(weightText.replacingOccurrences(of: ",", with: ".")), v > 30, v < 300 {
                    store.save(WeightEntry(kg: v))
                    store.update { $0.weightKg = v }
                }
                weightText = ""
            }
            Button("Cancel", role: .cancel) { weightText = "" }
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name).font(.system(size: 13.5)).foregroundStyle(Color.soft); Spacer(); Text(value).font(.system(size: 13.5, weight: .semibold, design: .monospaced)) }
    }
}

struct WaterCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let water = store.fuel().water, goal = store.waterGoal(), pace = store.waterPace()
        Card(tint: .water) {
            HStack {
                Eyebrow(text: "Water", icon: "drop.fill", color: .water)
                Spacer()
                Text(String(format: "%.1f / %.1f L", water / 1000, goal / 1000)).font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            Bar(progress: water / goal, area: .water)
            HStack {
                Text(water + 150 < pace ? "Behind pace by \(Int((pace - water) / 50) * 50) ml" : "On pace").font(.system(size: 12.5)).foregroundStyle(water + 150 < pace ? Color.warn : Color.soft)
                Spacer()
                ForEach([250.0, 500.0], id: \.self) { ml in SoftButton(title: "+\(Int(ml))") { store.addWater(ml) } }
            }
        }
    }
}

/// The fast log: saved and recent first, then caffeine drinks, barcode, or typing it in
struct FoodLogSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var custom = FoodEntry(name: "", kcal: 0, protein: 0)
    @State private var scanning = false
    @State private var product: OFFProduct?
    @State private var grams = 100.0
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if let product {
                    Section("Scanned") {
                        Text(product.name).font(.headline)
                        Stepper("\(Int(grams)) g", value: $grams, in: 5...1000, step: 5)
                        Text("\(Int(product.kcal100 * grams / 100)) kcal · \(Int(product.protein100 * grams / 100)) g protein").foregroundStyle(Color.soft)
                        Button("Log it") {
                            store.logFood(FoodEntry(name: product.name, kcal: (product.kcal100 * grams / 100).rounded(), protein: (product.protein100 * grams / 100).rounded(), carbs: product.carbs100 * grams / 100, fat: product.fat100 * grams / 100, grams: grams))
                            dismiss()
                        }
                    }
                }
                if let message { Section { Text(message).foregroundStyle(Color.warn) } }
                Section("Saved and recent") {
                    let items = store.quickFoods.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                    if items.isEmpty { Text("Foods you log appear here, most used first.").foregroundStyle(Color.soft) }
                    ForEach(items.prefix(25)) { m in
                        Button {
                            store.logFood(FoodEntry(name: m.name, kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat, caffeine: m.caffeine, mealId: m.id.hasPrefix("recent-") ? nil : m.id))
                            dismiss()
                        } label: {
                            HStack { Text(m.name).foregroundStyle(Color.ink); Spacer(); Text("\(Int(m.kcal)) · \(Int(m.protein)) g").font(.caption.monospaced()).foregroundStyle(Color.soft) }
                        }
                    }
                }
                Section("Caffeine") {
                    ForEach(caffeineDrinks, id: \.name) { d in
                        Button { store.logFood(FoodEntry(name: d.name, kcal: d.kcal, protein: 0, caffeine: d.mg)); dismiss() } label: {
                            HStack { Text(d.name).foregroundStyle(Color.ink); Spacer(); Text("\(Int(d.mg)) mg").font(.caption.monospaced()).foregroundStyle(Color.soft) }
                        }
                    }
                }
                Section("Quick add") {
                    TextField("Name", text: $custom.name)
                    TextField("kcal", value: $custom.kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Protein g", value: $custom.protein, format: .number).keyboardType(.decimalPad)
                    Button("Log") {
                        var e = custom
                        e.minute = Day.minuteOfDay()
                        if e.name.isEmpty { e.name = "Quick add" }
                        store.logFood(e)
                        dismiss()
                    }
                    .disabled(custom.kcal <= 0 && custom.protein <= 0)
                }
            }
            .cadenceList()
            .searchable(text: $search, prompt: "Search your foods")
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { scanning = true } label: { Image(systemName: "barcode.viewfinder") }
                        .disabled(!(DataScannerViewController.isSupported && DataScannerViewController.isAvailable))
                }
            }
            .sheet(isPresented: $scanning) {
                BarcodeScanner { code in
                    scanning = false
                    Task {
                        if let p = await OFFProduct.fetch(code) { product = p; grams = p.serving ?? 100; message = nil } else { message = "Not found in Open Food Facts: use quick add." }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}

/// A product from Open Food Facts, per 100 g
struct OFFProduct {
    var name: String
    var kcal100: Double
    var protein100: Double
    var carbs100: Double
    var fat100: Double
    var serving: Double?

    static func fetch(_ code: String) async -> OFFProduct? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,nutriments,serving_quantity") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Cadence/0.2 (personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = root["product"] as? [String: Any] else { return nil }
        let n = p["nutriments"] as? [String: Any] ?? [:]
        func num(_ k: String) -> Double { (n[k] as? Double) ?? (n[k] as? NSNumber)?.doubleValue ?? Double(n[k] as? String ?? "") ?? 0 }
        let serving = (p["serving_quantity"] as? Double) ?? Double(p["serving_quantity"] as? String ?? "")
        return OFFProduct(name: p["product_name"] as? String ?? "Product \(code)", kcal100: num("energy-kcal_100g"), protein100: num("proteins_100g"), carbs100: num("carbohydrates_100g"), fat100: num("fat_100g"), serving: serving)
    }
}

struct BarcodeScanner: UIViewControllerRepresentable {
    var found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])], qualityLevel: .balanced, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (String) -> Void
        var done = false
        init(found: @escaping (String) -> Void) { self.found = found }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let code = b.payloadStringValue { done = true; found(code); return }
            }
        }
    }
}
