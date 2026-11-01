// Meal prep and shopping: the week's plan and what it covers, the guided prep session, the fridge, the pantry, the list.
import SwiftUI

struct KitchenView: View {
    @EnvironmentObject var store: Store
    @State private var editingRecipe: Recipe?
    @State private var editingPantry: PantryItem?
    @State private var prepping = false
    @State private var newItem = ""

    var body: some View {
        let week = store.week
        let cover = store.planCoverage(week)
        Screen(glow: Color(hex: 0xFFCF70)) {
            Card(tint: .fuel) {
                HStack { Eyebrow(text: "This week's prep", icon: "frying.pan.fill", color: .fuel); Spacer(); if !store.plan(for: week).isEmpty { SoftButton(title: "Start prep", icon: "play.fill") { prepping = true } } }
                ForEach(store.plan(for: week), id: \.0.id) { r, n in
                    HStack {
                        Text(r.name).font(.geist(14))
                        Spacer()
                        Text("×\(n) · \(Int(r.protein)) g P").font(.mono(12.5)).foregroundStyle(Color.soft)
                        Stepper("", value: Binding(get: { n }, set: { store.save(MealPlanEntry(week: week, recipeId: r.id, portions: $0)) }), in: 0...14).labelsHidden()
                    }
                }
                Bar(progress: cover.protein, area: .fuel)
                Text("Covers \(Int(cover.protein * 100))% of the week's protein and \(Int(cover.kcal * 100))% of calories").font(.geist(12)).foregroundStyle(Color.soft)
            }
            Card {
                HStack { Eyebrow(text: "Recipes", icon: "book.closed.fill"); Spacer(); Button { editingRecipe = Recipe(name: "") } label: { Image(systemName: "plus") }.tint(.fuel) }
                ForEach(store.all(Recipe.self).sorted { $0.protein / $0.kcal > $1.protein / $1.kcal }) { r in
                    HStack {
                        Button { editingRecipe = r } label: {
                            VStack(alignment: .leading, spacing: 1) { Text(r.name).font(.geist(14, .medium)); Text("\(Int(r.kcal)) kcal · \(Int(r.protein)) g protein · keeps \(r.keepsDays) d").font(.geist(11.5)).foregroundStyle(Color.faint) }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if !store.plan(for: week).contains(where: { $0.0.id == r.id }) { Button("Plan") { store.save(MealPlanEntry(week: week, recipeId: r.id, portions: r.portions)) }.font(.geist(12.5, .semibold)).tint(.fuel) }
                    }
                }
            }
            Card {
                Eyebrow(text: "Fridge", icon: "refrigerator.fill")
                let fridge = store.fridge
                if fridge.isEmpty { Text("Prepped portions appear here with eat-by days.").font(.geist(13)).foregroundStyle(Color.soft) }
                ForEach(Dictionary(grouping: fridge, by: \.name).sorted { $0.key < $1.key }, id: \.key) { name, items in
                    HStack {
                        Text("\(items.count) × \(name)").font(.geist(14))
                        Spacer()
                        let soon = items.min { $0.eatBy < $1.eatBy }!
                        Chip(text: soon.frozen ? "frozen" : "eat by \(Day.date(soon.eatBy).formatted(.dateTime.weekday(.abbreviated)))", color: Day.between(Day.today, soon.eatBy) <= 1 && !soon.frozen ? .warn : .soft)
                        Button("Eat") { store.eat(soon) }.font(.geist(12.5, .semibold)).tint(.fuel)
                    }
                }
            }
            Card(tint: .mint) {
                let list = store.shoppingList()
                HStack {
                    Eyebrow(text: "Shopping", icon: "cart.fill", color: .mint)
                    Spacer()
                    let total = list.compactMap(\.price).reduce(0, +)
                    if total > 0 { Text("~\(euro(total))").font(.geist(13, .semibold)) }
                }
                HStack { TextField("Add to the list", text: $newItem); Button("Add") { store.save(ShoppingItem(name: newItem)); newItem = "" }.disabled(newItem.isEmpty) }
                ForEach(aisles, id: \.self) { aisle in
                    let lines = list.filter { $0.aisle == aisle }
                    if !lines.isEmpty {
                        Text(aisle).font(.geist(11.5, .semibold)).foregroundStyle(Color.soft)
                        ForEach(lines) { l in
                            HStack {
                                Button { store.tick(l) } label: { Image(systemName: "circle").foregroundStyle(Color.soft) }.buttonStyle(.plain)
                                Text(l.qty > 1 || !l.unit.isEmpty ? "\(l.name) \(kg(l.qty.rounded())) \(l.unit)" : l.name).font(.geist(14))
                                Spacer()
                                Text(l.reason).font(.geist(11)).foregroundStyle(Color.faint).lineLimit(1)
                            }
                        }
                    }
                }
            }
            Card {
                HStack { Eyebrow(text: "Pantry", icon: "cabinet.fill"); Spacer(); Button { editingPantry = PantryItem(name: "", qty: 0) } label: { Image(systemName: "plus") }.tint(.fuel) }
                ForEach(store.all(PantryItem.self).sorted { $0.name < $1.name }) { p in
                    Button { editingPantry = p } label: {
                        HStack {
                            Text(p.name).font(.geist(14))
                            Spacer()
                            Text("\(kg(p.qty)) \(p.unit)").font(.mono(12.5)).foregroundStyle(Color.soft)
                            if let d = store.runOut(p) { Chip(text: "\(d) d left", color: d <= 10 ? .warn : .soft) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Meal prep and shopping")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingRecipe) { RecipeEditor(recipe: $0) }
        .sheet(item: $editingPantry) { PantryEditor(item: $0) }
        .fullScreenCover(isPresented: $prepping) { PrepSession(week: week) }
        .task { seedRecipes() }
    }

    private func seedRecipes() {
        guard store.all(Recipe.self).isEmpty else { return }
        store.save(Recipe(name: "Chicken rice bowl", portions: 4, kcal: 720, protein: 44,
                          ingredients: [Ingredient(name: "Chicken breast", qty: 800, aisle: "Meat and fish"), Ingredient(name: "Rice", qty: 320, aisle: "Pantry"), Ingredient(name: "Broccoli", qty: 600, aisle: "Fruit and veg"), Ingredient(name: "Olive oil", qty: 30, unit: "ml", aisle: "Pantry")],
                          steps: [PrepStep(title: "Oven 200°, chicken in", minutes: 25, parallel: true), PrepStep(title: "Rice on, 12 min", minutes: 12, parallel: true), PrepStep(title: "Chop broccoli and steam it", minutes: 10), PrepStep(title: "Portion into 4 boxes", minutes: 5)]))
        store.save(Recipe(name: "Turkey chili", portions: 3, kcal: 610, protein: 41,
                          ingredients: [Ingredient(name: "Turkey mince", qty: 750, aisle: "Meat and fish"), Ingredient(name: "Kidney beans", qty: 400, aisle: "Pantry"), Ingredient(name: "Chopped tomatoes", qty: 800, aisle: "Pantry"), Ingredient(name: "Onion", qty: 2, unit: "", aisle: "Fruit and veg")],
                          steps: [PrepStep(title: "Brown turkey, onions, peppers", minutes: 10), PrepStep(title: "Tomatoes and beans in, simmer", minutes: 25, parallel: true), PrepStep(title: "Portion; freeze two", minutes: 5)]))
        store.save(Recipe(name: "Overnight oats", portions: 3, kcal: 450, protein: 28,
                          ingredients: [Ingredient(name: "Oats", qty: 240, aisle: "Pantry"), Ingredient(name: "Skyr", qty: 3, unit: "", aisle: "Dairy"), Ingredient(name: "Milk", qty: 600, unit: "ml", aisle: "Dairy")],
                          steps: [PrepStep(title: "Oats, skyr and milk into 3 jars", minutes: 5)], keepsDays: 3, freezes: false))
        store.save(PantryItem(name: "Creatine", qty: 300, aisle: "Health"))
        store.save(PantryItem(name: "Whey protein", qty: 900, aisle: "Health"))
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
                Section("\(steps.count) steps · \(elapsed) min in") {
                    ForEach(steps, id: \.step.id) { s in
                        let isDone = done.contains(s.step.id)
                        HStack {
                            Button { if isDone { done.remove(s.step.id) } else { done.insert(s.step.id) } } label: { Image(systemName: isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(isDone ? Color.good : Color.soft) }.buttonStyle(.plain)
                            VStack(alignment: .leading) {
                                Text(s.step.title).strikethrough(isDone)
                                Text("\(s.recipe) · \(s.step.minutes) min" + (s.step.parallel ? " · runs alongside" : "")).font(.caption).foregroundStyle(Color.soft)
                            }
                            Spacer()
                            let left = s.start + s.step.minutes - elapsed
                            if !isDone && elapsed >= s.start { Text(left > 0 ? "\(left) min" : "check").font(.caption.monospaced()).foregroundStyle(left > 0 ? Color.fuel : Color.warn) }
                            else if !isDone { Text("at \(s.start) min").font(.caption.monospaced()).foregroundStyle(Color.faint) }
                        }
                    }
                }
            }
            .cadenceList()
            .navigationTitle("Prep session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Into the fridge") { store.finishPrep(week); dismiss() } }
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
                    TextField("Name", text: $recipe.name)
                    Stepper("\(recipe.portions) portions", value: $recipe.portions, in: 1...20)
                    TextField("kcal per portion", value: $recipe.kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Protein g per portion", value: $recipe.protein, format: .number).keyboardType(.decimalPad)
                    Stepper("Keeps \(recipe.keepsDays) days", value: $recipe.keepsDays, in: 1...7)
                    Toggle("Freezes well", isOn: $recipe.freezes)
                }
                Section("Ingredients (for all portions)") {
                    ForEach($recipe.ingredients) { $i in
                        HStack {
                            TextField("Ingredient", text: $i.name)
                            TextField("Qty", value: $i.qty, format: .number).keyboardType(.decimalPad).frame(width: 60)
                            TextField("unit", text: $i.unit).frame(width: 40)
                            Picker("", selection: $i.aisle) { ForEach(aisles, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 110)
                        }
                    }
                    .onDelete { recipe.ingredients.remove(atOffsets: $0) }
                    Button("Add ingredient") { recipe.ingredients.append(Ingredient(name: "", qty: 100)) }
                }
                Section("Steps") {
                    ForEach($recipe.steps) { $s in
                        VStack {
                            TextField("Step", text: $s.title)
                            HStack { Stepper("\(s.minutes) min", value: $s.minutes, in: 1...240); Toggle("Alongside", isOn: $s.parallel).fixedSize() }
                        }
                    }
                    .onDelete { recipe.steps.remove(atOffsets: $0) }
                    Button("Add step") { recipe.steps.append(PrepStep(title: "", minutes: 10)) }
                }
                if store.record(Recipe.self, recipe.id) != nil { Button("Delete recipe", role: .destructive) { store.remove(recipe); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(recipe.name.isEmpty ? "New recipe" : recipe.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(recipe); dismiss() }.disabled(recipe.name.isEmpty) }
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
                TextField("Name", text: $item.name)
                HStack { TextField("Have", value: $item.qty, format: .number).keyboardType(.decimalPad); TextField("unit", text: $item.unit).frame(width: 50) }
                TextField("Used per day (0 = learn from routines)", value: $item.usePerDay, format: .number).keyboardType(.decimalPad)
                TextField("Low at", value: $item.lowAt, format: .number).keyboardType(.decimalPad)
                TextField("Price €", value: $item.price, format: .number).keyboardType(.decimalPad)
                TextField("Protein per pack, g (optional)", value: $item.proteinPerPack, format: .number).keyboardType(.decimalPad)
                Picker("Aisle", selection: $item.aisle) { ForEach(aisles, id: \.self) { Text($0).tag($0) } }
                if store.record(PantryItem.self, item.id) != nil { Button("Delete", role: .destructive) { store.remove(item); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(item.name.isEmpty ? "Pantry item" : item.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if let p = item.price { store.put("price", item.name.lowercased(), .number(p)) }; store.save(item); dismiss() }.disabled(item.name.isEmpty) }
            }
        }
    }
}
