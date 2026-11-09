// Pip's house, the chests and the collection (PipRewards.swift). A chest opens by shaking the phone three times, or by
// tapping it: tapping always works, so nothing here depends on being able to shake.
import CoreMotion
import SwiftUI
import UIKit

/// The room with Pip in it. Every layer's picture is the same square, so they only stack; Pip's own square is half the
/// room's, standing on the floor (pip_room.py draws the sample rooms the same way).
struct PipRoomView: View {
    @EnvironmentObject var store: Store
    var mood: PipMood

    var body: some View {
        GeometryReader { g in
            let side = g.size.width
            ZStack {
                ForEach(store.pipRoom()) { item in
                    Image("room-" + item.id).resizable().scaledToFit()
                }
                PipAnimation(mood: mood)
                    .frame(width: side * 0.5, height: side * 0.5)
                    .position(x: side * 0.5, y: side * 0.658)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A casa do Pip")
        .accessibilityIdentifier("pip.room")
    }
}

/// On Pip's page: the chests waiting, or how far the next one is
struct ChestCard: View {
    @EnvironmentObject var store: Store
    @State private var opening = false

    var body: some View {
        let ready = store.chestsReady
        let total = pipPrizes.count
        let have = total - store.pipMissing.count
        let toNext = store.pointsToNextChest
        Card(tint: .fuel) {
            HStack {
                Eyebrow(text: "Baús", icon: "gift.fill", color: .fuel)
                Spacer()
                Text("Coleção \(have) de \(total)").font(.geist(12)).foregroundStyle(Color.soft)
            }
            if have == total {
                Text("Coleção completa. Não há mais nada para ganhar.").font(.geist(14, .semibold))
            } else if ready.isEmpty {
                Text("Faltam \(toNext) pts para o próximo baú").font(.geist(14, .semibold))
                Bar(progress: Double(ChestRules.pointsPerChest - toNext) / Double(ChestRules.pointsPerChest), area: .fuel)
            } else {
                HStack(spacing: 8) {
                    ForEach(ChestKind.allCases) { kind in
                        let count = ready.filter { $0 == kind }.count
                        if count > 0 { Chip(text: "\(count) × \(kind.name)") }
                    }
                }
                PrimaryButton(title: ready.count == 1 ? "Abrir o baú" : "Abrir baús (\(ready.count))", area: .fuel) { opening = true }
                    .accessibilityIdentifier("pip.chest.open")
            }
            Text("Madeira: a cada \(ChestRules.pointsPerChest) pontos · Prata: ao subir de nível · Ouro: 7 dias fechados seguidos (\(store.goldRun) de 7)")
                .font(.geist(11.5)).foregroundStyle(Color.faint).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("pip.chests")
        .fullScreenCover(isPresented: $opening) { ChestOpenView().environmentObject(store) }
    }
}

/// Counts shakes of the phone from the accelerometer (no permission is needed for it). Not available on a simulator.
final class ShakeSensor: ObservableObject {
    @Published var count = 0
    private let manager = CMMotionManager()
    private var last = Date.distantPast

    var available: Bool { manager.isAccelerometerAvailable && !TestMode.active }

    func start() {
        guard available, !manager.isAccelerometerActive else { return }
        manager.accelerometerUpdateInterval = 1.0 / 30.0
        manager.startAccelerometerUpdates(to: OperationQueue.main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            let force = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() // 1 at rest
            if force > 1.9, Date().timeIntervalSince(self.last) > 0.25 {
                self.last = Date()
                self.count += 1
            }
        }
    }

    func stop() { manager.stopAccelerometerUpdates() }
}

/// A chest, closed. Drawn here so the three kinds only differ in colour.
struct ChestPicture: View {
    var kind: ChestKind

    private var colors: (main: UInt32, dark: UInt32, light: UInt32, band: UInt32) {
        switch kind {
        case .wood: return (0x9A6234, 0x734522, 0xB67A45, 0x5B6170)
        case .silver: return (0xAEB6C4, 0x8891A1, 0xD3D9E3, 0x5B6170)
        case .gold: return (0xF2B632, 0xD9931A, 0xFFD45E, 0x8A5A1E)
        }
    }

    var body: some View {
        let c = colors
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.07, style: .continuous).fill(Color(hex: c.dark))
                    .frame(width: w * 0.9, height: h * 0.5).position(x: w / 2, y: h * 0.72)
                RoundedRectangle(cornerRadius: w * 0.07, style: .continuous).fill(Color(hex: c.main))
                    .frame(width: w * 0.9, height: h * 0.44).position(x: w / 2, y: h * 0.7)
                UnevenRoundedRectangle(topLeadingRadius: w * 0.3, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: w * 0.3, style: .continuous)
                    .fill(Color(hex: c.light))
                    .frame(width: w * 0.94, height: h * 0.36).position(x: w / 2, y: h * 0.32)
                Rectangle().fill(Color(hex: c.band)).frame(width: w * 0.08, height: h * 0.72).position(x: w * 0.22, y: h * 0.58)
                Rectangle().fill(Color(hex: c.band)).frame(width: w * 0.08, height: h * 0.72).position(x: w * 0.78, y: h * 0.58)
                Rectangle().fill(Color(hex: c.band)).frame(width: w * 0.94, height: h * 0.05).position(x: w / 2, y: h * 0.5)
                Circle().fill(Color(hex: 0xFFC53D)).frame(width: w * 0.17, height: w * 0.17).position(x: w / 2, y: h * 0.53)
                Circle().fill(Color(hex: 0x4A3210)).frame(width: w * 0.05, height: w * 0.05).position(x: w / 2, y: h * 0.53)
            }
        }
    }
}

