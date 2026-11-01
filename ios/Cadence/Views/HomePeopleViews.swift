// Home and documents, People, and Learning (review cards and skill minutes).
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var editingChore: Chore?
    @State private var editingPlant: Plant?
    @State private var editingDoc: DocumentItem?

    var body: some View {
        Screen(glow: Color(hex: 0x8FA8FF)) {
            Card {
                HStack { Eyebrow(text: "Home freshness", icon: "sparkles"); Spacer(); Button { editingChore = Chore(title: "") } label: { Image(systemName: "plus") }.tint(Color(hex: 0x8FA8FF)) }
                ForEach(store.all(Chore.self).sorted { $0.freshness < $1.freshness }) { c in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(c.title).font(.system(size: 14)); Spacer(); Text(c.daysSince.map { "\($0) d" } ?? "–").font(.system(size: 11.5)).foregroundStyle(Color.faint) }
                            Bar(progress: c.freshness, area: c.freshness < 0.2 ? .fuel : .water)
                        }
                        Button { var x = c; x.history.append(Day.today); store.save(x) } label: { Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(Color.mint) }.buttonStyle(.plain)
                    }
                    .onLongPressGesture { editingChore = c }
                }
                if (store.readiness()?.score ?? 70) < 50, !store.tidyQueue.isEmpty {
                    Text("Low-energy day: just the 10-minute tidy queue: \(store.tidyQueue.map(\.title).joined(separator: ", ")).").font(.system(size: 12.5)).foregroundStyle(Color.soft)
                }
            }
            Card(tint: .good) {
                HStack { Eyebrow(text: "Plants", icon: "leaf.fill", color: .good); Spacer(); Button { editingPlant = Plant(name: "") } label: { Image(systemName: "plus") }.tint(.good) }
                ForEach(store.all(Plant.self)) { p in
                    let due = store.plantDue(p)
                    HStack {
                        Image(systemName: p.outdoor ? "sun.max" : "house").foregroundStyle(Color.soft).frame(width: 20)
                        Text(p.name).font(.system(size: 14))
                        Spacer()
                        Text(due.note).font(.system(size: 12)).foregroundStyle(due.due ? Color.warn : Color.faint)
                        Button { var x = p; x.watered = Day.today; store.save(x) } label: { Image(systemName: "drop.circle").font(.system(size: 20)).foregroundStyle(Color.water) }.buttonStyle(.plain)
                    }
                    .onLongPressGesture { editingPlant = p }
                }
            }
            Card {
                HStack { Eyebrow(text: "Documents and checkups", icon: "doc.text.fill"); Spacer(); Button { editingDoc = DocumentItem(title: "", expires: Day.add(365, to: Day.today)) } label: { Image(systemName: "plus") }.tint(Color(hex: 0x8FA8FF)) }
                ForEach(store.all(DocumentItem.self).sorted { $0.expires < $1.expires }) { d in
                    Button { editingDoc = d } label: {
                        HStack {
                            Text(d.title).font(.system(size: 14))
                            Spacer()
                            let days = Day.between(Day.today, d.expires)
                            Chip(text: days < 0 ? "expired" : "\(Day.date(d.expires).formatted(.dateTime.day().month().year()))", color: days <= d.leadDays ? .warn : .soft)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(store.documentWarnings(), id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(Color.warn) }
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .task { seed() }
        .sheet(item: $editingChore) { c in SimpleEditor(title: "Chore", onDelete: { store.remove(c) }) { ChoreForm(chore: c) } }
        .sheet(item: $editingPlant) { p in SimpleEditor(title: "Plant", onDelete: { store.remove(p) }) { PlantForm(plant: p) } }
        .sheet(item: $editingDoc) { d in SimpleEditor(title: "Document", onDelete: { store.remove(d) }) { DocForm(doc: d) } }
    }

    private func seed() {
        guard store.all(Chore.self).isEmpty else { return }
        for (t, r, e, m) in [("Hoover", "Home", 7, 20), ("Bathroom", "Bathroom", 7, 20), ("Change bed sheets", "Bedroom", 14, 10), ("Kitchen surfaces", "Kitchen", 3, 10), ("Take out recycling", "Kitchen", 4, 5), ("Fridge clean-out", "Kitchen", 14, 10)] {
            store.save(Chore(title: t, room: r, everyDays: e, minutes: m))
        }
    }
}

/// A sheet wrapper for the small forms below
struct SimpleEditor<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var onDelete: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        NavigationStack {
            content
                .cadenceList()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .destructiveAction) { Button("Delete", role: .destructive) { onDelete(); dismiss() } }
                }
        }
    }
}

