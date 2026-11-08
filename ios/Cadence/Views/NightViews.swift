// The night on Today and its sheets (phase 2.9, design v17 N_HojeNoite, N_PrepAmanha, N_AntesDeDormir,
// N_AntesDeDormirTarde, N_BoaNoite, N_SonoManha; decisions 68–80). At night «Agora» follows your sequence, teeth →
// prepare tomorrow → read → sleep, and steps with nothing to do are hidden. Nothing here is required, nothing is
// saved without your tap, and «Vou dormir» is an intention, never the start of sleep. Rules and records: Night.swift.
import SwiftUI

/// Which night sheet Today opens
enum NightSheetPage: String, Identifiable {
    case prepare, bedtime
    var id: String { rawValue }
}

/// A reading started from the night, with the minutes planned (nil: none planned)
struct ReadingStart: Identifiable {
    let id = UUID()
    var minutes: Int?
}

/// A habit's answer as the morning shows it, with its label
struct HabitAnswer: Identifiable {
    var promise: PromiseItem
    var state: DataState
    var text: String? = nil // «Não fiz» or «Não se aplica»; nil is the state's own word
    var imported = false // answered from the band, not by you
    var id: String { promise.id }
}

/// A row's icon for an answer that isn't «feito»: a minus for «Não fiz», a slash for «Não se aplica», as their tags
fileprivate func skipIcon(_ state: DataState) -> String { state == .unavailable ? "slash.circle" : "minus.circle" }

// MARK: - Today at night

/// «Agora» at night: the sequence, the step for now, what comes after, and the day in a few lines (decisions 68–75)
struct TodayNightCard: View {
    @EnvironmentObject var store: Store
    var minute: Int
    var open: (NightSheetPage) -> Void
    var read: (Int?) -> Void

    var body: some View {
        let day = store.nightDay(minute: minute)
        let status = store.nightStatus(minute: minute)
        let plan = store.sleepPlan(for: day)
        VStack(alignment: .leading, spacing: 12) {
            NightStepsRow(status: status)
            switch status.current {
            case .teeth?: teeth(day)
            case .prepare?: prepare(day)
            case .read?: readingCard(plan)
            case .sleep?: sleepCard(plan, late: status.late)
            case nil: asleep(day)
            }
            if let later = laterText(status) { laterLine(later) }
            summary(day)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("night.card")
    }

    private func eyebrow(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Eyebrow(text: text, color: color)
            Spacer(minLength: 0)
        }
    }

