// Putting a food together: what's in it, the sauces and the sides, with the estimate as you go (FoodBuilds.swift).
// It only adds to the meal being logged: as with every food, only «Guardar refeição» saves.
import SwiftUI

struct FoodBuildView: View {
    @Environment(\.dismiss) private var dismiss
    let food: BuildFood
    var onAdd: (FoodItem) -> Void
    @State private var choice: BuildChoice

    init(food: BuildFood, onAdd: @escaping (FoodItem) -> Void) {
        self.food = food
        self.onAdd = onAdd
        _choice = State(initialValue: food.start)
    }

    var body: some View {
        NavigationStack {
            List {
                if !food.sizes.isEmpty {
                    Section("Quantidade") {
                        ForEach(food.sizes) { size in
                            row(size.name, on: choice.size == size.name, detail: "") { choice.size = size.name }
                        }
                    }
                }
                ForEach(food.sections) { section in
                    Section(section.title) {
                        ForEach(section.options) { option in
                            row(option.name, on: choice.picked[section.title]?.contains(option.name) == true, detail: detail(option, in: section)) {
                                choice = food.toggling(option.name, in: section, choice)
                            }
                        }
                    }
                }
            }
            .cadenceList()
            .safeAreaInset(edge: .bottom) { bar }
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() }.accessibilityIdentifier("food.build.close") }
            }
        }
    }

    private func detail(_ option: BuildOption, in section: BuildSection) -> String {
        let kcal = option.kcal * (section.scales ? food.factor(choice) : 1)
        return kcal < 1 ? "" : "\(Int(kcal.rounded())) kcal"
    }

    private func row(_ title: String, on: Bool, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.fuel : Color.faint)
                Text(title).foregroundStyle(Color.ink)
                Spacer()
                Text(detail).font(.caption.monospaced()).foregroundStyle(Color.soft)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityValue(on ? "Escolhido" : "Não escolhido")
        .accessibilityIdentifier("food.build.option.\(title)")
    }

    private var bar: some View {
        let total = food.total(choice).rounded
        return VStack(spacing: 8) {
            Text("≈ \(Int(total.kcal)) kcal · \(Int(total.protein)) g de proteína · estimativa").font(.geist(13, .semibold)).foregroundStyle(Color.ink)
            PrimaryButton(title: "Adicionar") {
                onAdd(food.item(choice))
                dismiss()
            }
            .accessibilityIdentifier("food.build.add")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
