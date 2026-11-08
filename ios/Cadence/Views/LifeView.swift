// Life: the panel for everything outside the body (phase 2.10, design v17 N_Vida). One need at a time at the top,
// with its «Porquê», the others in one line, and the areas always in the same place, each with its own state:
// wardrobe, laundry, shopping, home, kitchen, money, people, plants and documents.
import SwiftUI

/// One thing that needs you in Vida, for the panel's top card
struct LifeNeed: Identifiable {
    enum Go { case load(String), laundry, shopping, money, home, people }
    var id: String
    var title: String
    var why: String
    var action: String
    var state: DataState
    var go: Go
}

@MainActor
extension Store {
    /// What needs you in Vida, the most useful first. Only from what the app knows: a proposal is «Sugerido», something
    /// waiting for you «Pendente». Nothing here changes anything; each one opens where you decide
    func lifeNeeds(on day: String = Day.today) -> [LifeNeed] {
        var out: [LifeNeed] = []
        if profile.on("wardrobe") {
            if let kit = gymKitNeed(on: day) {
                out.append(LifeNeed(id: "laundry.gym", title: "Lavar a roupa de treino", why: "esta " + gymKitText(trainings: kit.trainings, clean: kit.clean) + ".",
                                    action: "Ver a carga sugerida", state: .suggested, go: .load(kit.group)))
            }
            for load in laundryLoads().sorted(by: { $0.group < $1.group }) where load.full {
                out.append(LifeNeed(id: "laundry.full.\(load.group)", title: "Lavar uma carga de \(washGroupLabel(load.group))", why: "\(load.items.count) peças para lavar no mesmo grupo enchem uma máquina.",
                                    action: "Ver a carga sugerida", state: .suggested, go: .load(load.group)))
            }
        }
        if profile.on("kitchen") {
            let suggestions = shoppingList().filter { !$0.mine }
            if let first = suggestions.first {
                let title = suggestions.count == 1 ? "\(first.name) para a lista de compras" : "\(suggestions.count) sugestões para a lista de compras"
                out.append(LifeNeed(id: "shopping", title: title, why: "\(first.originLabel) \(shoppingReasonLabel(first.reason)).", action: "Ver as sugestões", state: .suggested, go: .shopping))
            }
        }
        if profile.on("money"), !reviewInbox.isEmpty {
            let n = reviewInbox.count
            out.append(LifeNeed(id: "money.review", title: n == 1 ? "1 transação por rever" : "\(n) transações por rever", why: "chegaram sem a tua confirmação da categoria.",
                                action: "Rever", state: .pending, go: .money))
        }
        if profile.on("home") {
            let chores = all(Chore.self).filter { $0.freshness < 0.1 }.sorted { ($0.freshness, $0.title) < ($1.freshness, $1.title) }
            if let c = chores.first {
                let last = c.daysSince.map { "a última vez foi há \($0) \($0 == 1 ? "dia" : "dias")" } ?? "ainda sem registo"
                out.append(LifeNeed(id: "home.chores", title: chores.count == 1 ? c.title : "\(c.title) e mais \(chores.count - 1)",
                                    why: "a cada \(c.everyDays) dias; \(last).", action: "Ver a casa", state: .pending, go: .home))
            }
            let plants = all(Plant.self).filter { plantDue($0).due }.sorted { $0.name < $1.name }
            if let p = plants.first {
                out.append(LifeNeed(id: "home.plants", title: plants.count == 1 ? "Regar \(p.name)" : "Regar \(plants.count) plantas", why: plantDue(p).note + ".",
                                    action: "Ver as plantas", state: .pending, go: .home))
            }
            if let d = documentsSoon.first {
                let days = max(0, Day.between(day, d.expires))
                out.append(LifeNeed(id: "home.documents", title: d.title, why: days == 1 ? "termina daqui a 1 dia." : "termina daqui a \(days) dias.",
                                    action: "Ver os documentos", state: .pending, go: .home))
            }
        }
        if profile.on("people"), let p = keepInTouchDue.first {
            out.append(LifeNeed(id: "people.touch", title: "Falar com \(p.name)", why: "escolheste manter contacto a cada \(p.everyWeeks) semanas.",
                                action: "Ver as pessoas", state: .suggested, go: .people))
        }
        return out
    }
}