/// Opens the chests that are waiting, one at a time: three shakes (or taps), then what came out
struct ChestOpenView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sensor = ShakeSensor()
    @State private var kind: ChestKind?
    @State private var hits = 0
    @State private var wobble = 0.0
    @State private var prize: PipPrize?
    @State private var burst = false
    @State private var used = false

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            if let prize {
                RadialGradient(colors: [Color(hex: prize.rarity.hex, opacity: 0.45), .clear], center: .center, startRadius: 0, endRadius: 380).ignoresSafeArea()
            }
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    Button("Fechar") { dismiss() }.foregroundStyle(Color.soft).frame(minHeight: 44).accessibilityIdentifier("pip.chest.close")
                }
                Spacer()
                if let prize {
                    reveal(prize)
                } else if let kind {
                    closed(kind)
                } else {
                    Text("Não há baús por abrir.").font(.geist(16, .semibold)).foregroundStyle(Color.soft)
                }
                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            kind = store.chestsReady.first
            sensor.start()
        }
        .onDisappear { sensor.stop() }
        .onChange(of: sensor.count) { _, _ in hit() }
    }

    private func closed(_ kind: ChestKind) -> some View {
        VStack(spacing: 18) {
            Text(kind.name).font(.geist(24, .bold))
            ChestPicture(kind: kind)
                .frame(width: 220, height: 190)
                .rotationEffect(.degrees(wobble))
                .scaleEffect(1 + Double(hits) * 0.05)
                .onTapGesture { hit() }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Abanar o \(kind.name.lowercased())")
                .accessibilityIdentifier("pip.chest.shake")
            HStack(spacing: 8) {
                ForEach(0..<ChestRules.shakes, id: \.self) { n in
                    Circle().fill(n < hits ? Color.fuel : Color.white.opacity(0.15)).frame(width: 12, height: 12)
                }
            }
            Text(sensor.available ? "Abana o telemóvel para abrir" : "Toca no baú para abrir").font(.geist(15, .semibold))
            if sensor.available { Text("Ou toca no baú.").font(.geist(12)).foregroundStyle(Color.faint) }
        }
    }

    private func reveal(_ prize: PipPrize) -> some View {
        let colour = Color(hex: prize.rarity.hex)
        let more = store.chestsReady.count
        return VStack(spacing: 14) {
            if used {
                if prize.isRoom {
                    PipRoomView(mood: .celebrate).frame(maxWidth: 240)
                } else {
                    PipAnimation(mood: .celebrate).frame(width: 190, height: 190)
                }
            } else {
                ZStack {
                    ForEach(0..<10, id: \.self) { n in
                        Text(n % 2 == 0 ? "✨" : "⭐️").font(.system(size: 22))
                            .offset(x: burst ? cos(Double(n) * Double.pi / 5) * 150 : 0, y: burst ? sin(Double(n) * Double.pi / 5) * 150 : 0)
                            .opacity(burst ? 0 : 1)
                    }
                    Circle().fill(colour.opacity(0.22)).frame(width: 170, height: 170)
                    Text(prize.emoji).font(.system(size: 84))
                }
                .frame(height: 200)
                .accessibilityHidden(true)
            }
            Text(prize.rarity.label.uppercased()).font(.geist(12, .bold)).tracking(1.2).foregroundStyle(colour)
            Text(prize.name).font(.geist(26, .bold)).multilineTextAlignment(.center).accessibilityIdentifier("pip.chest.prize")
            Text(prize.place).font(.geist(13)).foregroundStyle(Color.soft)
            if used {
                Text(prize.isRoom ? "Já está na casa." : "O Pip já está a usar.").font(.geist(13, .semibold)).foregroundStyle(Color.good)
            } else {
                PrimaryButton(title: prize.isRoom ? "Pôr na casa" : "Vestir já", area: .fuel) {
                    store.use(prize)
                    withAnimation { used = true }
                }
                .accessibilityIdentifier("pip.chest.use")
            }
            if more > 0 {
                SoftButton(title: more == 1 ? "Abrir o outro baú" : "Abrir outro baú (\(more))", icon: "gift.fill") { next() }
                    .accessibilityIdentifier("pip.chest.next")
            } else {
                SoftButton(title: "Concluído") { dismiss() }.accessibilityIdentifier("pip.chest.done")
            }
        }
    }

    /// One shake or tap. The third opens the chest: what comes out is saved before it is shown.
    private func hit() {
        guard prize == nil, let kind else { return }
        hits += 1
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.spring(response: 0.12, dampingFraction: 0.25)) { wobble = hits % 2 == 0 ? -12 : 12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { wobble = 0 }
        }
        guard hits >= ChestRules.shakes else { return }
        guard let won = store.openChest(kind) else {
            self.kind = nil
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { prize = won }
        withAnimation(.easeOut(duration: 0.9)) { burst = true }
    }

    private func next() {
        prize = nil
        used = false
        burst = false
        hits = 0
        kind = store.chestsReady.first
    }
}