struct ChoreForm: View {
    @EnvironmentObject var store: Store
    @State var chore: Chore
    var body: some View {
        Form {
            TextField("Chore", text: $chore.title)
            TextField("Room", text: $chore.room)
            Stepper("Every \(chore.everyDays) days", value: $chore.everyDays, in: 1...90)
            Stepper("About \(chore.minutes) min", value: $chore.minutes, in: 5...120, step: 5)
            Button("Save") { store.save(chore) }.disabled(chore.title.isEmpty)
        }
    }
}

struct PlantForm: View {
    @EnvironmentObject var store: Store
    @State var plant: Plant
    var body: some View {
        Form {
            TextField("Plant", text: $plant.name)
            Picker("Lives", selection: $plant.outdoor) { Text("Indoors").tag(false); Text("Outdoors").tag(true) }.pickerStyle(.segmented)
            Stepper("Water every \(plant.everyDays) days", value: $plant.everyDays, in: 1...30)
            Text(plant.outdoor ? "Outdoor plants count rain as watering and need more in heat." : "Indoor plants ignore the weather.").font(.footnote).foregroundStyle(Color.soft)
            Button("Save") { store.save(plant) }.disabled(plant.name.isEmpty)
        }
    }
}

struct DocForm: View {
    @EnvironmentObject var store: Store
    @State var doc: DocumentItem
    var body: some View {
        Form {
            TextField("Passport, ID, licence, IPO…", text: $doc.title)
            Picker("Kind", selection: $doc.kind) { Text("Document").tag("document"); Text("Checkup").tag("checkup"); Text("Warranty").tag("warranty"); Text("Car").tag("car") }
            DatePicker("Expires / due", selection: Binding(get: { Day.date(doc.expires) }, set: { doc.expires = Day.key($0) }), displayedComponents: .date)
            Stepper("Warn \(doc.leadDays) days before", value: $doc.leadDays, in: 7...365, step: 7)
            TextField("Notes", text: $doc.notes)
            Button("Save") { store.save(doc) }.disabled(doc.title.isEmpty)
        }
    }
}

