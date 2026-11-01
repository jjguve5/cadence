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
                            Text(call.umbrella ? "Take the umbrella" : "No umbrella").font(.system(size: 17, weight: .bold))
                            Text(call.summary).font(.system(size: 12.5)).foregroundStyle(Color.soft)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(Int(w.high.rounded()))°").font(.system(size: 26, weight: .bold))
                            Text("low \(Int(w.low.rounded()))°").font(.system(size: 11.5)).foregroundStyle(Color.soft)
                        }
                    }
                    if call.uvPeak >= 3, let h = call.uvHours { Text("UV \(Int(call.uvPeak)) from \(h): sunscreen before you go, reapply after 2 hours outside.").font(.system(size: 12)).foregroundStyle(Color.fuel) }
                    if let a = call.airNote { Text(a).font(.system(size: 12)).foregroundStyle(Color.warn) }
                    HStack {
                        Text("Sunrise \(clock(w.sunrise)) · daylight in the first hour helps tonight's sleep").font(.system(size: 11.5)).foregroundStyle(Color.faint)
                        Spacer()
                        Button("I was outside") { store.put("outside", "\(Day.today)-\(Day.minuteOfDay())", .bool(true)) }.font(.system(size: 11.5, weight: .semibold)).tint(.water)
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
                HStack { Eyebrow(text: "Wear today · \(store.weatherCall()?.layers ?? 2) layers", icon: "tshirt.fill"); Spacer() }
                if outfit.isEmpty { Text("Add some clothes and Cadence matches them to the weather and your day.").font(.system(size: 13)).foregroundStyle(Color.soft) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(outfit) { g in
                        VStack(spacing: 4) {
                            GarmentImage(garment: g).frame(height: 70)
                            Text(g.name).font(.system(size: 10.5)).lineLimit(1).foregroundStyle(Color.soft)
                        }
                        .contextMenu { Button("Swap", systemImage: "arrow.triangle.2.circlepath") { store.swap(g) } }
                    }
                }
                if !outfit.isEmpty, store.record(OutfitLog.self, Day.today)?.worn != true {
                    HStack {
                        SoftButton(title: "Wearing this", icon: "checkmark") { store.wear(outfit) }
                        Text("Long-press a piece to swap it").font(.system(size: 11)).foregroundStyle(Color.faint)
                    }
                }
                if store.weatherCall()?.umbrella == true, let white = store.garments.first(where: { $0.type == "shoes" && !$0.rainproof && $0.colors.contains(where: { $0.uppercased() == "FFFFFF" }) }) {
                    Text("\(white.name) stay home: rain.").font(.system(size: 12)).foregroundStyle(Color.soft)
                }
            }
            if gym.needed {
                Card(tint: .train) {
                    Eyebrow(text: "Gym bag", icon: "bag.fill", color: .train)
                    Text(gym.clean.isEmpty ? "No clean gym kit: wash a gym load today." : gym.clean.prefix(3).map(\.name).joined(separator: ", ")).font(.system(size: 14))
                }
            }
            Card(tint: .water) {
                Eyebrow(text: "Laundry", icon: "washer.fill", color: .water)
                let loads = store.laundryLoads()
                if loads.isEmpty { Text("Nothing waiting to be washed.").font(.system(size: 13)).foregroundStyle(Color.soft) }
                ForEach(loads, id: \.group) { load in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(load.group.capitalized) · \(load.items.count) items").font(.system(size: 14, weight: .medium))
                            Bar(progress: Double(load.items.count) / 11, area: .water)
                        }
                        Spacer()
                        if load.full { SoftButton(title: "Washed") { store.washed(load.group) } } else { Text("\(load.items.count) of 11").font(.system(size: 12)).foregroundStyle(Color.faint) }
                    }
                }
                let drying = store.garments.filter { $0.state == "drying" }
                if !drying.isEmpty {
                    HStack { Text("\(drying.count) drying").font(.system(size: 13)); Spacer(); SoftButton(title: "Put away") { store.putAway() } }
                }
            }
            Card {
                HStack { Eyebrow(text: "All clothes · \(store.garments.count)", icon: "square.grid.2x2"); Spacer(); Button { adding = true } label: { Label("Add", systemImage: "plus").font(.system(size: 13, weight: .semibold)) }.tint(Color(hex: 0x7FB8FF)) }
                ForEach(garmentTypes.sorted { $0.value < $1.value }, id: \.key) { type, name in
                    let items = store.garments.filter { $0.type == type }
                    if !items.isEmpty {
                        Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.soft)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(items) { g in
                                    Button { editing = g } label: {
                                        VStack(spacing: 2) {
                                            GarmentImage(garment: g).frame(width: 64, height: 64)
                                            Text(g.state).font(.system(size: 9.5)).foregroundStyle(g.state == "clean" ? Color.good : Color.faint)
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
        .navigationTitle("Wardrobe")
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
                        PhotosPicker(selection: $photo, matching: .images) { Label(working ? "Removing background…" : "Photo", systemImage: "camera") }
                    }
                    TextField("Name", text: $garment.name)
                    Picker("Type", selection: $garment.type) { ForEach(garmentTypes.sorted { $0.value < $1.value }, id: \.key) { Text($0.value).tag($0.key) } }
                    Picker("Style", selection: $garment.style) { Text("Casual").tag("casual"); Text("Smart").tag("smart"); Text("Sport").tag("sport") }
                    Stepper("Warmth \(garment.warmth) of 5", value: $garment.warmth, in: 1...5)
                    Toggle("Rainproof", isOn: $garment.rainproof)
                }
                Section("Washing") {
                    Picker("Washes with", selection: $garment.washGroup) { ForEach(washGroups, id: \.self) { Text($0).tag($0) } }
                    Stepper("Wash after \(garment.wearsBeforeWash) wears", value: $garment.wearsBeforeWash, in: 1...15)
                    Picker("State", selection: $garment.state) { Text("Clean").tag("clean"); Text("Worn").tag("worn"); Text("To wash").tag("wash"); Text("Drying").tag("drying") }
                }
                Section("Cost per wear") {
                    TextField("Price €", value: $garment.price, format: .number).keyboardType(.decimalPad)
                    if let p = garment.price, garment.totalWears > 0 { Text("\(euro(p / Double(garment.totalWears), decimals: true)) per wear after \(garment.totalWears) wears").foregroundStyle(Color.soft) }
                }
                if !isNew { Button("Delete", role: .destructive) { store.remove(garment); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(isNew ? "New item" : garment.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(garment); dismiss() }.disabled(garment.name.isEmpty) }
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
