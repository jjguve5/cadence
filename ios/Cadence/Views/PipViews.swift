// Pip: the Lottie animations from After Effects for the full body, the head renders for small places.
import Lottie
import SwiftUI

struct PipAnimation: View {
    var mood: PipMood
    @ObservedObject private var store = Store.shared

    var body: some View {
        let worn = store.pipOutfit
        var view = TestMode.active ? LottieView(animation: .named(mood.rawValue)).currentProgress(0.3) : LottieView(animation: .named(mood.rawValue)).looping()
        for a in worn { view = view.valueProvider(FloatValueProvider(100), for: AnimationKeypath(keypath: "\(a.layer).Transform.Opacity")) }
        return view.id(mood.rawValue + worn.map(\.id).joined())
    }
}

struct PipHead: View {
    var mood: PipMood
    var size: CGFloat = 40
    @ObservedObject private var store = Store.shared

    var body: some View {
        ZStack {
            Image(mood.head).resizable().scaledToFit()
            ForEach(store.pipOutfit.filter { $0.slot == "head" || $0.slot == "face" }) { a in Image("\(mood.head)-\(a.id)").resizable().scaledToFit() }
        }
        .frame(width: size, height: size)
    }
}

/// The page that opens when you tap Pip on Today
struct PipPage: View {
    @EnvironmentObject var store: Store
    @State private var tapped = false

    var body: some View {
        let mood = store.pipMood()
        let level = store.level
        Screen(glow: Color(hex: 0x8A5A1E)) {
            VStack(spacing: 4) {
                PipRoomView(mood: tapped ? .tapped : mood)
                    .padding(.bottom, 8)
                    .onTapGesture {
                        tapped = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { tapped = false }
                    }
                Text("«\(store.pipLine())»")
                    .font(.geist(15)).multilineTextAlignment(.center).foregroundStyle(Color.ink)
                    .padding(12).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xFFF3E3, opacity: 0.1)))
            }
            .frame(maxWidth: .infinity)

            Card {
                HStack { Eyebrow(text: "Como está o Pip"); Spacer(); Text(mood.label).font(.geist(14, .bold)).foregroundStyle(Color.good) }
                ForEach(store.pipReasons()) { r in
                    HStack {
                        Text(r.text).font(.geist(14))
                        Spacer()
                        if let good = r.good { Chip(text: good ? "+" : "−", color: good ? .good : .warn) }
                    }
                }
            }

            let lines = store.pointLines()
            Card {
                HStack {
                    Eyebrow(text: "Pontos de hoje")
                    Spacer()
                    Text("\(lines.filter(\.earned).map(\.points).reduce(0, +)) pts").font(.mono(12)).foregroundStyle(Color.soft)
                }
                ForEach(lines) { line in
                    HStack {
                        Image(systemName: line.earned ? "checkmark.circle.fill" : line.icon).foregroundStyle(line.earned ? Color.good : Color.soft).frame(width: 20)
                        Text(line.title).font(.geist(14)).foregroundStyle(line.earned ? Color.soft : Color.ink)
                        Spacer()
                        Chip(text: "+\(line.points)", color: line.earned ? .good : .ink)
                    }
                }
                Text("O que é mais difícil dá mais pontos. A dificuldade de cada hábito escolhes tu, ao editá-lo.").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            .accessibilityIdentifier("pip.points")

            Card(tint: .mint) {
                HStack {
                    Eyebrow(text: "Nível \(level.level) · \(store.totalPoints.formatted()) / \(level.next.formatted()) pts", color: .mint)
                    Spacer()
                    Text(pipAccessories.first { $0.level > level.level }.map { "Nível \($0.level): \($0.name.lowercased())" } ?? "Tudo desbloqueado").font(.geist(12)).foregroundStyle(Color.soft)
                }
                Bar(progress: Double(level.into) / Double(max(1, level.span)), area: .mint)
            }

            ChestCard()
            WardrobePicker()
            HousePicker()
            Text("O humor do Pip vem sempre do teu dia real. Nunca te faz sentir culpa: num dia mau, fica com sono ou um pouco triste e sugere uma pequena coisa que ajudaria.")
                .font(.geist(12)).foregroundStyle(Color.faint)
        }
        .navigationTitle("Pip")
        .navigationBarTitleDisplayMode(.inline)
    }
}
