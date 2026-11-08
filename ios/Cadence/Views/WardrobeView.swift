// Wardrobe and weather: the morning call, today's outfit with swaps, the gym bag, the catalogue. Phase 2.10 (design
// v17, N_Roupeiro, N_RoupaNova, N_Lavandaria, N_LavarCarga): search and filters, each piece's uses with «Vesti hoje»
// and «Para lavar» (with Desfazer), the assisted add, the Lavandaria's five stages and the load planner.
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

/// A small action in a row of the Vida screens, like the design's «sm» buttons: at least 44 pt tall
struct LifeButton: View {
    enum Look { case soft, line, go }
    var title: String
    var icon: String? = nil
    var look: Look = .soft
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1)
            }
            .font(.geist(13.5, .semibold))
            .foregroundStyle(look == .go ? Color(hex: 0x05140F) : Color.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                switch look {
                case .soft: shape.fill(Color.white.opacity(0.09))
                case .line: shape.stroke(Color.white.opacity(0.22), lineWidth: 1)
                case .go: shape.fill(Area.mint.gradient)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(Pressable())
    }
}

/// "2 de 3 usos": uses since the last wash against the piece's limit
func usesText(_ g: Garment) -> String {
    "\(g.wears) de \(g.wearsBeforeWash) \(g.wearsBeforeWash == 1 ? "uso" : "usos")"
}

/// A past day in words: hoje, ontem, há 3 dias, or the date
func lifeDayText(_ day: String, today: String = Day.today) -> String {
    let n = Day.between(day, today)
    switch n {
    case 0: return "hoje"
    case 1: return "ontem"
    case 2...6: return "há \(n) dias"
    default: return "em \(Day.date(day).formatted(.dateTime.day().month()))"
    }
}

/// The Lavandaria in one line: what's suggested for washing, what waits, what's in the machine and what's drying
func laundrySummary(_ garments: [Garment]) -> String {
    let suggested = garments.filter { $0.stage == .suggested }.count
    let toWash = garments.filter { $0.stage == .toWash }.count
    let washing = garments.filter { $0.stage == .washing }.count
    let drying = garments.filter { $0.stage == .drying }.count
    var parts: [String] = []
    if suggested > 0 { parts.append(ptCount(suggested, "sugerida para lavar", "sugeridas para lavar")) }
    if toWash > 0 { parts.append("\(toWash) para lavar") }
    if washing > 0 { parts.append("\(washing) em lavagem") }
    if drying > 0 { parts.append("\(drying) a secar") }
    return parts.isEmpty ? "Nada por lavar" : parts.joined(separator: " · ")
}

/// "semana tens mais 3 treinos e só 1 peça de treino disponível" (after «Esta» or «esta»)
func gymKitText(trainings: Int, clean: Int) -> String {
    let more = trainings == 1 ? "1 treino" : "\(trainings) treinos"
    let kit: String
    if clean == 0 { kit = "nenhuma peça de treino disponível" } else if clean == 1 { kit = "só 1 peça de treino disponível" } else { kit = "só \(clean) peças de treino disponíveis" }
    return "semana tens mais \(more) e \(kit)"
}

/// A wash group as an identifier part ("gym 30°" → "gym30"), for the UI tests
func laundryGroupKey(_ group: String) -> String { group.filter { $0.isASCII && ($0.isLetter || $0.isNumber) } }

/// The Roupeiro's availability and stage filters
enum WardrobeFilter: String, CaseIterable {
    case available, suggested, toWash, washing, drying

    var label: String {
        switch self {
        case .available: return "Disponível"
        case .suggested: return "Sugerida"
        case .toWash: return "Para lavar"
        case .washing: return "Em lavagem"
        case .drying: return "A secar"
        }
    }

