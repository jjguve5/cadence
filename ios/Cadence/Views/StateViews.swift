// Shared pieces of the design's state system (artifact v17, «Estados · legenda» and «Componentes e verbos»): a state
// label with its own icon and word (never colour alone), the «Porquê» line, the imported-source line, an estimate
// mark, the Aceitar · Ajustar · Ignorar trio, a segmented choice and the Desfazer bar (only the last action, 5 s).
import SwiftUI
import UIKit

/// What a piece of information is. The first six are the system's; the rest are specialised states that keep the
/// meaning of their family (a draft or a load in the wash is pending; unavailable or ignored is off).
enum DataState: String, CaseIterable {
    case confirmed, imported, estimated, suggested, pending, noData
    case draft, partial, unavailable, washing, drying, done, ignored, setup, error, locked

    var label: String {
        switch self {
        case .confirmed: return "Confirmado"
        case .imported: return "Importado"
        case .estimated: return "Estimado"
        case .suggested: return "Sugerido"
        case .pending: return "Pendente"
        case .noData: return "Sem dados"
        case .draft: return "Rascunho"
        case .partial: return "Parcial"
        case .unavailable: return "Indisponível"
        case .washing: return "Em lavagem"
        case .drying: return "A secar"
        case .done: return "Concluído"
        case .ignored: return "Ignorado"
        case .setup: return "Por configurar"
        case .error: return "Erro"
        case .locked: return "Privado"
        }
    }

    /// Each state has its own icon, so it reads without colour
    var icon: String {
        switch self {
        case .confirmed, .done: return "checkmark"
        case .imported: return "arrow.down.to.line"
        case .estimated: return "water.waves"
        case .suggested: return "sparkle"
        case .pending: return "clock"
        case .noData: return "circle.dashed"
        case .draft: return "pencil"
        case .partial: return "circle.lefthalf.filled"
        case .unavailable: return "slash.circle"
        case .washing: return "drop"
        case .drying: return "wind"
        case .ignored: return "minus"
        case .setup: return "plus"
        case .error: return "exclamationmark.triangle"
        case .locked: return "lock"
        }
    }

    enum Family { case confirmed, imported, estimated, suggested, pending, noData, off, error }

    var family: Family {
        switch self {
        case .confirmed, .done: return .confirmed
        case .imported: return .imported
        case .estimated: return .estimated
        case .suggested: return .suggested
        case .pending, .draft, .partial, .washing, .drying: return .pending
        case .noData, .setup: return .noData
        case .unavailable, .ignored, .locked: return .off
        case .error: return .error
        }
    }

    var color: Color {
        switch family {
        case .confirmed: return Color(hex: 0x46D887)
        case .imported: return Color(hex: 0x5CCBF0)
        case .estimated: return Color(hex: 0xC3A2FF)
        case .suggested: return Color(hex: 0xFF8FC8)
        case .pending: return Color(hex: 0xFFBD4A)
        case .noData: return Color(hex: 0xA3ABBD)
        case .off: return Color(hex: 0x98A1B3)
        case .error: return Color(hex: 0xFF7A85)
        }
    }
}

