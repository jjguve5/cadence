// Fuel: calories, protein and water at a glance, the fast log (saved meals and recents first, barcode, quick add),
// caffeine, weight and the weekly target check-in.
import SwiftUI
import VisionKit

struct FuelView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var building = false
    @State private var weighing = false
    @State private var weightText = ""

    var body: some View {
        let f = store.fuel()
        let p = store.profile
        Screen(glow: .fuel) {
            HStack {
                GoalMenu()
                Spacer()
                NavigationLink { SmartSetup() } label: { Label("Configurar", systemImage: "wand.and.stars").font(.geist(13, .semibold)) }.tint(.mint)
            }
            Card {
                HStack(spacing: 16) {
                    ZStack {
                        Ring(progress: f.kcal / p.kcal, area: .fuel, width: 8, marker: store.ringStats().day.first { $0.key == .calories }?.pace).frame(width: 92, height: 92)
                        Ring(progress: f.protein / p.proteinTarget, area: .train, width: 7, marker: store.ringStats().day.first { $0.key == .protein }?.pace).frame(width: 66, height: 66)
                        Text("\(Int(f.protein)) g").font(.geist(14, .bold))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        row("Calorias", "\(Int(f.kcal)) / \(Int(p.kcal))")
                        row("Proteína", "\(Int(f.protein)) / \(Int(p.proteinTarget)) g")
                        if let burned = store.health[Day.today]?.calories { row("Calorias gastas", "\(Int(burned).formatted())") }
                        if let fat = p.fatTarget, let carbs = p.carbTarget { row("Gordura · hidratos", "\(Int(f.fat))/\(Int(fat)) · \(Int(f.carbs))/\(Int(carbs)) g") }
                        if f.caffeine > 0 { row("Cafeína", "\(Int(f.caffeine)) mg") }
                    }
                }
            }
            if let c = store.proteinCatchUp() {
                Card(tint: .fuel) {
                    Eyebrow(text: "Proteína em falta", icon: "fork.knife", color: .fuel)
                    Text("Faltam \(Int(c.gap)) g de proteína hoje." + (c.meal.map { " Uma dose de \($0.name.lowercased()) tem \(Int($0.protein)) g." } ?? "")).font(.geist(14))
                    if let m = c.meal { SoftButton(title: "Registar \(m.name)", icon: "plus") { store.logFood(FoodEntry(name: m.name, kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat, mealId: m.id, group: m.group)) } }
                }
            }
            WaterCard()
            Card {
                HStack { Eyebrow(text: "Hoje", icon: "list.bullet"); Spacer(); Button { building = true } label: { Label("Montar", systemImage: "square.stack.3d.up").font(.geist(13, .semibold)) }.tint(.fuel).accessibilityIdentifier("fuel.build"); Button { adding = true } label: { Label("Registar comida", systemImage: "plus").font(.geist(13, .semibold)) }.tint(.fuel) }
                let foods = store.foods()
                if foods.isEmpty { Text("Ainda nada registado.").font(.geist(14)).foregroundStyle(Color.soft) }
                ForEach(foods) { e in
                    HStack {
                        Text(clock(e.minute)).font(.mono(12)).foregroundStyle(Color.faint)
                        Text(e.name).font(.geist(14)).lineLimit(1)
                        Spacer()
                        Text("\(Int(e.kcal)) · \(Int(e.protein)) g").font(.mono(12.5)).foregroundStyle(Color.soft)
                    }
                    .contextMenu {
                        Button("Guardar como refeição", systemImage: "star") { store.save(SavedMeal(name: e.name, kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, caffeine: e.caffeine, group: e.group)) }
                        Button("Apagar", systemImage: "trash", role: .destructive) { store.remove(e) }
                    }
                }
                if let last = f.lastMeal, last > store.kitchenClose() { Text("Refeição tardia: a cozinha fechou às \(clock(store.kitchenClose())). Comer tarde aumenta a frequência cardíaca durante a noite.").font(.geist(12)).foregroundStyle(Color.warn) }
            }
            Card {
                HStack { Eyebrow(text: "Peso e metas", icon: "scalemass"); Spacer(); Button("Registar peso") { weighing = true }.font(.geist(13, .semibold)).tint(.fuel) }
                let w = store.all(WeightEntry.self).sorted { $0.date > $1.date }
                row("Peso", w.first.map { "\(kg($0.kg)) kg · \(Day.date($0.date).formatted(.dateTime.day().month()))" + ($0.source == "health" ? " · Apple Health" : "") } ?? "\(kg(p.weightKg)) kg (perfil)")
                if let a = store.adaptiveTarget() {
                    row("Tendência", String(format: "%+.2f kg / semana", a.trendKgPerWeek))
                    row("Manutenção", "\(Int(a.tdee)) kcal")
                    if abs(a.kcal - p.kcal) >= 50 {
                        SoftButton(title: "Usar as \(Int(a.kcal)) kcal dos teus dados", icon: "arrow.triangle.2.circlepath") { store.update { $0.kcalTarget = a.kcal } }
                    }
                } else {
                    Text("Regista o peso algumas vezes por semana e a comida durante 10 dias: a meta passa a ajustar-se ao que o teu peso faz de facto.").font(.geist(12)).foregroundStyle(Color.soft)
                }
                DisclosureGroup("A partir do Apple Health") {
                    Text("Atalhos → Automatização → Nova → Hora do dia (10:00, diariamente, Executar imediatamente). Adiciona «Encontrar amostras de saúde»: tipo Peso, ordenar por Data de início, Mais recentes primeiro, limite 1. Depois «Obter conteúdo do URL» com o URL abaixo, método POST, cabeçalho X-Cadence-Token com o teu token e um corpo JSON: kg = Amostras de saúde › Valor, date = Amostras de saúde › Data de início (toca-lhe, Formato da data: ISO 8601). Os pesos que escreves à mão nunca são substituídos.").font(.geist(12)).foregroundStyle(Color.soft)
                    LabeledContent("URL", value: store.connection.server + "/weight.php").font(.geist(12))
                }
                .font(.geist(13)).tint(.soft)
            }
        }
        .navigationTitle("Comida")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { FoodLogSheet() }
        .sheet(isPresented: $building) { NavigationStack { MealBuilderView() } }
        .alert("Peso de hoje", isPresented: $weighing) {
            TextField("kg", text: $weightText).keyboardType(.decimalPad)
            Button("Guardar") {
                if let v = Double(weightText.replacingOccurrences(of: ",", with: ".")), v > 30, v < 300 {
                    store.save(WeightEntry(kg: v))
                    store.update { $0.weightKg = v }
                }
                weightText = ""
            }
            Button("Cancelar", role: .cancel) { weightText = "" }
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name).font(.geist(13.5)).foregroundStyle(Color.soft); Spacer(); Text(value).font(.mono(13.5, .semibold)) }
    }
}

