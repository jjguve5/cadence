// Today's intelligence: the focus card (up to three recommendations with why, evidence, confidence, action and
// dismiss), the minimum viable day banner, quick capture, and the monthly "what Cadence has learned" report.
import SwiftUI

struct FocusCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    @State private var expanded: String?
    @State private var focusing = false
    @State private var loggingFood = false
    @State private var training = false

    var body: some View {
        let recs = store.recommendations()
        Group {
            if !recs.isEmpty {
                Card(tint: .mint) {
                    HStack { Eyebrow(text: "Today's focus", icon: "scope", color: .mint); Spacer() }
                    ForEach(Array(recs.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Divider().overlay(Color.white.opacity(0.06)) }
                        row(r, open: i == 0 || expanded == r.id)
                    }
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("focus.card")
            } else if let note = store.freshnessNote {
                Card { Label(note, systemImage: "clock.arrow.circlepath").font(.geist(13)).foregroundStyle(Color.soft) }
            }
        }
        .fullScreenCover(isPresented: $focusing) { FocusView() }
        .sheet(isPresented: $loggingFood) { FoodLogSheet() }
        .navigationDestination(isPresented: $training) { TrainingView() }
    }

    private func row(_ r: Recommendation, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { withAnimation(.easeOut(duration: 0.2)) { expanded = expanded == r.id ? nil : r.id } } label: {
                HStack(alignment: .top) {
                    Text(r.title).font(.geist(open ? 16.5 : 14.5, .semibold)).foregroundStyle(Color.ink).multilineTextAlignment(.leading)
                    Spacer()
                    Chip(text: r.confidence.label, color: r.confidence == .high ? .good : r.confidence == .moderate ? .soft : .warn)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rec.\(r.kind)")
            if open {
                Text(r.why).font(.geist(13.5)).foregroundStyle(Color.ink.opacity(0.9))
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(r.evidence, id: \.self) { e in
                        HStack(alignment: .top, spacing: 6) { Circle().fill(Color.mint.opacity(0.6)).frame(width: 4, height: 4).padding(.top, 6); Text(e).font(.geist(12)).foregroundStyle(Color.soft) }
                    }
                }
                HStack(spacing: 8) {
                    if r.action != .none { SoftButton(title: r.actionLabel, icon: icon(r.action)) { act(r) }.accessibilityIdentifier("rec.\(r.kind).action") }
                    Spacer()
                    Button("Not useful") { store.feedback(r, useful: false) }.font(.geist(12.5)).foregroundStyle(Color.faint)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("rec.\(r.kind).dismiss")
                }
            }
        }
    }

    private func icon(_ a: RecAction) -> String {
        switch a {
        case .doMustDo: return "checkmark"
        case .protectFocus: return "brain.head.profile"
        case .trainByFeel: return "dumbbell.fill"
        case .earlierBedtime: return "moon.fill"
        case .offerMinimumDay: return "leaf"
        case .placeDeepWork: return "calendar.badge.plus"
        case .logFood: return "fork.knife"
        case .syncAir: return "arrow.triangle.2.circlepath"
        default: return "checkmark"
        }
    }

    private func act(_ r: Recommendation) {
        store.feedback(r, useful: true)
        switch r.action {
        case .doMustDo(let title): if let p = store.openMustDos().first(where: { $0.title == title }) { store.log(p, .done) }
        case .protectFocus: focusing = true
        case .trainByFeel: training = true
        case .earlierBedtime(let m): store.put("bedshift", Day.today, .number(Double(m))); Reminders.shared.reschedule()
        case .offerMinimumDay: store.setMinimumDay(true, reasons: r.evidence)
        case .placeDeepWork(let title):
            if let start = store.suggestedDeepWork() {
                let p = store.all(Project.self).first { $0.title == title }
                store.save(PlanBlock(date: Day.today, start: start, minutes: 100, title: "Deep work · \(title)", type: "deep", projectId: p?.id))
            }
        case .logFood: loggingFood = true
        case .syncAir: openURL(URL(string: "fitbit://")!)
        default: break
        }
    }
}

struct MinimumDayBanner: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if store.isMinimumDay() {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill").font(.geist(12)).foregroundStyle(Color.good)
                Text("Minimum day: essentials only").font(.geist(12.5, .medium)).foregroundStyle(Color.ink.opacity(0.9))
                Spacer()
                Button("Turn off") { store.setMinimumDay(false) }.font(.geist(12.5, .semibold)).tint(.soft)
                    .frame(minHeight: 44).accessibilityIdentifier("mvd.off")
            }
            .padding(.horizontal, 14)
            .background(Capsule().fill(Color.good.opacity(0.12)))
            .accessibilityElement(children: .contain).accessibilityIdentifier("mvd.banner")
        }
    }
}

