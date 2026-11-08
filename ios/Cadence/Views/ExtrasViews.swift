// Screens for the extras: Air workouts, body progress, rest or train, where your time went, money extras, Pip's look.
import Charts
import PhotosUI
import SwiftUI

struct AirWorkoutsCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject var air = AirWorkouts.shared
    var body: some View {
        Card(tint: .train) {
            Eyebrow(text: "Registado pelo teu Air", icon: "applewatch.radiowaves.left.and.right", color: .train)
            if air.list.isEmpty { Text("As corridas, caminhadas e sessões que o Air regista aparecem aqui com a frequência cardíaca, depois de sincronizar.").font(.geist(13)).foregroundStyle(Color.soft) }
            ForEach(air.list.prefix(5)) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.name).font(.geist(14, .medium))
                        Text(e.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()) + " · \(e.minutes) min" + (e.distance.map { String(format: " · %.1f km", $0 / 1_000_000) } ?? "")).font(.geist(11.5)).foregroundStyle(Color.faint)
                    }
                    Spacer()
                    if let hr = e.avgHr { Text("\(Int(hr)) bpm").font(.mono(13)) }
                    if let c = e.calories { Text("\(Int(c)) kcal").font(.mono(12)).foregroundStyle(Color.soft) }
                }
            }
        }
        .task { await air.refresh() }
    }
}

struct RestOrTrainCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Group {
            if let f = store.restOrTrain() {
                Card {
                    Eyebrow(text: "Descansar ou treinar · próximos 3 dias", icon: "arrow.triangle.branch")
                    Chart {
                        ForEach(Array(f.train.enumerated()), id: \.offset) { i, v in LineMark(x: .value("day", i + 1), y: .value("r", v), series: .value("p", "Train")).foregroundStyle(Color.train) }
                        ForEach(Array(f.rest.enumerated()), id: \.offset) { i, v in LineMark(x: .value("day", i + 1), y: .value("r", v), series: .value("p", "Rest")).foregroundStyle(Color.mint) }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 90)
                    Text("Se treinares hoje: prontidão \(f.train[0]) amanhã. Se descansares: \(f.rest[0]). Pela forma como a tua prontidão mudou depois de dias de treino e de descanso.").font(.geist(12.5)).foregroundStyle(Color.soft)
                }
            }
        }
    }
}

struct BodyProgressView: View {
    @EnvironmentObject var store: Store
    @State private var photo: PhotosPickerItem?
    @State private var values: [String: String] = [:]
    @State private var photos = ProgressPhotos.all

    var body: some View {
        Screen(glow: .train) {
            Card {
                HStack { Eyebrow(text: "Fotografias de progresso", icon: "camera.fill"); Spacer(); PhotosPicker(selection: $photo, matching: .images) { Label("Adicionar", systemImage: "plus") }.tint(.train) }
                if photos.isEmpty { Text("Mesma luz, mesma pose, de poucas em poucas semanas. Ficam neste telemóvel.").font(.geist(13)).foregroundStyle(Color.soft) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(photos, id: \.url) { p in
                            VStack(spacing: 3) {
                                if let img = UIImage(contentsOfFile: p.url.path) { Image(uiImage: img).resizable().scaledToFill().frame(width: 110, height: 150).clipShape(RoundedRectangle(cornerRadius: 12)) }
                                Text(Day.date(p.date).formatted(.dateTime.day().month())).font(.geist(11)).foregroundStyle(Color.soft)
                            }
                        }
                    }
                }
            }
            Card {
                Eyebrow(text: "Medidas (cm)", icon: "ruler")
                let history = store.all(Measurement.self).sorted { $0.date > $1.date }
                ForEach(measurementNames, id: \.self) { name in
                    HStack {
                        Text(measurementLabel(name)).font(.geist(14))
                        Spacer()
                        if let last = history.first(where: { $0.values[name] != nil })?.values[name] {
                            let first = history.last(where: { $0.values[name] != nil })?.values[name] ?? last
                            Text("\(kg(last))" + (first != last ? String(format: " (%+.1f)", last - first) : "")).font(.mono(12.5)).foregroundStyle(Color.soft)
                        }
                        TextField("–", text: Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })).keyboardType(.decimalPad).frame(width: 60).multilineTextAlignment(.trailing)
                    }
                }
                SoftButton(title: "Guardar as de hoje", icon: "checkmark") {
                    var m = store.record(Measurement.self, Day.today) ?? Measurement()
                    for (k, v) in values { if let d = Double(v.replacingOccurrences(of: ",", with: ".")) { m.values[k] = d } }
                    store.save(m)
                    values = [:]
                }
            }
            Card {
                Eyebrow(text: "Força por quilo de peso corporal", icon: "scalemass")
                let bw = store.all(WeightEntry.self).max { $0.date < $1.date }?.kg ?? store.profile.weightKg
                let ids = Array(Set(store.sessions().flatMap { $0.sets.filter(\.done).map(\.exerciseId) }))
                ForEach(ids.compactMap { id in store.e1rmHistory(id).last.map { (id, $0.value) } }.sorted { $0.1 > $1.1 }.prefix(6), id: \.0) { id, v in
                    HStack { Text(Catalog.shared.exercise(id)?.name ?? id).font(.geist(13.5)).lineLimit(1); Spacer(); Text(String(format: "%.2f× o peso corporal", v / bw)).font(.mono(12.5)).foregroundStyle(Color.soft) }
                }
            }
            Card {
                Eyebrow(text: "Atividade · 12 semanas", icon: "calendar")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 12), spacing: 3) {
                    ForEach(0..<84, id: \.self) { i in
                        let d = Day.add(-83 + i, to: Day.today)
                        let trained = !store.sessions(on: d).isEmpty, azm = store.health[d]?.azm ?? 0
                        RoundedRectangle(cornerRadius: 3).fill(trained ? Color.train : azm >= 20 ? Color.train.opacity(0.45) : Color.white.opacity(0.06)).aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .navigationTitle("Evolução do corpo")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photo) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.7) {
                    ProgressPhotos.save(jpg)
                    photos = ProgressPhotos.all
                }
            }
        }
    }
}