struct PeopleView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Person?
    var body: some View {
        Screen(glow: Color(hex: 0xFF9FBF)) {
            let soon = store.birthdaysSoon
            if !soon.isEmpty {
                Card(tint: Color(hex: 0xFF9FBF)) {
                    Eyebrow(text: "Birthdays soon", icon: "gift.fill", color: Color(hex: 0xFF9FBF))
                    ForEach(soon, id: \.name) { b in
                        HStack {
                            Text(b.name).font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(Day.date(b.date).formatted(.dateTime.weekday(.abbreviated).day().month())).font(.system(size: 12.5)).foregroundStyle(Color.soft)
                        }
                        if let gifts = b.person?.gifts, !gifts.isEmpty { Text("Ideas: " + gifts.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Color.soft) }
                    }
                }
            }
            let due = store.keepInTouchDue
            if !due.isEmpty {
                Card {
                    Eyebrow(text: "It's been a while", icon: "bubble.left.and.bubble.right.fill")
                    ForEach(due) { p in
                        HStack {
                            Text(p.name).font(.system(size: 14))
                            Spacer()
                            Button("Talked today") { var x = p; x.lastContact = Day.today; store.save(x) }.font(.system(size: 12.5, weight: .semibold)).tint(Color(hex: 0xFF9FBF))
                        }
                    }
                }
            }
            Card {
                HStack { Eyebrow(text: "People", icon: "person.2.fill"); Spacer(); Button { editing = Person(name: "") } label: { Image(systemName: "plus") }.tint(Color(hex: 0xFF9FBF)) }
                ForEach(store.all(Person.self).sorted { $0.name < $1.name }) { p in
                    Button { editing = p } label: {
                        HStack {
                            Text(p.name).font(.system(size: 14))
                            Spacer()
                            if p.keepInTouch { Text("every \(p.everyWeeks) wk").font(.system(size: 11.5)).foregroundStyle(Color.faint) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Text("Keep in touch is off unless you set it up for a person. Mentioning someone in a day's note counts as contact.").font(.system(size: 11.5)).foregroundStyle(Color.faint)
            }
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { p in SimpleEditor(title: p.name.isEmpty ? "New person" : p.name, onDelete: { store.remove(p) }) { PersonForm(person: p) } }
        .task {
            // A mention in a closed day's note counts as contact
            for var p in store.all(Person.self) where p.keepInTouch {
                if let d = store.days.values.filter({ $0.note.localizedCaseInsensitiveContains(p.name) }).map(\.date).max(), d > (p.lastContact ?? "") { p.lastContact = d; store.save(p) }
            }
        }
    }
}

struct PersonForm: View {
    @EnvironmentObject var store: Store
    @State var person: Person
    @State private var gift = ""
    @State private var note = ""
    var body: some View {
        Form {
            TextField("Name", text: $person.name)
            Toggle("Keep in touch", isOn: $person.keepInTouch)
            if person.keepInTouch { Stepper("Every \(person.everyWeeks) weeks", value: $person.everyWeeks, in: 1...26) }
            Toggle("Birthday", isOn: Binding(get: { person.birthday != nil }, set: { person.birthday = $0 ? String(Day.today.dropFirst(5)) : nil }))
            if person.birthday != nil {
                DatePicker("On", selection: Binding(get: { Day.date("2000-" + (person.birthday ?? "01-01")) }, set: { person.birthday = String(Day.key($0).dropFirst(5)) }), displayedComponents: .date)
            }
            Section("Gift ideas") {
                ForEach(person.gifts, id: \.self) { Text($0) }.onDelete { person.gifts.remove(atOffsets: $0) }
                HStack { TextField("Idea", text: $gift); Button("Add") { person.gifts.append(gift); gift = "" }.disabled(gift.isEmpty) }
            }
            Section("Moments") {
                ForEach(person.notes, id: \.self) { Text($0).font(.footnote) }
                HStack { TextField("A note", text: $note); Button("Add") { person.notes.append("\(Day.today): \(note)"); note = ""; person.lastContact = Day.today }.disabled(note.isEmpty) }
            }
            Button("Save") { store.save(person) }.disabled(person.name.isEmpty)
        }
    }
}

struct LearningView: View {
    @EnvironmentObject var store: Store
    @State private var front = ""
    @State private var back = ""
    @State private var showBack = false
    @State private var skill = ""
    @State private var minutes = 15

    var body: some View {
        let due = store.dueCards()
        Screen(glow: Color(hex: 0x9BE27F)) {
            Card(tint: Color(hex: 0x9BE27F)) {
                Eyebrow(text: "Review · \(due.count) due", icon: "rectangle.stack.fill", color: Color(hex: 0x9BE27F))
                if let c = due.first {
                    Text(c.front).font(.system(size: 17, weight: .semibold))
                    if showBack {
                        Text(c.back).font(.system(size: 15)).foregroundStyle(Color.soft)
                        HStack {
                            ForEach([(1, "Again"), (2, "Hard"), (3, "Good"), (4, "Easy")], id: \.0) { g, name in SoftButton(title: name) { store.review(c, grade: g); showBack = false } }
                        }
                    } else { SoftButton(title: "Show answer") { showBack = true } }
                } else { Text("Nothing due. Spaced repetition brings each card back just before you'd forget it.").font(.system(size: 13)).foregroundStyle(Color.soft) }
                if (store.readiness()?.score ?? 70) < 50 { Text("Low readiness: a lighter set today.").font(.system(size: 11.5)).foregroundStyle(Color.faint) }
            }
            Card {
                Eyebrow(text: "New card", icon: "plus.rectangle")
                TextField("Question", text: $front)
                TextField("Answer", text: $back)
                HStack { SoftButton(title: "Add") { store.save(ReviewCard(front: front, back: back)); front = ""; back = "" }; SoftButton(title: "Quotes → cards") { store.quotesToCards() } }
            }
            Card {
                Eyebrow(text: "Daily skill minutes", icon: "music.note")
                HStack { TextField("Language, instrument…", text: $skill); Stepper("\(minutes)", value: $minutes, in: 5...180, step: 5).fixedSize() }
                SoftButton(title: "Log") { store.save(SkillLog(skill: skill, minutes: minutes)); skill = "" }
                let week = store.all(SkillLog.self).filter { Day.between($0.date, Day.today) < 7 }
                ForEach(Dictionary(grouping: week, by: \.skill).sorted { $0.key < $1.key }, id: \.key) { s, logs in
                    HStack { Text(s).font(.system(size: 14)); Spacer(); Text("\(logs.map(\.minutes).reduce(0, +)) min this week").font(.system(size: 12.5)).foregroundStyle(Color.soft) }
                }
            }
        }
        .navigationTitle("Learning")
        .navigationBarTitleDisplayMode(.inline)
    }
}
