// All promises: routines every x days at y time, must-dos, their weekly windows; and the editor.
import SwiftUI

struct PromisesView: View {
    @EnvironmentObject var store: Store
    @State private var editing: PromiseItem?

    var body: some View {
        List {
            ForEach([PromiseKind.mustDo, .routine], id: \.self) { kind in
                let items = store.promises.values.filter { $0.kind == kind }.sorted { store.time(of: $0) < store.time(of: $1) }
                if !items.isEmpty {
                    Section(kind == .mustDo ? "Obrigatórios" : "Rotinas") {
                        ForEach(items) { p in
                            Button { editing = p } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: p.icon).frame(width: 24).foregroundStyle(kind == .mustDo ? Color.warn : Color.mint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.title).foregroundStyle(p.active ? Color.ink : Color.faint)
                                        let w = store.week(p)
                                        Text(store.timeLabel(p) + (p.schedule.anchor.map { " (\(Schedule.anchors[$0] ?? $0))" } ?? "") + (p.schedule.weekendMinute.map { ", fim de semana \(clock($0))" } ?? "") + " · \(p.schedule.summary) · \(w.done)/\(w.total) esta semana").font(.caption).foregroundStyle(Color.soft)
                                    }
                                    Spacer()
                                    if !p.active { Text("em pausa").font(.caption).foregroundStyle(Color.faint) }
                                }
                            }
                            .swipeActions { Button("Apagar", role: .destructive) { store.delete(p) } }
                        }
                    }
                }
            }
            Section {
                Text("Janelas semanais em vez de sequências frágeis: um dia falhado baixa a contagem desta semana, mas nunca te põe a zero.")
                    .font(.footnote).foregroundStyle(Color.soft)
            }
        }
        .cadenceList()
        .navigationTitle("Hábitos")
        .toolbar { Button { editing = PromiseItem(title: "") } label: { Image(systemName: "plus") } }
        .sheet(item: $editing) { PromiseEditor(promise: $0) }
    }
}

struct PromiseEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var promise: PromiseItem
    @State private var time = Date()

    static let icons = ["checkmark.circle", "pills.fill", "drop.fill", "book.fill", "dumbbell.fill", "figure.walk", "mouth.fill", "takeoutbag.and.cup.and.straw.fill",
                        "fork.knife", "bed.double.fill", "sun.max.fill", "brain.head.profile", "scissors", "leaf.fill", "phone.fill", "creditcard.fill", "house.fill", "sparkles"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("O quê", text: $promise.title)
                    Picker("Tipo", selection: $promise.kind) { ForEach(PromiseKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                    Toggle("Ativo", isOn: $promise.active)
                } footer: {
                    Text(promise.kind == .mustDo ? "Um obrigatório avisa à hora marcada, outra vez 90 e 150 minutos depois, e o desacelerar espera até responderes." : "Uma rotina avisa uma vez, dentro do teu limite de notificações.")
                }
                Section("Quando") {
                    Picker("Repete", selection: $promise.schedule.rule) { ForEach(Schedule.Rule.allCases, id: \.self) { Text($0.label).tag($0) } }
                    if promise.schedule.rule == .everyNDays {
                        Stepper("A cada \(promise.schedule.every) dias", value: $promise.schedule.every, in: 1...60)
                        DatePicker("A partir de", selection: Binding(get: { Day.date(promise.schedule.start) }, set: { promise.schedule.start = Day.key($0) }), displayedComponents: .date)
                    }
                    if promise.schedule.rule == .weekdays {
                        HStack {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                                let on = promise.schedule.weekdays.contains(wd)
                                Button(["D", "S", "T", "Q", "Q", "S", "S"][wd - 1]) {
                                    if on { promise.schedule.weekdays.removeAll { $0 == wd } } else { promise.schedule.weekdays.append(wd) }
                                }
                                .buttonStyle(.plain)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(on ? Color.mint : .white.opacity(0.08)))
                                .foregroundStyle(on ? Color(hex: 0x032018) : Color.ink)
                            }
                        }
                    }
                    TimeChoice(promise: $promise, time: $time)
                }
                Section {
                    TextField("Versão mínima (p. ex. duas páginas)", text: Binding(get: { promise.tiny ?? "" }, set: { promise.tiny = $0.isEmpty ? nil : $0 }))
                } footer: { Text("Proposta antes de saltares: conta na mesma para a semana.") }
                Section("Regista comida ao marcar") {
                    TextField("kcal", value: $promise.kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Proteína g", value: $promise.protein, format: .number).keyboardType(.decimalPad)
                }
                Section("Ícone") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                        ForEach(Self.icons, id: \.self) { icon in
                            Image(systemName: icon).frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 10).fill(promise.icon == icon ? Color.mint.opacity(0.3) : .clear))
                                .onTapGesture { promise.icon = icon }
                        }
                    }
                }
            }
            .cadenceList()
            .navigationTitle(promise.title.isEmpty ? "Novo hábito" : promise.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        promise.schedule.minute = Day.minuteOfDay(time)
                        promise.title = promise.title.trimmingCharacters(in: .whitespaces)
                        store.save(promise)
                        dismiss()
                    }
                    .disabled(promise.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { time = Day.at(promise.schedule.minute, on: Day.today) }
        }
    }
}

/// Same time every day, a different weekend time, or anchored to waking, wind-down or lights out
struct TimeChoice: View {
    @EnvironmentObject var store: Store
    @Binding var promise: PromiseItem
    @Binding var time: Date

    private var mode: Binding<String> {
        Binding(get: { promise.schedule.anchor ?? (promise.schedule.weekendMinute == nil ? "fixed" : "weekend") }, set: { v in
            if v == "fixed" { promise.schedule.anchor = nil; promise.schedule.weekendMinute = nil }
            else if v == "weekend" { promise.schedule.anchor = nil; promise.schedule.weekendMinute = promise.schedule.weekendMinute ?? Day.minuteOfDay(time) + 120 }
            else { promise.schedule.anchor = v; promise.schedule.offset = promise.schedule.offset ?? (v == "lightsOut" ? -10 : 0) }
        })
    }

    var body: some View {
        Picker("Hora", selection: mode) {
            Text("Mesma hora todos os dias").tag("fixed")
            Text("Diferente ao fim de semana").tag("weekend")
            Text("Depois de acordar").tag("wake")
            Text("Ao desacelerar").tag("windDown")
            Text("Antes de apagar as luzes").tag("lightsOut")
        }
        if let a = promise.schedule.anchor {
            let off = promise.schedule.offset ?? 0
            let name = a == "wake" ? "acordar" : a == "lightsOut" ? "apagar as luzes" : "desacelerar"
            Stepper("\(abs(off)) min \(off < 0 ? "antes de" : "depois de") \(name)", value: Binding(get: { promise.schedule.offset ?? 0 }, set: { promise.schedule.offset = $0 }), in: -180...240, step: 5)
            Text("Hoje: \(store.timeLabel(promise)). Muda quando a tua hora de deitar muda.").font(.footnote).foregroundStyle(Color.soft)
        } else {
            DatePicker(promise.schedule.weekendMinute == nil ? "Hora" : "Dias úteis", selection: $time, displayedComponents: .hourAndMinute)
            if promise.schedule.weekendMinute != nil {
                DatePicker("Fim de semana", selection: Binding(get: { Day.at(promise.schedule.weekendMinute ?? 0, on: Day.today) }, set: { promise.schedule.weekendMinute = Day.minuteOfDay($0) }), displayedComponents: .hourAndMinute)
            }
        }
    }
}
