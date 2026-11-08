// The lock-screen workout: tick the set, nudge weight and reps, control rest, without unlocking. The Dynamic Island
// shows the set and the countdown. Detailed editing stays in the app.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CadenceWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        PipLiveActivity()
        CadenceHomeWidget()
    }
}

private let coral = Color(red: 1, green: 0.48, blue: 0.52)
private let good = Color(red: 0.27, green: 0.85, blue: 0.53)

private func kgText(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            LockScreenWorkout(context: context)
                .widgetURL(URL(string: "cadence://workout?id=\(context.attributes.sessionId)"))
                .activityBackgroundTint(Color(red: 0.12, green: 0.09, blue: 0.13).opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.state.exercise).font(.caption.bold()).lineLimit(1)
                        Text(context.state.setLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(kgText(context.state.weight))×\(context.state.reps)").font(.title3.monospacedDigit().bold()).foregroundStyle(coral)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let end = context.state.restEnd, end > Date() {
                            Text(timerInterval: Date()...end, countsDown: true).font(.headline.monospacedDigit()).foregroundStyle(coral)
                        }
                        Spacer()
                        Button(intent: WorkoutIntent(.done)) { Label("Feito", systemImage: "checkmark") }.tint(good)
                    }
                }
            } compactLeading: {
                Text("\(kgText(context.state.weight))×\(context.state.reps)").font(.caption.monospacedDigit().bold()).foregroundStyle(coral)
            } compactTrailing: {
                if let end = context.state.restEnd, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true).font(.caption.monospacedDigit()).foregroundStyle(coral).frame(width: 44)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(coral)
                }
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(coral)
            }
            .widgetURL(URL(string: "cadence://workout?id=\(context.attributes.sessionId)"))
        }
    }
}

struct LockScreenWorkout: View {
    let context: ActivityViewContext<WorkoutAttributes>

    var body: some View {
        let s = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                (Text("\(context.attributes.sessionName) · ") + Text(context.attributes.started, style: .timer))
                    .font(.caption.bold()).foregroundStyle(coral)
                Spacer()
                Text(s.setLabel).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(s.exercise).font(.headline).lineLimit(1)
                Spacer()
                Text("\(kgText(s.weight)) kg × \(s.reps)").font(.headline.monospacedDigit())
            }
            HStack(spacing: 4) {
                button("−2.5", .weightDown)
                button("−1 rep", .repDown)
                Button(intent: WorkoutIntent(.done)) { Text("Feito ✓").font(.caption.bold()).frame(maxWidth: .infinity) }.tint(good)
                button("+1 rep", .repUp)
                button("+2.5", .weightUp)
            }
            HStack(spacing: 6) {
                if let end = s.restEnd, end > Date() {
                    Text("Descanso").font(.caption).foregroundStyle(.secondary)
                    Text(timerInterval: Date()...end, countsDown: true).font(.caption.monospacedDigit().bold())
                    Spacer()
                    button("−15", .restDown)
                    button("+15", .restUp)
                    button("Saltar", .restSkip)
                } else {
                    Text("A seguir: \(s.next)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(14)
    }

    private func button(_ title: String, _ action: WorkoutAction) -> some View {
        Button(intent: WorkoutIntent(action)) { Text(title).font(.caption.bold()).frame(maxWidth: .infinity) }.tint(.white.opacity(0.25))
    }
}
