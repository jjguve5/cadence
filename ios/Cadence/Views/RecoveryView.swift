// Shown instead of the app when the data file can't be read or a save failed. Nothing here writes over the original:
// every way out keeps it, and changes stay blocked until the data is safe again. In Portuguese (Portugal).
import SwiftUI

struct RecoveryView: View {
    @EnvironmentObject var store: Store
    @State private var confirming: LocalCopy?
    @State private var message: String?

    var body: some View {
        Screen(glow: .warn) {
            Title(eyebrow: "Os teus dados estão protegidos", title: headline).padding(.top, 8)
            switch store.storage {
            case .protected(let problem): protectedCards(problem)
            case .unsaved(let why): unsavedCards(why)
            case .ok: EmptyView()
            }
            if let message {
                Card { Text(message).font(.geist(13.5)).foregroundStyle(Color.ink) }
            }
        }
        .alert("Recuperar esta cópia?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), presenting: confirming) { copy in
            Button("Recuperar") { recover(copy) }
            Button("Cancelar", role: .cancel) {}
        } message: { copy in
            Text("Cópia de \(copy.date.formatted(date: .abbreviated, time: .shortened)), com \(copy.records) registos. O ficheiro atual é guardado à parte antes, por isso podes desfazer.")
        }
        .accessibilityIdentifier("recovery.screen")
    }

    private var headline: String {
        if case .unsaved = store.storage { return "Não foi possível guardar" }
        return "Não foi possível ler os dados"
    }

    @ViewBuilder
    private func protectedCards(_ p: StorageProblem) -> some View {
        Card(tint: .warn) {
            Text(explanation(p)).font(.geist(14)).foregroundStyle(Color.ink)
            if !p.categories.isEmpty {
                Text("Partes afetadas: " + Array(Set(p.categories.map(Storage.name(ofCategory:)))).sorted().joined(separator: ", "))
                    .font(.geist(13)).foregroundStyle(Color.soft)
            }
            if !p.detail.isEmpty { Text("Detalhe: \(p.detail)").font(.geist(12)).foregroundStyle(Color.faint) }
            Text("Nada foi apagado nem gravado por cima. Até isto ficar resolvido, o Cadence não guarda nem sincroniza alterações.")
                .font(.geist(13)).foregroundStyle(Color.soft)
        }
        Card {
            SoftButton(title: "Tentar outra vez", icon: "arrow.clockwise") { store.retryLoad() }
                .accessibilityIdentifier("recovery.retry")
            if FileManager.default.fileExists(atPath: store.dataFileURL.path) {
                ShareLink(item: store.dataFileURL) {
                    Label("Exportar o ficheiro original", systemImage: "square.and.arrow.up").font(.geist(13.5, .semibold))
                }
            }
        }
        Card {
            Eyebrow(text: "Cópias locais validadas", icon: "clock.arrow.circlepath")
            if store.localCopies.isEmpty {
                Text("Ainda não há cópias locais neste iPhone.").font(.geist(13)).foregroundStyle(Color.soft)
            }
            ForEach(store.localCopies) { copy in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.date.formatted(date: .abbreviated, time: .shortened)).font(.geist(14))
                        Text("\(copy.records) registos" + (copy.beforeUpdate ? " · antes de uma atualização" : "")).font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer()
                    Button("Recuperar") { confirming = copy }.font(.geist(13.5, .semibold)).frame(minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder
    private func unsavedCards(_ why: String) -> some View {
        Card(tint: .warn) {
            Text(why).font(.geist(14)).foregroundStyle(Color.ink)
            Text(store.unsaved.isEmpty ? "Não há alterações por guardar." : "Alterações por guardar: \(store.unsavedSummary).")
                .font(.geist(13)).foregroundStyle(Color.soft)
            Text("Até ficar resolvido, o Cadence não aceita novas alterações, para não as perderes.").font(.geist(13)).foregroundStyle(Color.soft)
        }
        Card {
            SoftButton(title: "Tentar guardar outra vez", icon: "arrow.clockwise") { store.retrySave() }
                .accessibilityIdentifier("recovery.retrySave")
            ShareLink(item: store.exportJSON(), preview: SharePreview("Cadence export.json")) {
                Label("Exportar tudo, incluindo o que está por guardar", systemImage: "square.and.arrow.up").font(.geist(13.5, .semibold))
            }
        }
    }

    private func explanation(_ p: StorageProblem) -> String {
        switch p.kind {
        case .cannotOpen: return "O ficheiro de dados existe, mas o iPhone não deixou abri-lo. Acontece, por exemplo, logo depois de reiniciar, antes do primeiro desbloqueio."
        case .corrupt: return "O ficheiro de dados está danificado e não se consegue ler."
        case .incompatible: return "Esta versão do Cadence não consegue ler uma parte dos teus dados."
        }
    }

    private func recover(_ copy: LocalCopy) {
        do {
            try store.recover(from: copy)
            message = nil
        } catch {
            message = (error as? StorageError)?.message ?? "Não foi possível recuperar: \(error.localizedDescription). Nada foi alterado."
        }
    }
}
