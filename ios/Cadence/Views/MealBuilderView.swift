// Build a meal with a live estimate, then confirm it (phase 2.7: the confirmation saves, and offers the add-ons for a
// full meal), and the daily food goals card.
import SwiftUI

private let chipColumns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

struct BuilderChip: View {
    var title: String
    var detail: String = ""
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.geist(13, .semibold)).foregroundStyle(selected ? Color(hex: 0x1A1205) : Color.ink).lineLimit(2).multilineTextAlignment(.leading)
                if !detail.isEmpty { Text(detail).font(.geist(10.5)).foregroundStyle(selected ? Color(hex: 0x1A1205).opacity(0.75) : Color.faint).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Color.fuel : Color.white.opacity(0.07)))
        }
        .buttonStyle(Pressable())
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : [])
    }
}

/// Add-ons by category. Used inside the builder and after logging a meal.
struct AddOnGrid: View {
    var categories: [String] = MealBuilder.addOnCategories
    var selected: Set<String>
    var toggle: (AddOn) -> Void

    var body: some View {
        ForEach(categories, id: \.self) { category in
            Text(MealBuilder.categoryLabel(category)).font(.geist(12, .semibold)).foregroundStyle(Color.soft)
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                ForEach(MealBuilder.addOns.filter { $0.category == category }) { a in
                    BuilderChip(title: a.name, detail: "\(Int(a.kcal)) kcal · \(a.portion)", selected: selected.contains(a.id)) { toggle(a) }
                        .accessibilityIdentifier("addon.\(a.id)")
                }
            }
        }
    }
}

