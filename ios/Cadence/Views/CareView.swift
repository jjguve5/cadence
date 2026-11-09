// Hygiene (brushing mode, showers, grooming freshness, the routine player) and Care (medicines and products).
import AVFoundation
import AudioToolbox
import SwiftUI

struct CareView: View {
    @EnvironmentObject var store: Store
    @State private var editingMed: Medicine?

    var body: some View {
        Screen(glow: Color(hex: 0x5FE3D0)) {
            MedicinesCard(editing: $editingMed)
        }
        .navigationTitle("Medicamentos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingMed) { MedicineEditor(med: $0) }
    }
}

/// Higiene (design v17, N_Higiene): the routine of the moment and what's pending first; frequencies, evolution, all the
/// routines and your products one level below
struct HygieneView: View {
    @EnvironmentObject var store: Store
    @State private var playing: CareRoutine?
    @State private var newProduct: CareProduct?

    var body: some View {
        NavigationStack {
        Screen(glow: Color(hex: 0x5FE3D0)) {
            // <name>.screen: how the UI tests know this tab's root is showing. Internal, never translated; if a redesign removes this title, the identifier moves to the new one
            Title(eyebrow: store.tick.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Higiene").accessibilityIdentifier("hygiene.screen").padding(.top, 8)
            RoutineNowCard { playing = $0 }
            NextUpCard()
            GlassesSuggestionCard()
            ShowerCard()
            Card(tint: Color(hex: 0x5FE3D0)) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Escovagem", icon: "mouth.fill", color: Color(hex: 0x5FE3D0))
                        let today = store.brushes()
                        Text(today.isEmpty ? "Hoje ainda não" : "\(today.count)× hoje · \(today.map { duration($0.seconds / 60) }.joined(separator: ", "))").font(.geist(14))
                        if store.brushHeadDue { Text("3 meses com esta cabeça de escova: está na altura de a trocar.").font(.geist(12)).foregroundStyle(Color.warn) }
                    }
                    Spacer()
                    Button { store.brushingOpen = true } label: { Image(systemName: "play.fill").foregroundStyle(Color(hex: 0x032018)).frame(width: 44, height: 44).background(Circle().fill(Color(hex: 0x5FE3D0))) }
                }
                if store.brushHeadDue { SoftButton(title: "Já troquei", icon: "checkmark") { store.put("brushhead", Day.today, .bool(true)) } }
            }
            HygieneMoreCard { newProduct = CareProduct(name: "") }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { store.seedCare() }
        .fullScreenCover(item: $playing) { RoutinePlayer(routine: $0).environmentObject(store) }
        .sheet(item: $newProduct) { ProductEditor(product: $0).environmentObject(store) }
        }
    }
}

/// «Agora»: the routine of the moment and its steps. You confirm them, one at a time or all at once, always with
/// Desfazer; tapping a confirmed step takes it back («Não fiz»). Nothing is marked because the hour passed: what you
/// don't confirm stays pending.
struct RoutineNowCard: View {
    @EnvironmentObject var store: Store
    var play: (CareRoutine) -> Void

