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
        .description("Score, readiness, what's next and Pip.")
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
            VStack(spacing: 4) {
                Image(systemName: "leaf.fill").foregroundStyle(mint)
                Text("Open Cadence").font(.caption)
            }
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
