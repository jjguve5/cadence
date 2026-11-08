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
                HStack { Eyebrow(text: "Frescura da casa", icon: "sparkles"); Spacer(); Button { editingChore = Chore(title: "") } label: { Image(systemName: "plus") }.tint(Color(hex: 0x8FA8FF)) }
                ForEach(store.all(Chore.self).sorted { $0.freshness < $1.freshness }) { c in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(c.title).font(.geist(14)); Spacer(); Text(c.daysSince.map { "\($0) d" } ?? "–").font(.geist(11.5)).foregroundStyle(Color.faint) }
                            Bar(progress: c.freshness, area: c.freshness < 0.2 ? .fuel : .water)
                        }
                        Button { var x = c; x.history.append(Day.today); store.save(x) } label: { Image(systemName: "checkmark.circle").font(.geist(20)).foregroundStyle(Color.mint) }.buttonStyle(.plain)
                    }
                    .onLongPressGesture { editingChore = c }
                }
                if (store.readiness()?.score ?? 70) < 50, !store.tidyQueue.isEmpty {
                    Text("Dia de pouca energia: só a arrumação de 10 minutos: \(store.tidyQueue.map(\.title).joined(separator: ", ")).").font(.geist(12.5)).foregroundStyle(Color.soft)
                }
            }
            Card(tint: .good) {
                HStack { Eyebrow(text: "Plantas", icon: "leaf.fill", color: .good); Spacer(); Button { editingPlant = Plant(name: "") } label: { Image(systemName: "plus") }.tint(.good) }
                ForEach(store.all(Plant.self)) { p in
                    let due = store.plantDue(p)
                    HStack {
                        Image(systemName: p.outdoor ? "sun.max" : "house").foregroundStyle(Color.soft).frame(width: 20)
                        Text(p.name).font(.geist(14))
                        Spacer()
                        Text(due.note).font(.geist(12)).foregroundStyle(due.due ? Color.warn : Color.faint)
                        Button { var x = p; x.watered = Day.today; store.save(x) } label: { Image(systemName: "drop.circle").font(.geist(20)).foregroundStyle(Color.water) }.buttonStyle(.plain)
                    }
                    .onLongPressGesture { editingPlant = p }
                }
            }
            Card {
                HStack { Eyebrow(text: "Documentos e consultas", icon: "doc.text.fill"); Spacer(); Button { editingDoc = DocumentItem(title: "", expires: Day.add(365, to: Day.today)) } label: { Image(systemName: "plus") }.tint(Color(hex: 0x8FA8FF)) }
                ForEach(store.all(DocumentItem.self).sorted { $0.expires < $1.expires }) { d in
                    Button { editingDoc = d } label: {
                        HStack {
                            Text(d.title).font(.geist(14))
                            Spacer()
                            let days = Day.between(Day.today, d.expires)
                            Chip(text: days < 0 ? "expirado" : "\(Day.date(d.expires).formatted(.dateTime.day().month().year()))", color: days <= d.leadDays ? .warn : .soft)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(store.documentWarnings(), id: \.self) { Text($0).font(.geist(12)).foregroundStyle(Color.warn) }
            }
        }
        .navigationTitle("Casa")
        .navigationBarTitleDisplayMode(.inline)
        .task { seed() }
        .sheet(item: $editingChore) { c in SimpleEditor(title: "Tarefa", onDelete: { store.remove(c) }) { ChoreForm(chore: c) } }
        .sheet(item: $editingPlant) { p in SimpleEditor(title: "Planta", onDelete: { store.remove(p) }) { PlantForm(plant: p) } }
        .sheet(item: $editingDoc) { d in SimpleEditor(title: "Documento", onDelete: { store.remove(d) }) { DocForm(doc: d) } }
    }

    private func seed() {
        guard store.all(Chore.self).isEmpty else { return }
        for (t, r, e, m) in [("Aspirar", "Casa", 7, 20), ("Limpar a casa de banho", "Casa de banho", 7, 20), ("Mudar os lençóis", "Quarto", 14, 10), ("Bancadas da cozinha", "Cozinha", 3, 10), ("Levar a reciclagem", "Cozinha", 4, 5), ("Limpar o frigorífico", "Cozinha", 14, 10)] {
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
                    ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                    ToolbarItem(placement: .destructiveAction) { Button("Apagar", role: .destructive) { onDelete(); dismiss() } }
                }
        }
    }
}