    /// «Disponível» is only the pieces whose stage is «Disponível»: a piece suggested for washing has its own filter
    func matches(_ g: Garment) -> Bool {
        switch self {
        case .available: return g.stage == .available || g.stage == .suggested // N_Roupeiro: only «Para lavar» hides a piece from the available ones
        case .suggested: return g.stage == .suggested
        case .toWash: return g.stage == .toWash
        case .washing: return g.stage == .washing
        case .drying: return g.stage == .drying
        }
    }
}

struct WardrobeView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var editing: Garment?
    @State private var search = ""
    @State private var stageFilter: WardrobeFilter? = .available
    @State private var typeFilter: String?
    @State private var colourFilter: String?
    @State private var selectedId: String?

    var body: some View {
        let outfit = store.outfit()
        let gym = store.gymBag()
        let all = store.garments
        let shown = filtered(all, byStage: true)
        let hidden = filtered(all, byStage: false).count - shown.count
        ScrollViewReader { proxy in
            Screen(glow: Color(hex: 0x7FB8FF)) {
                WeatherCard()
                Card {
                    HStack { Eyebrow(text: "Vestir hoje · \(ptCount(store.weatherCall()?.layers ?? 2, "camada", "camadas"))", icon: "tshirt.fill"); Spacer() }
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
                            LifeButton(title: "Vesti hoje", icon: "checkmark") { wearOutfit(outfit) }
                                .accessibilityIdentifier("life.wardrobe.outfit.wear")
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
                NavigationLink { LaundryView() } label: {
                    Card(tint: .water) {
                        HStack { Eyebrow(text: "Lavandaria", icon: "washer.fill", color: .water); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                        Text(laundrySummary(all)).font(.geist(13.5)).foregroundStyle(Color.ink)
                    }
                }
                .buttonStyle(Pressable())
                .accessibilityIdentifier("life.wardrobe.laundry")
                Card {
                    HStack { Eyebrow(text: "Todas as peças · \(all.count)", icon: "square.grid.2x2"); Spacer() }
                    if all.isEmpty {
                        Text("Ainda não tens peças. Adiciona a primeira com uma fotografia, ou preenche à mão.").font(.geist(13)).foregroundStyle(Color.soft)
                        LifeButton(title: "Adicionar peça", icon: "plus") { adding = true }
                    } else {
                        searchField
                        filters(all)
                        if shown.isEmpty { Text("Nenhuma peça com estes filtros.").font(.geist(13)).foregroundStyle(Color.soft) }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(shown) { g in tile(g) }
                        }
                        if hidden > 0, let f = stageFilter {
                            Text("\(hidden) \(hidden == 1 ? "peça escondida" : "peças escondidas") pelo filtro «\(f.label)».").font(.geist(12)).foregroundStyle(Color.faint)
                                .accessibilityIdentifier("life.wardrobe.hidden")
                        }
                    }
                }
                if let id = selectedId, let g = store.record(Garment.self, id) {
                    detail(g).id("life.wardrobe.detail")
                }
            }
            .onChange(of: selectedId) { _, id in
                guard id != nil else { return }
                withAnimation { proxy.scrollTo("life.wardrobe.detail", anchor: .bottom) }
            }
        }
        .navigationTitle("Roupeiro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label("Adicionar peça", systemImage: "plus") }.accessibilityIdentifier("life.wardrobe.add")
            }
        }
        .sheet(isPresented: $adding) { GarmentEditor(garment: Garment(name: "", unsure: ["washGroup"]), isNew: true) }
        .sheet(item: $editing) { GarmentEditor(garment: $0, isNew: false) }
    }

    // MARK: Search and filters

    private func filtered(_ all: [Garment], byStage: Bool) -> [Garment] {
        all.filter { (g: Garment) -> Bool in
            if !search.isEmpty && !g.name.localizedCaseInsensitiveContains(search) { return false }
            if let t = typeFilter, g.type != t { return false }
            if let c = colourFilter, !g.colors.contains(where: { colourFamily($0) == c }) { return false }
            if byStage, let f = stageFilter, !f.matches(g) { return false }
            return true
        }
        .sorted { $0.name < $1.name }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.faint)
            TextField("Pesquisar peças", text: $search).font(.geist(14)).accessibilityIdentifier("life.wardrobe.search")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func filters(_ all: [Garment]) -> some View {
        let types = Array(Set(all.map(\.type))).sorted { (garmentTypes[$0] ?? $0) < (garmentTypes[$1] ?? $1) }
        let colours = Array(Set(all.flatMap(\.colors).compactMap(colourFamily))).sorted()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(WardrobeFilter.allCases, id: \.self) { f in
                    chip(f.label, on: stageFilter == f, id: "life.wardrobe.filter.\(f.rawValue)") { stageFilter = stageFilter == f ? nil : f }
                }
                ForEach(types, id: \.self) { t in
                    chip(garmentTypes[t] ?? t, on: typeFilter == t, id: "life.wardrobe.filter.type.\(t)") { typeFilter = typeFilter == t ? nil : t }
                }
                if !colours.isEmpty {
                    Menu {
                        Button("Todas as cores") { colourFilter = nil }
                        ForEach(colours, id: \.self) { c in Button(c) { colourFilter = c } }
                    } label: {
                        chipLabel(colourFilter ?? "Cor", on: colourFilter != nil)
                    }
                    .accessibilityIdentifier("life.wardrobe.filter.colour")
                }
            }
        }
    }

    private func chip(_ text: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(text, on: on) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A selected chip has a check as well as its colour
    private func chipLabel(_ text: String, on: Bool) -> some View {
        HStack(spacing: 4) {
            if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            Text(text).font(.geist(13, .semibold)).lineLimit(1)
        }
        .foregroundStyle(on ? Color(hex: 0x05140F) : Color.ink)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Capsule().fill(on ? Color.mint : Color.white.opacity(0.08)))
        .contentShape(Capsule())
    }

    // MARK: Pieces

    private func tile(_ g: Garment) -> some View {
        Button { selectedId = g.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                GarmentImage(garment: g).frame(height: 64)
                Text(g.name).font(.geist(12.5, .semibold)).foregroundStyle(Color.ink).lineLimit(1)
                Text(usesText(g)).font(.geist(11)).foregroundStyle(Color.soft)
                if g.stage != .available { StateTag(state: g.stage.dataState, text: g.stage == .suggested ? "Lavar?" : g.stage.label) }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(selectedId == g.id ? 0.13 : 0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedId == g.id ? .isSelected : [])
        .accessibilityIdentifier("life.wardrobe.piece.\(g.id)")
    }

    private func detail(_ g: Garment) -> some View {
        Card {
            HStack(spacing: 12) {
                GarmentImage(garment: g).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.name).font(.geist(15, .semibold))
                    Text("\(garmentTypes[g.type] ?? g.type) · \(garmentStyleLabel(g.style).lowercased()) · lavar a cada \(g.wearsBeforeWash) \(g.wearsBeforeWash == 1 ? "uso" : "usos")").font(.geist(12)).foregroundStyle(Color.soft)
                }
                Spacer(minLength: 6)
                StateTag(state: g.stage.dataState, text: g.stage.label)
            }
            Text(usesSentence(g)).font(.geist(12.5)).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("life.wardrobe.uses")
            if g.isUnsure("washGroup") {
                HStack(spacing: 6) {
                    Text("Lava com \(washGroupLabel(g.washGroup))").font(.geist(12.5))
                    StateTag(state: .estimated, text: "Incerto")
                }
            }
            HStack(spacing: 8) {
                if g.wearable && g.lastWorn != Day.today {
                    LifeButton(title: "Vesti hoje", icon: "checkmark", look: .go) { wearPiece(g) }.accessibilityIdentifier("life.wardrobe.wear")
                }
                LifeButton(title: "Editar", look: .line) { editing = g }.accessibilityIdentifier("life.wardrobe.edit")
                if g.stage == .available || g.stage == .suggested {
                    LifeButton(title: "Para lavar") { sendToWash(g) }.accessibilityIdentifier("life.wardrobe.towash")
                }
            }
            Text("Só conta como usada quando confirmas «Vesti hoje»; escolher para amanhã não conta.").font(.geist(11)).foregroundStyle(Color.faint)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("life.wardrobe.detail")
    }

    private func usesSentence(_ g: Garment) -> String {
        var since: String
        if g.wears == 0 {
            since = "Ainda não usada desde a última lavagem"
        } else {
            since = "Usada \(g.wears) \(g.wears == 1 ? "vez" : "vezes") desde a última lavagem"
            if let last = g.lastWorn { since += ", a última \(lifeDayText(last))" }
        }
        let total = "\(g.totalWears) \(g.totalWears == 1 ? "uso" : "usos") no total"
        return since + " · " + total
    }

    // MARK: Actions (each with Desfazer)

    private func wearOutfit(_ items: [Garment]) {
        let s = store
        let log = s.record(OutfitLog.self, Day.today)
        s.wear(items)
        UndoCenter.shared.show(items.count == 1 ? "Vesti hoje: mais um uso" : "Vesti hoje: mais um uso em \(items.count) peças") { s.undoWear(items, log: log) }
    }

    private func wearPiece(_ g: Garment) {
        let s = store
        let log = s.record(OutfitLog.self, Day.today)
        s.wearPiece(g)
        UndoCenter.shared.show("\(g.name): mais um uso") { s.undoWear([g], log: log) }
    }

    private func sendToWash(_ g: Garment) {
        let s = store
        s.sendToWash(g)
        UndoCenter.shared.show("\(g.name) passou para a Lavandaria") { s.restoreGarments([g]) }
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

/// Nova peça and editing a piece. The assisted add (design N_RoupaNova): what the app proposes is marked «Sugerido»
/// until you save; how the piece washes stays «Incerto» until you choose or confirm it, and a load never presumes it.
/// A piece that looks like one you have is pointed out, never blocked: «É a mesma» adds to that piece instead.
struct GarmentEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var garment: Garment
    var isNew: Bool
    @State private var photo: PhotosPickerItem?
    @State private var working = false
    @State private var colourFromPhoto = false
    @State private var limitTouched = false
    @State private var notTheSame = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        GarmentImage(garment: garment).frame(width: 90, height: 90)
                        VStack(alignment: .leading, spacing: 6) {
                            PhotosPicker(selection: $photo, matching: .images) { Label(working ? "A remover o fundo…" : "Fotografia", systemImage: "camera") }
                            if colourFromPhoto, let c = garment.colors.first {
                                HStack(spacing: 6) {
                                    Text(colourFamily(c) ?? "Cor").font(.geist(12.5)).foregroundStyle(Color.soft)
                                    StateTag(state: .suggested)
                                }
                            }
                        }
                    }
                    TextField("Nome", text: $garment.name).accessibilityIdentifier("life.piece.name")
                    Picker("Tipo", selection: $garment.type) { ForEach(garmentTypes.sorted { $0.value < $1.value }, id: \.key) { Text($0.value).tag($0.key) } }
                    Picker("Estilo", selection: $garment.style) { Text("Casual").tag("casual"); Text("Formal").tag("smart"); Text("Desportivo").tag("sport") }
                    Stepper("Calor \(garment.warmth) de 5", value: $garment.warmth, in: 1...5)
                    Toggle("Impermeável", isOn: $garment.rainproof)
                } footer: {
                    if isNew { Text("Revê antes de guardar: a app sugere, tu confirmas.") }
                }
                if isNew, !notTheSame, !garment.name.isEmpty || !garment.colors.isEmpty, let twin = store.lookalike(of: garment) {
                    Section {
                        Text("Parece-se com «\(twin.name)», que já tens. É outra peça?").font(.geist(13.5))
                        HStack(spacing: 8) {
                            LifeButton(title: "É outra") { notTheSame = true }.accessibilityIdentifier("life.piece.other")
                            LifeButton(title: "É a mesma", look: .line) { same(twin) }.accessibilityIdentifier("life.piece.same")
                        }
                        Text("Não bloqueia: podes guardar já.").font(.geist(11)).foregroundStyle(Color.faint)
                    }
                }
                Section("Lavagem") {
                    HStack {
                        Picker("Lava com", selection: $garment.washGroup) { ForEach(washGroups, id: \.self) { Text(washGroupLabel($0)).tag($0) } }
                        if garment.isUnsure("washGroup") { StateTag(state: .estimated, text: "Incerto") }
                    }
                    if garment.isUnsure("washGroup") {
                        HStack {
                            Text("Confirma na etiqueta: muda a temperatura de lavagem. Até lá, não entra sozinha numa carga.").font(.geist(11.5)).foregroundStyle(Color.faint)
                            Spacer(minLength: 6)
                            LifeButton(title: "Confirmar", look: .line) { confirmWashGroup() }.accessibilityIdentifier("life.piece.confirmwash")
                        }
                    }
                    HStack {
                        Stepper("Lavar a cada \(garment.wearsBeforeWash) \(garment.wearsBeforeWash == 1 ? "uso" : "usos")", value: $garment.wearsBeforeWash, in: 1...15)
                        if isNew && !limitTouched { StateTag(state: .suggested) }
                    }
                    Stepper("\(garment.wears) \(garment.wears == 1 ? "uso" : "usos") desde a última lavagem", value: $garment.wears, in: 0...99)
                    Picker("Estado", selection: $garment.state) { Text("Disponível").tag("clean"); Text("Usada").tag("worn"); Text("Para lavar").tag("wash"); Text("A secar").tag("drying") }
                }
                Section("Custo por uso") {
                    TextField("Preço €", value: $garment.price, format: .number).keyboardType(.decimalPad)
                    if let p = garment.price, garment.totalWears > 0 { Text("\(euro(p / Double(garment.totalWears), decimals: true)) por uso, ao fim de \(ptCount(garment.totalWears, "uso", "usos"))").foregroundStyle(Color.soft) }
                }
                if !isNew { Button("Apagar", role: .destructive) { store.remove(garment); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(isNew ? "Nova peça" : garment.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { saveGarment() }
                        .disabled(garment.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("life.piece.save")
                }
            }
            .onChange(of: garment.washGroup) { _, _ in confirmWashGroup() }
            .onChange(of: garment.wearsBeforeWash) { _, _ in limitTouched = true }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                working = true
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        let (thumb, b64) = await Task.detached { Cutout.thumbnail(img) }.value
                        garment.thumb = b64
                        if let c = Cutout.color(thumb) { garment.colors = [c]; colourFromPhoto = true }
                    }
                    working = false
                }
            }
        }
    }

    /// You chose or confirmed how the piece washes: no longer «Incerto»
    private func confirmWashGroup() {
        guard let unsure = garment.unsure else { return }
        let left = unsure.filter { $0 != "washGroup" }
        garment.unsure = left.isEmpty ? nil : left
    }

    private func saveGarment() {
        let s = store
        var g = garment
        g.name = g.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if g.state != "wash" { g.washing = nil }
        if g.unsure?.isEmpty == true { g.unsure = nil }
        let before = s.record(Garment.self, g.id)
        s.save(g)
        let saved = g
        UndoCenter.shared.show(before == nil ? "\(saved.name) guardada no roupeiro" : "\(saved.name) alterada") {
            if let before { s.save(before) } else { s.remove(saved) }
        }
        dismiss()
    }

    /// «É a mesma»: no second piece; what this entry adds goes into the one you have
    private func same(_ twin: Garment) {
        let s = store
        s.mergeGarment(garment, into: twin)
        UndoCenter.shared.show("Juntada a \(twin.name), sem duplicar") { s.save(twin) }
        dismiss()
    }
}