struct TimeAuditCard: View {
    @EnvironmentObject var store: Store
    var week: String
    var body: some View {
        Card {
            Eyebrow(text: "Para onde foi o teu tempo", icon: "chart.pie.fill")
            ForEach(store.timeAudit(week: week), id: \.0) { name, actual, planned in
                HStack {
                    Text(timeAuditLabel(name)).font(.geist(13.5))
                    Spacer()
                    Text(duration(actual) + (planned.map { " de \(duration($0)) planeados" } ?? "")).font(.mono(12.5)).foregroundStyle(Color.soft)
                }
            }
            Text(store.timeAuditSuggestion(week: week)).font(.geist(12.5)).foregroundStyle(Color.mint)
        }
    }
}

struct MoneyExtras: View {
    @EnvironmentObject var store: Store
    @State private var planning = false
    var body: some View {
        let prep = store.prepSavings()
        let protein = store.proteinValue()
        Card {
            Eyebrow(text: "Pequenas vitórias", icon: "sparkles")
            HStack { Text("Arredondamentos este mês").font(.geist(13.5)); Spacer(); Text(euro(store.roundUps(), decimals: true)).font(.mono(13.5, .semibold)) }
            Text("Passa isto para a poupança no fim do mês: são os trocos de cada compra.").font(.geist(11.5)).foregroundStyle(Color.faint)
            HStack { Text("Comer fora e entregas").font(.geist(13.5)); Spacer(); Text(euro(prep.eatingOut)).font(.mono(13.5)) }
            if let per = prep.perPortion { Text("Uma porção preparada custa cerca de \(euro(per, decimals: true))" + (prep.saved.map { $0 > 0 ? ": cozinhar com antecedência poupou-te ~\(euro($0)) este mês." : "." } ?? ".")).font(.geist(12)).foregroundStyle(Color.good) }
            if !protein.isEmpty {
                Text("Proteína por euro").font(.geist(12, .semibold)).foregroundStyle(Color.soft)
                ForEach(protein.prefix(4), id: \.name) { p in HStack { Text(p.name).font(.geist(13)); Spacer(); Text("\(Int(p.perEuro)) g/€").font(.mono(12.5)) } }
            }
        }
        Card {
            HStack { Eyebrow(text: "Plano do ordenado", icon: "banknote.fill"); Spacer(); SoftButton(title: "Planear este mês") { planning = true } }
            if let p = store.record(Payday.self, String(Day.today.prefix(7))) {
                ForEach(p.jobs.sorted { $0.value > $1.value }, id: \.key) { k, v in HStack { Text(paydayJobLabel(k)).font(.geist(13.5)); Spacer(); Text(euro(v)).font(.mono(13.5)) } }
            } else { Text("No dia do ordenado, dá uma função a cada euro: contas, supermercado, roupeiro, viagens, objetivos.").font(.geist(12.5)).foregroundStyle(Color.soft) }
        }
        .sheet(isPresented: $planning) { PaydayPlanner() }
        Card {
            Eyebrow(text: "e-Fatura · \(String(Day.today.prefix(4)))", icon: "doc.plaintext")
            ForEach(store.efatura(), id: \.0) { name, v, rule in
                HStack { VStack(alignment: .leading) { Text(name).font(.geist(13.5)); Text(rule).font(.geist(10.5)).foregroundStyle(Color.faint) }; Spacer(); Text(euro(v)).font(.mono(13.5)) }
            }
            Text("Estimativas a partir dos gastos por categoria e do IVA das faturas. Valida as faturas pendentes no e-Fatura antes do prazo de fevereiro.").font(.geist(11.5)).foregroundStyle(Color.faint)
        }
    }
}

