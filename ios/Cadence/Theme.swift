// The look from the concept: near-black, soft glass cards, one gradient per area, rings.
import SwiftUI

extension Font {
    /// Geist for text, Geist Mono for numbers, Instrument Serif for display: the concept's type
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Geist-Bold"
        case .semibold: name = "Geist-SemiBold"
        case .medium: name = "Geist-Medium"
        default: name = "Geist-Regular"
        }
        return .custom(name, size: size)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(weight == .regular || weight == .light ? "GeistMono-Regular" : "GeistMono-Medium", size: size)
    }
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font { .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size) }
}

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
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(LinearGradient(colors: [tint?.opacity(0.45) ?? .white.opacity(0.11), tint?.opacity(0.15) ?? .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

struct Eyebrow: View {
    var text: String
    var icon: String? = nil
    var color: Color = .soft
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.geist(10, .semibold)) }
            Text(text.uppercased()).font(.geist(10.5, .semibold)).tracking(0.8)
        }
        .foregroundStyle(color)
    }
}

struct Chip: View {
    var text: String
    var color: Color = .ink
    var fill: Color = .white.opacity(0.08)
    var body: some View {
        Text(text).font(.geist(11.5, .semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(fill).overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 1)))
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
            Text(eyebrow).font(.geist(13)).foregroundStyle(Color.soft)
            Text(title).font(.geist(31, .bold)).tracking(-0.8).foregroundStyle(Color.ink)
        }
    }
}

struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    var title: String
    var area: Area = .mint
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.geist(16, .semibold)).tracking(-0.2).foregroundStyle(Color(hex: 0x05140F))
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(area.gradient)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center)))
                )
                .shadow(color: area.glow.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(Pressable())
    }
}

/// The round gradient play button from the concept
struct PlayButton: View {
    var icon = "play.fill"
    var area: Area = .mint
    var size: CGFloat = 44
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(Color(hex: 0x05140F))
                .frame(width: size, height: size)
                .background(Circle().fill(area.gradient).overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center))))
                .shadow(color: area.glow.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(Pressable())
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
            .font(.geist(13.5, .semibold)).foregroundStyle(Color.ink)
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.09))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
            )
        }
        .buttonStyle(Pressable())
    }
}

extension View {
    func cadenceList() -> some View {
        self.scrollContentBackground(.hidden).background(Color.bg.ignoresSafeArea())
    }
}
