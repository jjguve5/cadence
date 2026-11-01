// Pip: the Lottie animations from After Effects for the full body, the head renders for small places.
import Lottie
import SwiftUI

struct PipAnimation: View {
    var mood: PipMood
    var body: some View {
        LottieView(animation: .named(mood.rawValue))
            .looping()
            .id(mood.rawValue)
    }
}

struct PipHead: View {
    var mood: PipMood
    var size: CGFloat = 40
    var body: some View {
        Image(mood.head).resizable().scaledToFit().frame(width: size, height: size)
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
                PipAnimation(mood: tapped ? .tapped : mood)
                    .frame(width: 190, height: 190)
                    .background(Circle().fill(LinearGradient(colors: store.backdrop.colors.map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom)).frame(width: 200, height: 200))
                    .onTapGesture {
                        tapped = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { tapped = false }
                    }
                Text("“\(store.pipLine())”")
                    .font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(Color.ink)
                    .padding(12).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xFFF3E3, opacity: 0.1)))
            }
            .frame(maxWidth: .infinity)

            Card {
                HStack { Eyebrow(text: "How Pip feels"); Spacer(); Text(mood.label).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.good) }
                ForEach(store.pipReasons()) { r in
                    HStack {
                        Text(r.text).font(.system(size: 14))
                        Spacer()
                        if let good = r.good { Chip(text: good ? "+" : "−", color: good ? .good : .warn) }
                    }
                }
            }

            let open = store.due().filter { store.status($0) == nil }
            if !open.isEmpty {
                Card {
                    HStack { Eyebrow(text: "Cheer Pip up today"); Spacer(); Text("+\(open.count * 10) pts").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.soft) }
                    ForEach(open) { p in
                        HStack {
                            Image(systemName: p.icon).foregroundStyle(Color.soft).frame(width: 20)
                            Text(p.title).font(.system(size: 14))
                            Spacer()
                            Chip(text: "+10")
                        }
                    }
                }
            }

            Card(tint: .mint) {
                HStack {
                    Eyebrow(text: "Level \(level.level) · \(store.totalPoints.formatted()) / \(level.next.formatted()) pts", color: .mint)
                    Spacer()
                    Text("Level \(level.level + 1): a new leaf").font(.system(size: 12)).foregroundStyle(Color.soft)
                }
                Bar(progress: Double(level.into) / Double(max(1, level.span)), area: .mint)
            }

            BackdropPicker()
            Text("Pip's mood always comes from your real day. It never guilt-trips you: on a bad day it gets sleepy or a little sad and names one small thing that would help.")
                .font(.system(size: 12)).foregroundStyle(Color.faint)
        }
        .navigationTitle("Pip")
        .navigationBarTitleDisplayMode(.inline)
    }
}
