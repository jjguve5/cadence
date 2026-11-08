// Close the day: open must-dos first, then how it went, tomorrow's top 3. The score and Pip's pose come from here.
import SwiftUI

struct CloseDayView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var entry = DayEntry(date: Day.today)
    @State private var tomorrow = ["", "", ""]
    @State private var done = false

    var body: some View {
        NavigationStack {
            Screen(glow: .sleep) {
                HStack(spacing: 12) {
                    PipAnimation(mood: done ? .celebrate : (store.score() >= 60 ? .proud : .idle)).frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Hoje")
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(store.score())").font(.geist(40, .bold))
                            Text("/ 100").font(.geist(13)).foregroundStyle(Color.soft)
                        }
                        Text("Pip: «\(store.pipLine())»").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }

                let open = store.due().filter { store.status($0) == nil }
                if !open.isEmpty {
                    Card(tint: .warn) {
                        Eyebrow(text: "Ainda por fazer", color: .warn)
                        ForEach(open) { PromiseRow(promise: $0, insideSheet: true) }
                    }
                }

                DisclosureGroup("Diário, se tiveres um minuto") { JournalCard(day: Day.today) }
                    .font(.geist(13.5, .medium)).tint(.soft).padding(.horizontal, 4)
                Card {
                    Eyebrow(text: "Como correu o dia?")
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { n in
                            Button { entry.rating = n } label: {
                                Text("\(n)").font(.geist(16, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(entry.rating == n ? AnyShapeStyle(Area.mind.gradient) : AnyShapeStyle(Color.white.opacity(0.08))))
                                    .foregroundStyle(entry.rating == n ? Color(hex: 0x14082B) : Color.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Text("Energia").font(.geist(13)).foregroundStyle(Color.soft)
                        Spacer()
                        ForEach(1...5, id: \.self) { n in
                            Button { entry.energy = n } label: {
                                Image(systemName: n <= (entry.energy ?? 0) ? "bolt.fill" : "bolt").foregroundStyle(Color.fuel).font(.system(size: 18))
                                    .frame(width: 36, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Energia \(n) de 5").accessibilityAddTraits(n == entry.energy ? .isSelected : [])
                            .accessibilityIdentifier("energy.\(n)")
                        }
                    }
                    TextField("Uma linha sobre hoje (opcional)", text: $entry.note, axis: .vertical).font(.geist(14))
                }

                Card {
                    Eyebrow(text: "3 prioridades de amanhã")
                    ForEach(0..<3, id: \.self) { i in
                        TextField("\(i + 1) · acrescenta uma", text: $tomorrow[i]).font(.geist(14))
                    }
                    let carry = entry.top3.enumerated().filter { $0.offset >= entry.top3Done.count || !entry.top3Done[$0.offset] }.map(\.element)
                    if !carry.isEmpty {
                        Button("Passar o que ficou por fazer: \(carry.joined(separator: ", "))") {
                            for (i, item) in carry.prefix(3).enumerated() where tomorrow[i].isEmpty { tomorrow[i] = item }
                        }
                        .font(.geist(12.5)).foregroundStyle(Color.mint)
                    }
                }

                PrimaryButton(title: done ? "Boa noite" : "Fechar o dia") {
                    if done { dismiss(); return }
                    let score = store.score()
                    entry.score = score
                    entry.points = score
                    entry.closedAt = nowMs()
                    store.save(entry)
                    let next = Day.add(1, to: Day.today)
                    var t = store.day(next)
                    t.top3 = tomorrow.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    t.top3Done = Array(repeating: false, count: t.top3.count)
                    store.save(t)
                    withAnimation { done = true }
                }
                .accessibilityIdentifier("closeday.save")
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mais tarde") { dismiss() } } }
            .onAppear {
                entry = store.day()
                let t = store.day(Day.add(1, to: Day.today)).top3
                for (i, item) in t.prefix(3).enumerated() { tomorrow[i] = item }
            }
        }
    }
}