/// What each payday job shows; the English name is the key saved in Payday.jobs
fileprivate func paydayJobLabel(_ job: String) -> String {
    ["Fixed bills": "Contas fixas", "Groceries": "Supermercado", "Into goals": "Para objetivos", "Wardrobe": "Roupeiro",
     "Travel": "Viagens", "Fun": "Lazer", "Buffer": "Margem"][job] ?? job
}

/// What each of Pip's slots shows; the English slot is what's saved
fileprivate func pipSlotLabel(_ slot: String) -> String {
    ["head": "Cabeça", "face": "Cara", "neck": "Pescoço"][slot] ?? slot.capitalized
}

struct PaydayPlanner: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var jobs: [String: Double] = [:]
    var body: some View {
        let m = store.moneyMonth()
        NavigationStack {
            Form {
                Section("Rendimento \(euro(m.income)) · por atribuir \(euro(m.income - jobs.values.reduce(0, +)))") {
                    ForEach(["Fixed bills", "Groceries", "Into goals", "Wardrobe", "Travel", "Fun", "Buffer"], id: \.self) { k in
                        HStack { Text(paydayJobLabel(k)); Spacer(); TextField("€", value: Binding(get: { jobs[k] ?? 0 }, set: { jobs[k] = $0 }), format: .number).keyboardType(.decimalPad).frame(width: 90).multilineTextAlignment(.trailing) }
                    }
                }
            }
            .cadenceList()
            .navigationTitle("Plano do ordenado")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(Payday(month: String(Day.today.prefix(7)), jobs: jobs)); dismiss() } }
            }
            .onAppear {
                if let p = store.record(Payday.self, String(Day.today.prefix(7))) { jobs = p.jobs; return }
                let weeklyShop = store.shoppingList().compactMap(\.price).reduce(0, +)
                jobs = ["Fixed bills": m.fixed, "Into goals": m.goals, "Groceries": weeklyShop > 0 ? weeklyShop * 4.3 : 200]
            }
        }
    }
}

struct WardrobePicker: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Card(tint: .fuel) {
            Eyebrow(text: "Roupeiro do Pip · desbloqueado por nível", icon: "tshirt.fill", color: .fuel)
            ForEach(["head", "face", "neck"], id: \.self) { slot in
                Text(pipSlotLabel(slot)).font(.geist(11.5, .semibold)).foregroundStyle(Color.soft)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        let worn = store.pipOutfit.first { $0.slot == slot }
                        item(name: "Nada", icon: "xmark", open: true, on: worn == nil) { store.wear(nil, slot: slot) }
                        ForEach(pipAccessories.filter { $0.slot == slot }) { a in
                            let open = a.level <= store.level.level
                            item(name: open ? a.name : "Nível \(a.level)", icon: open ? a.icon : "lock.fill", open: open, on: worn?.id == a.id) { if open { store.wear(a, slot: slot) } }
                        }
                    }
                }
            }
            Text("Cada peça fica vestida em todas as animações. Desbloqueias mais ao subir de nível.").font(.geist(11.5)).foregroundStyle(Color.faint)
        }
    }

    private func item(name: String, icon: String, open: Bool, on: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.geist(18)).foregroundStyle(open ? Color.ink : Color.faint).frame(width: 50, height: 50)
                    .background(Circle().fill(.white.opacity(on ? 0.18 : 0.06)))
                    .overlay(Circle().stroke(on ? Color.mint : .clear, lineWidth: 2))
                Text(name).font(.geist(10.5)).foregroundStyle(open ? Color.ink : Color.faint).lineLimit(1)
            }
            .frame(width: 74)
        }
        .buttonStyle(.plain)
    }
}