struct QuickCaptureSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var done: String?
    @State private var undo: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Ate a banana · spent 12 € on groceries · remind me…", text: $text, axis: .vertical)
                    .font(.geist(17)).focused($focused)
                    .padding(14).background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.07)))
                    .accessibilityIdentifier("capture.field")
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    let intent = QuickCapture.parse(text)
                    Card {
                        Eyebrow(text: "Understood as", icon: "text.magnifyingglass")
                        Text(intent.summary).font(.geist(15, .medium)).accessibilityIdentifier("capture.summary")
                    }
                    PrimaryButton(title: "Confirm") {
                        let r = store.apply(intent)
                        done = r.message
                        undo = r.undo
                        text = ""
                    }
                    .disabled(!intent.savesSomething).opacity(intent.savesSomething ? 1 : 0.4)
                    .accessibilityIdentifier("capture.confirm")
                }
                if let done {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.good).accessibilityHidden(true)
                        Text(done).font(.geist(14)).foregroundStyle(Color.good).accessibilityIdentifier("capture.done")
                        Spacer()
                        if let undo {
                            Button("Undo") { undo(); self.undo = nil; self.done = "Undone" }
                                .font(.geist(14, .semibold)).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("capture.undo")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Try").font(.geist(12, .semibold)).foregroundStyle(Color.faint)
                    ForEach(["Ate Greek yogurt and a banana", "Spent 12 euros on groceries", "Remind me to wash my clothes tomorrow at 18:00", "Move studying to tomorrow", "Felt exhausted after lunch"], id: \.self) { s in
                        Button(s) { text = s }.font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }
                Spacer()
            }
            .padding(18)
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Quick capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("capture.close") } }
            .onAppear { focused = true }
        }
    }
}

/// The monthly report: what Cadence has learned about you, with sample sizes, and where it's still unsure
struct LearnedView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Screen(glow: .mind) {
            Text("Each prediction is written down before the day happens, then checked against what you reported. Under 10 pairs Cadence says so instead of guessing.")
                .font(.geist(13)).foregroundStyle(Color.soft).padding(.top, 6).accessibilityIdentifier("learned.screen")
            calibration("Morning readiness → your energy that evening", store.energyPairs())
            calibration("Readiness → how the session felt", store.trainingPairs())
            calibration("Energy curve → focus session quality", store.focusPairs())
            let effects = store.journalEffects()
            Card {
                Eyebrow(text: "Habits and your sleep", icon: "moon.stars")
                if effects.isEmpty { Text("Answer the morning journal for a few weeks; each habit needs 5 days with it and 5 without.").font(.geist(12.5)).foregroundStyle(Color.soft) }
                ForEach(effects, id: \.question) { e in
                    HStack { Text(journalText(e.question)).font(.geist(13.5)); Spacer(); Text(e.sleep.map { "\($0 > 0 ? "+" : "")\($0) min" } ?? "–").font(.mono(12.5)).foregroundStyle(Color.soft) }
                }
                Text("Associations in your own days. Other things change at the same time, so none of this proves cause.").font(.geist(11)).foregroundStyle(Color.faint)
            }
            Card {
                Eyebrow(text: "Notifications you answer", icon: "bell.badge")
                let n = NotificationLearning.summary
                if n.isEmpty { Text("Builds up as you answer or swipe away reminders.").font(.geist(12.5)).foregroundStyle(Color.soft) }
                ForEach(n, id: \.kind) { k in
                    HStack { Text(kindName(k.kind)).font(.geist(13.5)); Spacer(); Text("\(Int((1 - k.rate) * 100))% answered · \(k.n)").font(.mono(12)).foregroundStyle(k.rate >= 0.7 ? Color.warn : Color.soft) }
                }
                Text("Kinds you swipe away 70% of the time drop in priority; at 90% they stop. Must-dos, medicines and leave-by alerts never do.").font(.geist(11)).foregroundStyle(Color.faint)
            }
        }
        .navigationTitle("What Cadence has learned")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func kindName(_ k: String) -> String {
        ["p": "Promises", "wind": "Wind-down", "close": "Close the day", "brief": "Morning brief", "protein": "Protein catch-up", "water": "Water", "plant": "Plants",
         "dry": "Laundry", "bday": "Birthdays", "renew": "Renewals", "doc": "Documents", "touch": "Keep in touch", "groom": "Grooming", "m": "Medicines", "leave": "Leave-by", "shower": "Shower", "gymbag": "Gym bag"][k] ?? k
    }

    private func calibration(_ title: String, _ pairs: [(predicted: Double, observed: Double)]) -> some View {
        let c = Engine.calibrate(pairs)
        return Card {
            Eyebrow(text: title)
            HStack(alignment: .firstTextBaseline) {
                Text(c.spearman.map { String(format: "%.2f", $0) } ?? "–").font(.mono(24, .medium))
                Text("rank correlation · \(c.n) pairs").font(.geist(12)).foregroundStyle(Color.soft).accessibilityIdentifier("calibration.pairs")
            }
            Text(c.verdict).font(.geist(13.5, .semibold)).foregroundStyle(c.verdict.hasPrefix("Useful") ? Color.good : Color.soft)
            if let m = c.modelError, let b = c.baselineError { Text(String(format: "Average miss %.2f points, against %.2f from guessing your own average", m, b)).font(.geist(11.5)).foregroundStyle(Color.faint) }
        }
    }
}
