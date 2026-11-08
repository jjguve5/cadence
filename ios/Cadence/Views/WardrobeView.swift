// Wardrobe and weather: the morning call, today's outfit with swaps, the gym bag, laundry loads, the catalogue.
import PhotosUI
import SwiftUI

struct WeatherCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject var weather = WeatherStore.shared
    var body: some View {
        Group {
            if let w = weather.today, let call = store.weatherCall() {
                Card(tint: .water) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Eyebrow(text: w.place, icon: call.umbrella ? "cloud.rain.fill" : "sun.max.fill", color: .water)
                            Text(call.umbrella ? "Leva o guarda-chuva" : "Sem guarda-chuva").font(.geist(17, .bold))
                            Text(call.summary).font(.geist(12.5)).foregroundStyle(Color.soft)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(Int(w.high.rounded()))°").font(.geist(26, .bold))
                            Text("mín. \(Int(w.low.rounded()))°").font(.geist(11.5)).foregroundStyle(Color.soft)
                        }
                    }
                    if call.uvPeak >= 3, let h = call.uvHours { Text("UV \(Int(call.uvPeak)), \(h): protetor solar antes de saíres, volta a pôr ao fim de 2 horas na rua.").font(.geist(12)).foregroundStyle(Color.fuel) }
                    if let a = call.airNote { Text(a).font(.geist(12)).foregroundStyle(Color.warn) }
                    HStack {
                        Text("Nascer do sol \(clock(w.sunrise)) · luz natural na primeira hora ajuda o sono desta noite").font(.geist(11.5)).foregroundStyle(Color.faint)
                        Spacer()
                        Button("Estive na rua") { store.put("outside", "\(Day.today)-\(Day.minuteOfDay())", .bool(true)) }.font(.geist(11.5, .semibold)).tint(.water)
                    }
                }
            }
        }
        .task { await weather.refresh() }
    }
}

