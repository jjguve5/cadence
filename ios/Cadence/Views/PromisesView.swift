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
                    Section(kind == .mustDo ? "Must-dos" : "Routines") {
                        ForEach(items) { p in
                            Button { editing = p } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: p.icon).frame(width: 24).foregroundStyle(kind == .mustDo ? Color.warn : Color.mint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.title).foregroundStyle(p.active ? Color.ink : Color.faint)
                                        let w = store.week(p)
                                        Text(store.timeLabel(p) + (p.schedule.anchor.map { " (\(Schedule.anchors[$0] ?? $0))" } ?? "") + (p.schedule.weekendMinute.map { ", weekends \(clock($0))" } ?? "") + " · \(p.schedule.summary) · \(w.done)/\(w.total) this week").font(.caption).foregroundStyle(Color.soft)
                                    }
                                    Spacer()
                                    if !p.active { Text("paused").font(.caption).foregroundStyle(Color.faint) }
                                }
                            }
                            .swipeActions { Button("Delete", role: .destructive) { store.delete(p) } }
                        }
                    }
                }
            }
            Section {
                Text("Weekly windows instead of fragile streaks: a missed day lowers this week's count, it never resets you to zero.")
                    .font(.footnote).foregroundStyle(Color.soft)
            }
        }
        .cadenceList()
        .navigationTitle("Promises")
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
                    TextField("What", text: $promise.title)
                    Picker("Type", selection: $promise.kind) { ForEach(PromiseKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                    Toggle("Active", isOn: $promise.active)
                } footer: {
                    Text(promise.kind == .mustDo ? "A must-do asks at its time, then 90 and 150 minutes later, and holds wind-down until you answer." : "A routine asks once, within your notification budget.")
                }
                Section("When") {
                    Picker("Repeats", selection: $promise.schedule.rule) { ForEach(Schedule.Rule.allCases, id: \.self) { Text($0.label).tag($0) } }
                    if promise.schedule.rule == .everyNDays {
                        Stepper("Every \(promise.schedule.every) days", value: $promise.schedule.every, in: 1...60)
                        DatePicker("Starting", selection: Binding(get: { Day.date(promise.schedule.start) }, set: { promise.schedule.start = Day.key($0) }), displayedComponents: .date)
                    }
                    if promise.schedule.rule == .weekdays {
                        HStack {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                                let on = promise.schedule.weekdays.contains(wd)
                                Button(["S", "M", "T", "W", "T", "F", "S"][wd - 1]) {
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
                    TextField("Tiny version (e.g. two pages)", text: Binding(get: { promise.tiny ?? "" }, set: { promise.tiny = $0.isEmpty ? nil : $0 }))
                } footer: { Text("Offered before you skip: it still counts toward the week.") }
                Section("Logs food when ticked") {
                    TextField("kcal", value: $promise.kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Protein g", value: $promise.protein, format: .number).keyboardType(.decimalPad)
                }
                Section("Icon") {
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
            .navigationTitle(promise.title.isEmpty ? "New promise" : promise.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
        Picker("Time", selection: mode) {
            Text("Same time every day").tag("fixed")
            Text("Different on weekends").tag("weekend")
            Text("After waking").tag("wake")
            Text("At wind-down").tag("windDown")
            Text("Before lights out").tag("lightsOut")
        }
        if let a = promise.schedule.anchor {
            let off = promise.schedule.offset ?? 0
            let name = a == "wake" ? "waking" : a == "lightsOut" ? "lights out" : "wind-down"
            Stepper("\(abs(off)) min \(off < 0 ? "before" : "after") \(name)", value: Binding(get: { promise.schedule.offset ?? 0 }, set: { promise.schedule.offset = $0 }), in: -180...240, step: 5)
            Text("Today: \(store.timeLabel(promise)). It moves when your bedtime moves.").font(.footnote).foregroundStyle(Color.soft)
        } else {
            DatePicker(promise.schedule.weekendMinute == nil ? "Time" : "Weekdays", selection: $time, displayedComponents: .hourAndMinute)
            if promise.schedule.weekendMinute != nil {
                DatePicker("Weekends", selection: Binding(get: { Day.at(promise.schedule.weekendMinute ?? 0, on: Day.today) }, set: { promise.schedule.weekendMinute = Day.minuteOfDay($0) }), displayedComponents: .hourAndMinute)
            }
        }
    }
}
