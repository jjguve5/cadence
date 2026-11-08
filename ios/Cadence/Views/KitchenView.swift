// Meal prep and shopping: the week's plan and what it covers, the guided prep session, the fridge, the pantry, the list.
// Phase 2.10 (design v17, N_Compras): the list is its own screen, one line per product, suggestions you add, adjust
// or ignore, by category, shop or occasion, and the circle marks a line bought by you, with Desfazer.
import SwiftUI

/// Compras: what you put on the list, grouped as you choose, and the app's suggestions apart. The app never buys
/// anything nor marks anything bought
struct ShoppingListView: View {
    @EnvironmentObject var store: Store
    @AppStorage("life.shopping.groupBy") private var groupBy = "aisle" // a per-iPhone view choice, not data
    @State private var ignored: Set<String> = [] // «Ignorar» leaves no mark: only hidden while you're here
    @State private var editing: ShoppingItem?

    struct ShoppingGroup: Identifiable {
        var id: String
        var lines: [ListLine]
    }

    var body: some View {
        let lines = store.shoppingList()
        let suggestions = lines.filter { !$0.mine && !ignored.contains($0.id) }
        let list = lines.filter(\.mine)
        let bought = store.boughtToday
        let total = list.compactMap(\.price).reduce(0, +)
        Screen(glow: .mint) {
            Text("Vida · lista da casa").font(.geist(13)).foregroundStyle(Color.soft)
                .accessibilityIdentifier("life.shopping.screen")
            if !suggestions.isEmpty {
                Card(state: .suggested) {
                    HStack { Eyebrow(text: "Sugestões"); Spacer(); StateTag(state: .suggested, text: "\(suggestions.count)") }
                    ForEach(suggestions) { l in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title(l)).font(.geist(15)).accessibilityIdentifier("life.shopping.suggestion.\(l.id)")
                            WhyLine(text: "\(l.originLabel) \(shoppingReasonLabel(l.reason)).")
                            DecisionButtons(accept: "Adicionar", onAccept: { accept(l) }, onAdjust: { editing = ShoppingItem(name: l.name, qty: l.qty, unit: l.unit, aisle: l.aisle) }, onIgnore: { _ = ignored.insert(l.id) })
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Segments(options: [("aisle", "Categoria"), ("shop", "Loja"), ("occasion", "Ocasião")], selection: $groupBy)
                .accessibilityIdentifier("life.shopping.groupby")
            if list.isEmpty {
                Card(state: .noData) {
                    Text("A lista está vazia.").font(.geist(14))
                    Text("O que adicionares, ou aceitares das sugestões, aparece aqui.").font(.geist(12.5)).foregroundStyle(Color.soft)
                }
            }
            ForEach(groups(list)) { group in
                Card {
                    HStack { Eyebrow(text: group.id); Spacer(); Text("\(group.lines.count)").font(.geist(11)).foregroundStyle(Color.faint) }
                    ForEach(group.lines) { l in row(l) }
                }
            }
            if !bought.isEmpty {
                Card {
                    HStack { Eyebrow(text: "Comprado hoje"); Spacer(); StateTag(state: .confirmed, text: "Comprado") }
                    ForEach(bought) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.good).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).strikethrough().font(.geist(14)).foregroundStyle(Color.soft)
                                Text("comprado por ti hoje").font(.geist(11.5)).foregroundStyle(Color.faint)
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if total > 0 {
                HStack { Text("Custo estimado").font(.geist(13)).foregroundStyle(Color.soft); Spacer(); EstimatedText(value: euro(total)).font(.geist(13, .semibold)) }
                    .padding(.horizontal, 4)
            }
            PrimaryButton(title: "+ Adicionar") { editing = ShoppingItem(name: "") }
                .accessibilityIdentifier("life.shopping.add")
            Text("A app nunca compra nem marca como comprado.").font(.geist(12)).foregroundStyle(Color.faint).frame(maxWidth: .infinity)
        }
        .navigationTitle("Compras")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ShoppingItemEditor(item: $0) }
    }

    private func title(_ l: ListLine) -> String {
        l.qty > 1 || !l.unit.isEmpty ? "\(l.name) \(kg(l.qty.rounded())) \(l.unit)" : l.name
    }

    private func groups(_ list: [ListLine]) -> [ShoppingGroup] {
        switch groupBy {
        case "shop":
            return Dictionary(grouping: list, by: \.shopLabel).map { ShoppingGroup(id: $0.key, lines: $0.value) }.sorted { $0.id < $1.id }
        case "occasion":
            return Dictionary(grouping: list, by: \.occasionLabel).map { ShoppingGroup(id: $0.key, lines: $0.value) }.sorted { $0.id < $1.id }
        default:
            var out = aisles.compactMap { a -> ShoppingGroup? in
                let ls = list.filter { $0.aisle == a }
                return ls.isEmpty ? nil : ShoppingGroup(id: shoppingAisleLabel(a), lines: ls)
            }
            let other = list.filter { !aisles.contains($0.aisle) }
            if !other.isEmpty { out.append(ShoppingGroup(id: "Sem categoria", lines: other)) }
            return out
        }
    }

    private func row(_ l: ListLine) -> some View {
        HStack(spacing: 6) {
            Button { buy(l) } label: {
                Image(systemName: "circle").font(.system(size: 20)).foregroundStyle(Color.soft)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Marcar \(l.name) como comprado")
            .accessibilityIdentifier("life.shopping.buy.\(l.id)")
            Button { editing = l.yourItem } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(l)).font(.geist(14)).foregroundStyle(Color.ink)
                    Text(shoppingReasonLabel(l.reason)).font(.geist(11.5)).foregroundStyle(Color.faint).lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ajustar")
            .accessibilityIdentifier("life.shopping.line.\(l.id)")
        }
    }

    /// The circle: bought by you, with Desfazer
    private func buy(_ l: ListLine) {
        let undo = store.buy(l)
        UndoCenter.shared.show("\(l.name): comprado por ti", undo: undo)
    }

    /// «Adicionar» a suggestion: it goes on your list, with Desfazer
    private func accept(_ l: ListLine) {
        let s = store
        let item = ShoppingItem(name: l.name, qty: l.qty, unit: l.unit, aisle: l.aisle)
        s.save(item)
        UndoCenter.shared.show("\(l.name) na lista") { s.remove(item) }
    }
}

/// Adding to the list, or adjusting a line of yours or a suggestion before it goes on the list («Ajustar»)
struct ShoppingItemEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var item: ShoppingItem

