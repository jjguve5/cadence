// Today: the morning brief, readiness with its reasons, what's next, rings, today's promises, closing the day.
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var closing = false
    @State private var editing: PromiseItem?
    @State private var briefHidden = false

    private var greeting: String {
        let m = Day.minuteOfDay(store.tick)
        return m < 12 * 60 ? "Good morning" : m < 18 * 60 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        NavigationStack {
            Screen(glow: .mint) {
                header
                if store.needsGoogle { googleCard }
                if Day.minuteOfDay(store.tick) < 12 * 60, !briefHidden, !store.briefLines().isEmpty { brief }
                if Day.minuteOfDay(store.tick) < 14 * 60 { WeatherCard() }
                readinessCard
                nextUp
                rings
                promisesCard
                top3Card
                closeCard
                syncLine
            }
            .refreshable { await store.refreshAll() }
            .sheet(isPresented: $closing) { CloseDayView() }
            .sheet(item: $editing) { PromiseEditor(promise: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Title(eyebrow: "\(store.tick.formatted(.dateTime.weekday(.wide).day().month(.wide))) · score \(store.score())", title: greeting)
            Spacer()
            NavigationLink { PipPage() } label: {
                ZStack(alignment: .bottomTrailing) {
                    PipHead(mood: store.pipMood(), size: 50)
                    Text("\(store.level.level)").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x032018))
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.mint)).offset(x: 4, y: 2)
                }
            }
        }
        .padding(.top, 8)
    }

    private var googleCard: some View {
        Card(tint: .warn) {
            Eyebrow(text: "Fitbit data paused", icon: "exclamationmark.triangle.fill", color: .warn)
            Text("Google's sign-in expired (it lasts 7 days while the app is in testing). Connect again to keep readiness and sleep up to date.").font(.system(size: 14))
            NavigationLink { SettingsView() } label: { Chip(text: "Connect Google", color: .warn) }
        }
    }

    private var brief: some View {
        Card(tint: .sleep) {
            HStack {
                Eyebrow(text: "Morning brief", icon: "sunrise.fill", color: .sleep)
                Spacer()
                Button { briefHidden = true } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.faint) }
            }
            ForEach(store.briefLines()) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(line.good == false ? Color.warn : Color.soft).frame(width: 6, height: 6).padding(.top, 6)
                    Text(line.text).font(.system(size: 14))
                }
            }
        }
    }

    private var readinessCard: some View {
        NavigationLink { ReadinessView() } label: {
            Card(tint: .mint) {
                if let r = store.readiness() {
                    HStack(spacing: 14) {
                        ZStack {
                            Ring(progress: Double(r.score) / 100, area: .mint, width: 8)
                            Text("\(r.score)").font(.system(size: 22, weight: .bold))
                        }
                        .frame(width: 70, height: 70)
                        VStack(alignment: .leading, spacing: 3) {
                            Eyebrow(text: "Readiness", icon: "gauge.with.dots.needle.50percent")
                            Text(r.label).font(.system(size: 18, weight: .bold))
                            Text(r.summary).font(.system(size: 12.5)).foregroundStyle(Color.soft).lineLimit(2)
                        }
                    }
                } else {
                    Eyebrow(text: "Readiness", icon: "gauge.with.dots.needle.50percent")
                    Text(store.health.isEmpty ? "Waiting for your first sync from the Air." : "Needs last night's sleep, HRV and resting HR: they arrive once the Air syncs.")
                        .font(.system(size: 14)).foregroundStyle(Color.soft)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var nextUp: some View {
        let minute = Day.minuteOfDay(store.tick)
        let next = store.due().first { store.status($0) == nil && store.time(of: $0) + 90 >= minute }
        return Group {
            if let next {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Eyebrow(text: "Next up", icon: "play")
                            Text(next.title).font(.system(size: 16, weight: .bold))
                            Text("\(store.timeLabel(next)) · \(next.kind == .mustDo ? "must-do" : next.schedule.summary)").font(.system(size: 12.5)).foregroundStyle(Color.soft)
                        }
                        Spacer()
                        Button { store.log(next, .done) } label: {
                            Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Color(hex: 0x032018))
                                .frame(width: 44, height: 44).background(Circle().fill(Area.mint.gradient))
                        }
                    }
                }
            }
        }
    }

    private var rings: some View {
        let today = store.health[Day.today]
        let due = store.due()
        let done = due.filter { store.status($0).map { $0 != .skipped } ?? false }.count
        let fuel = store.fuel()
        let items: [(String, Double, Area, String)] = [
            ("Protein", fuel.protein / store.profile.proteinTarget, .fuel, "\(Int(fuel.protein))g"),
            ("Water", fuel.water / store.waterGoal(), .water, String(format: "%.1fL", fuel.water / 1000)),
            ("Move", (today?.steps ?? 0) / Double(store.profile.stepGoal), .train, today?.steps.map { "\(Int($0 / 100) / 10).\(Int($0 / 100) % 10)k" } ?? "–"),
            ("Promises", due.isEmpty ? 1 : Double(done) / Double(due.count), .mint, "\(done)/\(due.count)"),
        ]
        return Card {
            HStack {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: 6) {
                        ZStack {
                            Ring(progress: item.1, area: item.2, width: 6)
                            Text(item.3).font(.system(size: 11.5, weight: .semibold)).minimumScaleFactor(0.7)
                        }
                        .frame(width: 58, height: 58)
                        Text(item.0).font(.system(size: 11.5)).foregroundStyle(Color.soft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var promisesCard: some View {
        Card {
            HStack {
                Eyebrow(text: "Promises today", icon: "bell")
                Spacer()
                NavigationLink { PromisesView() } label: { Text("All").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mint) }
            }
            let due = store.due()
            if due.isEmpty { Text("Nothing due today.").foregroundStyle(Color.soft).font(.system(size: 14)) }
            ForEach(due) { p in PromiseRow(promise: p, edit: { editing = p }) }
        }
    }

    private var top3Card: some View {
        let entry = store.day()
        return Group {
            if !entry.top3.isEmpty {
                Card {
                    Eyebrow(text: "Today's top 3", icon: "list.number")
                    ForEach(Array(entry.top3.enumerated()), id: \.offset) { i, item in
                        let done = i < entry.top3Done.count && entry.top3Done[i]
                        Button {
                            var e = entry
                            while e.top3Done.count < e.top3.count { e.top3Done.append(false) }
                            e.top3Done[i].toggle()
                            store.save(e)
                        } label: {
                            HStack {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Color.good : Color.soft)
                                Text(item).strikethrough(done).foregroundStyle(done ? Color.soft : Color.ink).font(.system(size: 14))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var closeCard: some View {
        let closed = store.day().closedAt != nil
        let late = Day.minuteOfDay(store.tick) >= 19 * 60
        return Group {
            if closed {
                Card { HStack { Image(systemName: "moon.stars.fill").foregroundStyle(Color.sleep); Text("Day closed · \(store.day().score ?? store.score()) / 100").font(.system(size: 14, weight: .semibold)) } }
            } else if late {
                PrimaryButton(title: "Close the day") { closing = true }
            }
        }
    }

    private var syncLine: some View {
        HStack(spacing: 6) {
            Circle().fill(store.syncError == nil && !store.needsGoogle ? Color.good : Color.warn).frame(width: 7, height: 7)
            Text(syncText).font(.system(size: 11.5)).foregroundStyle(Color.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var syncText: String {
        var parts: [String] = []
        if let s = store.device?.lastSync, let d = ISO8601DateFormatter().date(from: s) { parts.append("Air synced \(d.formatted(.relative(presentation: .named)))") }
        if let b = store.device?.battery { parts.append("battery \(b)%") }
        if let e = store.syncError { parts.append(e) }
        if store.syncing { parts.append("syncing…") }
        return parts.isEmpty ? "Not synced yet" : parts.joined(separator: " · ")
    }
}

struct PromiseRow: View {
    @EnvironmentObject var store: Store
    var promise: PromiseItem
    var day: String = Day.today
    var edit: () -> Void = {}
    @State private var brushing = false
    @State private var reading = false

    var body: some View {
        let status = store.status(promise, on: day)
        let w = store.week(promise, upTo: day)
        HStack(spacing: 10) {
            Button {
                if status == nil { store.log(promise, on: day, .done) } else { store.undo(promise, on: day) }
            } label: {
                Image(systemName: status == .done || status == .tiny ? "checkmark.circle.fill" : status == .skipped ? "minus.circle" : "circle")
                    .font(.system(size: 22)).foregroundStyle(status == nil ? Color.soft : status == .skipped ? Color.faint : Color.good)
            }
            .buttonStyle(.plain)
            Image(systemName: promise.icon).foregroundStyle(Color.soft).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(promise.title).font(.system(size: 14.5, weight: .medium)).strikethrough(status == .skipped)
                Text("\(store.timeLabel(promise, on: day)) · \(w.done)/\(w.total) this week").font(.system(size: 11.5)).foregroundStyle(Color.faint)
            }
            Spacer()
            if status == nil, promise.title.lowercased().contains("brush") {
                Button { brushing = true } label: { Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundStyle(Color(hex: 0x5FE3D0)) }.buttonStyle(.plain)
            } else if status == nil, promise.title.lowercased().hasPrefix("read") {
                Button { reading = true } label: { Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundStyle(Color.read) }.buttonStyle(.plain)
            } else if promise.kind == .mustDo { Chip(text: "must-do", color: status == nil ? .warn : .good) }
            else { Chip(text: promise.schedule.summary, color: .soft) }
        }
        .fullScreenCover(isPresented: $brushing) { BrushingView() }
        .fullScreenCover(isPresented: $reading) { ReadingMode() }
        .contentShape(Rectangle())
        .contextMenu {
            if let tiny = promise.tiny, status == nil { Button("Tiny version: \(tiny)", systemImage: "leaf") { store.log(promise, on: day, .tiny) } }
            if status == nil { Button("Skip today", systemImage: "forward") { store.log(promise, on: day, .skipped) } }
            if status != nil { Button("Undo", systemImage: "arrow.uturn.backward") { store.undo(promise, on: day) } }
            Button("Edit", systemImage: "pencil") { edit() }
        }
    }
}

/// Readiness with each part against your baseline, and the "feels wrong" button
struct ReadinessView: View {
    @EnvironmentObject var store: Store
    @State private var sent = false

    var body: some View {
        Screen(glow: .mint) {
            if let r = store.readiness() {
                HStack(spacing: 16) {
                    ZStack { Ring(progress: Double(r.score) / 100, area: .mint, width: 10); Text("\(r.score)").font(.system(size: 34, weight: .bold)) }.frame(width: 110, height: 110)
                    VStack(alignment: .leading) {
                        Text(r.label).font(.system(size: 24, weight: .bold))
                        Text("Against your own 14-day baseline").font(.system(size: 13)).foregroundStyle(Color.soft)
                    }
                }
                .padding(.top, 10)
                Card {
                    Eyebrow(text: "What it's made of")
                    ForEach(r.parts) { part in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(part.name).font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text(part.value).font(.system(size: 14, design: .monospaced)).foregroundStyle(part.good ? Color.good : Color.warn)
                            }
                            Text(part.detail).font(.system(size: 12.5)).foregroundStyle(Color.soft)
                            Bar(progress: part.score / 100, area: part.good ? .mint : .fuel)
                        }
                        .padding(.vertical, 3)
                    }
                }
                Card {
                    Eyebrow(text: "Feels wrong?", icon: "bubble.left")
                    Text("Tell Cadence how you actually feel. It tunes the score over time.").font(.system(size: 13)).foregroundStyle(Color.soft)
                    if sent { Text("Thanks, noted.").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.good) }
                    else {
                        HStack {
                            SoftButton(title: "I feel worse", icon: "arrow.down") { store.addFeedback(ReadinessFeedback(date: Day.today, score: r.score, felt: -1)); sent = true }
                            SoftButton(title: "I feel better", icon: "arrow.up") { store.addFeedback(ReadinessFeedback(date: Day.today, score: r.score, felt: 1)); sent = true }
                        }
                    }
                }
            } else {
                Text("No readiness yet: it needs a night of data from the Air and four days of baseline.").foregroundStyle(Color.soft).padding(.top, 20)
            }
        }
        .navigationTitle("Readiness")
        .navigationBarTitleDisplayMode(.inline)
    }
}