    var body: some View {
        let routines = store.routinesOfTheMoment()
        if let r = routines.first(where: { !store.pendingSteps($0).isEmpty }) ?? routines.first {
            let done = store.doneSteps(r)
            let pending = r.steps.filter { done[$0.id] == nil }
            Card(tint: Color(hex: 0x5FE3D0)) {
                HStack(spacing: 8) {
                    Eyebrow(text: "Agora · \(CareRules.moment(at: Clock.minute()).label)", color: .mint)
                    Spacer()
                    if pending.isEmpty {
                        StateTag(state: .done, text: "Feita").accessibilityIdentifier("hygiene.now.done")
                    } else {
                        StateTag(state: .pending, text: "\(pending.count) por confirmar").accessibilityIdentifier("hygiene.now.pending")
                    }
                }
                Text(r.title).font(.geist(17, .semibold))
                ForEach(r.steps) { s in
                    stepRow(s, of: r, at: done[s.id])
                }
                if !pending.isEmpty {
                    let name: String = r.title.prefix(1).lowercased() + String(r.title.dropFirst())
                    PrimaryButton(title: "Começar " + name) {
                        var left = r
                        left.steps = pending // the player goes through what's still to do
                        play(left)
                    }
                    .accessibilityIdentifier("hygiene.start")
                    if pending.count >= 2 {
                        Button { confirm(pending, of: r) } label: {
                            Text(pending.count == 2 ? "Já fiz os dois" : "Já fiz os \(pending.count)").font(.geist(13.5, .semibold)).foregroundStyle(Color.ink)
                                .padding(.horizontal, 18).frame(minHeight: 44)
                                .background(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(Pressable())
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("hygiene.batch")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hygiene.now")
        }
    }

    private func stepRow(_ s: RoutineStep, of r: CareRoutine, at time: Double?) -> some View {
        let product = s.productId.flatMap { store.record(CareProduct.self, $0) }
        let sub = time.map { "feito às \(clock(Day.minuteOfDay(Date(timeIntervalSince1970: $0 / 1000))))" } ?? product?.name ?? CareRules.stepLength(s.seconds)
        return Button { toggle(s, of: r, done: time != nil) } label: {
            HStack(spacing: 10) {
                Image(systemName: time != nil ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(time != nil ? Color.good : Color.soft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(.geist(14)).foregroundStyle(Color.ink)
                    Text(sub).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s.title), \(time != nil ? sub : "por confirmar")")
        .accessibilityHint(time != nil ? "Toca se não o fizeste" : "Toca para confirmar")
        .accessibilityIdentifier("hygiene.step.\(s.id)")
    }

    private func confirm(_ steps: [RoutineStep], of r: CareRoutine) {
        let s: Store = store, day = Day.today, now = nowMs()
        var times: [String: Double] = [:]
        for step in steps { times[step.id] = now }
        let before = s.confirmSteps(times, of: r, on: day)
        UndoCenter.shared.show(steps.count == 1 ? "1 passo concluído" : "\(steps.count) passos concluídos") { s.restoreRoutineLog(before, routine: r, on: day) }
    }

    private func toggle(_ step: RoutineStep, of r: CareRoutine, done: Bool) {
        guard done else { return confirm([step], of: r) }
        let s: Store = store, day = Day.today
        let before = s.unconfirmStep(step.id, of: r, on: day)
        UndoCenter.shared.show("Desmarcado: \(step.title)") { s.restoreRoutineLog(before, routine: r, on: day) }
    }
}

/// A cloth takes off the dust, not the grease that builds up: a proper wash every so often. A suggestion until you accept
/// it (decision D41); once it's yours it is one more item in Frequências, with its own interval
struct GlassesSuggestionCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var hidden = CareSuggestionsHidden.shared
    @State private var editing: GroomingEdit?

    private var alreadyThere: Bool {
        store.all(GroomingItem.self).contains { $0.title.folding(options: .diacriticInsensitive, locale: nil).lowercased().contains("oculos") }
    }

    var body: some View {
        if !alreadyThere && !hidden.isHidden("glasses", for: "7") {
            Card(state: .suggested) {
                HStack { Eyebrow(text: "Sugestão"); Spacer(); StateTag(state: .suggested) }
                Text("Lavar os óculos a cada 7 dias").font(.geist(15, .semibold))
                WhyLine(text: "o pano tira o pó, mas a gordura vai ficando. Água morna e um pouco de detergente suave resolvem.")
                DecisionButtons(onAccept: { accept() },
                                onAdjust: { editing = GroomingEdit(item: GroomingItem(title: "Lavar os óculos", icon: "eyeglasses", interval: 7), interval: 7) },
                                onIgnore: { hidden.hide("glasses", for: "7") })
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hygiene.glasses")
            .sheet(item: $editing) { e in GroomingEditor(item: e.item, interval: e.interval).environmentObject(store) }
        }
    }

    private func accept() {
        let glasses = GroomingItem(title: "Lavar os óculos", icon: "eyeglasses", interval: 7)
        store.save(glasses)
        UndoCenter.shared.show("Lavar os óculos · adicionado") { store.remove(glasses) }
    }
}

/// «A seguir»: the care that's due today or tomorrow. Concluído starts its interval again from today, with Desfazer.
struct NextUpCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let soon = store.groomingSoon
        let trip: Trip? = store.nextTrip.flatMap { t -> Trip? in store.groomingBefore(t).isEmpty ? nil : t }
        if !soon.isEmpty || trip != nil {
            Card {
                Eyebrow(text: "A seguir")
                ForEach(soon) { g in
                    HStack(spacing: 10) {
                        Image(systemName: g.icon).foregroundStyle(Color.soft).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.title).font(.geist(14, .medium))
                            Text([CareRules.sinceText(g, today: Day.today), CareRules.frequencyText(g)].compactMap { $0 }.joined(separator: " · ")).font(.geist(12)).foregroundStyle(Color.soft)
                        }
                        Spacer(minLength: 6)
                        CareSoftButton(title: "Concluído", icon: "checkmark") { done(g) }
                            .accessibilityLabel("Concluído: \(g.title)")
                            .accessibilityIdentifier("hygiene.groom.\(g.id).done")
                    }
                }
                if let trip {
                    Text("Viagem a \(trip.destination), \(Day.date(trip.start).formatted(.dateTime.weekday(.wide))): \(store.groomingBefore(trip).map { $0.title.lowercased() }.joined(separator: ", ")) na véspera.").font(.geist(12.5)).foregroundStyle(Color.fuel)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hygiene.next")
        }
    }

    private func done(_ g: GroomingItem) {
        let s: Store = store
        guard let before = s.markGroomingDone(g) else { return }
        UndoCenter.shared.show("\(g.title): concluído hoje") { s.save(before) }
    }
}

/// The level below: all the routines, frequencies and evolution, and your products
struct HygieneMoreCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var hidden = CareSuggestionsHidden.shared
    var addProduct: () -> Void

    var body: some View {
        let routines = store.all(CareRoutine.self).sorted { $0.title < $1.title }
        let grooming = store.all(GroomingItem.self).sorted { ($0.rhythm, $0.title) < ($1.rhythm, $1.title) }
        let suggestions = grooming.filter { g in g.suggestedInterval.map { !hidden.isHidden("interval.\(g.id)", for: "\($0)") } ?? false }.count
        let products = store.all(CareProduct.self).sorted { $0.name < $1.name }
        Card {
            NavigationLink { RoutinesList() } label: {
                CareLinkRow(title: "Todas as rotinas", sub: routines.isEmpty ? "ainda nenhuma" : routines.map { $0.title.lowercased() }.joined(separator: " · ")) { EmptyView() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hygiene.routines")
            Divider()
            NavigationLink { CareDetailsView() } label: {
                CareLinkRow(title: "Frequências e evolução", sub: (["duche"] + grooming.map { $0.title.lowercased() } + ["fio dentário"]).joined(separator: ", ")) {
                    if suggestions > 0 { StateTag(state: .suggested, text: suggestions == 1 ? "1 sugestão" : "\(suggestions) sugestões") }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hygiene.details")
            ForEach(products) { p in
                Divider()
                NavigationLink { CareProductView(productId: p.id) } label: {
                    CareLinkRow(title: p.name, sub: "teu · " + (store.productMoments(p).isEmpty ? "ainda em nenhuma rotina" : store.productMoments(p).lowercased())) { EmptyView() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hygiene.product.\(p.id)")
            }
            Divider()
            Button(action: addProduct) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                    Text("Adicionar produto").font(.geist(14, .medium))
                    Spacer()
                }
                .foregroundStyle(Color.mint)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hygiene.product.add")
        }
    }
}

/// A row that opens a detail, as in the design's lists: the title, a short line under it, a state, then ›
struct CareLinkRow<Trailing: View>: View {
    var title: String
    var sub: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.geist(14, .medium)).foregroundStyle(Color.ink)
                if !sub.isEmpty { Text(sub).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(2) }
            }
            Spacer(minLength: 8)
            trailing
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.faint)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct MedicinesCard: View {
    @EnvironmentObject var store: Store
    @Binding var editing: Medicine?
    var body: some View {
        Card(tint: .mind) {
            HStack { Eyebrow(text: "Medicamentos e produtos", icon: "pills.fill", color: .mind); Spacer(); Button { editing = Medicine(name: "") } label: { Image(systemName: "plus") }.tint(.mind) }
            let doses = store.doses()
            if doses.isEmpty { Text("Nada marcado para hoje.").font(.geist(13)).foregroundStyle(Color.soft) }
            ForEach(Array(doses.enumerated()), id: \.offset) { _, d in
                HStack {
                    Text(clock(d.minute)).font(.mono(12)).foregroundStyle(Color.faint)
                    VStack(alignment: .leading) {
                        Text(d.med.name).font(.geist(14, .medium))
                        Text([d.med.dose, d.med.how].filter { !$0.isEmpty }.joined(separator: " · ")).font(.geist(11.5)).foregroundStyle(Color.soft)
                    }
                    Spacer()
                    if let log = d.log { Chip(text: log.taken ? "tomado" : "saltado", color: log.taken ? .good : .faint) }
                    else {
                        Button("Saltar") { store.take(d.med, minute: d.minute, taken: false) }.font(.geist(12)).tint(.soft)
                        Button { store.take(d.med, minute: d.minute) } label: { Image(systemName: "checkmark.circle.fill").font(.geist(22)).foregroundStyle(Color.mind) }.buttonStyle(.plain)
                    }
                }
            }
            ForEach(store.all(Medicine.self)) { m in
                if let left = store.dosesLeft(m), Double(left.doses) <= m.refillAt {
                    MedicineRefillLine(med: m, doses: left.doses, runsOut: left.runsOut)
                }
            }
            NavigationLink { MedicinesList(editing: $editing) } label: { Text("Todos os produtos e histórico").font(.geist(13, .semibold)).foregroundStyle(Color.mind) }
        }
    }
}

/// A medicine running low. It says it's on the shopping list only when it is (phase 2.5: before, it said "added" and
/// saved nothing); otherwise «Adicionar às compras» saves a real item, with Desfazer.
struct MedicineRefillLine: View {
    @EnvironmentObject var store: Store
    var med: Medicine
    var doses: Int
    var runsOut: String

    var body: some View {
        let onList = store.isOnShoppingList(med.name)
        let left = doses == 1 ? "resta 1 dose" : "restam \(doses) doses"
        VStack(alignment: .leading, spacing: 4) {
            Text("\(med.name): \(left), acaba a \(Day.date(runsOut).formatted(.dateTime.day().month())).").font(.geist(12)).foregroundStyle(Color.warn)
            if onList {
                StateTag(state: .pending, text: "Na lista de compras")
            } else {
                CareSoftButton(title: "Adicionar às compras", icon: "cart.badge.plus") {
                    let s: Store = store
                    if let item = s.addToShopping(name: med.name, reason: left, source: "Medicamentos") {
                        UndoCenter.shared.show("Adicionado às compras: \(item.name)") { s.remove(item) }
                    }
                }
            }
        }
    }
}

struct MedicinesList: View {
    @EnvironmentObject var store: Store
    @Binding var editing: Medicine?
    var body: some View {
        List {
            ForEach(store.all(Medicine.self).sorted { $0.name < $1.name }) { m in
                Button { editing = m } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).foregroundStyle(Color.ink)
                        Text("\(m.times.map(clock).joined(separator: ", ")) · \(m.schedule.summary)" + (m.end.map { " · até \(Day.date($0).formatted(.dateTime.day().month()))" } ?? " · contínuo")).font(.caption).foregroundStyle(Color.soft)
                        if let a = store.adherence(m) { Text("Tomado em \(Int(a * 100))% dos últimos 30 dias").font(.caption2).foregroundStyle(a > 0.9 ? Color.good : Color.warn) }
                    }
                }
            }
            Section {
                ShareLink(item: medicineCSV(), preview: SharePreview("Histórico de medicamentos")) { Label("Exportar o histórico para o médico", systemImage: "square.and.arrow.up") }
            }
        }
        .cadenceList()
        .navigationTitle("Medicamentos")
    }

    private func medicineCSV() -> String {
        var rows = ["data,hora,produto,dose,tomado"]
        for log in store.all(MedLog.self).sorted(by: { ($0.date, $0.minute) < ($1.date, $1.minute) }) {
            let m = store.record(Medicine.self, log.medId)
            rows.append("\(log.date),\(clock(log.minute)),\(m?.name ?? "?"),\(m?.dose ?? ""),\(log.taken ? "sim" : "não")")
        }
        return rows.joined(separator: "\n")
    }
}

struct MedicineEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var med: Medicine
    @State private var newTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $med.name)
                    Picker("Tipo", selection: $med.kind) { ForEach(["medicine", "supplement", "skincare", "drops", "other"], id: \.self) { Text(medicineKindLabel($0)).tag($0) } }
                    TextField("Dose (ex.: 1 comprimido, 2 gotas)", text: $med.dose)
                    TextField("Como (com comida, em jejum…)", text: $med.how)
                    Toggle("Essencial (pergunta outra vez até responderes)", isOn: $med.mustDo)
                }
                Section("Horários") {
                    ForEach(med.times.sorted(), id: \.self) { t in Text(clock(t)).swipeActions { Button("Remover", role: .destructive) { med.times.removeAll { $0 == t } } } }
                    HStack { DatePicker("Adicionar", selection: $newTime, displayedComponents: .hourAndMinute); Button("Adicionar") { let m = Day.minuteOfDay(newTime); if !med.times.contains(m) { med.times.append(m) } } }
                }
                Section("Frequência") {
                    Picker("Repete", selection: $med.schedule.rule) { ForEach(Schedule.Rule.allCases, id: \.self) { Text($0.label).tag($0) } }
                    if med.schedule.rule == .everyNDays { Stepper("A cada \(ptCount(med.schedule.every, "dia", "dias"))", value: $med.schedule.every, in: 1...60) }
                    if med.schedule.rule == .weekdays {
                        HStack {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                                let on = med.schedule.weekdays.contains(wd)
                                Text(["D", "S", "T", "Q", "Q", "S", "S"][wd - 1]).frame(width: 32, height: 32).background(Circle().fill(on ? Color.mind : .white.opacity(0.08)))
                                    .onTapGesture { if on { med.schedule.weekdays.removeAll { $0 == wd } } else { med.schedule.weekdays.append(wd) } }
                            }
                        }
                    }
                    DatePicker("Começa", selection: Binding(get: { Day.date(med.start) }, set: { med.start = Day.key($0) }), displayedComponents: .date)
                    Toggle("Tratamento temporário", isOn: Binding(get: { med.end != nil }, set: { med.end = $0 ? Day.add(7, to: med.start) : nil }))
                    if med.end != nil { DatePicker("Acaba", selection: Binding(get: { Day.date(med.end ?? Day.today) }, set: { med.end = Day.key($0) }), displayedComponents: .date) }
                }
                Section("Stock") {
                    TextField("Unidades restantes (opcional)", value: $med.stock, format: .number).keyboardType(.decimalPad)
                    Stepper("\(kg(med.perDose)) por dose", value: $med.perDose, in: 0.5...10, step: 0.5)
                    Stepper(Int(med.refillAt) == 1 ? "Avisar quando restar 1 dose" : "Avisar quando restarem \(Int(med.refillAt)) doses", value: $med.refillAt, in: 1...60)
                }
                if store.record(Medicine.self, med.id) != nil { Button("Apagar", role: .destructive) { store.remove(med); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(med.name.isEmpty ? "Novo produto" : med.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { med.times.sort(); store.save(med); Reminders.shared.reschedule(); dismiss() }.disabled(med.name.isEmpty || med.times.isEmpty) }
            }
        }
    }
}