struct WaterCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let water = store.fuel().water, goal = store.waterGoal(), pace = store.waterPace()
        Card(tint: .water) {
            HStack {
                Eyebrow(text: "Água", icon: "drop.fill", color: .water)
                Spacer()
                Text(String(format: "%.1f / %.1f L", water / 1000, goal / 1000)).font(.mono(14, .semibold))
            }
            Bar(progress: water / goal, area: .water)
            HStack {
                Text(water + 150 < pace ? "Faltam \(Int((pace - water) / 50) * 50) ml para o ritmo" : "No ritmo").font(.geist(12.5)).foregroundStyle(water + 150 < pace ? Color.warn : Color.soft)
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
    @State private var choosing: CommonFood?
    @State private var results: [OFFResult] = []
    @State private var searching = false
    @State private var group = "Eating out"
    @State private var offeringAddOns = false
    @State private var loggedMeal = ""

    private func log(_ f: CommonFood, _ factor: Double, size: String) {
        logAndFinish(FoodEntry(name: f.name + (factor == 1 ? "" : " (\(size.lowercased()))"), kcal: (f.kcal * factor).rounded(), protein: (f.protein * factor).rounded()))
    }

    /// A full meal goes on to its add-ons (fruit, soup, salad...); anything smaller just closes
    private func logAndFinish(_ e: FoodEntry) {
        store.logFood(e)
        if MealBuilder.isFullMeal(kcal: e.kcal) { loggedMeal = e.name; offeringAddOns = true } else { dismiss() }
    }

    var body: some View {
        NavigationStack {
            List {
                if let product {
                    Section("Produto") {
                        Text(product.name).font(.headline)
                        Stepper("\(Int(grams)) g", value: $grams, in: 5...1000, step: 5)
                        Text("\(Int(product.kcal100 * grams / 100)) kcal · \(Int(product.protein100 * grams / 100)) g de proteína").foregroundStyle(Color.soft)
                        Button("Registar") {
                            store.logFood(FoodEntry(name: product.name, kcal: (product.kcal100 * grams / 100).rounded(), protein: (product.protein100 * grams / 100).rounded(), carbs: product.carbs100 * grams / 100, fat: product.fat100 * grams / 100, grams: grams))
                            dismiss()
                        }
                    }
                }
                if let message { Section { Text(message).foregroundStyle(Color.warn) } }
                if !search.isEmpty {
                    let local = FoodSearch.local(search)
                    if !local.isEmpty {
                        Section("Alimentos e refeições comuns") {
                            ForEach(local.prefix(15)) { f in foodRow(f) }
                        }
                    }
                    Section(searching ? "Produtos · a procurar…" : "Produtos") {
                        if results.isEmpty && !searching { Text(search.count < 3 ? "Escreve algumas letras." : "Nenhum produto embalado encontrado. Experimenta outro nome ou o registo manual.").foregroundStyle(Color.soft) }
                        ForEach(results) { r in
                            Button { product = OFFProduct(name: r.name + (r.brand.map { " · \($0)" } ?? ""), kcal100: r.kcal100, protein100: r.protein100, carbs100: 0, fat100: 0, serving: r.serving); grams = r.serving ?? 100 } label: {
                                HStack {
                                    VStack(alignment: .leading) { Text(r.name).foregroundStyle(Color.ink).lineLimit(1); if let b = r.brand { Text(b).font(.caption).foregroundStyle(Color.faint) } }
                                    Spacer()
                                    Text("\(Int(r.kcal100)) kcal · \(Int(r.protein100)) g /100 g").font(.caption.monospaced()).foregroundStyle(Color.soft)
                                }
                            }
                        }
                    }
                }
                Section("Guardados e recentes") {
                    let items = store.quickFoods.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                    if items.isEmpty { Text("O que registas aparece aqui, o mais usado primeiro.").foregroundStyle(Color.soft) }
                    ForEach(items.prefix(25)) { m in
                        Button {
                            logAndFinish(FoodEntry(name: m.name, kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat, caffeine: m.caffeine, mealId: m.id.hasPrefix("recent-") ? nil : m.id, group: m.group))
                        } label: {
                            HStack { Text(m.name).foregroundStyle(Color.ink); Spacer(); Text("\(Int(m.kcal)) · \(Int(m.protein)) g").font(.caption.monospaced()).foregroundStyle(Color.soft) }
                        }
                    }
                }
                if search.isEmpty { buildSection }
                if search.isEmpty {
                    Section {
                        Picker("", selection: $group) { ForEach(["Eating out", "Meals", "Soups and salads", "Breakfast", "Snacks", "Fruit", "Dairy", "Desserts", "Drinks"], id: \.self) { Text(CommonFood.groupLabel($0)).tag($0) } }.pickerStyle(.menu).tint(.fuel)
                        ForEach(commonFoods.filter { $0.group == group }) { f in foodRow(f) }
                    } header: { Text("Alimentos comuns · porções típicas") } footer: { Text("Estimativas para uma porção normal; escolhe pequena, grande ou dupla quando for diferente.") }
                }
                Section("Cafeína") {
                    ForEach(caffeineDrinks, id: \.name) { d in
                        Button { store.logFood(FoodEntry(name: d.name, kcal: d.kcal, protein: 0, caffeine: d.mg)); dismiss() } label: {
                            HStack { Text(d.name).foregroundStyle(Color.ink); Spacer(); Text("\(Int(d.mg)) mg").font(.caption.monospaced()).foregroundStyle(Color.soft) }
                        }
                    }
                }
                Section("Registo manual") {
                    TextField("Nome", text: $custom.name)
                    TextField("kcal", value: $custom.kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Proteína g", value: $custom.protein, format: .number).keyboardType(.decimalPad)
                    Button("Registar") {
                        var e = custom
                        e.minute = Day.minuteOfDay()
                        if e.name.isEmpty { e.name = "Registo manual" }
                        logAndFinish(e)
                    }
                    .disabled(custom.kcal <= 0 && custom.protein <= 0)
                }
            }
            .cadenceList()
            .searchable(text: $search, prompt: "Procurar alimentos, refeições, produtos")
            .task(id: search) {
                results = []
                guard search.count >= 3 else { return }
                try? await Task.sleep(nanoseconds: 450_000_000) // wait for typing to pause
                guard !Task.isCancelled else { return }
                searching = true
                results = await FoodSearch.products(search)
                searching = false
            }
            .confirmationDialog(choosing.map { "\($0.name) · porção normal: \($0.portion)" } ?? "", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }), titleVisibility: .visible) {
                if let f = choosing {
                    ForEach(portionSizes, id: \.name) { p in
                        Button("\(portionSizeLabel(p.name)) · \(Int(f.kcal * p.factor)) kcal, \(Int(f.protein * p.factor)) g de proteína") { log(f, p.factor, size: portionSizeLabel(p.name)) }
                    }
                }
            }
            .navigationDestination(isPresented: $offeringAddOns) { MealAddOnsView(meal: loggedMeal) { dismiss() } }
            .navigationTitle("Registar comida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { scanning = true } label: { Image(systemName: "barcode.viewfinder") }
                        .disabled(!(DataScannerViewController.isSupported && DataScannerViewController.isAvailable))
                }
            }
            .sheet(isPresented: $scanning) {
                BarcodeScanner { code in
                    scanning = false
                    Task {
                        if let p = await OFFProduct.fetch(code) { product = p; grams = p.serving ?? 100; message = nil } else { message = "Não está no Open Food Facts: usa o registo manual." }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}

extension FoodLogSheet {
    var buildSection: some View {
        Section {
            NavigationLink { MealBuilderView(onDone: { dismiss() }) } label: { Label("Montar uma refeição", systemImage: "square.stack.3d.up").foregroundStyle(Color.ink) }
                .accessibilityIdentifier("food.build")
        } footer: { Text("Escolhe uma base, proteína, legumes e molhos para uma estimativa em tempo real.") }
    }

    func foodRow(_ f: CommonFood) -> some View {
        Button { choosing = f } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) { Text(f.name).foregroundStyle(Color.ink); Text(f.portion).font(.caption).foregroundStyle(Color.faint) }
                Spacer()
                Text("\(Int(f.kcal)) · \(Int(f.protein)) g").font(.caption.monospaced()).foregroundStyle(Color.soft)
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
        return OFFProduct(name: p["product_name"] as? String ?? "Produto \(code)", kcal100: num("energy-kcal_100g"), protein100: num("proteins_100g"), carbs100: num("carbohydrates_100g"), fat100: num("fat_100g"), serving: serving)
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