    private func teeth(_ day: String) -> some View {
        Card(tint: .mint) {
            eyebrow("Agora · dentes", color: .mint)
            Text("Lavar os dentes").font(.geist(17, .semibold))
            HStack(spacing: 8) {
                Button { store.brushingOpen = true } label: {
                    Label("Começar", systemImage: "play.fill").font(.geist(14, .semibold)).foregroundStyle(Color(hex: 0x05140F))
                        .padding(.horizontal, 16).frame(minHeight: 44).background(Capsule().fill(Area.mint.gradient))
                }
                .accessibilityIdentifier("next.action")
                Button { store.markTeethDone(on: day) } label: {
                    Text("Já lavei").font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                .accessibilityIdentifier("night.teeth.done")
                Spacer(minLength: 0)
            }
            .buttonStyle(Pressable())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("night.now.teeth")
    }

    private func prepare(_ day: String) -> some View {
        let tomorrow = Day.add(1, to: day)
        let outfitOpen = store.profile.on("wardrobe") && store.record(OutfitLog.self, tomorrow) == nil && !store.tomorrowOutfit(tomorrow).isEmpty
        let bagOpen = store.profile.on("training") && store.gymBag(on: tomorrow).needed && store.gymBagPack(for: tomorrow)?.done != true
        let count = (outfitOpen ? 1 : 0) + (bagOpen ? 1 : 0)
        let weather = store.tomorrowWeather(tomorrow)
        let bag = store.bagItems(for: tomorrow)
        return Card(tint: .mint) {
            HStack(spacing: 8) {
                Eyebrow(text: "Agora · preparar amanhã", color: .mint)
                Spacer(minLength: 0)
                if count > 0 { StateTag(state: .pending, text: LeaveRules.pendingText(count)) }
            }
            if outfitOpen {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Roupa").font(.geist(15))
                        Text(weather.map { "sugerida · " + $0.text } ?? "sugerida com peças limpas e disponíveis").font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    StateTag(state: .suggested)
                }
            }
            if bagOpen {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saco de treino").font(.geist(15))
                        Text(bagNote(bag)).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    StateTag(state: .pending, text: "Por preparar")
                }
            }
            PrimaryButton(title: "Preparar · cerca de 5 min") { open(.prepare) }.accessibilityIdentifier("next.action")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("night.now.prepare")
    }

    private func bagNote(_ bag: (items: [BagItem], unavailable: [Garment])) -> String {
        var text = ptCount(bag.items.count, "item", "itens")
        if let g = bag.unavailable.first { text += " · \(g.name): \(g.stage.label.lowercased())" }
        return text
    }

    private func readingCard(_ plan: SleepPlan) -> some View {
        let suggestion = store.readingSuggestion(minute: minute)
        let detail: String = suggestion.map { "\($0.minutes) min sugeridos · até \(PlanFormat.at($0.until))" } ?? "luzes \(PlanFormat.at(plan.perform))"
        return Card(tint: .read) {
            eyebrow("Agora · ler", color: .read)
            Text(store.currentBook?.title ?? "Ler").font(.geist(17, .semibold))
            Text(detail).font(.geist(12)).foregroundStyle(Color.soft)
            HStack(spacing: 8) {
                Button { read(suggestion?.minutes) } label: {
                    Label("Começar", systemImage: "play.fill").font(.geist(14, .semibold)).foregroundStyle(Color(hex: 0x2B1A05))
                        .padding(.horizontal, 16).frame(minHeight: 44).background(Capsule().fill(Area.read.gradient))
                }
                .accessibilityIdentifier("next.action")
                Button { open(.bedtime) } label: {
                    Text("Antes de dormir").font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                .accessibilityIdentifier("night.open.bedtime")
                Spacer(minLength: 0)
            }
            .buttonStyle(Pressable())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("night.now.read")
    }

    private func sleepCard(_ plan: SleepPlan, late: Bool) -> some View {
        Card(tint: .sleep) {
            eyebrow(late ? "Agora · só o essencial" : "Agora · dormir", color: .sleep)
            Text("Antes de dormir").font(.geist(17, .semibold))
            Text(late ? "Ficou tarde: a versão curta, sem pressão." : "Luzes \(PlanFormat.at(plan.perform)) · acordas \(PlanFormat.at(store.profile.wakeMinute))")
                .font(.geist(12)).foregroundStyle(Color.soft)
            PrimaryButton(title: "Antes de dormir", area: .sleep) { open(.bedtime) }.accessibilityIdentifier("next.action")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("night.now.sleep")
    }

    /// After «Vou dormir»: one calm line, no new task
    @ViewBuilder private func asleep(_ day: String) -> some View {
        if let i = store.sleepIntent(day) {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(Color.sleep).frame(width: 22).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Boa noite").font(.geist(14.5, .semibold))
                        Text("Intenção de dormir \(PlanFormat.at(i.minute)). O sono chega \(store.profile.usesBand ? "da pulseira" : "do Apple Health") de manhã.")
                            .font(.geist(12)).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("night.intent")
        }
    }

    /// "Depois: ler · dormir"
    private func laterText(_ status: NightStatus) -> String? {
        guard let current = status.current, !status.late else { return nil }
        let rest = status.steps.drop { $0 != current }.dropFirst().filter { !status.done.contains($0) }
        return rest.isEmpty ? nil : "Depois: " + rest.map { $0.label.lowercased() }.joined(separator: " · ")
    }

    private func laterLine(_ text: String) -> some View {
        Button { open(.bedtime) } label: {
            HStack(spacing: 8) {
                Text(text).font(.geist(12.5)).foregroundStyle(Color.soft).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre Antes de dormir")
        .accessibilityIdentifier("night.later")
    }

    /// «O dia»: imported apart from yours, what's still to confirm (never «não feito»), and no records as «Sem dados»
    @ViewBuilder private func summary(_ day: String) -> some View {
        let s = store.nightDaySummary(on: day, minute: minute)
        if !s.isEmpty {
            Card {
                Eyebrow(text: "O dia")
                if !s.imported.isEmpty { summaryRow(s.imported.joined(separator: ", "), "da pulseira", state: .imported, tag: nil) }
                if !s.yours.isEmpty { summaryRow(s.yours.joined(separator: ", "), "respondido por ti", state: .confirmed, tag: "Registado") }
                if !s.open.isEmpty { summaryRow(s.open.joined(separator: ", "), "sem resposta: confirmas tu, se quiseres", state: .pending, tag: "Por confirmar") }
                if s.noWater { summaryRow("Água", "nada registado hoje", state: .noData, tag: nil) }
                if s.noFood { summaryRow("Comida", "nada registado hoje", state: .noData, tag: nil) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("night.day")
        }
    }

    private func summaryRow(_ title: String, _ sub: String, state: DataState, tag: String?) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.geist(14)).lineLimit(2)
                Text(sub).font(.geist(12)).foregroundStyle(Color.soft)
            }
            Spacer(minLength: 4)
            StateTag(state: state, text: tag)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The night's sequence: each step with its word, a check when done (state never by colour alone)
struct NightStepsRow: View {
    var status: NightStatus

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(status.steps, id: \.self) { step in
                let done = status.done.contains(step)
                let now = status.current == step
                let skip = NightRules.skipTag(status.skipped[step])
                VStack(spacing: 4) {
                    ZStack {
                        if let skip {
                            Circle().stroke(Color.faint, lineWidth: 1.5)
                            Image(systemName: skip.state == .unavailable ? "line.diagonal" : "minus").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.soft)
                        } else if done {
                            Circle().fill(Color.mint)
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x05140F))
                        } else {
                            Circle().fill(now ? Color.white.opacity(0.12) : Color.clear)
                            Circle().stroke(now ? Color.ink : Color.faint, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 20, height: 20)
                    Text(step.label).font(.geist(11, .semibold)).foregroundStyle(skip != nil ? Color.soft : done ? Color.mint : now ? Color.ink : Color.faint)
                        .multilineTextAlignment(.center)
                    if let skip { Text(skip.text).font(.geist(10)).foregroundStyle(Color.faint).multilineTextAlignment(.center) }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sequência da noite: " + status.steps.map { status.spoken($0) }.joined(separator: "; "))
        .accessibilityIdentifier("night.steps")
    }
}

// MARK: - The night's sheets

/// Preparar amanhã or Antes de dormir, in one navigation stack (one leads to the other), with Desfazer at the bottom
struct NightSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var page: NightSheetPage

    var body: some View {
        NavigationStack {
            switch page {
            case .prepare: PrepTomorrowView(close: { dismiss() })
            case .bedtime: BedtimeView(close: { dismiss() })
            }
        }
        .overlay(alignment: .bottom) { UndoBar() }
    }
}

/// Preparar amanhã (N_PrepAmanha): tomorrow's outfit from clean, available pieces only, the gym bag, and the way to
/// the reading. «Aceitar roupa» chooses without counting a use; the bag packed reaches Antes de sair as packed.
struct PrepTomorrowView: View {
    @EnvironmentObject var store: Store
    var close: () -> Void
    @State private var picked: [String]? = nil // pieces swapped here before «Aceitar roupa»; nothing is saved until then

    var body: some View {
        let day = store.nightDay(minute: store.nowMinute)
        let tomorrow = Day.add(1, to: day)
        Screen(glow: .sleep) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Preparar amanhã").font(.geist(26, .bold)).accessibilityIdentifier("night.prep.screen")
                Text(subtitle(tomorrow)).font(.geist(13)).foregroundStyle(Color.soft)
            }
            .padding(.top, 8)
            if let w = store.tomorrowWeather(tomorrow) { SourceLine(text: "Open-Meteo · " + w.text) }
            outfitCard(tomorrow)
            bagCard(tomorrow)
            Text("Nada mais para amanhã.").font(.geist(12)).foregroundStyle(Color.faint).padding(.horizontal, 4)
            NavigationLink { BedtimeView(close: close) } label: {
                Text(store.nightRead(on: day) == nil ? "Antes de dormir" : "Ir para a leitura").font(.geist(16, .semibold)).foregroundStyle(Color(hex: 0x05140F))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Area.mint.gradient))
            }
            .buttonStyle(Pressable())
            .accessibilityIdentifier("night.prep.read")
            Button { store.dismissPrep(on: day); close() } label: {
                Text("Dispensar hoje").font(.geist(14, .semibold)).foregroundStyle(Color.soft).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("night.prep.dismiss")
            Text("Ir para a leitura não fecha o dia.").font(.geist(11)).foregroundStyle(Color.faint).frame(maxWidth: .infinity)
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { close() }.accessibilityIdentifier("night.prep.close") } }
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Segunda-feira · Faculdade às 9:00 · treino às 18:00"
    private func subtitle(_ day: String) -> String {
        let name = Day.date(day).formatted(.dateTime.weekday(.wide))
        let first = name.prefix(1).uppercased() + String(name.dropFirst())
        return ([first] + store.dayParts(day).filter { $0 != "saco pronto" && $0 != "roupa escolhida" }).joined(separator: " · ")
    }

    // MARK: Outfit

    @ViewBuilder private func outfitCard(_ tomorrow: String) -> some View {
        if store.profile.on("wardrobe"), store.garments.contains(where: { $0.type != "gym" }) {
            let saved = store.record(OutfitLog.self, tomorrow)
            let ids = picked ?? store.tomorrowOutfit(tomorrow).map { $0.id }
            let pieces = ids.compactMap { store.record(Garment.self, $0) }
            let chosen = saved != nil && picked == nil
            if pieces.isEmpty {
                Card(state: .noData) {
                    HStack(spacing: 8) {
                        Eyebrow(text: "Roupa")
                        Spacer(minLength: 0)
                        StateTag(state: .noData)
                    }
                    Text("Nenhuma peça limpa e disponível para amanhã.").font(.geist(13)).foregroundStyle(Color.soft)
                }
            } else {
                Card(state: chosen ? .plain : .suggested) {
                    HStack(spacing: 8) {
                        Eyebrow(text: "Roupa")
                        Spacer(minLength: 0)
                        if chosen { StateTag(state: .confirmed, text: "Escolhida").accessibilityIdentifier("night.outfit.chosen") } else { StateTag(state: .suggested) }
                    }
                    ForEach(pieces) { g in pieceRow(g, ids: ids) }
                    if !chosen {
                        WhyLine(text: outfitWhy(tomorrow))
                        Button { accept(pieces, for: tomorrow) } label: {
                            Text("Aceitar roupa").font(.geist(13, .semibold)).foregroundStyle(Color(hex: 0x05140F))
                                .padding(.horizontal, 16).frame(minHeight: 44).background(Capsule().fill(Area.mint.gradient))
                        }
                        .buttonStyle(Pressable())
                        .accessibilityIdentifier("night.outfit.accept")
                    }
                    Text("Escolher não conta como usar: só conta quando confirmares que vestiste.").font(.geist(11)).foregroundStyle(Color.faint)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("night.outfit")
            }
        }
    }

    private func pieceRow(_ g: Garment, ids: [String]) -> some View {
        let alternatives = store.garments.filter { $0.type == g.type && $0.stage == .available && !ids.contains($0.id) }.sorted { $0.name < $1.name }
        let uses: String = g.wears == 0 ? "disponível" : "disponível · \(g.wears) de \(g.wearsBeforeWash) usos"
        return HStack(spacing: 10) {
            thumb(g)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).font(.geist(14))
                Text(uses).font(.geist(12)).foregroundStyle(Color.soft)
            }
            Spacer(minLength: 4)
            Button {
                if let alt = alternatives.first { picked = ids.map { $0 == g.id ? alt.id : $0 } }
            } label: {
                Text("Trocar").font(.geist(13, .semibold)).foregroundStyle(alternatives.isEmpty ? Color.faint : Color.ink)
                    .padding(.horizontal, 12).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(alternatives.isEmpty)
            .accessibilityLabel(alternatives.isEmpty ? "Sem outra peça disponível para \(g.name)" : "Trocar \(g.name)")
            .accessibilityIdentifier("night.outfit.swap.\(g.id)")
        }
    }

    @ViewBuilder private func thumb(_ g: Garment) -> some View {
        if let img = g.image {
            Image(uiImage: img).resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
        } else {
            Circle().fill(Color(hex: UInt32(g.colors.first ?? "", radix: 16) ?? 0x808080)).frame(width: 26, height: 26)
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1)).frame(width: 36, height: 36).accessibilityHidden(true)
        }
    }

    private func outfitWhy(_ day: String) -> String {
        var parts: [String] = []
        if let w = store.tomorrowWeather(day) { parts.append(w.rain ? "chuva prevista" : "sem chuva prevista") }
        parts.append(store.formalDay(day) ? "há um compromisso formal" : "nada formal no calendário")
        return parts.joined(separator: ", ") + "; só peças limpas e disponíveis."
    }

    private func accept(_ pieces: [Garment], for day: String) {
        let s: Store = store
        let before = s.chooseOutfit(pieces, for: day)
        picked = nil
        UndoCenter.shared.show("Roupa escolhida para amanhã · sem contar uso") { s.restoreOutfit(before, for: day) }
    }

    // MARK: Gym bag

    @ViewBuilder private func bagCard(_ tomorrow: String) -> some View {
        if store.profile.on("training"), store.gymBag(on: tomorrow).needed {
            let bag = store.bagItems(for: tomorrow)
            let pack = store.gymBagPack(for: tomorrow)
            let packed = Set(pack?.items ?? [])
            let ready = pack?.done == true
            let slot = store.trainingSlot(on: tomorrow)
            Card(state: ready ? .plain : .pending) {
                HStack(spacing: 8) {
                    Eyebrow(text: "Saco de treino")
                    if let slot { Text("\(slot.title) · \(clock(slot.start))").font(.geist(11)).foregroundStyle(Color.faint).lineLimit(1) }
                    Spacer(minLength: 0)
                    if ready { StateTag(state: .done, text: "Pronto").accessibilityIdentifier("night.bag.ready") } else { StateTag(state: .pending, text: "Por preparar") }
                }
                ForEach(bag.items) { item in bagRow(item, packed: packed.contains(item.id), all: bag.items, day: tomorrow) }
                ForEach(bag.unavailable) { g in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.geist(14)).foregroundStyle(Color.soft)
                            Text("não está disponível para levar").font(.geist(12)).foregroundStyle(Color.faint)
                        }
                        Spacer(minLength: 4)
                        StateTag(state: g.stage.dataState, text: g.stage.label)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
                if !bag.items.contains(where: { $0.id.hasPrefix("g.") }), !bag.unavailable.isEmpty {
                    Text("Sem roupa de treino disponível: vê na Lavandaria o que fica pronto a tempo.").font(.geist(12)).foregroundStyle(Color.warn)
                }
                if !ready {
                    Button { store.packBag(bag.items, for: tomorrow) } label: {
                        Label(bag.items.count > 1 ? "Pus os \(bag.items.count) no saco" : "Pus no saco", systemImage: "checkmark")
                            .font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                            .padding(.horizontal, 16).frame(minHeight: 44).background(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(Pressable())
                    .accessibilityIdentifier("night.bag.packall")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("night.bag")
        }
    }

    private func bagRow(_ item: BagItem, packed: Bool, all: [BagItem], day: String) -> some View {
        Button { store.toggleBagItem(item, of: all, for: day) } label: {
            HStack(spacing: 10) {
                Image(systemName: packed ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(packed ? Color.good : Color.soft)
                Text(item.title).font(.geist(14)).foregroundStyle(Color.ink)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), \(packed ? "no saco" : "por pôr no saco")")
        .accessibilityIdentifier("night.bag.item.\(item.id)")
    }
}

/// Antes de dormir (N_AntesDeDormir), its short version when it's late (N_AntesDeDormirTarde) and Boa noite once you
/// say «Vou dormir» (N_BoaNoite). Nothing here is required.
struct BedtimeView: View {
    @EnvironmentObject var store: Store
    var close: () -> Void
    @State private var reading: ReadingStart? = nil

    var body: some View {
        let minute = store.nowMinute
        let day = store.nightDay(minute: minute)
        let intent = store.sleepIntent(day)
        Group {
            if let intent { GoodNightView(day: day, intent: intent, close: close) }
            else if store.nightLate(minute: minute) { short(day, minute: minute) }
            else { full(day, minute: minute) }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if intent == nil { Button("Fechar") { close() }.accessibilityIdentifier("night.bedtime.close") }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $reading) { r in ReadingMode(planned: r.minutes).environmentObject(store) }
    }

    private func start(_ minutes: Int?, day: String) {
        if let minutes { store.planReading(minutes: minutes, from: NightRules.evening(store.nowMinute), on: day) }
        reading = ReadingStart(minutes: minutes)
    }

    // MARK: The whole evening

    private func full(_ day: String, minute: Int) -> some View {
        let plan = store.sleepPlan(for: day)
        let suggestion = store.readingSuggestion(minute: minute)
        let teeth = store.nightBrushHabits(on: day)
        let routine = store.nightRoutine(on: day)
        let prepare = store.nightPrepare(on: day)
        let read = store.nightRead(on: day)
        let readAnswer = store.nightReadAnswer(on: day)
        let hasRows = !teeth.isEmpty || prepare != nil || routine != nil || read != nil
        let planText: String = read == false && suggestion != nil ? "Ler até \(PlanFormat.at(suggestion?.until ?? 0)) · luzes \(PlanFormat.at(plan.perform))" : "Luzes \(PlanFormat.at(plan.perform))"
        return Screen(glow: .sleep) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Antes de dormir").font(.geist(26, .bold)).accessibilityIdentifier("night.bedtime.screen")
                Text("Acordas \(PlanFormat.at(store.profile.wakeMinute))").font(.geist(13)).foregroundStyle(Color.soft)
            }
            .padding(.top, 8)
            Card(state: .suggested) {
                HStack(spacing: 8) {
                    Eyebrow(text: "Plano para esta noite")
                    Spacer(minLength: 0)
                    StateTag(state: .suggested)
                }
                Text(planText).font(.geist(15))
                WhyLine(text: NightRules.planWhy(need: plan.need, fallAsleep: store.usualFallAsleep))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("night.plan")
            if hasRows {
                Card {
                    if !teeth.isEmpty { teethRow(teeth, day: day) }
                    if let prepare { prepareRow(done: prepare) }
                    if let routine { ForEach(routine.steps) { step in routineRow(step, of: routine, day: day) } }
                    if read != nil { readRow(answer: readAnswer, suggestion: suggestion, day: day) }
                }
            }
            Button { store.goingToSleep(minute: NightRules.evening(minute), on: day) } label: {
                Text("Vou dormir").font(.geist(16, .semibold)).foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(Pressable())
            .accessibilityHint("Regista a intenção de dormir, não o início do sono")
            .accessibilityIdentifier("night.sleep")
            Text("Nada aqui é obrigatório.").font(.geist(12)).foregroundStyle(Color.faint).frame(maxWidth: .infinity)
        }
    }

    /// `skip`: answered «Não fiz» or «Não se aplica», which shows as that: never a tick, never «feito»
    private func checkRow(_ title: String, sub: String, done: Bool, skip: (state: DataState, text: String)? = nil, id: String, action: @escaping () -> Void) -> some View {
        let icon: String = skip.map { skipIcon($0.state) } ?? (done ? "checkmark.circle.fill" : "circle")
        let spoken: String = skip?.text.lowercased() ?? (done ? "feito" : "por fazer")
        return Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(done && skip == nil ? Color.good : Color.soft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.geist(14)).foregroundStyle(Color.ink)
                    Text(sub).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let skip { StateTag(state: skip.state, text: skip.text) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(spoken)")
        .accessibilityIdentifier(id)
    }

    private func teethRow(_ habits: [PromiseItem], day: String) -> some View {
        let answer = store.nightTeethAnswer(on: day)
        let brushed = store.nightBrushMinute(on: day)
        let answered = habits.compactMap { store.logs["\($0.id)|\(day)"]?.at }.max()
        let done = answer == .done
        let sub: String
        if let brushed { sub = clock(brushed) }
        else if answer != nil, let answered { sub = clock(Day.minuteOfDay(Date(timeIntervalSince1970: answered / 1000))) }
        else { sub = done ? "feito" : "2 min" }
        return checkRow("Lavar os dentes", sub: sub, done: done, skip: NightRules.skipTag(answer), id: "night.step.teeth") { if answer == nil { store.markTeethDone(on: day) } }
    }

    @ViewBuilder private func prepareRow(done: Bool) -> some View {
        if done {
            checkRow("Preparar amanhã", sub: "feito", done: true, id: "night.step.prepare") {}
        } else {
            NavigationLink { PrepTomorrowView(close: close) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "circle").font(.system(size: 22)).foregroundStyle(Color.soft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preparar amanhã").font(.geist(14)).foregroundStyle(Color.ink)
                        Text("roupa e saco de treino").font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("night.step.prepare")
        }
    }

    private func routineRow(_ step: RoutineStep, of routine: CareRoutine, day: String) -> some View {
        let at = store.doneSteps(routine, on: day)[step.id]
        let product = step.productId.flatMap { store.record(CareProduct.self, $0) }
        let sub: String = at.map { clock(Day.minuteOfDay(Date(timeIntervalSince1970: $0 / 1000))) } ?? product?.name ?? CareRules.stepLength(step.seconds)
        return checkRow(step.title, sub: sub, done: at != nil, id: "night.step.routine.\(step.id)") {
            if at == nil { store.confirmNightStep(step, of: routine, on: day) }
        }
    }

    private func readRow(answer: ReviewAnswer?, suggestion: (minutes: Int, until: Int)?, day: String) -> some View {
        let done = answer == .done
        let skip = NightRules.skipTag(answer)
        let parts: [String] = [store.currentBook?.title, suggestion.map { "\($0.minutes) min sugeridos" }].compactMap { $0 }
        let answered = store.readHabits(on: day).compactMap { store.logs["\($0.id)|\(day)"]?.at }.max()
        let icon: String = skip.map { skipIcon($0.state) } ?? (done ? "checkmark.circle.fill" : "circle")
        let sub: String
        if done { sub = "feito" }
        else if skip != nil { sub = answered.map { clock(Day.minuteOfDay(Date(timeIntervalSince1970: $0 / 1000))) } ?? "" }
        else { sub = parts.isEmpty ? "quando quiseres" : parts.joined(separator: " · ") }
        return HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(done ? Color.good : Color.soft)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ler").font(.geist(14))
                Text(sub).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let skip { StateTag(state: skip.state, text: skip.text) }
            if answer == nil {
                Button { start(suggestion?.minutes, day: day) } label: {
                    Label("Começar", systemImage: "play.fill").font(.geist(13, .semibold)).foregroundStyle(Color(hex: 0x2B1A05))
                        .padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().fill(Area.read.gradient))
                }
                .buttonStyle(Pressable())
                .accessibilityIdentifier("night.read.start")
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: Late: only the essentials

    private func short(_ day: String, minute: Int) -> some View {
        let teethOpen = store.nightTeeth(on: day) == false
        let routine = store.nightRoutine(on: day)
        let step = routine.flatMap { r in store.pendingSteps(r, on: day).first }
        let anything = teethOpen || step != nil
        let minutes = NightRules.shortMinutes(teeth: teethOpen, stepSeconds: step?.seconds)
        return Screen(glow: .sleep) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Só o essencial").font(.geist(26, .bold)).accessibilityIdentifier("night.bedtime.short")
                Text("Antes de dormir · são \(clock(minute))").font(.geist(13)).foregroundStyle(Color.soft)
            }
            .padding(.top, 8)
            Text(anything ? "Ficou tarde. Se quiseres, só isto, cerca de \(minutes) min." : "Ficou tarde. O essencial já está feito.")
                .font(.geist(14)).foregroundStyle(Color.soft)
            if anything {
                Card {
                    if teethOpen { checkRow("Lavar os dentes", sub: "2 min", done: false, id: "night.step.teeth") { store.markTeethDone(on: day) } }
                    if let routine, let step {
                        checkRow(step.title, sub: CareRules.stepLength(step.seconds), done: false, id: "night.step.routine.\(step.id)") {
                            store.confirmNightStep(step, of: routine, on: day)
                        }
                    }
                }
            }
            Text("Leitura, diário e pele ficam para outro dia, sem marca de falha.").font(.geist(12)).foregroundStyle(Color.faint)
            PrimaryButton(title: "Vou dormir", area: .sleep) { store.goingToSleep(minute: NightRules.evening(minute), on: day) }
                .accessibilityIdentifier("night.sleep")
            Button { start(10, day: day) } label: {
                Text("Ler 10 min primeiro").font(.geist(14, .semibold)).foregroundStyle(Color.soft).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("night.read.short")
        }
    }
}

/// Boa noite (N_BoaNoite): a short calm message, when you wake and tomorrow's essentials, and an easy way out. No new
/// task. The intention's time is said for what it is.
struct GoodNightView: View {
    @EnvironmentObject var store: Store
    var day: String
    var intent: SleepIntent
    var close: () -> Void

    var body: some View {
        let source = store.profile.usesBand ? "do \(store.device?.name ?? "Fitbit")" : "do Apple Health"
        ZStack {
            Color(hex: 0x0A0A18).ignoresSafeArea()
            VStack(spacing: 14) {
                Spacer(minLength: 40)
                Text("Boa noite.").font(.geist(34, .semibold)).foregroundStyle(Color(hex: 0xD9DCF2)).accessibilityIdentifier("night.goodnight")
                Text("Acordas \(PlanFormat.at(store.profile.wakeMinute))").font(.geist(15, .medium)).foregroundStyle(Color.soft)
                Text(NightRules.tomorrowText(store.dayParts(Day.add(1, to: day)))).font(.geist(13)).foregroundStyle(Color.faint).multilineTextAlignment(.center)
                Spacer(minLength: 40)
                Button { close() } label: {
                    Text("Fechar").font(.geist(15, .semibold)).foregroundStyle(Color.soft).frame(minWidth: 120, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("night.goodnight.close")
                Text("Registei a intenção \(PlanFormat.at(intent.minute)). O sono real chega \(source) de manhã.")
                    .font(.geist(11)).foregroundStyle(Color.faint).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}

// MARK: - The morning

/// On Today in the morning: last night's sleep in one line, with its source, or «Sem dados»; a tap opens Como dormiste
struct SleepMorningLine: View {
    @EnvironmentObject var store: Store
    var open: () -> Void

    var body: some View {
        let day = Day.today
        let manual = store.sleepManual(day)
        let band = store.health[day]?.sleep
        Button(action: open) {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz").foregroundStyle(Color.sleep).frame(width: 22).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Como dormiste").font(.geist(14, .semibold)).foregroundStyle(Color.ink)
                        if let manual {
                            HStack(spacing: 6) {
                                Text("\(clock(manual.bed))–\(clock(manual.wake))").font(.geist(12)).foregroundStyle(Color.soft)
                                StateTag(state: .confirmed, text: "Registo teu")
                            }
                        } else if let band {
                            HStack(spacing: 6) {
                                Text(duration(band.asleep)).font(.geist(12)).foregroundStyle(Color.soft)
                                SourceLine(text: store.sleepSourceName)
                            }
                        } else {
                            HStack(spacing: 6) {
                                StateTag(state: .noData)
                                Text("podes registar tu, se quiseres").font(.geist(12)).foregroundStyle(Color.soft)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint)
                }
            }
        }
        .buttonStyle(Pressable())
        .accessibilityIdentifier("night.morning.open")
    }
}

/// Como dormiste (N_SonoManha): the night with its source in sight, the intention kept apart, the bedtime habit as it
/// was answered (imported from the band, or yours), and «Corrigir» or «Sem pulseira?» saving the hours as yours. The
/// app never makes up hours or sleep stages.
struct SleepMorningView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var correcting = false
    @State private var bed = ""
    @State private var wake = ""

    var body: some View {
        let day = Day.today
        let evening = Day.add(-1, to: day)
        let band = store.health[day]?.sleep
        let manual = store.sleepManual(day)
        let hasData = band != nil || manual != nil
        NavigationStack {
            Screen(glow: .sleep) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Como dormiste").font(.geist(26, .bold)).accessibilityIdentifier("night.morning.screen")
                    Text("Noite de \(weekday(evening)) para \(weekday(day))").font(.geist(13)).foregroundStyle(Color.soft)
                }
                .padding(.top, 8)
                if let manual { manualCard(manual, band: band) } else if let band { bandCard(band, evening: evening) }
                if band != nil, manual == nil, store.profile.usesBand {
                    Card {
                        Eyebrow(text: "Apple Health")
                        Text("Se o mesmo sono estiver no Apple Health, vindo do \(store.sleepSourceName), conta uma vez: o sono vem só do \(store.sleepSourceName).").font(.geist(13))
                    }
                }
                if correcting || !hasData { entryCard(day, hasData: hasData) }
                habitsCard(evening)
                PrimaryButton(title: "Continuar para Hoje") { dismiss() }.accessibilityIdentifier("night.morning.continue")
                if hasData, !correcting {
                    Button { prefill(band: band, manual: manual); correcting = true } label: {
                        Text("Corrigir").font(.geist(14, .semibold)).foregroundStyle(Color.soft).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("night.morning.correct")
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay(alignment: .bottom) { UndoBar() }
    }

    private func weekday(_ day: String) -> String { Day.date(day).formatted(.dateTime.weekday(.wide)) }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.geist(11)).foregroundStyle(Color.faint)
            Text(value).font(.geist(17, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    private func bandCard(_ s: SleepRecord, evening: String) -> some View {
        Card {
            HStack(spacing: 8) {
                Eyebrow(text: "Sono")
                SourceLine(text: store.sleepSourceName)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                field("Adormeceste", clock(Day.minuteOfDay(s.startDate)))
                field("Acordaste", clock(Day.minuteOfDay(s.endDate)))
                field("Dormiste", duration(s.asleep))
            }
            if s.stages != nil { Text("Fases do sono: as do \(store.sleepSourceName). A app não as calcula.").font(.geist(12)).foregroundStyle(Color.soft) }
            if let i = store.sleepIntent(evening) {
                Text("«Vou dormir» \(PlanFormat.at(i.minute)) foi a tua intenção; não entra nestas contas.").font(.geist(12)).foregroundStyle(Color.soft)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("night.morning.band")
    }

    private func manualCard(_ m: SleepManual, band: SleepRecord?) -> some View {
        Card {
            HStack(spacing: 8) {
                Eyebrow(text: "Sono")
                StateTag(state: .confirmed, text: "Registo teu")
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                field("Deitaste-te", clock(m.bed))
                field("Acordaste", clock(m.wake))
                field("Na cama", duration(NightRules.span(bed: m.bed, wake: m.wake)))
            }
            if let band {
                Text("\(store.sleepSourceName): \(clock(Day.minuteOfDay(band.startDate)))–\(clock(Day.minuteOfDay(band.endDate))). Ficam as tuas horas; os dados da pulseira não mudam.")
                    .font(.geist(12)).foregroundStyle(Color.soft)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("night.morning.manual")
    }

    private func entryCard(_ day: String, hasData: Bool) -> some View {
        let b = NightRules.parseClock(bed), w = NightRules.parseClock(wake)
        return Card(state: hasData ? .plain : .noData) {
            HStack(spacing: 8) {
                Eyebrow(text: hasData ? "Corrigir" : "Sem pulseira?")
                Spacer(minLength: 0)
                if !hasData { StateTag(state: .noData) }
            }
            Text(hasData ? "Escreve as horas certas: ficam marcadas como registo teu." : "Sem dados de sono desta noite. Se quiseres, diz quando te deitaste e acordaste: fica marcado como registo teu.")
                .font(.geist(13)).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                timeField("Deitaste-te às", text: $bed, id: "night.morning.bed")
                timeField("Acordaste às", text: $wake, id: "night.morning.wake")
            }
            Button {
                if let b, let w { store.saveSleepManual(bed: b, wake: w, on: day); correcting = false }
            } label: {
                Text("Guardar").font(.geist(13, .semibold)).foregroundStyle(Color(hex: 0x05140F))
                    .padding(.horizontal, 18).frame(minHeight: 44).background(Capsule().fill(Area.mint.gradient))
            }
            .buttonStyle(Pressable())
            .disabled(b == nil || w == nil)
            .opacity(b == nil || w == nil ? 0.5 : 1)
            .accessibilityIdentifier("night.morning.save")
        }
    }

    private func timeField(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.geist(11)).foregroundStyle(Color.faint)
            TextField("hh:mm", text: text).font(.geist(17, .semibold)).keyboardType(.numbersAndPunctuation).frame(minHeight: 44)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func prefill(band: SleepRecord?, manual: SleepManual?) {
        if let manual { bed = clock(manual.bed); wake = clock(manual.wake) }
        else if let band { bed = clock(Day.minuteOfDay(band.startDate)); wake = clock(Day.minuteOfDay(band.endDate)) }
    }

    /// The bedtime habit as it was answered: «Importado» when the band ticked it, «Confirmado» when you did, and «Não
    /// fiz» or «Não se aplica» when that was the answer
    @ViewBuilder private func habitsCard(_ evening: String) -> some View {
        let rows = store.bedtimeHabits(on: evening).compactMap { p -> HabitAnswer? in
            let origin = store.answerOrigin(p, on: evening)
            guard let tag = NightRules.answerTag(origin, store.reviewAnswer(p, on: evening)) else { return nil }
            return HabitAnswer(promise: p, state: tag.state, text: tag.text, imported: NightRules.answerState(origin) == .imported)
        }
        if !rows.isEmpty {
            Card {
                Eyebrow(text: "Hora de deitar")
                ForEach(rows) { r in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.promise.title).font(.geist(14))
                            Text(r.imported ? "marcado com os dados da pulseira, não por ti" : "respondido por ti").font(.geist(12)).foregroundStyle(Color.soft)
                        }
                        Spacer(minLength: 4)
                        StateTag(state: r.state, text: r.text)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("night.morning.habit.\(r.promise.id)")
                }
            }
        }
    }
}