struct RoutineEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var routine: CareRoutine
    @State private var newProduct: CareProduct?

    var body: some View {
        let products = store.all(CareProduct.self).sorted { $0.name < $1.name }
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $routine.title)
                    // Phase 2.5: the routine's own time decides whether it counts for the morning or the night
                    Toggle("Hora própria", isOn: Binding(get: { routine.minute != nil }, set: { routine.minute = $0 ? (routine.minute ?? 8 * 60) : nil }))
                    if let m = routine.minute {
                        DatePicker("Hora", selection: Binding(get: { Day.at(m, on: Day.today) }, set: { routine.minute = Day.minuteOfDay($0) }), displayedComponents: .hourAndMinute)
                    }
                    Text(momentNote).font(.geist(12)).foregroundStyle(Color.soft)
                }
                Section("Passos") {
                    ForEach($routine.steps) { $s in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { TextField("Passo", text: $s.title); Stepper("\(s.seconds) s", value: $s.seconds, in: 5...900, step: 5).fixedSize() }
                            if !products.isEmpty {
                                Picker("Produto", selection: $s.productId) {
                                    Text("Nenhum").tag(String?.none)
                                    ForEach(products) { p in Text(p.name).tag(String?.some(p.id)) }
                                }
                            }
                        }
                    }
                    .onDelete { routine.steps.remove(atOffsets: $0) }
                    .onMove { routine.steps.move(fromOffsets: $0, toOffset: $1) }
                    Button("Adicionar passo") { routine.steps.append(RoutineStep(title: "", seconds: 30)) }
                    Button("Novo produto") { newProduct = CareProduct(name: "") }
                }
                if store.record(CareRoutine.self, routine.id) != nil { Button("Apagar rotina", role: .destructive) { store.remove(routine); dismiss() } }
            }
            .sheet(item: $newProduct) { ProductEditor(product: $0).environmentObject(store) }
            .cadenceList()
            .navigationTitle(routine.title.isEmpty ? "Nova rotina" : routine.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(routine); dismiss() }.disabled(routine.title.isEmpty) }
            }
        }
    }

    /// Which half of the day the routine counts for, as it stands
    private var momentNote: String {
        switch CareRules.moment(of: routine) {
        case .morning?: return "Conta para a manhã (até às 14:00)."
        case .night?: return "Conta para a noite (a partir das 14:00)."
        case nil: return "Ainda sem momento. Para aparecer em «Agora», dá-lhe uma hora própria ou põe «manhã» ou «noite» no nome."
        }
    }
}

/// One step of brushing: which teeth, which surface, how long, and how
struct BrushStep {
    var area: String // upper-right, upper-front, upper-left, lower-left, lower-front, lower-right, upper, lower, all
    var surface: String // outer, inner, chewing, all
    var seconds: Double
    var title: String
    var tip: String
}

enum BrushPlan: String, CaseIterable {
    case sextants, thorough, quadrants
    var label: String { ["sextants": "6 zonas · 2 min", "thorough": "12 passos · 2 min", "quadrants": "4 zonas · 2 min"][rawValue]! }

