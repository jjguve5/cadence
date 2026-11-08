// Fuel: calories, protein and water at a glance, the fast log (saved meals and recents first, barcode, quick add),
// caffeine, weight and the weekly target check-in. Phase 2.7 (design N_ComidaConfirmar, N_ComidaResumo, N_Corpo):
// every way of logging food opens the confirmation and only «Guardar refeição» saves, with Desfazer; «Editar» reopens
// the same entry; the water goal shows as «Sugerido» until you accept or adjust it.
import SwiftUI
import VisionKit

struct FuelView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var building = false
    @State private var weighing = false
    @State private var weightText = ""
    @State private var confirming: FoodConfirmRequest?

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
                        if !store.foods().isEmpty {
                            HStack(spacing: 6) {
                                StateTag(state: .estimated)
                                Text("nutrientes de tabelas").font(.geist(11)).foregroundStyle(Color.faint)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fuel.screen")
            if let c = store.proteinCatchUp() {
                Card(tint: .fuel) {
                    Eyebrow(text: "Proteína em falta", icon: "fork.knife", color: .fuel)
                    Text("Faltam \(Int(c.gap)) g de proteína hoje." + (c.meal.map { " Uma dose de \($0.name.lowercased()) tem \(Int($0.protein)) g." } ?? "")).font(.geist(14))
                    if let m = c.meal {
                        SoftButton(title: "Registar \(m.name)", icon: "plus") { confirming = FoodConfirmRequest(items: [FoodItem(saved: m)]) }
                            .accessibilityIdentifier("fuel.catchup")
                    }
                }
            }
            WaterCard()
            Card {
                HStack {
                    Eyebrow(text: "Hoje", icon: "list.bullet")
                    Spacer()
                    Button { building = true } label: { Label("Montar", systemImage: "square.stack.3d.up").font(.geist(13, .semibold)) }.tint(.fuel).accessibilityIdentifier("fuel.build")
                    Button { adding = true } label: { Label("Registar comida", systemImage: "plus").font(.geist(13, .semibold)) }.tint(.fuel).accessibilityIdentifier("fuel.log")
                }
                let foods = store.foods()
                if foods.isEmpty { Text("Ainda nada registado.").font(.geist(14)).foregroundStyle(Color.soft).accessibilityIdentifier("fuel.empty") }
                ForEach(foods) { e in entryRow(e) }
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
        .sheet(isPresented: $building) {
            NavigationStack { MealBuilderView() }
                .overlay(alignment: .bottom) { UndoBar().padding(.bottom, FoodConfirmView.undoLift) }
        }
        .sheet(item: $confirming) { FoodConfirmSheet($0) }
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

    /// A logged food: tap (or «Editar») reopens the same entry in the confirmation
    private func entryRow(_ e: FoodEntry) -> some View {
        Button { edit(e) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(clock(e.minute)).font(.mono(12)).foregroundStyle(Color.faint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.name).font(.geist(14)).foregroundStyle(Color.ink).lineLimit(1)
                    if let a = e.amountText { Text(a).font(.geist(11.5)).foregroundStyle(Color.faint).lineLimit(1) }
                }
                Spacer()
                Text("≈ \(Int(e.kcal)) · \(Int(e.protein)) g").font(.mono(12.5)).foregroundStyle(Color.soft)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre para editar")
        .accessibilityIdentifier("fuel.entry.\(e.id)")
        .contextMenu {
            Button("Editar", systemImage: "pencil") { edit(e) }
            Button("Guardar como refeição", systemImage: "star") { saveAsMeal(e) }
            Button("Apagar", systemImage: "trash", role: .destructive) { delete(e) }
        }
    }

    private func edit(_ e: FoodEntry) {
        confirming = FoodConfirmRequest(items: [FoodItem(editing: e)], reopened: [e])
    }

    private func saveAsMeal(_ e: FoodEntry) {
        let m = SavedMeal(name: e.name, kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, caffeine: e.caffeine, group: e.group)
        store.save(m)
        UndoCenter.shared.show("Guardado nas refeições: \(e.name)") { store.remove(m) }
    }

    private func delete(_ e: FoodEntry) {
        store.remove(e)
        UndoCenter.shared.show("Apagado: \(e.name)") { store.save(e) }
    }
}

/// Water today, at your pace, and the day's goal: «Sugerido» until you accept or adjust it (decision 47, N_Corpo)
struct WaterCard: View {
    @EnvironmentObject var store: Store
    @State private var adjusting = false
    @State private var adjustMl = 3000.0

    var body: some View {
        let water = store.fuel().water, target = store.waterGoal(), pace = store.waterPace()
        let choice = store.waterGoalChoice()
        let suggestion = store.waterSuggestion()
        Card(tint: .water) {
            HStack {
                Eyebrow(text: "Água", icon: "drop.fill", color: .water)
                Spacer()
                Text("\(WaterGoals.litres(water)) / \(WaterGoals.litres(target)) L").font(.mono(14, .semibold))
            }
            Bar(progress: water / max(1, target), area: .water)
            HStack {
                Text(water + 150 < pace ? "Faltam \(Int((pace - water) / 50) * 50) ml para o ritmo" : "No ritmo").font(.geist(12.5)).foregroundStyle(water + 150 < pace ? Color.warn : Color.soft)
                Spacer()
                ForEach([250.0, 500.0], id: \.self) { ml in
                    SoftButton(title: "+\(Int(ml))") { addWater(ml) }.accessibilityIdentifier("water.add.\(Int(ml))")
                }
            }
            Divider().overlay(Color.white.opacity(0.06))
            goalRow(choice: choice, suggestion: suggestion)
        }
    }

    @ViewBuilder private func goalRow(choice: WaterGoalChoice?, suggestion s: WaterSuggestion) -> some View {
        if adjusting {
            Stepper(value: $adjustMl, in: 1000...6000, step: 50) {
                Text("Meta de hoje: \(WaterGoals.litres(adjustMl)) L").font(.geist(13.5))
            }
            .accessibilityIdentifier("water.goal.stepper")
            HStack(spacing: 8) {
                TallSoftButton(title: "Guardar meta", icon: "checkmark") { choose(adjustMl) }.accessibilityIdentifier("water.goal.save")
                Button("Cancelar") { adjusting = false }.font(.geist(13, .semibold)).foregroundStyle(Color.soft).frame(minHeight: 44)
                Spacer(minLength: 0)
            }
        } else if let choice {
            HStack(spacing: 8) {
                Text("Meta de hoje: \(WaterGoals.litres(choice.ml)) L").font(.geist(13.5))
                Spacer()
                StateTag(state: .confirmed)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("water.goal.confirmed")
            Button("Ajustar") { startAdjusting(choice.ml) }.font(.geist(13, .semibold)).tint(.water).frame(minHeight: 44).accessibilityIdentifier("water.goal.adjust")
        } else {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Meta de hoje:").font(.geist(13.5))
                        EstimatedText(value: "\(WaterGoals.litres(s.total)) L").font(.geist(13.5, .semibold))
                    }
                    WhyLine(text: WaterGoals.why(s) + " · não é indicação médica")
                }
                Spacer(minLength: 4)
                StateTag(state: .suggested)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("water.goal.suggested")
            HStack(spacing: 8) {
                Button { choose(s.total) } label: {
                    Text("Aceitar meta").font(.geist(13, .semibold)).foregroundStyle(Color(hex: 0x05140F))
                        .padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().fill(Area.mint.gradient))
                }
                .accessibilityIdentifier("water.goal.accept")
                Button { startAdjusting(s.total) } label: {
                    Text("Ajustar").font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                .accessibilityIdentifier("water.goal.adjust")
                Spacer(minLength: 0)
            }
            .buttonStyle(Pressable())
        }
    }

    /// «Aceitar meta» or «Guardar meta»: the goal for today becomes yours, with Desfazer
    private func choose(_ ml: Double) {
        let undo = store.chooseWaterGoal(ml)
        adjusting = false
        UndoCenter.shared.show("Meta de água: \(WaterGoals.litres(store.waterGoal())) L hoje", undo: undo)
    }

    private func startAdjusting(_ ml: Double) {
        adjustMl = min(6000, max(1000, (ml / 50).rounded() * 50))
        adjusting = true
    }

    private func addWater(_ ml: Double) {
        let e = store.addWater(ml)
        UndoCenter.shared.show("Água +\(Int(ml)) ml") { store.remove(e) }
    }
}

/// The fast log: saved and recent first, then caffeine drinks, barcode, or typing it in. Every pick opens the
/// confirmation; nothing is saved here
struct FoodLogSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var custom = FoodEntry(name: "", kcal: 0, protein: 0)
    @State private var scanning = false
    @State private var message: String?
    @State private var choosing: CommonFood?
    @State private var results: [OFFResult] = []
    @State private var searching = false
    @State private var group = "Eating out"
    /// The meal being put together: nothing in it is saved until «Guardar refeição»
    @State private var draft: [FoodItem] = []
    @State private var confirming = false

    /// A pick joins the meal and opens the confirmation
    private func add(_ item: FoodItem) {
        draft.append(item)
        confirming = true
    }

    /// A saved meal, or a recent food again (the same amount, as a guess to confirm)
    private func quickItem(_ m: SavedMeal) -> FoodItem {
        guard m.id.hasPrefix("recent-") else { return FoodItem(saved: m) }
        if let e = store.record(FoodEntry.self, String(m.id.dropFirst("recent-".count))) { return FoodItem.again(e) }
        var item = FoodItem(saved: m)
        item.mealId = nil
        return item
    }

    var body: some View {
        NavigationStack {
            List {
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
                            Button {
                                add(FoodItem(product: OFFProduct(name: r.name + (r.brand.map { " · \($0)" } ?? ""), kcal100: r.kcal100, protein100: r.protein100, carbs100: nil, fat100: nil, serving: r.serving)))
                            } label: {
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
                    ForEach(Array(items.prefix(25).enumerated()), id: \.element.id) { i, m in
                        Button { add(quickItem(m)) } label: {
                            HStack { Text(m.name).foregroundStyle(Color.ink); Spacer(); Text("≈ \(Int(m.kcal)) · \(Int(m.protein)) g").font(.caption.monospaced()).foregroundStyle(Color.soft) }
                        }
                        .accessibilityIdentifier("food.quick.\(i)")
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
                    ForEach(Array(caffeineDrinks.enumerated()), id: \.offset) { i, d in
                        Button { add(FoodItem(drink: d.name, mg: d.mg, kcal: d.kcal)) } label: {
                            HStack { Text(d.name).foregroundStyle(Color.ink); Spacer(); Text("\(Int(d.mg)) mg").font(.caption.monospaced()).foregroundStyle(Color.soft) }
                        }
                        .accessibilityIdentifier("food.caffeine.\(i)")
                    }
                }
                Section("Registo manual") {
                    TextField("Nome", text: $custom.name)
                    TextField("kcal", value: $custom.kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Proteína g", value: $custom.protein, format: .number).keyboardType(.decimalPad)
                    Button("Continuar") {
                        let name = custom.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        add(FoodItem(manual: name.isEmpty ? "Registo manual" : name, kcal: custom.kcal, protein: custom.protein))
                        custom = FoodEntry(name: "", kcal: 0, protein: 0)
                    }
                    .disabled(custom.kcal <= 0 && custom.protein <= 0)
                    .accessibilityIdentifier("food.manual.continue")
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
                        Button("\(portionSizeLabel(p.name)) · \(Int(f.kcal * p.factor)) kcal, \(Int(f.protein * p.factor)) g de proteína") { add(FoodItem(common: f, factor: p.factor)) }
                    }
                }
            }
            .navigationDestination(isPresented: $confirming) {
                FoodConfirmView(items: $draft, onAddMore: { confirming = false }, onBack: { confirming = false }, onFinish: { dismiss() })
            }
            .safeAreaInset(edge: .bottom) { draftBar }
            .navigationTitle("Registar comida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() }.accessibilityIdentifier("food.close") }
                ToolbarItem(placement: .primaryAction) {
                    Button { scanning = true } label: { Image(systemName: "barcode.viewfinder") }
                        .disabled(!(DataScannerViewController.isSupported && DataScannerViewController.isAvailable))
                        .accessibilityLabel("Ler código de barras")
                }
            }
            .sheet(isPresented: $scanning) {
                BarcodeScanner { code in
                    scanning = false
                    Task {
                        if let p = await OFFProduct.fetch(code) { message = nil; add(FoodItem(product: p)) } else { message = "Não está no Open Food Facts: usa o registo manual." }
                    }
                }
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .bottom) { UndoBar().padding(.bottom, FoodConfirmView.undoLift) }
    }

    /// What is waiting to be saved, back on the list: review it or let it go
    @ViewBuilder private var draftBar: some View {
        if !draft.isEmpty {
            HStack(spacing: 10) {
                StateTag(state: .pending, text: "Por guardar")
                Text(draft.count == 1 ? "1 alimento" : "\(draft.count) alimentos").font(.geist(13)).foregroundStyle(Color.ink)
                Spacer()
                Button("Descartar") { draft = [] }.font(.geist(13, .semibold)).foregroundStyle(Color.soft).frame(minHeight: 44).accessibilityIdentifier("food.draft.discard")
                Button("Rever") { confirming = true }.font(.geist(13.5, .semibold)).tint(.fuel).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("food.draft.review")
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .background(.ultraThinMaterial)
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
                Text("≈ \(Int(f.kcal)) · \(Int(f.protein)) g").font(.caption.monospaced()).foregroundStyle(Color.soft)
            }
        }
    }
}

// MARK: - The confirmation and the summary after saving (design N_ComidaConfirmar, N_ComidaResumo)

/// What opens the confirmation on its own (editing a saved entry, the protein catch-up)
struct FoodConfirmRequest: Identifiable {
    let id = UUID()
    var items: [FoodItem]
    var reopened: [FoodEntry] = []
}

/// The confirmation in its own sheet: closes when done or on «Voltar»
struct FoodConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [FoodItem]
    private let reopened: [FoodEntry]

    init(_ request: FoodConfirmRequest) {
        _items = State(initialValue: request.items)
        reopened = request.reopened
    }

    var body: some View {
        NavigationStack {
            FoodConfirmView(items: $items, reopened: reopened, onBack: { dismiss() }, onFinish: { dismiss() })
        }
        .overlay(alignment: .bottom) { UndoBar().padding(.bottom, FoodConfirmView.undoLift) }
    }
}

/// Every way of logging food ends here, and only «Guardar refeição» saves (decisions 55–57). Food and amount first,
/// nutrients compact and always estimated; each food's amount, unit and group can be changed, and the amount stops
/// being an estimate when you confirm it. After saving: the day's summary (decision 60), Desfazer, and «Editar
/// refeição», which reopens the same entries (saving again replaces them).
struct FoodConfirmView: View {
    /// How far the Desfazer bar is lifted in the food sheets, clear of the buttons at the bottom
    static let undoLift: CGFloat = 76

    @EnvironmentObject var store: Store
    @Binding var items: [FoodItem]
    /// Saved entries this confirmation edits: saving replaces them (same ids), and one taken off the meal is removed
    @State private var reopened: [FoodEntry]
    private let onAddMore: (() -> Void)?
    private let onBack: () -> Void
    private let onFinish: () -> Void
    @State private var open: String? = nil
    @State private var saved: [FoodEntry]? = nil // once saved, the meal as it was saved
    @State private var itemsAtSave: [FoodItem] = []
    @State private var showingSummary = false
    @State private var failed = false
    @State private var extrasOpen = false
    @State private var tipsOk = false
    @AppStorage("food.tipsHiddenOn") private var tipsHiddenOn = ""

    init(items: Binding<[FoodItem]>, reopened: [FoodEntry] = [], onAddMore: (() -> Void)? = nil, onBack: @escaping () -> Void, onFinish: @escaping () -> Void) {
        _items = items
        _reopened = State(initialValue: reopened)
        self.onAddMore = onAddMore
        self.onBack = onBack
        self.onFinish = onFinish
    }

    var body: some View {
        Group {
            if showingSummary, let saved { summary(saved) } else { confirmation }
        }
        .navigationTitle(showingSummary ? "Refeição guardada" : "Confirmar refeição")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(saved != nil)
        .sensoryFeedback(.success, trigger: showingSummary)
    }

    // MARK: Before saving

    private var whenText: String {
        let day = items.first?.date ?? Day.today
        let minute = items.first?.minute ?? Day.minuteOfDay(store.tick)
        let date = Day.date(day).formatted(.dateTime.weekday(.wide).day().month(.wide))
        let head = date.prefix(1).uppercased() + date.dropFirst()
        return head + " · " + clock(minute)
    }

    private var confirmation: some View {
        let totals = FoodMeal.totals(items)
        let counts = FoodMeal.goals(items)
        return Screen(glow: .fuel) {
            Text(whenText).font(.geist(13)).foregroundStyle(Color.soft).padding(.top, 6).accessibilityIdentifier("food.confirm.screen")
            if failed {
                Card(tint: .bad) {
                    HStack { Eyebrow(text: "Não ficou guardado", icon: DataState.error.icon, color: DataState.error.color); Spacer(); StateTag(state: .error) }
                    Text("Não consegui guardar a refeição. Fica neste ecrã até tentares de novo.").font(.geist(13))
                }
            }
            Card(state: .pending) {
                HStack { Eyebrow(text: "Antes de guardar"); Spacer(); StateTag(state: .pending, text: "Por guardar") }
                if items.isEmpty { Text("Nada nesta refeição. Acrescenta um alimento ou volta atrás.").font(.geist(13)).foregroundStyle(Color.soft) }
                ForEach(items) { item in
                    row(item)
                    if item.id != items.last?.id { Divider().overlay(Color.white.opacity(0.06)) }
                }
                if let onAddMore, saved == nil {
                    Button { onAddMore() } label: { Label("Acrescentar alimento", systemImage: "plus").font(.geist(13.5, .semibold)).frame(minHeight: 44) }
                        .tint(.fuel)
                        .accessibilityIdentifier("food.confirm.addmore")
                }
            }
            Card {
                HStack { Eyebrow(text: "Resumo"); Spacer(); Text("nutrientes de tabelas, estimados").font(.geist(11)).foregroundStyle(Color.faint) }
                HStack(spacing: 6) {
                    nutrient("kcal", "\(Int(totals.kcal.rounded()))", partial: false)
                    nutrient("proteína", "\(Int(totals.protein.rounded())) g", partial: false)
                    nutrient("hidratos", totals.carbs.map { "\(Int($0.rounded())) g" }, partial: totals.carbsPartial)
                    nutrient("gordura", totals.fat.map { "\(Int($0.rounded())) g" }, partial: totals.fatPartial)
                }
                if totals.caffeine > 0 {
                    DisclosureGroup("Mais nutrientes") {
                        HStack { Text("Cafeína").font(.geist(13)); Spacer(); EstimatedText(value: "\(Int(totals.caffeine.rounded())) mg").font(.mono(13)) }
                    }
                    .font(.geist(13)).tint(.soft)
                }
                Text("Conta para: fruta \(counts.fruit) · sopa \(counts.soup) · legumes \(counts.veg). O grupo vem de cada alimento, não do nome.")
                    .font(.geist(12)).foregroundStyle(Color.soft).accessibilityIdentifier("food.confirm.groups")
            }
            if MealBuilder.isFullMeal(kcal: totals.kcal) || items.contains(where: { $0.addOnId != nil }) { extrasCard }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                PrimaryButton(title: "Guardar refeição", area: .fuel) { save() }
                    .disabled(items.isEmpty)
                    .opacity(items.isEmpty ? 0.5 : 1)
                    .accessibilityIdentifier("food.confirm.save")
                Button("Voltar") { back() }
                    .font(.geist(13.5, .semibold)).foregroundStyle(Color.soft).frame(minWidth: 88, minHeight: 44)
                    .accessibilityIdentifier("food.confirm.back")
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
            .background(.ultraThinMaterial)
        }
    }

    /// One food: name and amount first, the estimate and whether the amount is yours on the right; tap to adjust
    @ViewBuilder private func row(_ item: FoodItem) -> some View {
        let isOpen = open == item.id
        Button { withAnimation(.easeOut(duration: 0.2)) { open = isOpen ? nil : item.id } } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.geist(14.5, .semibold)).foregroundStyle(Color.ink).multilineTextAlignment(.leading)
                    Text(item.amountText).font(.geist(12.5)).foregroundStyle(Color.soft).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    EstimatedText(value: "\(Int(item.totalKcal.rounded())) kcal").font(.geist(13)).foregroundStyle(Color.ink)
                    StateTag(state: item.quantityConfirmed ? .confirmed : .estimated)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isOpen ? "Fecha os ajustes" : "Ajusta a quantidade, a unidade e o grupo")
        .accessibilityIdentifier("food.item.\(item.id)")
        if isOpen { editor(item) }
    }

    /// Amount (in the units this food allows), «Confirmar quantidade», «Não sei», the group and Remover
    private func editor(_ item: FoodItem) -> some View {
        let id = item.id
        return VStack(alignment: .leading, spacing: 10) {
            if item.units.count > 1 {
                Segments(options: item.units.map { ($0, $0.short) }, selection: Binding(get: { item.unit }, set: { u in
                    update(id) { $0 = $0.converted(to: u); $0.quantityConfirmed = true }
                }))
                .accessibilityIdentifier("food.item.\(id).unit")
            }
            HStack(spacing: 12) {
                stepButton("minus", label: "Menos", id: "food.item.\(id).less") { update(id) { $0.change(by: -1) } }
                Text(item.unit.amount(item.quantity)).font(.mono(15, .semibold)).foregroundStyle(Color.ink).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("food.item.\(id).amount")
                stepButton("plus", label: "Mais", id: "food.item.\(id).more") { update(id) { $0.change(by: 1) } }
            }
            HStack(spacing: 8) {
                if !item.quantityConfirmed {
                    TallSoftButton(title: "Confirmar quantidade", icon: "checkmark") { update(id) { $0.quantityConfirmed = true } }
                        .accessibilityIdentifier("food.item.\(id).confirm")
                }
                Button("Não sei") { update(id) { $0.dontKnow() } }
                    .font(.geist(13, .semibold)).foregroundStyle(Color.soft).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("food.item.\(id).unsure")
                Spacer(minLength: 0)
                Button(role: .destructive) { remove(id) } label: { Label("Remover", systemImage: "trash").font(.geist(13, .semibold)) }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("food.item.\(id).remove")
            }
            Text("«Não sei» guarda a estimativa habitual (\(item.defaultUnit.amount(item.defaultQuantity))), marcada como tal.").font(.geist(11.5)).foregroundStyle(Color.faint)
            HStack {
                Text("Conta para").font(.geist(13)).foregroundStyle(Color.soft)
                Spacer()
                Picker("Conta para", selection: Binding(get: { FoodGoals.choice(for: item.group) }, set: { g in update(id) { $0.group = g } })) {
                    ForEach(FoodGoals.choices(current: item.group), id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.menu)
                .tint(.fuel)
                .accessibilityIdentifier("food.item.\(id).group")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private func stepButton(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func nutrient(_ label: String, _ value: String?, partial: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.geist(10.5)).foregroundStyle(Color.faint)
            if let value {
                EstimatedText(value: value).font(.geist(14, .semibold)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("Sem dados").font(.geist(11.5, .semibold)).foregroundStyle(DataState.noData.color)
            }
            if partial { Text("parcial").font(.geist(10)).foregroundStyle(Color.faint) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    /// Add-ons for a full meal (fruit, soup, bread…): they join the meal and are saved only with it
    private var extrasCard: some View {
        Card {
            Button { withAnimation(.easeOut(duration: 0.2)) { extrasOpen.toggle() } } label: {
                HStack {
                    Eyebrow(text: "Juntar a esta refeição", icon: "plus.circle")
                    Spacer()
                    Image(systemName: extrasOpen ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(Color.faint)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("food.confirm.extras")
            if extrasOpen {
                Text("Fruta, sopa, pão, sobremesa ou bebida: cada um com a sua estimativa, guardado só com a refeição.").font(.geist(12)).foregroundStyle(Color.soft)
                AddOnGrid(selected: Set(items.compactMap(\.addOnId))) { a in toggleAddOn(a) }
            }
        }
    }

    private func toggleAddOn(_ a: AddOn) {
        if let i = items.firstIndex(where: { $0.addOnId == a.id }) { items.remove(at: i) } else { items.append(FoodItem(addOn: a)) }
    }

    private func update(_ id: String, _ change: (inout FoodItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    private func remove(_ id: String) {
        items.removeAll { $0.id == id }
        if open == id { open = nil }
    }

    /// «Voltar»: before saving, back to where you came from (the food waits there); after «Editar refeição», back to
    /// the summary with the meal as it was saved
    private func back() {
        if let saved {
            items = itemsAtSave
            reopened = saved
            open = nil
            showingSummary = true
        } else {
            onBack()
        }
    }

    /// «Guardar refeição»: the only thing that saves, all foods at once, then the summary and Desfazer
    private func save() {
        guard !showingSummary, !items.isEmpty else { return }
        let r = store.saveMeal(items, reopened: reopened)
        guard r.saved.allSatisfy({ store.record(FoodEntry.self, $0.id) != nil }) else { failed = true; return }
        failed = false
        for e in r.saved { update(e.id) { $0.date = e.date; $0.minute = e.minute } } // the same entries from now on
        reopened = r.saved
        itemsAtSave = items
        saved = r.saved
        open = nil
        showingSummary = true
        let text = r.saved.count == 1 ? "Guardado: \(r.saved[0].name)" : "Refeição guardada · \(r.saved.count) alimentos"
        UndoCenter.shared.show(text, undo: r.undo)
    }

    // MARK: After saving

    /// The day so far with this meal in it, and what could help next, without judging any food and without reading a
    /// meal that wasn't logged as skipped (decision 60)
    @ViewBuilder private func summary(_ saved: [FoodEntry]) -> some View {
        let live = saved.compactMap { store.record(FoodEntry.self, $0.id) }
        let kept = live == saved
        let day = saved.first?.date ?? Day.today
        let foods = store.foods(on: day)
        let f = store.fuel(on: day)
        let p = store.profile
        let c = FoodGoals.count(foods)
        let showTips = kept && !tipsOk && tipsHiddenOn != Day.today
        Screen(glow: .fuel) {
            VStack(alignment: .leading, spacing: 6) {
                if kept {
                    StateTag(state: .confirmed, text: "Guardado às \(clock(saved.first?.minute ?? 0))")
                } else {
                    StateTag(state: .ignored, text: "Desfeito")
                }
                Text(saved.map { $0.name.lowercased() }.joined(separator: ", ")).font(.geist(12.5)).foregroundStyle(Color.soft)
                if !kept { Text(live.isEmpty ? "Nada desta refeição ficou guardado." : "A refeição ficou como estava antes.").font(.geist(13)) }
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(kept ? "food.summary" : "food.summary.undone")
            Card {
                Eyebrow(text: day == Day.today ? "Hoje até agora" : "Nesse dia")
                goalBar("Proteína", "\(Int(f.protein)) g", estimated: true, of: "\(Int(p.proteinTarget)) g", f.protein / max(1, p.proteinTarget), .train)
                goalBar("Energia", "\(Int(f.kcal)) kcal", estimated: true, of: "\(Int(p.kcal))", f.kcal / max(1, p.kcal), .fuel)
                goalBar("Fruta", "\(c.fruit)", estimated: false, of: "\(FoodGoals.fruitTarget)", Double(c.fruit) / Double(FoodGoals.fruitTarget), .mint)
                goalBar("Sopa", "\(c.soup)", estimated: false, of: "\(FoodGoals.soupTarget)", Double(c.soup) / Double(FoodGoals.soupTarget), .mint)
                goalBar("Legumes", "\(c.veg)", estimated: false, of: "\(FoodGoals.vegTarget)", Double(c.veg) / Double(FoodGoals.vegTarget), .mint)
                Text("O que não registaste fica sem dados: não quer dizer que não comeste.").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            if showTips {
                Card(state: .suggested) {
                    HStack { Eyebrow(text: "Para as próximas refeições"); Spacer(); StateTag(state: .suggested) }
                    Text(FoodGoals.proteinHint(foods, target: p.proteinTarget)).font(.geist(13.5))
                    if !FoodGoals.missing(c).isEmpty { Text(FoodGoals.line(c, minute: Clock.minute())).font(.geist(13.5)) }
                    HStack(spacing: 8) {
                        TallSoftButton(title: "Ok") { tipsOk = true }.accessibilityIdentifier("food.tips.ok")
                        Button("Não mostrar hoje") { tipsHiddenOn = Day.today }.font(.geist(13, .semibold)).foregroundStyle(Color.soft).frame(minHeight: 44)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                PrimaryButton(title: "Concluído", area: .fuel) { onFinish() }
                    .accessibilityIdentifier("food.summary.done")
                Button("Editar refeição") { open = nil; showingSummary = false }
                    .font(.geist(13.5, .semibold)).tint(.fuel).frame(minWidth: 88, minHeight: 44)
                    .accessibilityIdentifier("food.summary.edit")
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
            .background(.ultraThinMaterial)
        }
    }

    private func goalBar(_ name: String, _ value: String, estimated: Bool, of goal: String, _ progress: Double, _ area: Area) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name).font(.geist(13))
                Spacer()
                if estimated {
                    EstimatedText(value: value).font(.geist(13, .semibold))
                } else {
                    Text(value).font(.geist(13, .semibold))
                }
                Text("de \(goal)").font(.geist(12)).foregroundStyle(Color.faint)
            }
            Bar(progress: progress, area: area)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A soft button at least 44 pt tall, for this phase's new controls
private struct TallSoftButton: View {
    var title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.geist(13.5, .semibold)).foregroundStyle(Color.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.09))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
            )
        }
        .buttonStyle(Pressable())
    }
}

/// A product from Open Food Facts, per 100 g
struct OFFProduct {
    var name: String
    var kcal100: Double
    var protein100: Double
    var carbs100: Double? // nil when Open Food Facts doesn't say: «Sem dados», never 0
    var fat100: Double?
    var serving: Double?

    static func fetch(_ code: String) async -> OFFProduct? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,nutriments,serving_quantity") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Cadence/0.2 (personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = root["product"] as? [String: Any] else { return nil }
        let n = p["nutriments"] as? [String: Any] ?? [:]
        func known(_ k: String) -> Double? { (n[k] as? Double) ?? (n[k] as? NSNumber)?.doubleValue ?? (n[k] as? String).flatMap { Double($0) } }
        func num(_ k: String) -> Double { known(k) ?? 0 }
        let serving = (p["serving_quantity"] as? Double) ?? Double(p["serving_quantity"] as? String ?? "")
        return OFFProduct(name: p["product_name"] as? String ?? "Produto \(code)", kcal100: num("energy-kcal_100g"), protein100: num("proteins_100g"), carbs100: known("carbohydrates_100g"), fat100: known("fat_100g"), serving: serving)
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