struct ChoreForm: View {
    @EnvironmentObject var store: Store
    @State var chore: Chore
    var body: some View {
        Form {
            TextField("Tarefa", text: $chore.title)
            TextField("Divisão", text: $chore.room)
            Stepper("A cada \(chore.everyDays) dias", value: $chore.everyDays, in: 1...90)
            Stepper("Cerca de \(chore.minutes) min", value: $chore.minutes, in: 5...120, step: 5)
            Button("Guardar") { store.save(chore) }.disabled(chore.title.isEmpty)
        }
    }
}

struct PlantForm: View {
    @EnvironmentObject var store: Store
    @State var plant: Plant
    var body: some View {
        Form {
            TextField("Planta", text: $plant.name)
            Picker("Vive", selection: $plant.outdoor) { Text("Interior").tag(false); Text("Exterior").tag(true) }.pickerStyle(.segmented)
            Stepper("Regar a cada \(plant.everyDays) dias", value: $plant.everyDays, in: 1...30)
            Text(plant.outdoor ? "As plantas de exterior contam a chuva como rega e precisam de mais com calor." : "As plantas de interior ignoram o tempo.").font(.footnote).foregroundStyle(Color.soft)
            Button("Guardar") { store.save(plant) }.disabled(plant.name.isEmpty)
        }
    }
}

struct DocForm: View {
    @EnvironmentObject var store: Store
    @State var doc: DocumentItem
    var body: some View {
        Form {
            TextField("Passaporte, cartão de cidadão, carta de condução, IPO…", text: $doc.title)
            Picker("Tipo", selection: $doc.kind) { Text("Documento").tag("document"); Text("Consulta").tag("checkup"); Text("Garantia").tag("warranty"); Text("Carro").tag("car") }
            DatePicker("Expira / prazo", selection: Binding(get: { Day.date(doc.expires) }, set: { doc.expires = Day.key($0) }), displayedComponents: .date)
            Stepper("Avisar \(doc.leadDays) dias antes", value: $doc.leadDays, in: 7...365, step: 7)
            TextField("Notas", text: $doc.notes)
            Button("Guardar") { store.save(doc) }.disabled(doc.title.isEmpty)
        }
    }
}