    var steps: [BrushStep] {
        let outer = "Cerdas a 45° da linha da gengiva, pequenos círculos suaves."
        let inner = "Inclina a escova, movimentos curtos ao longo das gengivas."
        let chew = "Para a frente e para trás nas superfícies de mastigação."
        switch self {
        case .quadrants:
            return [("upper-right", "Em cima à direita"), ("upper-left", "Em cima à esquerda"), ("lower-left", "Em baixo à esquerda"), ("lower-right", "Em baixo à direita")].map {
                BrushStep(area: $0.0, surface: "all", seconds: 30, title: $0.1, tip: "Por fora, por dentro e depois por cima. " + outer)
            }
        case .thorough:
            var out: [BrushStep] = []
            for (a, name) in [("upper-right", "Em cima à direita"), ("upper-left", "Em cima à esquerda"), ("lower-left", "Em baixo à esquerda"), ("lower-right", "Em baixo à direita")] {
                out.append(BrushStep(area: a, surface: "outer", seconds: 10, title: "\(name) · por fora", tip: outer))
                out.append(BrushStep(area: a, surface: "inner", seconds: 10, title: "\(name) · por dentro", tip: inner))
                out.append(BrushStep(area: a, surface: "chewing", seconds: 10, title: "\(name) · por cima", tip: chew))
            }
            return out
        case .sextants:
            return [("upper-right", "Em cima à direita"), ("upper-front", "Em cima à frente"), ("upper-left", "Em cima à esquerda"), ("lower-left", "Em baixo à esquerda"), ("lower-front", "Em baixo à frente"), ("lower-right", "Em baixo à direita")].map {
                BrushStep(area: $0.0, surface: "all", seconds: 20, title: $0.1, tip: $0.0.hasSuffix("front") ? "Escova na vertical a parte de trás dos dentes da frente. " + outer : "Por fora, por dentro e depois por cima. " + outer)
            }
        }
    }
}