    var body: some View {
        let isNew = store.record(ShoppingItem.self, item.id) == nil
        NavigationStack {
            Form {
                TextField("Nome", text: $item.name).accessibilityIdentifier("life.shopping.editor.name")
                HStack {
                    TextField("Quantidade", value: $item.qty, format: .number).keyboardType(.decimalPad)
                    TextField("un.", text: $item.unit).frame(width: 60)
                }
                Picker("Categoria", selection: $item.aisle) { ForEach(aisles, id: \.self) { Text(shoppingAisleLabel($0)).tag($0) } }
                TextField("Loja (opcional)", text: Binding(get: { item.shop ?? "" }, set: { item.shop = $0.isEmpty ? nil : $0 }))
                TextField("Ocasião (opcional)", text: Binding(get: { item.occasion ?? "" }, set: { item.occasion = $0.isEmpty ? nil : $0 }))
            }
            .cadenceList()
            .navigationTitle(isNew ? "Adicionar à lista" : item.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("life.shopping.editor.save")
                }
            }
        }
    }

    private func save() {
        let s = store
        var saved = item
        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = s.record(ShoppingItem.self, saved.id)
        s.save(saved)
        let done = saved
        UndoCenter.shared.show(before == nil ? "\(done.name) na lista" : "\(done.name) alterado") {
            if let before { s.save(before) } else { s.remove(done) }
        }
        dismiss()
    }
}

struct KitchenView: View {
    @EnvironmentObject var store: Store
    @State private var editingRecipe: Recipe?
    @State private var editingPantry: PantryItem?
    @State private var prepping = false