struct WardrobeView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var editing: Garment?

    var body: some View {
        let outfit = store.outfit()
        let gym = store.gymBag()
        Screen(glow: Color(hex: 0x7FB8FF)) {
            WeatherCard()
            Card {
                HStack { Eyebrow(text: "Vestir hoje · \(store.weatherCall()?.layers ?? 2) camadas", icon: "tshirt.fill"); Spacer() }
                if outfit.isEmpty { Text("Adiciona algumas peças e o Cadence combina-as com o tempo e o teu dia.").font(.geist(13)).foregroundStyle(Color.soft) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(outfit) { g in
                        VStack(spacing: 4) {
                            GarmentImage(garment: g).frame(height: 70)
                            Text(g.name).font(.geist(10.5)).lineLimit(1).foregroundStyle(Color.soft)
                        }
                        .contextMenu { Button("Trocar", systemImage: "arrow.triangle.2.circlepath") { store.swap(g) } }
                    }
                }
                if !outfit.isEmpty, store.record(OutfitLog.self, Day.today)?.worn != true {
                    HStack {
                        SoftButton(title: "Vesti hoje", icon: "checkmark") { store.wear(outfit) }
                        Text("Toca sem largar numa peça para a trocar").font(.geist(11)).foregroundStyle(Color.faint)
                    }
                }
                if store.weatherCall()?.umbrella == true, let white = store.garments.first(where: { $0.type == "shoes" && !$0.rainproof && $0.colors.contains(where: { $0.uppercased() == "FFFFFF" }) }) {
                    Text("\(white.name) ficam em casa: chuva.").font(.geist(12)).foregroundStyle(Color.soft)
                }
            }
            if gym.needed {
                Card(tint: .train) {
                    Eyebrow(text: "Saco do ginásio", icon: "bag.fill", color: .train)
                    Text(gym.clean.isEmpty ? "Sem roupa de treino disponível: lava uma carga de treino hoje." : gym.clean.prefix(3).map(\.name).joined(separator: ", ")).font(.geist(14))
                }
            }
            Card(tint: .water) {
                Eyebrow(text: "Lavandaria", icon: "washer.fill", color: .water)
                let loads = store.laundryLoads()
                if loads.isEmpty { Text("Nada à espera de ser lavado.").font(.geist(13)).foregroundStyle(Color.soft) }
                ForEach(loads, id: \.group) { load in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(washGroupLabel(load.group).capitalized) · \(load.items.count) \(load.items.count == 1 ? "peça" : "peças")").font(.geist(14, .medium))
                            Bar(progress: Double(load.items.count) / 11, area: .water)
                        }
                        Spacer()
                        if load.full { SoftButton(title: "Já lavei") { store.washed(load.group) } } else { Text("\(load.items.count) de 11").font(.geist(12)).foregroundStyle(Color.faint) }
                    }
                }
                let drying = store.garments.filter { $0.state == "drying" }
                if !drying.isEmpty {
                    HStack { Text("\(drying.count) a secar").font(.geist(13)); Spacer(); SoftButton(title: "Arrumar") { store.putAway() } }
                }
            }
            Card {
                HStack { Eyebrow(text: "Todas as peças · \(store.garments.count)", icon: "square.grid.2x2"); Spacer(); Button { adding = true } label: { Label("Adicionar", systemImage: "plus").font(.geist(13, .semibold)) }.tint(Color(hex: 0x7FB8FF)) }
                ForEach(garmentTypes.sorted { $0.value < $1.value }, id: \.key) { type, name in
                    let items = store.garments.filter { $0.type == type }
                    if !items.isEmpty {
                        Text(name).font(.geist(12, .semibold)).foregroundStyle(Color.soft)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(items) { g in
                                    Button { editing = g } label: {
                                        VStack(spacing: 2) {
                                            GarmentImage(garment: g).frame(width: 64, height: 64)
                                            Text(garmentStateLabel(g.state)).font(.geist(9.5)).foregroundStyle(g.state == "clean" ? Color.good : Color.faint)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Roupeiro")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { GarmentEditor(garment: Garment(name: ""), isNew: true) }
        .sheet(item: $editing) { GarmentEditor(garment: $0, isNew: false) }
    }
}

struct GarmentImage: View {
    var garment: Garment
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(garment.colors.first.flatMap { UInt32($0, radix: 16) }.map { Color(hex: $0).opacity(0.35) } ?? Color.white.opacity(0.06))
            if let img = garment.image { Image(uiImage: img).resizable().scaledToFit().padding(4) }
            else { Image(systemName: garment.type == "shoes" ? "shoe.fill" : garment.type == "bottom" ? "figure.stand" : "tshirt.fill").foregroundStyle(Color.soft) }
        }
    }
}

struct GarmentEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var garment: Garment
    var isNew: Bool
    @State private var photo: PhotosPickerItem?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        GarmentImage(garment: garment).frame(width: 90, height: 90)
                        PhotosPicker(selection: $photo, matching: .images) { Label(working ? "A remover o fundo…" : "Fotografia", systemImage: "camera") }
                    }
                    TextField("Nome", text: $garment.name)
                    Picker("Tipo", selection: $garment.type) { ForEach(garmentTypes.sorted { $0.value < $1.value }, id: \.key) { Text($0.value).tag($0.key) } }
                    Picker("Estilo", selection: $garment.style) { Text("Casual").tag("casual"); Text("Formal").tag("smart"); Text("Desportivo").tag("sport") }
                    Stepper("Calor \(garment.warmth) de 5", value: $garment.warmth, in: 1...5)
                    Toggle("Impermeável", isOn: $garment.rainproof)
                }
                Section("Lavagem") {
                    Picker("Lava com", selection: $garment.washGroup) { ForEach(washGroups, id: \.self) { Text(washGroupLabel($0)).tag($0) } }
                    Stepper("Lavar a cada \(garment.wearsBeforeWash) usos", value: $garment.wearsBeforeWash, in: 1...15)
                    Picker("Estado", selection: $garment.state) { Text("Disponível").tag("clean"); Text("Usada").tag("worn"); Text("Para lavar").tag("wash"); Text("A secar").tag("drying") }
                }
                Section("Custo por uso") {
                    TextField("Preço €", value: $garment.price, format: .number).keyboardType(.decimalPad)
                    if let p = garment.price, garment.totalWears > 0 { Text("\(euro(p / Double(garment.totalWears), decimals: true)) por uso, ao fim de \(garment.totalWears) usos").foregroundStyle(Color.soft) }
                }
                if !isNew { Button("Apagar", role: .destructive) { store.remove(garment); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(isNew ? "Nova peça" : garment.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(garment); dismiss() }.disabled(garment.name.isEmpty) }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                working = true
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        let (thumb, b64) = await Task.detached { Cutout.thumbnail(img) }.value
                        garment.thumb = b64
                        if let c = Cutout.color(thumb) { garment.colors = [c] }
                    }
                    working = false
                }
            }
        }
    }
}