/// Brushing mode: a tooth chart that lights the teeth and the surface to brush now, a vibration and chime at
/// each switch, then floss and mouthwash
struct BrushingView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("brushPlan2") private var planName = BrushPlan.sextants.rawValue
    @AppStorage("brushStart") private var startedAt = 0.0 // survives the screen locking and the view being rebuilt
    @AppStorage("brushFloss") private var floss = false
    @AppStorage("brushMouthwash") private var mouthwash = false
    @State private var now = Date()
    @State private var lastStep = -1
    private var start: Date? { startedAt > 0 ? Date(timeIntervalSince1970: startedAt) : nil }
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private var plan: BrushPlan { BrushPlan(rawValue: planName) ?? .sextants }
    private var steps: [BrushStep] { plan.steps }
    private var total: Double { steps.map(\.seconds).reduce(0, +) }
    private var elapsed: Double { start.map { now.timeIntervalSince($0) } ?? 0 }
    private var finished: Bool { start != nil && elapsed >= total }
    private var index: Int {
        var t = 0.0
        for (i, s) in steps.enumerated() { t += s.seconds; if elapsed < t { return i } }
        return steps.count - 1
    }
    private var stepLeft: Double {
        let end = steps.prefix(index + 1).map(\.seconds).reduce(0, +)
        return max(0, end - elapsed)
    }

    var body: some View {
        let step = start == nil || finished ? nil : steps[index]
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack { Spacer(); Button("Fechar") { clear(); dismiss() }.foregroundStyle(Color.soft) }
                Text(finished ? "Concluído" : step?.title ?? "Lavar os dentes").font(.geist(26, .bold))
                ToothChart(area: step?.area, surface: step?.surface, sextants: plan == .sextants).frame(maxHeight: 340)
                if let step {
                    Text(step.tip).font(.geist(14)).foregroundStyle(Color.soft).multilineTextAlignment(.center).frame(minHeight: 40)
                    HStack(spacing: 4) {
                        ForEach(steps.indices, id: \.self) { i in
                            Capsule().fill(i < index ? Color(hex: 0x5FE3D0) : i == index ? Color.ink : Color.white.opacity(0.12)).frame(height: 5)
                        }
                    }
                }
                Text(start == nil ? timeText(total) : finished ? "0:00" : timeText(stepLeft) + "  ·  " + timeText(total - elapsed) + " em falta")
                    .font(.system(size: start == nil ? 44 : 22, weight: .medium, design: .monospaced))
                if start == nil {
                    Picker("", selection: $planName) { ForEach(BrushPlan.allCases, id: \.self) { Text($0.label).tag($0.rawValue) } }.pickerStyle(.segmented)
                    PrimaryButton(title: "Começar") { startedAt = Date().timeIntervalSince1970; now = Date() }
                } else if finished {
                    Toggle("Fio dentário", isOn: $floss).tint(.mint)
                    Toggle("Elixir", isOn: $mouthwash).tint(.mint)
                    PrimaryButton(title: "Guardar") {
                        store.saveBrushing(BrushLog(seconds: Int(total), floss: floss, mouthwash: mouthwash)) // answers the night's habit after midnight (Night.swift)
                        clear()
                        dismiss()
                    }
                }
            }
            .padding(22)
        }
        .onReceive(timer) { t in
            now = t
            guard start != nil else { return }
            let i = finished ? steps.count : index
            if i != lastStep {
                if lastStep >= 0 { UINotificationFeedbackGenerator().notificationOccurred(.success); AudioServicesPlaySystemSound(1057) }
                lastStep = i
            }
        }
        // awake from opening until saved or closed, so the last two questions don't get lost behind the lock screen
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; now = Date(); if !BrushingView.pending { clear() } }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func clear() { startedAt = 0; floss = false; mouthwash = false }

    /// A session that was started and never saved, recent enough to come back to
    static var pending: Bool {
        let t = UserDefaults.standard.double(forKey: "brushStart")
        return t > 0 && Date().timeIntervalSince1970 - t < 20 * 60
    }

    private func timeText(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// A dental chart drawn like the body map: 16 teeth per arch along a U-shaped curve, sized by type (molars,
/// premolars, canine, incisors), seen as in a mirror. The teeth to brush light up; the outer or inner side gets a band.
struct ToothChart: View {
    var area: String?
    var surface: String?
    var sextants = true

    // From the middle to the back: 2 incisors, canine, 2 premolars, 3 molars (width, depth relative to a molar)
    private static let types: [(w: CGFloat, d: CGFloat)] = [(0.72, 0.55), (0.6, 0.55), (0.66, 0.82), (0.74, 0.9), (0.74, 0.9), (1, 1.05), (1, 1.05), (1, 1.05)]
    private static let sweep = 92.0 * Double.pi / 180

    private struct Tooth { var center: CGPoint; var angle: Double; var w: CGFloat; var d: CGFloat; var upper: Bool; var right: Bool; var index: Int; var normal: CGVector }

    private func point(_ t: Double, _ size: CGSize, upper: Bool) -> CGPoint {
        let rx = size.width * 0.31, ry = size.height * 0.33
        let y0 = upper ? size.height * 0.07 : size.height * 0.93
        let y = ry * CGFloat(1 - cos(t))
        return CGPoint(x: rx * CGFloat(sin(t)), y: upper ? y0 + y : y0 - y)
    }

    private func teeth(in size: CGSize) -> ([Tooth], CGFloat) {
        var out: [Tooth] = []
        var unit: CGFloat = 0
        for upper in [true, false] {
            var table: [(Double, CGFloat)] = [(0, 0)]
            var length: CGFloat = 0
            var prev = point(0, size, upper: upper)
            for i in 1...400 {
                let t = Self.sweep * Double(i) / 400
                let p = point(t, size, upper: upper)
                length += hypot(p.x - prev.x, p.y - prev.y)
                table.append((t, length))
                prev = p
            }
            let gap: CGFloat = 0.06
            let widths = Self.types.map { $0.w }.reduce(0, +)
            unit = length / (widths + gap * CGFloat(Self.types.count))
            for right in [true, false] {
                var s = gap * unit / 2
                for (k, type) in Self.types.enumerated() {
                    let w = type.w * unit, d = type.d * unit
                    let c = s + w / 2
                    s += w + gap * unit
                    let t = table.first { $0.1 >= c }?.0 ?? Self.sweep
                    let p = point(t, size, upper: upper), q = point(t + 0.002, size, upper: upper)
                    let sx: CGFloat = right ? 1 : -1 // mirror view: your right is on the right
                    let dx = sx * (q.x - p.x), dy = q.y - p.y
                    let len = max(0.0001, hypot(dx, dy))
                    var normal = CGVector(dx: -dy / len, dy: dx / len)
                    let inside = CGPoint(x: size.width / 2, y: upper ? size.height * 0.3 : size.height * 0.7)
                    let center = CGPoint(x: size.width / 2 + sx * p.x, y: p.y)
                    if (center.x - inside.x) * normal.dx + (center.y - inside.y) * normal.dy < 0 { normal = CGVector(dx: -normal.dx, dy: -normal.dy) }
                    out.append(Tooth(center: center, angle: atan2(Double(dy), Double(dx)), w: w, d: d, upper: upper, right: right, index: k, normal: normal))
                }
            }
        }
        return (out, unit)
    }

    private func active(_ t: Tooth) -> Bool {
        guard let area else { return false }
        let front = t.index <= 2 // incisors and canine
        let side = !sextants || !front // in six zones the side zones stop before the canines
        switch area {
        case "all": return true
        case "upper-right": return t.upper && t.right && side
        case "upper-left": return t.upper && !t.right && side
        case "lower-left": return !t.upper && !t.right && side
        case "lower-right": return !t.upper && t.right && side
        case "upper-front": return t.upper && front
        case "lower-front": return !t.upper && front
        default: return false
        }
    }

    private func place(_ rect: CGRect, corner: CGFloat, _ t: Tooth, offset: CGFloat = 0) -> Path {
        Path(roundedRect: rect, cornerRadius: corner)
            .applying(CGAffineTransform(rotationAngle: CGFloat(t.angle)))
            .applying(CGAffineTransform(translationX: t.center.x + t.normal.dx * offset, y: t.center.y + t.normal.dy * offset))
    }

    var body: some View {
        Canvas { ctx, size in
            let (list, unit) = teeth(in: size)
            let mint = Color(hex: 0x5FE3D0)
            for upper in [true, false] {
                var gum = Path()
                let steps = 60
                for i in 0...(2 * steps) {
                    let f = Double(i - steps) / Double(steps)
                    let p = point(abs(f) * Self.sweep, size, upper: upper)
                    let pt = CGPoint(x: size.width / 2 + (f < 0 ? -p.x : p.x), y: p.y)
                    if i == 0 { gum.move(to: pt) } else { gum.addLine(to: pt) }
                }
                ctx.stroke(gum, with: .color(Color(hex: 0x6E2D3E)), style: StrokeStyle(lineWidth: unit * 1.4, lineCap: .round, lineJoin: .round))
            }
            let kinds = ["incisor", "incisor", "canine", "premolar", "premolar", "molar", "molar", "molar"]
            var images: [String: GraphicsContext.ResolvedImage] = [:]
            for k in Set(kinds) {
                images[k] = ctx.resolve(Image("tooth-\(k)"))
                images[k + "-on"] = ctx.resolve(Image("tooth-\(k)-on"))
            }
            for t in list {
                let on = active(t)
                let sideOnly = surface == "inner" || surface == "outer"
                let name = kinds[t.index] + (on ? "-on" : "")
                if let img = images[name] {
                    ctx.drawLayer { layer in
                        layer.translateBy(x: t.center.x, y: t.center.y)
                        layer.rotate(by: .radians(t.angle))
                        if on && sideOnly { layer.opacity = 0.75 }
                        layer.draw(img, in: CGRect(x: -t.w * 0.66, y: -t.d * 0.66, width: t.w * 1.32, height: t.d * 1.32))
                    }
                }
                if on, sideOnly {
                    let dir: CGFloat = surface == "outer" ? 1 : -1
                    let band = place(CGRect(x: -t.w / 2, y: -3, width: t.w, height: 6), corner: 3, t, offset: dir * (t.d / 2 + 5))
                    ctx.fill(band, with: .color(mint))
                }
            }
            ctx.draw(Text("tua direita").font(.geist(11)).foregroundColor(Color.faint), at: CGPoint(x: size.width - 36, y: size.height / 2))
            ctx.draw(Text("tua esquerda").font(.geist(11)).foregroundColor(Color.faint), at: CGPoint(x: 34, y: size.height / 2))
            ctx.draw(Text("em cima").font(.geist(11)).foregroundColor(Color.faint), at: CGPoint(x: size.width / 2, y: size.height * 0.24))
            ctx.draw(Text("em baixo").font(.geist(11)).foregroundColor(Color.faint), at: CGPoint(x: size.width / 2, y: size.height * 0.76))
        }
        .aspectRatio(360.0 / 420.0, contentMode: .fit)
    }
}

/// Step-by-step routine player: a timer per step, the next step spoken aloud, a projected done-by time. A step you go
/// through to the end (its timer, or «Feito») counts as done; «Saltar» leaves it pending. At the end what you did is
/// saved once, in the same record Higiene and Hoje show (phase 2.5: before, nothing was saved), with Desfazer.
struct RoutinePlayer: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var routine: CareRoutine
    @State private var playback: RoutinePlayback
    @State private var saved = false
    @State private var undone = false
    @ObservedObject private var undoCenter = UndoCenter.shared
    @State private var stepStart = Date()
    @State private var now = Date()
    @State private var paused: Date?
    @State private var speech = AVSpeechSynthesizer()
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(routine: CareRoutine) {
        self.routine = routine
        _playback = State(initialValue: RoutinePlayback(steps: routine.steps))
    }

    var body: some View {
        let step = playback.current
        let left = step.map { Double($0.seconds) - (paused ?? now).timeIntervalSince(stepStart) } ?? 0
        let remaining = routine.steps.dropFirst(playback.index + 1).map(\.seconds).reduce(0, +) + Int(max(0, left))
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack { Text(routine.title).font(.geist(15, .semibold)).foregroundStyle(Color.soft); Spacer(); Button("Fechar") { dismiss() }.foregroundStyle(Color.soft).frame(minHeight: 44) }
                Spacer()
                if let step {
                    Text("Passo \(playback.index + 1) de \(routine.steps.count)").font(.geist(13)).foregroundStyle(Color.soft)
                    Text(step.title).font(.geist(30, .bold)).multilineTextAlignment(.center)
                    ZStack {
                        Ring(progress: 1 - max(0, left) / Double(max(1, step.seconds)), area: .mint, width: 9)
                        Text(String(format: "%d:%02d", Int(max(0, left)) / 60, Int(max(0, left)) % 60)).font(.mono(36))
                    }
                    .frame(width: 200, height: 200)
                    Text("Termina às \(Date().addingTimeInterval(Double(remaining)).formatted(date: .omitted, time: .shortened))").font(.geist(13)).foregroundStyle(Color.soft)
                } else {
                    PipAnimation(mood: .celebrate).frame(width: 140, height: 140)
                    Text(playback.done.isEmpty ? "Rotina terminada" : "Rotina concluída").font(.geist(26, .bold)).accessibilityIdentifier("care.player.finished")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(routine.steps) { s in
                            HStack(spacing: 8) {
                                if let t = playback.done[s.id], !undone {
                                    StateTag(state: .done, text: "Feito · \(clock(Day.minuteOfDay(Date(timeIntervalSince1970: t / 1000))))")
                                } else {
                                    StateTag(state: .pending, text: "Por confirmar")
                                }
                                Text(s.title).font(.geist(14)).foregroundStyle(Color.ink)
                            }
                        }
                    }
                    Text(undone ? "Desfeito: nada ficou registado." : playback.done.isEmpty ? "Nada ficou registado: os passos saltados ficam por confirmar em Higiene." : "Ficou registado em Higiene. Os passos saltados ficam por confirmar.")
                        .font(.geist(12.5)).foregroundStyle(Color.soft).multilineTextAlignment(.center)
                    // Desfazer, here too: the bar at the bottom of the app is behind this screen
                    if saved && !undone && !playback.done.isEmpty && undoCenter.current != nil {
                        CareSoftButton(title: "Desfazer", icon: "arrow.uturn.backward") { undoCenter.undo(); undone = true }
                            .accessibilityIdentifier("care.player.undo")
                    }
                }
                Spacer()
                if step != nil {
                    PrimaryButton(title: "Feito") { next(done: true) }.accessibilityIdentifier("care.player.done")
                    HStack {
                        SoftButton(title: paused == nil ? "Pausa" : "Retomar") { if let p = paused { stepStart = stepStart.addingTimeInterval(Date().timeIntervalSince(p)); paused = nil } else { paused = Date() } }
                        SoftButton(title: "+30 s") { stepStart = stepStart.addingTimeInterval(30) }
                        SoftButton(title: "Saltar") { next(done: false) }.accessibilityIdentifier("care.player.skip")
                    }
                } else {
                    PrimaryButton(title: "Concluído") { dismiss() }.accessibilityIdentifier("care.player.close")
                }
            }
            .padding(24)
        }
        .onAppear { say(routine.steps.first?.title) }
        .onReceive(timer) { t in
            now = t
            if paused == nil, let current = playback.current, t.timeIntervalSince(stepStart) >= Double(current.seconds) { next(done: true) }
        }
    }

    /// The step is done (its timer ran out, or «Feito») or skipped; after the last one, what was done is saved
    private func next(done: Bool) {
        if done { playback.complete() } else { playback.skip() }
        stepStart = Date()
        paused = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        say(playback.current.map { "A seguir: " + $0.title } ?? "Tudo feito")
        if playback.finished { saveAtTheEnd() }
    }

    private func saveAtTheEnd() {
        guard !saved else { return }
        saved = true
        // skipped steps stay to confirm in Higiene, but «Agora» doesn't keep asking today
        if playback.done.count < routine.steps.count { store.skipRoutineToday(routine, undoable: false) }
        guard !playback.done.isEmpty else { return }
        let s: Store = store, r = routine, day = Day.today, n = playback.done.count
        let before = s.confirmSteps(playback.done, of: r, on: day)
        UndoCenter.shared.show("\(r.title): " + (n == 1 ? "1 passo concluído" : "\(n) passos concluídos")) { s.restoreRoutineLog(before, routine: r, on: day) }
    }

    private func say(_ text: String?) {
        guard let text else { return }
        speech.speak(AVSpeechUtterance(string: text))
    }
}