struct MealBuilderView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    private let onDone: (() -> Void)?
    @State private var draft = MealDraft()
    @State private var proteinGroup = "Meat"
    @State private var naming = false
    @State private var favouriteName = ""
    @State private var savedNote: String?
    /// What the confirmation shows: nothing is saved before «Guardar refeição»
    @State private var confirmItems: [FoodItem] = []
    @State private var confirming = false

    init(onDone: (() -> Void)? = nil) { self.onDone = onDone }

    private var favourites: [SavedMeal] {
        store.all(SavedMeal.self).filter { $0.built == true }.sorted { ($0.uses, $0.lastUsed) > ($1.uses, $1.lastUsed) }
    }

    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }

    private func toggle(_ id: String, _ path: WritableKeyPath<MealDraft, Set<String>>) {
        if draft[keyPath: path].contains(id) { draft[keyPath: path].remove(id) } else { draft[keyPath: path].insert(id) }
    }

    /// «Continuar»: the plate and its add-ons go to the confirmation
    private func logMeal() {
        confirmItems = MealBuilder.items(draft)
        confirming = true
    }

    /// A favourite opens the confirmation too: its amount is taken as typical until you confirm it
    private func logFavourite(_ m: SavedMeal) {
        confirmItems = [FoodItem(saved: m)]
        confirming = true
    }

    /// The same name replaces the old favourite and keeps how often it was used
    private func saveFavourite() {
        var meal = MealBuilder.favourite(draft, name: favouriteName)
        if let old = store.all(SavedMeal.self).first(where: { $0.name.lowercased() == meal.name.lowercased() }) {
            meal.id = old.id
            meal.uses = old.uses
            meal.lastUsed = old.lastUsed
        }
        store.save(meal)
        savedNote = "Guardado nos favoritos: \(meal.name)."
    }

    var body: some View {
        Screen(glow: .fuel) {
            if !favourites.isEmpty { favouritesCard }
            dishesCard
            basesCard
            proteinCard
            vegetablesCard
            saucesCard
            addOnsCard
            portionCard
        }
        .safeAreaInset(edge: .bottom) { estimateBar }
        .onChange(of: draft) { savedNote = nil }
        .navigationDestination(isPresented: $confirming) {
            FoodConfirmView(items: $confirmItems, onBack: { confirming = false }, onFinish: { finish() })
        }
        .navigationTitle("Montar uma refeição")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { if onDone == nil { Button("Fechar") { dismiss() } } }
        }
        .alert("Guardar como favorito", isPresented: $naming) {
            TextField("Nome", text: $favouriteName)
            Button("Guardar") { saveFavourite() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Da próxima vez, encontra-a aqui ou em Registar comida.") }
    }

    private var favouritesCard: some View {
        Card(tint: .fuel) {
            Eyebrow(text: "Os teus favoritos", icon: "star.fill", color: .fuel)
            ForEach(favourites) { m in
                Button { logFavourite(m) } label: {
                    HStack {
                        Text(m.name).font(.geist(14)).foregroundStyle(Color.ink).lineLimit(1)
                        Spacer()
                        Text("\(Int(m.kcal)) · \(Int(m.protein)) g").font(.mono(12.5)).foregroundStyle(Color.soft)
                    }
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Apagar", systemImage: "trash", role: .destructive) { store.remove(m) } }
                .accessibilityIdentifier("builder.favourite")
            }
        }
    }

    private var dishesCard: some View {
        Card {
            Eyebrow(text: "Começar por um prato típico", icon: "fork.knife")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MealBuilder.dishes) { d in
                        let on = MealBuilder.matchingDish(draft)?.name == d.name
                        Button { applyDish(d) } label: { Chip(text: d.name, color: on ? Color(hex: 0x1A1205) : .ink, fill: on ? Color.fuel : Color.white.opacity(0.08)) }
                            .buttonStyle(Pressable())
                    }
                }
            }
        }
    }

    private func applyDish(_ d: MealDish) {
        var next = d.draft
        next.factor = draft.factor
        next.addOns = draft.addOns
        draft = next
        if let id = next.protein, let p = MealBuilder.protein(id) { proteinGroup = p.group }
    }

    private var basesCard: some View {
        Card {
            Eyebrow(text: "Base · escolhe uma ou duas", icon: "circle.grid.2x2")
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                BuilderChip(title: "Nenhuma", selected: draft.bases.isEmpty) { draft.bases = [] }
                ForEach(MealBuilder.bases) { b in
                    BuilderChip(title: b.name, detail: partDetail(b), selected: draft.bases.contains(b.id)) { toggle(b.id, \.bases) }
                        .accessibilityIdentifier("builder.base.\(b.id)")
                }
            }
        }
    }

    private var proteinCard: some View {
        Card {
            Eyebrow(text: "Proteína", icon: "flame")
            Picker("", selection: $proteinGroup) { ForEach(MealBuilder.proteinGroups, id: \.self) { Text(MealBuilder.proteinGroupLabel($0)).tag($0) } }.pickerStyle(.segmented)
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                BuilderChip(title: "Nenhuma", selected: draft.protein == nil) { draft.protein = nil; draft.method = nil }
                ForEach(MealBuilder.proteins.filter { $0.group == proteinGroup }) { p in
                    BuilderChip(title: p.name, detail: partDetail(p), selected: draft.protein == p.id) { pickProtein(p) }
                        .accessibilityIdentifier("builder.protein.\(p.id)")
                }
            }
            methodRow
        }
    }

    private func pickProtein(_ p: FoodPart) {
        if draft.protein == p.id { draft.protein = nil; draft.method = nil; return }
        draft.protein = p.id
        draft.method = p.methods.first
    }

    @ViewBuilder private var methodRow: some View {
        if let id = draft.protein, let p = MealBuilder.protein(id), !p.methods.isEmpty {
            let current = MealBuilder.effectiveMethod(draft)
            Text("Como é cozinhado").font(.geist(12, .semibold)).foregroundStyle(Color.soft)
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                ForEach(p.methods, id: \.self) { m in
                    BuilderChip(title: m.label, selected: current == m) { draft.method = m }
                        .accessibilityIdentifier("builder.method.\(m.rawValue)")
                }
            }
        }
    }

    private var vegetablesCard: some View {
        Card {
            Eyebrow(text: "Legumes ou salada", icon: "leaf")
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                ForEach(MealBuilder.vegetables) { v in
                    BuilderChip(title: v.name, detail: partDetail(v), selected: draft.vegetables.contains(v.id)) { toggle(v.id, \.vegetables) }
                        .accessibilityIdentifier("builder.veg.\(v.id)")
                }
            }
        }
    }

    private var saucesCard: some View {
        Card {
            Eyebrow(text: "Molhos, azeite e extras", icon: "drop")
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                ForEach(MealBuilder.sauces) { s in
                    BuilderChip(title: s.name, detail: partDetail(s), selected: draft.sauces.contains(s.id)) { toggle(s.id, \.sauces) }
                        .accessibilityIdentifier("builder.sauce.\(s.id)")
                }
            }
        }
    }

    private var addOnsCard: some View {
        Card {
            Eyebrow(text: "Com a refeição", icon: "plus.circle")
            AddOnGrid(categories: MealBuilder.addOnCategories.filter { $0 != "Salad" }, selected: draft.addOns) { a in toggle(a.id, \.addOns) }
        }
    }

    private var portionCard: some View {
        Card {
            Eyebrow(text: "Porção", icon: "scalemass")
            HStack(spacing: 8) {
                ForEach(portionSizes, id: \.name) { p in
                    BuilderChip(title: portionSizeLabel(p.name), selected: abs(draft.factor - p.factor) < 0.001) { draft.factor = p.factor }
                        .accessibilityIdentifier("builder.portion.\(p.name.lowercased())")
                }
            }
            Stepper(value: $draft.factor, in: 0.5...2.5, step: 0.05) {
                Text("\(Int((draft.factor * 100).rounded()))% de um prato normal").font(.geist(13.5)).foregroundStyle(Color.soft)
            }
            .accessibilityIdentifier("builder.portion.stepper")
        }
    }

    private var estimateBar: some View {
        let t = MealBuilder.total(draft).rounded
        let empty = MealBuilder.isEmpty(draft)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Eyebrow(text: "Estimativa", color: .fuel)
                Text(empty ? "Escolhe algo para começar" : MealBuilder.name(draft)).font(.geist(12.5)).foregroundStyle(Color.soft).lineLimit(1)
            }
            HStack {
                stat("\(Int(t.kcal))", "kcal")
                Spacer()
                stat("\(Int(t.protein)) g", "proteína")
                Spacer()
                stat("\(Int(t.carbs)) g", "hidratos")
                Spacer()
                stat("\(Int(t.fat)) g", "gordura")
            }
            .accessibilityIdentifier("builder.estimate")
            if let savedNote { Text(savedNote).font(.geist(12)).foregroundStyle(Color.good).lineLimit(1) }
            HStack(spacing: 8) {
                SoftButton(title: "Favorito", icon: "star") {
                    favouriteName = ""
                    naming = true
                }
                .disabled(empty)
                .accessibilityIdentifier("builder.favourite.save")
                PrimaryButton(title: "Continuar", area: .fuel) { logMeal() }
                    .disabled(empty)
                    .opacity(empty ? 0.5 : 1)
                    .accessibilityIdentifier("builder.save")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.mono(16, .semibold)).foregroundStyle(Color.ink)
            Text(label).font(.geist(11)).foregroundStyle(Color.faint)
        }
    }

    private func partDetail(_ p: FoodPart) -> String {
        p.note.isEmpty ? "\(Int(p.grams)) g" : "\(Int(p.grams)) g · \(p.note)"
    }
}