/// One piece in a picker: what it is when it's yours, dimmed with where it comes from when it isn't
struct PipPieceCell: View {
    var title: String
    var emoji: String?
    var icon: String
    var open: Bool
    var on: Bool
    var rarity: PipRarity?
    var locked: String
    var tap: () -> Void

    var body: some View {
        let ring: Color = on ? Color.mint : (rarity.map { Color(hex: $0.hex, opacity: open ? 0.75 : 0.3) } ?? Color.clear)
        Button(action: tap) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(.white.opacity(on ? 0.18 : 0.06))
                    if let emoji {
                        Text(emoji).font(.system(size: 24)).opacity(open ? 1 : 0.3)
                    } else {
                        Image(systemName: open ? icon : "lock.fill").font(.geist(18)).foregroundStyle(open ? Color.ink : Color.faint)
                    }
                }
                .frame(width: 50, height: 50)
                .overlay(Circle().stroke(ring, lineWidth: on ? 2.5 : 1.5))
                Text(open ? title : locked).font(.geist(10.5)).foregroundStyle(open ? Color.ink : Color.faint).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 78)
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel(open ? title : "\(title), por desbloquear: \(locked)")
    }
}

/// What Pip wears: the pieces by level, as before, and the ones from chests
struct WardrobePicker: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let have = pipAccessories.filter { store.owns($0) }.count
        Card(tint: .fuel) {
            HStack {
                Eyebrow(text: "Roupeiro do Pip", icon: "tshirt.fill", color: .fuel)
                Spacer()
                Text("\(have) de \(pipAccessories.count)").font(.geist(12)).foregroundStyle(Color.soft)
            }
            ForEach(["head", "face", "neck", "back"], id: \.self) { slot in
                Text(pipSlotName(slot)).font(.geist(11.5, .semibold)).foregroundStyle(Color.soft)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let worn = store.pipOutfit.first { $0.slot == slot }
                        PipPieceCell(title: "Nada", emoji: nil, icon: "xmark", open: true, on: worn == nil, rarity: nil, locked: "") { store.wear(nil, slot: slot) }
                        ForEach(pipAccessories.filter { $0.slot == slot }.sorted { store.owns($0) && !store.owns($1) }) { a in
                            PipPieceCell(title: a.name, emoji: a.emoji, icon: a.icon, open: store.owns(a), on: worn?.id == a.id, rarity: a.rarity,
                                         locked: a.rarity.map { "Baú · \($0.label)" } ?? "Nível \(a.level)") { store.wear(a, slot: slot) }
                        }
                    }
                }
            }
            Text("Cada peça fica vestida em todas as animações. Umas desbloqueias ao subir de nível, as outras saem dos baús.")
                .font(.geist(11.5)).foregroundStyle(Color.faint).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("pip.wardrobe")
    }
}

/// The house: one choice per slot. The wall, the floor and the window always have one.
struct HousePicker: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let room = store.pipRoom()
        let have = pipRoomItems.filter { store.owns($0) }.count
        Card(tint: .mint) {
            HStack {
                Eyebrow(text: "Casa do Pip", icon: "house.fill", color: .mint)
                Spacer()
                Text("\(have) de \(pipRoomItems.count)").font(.geist(12)).foregroundStyle(Color.soft)
            }
            ForEach(pipRoomSlots, id: \.self) { slot in
                Text(pipSlotName(slot)).font(.geist(11.5, .semibold)).foregroundStyle(Color.soft)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let placed = room.first { $0.slot == slot }
                        if pipRoomDefaults[slot] == nil {
                            PipPieceCell(title: "Nada", emoji: nil, icon: "xmark", open: true, on: placed == nil, rarity: nil, locked: "") { store.place(nil, slot: slot) }
                        }
                        ForEach(pipRoomItems.filter { $0.slot == slot }.sorted { store.owns($0) && !store.owns($1) }) { item in
                            PipPieceCell(title: item.name, emoji: item.emoji, icon: "house.fill", open: store.owns(item), on: placed?.id == item.id, rarity: item.rarity,
                                         locked: item.rarity.map { "Baú · \($0.label)" } ?? "") { store.place(item, slot: slot) }
                        }
                    }
                }
            }
            Text("A mobília, o papel de parede e o resto saem dos baús. Mudas tudo quando quiseres.")
                .font(.geist(11.5)).foregroundStyle(Color.faint).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("pip.house")
    }
}