/// One shower a day: that evening or the next morning. A finished gym session counts.
struct ShowerCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let covered = ShowerRules.covered(store.showerTimes)
        let week = (0..<7).reversed().map { Day.add(-$0, to: Day.today) }
        let yesterdayOpen = Day.minuteOfDay() < 12 * 60 && !covered.contains(Day.add(-1, to: Day.today))
        Card {
            HStack {
                Eyebrow(text: "Duche", icon: "shower.fill")
                Spacer()
                Text("\(week.dropLast().filter(covered.contains).count) dos últimos 6 dias").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            HStack(spacing: 6) {
                ForEach(week, id: \.self) { d in
                    VStack(spacing: 3) {
                        Circle().fill(covered.contains(d) ? Color.water : Color.white.opacity(0.08)).frame(width: 14, height: 14)
                        Text(Day.date(d).formatted(.dateTime.weekday(.narrow))).font(.geist(10)).foregroundStyle(Color.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement().accessibilityLabel("\(Day.date(d).formatted(.dateTime.weekday(.wide))): \(covered.contains(d) ? "duche tomado" : "sem duche")")
                }
            }
            if covered.contains(Day.today) {
                Text("Feito por hoje").font(.geist(14)).foregroundStyle(Color.good)
            } else if yesterdayOpen {
                Text("O duche de ontem ainda está em aberto: um esta manhã conta para ontem.").font(.geist(13.5))
            } else if let s = store.showerPlan() {
                Text(s.when == .tonight ? "Esta noite, por volta das \(clock(Day.minuteOfDay(s.at)))" : "Amanhã de manhã, por volta das \(clock(Day.minuteOfDay(s.at)))").font(.geist(14, .medium))
                Text(s.why).font(.geist(12)).foregroundStyle(Color.soft)
                Picker("Quando", selection: Binding(get: { s.when }, set: { store.pickShower($0) })) {
                    Text("Esta noite").tag(ShowerRules.When.tonight)
                    Text("Amanhã de manhã").tag(ShowerRules.When.morning)
                }
                .pickerStyle(.segmented)
            }
            if !covered.contains(Day.today) || yesterdayOpen {
                SoftButton(title: "Já tomei duche", icon: "checkmark") { store.logShower() }.accessibilityIdentifier("shower.log")
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("shower.card")
    }
}

// MARK: - Higiene, one level below (phase 2.5)

/// Suggestions you answered «Ignorar» or «Lembrar mais tarde» to, kept in memory only, so they leave no mark in your
/// data: each stays away while the value it was answered for is the same (the estimate, the interval, the day)
@MainActor
final class CareSuggestionsHidden: ObservableObject {
    static let shared = CareSuggestionsHidden()
    @Published private(set) var hidden: [String: String] = [:]
    func hide(_ key: String, for value: String) { hidden[key] = value }
    func isHidden(_ key: String, for value: String) -> Bool { hidden[key] == value }
}

/// A secondary action, at least 44 pt tall
struct CareSoftButton: View {
    var title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.geist(13, .semibold)).foregroundStyle(Color.ink)
            .padding(.horizontal, 13).frame(minHeight: 44)
            .background(Capsule().fill(Color.white.opacity(0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
    }
}

/// All the routines: start one, change it, or add one
struct RoutinesList: View {
    @EnvironmentObject var store: Store
    @State private var playing: CareRoutine?
    @State private var editing: CareRoutine?

    var body: some View {
        let routines = store.all(CareRoutine.self).sorted { (rank($0), $0.title) < (rank($1), $1.title) }
        Screen(glow: Color(hex: 0x5FE3D0)) {
            Card {
                HStack {
                    Eyebrow(text: "Rotinas", icon: "list.number")
                    Spacer()
                    Button { editing = CareRoutine(title: "", steps: []) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                        .tint(.mint)
                        .accessibilityLabel("Nova rotina")
                }
                if routines.isEmpty { Text("Ainda sem rotinas.").font(.geist(13)).foregroundStyle(Color.soft) }
                ForEach(routines) { r in
                    HStack(spacing: 8) {
                        Image(systemName: r.icon).foregroundStyle(Color.soft).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.geist(14, .medium))
                            Text(summary(r)).font(.geist(11.5)).foregroundStyle(Color.faint)
                        }
                        Spacer(minLength: 4)
                        todayTag(r)
                        Button { editing = r } label: { Image(systemName: "pencil").foregroundStyle(Color.soft).frame(width: 44, height: 44) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Editar \(r.title)")
                        Button { playing = r } label: { Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(Color.mint).frame(width: 44, height: 44) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Começar \(r.title)")
                    }
                }
            }
            Text("Manhã até às 14:00, noite a partir daí, salvo se a rotina tiver uma hora própria.").font(.geist(11.5)).foregroundStyle(Color.faint).padding(.horizontal, 4)
        }
        .navigationTitle("Todas as rotinas")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { RoutinePlayer(routine: $0).environmentObject(store) }
        .sheet(item: $editing) { RoutineEditor(routine: $0).environmentObject(store) }
    }

    /// Morning first, then night, then the rest
    private func rank(_ r: CareRoutine) -> Int {
        switch CareRules.moment(of: r) {
        case .morning?: return 0
        case .night?: return 1
        case nil: return 2
        }
    }

    private func summary(_ r: CareRoutine) -> String {
        var parts = ["\(r.steps.count) \(r.steps.count == 1 ? "passo" : "passos")", duration(r.steps.map(\.seconds).reduce(0, +) / 60)]
        if let m = r.minute { parts.append(clock(m)) } else if let moment = CareRules.moment(of: r) { parts.append(moment.label) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func todayTag(_ r: CareRoutine) -> some View {
        let done = store.doneSteps(r).count
        if !r.steps.isEmpty && done == r.steps.count {
            StateTag(state: .done, text: "Feita hoje")
        } else if done > 0 {
            StateTag(state: .partial, text: "\(done) de \(r.steps.count)")
        }
    }
}

/// What the frequency editor opens with: the item, and the interval to start from when it comes from a suggestion
struct GroomingEdit: Identifiable {
    var item: GroomingItem
    var interval: Int?
    var id: String { item.id }
}

/// Frequências e evolução (N_HigieneDetalhes): how often each care is due, by fixed days or an interval (its editor
/// changes it); the interval you've learned, as a suggestion that changes nothing unless you accept it; and how
/// consistent the routines were, with prudence
struct CareDetailsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var hidden = CareSuggestionsHidden.shared
    @State private var editing: GroomingEdit?

    var body: some View {
        let today = Day.today
        let grooming = store.all(GroomingItem.self).sorted { ($0.rhythm, $0.title) < ($1.rhythm, $1.title) }
        let suggestion = grooming.first { g in g.suggestedInterval.map { !hidden.isHidden("interval.\(g.id)", for: "\($0)") } ?? false }
        let lastShower = store.showerTimes.max()
        let lastFloss = store.all(BrushLog.self).filter { $0.floss }.map(\.date).max()
        let routines = store.all(CareRoutine.self).filter { !$0.steps.isEmpty }.sorted { $0.title < $1.title }
        let anyLog = routines.contains { r in store.routineConsistency(r).full + store.routineConsistency(r).partial > 0 }
        Screen(glow: Color(hex: 0x5FE3D0)) {
            Card {
                HStack { Eyebrow(text: "Frequências"); Spacer(); Text("toca para mudar").font(.geist(11)).foregroundStyle(Color.faint) }
                fixedRow(title: "Duche", sub: "um por dia, à noite ou na manhã seguinte" + (lastShower.map { " · último \($0.formatted(.dateTime.weekday(.wide).hour().minute()))" } ?? ""), never: lastShower == nil)
                ForEach(grooming) { g in groomingRow(g, today: today) }
                fixedRow(title: "Fio dentário", sub: "no fim da escovagem" + (lastFloss.map { " · último a \(Day.date($0).formatted(.dateTime.day().month()))" } ?? ""), never: lastFloss == nil)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("care.frequencies")
            if let g = suggestion, let l = g.suggestedInterval {
                Card(state: .suggested) {
                    HStack { Eyebrow(text: "Sugestão"); Spacer(); StateTag(state: .suggested) }
                    Text("\(g.title) a cada \(l) dias").font(.geist(15, .semibold))
                    WhyLine(text: "nas últimas \(g.history.count) vezes fizeste-o, em média, a cada \(l) dias; está definido a cada \(g.interval).")
                    DecisionButtons(onAccept: { accept(l, for: g) },
                                    onAdjust: { editing = GroomingEdit(item: g, interval: l) },
                                    onIgnore: { hidden.hide("interval.\(g.id)", for: "\(l)") })
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("care.suggestion")
            }
            Card(state: anyLog ? .plain : .noData) {
                HStack {
                    Eyebrow(text: "Evolução · 14 dias")
                    Spacer()
                    if !anyLog { StateTag(state: .noData) }
                }
                if anyLog {
                    ForEach(routines) { r in
                        HStack {
                            Text(r.title).font(.geist(14))
                            Spacer()
                            Text(consistencyText(store.routineConsistency(r))).font(.geist(12)).foregroundStyle(Color.soft)
                        }
                    }
                } else {
                    Text("Ainda sem registos das rotinas nestes 14 dias. Preenche-se quando confirmas os passos.").font(.geist(13))
                }
                Text("Os dias sem registo ficam sem dados: não contam como falha. Sem diagnóstico nem conclusões de causa.").font(.geist(12)).foregroundStyle(Color.soft)
            }
        }
        .navigationTitle("Frequências e evolução")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { e in GroomingEditor(item: e.item, interval: e.interval).environmentObject(store) }
    }

    /// A frequency the app follows by its own rule (one shower a day; floss at brushing)
    private func fixedRow(title: String, sub: String, never: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.geist(14, .medium))
                Text(sub).font(.geist(12)).foregroundStyle(Color.soft)
            }
            Spacer(minLength: 6)
            if never { StateTag(state: .noData, text: "Nunca registado") }
        }
        .frame(minHeight: 44)
    }

    private func groomingRow(_ g: GroomingItem, today: String) -> some View {
        let last: String? = g.last.map { "último a \(Day.date($0).formatted(.dateTime.day().month()))" }
        let doneToday = g.history.contains(today)
        return HStack(spacing: 6) {
            Button { editing = GroomingEdit(item: g, interval: nil) } label: {
                HStack(spacing: 10) {
                    Image(systemName: g.icon).foregroundStyle(Color.soft).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.title).font(.geist(14, .medium)).foregroundStyle(Color.ink)
                        Text([CareRules.frequencyText(g), last].compactMap { $0 }.joined(separator: " · ")).font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 6)
                    if g.last == nil { StateTag(state: .noData, text: "Nunca registado") }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Mudar a frequência: dias fixos ou intervalo")
            .accessibilityIdentifier("care.freq.\(g.id)")
            Button { done(g) } label: {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "checkmark.circle").font(.system(size: 22)).foregroundStyle(Color.mint).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(doneToday)
            .accessibilityLabel(doneToday ? "\(g.title): feito hoje" : "Concluído: \(g.title)")
            .accessibilityIdentifier("care.freq.\(g.id).done")
        }
    }

    private func done(_ g: GroomingItem) {
        let s: Store = store
        guard let before = s.markGroomingDone(g) else { return }
        UndoCenter.shared.show("\(g.title): concluído hoje") { s.save(before) }
    }

    /// Aceitar: the interval changes now, with Desfazer
    private func accept(_ days: Int, for g: GroomingItem) {
        let s: Store = store
        guard let before = s.acceptInterval(days, for: g) else { return }
        UndoCenter.shared.show("\(g.title): a cada \(days) dias") { s.save(before) }
    }

    private func consistencyText(_ c: (full: Int, partial: Int)) -> String {
        let full = c.full == 1 ? "1 dia completo" : "\(c.full) dias completos"
        return c.partial == 0 ? full : full + " · \(c.partial) em parte"
    }
}

/// The frequency of one care: fixed days or an interval
struct GroomingEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var item: GroomingItem
    @State private var fixed: Bool
    @State private var days: [Int]

    /// `interval`: start from this interval (Ajustar on a suggestion)
    init(item: GroomingItem, interval: Int? = nil) {
        var x = item
        if let interval { x.interval = interval }
        let current: [Int] = interval == nil ? x.fixedDays : []
        _item = State(initialValue: x)
        _fixed = State(initialValue: !current.isEmpty)
        _days = State(initialValue: current.isEmpty ? [2, 4, 6] : current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Nome", text: $item.title) }
                Section("Frequência") {
                    Segments(options: [(false, "Intervalo"), (true, "Dias fixos")], selection: $fixed)
                    if fixed {
                        HStack(spacing: 0) {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in dayButton(wd) }
                        }
                        Text(days.isEmpty ? "Escolhe pelo menos um dia." : CareRules.weekdayNames(days)).font(.geist(12)).foregroundStyle(Color.soft)
                    } else {
                        Stepper(item.interval == 1 ? "Todos os dias" : "A cada \(item.interval) dias", value: $item.interval, in: 1...180)
                    }
                }
                if let l = item.learned {
                    Section { Text("O teu intervalo real, nas últimas \(item.history.count) vezes: cerca de \(l) dias.").font(.geist(13)).foregroundStyle(Color.soft) }
                }
            }
            .cadenceList()
            .navigationTitle(item.title.isEmpty ? "Frequência" : item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        item.weekdays = fixed ? days.sorted() : nil
                        store.save(item)
                        dismiss()
                    }
                    .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty || (fixed && days.isEmpty))
                }
            }
        }
    }

    private func dayButton(_ wd: Int) -> some View {
        let on = days.contains(wd)
        return Button { if on { days.removeAll { $0 == wd } } else { days.append(wd) } } label: {
            Text(["D", "S", "T", "Q", "Q", "S", "S"][wd - 1]).font(.geist(13, .semibold)).foregroundStyle(on ? Color(hex: 0x05140F) : Color.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(on ? Color.mint : Color.white.opacity(0.08)))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CareRules.weekdayName(wd))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One product of yours (N_HigieneProduto): its confirmed uses, when it runs out (always «Estimado»), what's left
/// («Muito», «Metade» and «Pouco» recalculate it) and, when it runs out soon and isn't on the list, the suggestion to add
/// it to the shopping list. Adicionar saves a real item; if the product is already on the list, the suggestion doesn't
/// show. «Lembrar mais tarde» and «Ignorar» leave no mark in your data (CareSuggestionsHidden).
struct CareProductView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var hidden = CareSuggestionsHidden.shared
    var productId: String
    @State private var editing: CareProduct?

    var body: some View {
        let product = store.record(CareProduct.self, productId)
        Screen(glow: Color(hex: 0x5FE3D0)) {
            if let p = product {
                content(p)
            } else {
                Text("Este produto já não está nos teus produtos.").font(.geist(14)).foregroundStyle(Color.soft).padding(.top, 12)
            }
        }
        .navigationTitle(product?.name ?? "Produto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let p = product { Button("Editar") { editing = p } }
            }
        }
        .sheet(item: $editing) { ProductEditor(product: $0).environmentObject(store) }
    }

    @ViewBuilder private func content(_ p: CareProduct) -> some View {
        let uses = store.productUses(p)
        let moments = store.productMoments(p)
        let refill = store.refillEstimate(p)
        let onList = store.isOnShoppingList(p.name)
        Text("Higiene · produto teu").font(.geist(13)).foregroundStyle(Color.soft).padding(.top, 8)
        Card {
            Eyebrow(text: "Uso")
            Text(moments.isEmpty ? "Ainda em nenhuma rotina: junta-o a um passo em Todas as rotinas." : moments).font(.geist(14))
            if let first = uses.first {
                Text(uses.count == 1 ? "1 uso confirmado, a \(dayText(first))" : "\(uses.count) usos confirmados desde \(dayText(first))").font(.geist(13)).foregroundStyle(Color.soft)
            } else {
                StateTag(state: .noData, text: "Ainda sem usos confirmados")
            }
        }
        refillCard(p, refill: refill)
        if onList {
            Card {
                HStack { Eyebrow(text: "Compras"); Spacer(); StateTag(state: .pending, text: "Na lista") }
                Text("Já está na lista de compras.").font(.geist(13)).foregroundStyle(Color.soft)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("care.product.onlist")
        } else if let refill, refill.days <= CareRules.refillWithin, !isHidden(p, refill) {
            Card(state: .suggested) {
                HStack { Eyebrow(text: "Compras"); Spacer(); StateTag(state: .suggested) }
                Text("Adicionar à lista de compras").font(.geist(15, .semibold))
                WhyLine(text: "acaba em cerca de \(CareRules.spanText(refill.days)); ainda não está na lista.")
                DecisionButtons(accept: "Adicionar", adjust: "Lembrar mais tarde", ignore: "Ignorar",
                                onAccept: { add(p, refill) },
                                onAdjust: { hidden.hide("later.\(p.id)", for: Day.today) },
                                onIgnore: { hidden.hide("refill.\(p.id)", for: CareRules.spanText(refill.days)) })
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("care.product.refill")
        }
    }

    @ViewBuilder private func refillCard(_ p: CareProduct, refill: CareRules.Refill?) -> some View {
        if let refill, let size = p.size, let per = p.perUse {
            Card {
                HStack { Eyebrow(text: "Reposição"); Spacer(); StateTag(state: .estimated) }
                HStack(spacing: 6) {
                    Text("Acaba em")
                    EstimatedText(value: CareRules.spanText(refill.days))
                }
                .font(.geist(17, .semibold))
                Text([CareRules.rangeText(refill), "embalagem de \(kg(size)) \(p.unit) e cerca de \(kg(per)) \(p.unit) por uso"].compactMap { $0 }.joined(separator: " · "))
                    .font(.geist(12)).foregroundStyle(Color.soft)
                Text("Não sei quanto usas de facto. Quanto ainda tens?").font(.geist(13))
                levelChips(p)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("care.product.estimate")
        } else {
            Card(state: .noData) {
                HStack { Eyebrow(text: "Reposição"); Spacer(); StateTag(state: .noData) }
                if p.size == nil || p.perUse == nil {
                    Text("Para estimar quando acaba, indica o tamanho da embalagem e quanto usas de cada vez.").font(.geist(13))
                    CareSoftButton(title: "Indicar", icon: "pencil") { editing = p }
                } else {
                    Text("Ainda há poucos usos confirmados para estimar quando acaba: são precisos 3, nos últimos 28 dias.").font(.geist(13))
                    Text("Quanto ainda tens?").font(.geist(13))
                    levelChips(p)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("care.product.estimate")
        }
    }

    private func levelChips(_ p: CareProduct) -> some View {
        HStack(spacing: 8) {
            ForEach(CareRules.levels) { level in
                let on = p.left.map { abs($0 - level.share) < 0.001 } ?? false
                Button { setLevel(level, of: p) } label: {
                    HStack(spacing: 4) {
                        if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                        Text(level.label)
                    }
                    .font(.geist(13, .semibold)).foregroundStyle(on ? Color.ink : Color.soft)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Capsule().fill(on ? Color.white.opacity(0.16) : Color.white.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .buttonStyle(Pressable())
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("care.product.level.\(level.id)")
            }
        }
    }

    private func setLevel(_ level: CareRules.Level, of p: CareProduct) {
        let s: Store = store
        guard let before = s.setLevel(level.share, of: p) else { return }
        UndoCenter.shared.show("Ainda tens: \(level.label.lowercased()). A estimativa foi recalculada.") { s.save(before) }
    }

    /// Adicionar: one real item on the shopping list, with Desfazer (nothing when it's already there)
    private func add(_ p: CareProduct, _ refill: CareRules.Refill) {
        let s: Store = store
        guard let item = s.addToShopping(name: p.name, reason: "acaba em cerca de \(CareRules.spanText(refill.days))", source: "Higiene") else { return }
        UndoCenter.shared.show("Adicionado às compras: \(item.name)") { s.remove(item) }
    }

    private func isHidden(_ p: CareProduct, _ refill: CareRules.Refill) -> Bool {
        hidden.isHidden("refill.\(p.id)", for: CareRules.spanText(refill.days)) || hidden.isHidden("later.\(p.id)", for: Day.today)
    }

    private func dayText(_ t: Double) -> String { Date(timeIntervalSince1970: t / 1000).formatted(.dateTime.day().month()) }
}

/// Your product: its name, the pack and about how much one use takes (both optional; without them there's no estimate)
struct ProductEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var product: CareProduct
    @State private var newPack = false

    var body: some View {
        let exists = store.record(CareProduct.self, product.id) != nil
        NavigationStack {
            Form {
                Section { TextField("Nome (ex.: Bioderma Sébium Gel Moussant)", text: $product.name) }
                Section("Embalagem") {
                    TextField("Tamanho (opcional)", value: $product.size, format: .number).keyboardType(.decimalPad)
                    Picker("Unidade", selection: $product.unit) { ForEach(["ml", "g"], id: \.self) { Text($0).tag($0) } }
                    TextField("Quanto usas de cada vez (opcional)", value: $product.perUse, format: .number).keyboardType(.decimalPad)
                }
                if exists {
                    Section { Toggle("Abri uma embalagem nova hoje", isOn: $newPack) }
                    Section { Button("Apagar", role: .destructive) { store.remove(product); dismiss() } }
                }
                Section { Text("Só entram os produtos que tens: a app não sugere marcas.").font(.geist(12)).foregroundStyle(Color.soft) }
            }
            .cadenceList()
            .navigationTitle(product.name.isEmpty ? "Novo produto" : product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        product.name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if newPack { product.startedAt = nowMs(); product.left = nil; product.leftAt = nil }
                        store.save(product)
                        dismiss()
                    }
                    .disabled(product.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
