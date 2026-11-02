// Home and lock-screen widgets: score and readiness with Pip, what's next and open must-dos, water and protein.
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: Snapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) { completion(SnapshotEntry(date: Date(), snapshot: SharedBox.read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: Date(), snapshot: SharedBox.read())], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

private let mint = Color(red: 0.2, green: 0.88, blue: 0.71)
private let water = Color(red: 0.25, green: 0.82, blue: 1)
private let fuel = Color(red: 1, green: 0.71, blue: 0.28)
private let warn = Color(red: 1, green: 0.74, blue: 0.29)

struct CadenceHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CadenceToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry).containerBackground(for: .widget) { Color(red: 0.03, green: 0.04, blue: 0.06) }
        }
        .configurationDisplayName("Today")
        .description("Shortcuts for water, brushing and quick add.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(s.score), in: 0...100) { Text("") } currentValueLabel: { Text("\(s.score)") }.gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                Text(s.mustDos.first.map { "\($0) · must-do" } ?? "Score \(s.score)" + (s.readiness.map { " · ready \($0)" } ?? ""))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Score \(s.score)" + (s.readiness.map { " · ready \($0)" } ?? "")).font(.headline)
                    if let m = s.mustDos.first { Text("\(m): not yet").font(.caption) } else if let n = s.next { Text("\(s.nextTime ?? "") \(n)").font(.caption) }
                    Text(String(format: "Water %.1f / %.1f L", s.water / 1000, s.waterGoal / 1000)).font(.caption2)
                }
            case .systemMedium:
                HStack(spacing: 14) {
                    small(s)
                    VStack(alignment: .leading, spacing: 6) {
                        if !s.mustDos.isEmpty { Label(s.mustDos.joined(separator: ", "), systemImage: "exclamationmark.circle.fill").font(.caption.bold()).foregroundStyle(warn).lineLimit(2) }
                        if let n = s.next { Label("\(s.nextTime ?? "") \(n)", systemImage: "play.fill").font(.caption).foregroundStyle(.white).lineLimit(1) }
                        bar("Water", s.water / max(1, s.waterGoal), water, String(format: "%.1f L", s.water / 1000))
                        bar("Protein", s.protein / max(1, s.proteinGoal), fuel, "\(Int(s.protein)) g")
                    }
                }
            default:
                small(s)
            }
        } else {
            shortcuts
        }
    }

    /// No shared data with free signing, so instead of a message the widget is a set of shortcuts into the app
    @ViewBuilder private var shortcuts: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 8) {
                shortcut("Water", "drop.fill", water, "cadence://water")
                shortcut("Brush", "mouth.fill", mint, "cadence://brush")
                shortcut("Add", "plus", fuel, "cadence://capture")
                shortcut("Train", "dumbbell.fill", warn, "cadence://workout")
            }
        case .systemSmall:
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 34)).foregroundStyle(mint)
                Text("Quick add").font(.caption.bold()).foregroundStyle(.white)
            }
            .widgetURL(URL(string: "cadence://capture"))
        case .accessoryInline:
            Label("Quick add", systemImage: "plus")
        case .accessoryRectangular:
            Label("Cadence: quick add", systemImage: "plus.circle.fill").font(.headline).widgetURL(URL(string: "cadence://capture"))
        default:
            Image(systemName: "plus").font(.title2.bold()).widgetURL(URL(string: "cadence://capture"))
        }
    }

    private func shortcut(_ name: String, _ icon: String, _ color: Color, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(color)
                Text(name).font(.caption2.weight(.semibold)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        }
    }

    private func small(_ s: Snapshot) -> some View {
        VStack(spacing: 4) {
            Image(s.mood).resizable().scaledToFit().frame(width: 54, height: 54)
            Text("\(s.score)").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(s.readiness.map { "ready \($0)" } ?? "level \(s.level)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func bar(_ name: String, _ p: Double, _ c: Color, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(name).font(.caption2).foregroundStyle(.secondary); Spacer(); Text(value).font(.caption2.monospacedDigit()).foregroundStyle(.white) }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(c).frame(width: max(4, g.size.width * min(1, p)))
                }
            }
            .frame(height: 5)
        }
    }
}
