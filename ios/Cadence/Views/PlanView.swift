// Plan: today's timeline from your wake time to lights out, with promises in place and the day windows.
import SwiftUI

struct PlanItem: Identifiable {
    var id: String
    var minute: Int
    var title: String
    var detail: String
    var icon: String
    var color: Color
    var promise: PromiseItem?
}

@MainActor
extension Store {
    func planItems(for day: String = Day.today) -> [PlanItem] {
        let plan = sleepPlan(for: day)
        var items: [PlanItem] = [
            PlanItem(id: "wake", minute: profile.wakeMinute, title: "Wake up", detail: "Daylight in the first hour sets tonight's sleep", icon: "sunrise.fill", color: .read),
            PlanItem(id: "wind", minute: plan.windDown, title: "Wind-down", detail: "Screens away, lights low", icon: "moon.fill", color: .sleep),
            PlanItem(id: "lights", minute: plan.perform, title: "Lights out", detail: "For \(duration(plan.need)) of sleep", icon: "bed.double.fill", color: .sleep),
        ]
        let kitchen = plan.perform - 180
        items.append(PlanItem(id: "kitchen", minute: kitchen, title: "Kitchen closes", detail: "Last meal 3 h before bed", icon: "fork.knife", color: .fuel))
        items.append(PlanItem(id: "caffeine", minute: plan.perform - 8 * 60, title: "Last caffeine", detail: "Cola, iced tea, energy drinks", icon: "cup.and.saucer.fill", color: .warn))
        for p in due(on: day) {
            let st = status(p, on: day)
            items.append(PlanItem(id: p.id, minute: p.schedule.minute, title: p.title, detail: st == nil ? (p.kind == .mustDo ? "must-do" : p.schedule.summary) : st == .skipped ? "skipped" : "done", icon: p.icon, color: p.kind == .mustDo ? .warn : .mint, promise: p))
        }
        return items.sorted { ($0.minute < 240 ? $0.minute + 1440 : $0.minute) < ($1.minute < 240 ? $1.minute + 1440 : $1.minute) }
    }
}

struct PlanView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            Screen(glow: .water) {
                Title(eyebrow: store.tick.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Plan")
                    .padding(.top, 8)
                let now = Day.minuteOfDay(store.tick)
                Card {
                    ForEach(store.planItems()) { item in
                        let past = (item.minute % 1440) < now && item.minute < 1440 && item.minute >= 240
                        HStack(alignment: .top, spacing: 12) {
                            Text(clock(item.minute)).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Color.soft).frame(width: 48, alignment: .leading)
                            Image(systemName: item.icon).foregroundStyle(item.color).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.system(size: 14.5, weight: .semibold))
                                Text(item.detail).font(.system(size: 12)).foregroundStyle(Color.soft)
                            }
                            Spacer()
                            if let p = item.promise, store.status(p) == nil {
                                Button { store.log(p, .done) } label: { Image(systemName: "circle").font(.system(size: 20)).foregroundStyle(Color.soft) }
                            }
                        }
                        .opacity(past ? 0.5 : 1)
                        .padding(.vertical, 4)
                    }
                }
                Text("Google Calendar, focus and reading blocks arrive with the next update of Plan.").font(.system(size: 12)).foregroundStyle(Color.faint)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