private struct FoodGoalSlot: Identifiable {
    var id: String
    var label: String
    var count: Int
    var target: Int
    var addOn: AddOn
}

/// Daily goals on Today: fruit, soup, vegetables and a protein spread hint, with one-tap adds
struct FoodGoalsCard: View {
    @EnvironmentObject var store: Store
    @State private var justAdded: FoodEntry?
    @State private var tick = 0

    var body: some View {
        if store.profile.on("fuel") { card }
    }

    private var card: some View {
        let foods = store.foods()
        let counts = FoodGoals.count(foods)
        let met = FoodGoals.goalsMet(counts)
        return Card(tint: met == 3 ? Color.good : nil) {
            HStack {
                Eyebrow(text: "Metas de comida", icon: "leaf.fill", color: .good)
                Spacer()
                Text("\(met)/3").font(.mono(12.5)).foregroundStyle(Color.soft)
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(slots(counts)) { s in column(s) }
            }
            footer(counts, foods: foods)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("foodgoals.card")
        .sensoryFeedback(.success, trigger: tick)
        .task(id: justAdded?.id) {
            guard justAdded != nil else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { justAdded = nil }
        }
    }

    private func slots(_ c: FoodGoalCounts) -> [FoodGoalSlot] {
        [
            FoodGoalSlot(id: "fruit", label: "Fruta", count: c.fruit, target: FoodGoals.fruitTarget, addOn: MealBuilder.pieceOfFruit),
            FoodGoalSlot(id: "soup", label: "Sopa", count: c.soup, target: FoodGoals.soupTarget, addOn: MealBuilder.mugOfSoup),
            FoodGoalSlot(id: "veg", label: "Legumes", count: c.veg, target: FoodGoals.vegTarget, addOn: MealBuilder.vegPortion),
        ]
    }

    private func column(_ s: FoodGoalSlot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(s.label).font(.geist(13, .semibold))
                Spacer(minLength: 0)
                Text("\(s.count)/\(s.target)").font(.mono(12.5)).foregroundStyle(s.count >= s.target ? Color.good : Color.soft)
            }
            Bar(progress: Double(s.count) / Double(s.target), area: s.count >= s.target ? .mint : .fuel)
            SoftButton(title: "+ \(s.label)") { add(s.addOn) }
                .accessibilityIdentifier("foodgoals.add.\(s.id)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func footer(_ c: FoodGoalCounts, foods: [FoodEntry]) -> some View {
        if let e = justAdded {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.good)
                Text("Adicionado: \(e.name.lowercased()), cerca de \(Int(e.kcal)) kcal").font(.geist(12.5)).lineLimit(1)
                Spacer(minLength: 0)
                Button("Desfazer") { undo(e) }.font(.geist(12.5, .semibold)).tint(.fuel).accessibilityIdentifier("foodgoals.undo")
            }
        } else {
            Text(FoodGoals.line(c, minute: Clock.minute())).font(.geist(13)).foregroundStyle(Color.ink).accessibilityIdentifier("foodgoals.line")
            if c.fruit < FoodGoals.fruitTarget || c.soup < FoodGoals.soupTarget {
                Text(Pip.stable(c.fruit < FoodGoals.fruitTarget ? .fruitGoal : .soupGoal, store: store)).font(.geist(12)).foregroundStyle(Color.soft)
            }
        }
        Text(FoodGoals.proteinHint(foods, target: store.profile.proteinTarget)).font(.geist(12)).foregroundStyle(Color.soft).accessibilityIdentifier("foodgoals.protein")
    }

    private func add(_ a: AddOn) {
        let e = a.entry()
        store.logFood(e)
        tick += 1
        withAnimation { justAdded = e }
    }

    private func undo(_ e: FoodEntry) {
        store.remove(e)
        withAnimation { justAdded = nil }
    }
}