/// The state label: icon and word in the state's colour; «Sem dados» has a dashed outline instead of a fill
struct StateTag: View {
    var state: DataState
    var text: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.icon).font(.system(size: 9.5, weight: .bold))
            Text(text ?? state.label).font(.geist(11, .semibold)).lineLimit(1)
        }
        .foregroundStyle(state.color)
        .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 4)
        .background {
            if state.family == .noData {
                Capsule().strokeBorder(Color.white.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            } else {
                Capsule().fill(state.family == .off ? Color.white.opacity(0.07) : state.color.opacity(0.13))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// «Porquê» and a short reason under a recommendation or a number
struct WhyLine: View {
    var text: String
    var label = "Porquê"
    var body: some View {
        (Text(label + " ").font(.geist(12, .semibold)).foregroundColor(.ink) + Text(text).font(.geist(12)).foregroundColor(.soft))
            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }
}

/// Where an imported value came from ("Fitbit · há 2 h")
struct SourceLine: View {
    var text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: DataState.imported.icon).font(.system(size: 9, weight: .bold)).foregroundStyle(DataState.imported.color)
            Text(text).font(.geist(11)).foregroundStyle(Color.faint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Importado: \(text)")
    }
}

/// An estimated value: «≈ value» with a dotted underline in the estimate colour
struct EstimatedText: View {
    var value: String
    var body: some View {
        Text("≈ \(value)").underline(pattern: .dot, color: DataState.estimated.color.opacity(0.9))
            .accessibilityLabel("cerca de \(value), estimado")
    }
}

/// The answer to a suggestion: Aceitar applies (and shows Desfazer), Ajustar opens the options first, Ignorar leaves
/// no mark and no penalty
struct DecisionButtons: View {
    var accept = "Aceitar", adjust: String? = "Ajustar", ignore = "Ignorar"
    var onAccept: () -> Void
    var onAdjust: (() -> Void)? = nil
    var onIgnore: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAccept) {
                Text(accept).font(.geist(13, .semibold)).foregroundStyle(Color(hex: 0x05140F))
                    .padding(.horizontal, 14).frame(minHeight: 36).background(Capsule().fill(Area.mint.gradient))
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            if let adjust, let onAdjust {
                Button(action: onAdjust) {
                    Text(adjust).font(.geist(13, .semibold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 14).frame(minHeight: 36).background(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
            }
            Button(action: onIgnore) {
                Text(ignore).font(.geist(13, .semibold)).foregroundStyle(Color.soft).padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(Pressable())
    }
}

/// A segmented choice in the app's style (Dia · Semana · Mês)
struct Segments<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button { selection = value } label: {
                    Text(label).font(.geist(13, .semibold)).foregroundStyle(selection == value ? Color.ink : Color.soft)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selection == value ? Color.white.opacity(0.12) : .clear))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Desfazer

/// The one action that can still be undone. Only the last action: a new one replaces it; after `seconds` it can't be
/// undone here any more (the correction is then made on the record itself). Undo runs once.
@MainActor
final class UndoCenter: ObservableObject {
    static let shared = UndoCenter()
    struct Item: Identifiable { let id = UUID(); let text: String; let undo: () -> Void }

    @Published private(set) var current: Item?
    var seconds: Double = 5
    /// With VoiceOver on, the bar stays longer (reaching it takes more than a glance and a tap)
    var voiceOverSeconds: Double = 20
    private var expiry: Task<Void, Never>?

    func show(_ text: String, undo: @escaping () -> Void) {
        let item = Item(text: text, undo: undo)
        current = item
        expiry?.cancel()
        let voiceOver = UIAccessibility.isVoiceOverRunning
        if voiceOver { UIAccessibility.post(notification: .announcement, argument: "\(text). Desfazer disponível.") }
        let wait = voiceOver ? max(seconds, voiceOverSeconds) : seconds
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.expire(item.id)
        }
    }

    /// Undoes the current action, once
    func undo() {
        guard let item = current else { return }
        current = nil
        expiry?.cancel()
        item.undo()
    }

    func dismiss() { current = nil; expiry?.cancel() }

    func expire(_ id: UUID) { if current?.id == id { current = nil } }
}

/// The bar at the bottom: a check, what was done, and Desfazer
struct UndoBar: View {
    @ObservedObject var center = UndoCenter.shared
    var body: some View {
        ZStack { bar }.animation(.easeOut(duration: 0.2), value: center.current?.id)
    }

    @ViewBuilder private var bar: some View {
        if let item = center.current {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.good)
                Text(item.text).font(.geist(13)).foregroundStyle(Color.ink).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button("Desfazer") { center.undo() }.font(.geist(13, .semibold)).tint(.mint).frame(minHeight: 44).accessibilityIdentifier("undo.action")
            }
            .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x1C2029)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1)))
            .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
            .padding(.horizontal, 16).padding(.bottom, 58)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain).accessibilityIdentifier("undo.bar")
        }
    }
}