    var body: some View {
        let week = store.week
        let cover = store.planCoverage(week)
        Screen(glow: Color(hex: 0xFFCF70)) {
            Card(tint: .fuel) {
                HStack { Eyebrow(text: "Preparação desta semana", icon: "frying.pan.fill", color: .fuel); Spacer(); if !store.plan(for: week).isEmpty { SoftButton(title: "Começar", icon: "play.fill") { prepping = true } } }
                ForEach(store.plan(for: week), id: \.0.id) { r, n in
                    HStack {
                        Text(r.name).font(.geist(14))
                        Spacer()
                        Text("×\(n) · \(Int(r.protein)) g P").font(.mono(12.5)).foregroundStyle(Color.soft)
                        Stepper("", value: Binding(get: { n }, set: { store.save(MealPlanEntry(week: week, recipeId: r.id, portions: $0)) }), in: 0...14).labelsHidden()
                    }
                }
                Bar(progress: cover.protein, area: .fuel)
                Text("Cobre \(Int(cover.protein * 100))% da proteína e \(Int(cover.kcal * 100))% das calorias da semana").font(.geist(12)).foregroundStyle(Color.soft)
            }
            Card {
                HStack { Eyebrow(text: "Receitas", icon: "book.closed.fill"); Spacer(); Button { editingRecipe = Recipe(name: "") } label: { Image(systemName: "plus") }.tint(.fuel) }
                ForEach(store.all(Recipe.self).sorted { $0.protein / $0.kcal > $1.protein / $1.kcal }) { r in
                    HStack {
                        Button { editingRecipe = r } label: {
                            VStack(alignment: .leading, spacing: 1) { Text(r.name).font(.geist(14, .medium)); Text("\(Int(r.kcal)) kcal · \(Int(r.protein)) g de proteína · dura \(r.keepsDays) d").font(.geist(11.5)).foregroundStyle(Color.faint) }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if !store.plan(for: week).contains(where: { $0.0.id == r.id }) { Button("Planear") { store.save(MealPlanEntry(week: week, recipeId: r.id, portions: r.portions)) }.font(.geist(12.5, .semibold)).tint(.fuel) }
                    }
                }
            }
            Card {
                Eyebrow(text: "Frigorífico", icon: "refrigerator.fill")
                let fridge = store.fridge
                if fridge.isEmpty { Text("As porções preparadas aparecem aqui, com a data-limite para as comer.").font(.geist(13)).foregroundStyle(Color.soft) }
                ForEach(Dictionary(grouping: fridge, by: \.name).sorted { $0.key < $1.key }, id: \.key) { name, items in
                    HStack {
                        Text("\(items.count) × \(name)").font(.geist(14))
                        Spacer()
                        let soon = items.min { $0.eatBy < $1.eatBy }!
                        Chip(text: soon.frozen ? "congelada" : "comer até \(Day.date(soon.eatBy).formatted(.dateTime.weekday(.abbreviated)))", color: Day.between(Day.today, soon.eatBy) <= 1 && !soon.frozen ? .warn : .soft)
                        Button("Comer") { let undo = store.eat(soon); UndoCenter.shared.show("\(name): registado") { undo() } }.font(.geist(12.5, .semibold)).tint(.fuel)
                    }
                }
            }
            // The list has its own screen (Compras, phase 2.10); here, what's on it and what's suggested
            NavigationLink { ShoppingListView() } label: {
                Card(tint: .mint) {
                    let list = store.shoppingList()
                    let mine = list.filter(\.mine).count
                    let suggested = list.count - mine
                    HStack { Eyebrow(text: "Compras", icon: "cart.fill", color: .mint); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                    Text(mine == 0 ? "A lista está vazia" : mine == 1 ? "1 artigo na lista" : "\(mine) artigos na lista").font(.geist(14)).foregroundStyle(Color.ink)
                    if suggested > 0 { StateTag(state: .suggested, text: suggested == 1 ? "1 sugestão" : "\(suggested) sugestões") }
                }
            }
            .buttonStyle(Pressable())
            .accessibilityIdentifier("life.kitchen.shopping")
            Card {
                HStack { Eyebrow(text: "Despensa", icon: "cabinet.fill"); Spacer(); Button { editingPantry = PantryItem(name: "", qty: 0) } label: { Image(systemName: "plus") }.tint(.fuel) }
                ForEach(store.all(PantryItem.self).sorted { $0.name < $1.name }) { p in
                    Button { editingPantry = p } label: {
                        HStack {
                            Text(p.name).font(.geist(14))
                            Spacer()
                            Text("\(kg(p.qty)) \(p.unit)").font(.mono(12.5)).foregroundStyle(Color.soft)
                            if let d = store.runOut(p) { Chip(text: "acaba em \(d) d", color: d <= 10 ? .warn : .soft) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Cozinha e compras")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingRecipe) { RecipeEditor(recipe: $0) }
        .sheet(item: $editingPantry) { PantryEditor(item: $0) }
        .fullScreenCover(isPresented: $prepping) { PrepSession(week: week) }
        .task { seedRecipes() }
    }

    private func seedRecipes() {
        guard store.all(Recipe.self).isEmpty else { return }
        store.save(Recipe(name: "Taça de frango com arroz", portions: 4, kcal: 720, protein: 44,
                          ingredients: [Ingredient(name: "Peito de frango", qty: 800, aisle: "Meat and fish"), Ingredient(name: "Arroz", qty: 320, aisle: "Pantry"), Ingredient(name: "Brócolos", qty: 600, aisle: "Fruit and veg"), Ingredient(name: "Azeite", qty: 30, unit: "ml", aisle: "Pantry")],
                          steps: [PrepStep(title: "Forno a 200°, meter o frango", minutes: 25, parallel: true), PrepStep(title: "Arroz ao lume, 12 min", minutes: 12, parallel: true), PrepStep(title: "Cortar os brócolos e cozê-los a vapor", minutes: 10), PrepStep(title: "Dividir por 4 caixas", minutes: 5)]))
        store.save(Recipe(name: "Chili de peru", portions: 3, kcal: 610, protein: 41,
                          ingredients: [Ingredient(name: "Carne picada de peru", qty: 750, aisle: "Meat and fish"), Ingredient(name: "Feijão encarnado", qty: 400, aisle: "Pantry"), Ingredient(name: "Tomate triturado", qty: 800, aisle: "Pantry"), Ingredient(name: "Cebola", qty: 2, unit: "", aisle: "Fruit and veg")],
                          steps: [PrepStep(title: "Alourar o peru, a cebola e os pimentos", minutes: 10), PrepStep(title: "Juntar o tomate e o feijão e deixar em lume brando", minutes: 25, parallel: true), PrepStep(title: "Dividir em porções; congelar duas", minutes: 5)]))
        store.save(Recipe(name: "Papas de aveia de véspera", portions: 3, kcal: 450, protein: 28,
                          ingredients: [Ingredient(name: "Flocos de aveia", qty: 240, aisle: "Pantry"), Ingredient(name: "Skyr", qty: 3, unit: "", aisle: "Dairy"), Ingredient(name: "Leite", qty: 600, unit: "ml", aisle: "Dairy")],
                          steps: [PrepStep(title: "Aveia, skyr e leite em 3 frascos", minutes: 5)], keepsDays: 3, freezes: false))
        store.save(PantryItem(name: "Creatina", qty: 300, aisle: "Health"))
        store.save(PantryItem(name: "Proteína whey", qty: 900, aisle: "Health"))
    }
}

/// One cooking timeline with steps in parallel and timers
struct PrepSession: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var week: String
    @State private var done = Set<String>()
    @State private var started = Date()
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let steps = store.prepTimeline(week)
        let elapsed = Int(now.timeIntervalSince(started) / 60)
        NavigationStack {
            List {
                Section("\(steps.count) \(steps.count == 1 ? "passo" : "passos") · em curso há \(elapsed) min") {
                    ForEach(steps, id: \.step.id) { s in
                        let isDone = done.contains(s.step.id)
                        HStack {
                            Button { if isDone { done.remove(s.step.id) } else { done.insert(s.step.id) } } label: { Image(systemName: isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(isDone ? Color.good : Color.soft) }.buttonStyle(.plain)
                            VStack(alignment: .leading) {
                                Text(s.step.title).strikethrough(isDone)
                                Text("\(s.recipe) · \(s.step.minutes) min" + (s.step.parallel ? " · em paralelo" : "")).font(.caption).foregroundStyle(Color.soft)
                            }
                            Spacer()
                            let left = s.start + s.step.minutes - elapsed
                            if !isDone && elapsed >= s.start { Text(left > 0 ? "\(left) min" : "ver").font(.caption.monospaced()).foregroundStyle(left > 0 ? Color.fuel : Color.warn) }
                            else if !isDone { Text("aos \(s.start) min").font(.caption.monospaced()).foregroundStyle(Color.faint) }
                        }
                    }
                }
            }
            .cadenceList()
            .navigationTitle("Sessão de preparação")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Para o frigorífico") { store.finishPrep(week); dismiss() } }
            }
            .onReceive(timer) { now = $0 }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
}

struct RecipeEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var recipe: Recipe
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $recipe.name)
                    Stepper("\(recipe.portions) \(recipe.portions == 1 ? "porção" : "porções")", value: $recipe.portions, in: 1...20)
                    TextField("kcal por porção", value: $recipe.kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Proteína g por porção", value: $recipe.protein, format: .number).keyboardType(.decimalPad)
                    Stepper("Dura \(recipe.keepsDays) \(recipe.keepsDays == 1 ? "dia" : "dias")", value: $recipe.keepsDays, in: 1...7)
                    Toggle("Pode congelar", isOn: $recipe.freezes)
                }
                Section("Ingredientes (para todas as porções)") {
                    ForEach($recipe.ingredients) { $i in
                        HStack {
                            TextField("Ingrediente", text: $i.name)
                            TextField("Qtd.", value: $i.qty, format: .number).keyboardType(.decimalPad).frame(width: 60)
                            TextField("un.", text: $i.unit).frame(width: 40)
                            Picker("", selection: $i.aisle) { ForEach(aisles, id: \.self) { Text(shoppingAisleLabel($0)).tag($0) } }.labelsHidden().frame(width: 110)
                        }
                    }
                    .onDelete { recipe.ingredients.remove(atOffsets: $0) }
                    Button("Adicionar ingrediente") { recipe.ingredients.append(Ingredient(name: "", qty: 100)) }
                }
                Section("Passos") {
                    ForEach($recipe.steps) { $s in
                        VStack {
                            TextField("Passo", text: $s.title)
                            HStack { Stepper("\(s.minutes) min", value: $s.minutes, in: 1...240); Toggle("Em paralelo", isOn: $s.parallel).fixedSize() }
                        }
                    }
                    .onDelete { recipe.steps.remove(atOffsets: $0) }
                    Button("Adicionar passo") { recipe.steps.append(PrepStep(title: "", minutes: 10)) }
                }
                if store.record(Recipe.self, recipe.id) != nil { Button("Apagar receita", role: .destructive) { store.remove(recipe); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(recipe.name.isEmpty ? "Nova receita" : recipe.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(recipe); dismiss() }.disabled(recipe.name.isEmpty) }
            }
        }
    }
}

struct PantryEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var item: PantryItem
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $item.name)
                HStack { TextField("Tenho", value: $item.qty, format: .number).keyboardType(.decimalPad); TextField("un.", text: $item.unit).frame(width: 50) }
                TextField("Uso por dia (0 = aprender com as rotinas)", value: $item.usePerDay, format: .number).keyboardType(.decimalPad)
                TextField("Avisar abaixo de", value: $item.lowAt, format: .number).keyboardType(.decimalPad)
                TextField("Preço €", value: $item.price, format: .number).keyboardType(.decimalPad)
                TextField("Proteína por embalagem, g (opcional)", value: $item.proteinPerPack, format: .number).keyboardType(.decimalPad)
                Picker("Secção", selection: $item.aisle) { ForEach(aisles, id: \.self) { Text(shoppingAisleLabel($0)).tag($0) } }
                if store.record(PantryItem.self, item.id) != nil { Button("Apagar", role: .destructive) { store.remove(item); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(item.name.isEmpty ? "Artigo da despensa" : item.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { if let p = item.price { store.put("price", item.name.lowercased(), .number(p)) }; store.save(item); dismiss() }.disabled(item.name.isEmpty) }
            }
        }
    }
}