struct PeopleView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Person?
    @State private var sayingTo: Person?
    var body: some View {
        Screen(glow: Color(hex: 0xFF9FBF)) {
            let soon = store.birthdaysSoon
            if !soon.isEmpty {
                Card(tint: Color(hex: 0xFF9FBF)) {
                    Eyebrow(text: "Aniversários em breve", icon: "gift.fill", color: Color(hex: 0xFF9FBF))
                    ForEach(soon, id: \.name) { b in
                        HStack {
                            Text(b.name).font(.geist(14, .medium))
                            Spacer()
                            Text(Day.date(b.date).formatted(.dateTime.weekday(.abbreviated).day().month())).font(.geist(12.5)).foregroundStyle(Color.soft)
                        }
                        if let gifts = b.person?.gifts, !gifts.isEmpty { Text("Ideias: " + gifts.joined(separator: ", ")).font(.geist(12)).foregroundStyle(Color.soft) }
                    }
                }
            }
            let due = store.keepInTouchDue
            if !due.isEmpty {
                Card {
                    Eyebrow(text: "Já passou algum tempo", icon: "bubble.left.and.bubble.right.fill")
                    ForEach(due) { p in
                        HStack {
                            Text(p.name).font(.geist(14))
                            Spacer()
                            Button("O que dizer") { sayingTo = p }.font(.geist(12.5, .semibold)).tint(Color(hex: 0xFF9FBF)).accessibilityIdentifier("friend.open")
                            Button("Falámos hoje") { var x = p; x.lastContact = Day.today; store.save(x) }.font(.geist(12.5, .semibold)).tint(Color(hex: 0xFF9FBF))
                        }
                    }
                }
            }
            Card {
                HStack { Eyebrow(text: "Pessoas", icon: "person.2.fill"); Spacer(); Button { editing = Person(name: "") } label: { Image(systemName: "plus") }.tint(Color(hex: 0xFF9FBF)) }
                ForEach(store.all(Person.self).sorted { $0.name < $1.name }) { p in
                    HStack(spacing: 12) {
                        Button { editing = p } label: {
                            HStack {
                                Text(p.name).font(.geist(14))
                                Spacer()
                                if p.keepInTouch { Text("a cada \(p.everyWeeks) sem.").font(.geist(11.5)).foregroundStyle(Color.faint) }
                            }
                        }
                        .buttonStyle(.plain)
                        Button { sayingTo = p } label: { Image(systemName: "text.bubble") }.tint(Color(hex: 0xFF9FBF)).accessibilityLabel("O que dizer a \(p.name)")
                    }
                }
                Text("Manter contacto fica desligado até o ativares para uma pessoa. Mencionar alguém na nota de um dia conta como contacto.").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
        }
        .navigationTitle("Pessoas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { p in SimpleEditor(title: p.name.isEmpty ? "Nova pessoa" : p.name, onDelete: { store.remove(p); store.put(FriendMessages.recordType, p.id, nil) }) { PersonForm(person: p) } }
        .sheet(item: $sayingTo) { p in FriendSuggestionsSheet(person: p) }
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
            TextField("Nome", text: $person.name)
            Toggle("Manter contacto", isOn: $person.keepInTouch)
            if person.keepInTouch { Stepper("A cada \(person.everyWeeks) semanas", value: $person.everyWeeks, in: 1...26) }
            Toggle("Aniversário", isOn: Binding(get: { person.birthday != nil }, set: { person.birthday = $0 ? String(Day.today.dropFirst(5)) : nil }))
            if person.birthday != nil {
                DatePicker("Dia", selection: Binding(get: { Day.date("2000-" + (person.birthday ?? "01-01")) }, set: { person.birthday = String(Day.key($0).dropFirst(5)) }), displayedComponents: .date)
            }
            Section("Ideias de presentes") {
                ForEach(person.gifts, id: \.self) { Text($0) }.onDelete { person.gifts.remove(atOffsets: $0) }
                HStack { TextField("Ideia", text: $gift); Button("Adicionar") { person.gifts.append(gift); gift = "" }.disabled(gift.isEmpty) }
            }
            Section("Momentos") {
                ForEach(person.notes, id: \.self) { Text($0).font(.footnote) }
                HStack { TextField("Uma nota", text: $note); Button("Adicionar") { person.notes.append("\(Day.today): \(note)"); note = ""; person.lastContact = Day.today }.disabled(note.isEmpty) }
            }
            Button("Guardar") { store.save(person) }.disabled(person.name.isEmpty)
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
                Eyebrow(text: "Rever · \(due.count) para hoje", icon: "rectangle.stack.fill", color: Color(hex: 0x9BE27F))
                if let c = due.first {
                    Text(c.front).font(.geist(17, .semibold))
                    if showBack {
                        Text(c.back).font(.geist(15)).foregroundStyle(Color.soft)
                        HStack {
                            ForEach([(1, "Outra vez"), (2, "Difícil"), (3, "Bem"), (4, "Fácil")], id: \.0) { g, name in SoftButton(title: name) { store.review(c, grade: g); showBack = false } }
                        }
                    } else { SoftButton(title: "Mostrar resposta") { showBack = true } }
                } else { Text("Nada para rever. A repetição espaçada traz cada cartão de volta mesmo antes de o esqueceres.").font(.geist(13)).foregroundStyle(Color.soft) }
                if (store.readiness()?.score ?? 70) < 50 { Text("Prontidão baixa: um conjunto mais leve hoje.").font(.geist(11.5)).foregroundStyle(Color.faint) }
            }
            Card {
                Eyebrow(text: "Novo cartão", icon: "plus.rectangle")
                TextField("Pergunta", text: $front)
                TextField("Resposta", text: $back)
                HStack { SoftButton(title: "Adicionar") { store.save(ReviewCard(front: front, back: back)); front = ""; back = "" }; SoftButton(title: "Citações → cartões") { store.quotesToCards() } }
            }
            Card {
                Eyebrow(text: "Minutos diários de prática", icon: "music.note")
                HStack { TextField("Língua, instrumento…", text: $skill); Stepper("\(minutes)", value: $minutes, in: 5...180, step: 5).fixedSize() }
                SoftButton(title: "Registar") { store.save(SkillLog(skill: skill, minutes: minutes)); skill = "" }
                let week = store.all(SkillLog.self).filter { Day.between($0.date, Day.today) < 7 }
                ForEach(Dictionary(grouping: week, by: \.skill).sorted { $0.key < $1.key }, id: \.key) { s, logs in
                    HStack { Text(s).font(.geist(14)); Spacer(); Text("\(logs.map(\.minutes).reduce(0, +)) min esta semana").font(.geist(12.5)).foregroundStyle(Color.soft) }
                }
            }
        }
        .navigationTitle("Aprendizagem")
        .navigationBarTitleDisplayMode(.inline)
    }
}
