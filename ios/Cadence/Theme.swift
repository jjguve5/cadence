// The look from the concept: near-black, soft glass cards, one gradient per area, rings.
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
    static let bg = Color(hex: 0x07090E)
    static let ink = Color(hex: 0xEEF1F7)
    static let soft = Color(hex: 0xA3ABBD)
    static let faint = Color(hex: 0x687186)
    static let mint = Color(hex: 0x34E0B4), mint2 = Color(hex: 0x12A39B)
    static let water = Color(hex: 0x3FD2FF), water2 = Color(hex: 0x2F78FF)
    static let train = Color(hex: 0xFF5F6D), train2 = Color(hex: 0xD9378E)
    static let fuel = Color(hex: 0xFFB547), fuel2 = Color(hex: 0xFF7444)
    static let sleep = Color(hex: 0x8B7BFF), sleep2 = Color(hex: 0x4E40D8)
    static let read = Color(hex: 0xF1C779), read2 = Color(hex: 0xC98B3A)
    static let mind = Color(hex: 0xC592FF)
    static let good = Color(hex: 0x46D887), warn = Color(hex: 0xFFBD4A), bad = Color(hex: 0xFF6B6B)
}

enum Area {
    case mint, water, train, fuel, sleep, read, mind
    var colors: [Color] {
        switch self {
        case .mint: return [.mint, .mint2]
        case .water: return [.water, .water2]
        case .train: return [.train, .train2]
        case .fuel: return [.fuel, .fuel2]
        case .sleep: return [.sleep, .sleep2]
        case .read: return [.read, .read2]
        case .mind: return [.mind, .sleep2]
        }
    }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
    var glow: Color { colors[0] }
}

struct Card<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(tint.map { LinearGradient(colors: [$0.opacity(0.18), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing) }
                          ?? LinearGradient(colors: [.white.opacity(0.055), .white.opacity(0.055)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tint?.opacity(0.35) ?? .white.opacity(0.07), lineWidth: 1))
    }
}

struct Eyebrow: View {
    var text: String
    var icon: String? = nil
    var color: Color = .soft
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
            Text(text.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.8)
        }
        .foregroundStyle(color)
    }
}

struct Chip: View {
    var text: String
    var color: Color = .ink
    var fill: Color = .white.opacity(0.08)
    var body: some View {
        Text(text).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5).background(Capsule().fill(fill))
    }
}

struct Ring: View {
    var progress: Double
    var area: Area
    var width: CGFloat = 7
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: width)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: area.colors + [area.colors[0]], center: .center), style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct Bar: View {
    var progress: Double
    var area: Area
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(LinearGradient(colors: area.colors, startPoint: .leading, endPoint: .trailing)).frame(width: max(6, g.size.width * min(1, max(0, progress))))
            }
        }.frame(height: 6)
    }
}

struct Screen<Content: View>: View {
    var glow: Color
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(
            ZStack {
                Color.bg
                RadialGradient(colors: [glow.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 420)
            }.ignoresSafeArea()
        )
    }
}

struct Title: View {
    var eyebrow: String
    var title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow).font(.system(size: 13)).foregroundStyle(Color.soft)
            Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(Color.ink)
        }
    }
}

struct PrimaryButton: View {
    var title: String
    var area: Area = .mint
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(hex: 0x032018))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(area.gradient))
        }
        .buttonStyle(.plain)
    }
}

struct SoftButton: View {
    var title: String
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func cadenceList() -> some View {
        self.scrollContentBackground(.hidden).background(Color.bg.ignoresSafeArea())
    }
}
