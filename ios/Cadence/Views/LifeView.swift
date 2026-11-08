// Life: live cards for everything outside the body, as in the concept. Each card shows what matters now and opens
// its full screen: money, what to wear, the kitchen, home freshness, plants, documents and bills, people.
import SwiftUI

struct LifeView: View {
    @EnvironmentObject var store: Store

    private var attention: Int {
        var n = store.reviewInbox.isEmpty ? 0 : 1
        n += store.all(Chore.self).filter { $0.freshness < 0.1 }.count
        n += store.all(Plant.self).filter { store.plantDue($0).due }.count
        n += store.documentsSoon.count + store.keepInTouchDue.count
        n += store.laundryLoads().filter(\.full).count
        return n
    }

    var body: some View {
        NavigationStack {
            Screen(glow: Color(hex: 0x1D2550)) {
                HStack(alignment: .bottom) {
                    Title(eyebrow: attention == 0 ? "All calm" : "\(attention) thing\(attention == 1 ? "" : "s") want attention", title: "Life")
                        .accessibilityIdentifier("life.screen")
                    Spacer()
                    Chip(text: store.tick.formatted(.dateTime.weekday(.abbreviated)))
                }
                .padding(.top, 8)
                if store.profile.on("money") { link(MoneyView()) { moneyCard } }
                if store.profile.on("wardrobe") { link(WardrobeView()) { wardrobeCard } }
                if store.profile.on("kitchen") { link(KitchenView()) { kitchenCard } }
                if store.profile.on("home") {
                    link(HomeView()) { homeCard }
                    if !store.all(Plant.self).isEmpty { link(HomeView()) { plantsCard } }
                    link(HomeView()) { documentsCard }
                }
                if store.profile.on("people") { link(PeopleView()) { peopleCard } }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func link<D: View, C: View>(_ dest: D, @ViewBuilder _ card: () -> C) -> some View {
        NavigationLink { dest } label: { card() }.buttonStyle(Pressable())
    }

    private func header(_ text: String, _ icon: String, _ color: Color = .soft) -> some View {
        HStack { Eyebrow(text: text, icon: icon, color: color); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
    }

    // MARK: Money

    private var moneyCard: some View {
        let m = store.moneyMonth()
        let next = store.upcomingRenewals.first { $0.0.amount < 0 }
        let gold = Color(hex: 0xFFD166)
        return Card(tint: gold) {
            header("Money", "eurosign.circle.fill", gold)
            HStack(alignment: .firstTextBaseline) {
                Text(euro(m.safePerDay)).font(.geist(30, .bold)).tracking(-0.6)
                Text("a day safe to spend").font(.geist(12.5)).foregroundStyle(Color.soft)
                Spacer()
                if !store.reviewInbox.isEmpty { Chip(text: "\(store.reviewInbox.count) to review", color: .warn) }
            }
            Bar(progress: m.income > 0 ? (m.fixed + m.spent) / m.income : 0, area: .fuel)
            HStack {
                Text("On track to save \(euro(m.projectedSaving))").font(.geist(12.5)).foregroundStyle(m.projectedSaving >= m.goals ? Color.good : Color.warn)
                Spacer()
                if let n = next { Text("\(n.0.title) \(Day.date(n.1).formatted(.dateTime.day().month()))").font(.mono(11.5)).foregroundStyle(Color.faint) }
            }
        }
    }

    // MARK: Wardrobe

    private var wardrobeCard: some View {
        let outfit = store.outfit()
        let loads = store.laundryLoads()
        return Card(tint: Color(hex: 0x7FB8FF)) {
            header("Wear today", "tshirt.fill", Color(hex: 0x7FB8FF))
            if let call = store.weatherCall() {
                Text((call.umbrella ? "Umbrella · " : "") + ["", "T-shirt weather", "Light layer", "Jumper and a jacket", "Coat and layers"][call.layers]).font(.geist(14, .semibold))
            }
            if outfit.isEmpty {
                Text("Add clothes and Cadence matches them to the weather and your day.").font(.geist(12.5)).foregroundStyle(Color.soft)
            } else {
                HStack(spacing: 6) {
                    ForEach(outfit.prefix(5)) { g in GarmentImage(garment: g).frame(width: 52, height: 52) }
                    Spacer()
                }
            }
            if let load = loads.first {
                HStack { Text("Laundry · \(load.group)").font(.geist(12.5)); Spacer(); Text(load.full ? "ready to wash" : "\(load.items.count) of 11").font(.geist(12)).foregroundStyle(load.full ? Color.warn : Color.faint) }
            }
        }
    }

    // MARK: Kitchen

    private var kitchenCard: some View {
        let fridge = store.fridge
        let list = store.shoppingList()
        let soon = fridge.first { !$0.frozen && Day.between(Day.today, $0.eatBy) <= 1 }
        return Card(tint: Color(hex: 0xFFCF70)) {
            header("Kitchen", "frying.pan.fill", Color(hex: 0xFFCF70))
            HStack(spacing: 18) {
                stat("\(fridge.count)", "in the fridge")
                stat("\(list.count)", "to buy")
                stat("\(Int(store.planCoverage(store.week).protein * 100))%", "week's protein planned")
            }
            if let soon { Text("Eat \(soon.name.lowercased()) by \(Day.date(soon.eatBy).formatted(.dateTime.weekday(.wide)))").font(.geist(12.5)).foregroundStyle(Color.warn) }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.geist(20, .bold)).tracking(-0.4)
            Text(label).font(.geist(11)).foregroundStyle(Color.soft)
        }
    }

    // MARK: Home

    private var homeCard: some View {
        let chores = store.all(Chore.self).sorted { $0.freshness < $1.freshness }.prefix(3)
        return Card {
            header("Home · freshness", "house.fill", Color(hex: 0x8FA8FF))
            ForEach(Array(chores)) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.title).font(.geist(13.5))
                        Spacer()
                        Text(c.freshness < 0.1 ? "overdue" : c.daysSince.map { "\(max(0, c.everyDays - $0)) d left" } ?? "start it").font(.geist(11.5)).foregroundStyle(c.freshness < 0.1 ? Color.bad : Color.soft)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(LinearGradient(colors: c.freshness < 0.3 ? [.warn, .bad] : [.good, .warn], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, g.size.width * (1 - c.freshness)))
                        }
                    }
                    .frame(height: 5)
                }
            }
            if !store.tidyQueue.isEmpty { Chip(text: "10-min tidy queue", color: .mint, fill: Color.mint.opacity(0.15)) }
        }
    }

    private var plantsCard: some View {
        let plants = store.all(Plant.self)
        return Card {
            header("Plants", "leaf.fill", .good)
            ForEach(plants.prefix(3)) { p in
                let due = store.plantDue(p)
                HStack { Text(p.name).font(.geist(13.5)); Spacer(); Text(due.note).font(.geist(11.5)).foregroundStyle(due.due ? Color.warn : Color.soft) }
            }
        }
    }

    private var documentsCard: some View {
        let docs = store.documentsSoon
        let renewals = store.upcomingRenewals.filter { $0.0.amount < 0 }.prefix(2)
        let subs = store.all(Recurring.self).filter { $0.subscription && $0.amount < 0 }.map { -$0.amount / Double(max(1, $0.everyMonths)) }.reduce(0, +)
        return Card(tint: docs.isEmpty ? nil : .warn) {
            header("Documents and bills", "doc.text.fill", docs.isEmpty ? .soft : .warn)
            if docs.isEmpty && renewals.isEmpty { Text("Passport, ID, car inspection, warranties and renewals, with warnings in time.").font(.geist(12.5)).foregroundStyle(Color.soft) }
            ForEach(docs.prefix(2)) { d in
                let months = max(0, Day.between(Day.today, d.expires) / 30)
                HStack { Text(d.title).font(.geist(13.5)); Spacer(); Chip(text: months <= 1 ? "\(max(0, Day.between(Day.today, d.expires))) days left" : "\(months) months left", color: .warn) }
            }
            ForEach(Array(renewals), id: \.0.id) { r, d in
                HStack { Text(r.title).font(.geist(13.5)); Spacer(); Text("\(euro(-r.amount, decimals: true)) · \(Day.between(Day.today, d) == 0 ? "today" : "in \(Day.between(Day.today, d)) days")").font(.mono(11.5)).foregroundStyle(Color.soft) }
            }
            if subs > 0 { HStack { Text("Subscriptions").font(.geist(13.5)); Spacer(); Text("\(euro(subs)) / month").font(.mono(11.5)).foregroundStyle(Color.soft) } }
        }
    }

    // MARK: People

    private var peopleCard: some View {
        let due = store.keepInTouchDue
        let birthdays = store.birthdaysSoon
        return Card(tint: due.isEmpty && birthdays.isEmpty ? nil : Color(hex: 0xFF9FBF)) {
            header("People", "person.2.fill", Color(hex: 0xFF9FBF))
            if due.isEmpty && birthdays.isEmpty { Text("Birthdays, gift ideas and the people you want to keep in touch with.").font(.geist(12.5)).foregroundStyle(Color.soft) }
            ForEach(due.prefix(2)) { p in
                let over = (p.lastContact.map { Day.between($0, Day.today) } ?? p.everyWeeks * 7) - p.everyWeeks * 7
                HStack { Text("\(p.name) · every \(p.everyWeeks) weeks").font(.geist(13.5)); Spacer(); Chip(text: over > 0 ? "\(over) days over" : "due") }
            }
            ForEach(birthdays.prefix(2), id: \.name) { b in
                HStack { Text("\(b.name)'s birthday · \(Day.date(b.date).formatted(.dateTime.weekday(.wide)))").font(.geist(13.5)); Spacer(); if b.person?.gifts.isEmpty == false { Text("gift idea saved").font(.geist(11.5)).foregroundStyle(Color.soft) } }
            }
        }
    }
}
