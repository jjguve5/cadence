// Antes de sair (phase 2.9, design v17 N_AntesDeSair and N_AntesDeSairPronto, decisions 9–16): what's still to see
// first, grouped into «Essencial» and «Se quiseres», what you've seen closed in one line. Tapping marks an item as
// taken; «Concluído» marks the rest, with Desfazer, and shows «Pronto para sair», with the list a tap away. Your list
// can be edited; what you remove doesn't come back. The rules and records are in Night.swift.
import SwiftUI

struct LeaveView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LeaveRules.reminderKey) private var remind = true
    @State private var reopened = false
    @State private var editingList = false
    @State private var seenOpen = false
    @State private var editing: LeaveItem? = nil

    var body: some View {
        let day = Day.today
        let entries = store.leaveEntries(on: day)
        let pending = entries.filter { !$0.seen }
        let ready = !entries.isEmpty && pending.isEmpty && !reopened
        NavigationStack {
            Screen(glow: .fuel) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Antes de sair").font(.geist(26, .bold)).accessibilityIdentifier("leave.screen")
                    Text(ready ? Date().formatted(.dateTime.weekday(.wide).day().month(.wide)) : "Só o que falta hoje").font(.geist(13)).foregroundStyle(Color.soft)
                }
                .padding(.top, 8)
                if ready { readyCard(entries, day: day) } else { list(entries, pending: pending, day: day) }
                resolvedLine(day)
                if !ready, !pending.isEmpty {
                    VStack(spacing: 6) {
                        PrimaryButton(title: "Concluído") { store.finishLeaving(on: day); reopened = false }.accessibilityIdentifier("leave.done")
                        Text("Marca os que faltam como levados. Podes desfazer.").font(.geist(12)).foregroundStyle(Color.faint).frame(maxWidth: .infinity)
                    }
                }
                if ready || editingList { editCard } else {
                    Button { editingList = true } label: {
                        Text("Editar a lista").font(.geist(13, .semibold)).foregroundStyle(Color.ink).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("leave.editlist")
                }
                reminderCard(day)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() }.accessibilityIdentifier("leave.close") }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay(alignment: .bottom) { UndoBar() }
        .sheet(item: $editing) { LeaveItemEditor(item: $0).environmentObject(store) }
    }

    // MARK: The list

    @ViewBuilder private func list(_ entries: [LeaveEntry], pending: [LeaveEntry], day: String) -> some View {
        let essential = pending.filter { $0.item.optional != true }
        let optional = pending.filter { $0.item.optional == true }
        let seen = entries.filter { $0.seen }
        if entries.isEmpty {
            Card(state: .noData) {
                Text("Nada na lista para hoje.").font(.geist(14))
                Text("Acrescenta o que levas sempre em «Editar a lista».").font(.geist(12)).foregroundStyle(Color.soft)
            }
        }
        if !essential.isEmpty {
            Card {
                HStack(spacing: 8) {
                    Eyebrow(text: "Essencial")
                    Spacer(minLength: 0)
                    Text(LeaveRules.pendingText(essential.count)).font(.geist(11)).foregroundStyle(Color.faint)
                }
                ForEach(essential) { row($0, day: day) }
            }
        }
        if !optional.isEmpty {
            Card {
                Eyebrow(text: "Se quiseres")
                ForEach(optional) { row($0, day: day) }
            }
        }
        if !seen.isEmpty { seenCard(seen, day: day) }
    }

    private func row(_ e: LeaveEntry, day: String) -> some View {
        Button { store.toggleLeaveSeen(e, on: day) } label: {
            HStack(spacing: 10) {
                Image(systemName: e.seen ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(e.seen ? Color.good : Color.soft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.item.title).font(.geist(14.5)).foregroundStyle(Color.ink)
                    HStack(spacing: 6) {
                        if !e.note.isEmpty { Text(e.note).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(2) }
                        if let source = e.source { SourceLine(text: source) }
                    }
                }
                Spacer(minLength: 4)
                if let state = e.state, !e.seen { StateTag(state: state) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(e.item.title), \(e.seen ? "levado" : "por ver")")
        .accessibilityHint(e.seen ? "Toca se ainda não o levaste" : "Toca para marcar como levado")
        .accessibilityIdentifier("leave.item.\(e.id)")
    }

    /// What you've seen, in one line; a tap shows it, to take one back
    private func seenCard(_ seen: [LeaveEntry], day: String) -> some View {
        Card {
            Button { withAnimation(.easeOut(duration: 0.2)) { seenOpen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.good)
                    Text("Já visto: " + LeaveRules.names(seen.map { $0.item.title })).font(.geist(13)).foregroundStyle(Color.soft).lineLimit(2)
                    Spacer(minLength: 4)
                    Image(systemName: seenOpen ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(Color.faint)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("leave.seen")
            if seenOpen || reopened { ForEach(seen) { row($0, day: day) } } // reopened, the list shows everything
        }
    }

    /// Today's outfit, chosen the night before (Preparar amanhã), is already settled: one discreet line
    @ViewBuilder private func resolvedLine(_ day: String) -> some View {
        if let o = store.record(OutfitLog.self, day), !o.worn, !o.items.isEmpty {
            let names = o.items.compactMap { store.record(Garment.self, $0)?.name }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Já resolvido").font(.geist(12, .semibold)).foregroundStyle(Color.soft)
                    Text("roupa para hoje" + (names.isEmpty ? "" : " · " + names.joined(separator: ", "))).font(.geist(12)).foregroundStyle(Color.faint).lineLimit(2)
                }
                Spacer(minLength: 4)
                StateTag(state: .confirmed, text: "Escolhida")
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Ready

    private func readyCard(_ entries: [LeaveEntry], day: String) -> some View {
        let at = store.leaveDay(day).map { $0.ready ?? $0.at }
        let time = at.map { " às " + clock(Day.minuteOfDay(Date(timeIntervalSince1970: $0 / 1000))) } ?? ""
        return Card(tint: .mint) {
            VStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: 0x05140F))
                    .frame(width: 44, height: 44).background(Circle().fill(Area.mint.gradient))
                    .accessibilityHidden(true)
                Text("Pronto para sair").font(.geist(17, .semibold))
                Text("\(entries.count) de \(entries.count) vistos\(time)").font(.geist(12)).foregroundStyle(Color.soft)
                Button { reopened = true } label: {
                    Text("Reabrir a lista").font(.geist(13, .semibold)).foregroundStyle(Color.mint).padding(.horizontal, 12).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("leave.reopen")
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("leave.ready")
    }

    // MARK: Editing and the reminder

    private var editCard: some View {
        Card {
            Eyebrow(text: "Editar a lista")
            ForEach(store.leaveItems) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.geist(14))
                        Text(LeaveRules.whenLabel(item)).font(.geist(12)).foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 4)
                    Button { editing = item } label: {
                        Text("Editar").font(.geist(13, .semibold)).foregroundStyle(Color.ink).padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(Pressable())
                    .accessibilityLabel("Editar \(item.title)")
                    .accessibilityIdentifier("leave.edit.\(item.id)")
                }
            }
            Button { editing = LeaveItem(id: "mine-" + UUID().uuidString, title: "") } label: {
                Label("Adicionar", systemImage: "plus").font(.geist(13, .semibold)).foregroundStyle(Color.mint).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("leave.add")
        }
    }

    /// The optional reminder at the time to leave, by the clock only: leaving home by location needs a permission this
    /// version doesn't ask for
    private func reminderCard(_ day: String) -> some View {
        let departures = store.leaveDepartures(on: day)
        let first = departures.first(where: { $0.leave >= store.nowMinute }) ?? departures.first
        return Card {
            Eyebrow(text: "Lembrete")
            Toggle(isOn: $remind) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(first.map { "Lembrar \(PlanFormat.at($0.leave))" } ?? "Lembrar à hora de sair").font(.geist(14))
                    Text(first.map { "à hora de saída · \($0.title)" } ?? "quando houver uma saída no dia").font(.geist(12)).foregroundStyle(Color.soft)
                }
            }
            .tint(.mint)
            .frame(minHeight: 44)
            .accessibilityIdentifier("leave.remind")
            Text("Lembrar ao sair de casa precisa da localização, que esta versão não usa.").font(.geist(12)).foregroundStyle(Color.faint)
        }
        .onChange(of: remind) { _, _ in Reminders.shared.reschedule() }
    }
}

/// Adds or edits one item of Antes de sair: its name, when it's on the list, and whether it's optional. «Remover»
/// keeps it as removed, so it never comes back as a suggestion.
struct LeaveItemEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var item: LeaveItem

    var body: some View {
        let known = LeaveRules.isBuiltIn(item.id) || store.record(LeaveItem.self, item.id) != nil
        NavigationStack {
            Form {
                TextField("Nome (p. ex. Passe do ginásio)", text: $item.title).accessibilityIdentifier("leave.editor.title")
                Picker("Quando", selection: $item.when) {
                    Text("Sempre").tag(LeaveItem.always)
                    Text("Em dias de treino").tag(LeaveItem.training)
                    Text("Quando há chuva prevista").tag(LeaveItem.rain)
                }
                Toggle("Opcional («Se quiseres»)", isOn: Binding(get: { item.optional == true }, set: { item.optional = $0 ? true : nil }))
                if known {
                    Button("Remover", role: .destructive) {
                        store.removeLeaveItem(store.leaveItems.first { $0.id == item.id } ?? item)
                        dismiss()
                    }
                    .accessibilityIdentifier("leave.editor.remove")
                }
            }
            .cadenceList()
            .navigationTitle(known ? item.title : "Novo item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { store.saveLeaveItem(item); dismiss() }
                        .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("leave.editor.save")
                }
            }
        }
    }
}

/// After the time to leave, what was left to see becomes one line in Today, once: a tap opens the list, the cross
/// closes it for the day. No notification, and nothing is marked by itself.
struct LeaveLaterLine: View {
    @EnvironmentObject var store: Store
    var minute: Int
    var open: () -> Void

    var body: some View {
        if store.leaveLineShows(minute: minute) {
            let left = store.leaveEntries().filter { !$0.seen }
            Card {
                HStack(spacing: 8) {
                    Button(action: open) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ficou por ver antes de sair").font(.geist(13.5, .semibold)).foregroundStyle(Color.ink)
                            Text(LeaveRules.names(left.map { $0.item.title })).font(.geist(12)).foregroundStyle(Color.soft).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("leave.line.open")
                    Button { store.closeLeaveLine() } label: {
                        Image(systemName: "xmark").font(.geist(12, .bold)).foregroundStyle(Color.faint).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fechar")
                    .accessibilityIdentifier("leave.line.close")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("leave.line")
        }
    }
}
