// Pip on the Dynamic Island and the lock screen, saying the one thing you're forgetting, with Done and Later.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let mint = Color(red: 0.2, green: 0.88, blue: 0.71)

struct PipLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PipAttributes.self) { context in
            HStack(spacing: 12) {
                Image(context.state.mood).resizable().scaledToFit().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.state.message).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let id = context.state.promiseId {
                        HStack(spacing: 6) {
                            Button(intent: PipIntent(.done, promiseId: id)) { Text("Done ✓").font(.caption.bold()) }.tint(mint)
                            Button(intent: PipIntent(.later, promiseId: id)) { Text("In 30 min").font(.caption.bold()) }.tint(.white.opacity(0.25))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .widgetURL(URL(string: "cadence://today"))
            .activityBackgroundTint(Color(red: 0.08, green: 0.07, blue: 0.1).opacity(0.9))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(context.state.mood).resizable().scaledToFit().frame(width: 44, height: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.message).font(.caption.weight(.semibold)).lineLimit(2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let id = context.state.promiseId {
                        HStack {
                            Button(intent: PipIntent(.done, promiseId: id)) { Label("Done", systemImage: "checkmark") }.tint(mint)
                            Button(intent: PipIntent(.later, promiseId: id)) { Text("In 30 min") }
                        }
                    }
                }
            } compactLeading: {
                Image(context.state.mood).resizable().scaledToFit().frame(width: 22, height: 22)
            } compactTrailing: {
                Text(context.state.short).font(.caption2.weight(.semibold)).foregroundStyle(mint).lineLimit(1).frame(maxWidth: 64)
            } minimal: {
                Image(context.state.mood).resizable().scaledToFit().frame(width: 20, height: 20)
            }
            .widgetURL(URL(string: "cadence://today"))
        }
    }
}