// MARK: - Lavandaria

/// Lavandaria (design N_Lavandaria): every piece's stage, explicit steps with Desfazer, nothing marked washed without
/// your tap. «Arrumada» returns the piece as available and puts the count back to zero; the history of uses stays
struct LaundryView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let all = store.garments.sorted { $0.name < $1.name }
        let suggested = all.filter { $0.stage == .suggested }
        let toWash = all.filter { $0.stage == .toWash }
        let washing = all.filter { $0.stage == .washing }
        let drying = all.filter { $0.stage == .drying }
        Screen(glow: .water) {
            Text("Vida · o estado de cada peça").font(.geist(13)).foregroundStyle(Color.soft)
                .accessibilityIdentifier("life.laundry.screen")
            if all.isEmpty {
                Card(state: .noData) {
                    StateTag(state: .noData)
                    Text("Ainda não há peças no roupeiro. Adiciona-as no Roupeiro e o estado de cada uma aparece aqui.").font(.geist(13)).foregroundStyle(Color.soft)
                }
            }
            if let need = store.gymKitNeed() {
                NavigationLink { LaundryLoadView(group: need.group) } label: {
                    Card(state: .pending) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Esta \(gymKitText(trainings: need.trainings, clean: need.clean))").font(.geist(14)).foregroundStyle(Color.ink)
                                Text("planear uma carga").font(.geist(12)).foregroundStyle(Color.soft)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
                        }
                    }
                }
                .buttonStyle(Pressable())
                .accessibilityIdentifier("life.laundry.need")
            }
            if !suggested.isEmpty {
                Card {
                    HStack { Eyebrow(text: "Sugerida para lavar"); Spacer(); StateTag(state: .suggested, text: "\(suggested.count)") }
                    ForEach(suggested) { g in
                        row(g, usesText(g)) {
                            LifeButton(title: "Para lavar") { sendToWash(g) }.accessibilityIdentifier("life.laundry.towash.\(g.id)")
                        }
                    }
                    Text("Perto do limite de usos. Só passa para lavar se tocares.").font(.geist(11)).foregroundStyle(Color.faint)
                }
            }
            Card {
                HStack { Eyebrow(text: "Para lavar"); Spacer(); StateTag(state: .pending, text: "\(toWash.count)") }
                if toWash.isEmpty { Text("Nada à espera de ser lavado.").font(.geist(13)).foregroundStyle(Color.soft) }
                ForEach(toWash) { g in
                    row(g, toWashLine(g)) { EmptyView() }
                }
                ForEach(Array(Set(toWash.map(\.washGroup))).sorted(), id: \.self) { group in
                    let n = toWash.filter { $0.washGroup == group }.count
                    NavigationLink { LaundryLoadView(group: group) } label: {
                        HStack {
                            Text("Planear carga · \(washGroupLabel(group))").font(.geist(13.5, .semibold)).foregroundStyle(Color.ink)
                            Spacer()
                            Text("\(n) \(n == 1 ? "peça" : "peças")").font(.geist(12)).foregroundStyle(Color.soft)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("life.laundry.plan.\(laundryGroupKey(group))")
                }
            }
            if washing.isEmpty {
                HStack { Text("Em lavagem").font(.geist(14)); Spacer(); StateTag(state: .washing, text: "nada") }.padding(.horizontal, 4)
            } else {
                Card {
                    HStack { Eyebrow(text: "Em lavagem"); Spacer(); StateTag(state: .washing, text: "\(washing.count)") }
                    ForEach(washing) { g in
                        row(g, washGroupLabel(g.washGroup)) { EmptyView() }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("life.laundry.washing.\(g.id)")
                    }
                    LifeButton(title: "Já lavei · pôr a secar", icon: "wind") { hangToDry(washing) }.accessibilityIdentifier("life.laundry.dry")
                }
            }
            if !drying.isEmpty {
                Card {
                    HStack { Eyebrow(text: "A secar"); Spacer(); StateTag(state: .drying, text: "\(drying.count)") }
                    ForEach(drying) { g in
                        row(g, washGroupLabel(g.washGroup)) {
                            LifeButton(title: "Arrumada", look: .line) { putAway(g) }.accessibilityIdentifier("life.laundry.putaway.\(g.id)")
                        }
                    }
                }
            }
            Text("«Arrumada» devolve a peça ao roupeiro como disponível e põe a contagem a zero. O histórico de usos fica.").font(.geist(12)).foregroundStyle(Color.soft).padding(.horizontal, 4)
        }
        .navigationTitle("Lavandaria")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row<Trailing: View>(_ g: Garment, _ sub: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            GarmentImage(garment: g).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).font(.geist(14))
                Text(sub).font(.geist(12)).foregroundStyle(Color.soft)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }

    /// "escuros 30° · usada ontem": how it washes (or that it's still to confirm) and when it was last worn
    private func toWashLine(_ g: Garment) -> String {
        var parts: [String] = [washGroupLabel(g.washGroup)]
        if g.isUnsure("washGroup") { parts.append("lavagem por confirmar") }
        if let last = g.lastWorn { parts.append("usada \(lifeDayText(last))") }
        return parts.joined(separator: " · ")
    }

    private func sendToWash(_ g: Garment) {
        let s = store
        s.sendToWash(g)
        UndoCenter.shared.show("\(g.name) para lavar") { s.restoreGarments([g]) }
    }

    private func hangToDry(_ items: [Garment]) {
        let s = store
        s.hangToDry(items)
        UndoCenter.shared.show(items.count == 1 ? "1 peça a secar" : "\(items.count) peças a secar") { s.restoreGarments(items) }
    }

    private func putAway(_ g: Garment) {
        let s = store
        s.putAway(piece: g)
        UndoCenter.shared.show("\(g.name) arrumada: disponível") { s.restoreGarments([g]) }
    }
}