struct LifeView: View {
    @EnvironmentObject var store: Store
    /// «Agora não» hides a need until tomorrow, on this iPhone only and with no mark in your data: "<day>|id,id"
    @AppStorage("life.notNow") private var notNow = ""

    var body: some View {
        let hidden = hiddenToday
        let needs = store.lifeNeeds().filter { !hidden.contains($0.id) }
        NavigationStack {
            Screen(glow: Color(hex: 0x1D2550)) {
                HStack(alignment: .bottom) {
                    Title(eyebrow: store.tick.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Vida")
                        .accessibilityIdentifier("life.screen") // <name>.screen: how the UI tests know this tab's root is showing. Internal, never translated; if a redesign removes this title, the identifier moves to the new one
                    Spacer()
                }
                .padding(.top, 8)
                if let first = needs.first { nowCard(first) }
                if needs.count > 1 { moreRow(Array(needs.dropFirst())) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    areaTiles
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: The need on top

    private var hiddenToday: Set<String> {
        let parts = notNow.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == Day.today else { return [] }
        return Set(parts[1].split(separator: ",").map(String.init))
    }

    private func hideUntilTomorrow(_ id: String) {
        let ids = hiddenToday.union([id])
        notNow = Day.today + "|" + ids.sorted().joined(separator: ",")
    }

    private func nowCard(_ need: LifeNeed) -> some View {
        Card(state: need.state == .pending ? .pending : .suggested) {
            HStack { Eyebrow(text: "Agora", color: .mint); Spacer(); StateTag(state: need.state) }
            Text(need.title).font(.geist(17, .bold)).fixedSize(horizontal: false, vertical: true)
            WhyLine(text: need.why)
            NavigationLink { destination(need.go) } label: {
                Text(need.action).font(.geist(15, .semibold)).foregroundStyle(Color(hex: 0x05140F))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Area.mint.gradient))
            }
            .buttonStyle(Pressable())
            .accessibilityIdentifier("life.now.action")
            Button { hideUntilTomorrow(need.id) } label: {
                Text("Agora não").font(.geist(13.5, .semibold)).foregroundStyle(Color.soft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Esconde até amanhã")
            .accessibilityIdentifier("life.now.notnow")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("life.now")
    }

    private func moreRow(_ rest: [LifeNeed]) -> some View {
        NavigationLink { destination(rest[0].go) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rest.count == 1 ? "Mais 1 sugestão" : "Mais \(rest.count) sugestões").font(.geist(14)).foregroundStyle(Color.ink)
                    Text(rest.map(\.title).joined(separator: " · ")).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1)
                }
                Spacer()
                StateTag(state: rest[0].state)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("life.more")
    }

    @ViewBuilder private func destination(_ go: LifeNeed.Go) -> some View {
        switch go {
        case .load(let group): LaundryLoadView(group: group)
        case .laundry: LaundryView()
        case .shopping: ShoppingListView()
        case .money: MoneyView()
        case .home: HomeView()
        case .people: PeopleView()
        }
    }

    // MARK: The areas, always in the same place

    @ViewBuilder private var areaTiles: some View {
        let garments = store.garments
        if store.profile.on("wardrobe") {
            if garments.isEmpty {
                tile("Roupeiro", "sem peças", tag: (DataState.setup, DataState.setup.label), id: "wardrobe", WardrobeView())
            } else {
                let free = garments.filter { WardrobeFilter.available.matches($0) }.count
                tile("Roupeiro", "\(free) de \(garments.count) disponíveis", id: "wardrobe", WardrobeView())
            }
            tile("Lavandaria", garments.isEmpty ? "sem peças" : laundrySummary(garments), id: "laundry", LaundryView())
        }
        if store.profile.on("kitchen") {
            let list = store.shoppingList()
            let mine = list.filter(\.mine).count
            let suggested = list.count - mine
            tile("Compras", mine == 0 ? "lista vazia" : "\(mine) na lista", tag: suggested == 0 ? nil : (DataState.suggested, suggested == 1 ? "1 sugestão" : "\(suggested) sugestões"), id: "shopping", ShoppingListView())
        }
        if store.profile.on("home") {
            let chores = store.all(Chore.self)
            let due = chores.filter { $0.freshness < 0.1 }.count
            if chores.isEmpty {
                tile("Casa", "sem tarefas", tag: (DataState.setup, DataState.setup.label), id: "home", HomeView())
            } else {
                tile("Casa", due == 0 ? "\(chores.count) \(chores.count == 1 ? "tarefa em dia" : "tarefas em dia")" : "\(due) para fazer", tag: due == 0 ? nil : (DataState.pending, "Precisa de ti"), id: "home", HomeView())
            }
        }
        if store.profile.on("kitchen") {
            let recipes = store.all(Recipe.self).count
            let fridge = store.fridge.count
            tile("Cozinha", "\(recipes) \(recipes == 1 ? "receita" : "receitas")" + (fridge > 0 ? " · \(fridge) no frigorífico" : ""), id: "kitchen", KitchenView())
        }
        if store.profile.on("money") {
            if store.transactions.isEmpty {
                tile("Dinheiro", "sem transações", tag: (DataState.setup, DataState.setup.label), id: "money", MoneyView())
            } else {
                let review = store.reviewInbox.count
                tile("Dinheiro", "\(euro(store.moneyMonth().safePerDay)) por dia livre", tag: review == 0 ? nil : (DataState.pending, "\(review) por rever"), id: "money", MoneyView())
            }
        }
        if store.profile.on("people") {
            let people = store.all(Person.self)
            let due = store.keepInTouchDue.count
            let birthdays = store.birthdaysSoon.count
            if people.isEmpty && birthdays == 0 {
                tile("Pessoas", "aniversários e contacto", tag: (DataState.setup, DataState.setup.label), id: "people", PeopleView())
            } else {
                tile("Pessoas", peopleStatus(due: due, birthdays: birthdays, people: people.count), id: "people", PeopleView())
            }
        }
        if store.profile.on("home") {
            let plants = store.all(Plant.self).filter { store.plantDue($0).due }.count
            let documents = store.documentsSoon.count
            tile("Plantas e documentos", plantsStatus(plants: plants, documents: documents), tag: plants + documents == 0 ? nil : (DataState.pending, "Precisa de ti"), id: "plants", HomeView())
        }
    }

    private func peopleStatus(due: Int, birthdays: Int, people: Int) -> String {
        var parts: [String] = []
        if due > 0 { parts.append(due == 1 ? "1 para contactar" : "\(due) para contactar") }
        if birthdays > 0 { parts.append(birthdays == 1 ? "1 aniversário" : "\(birthdays) aniversários") }
        return parts.isEmpty ? (people == 1 ? "1 pessoa" : "\(people) pessoas") : parts.joined(separator: " · ")
    }

    private func plantsStatus(plants: Int, documents: Int) -> String {
        var parts: [String] = []
        if plants > 0 { parts.append(plants == 1 ? "1 rega" : "\(plants) regas") }
        if documents > 0 { parts.append(documents == 1 ? "1 prazo" : "\(documents) prazos") }
        return parts.isEmpty ? "regas e prazos" : parts.joined(separator: " · ")
    }

    private func tile<D: View>(_ title: String, _ status: String, tag: (DataState, String)? = nil, id: String, _ dest: D) -> some View {
        NavigationLink { dest } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(title).font(.geist(16, .semibold)).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
                }
                Text(status).font(.geist(12.5)).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
                if let tag { StateTag(state: tag.0, text: tag.1) }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.055))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.11), lineWidth: 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(Pressable())
        .accessibilityIdentifier("life.area.\(id)")
    }
}