/// Planear lavagem (design N_LavarCarga): the pieces for washing whose care is known go in; a piece of the group only
/// suggested for washing is a candidate, and one whose wash group the app only guessed is marked «Desconhecido»: both
/// stay out unless you add them. Nothing changes until «Pôr a lavar agora» (with Desfazer), and nothing goes into the
/// Plano until you add it at the time you choose
struct LaundryLoadView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var group: String
    @State private var joined: Set<String> = []
    @State private var start = LaundryLoadView.nextHour()
    @State private var planned = false

    static func nextHour() -> Date {
        Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date()
    }

    var body: some View {
        let plan = store.loadPlan(group)
        let going = store.loadGoing(group, joined: joined)
        Screen(glow: .water) {
            Text("Lavandaria · carga sugerida").font(.geist(13)).foregroundStyle(Color.soft)
                .accessibilityIdentifier("life.load.screen")
            Card(state: .suggested) {
                HStack { Eyebrow(text: washGroupLabel(group), icon: "washer.fill", color: .water); Spacer(); StateTag(state: .suggested) }
                if plan.known.isEmpty && plan.suggested.isEmpty && plan.unknown.isEmpty { Text("Nada à espera de ser lavado neste grupo.").font(.geist(13)).foregroundStyle(Color.soft) }
                ForEach(plan.known) { g in
                    row(g, "lava com \(washGroupLabel(g.washGroup))") { EmptyView() }
                }
                ForEach(plan.suggested) { g in
                    let isIn = joined.contains(g.id)
                    row(g, "sugerida para lavar · \(usesText(g))") { StateTag(state: .suggested, text: "Sugerida") }
                    HStack(spacing: 8) {
                        LifeButton(title: "Juntar", icon: isIn ? "checkmark" : nil, look: isIn ? .soft : .line) { _ = joined.insert(g.id) }
                            .accessibilityLabel("Juntar \(g.name) à carga")
                            .accessibilityIdentifier("life.load.join.\(g.id)")
                            .accessibilityAddTraits(isIn ? .isSelected : [])
                        LifeButton(title: "Fica de fora", icon: isIn ? nil : "checkmark", look: isIn ? .line : .soft) { _ = joined.remove(g.id) }
                            .accessibilityLabel("\(g.name) fica de fora")
                            .accessibilityAddTraits(isIn ? [] : .isSelected)
                    }
                }
                ForEach(plan.unknown) { g in
                    let isIn = joined.contains(g.id)
                    row(g, g.stage == .suggested ? "sugerida para lavar · sem instruções de lavagem confirmadas" : "sem instruções de lavagem confirmadas") { StateTag(state: .noData, text: "Desconhecido") }
                    Text("Não presumo que \(g.name) aguenta \(washGroupLabel(group)).").font(.geist(12)).foregroundStyle(Color.soft)
                    HStack(spacing: 8) {
                        LifeButton(title: "Juntar mesmo assim", icon: isIn ? "checkmark" : nil, look: isIn ? .soft : .line) { _ = joined.insert(g.id) }
                            .accessibilityIdentifier("life.load.join.\(g.id)")
                            .accessibilityAddTraits(isIn ? .isSelected : [])
                        LifeButton(title: "Fica de fora", icon: isIn ? nil : "checkmark", look: isIn ? .line : .soft) { _ = joined.remove(g.id) }
                            .accessibilityAddTraits(isIn ? [] : .isSelected)
                    }
                }
            }
            Card {
                Eyebrow(text: "Quando", icon: "calendar")
                DatePicker("Hoje às", selection: $start, displayedComponents: .hourAndMinute).font(.geist(14))
                LifeButton(title: planned ? "No plano" : "Adicionar ao plano", icon: planned ? "checkmark" : "calendar.badge.plus") { addToPlan() }
                    .disabled(planned)
                    .accessibilityIdentifier("life.load.addplan")
                Text("Só entra no Plano quando tocas em «Adicionar ao plano».").font(.geist(11)).foregroundStyle(Color.faint)
            }
            PrimaryButton(title: "Pôr a lavar agora") { startNow(going) }
                .disabled(going.isEmpty)
                .opacity(going.isEmpty ? 0.45 : 1)
                .accessibilityIdentifier("life.load.start")
            Text(going.isEmpty ? "Nada para pôr a lavar." : "Passa \(going.count == 1 ? "a peça" : "as \(going.count) peças") para «em lavagem». Podes desfazer.")
                .font(.geist(12)).foregroundStyle(Color.faint).frame(maxWidth: .infinity)
        }
        .navigationTitle("Planear lavagem")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row<Trailing: View>(_ g: Garment, _ sub: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            GarmentImage(garment: g).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).font(.geist(14))
                Text(sub).font(.geist(12)).foregroundStyle(Color.soft)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }

    private func addToPlan() {
        let s = store
        let minute = Day.minuteOfDay(start)
        let block = PlanBlock(date: Day.today, start: minute, minutes: 90, title: "Lavar a roupa · \(washGroupLabel(group))", type: "other")
        s.save(block)
        planned = true
        UndoCenter.shared.show("Lavagem no plano às \(clock(minute))") {
            s.remove(block)
            planned = false
        }
    }

    private func startNow(_ items: [Garment]) {
        guard !items.isEmpty else { return }
        let s = store
        let laundryBefore = s.startWashing(items)
        UndoCenter.shared.show(items.count == 1 ? "1 peça em lavagem" : "\(items.count) peças em lavagem") { s.undoStartWashing(items, laundryBefore: laundryBefore) }
        dismiss()
    }
}
