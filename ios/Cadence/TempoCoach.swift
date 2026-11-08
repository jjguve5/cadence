// The guided set: Fitbit Air sends no live motion, so Cadence sets the tempo instead. A pure model gives each exercise
// its phases in the right order and turns elapsed seconds into rep, phase and breath; a clock-driven runner and a
// full-screen guide show and speak them. Everything is computed from Date, so lag or a locked phone can't drift the count.
import AVFoundation
import SwiftUI

// MARK: - Model

enum TempoBreath: Equatable {
    case inhale, exhale, hold, steady

    var word: String {
        switch self {
        case .inhale: return "Inspira"
        case .exhale: return "Expira"
        case .hold: return "Sustém o ar"
        case .steady: return "Respira com calma"
        }
    }

    /// What the voice says at the start of the phase. Short pauses stay silent.
    var spoken: String? {
        switch self {
        case .inhale: return "in"
        case .exhale: return "out"
        case .hold, .steady: return nil
        }
    }
}

struct TempoPhase: Equatable {
    enum Kind: Equatable { case eccentric, concentric, hold }
    var kind: Kind
    var word: String
    var seconds: Double
    var breath: TempoBreath
    /// Where the bar travels, 0 is the bottom of the track and 1 the top
    var from: Double
    var to: Double

    static func lower(_ seconds: Double, word: String = "Desce", from: Double = 1, to: Double = 0) -> TempoPhase {
        TempoPhase(kind: .eccentric, word: word, seconds: seconds, breath: .inhale, from: from, to: to)
    }
    static func lift(_ seconds: Double, word: String = "Sobe", from: Double = 0, to: Double = 1) -> TempoPhase {
        TempoPhase(kind: .concentric, word: word, seconds: seconds, breath: .exhale, from: from, to: to)
    }
    static func hold(_ seconds: Double, at position: Double) -> TempoPhase {
        TempoPhase(kind: .hold, word: "Segura", seconds: seconds, breath: .hold, from: position, to: position)
    }
}

/// One moment of a set
struct TempoFrame: Equatable {
    var rep: Int // the rep in progress, from 1
    var completed: Int
    var target: Int
    var phaseIndex: Int
    var phase: TempoPhase
    var progress: Double // through the phase, 0 to 1
    var position: Double // of the bar, 0 to 1
    var done: Bool
}

struct TempoPlan: Equatable {
    var phases: [TempoPhase]
    /// A hold like a plank: every "rep" is one second, and the set's reps are its seconds
    var timed = false

    var cycle: Double { phases.map(\.seconds).reduce(0, +) }

    /// Pure: the same elapsed time always gives the same frame
    func frame(elapsed: TimeInterval, target: Int) -> TempoFrame {
        let goal = max(1, target)
        let t = max(0, elapsed)
        let total = cycle * Double(goal)
        if t >= total {
            let last = phases.count - 1
            return TempoFrame(rep: goal, completed: goal, target: goal, phaseIndex: last, phase: phases[last], progress: 1, position: timed ? 1 : phases[last].to, done: true)
        }
        let completed = min(goal - 1, Int(t / cycle))
        var left = t - Double(completed) * cycle
        var index = 0
        while index < phases.count - 1 && left >= phases[index].seconds {
            left -= phases[index].seconds
            index += 1
        }
        let phase = phases[index]
        let progress = min(1, left / phase.seconds)
        let eased = progress * progress * (3 - 2 * progress)
        let position = timed ? t / total : phase.from + (phase.to - phase.from) * eased
        return TempoFrame(rep: completed + 1, completed: completed, target: goal, phaseIndex: index, phase: phase, progress: progress, position: position, done: false)
    }

    /// What to say on moving between two frames. Only the newest state is spoken, so coming back from a lock or a
    /// stall never reads out a backlog of reps.
    func cue(from old: TempoFrame?, to new: TempoFrame, speakBreath: Bool) -> String? {
        if new.done { return old?.done == true ? nil : "Done" }
        if timed {
            guard let old else { return "Go" }
            guard new.completed != old.completed else { return nil }
            return new.completed % 5 == 0 || new.target - new.completed <= 3 ? String(new.completed) : nil
        }
        let breath = speakBreath ? new.phase.breath.spoken : nil
        if old?.rep != new.rep {
            if let breath { return "\(new.rep). \(breath)" }
            return String(new.rep)
        }
        return old?.phaseIndex != new.phaseIndex ? breath : nil
    }

    private static func lowerFirst(lower: Double = 3, pause: Double = 0, lift: Double = 2) -> TempoPlan {
        var phases = [TempoPhase.lower(lower)]
        if pause > 0 { phases.append(.hold(pause, at: 0)) }
        phases.append(.lift(lift))
        return TempoPlan(phases: phases)
    }

    private static func liftFirst(lift: Double = 2, squeeze: Double = 0, lower: Double = 3) -> TempoPlan {
        var phases = [TempoPhase.lift(lift)]
        if squeeze > 0 { phases.append(.hold(squeeze, at: 1)) }
        phases.append(.lower(lower))
        return TempoPlan(phases: phases)
    }

    /// Pulldowns and pushdowns: the effort moves the handle down, then it comes back up
    private static func downFirst(word: String, squeeze: Double) -> TempoPlan {
        TempoPlan(phases: [.lift(2, word: word, from: 1, to: 0), .hold(squeeze, at: 0), .lower(3, word: "Volta", from: 0, to: 1)])
    }

    /// Classifies by whole words of the id and name, so "narrow" isn't a row and "press down" isn't a press
    static func forExercise(id: String, name: String) -> TempoPlan {
        let cleaned = (id + " " + name).lowercased().map { (c: Character) -> Character in c.isLetter || c.isNumber ? c : " " }
        let text = " " + String(cleaned).split(separator: " ").joined(separator: " ") + " "
        func has(_ options: String...) -> Bool {
            options.contains { text.contains(" \($0) ") || text.contains(" \($0)s ") || text.contains(" \($0)es ") }
        }
        func isTimed() -> Bool {
            if has("hold", "stretch", "pose", "warrior", "isometric", "wall sit", "l sit", "v sit", "dead hang", "arm hang", "lever", "human flag", "carry", "walk", "plate pinch", "stand", "sled") { return true }
            if has("running", "cycling", "bike", "elliptical", "treadmill", "stair climber", "jump rope", "ski erg", "rowing machine", "battle rope") { return true }
            if has("walking") && !has("lunge") { return true }
            if has("plank") && !has("raise", "dip", "knee tuck", "to plank", "leg lift") { return true }
            return has("planche") && !has("push up")
        }
        let paused = has("pause", "paused")

        if isTimed() { return TempoPlan(phases: [TempoPhase(kind: .hold, word: "Segura", seconds: 1, breath: .steady, from: 0, to: 1)], timed: true) }

        if has("pulldown", "pull down") { return downFirst(word: "Puxa", squeeze: paused ? 2 : 1) }
        if has("pushdown", "push down", "pressdown", "press down") || (has("machine") && has("tricep extension", "triceps extension")) {
            return downFirst(word: "Empurra", squeeze: paused ? 2 : 1)
        }

        // These start from the top even though their names say curl, deadlift or extension
        if has("dragon flag", "nordic") { return lowerFirst(lower: 4) }
        if has("romanian", "rdl", "stiff leg", "single leg deadlift", "good morning", "pull through", "jefferson", "back extension", "hyperextension", "pullover", "skull crusher", "rollout") {
            return lowerFirst()
        }

        if has("deadlift", "rack pull") { return liftFirst(lower: 2) }
        if has("row", "pull up", "pullup", "chin up", "chinup", "shrug", "raise", "leg extension", "knee extension", "thrust", "bridge", "face pull", "kickback", "reverse fly", "rear delt fly", "pec deck", "machine chest fly", "high pull", "bench pull", "pull apart") {
            return liftFirst(squeeze: paused ? 2 : 1)
        }
        if has("curl", "crunch", "sit up", "situp", "step up", "stepup", "muscle up", "clean", "snatch", "jerk", "swing", "pallof", "svend") { return liftFirst() }

        if has("bench") && has("press") { return lowerFirst(pause: paused ? 2 : 1) }
        if has("press", "ohp", "dip", "push up", "pushup", "squat", "lunge", "fly", "flye", "flies", "tricep extension", "triceps extension", "overhead extension", "thruster", "wall ball") {
            return lowerFirst(pause: paused ? 2 : 0)
        }
        return liftFirst()
    }
}

/// Elapsed set time that only runs between start and pause, always worked out from the clock
struct TempoClock: Equatable {
    private(set) var banked: TimeInterval = 0
    private(set) var runningSince: Date?

    func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    mutating func start(at now: Date) {
        if runningSince == nil { runningSince = now }
    }

    mutating func pause(at now: Date) {
        banked = elapsed(at: now)
        runningSince = nil
    }
}

/// Typed numbers: a Portuguese keypad gives a comma, others a dot
enum NumberInput {
    static func decimal(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard t != ".", !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), t.filter({ $0 == "." }).count <= 1 else { return nil }
        if t.hasPrefix(".") { t = "0" + t }
        if t.hasSuffix(".") { t += "0" }
        return Double(t)
    }

    static func weight(_ text: String) -> Double? {
        guard let v = decimal(text), v <= 1000 else { return nil }
        return v
    }

    static func reps(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(t), v <= 999 else { return nil }
        return v
    }
}

// MARK: - Voice

/// Speaks over the user's music in headphones. Silent in test mode.
@MainActor
final class TempoVoice {
    private static var generation = 0
    private let synth = AVSpeechSynthesizer()
    private var active = false

    func activate() {
        if TestMode.active { return }
        TempoVoice.generation += 1
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
        active = true
    }

    func say(_ text: String) {
        guard active else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) } // a late word must never lag the count
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = 0.52
        synth.speak(u)
    }

    func silence() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    /// The speech engine needs a moment to stop: deactivating while it runs fails and would leave the music ducked
    func deactivate() {
        guard active else { return }
        active = false
        silence()
        TempoVoice.generation += 1
        let mine = TempoVoice.generation
        let held = synth
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            _ = held
            guard mine == TempoVoice.generation else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// MARK: - Runner

@MainActor
final class TempoRunner: ObservableObject {
    enum Stage: Equatable { case idle, countdown(Int), running, paused, finished }
    private static let lead: TimeInterval = 3

    @Published private(set) var stage = Stage.idle
    @Published private(set) var frame: TempoFrame?
    @Published private(set) var completedAll = false
    @Published var reached = 0
    var speakBreath = true

    private var plan: TempoPlan?
    private var target = 1
    private var clock = TempoClock()
    private var leadEnd = Date()
    private var timer: Timer?
    private let voice = TempoVoice()
    private var voiceOn = true

    func begin(plan: TempoPlan, target: Int, voiceOn: Bool, speakBreath: Bool) {
        guard stage == .idle else { return }
        self.plan = plan
        self.target = target
        self.voiceOn = voiceOn
        self.speakBreath = speakBreath
        if voiceOn { voice.activate() }
        startLead()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        let now = Date()
        switch stage {
        case .running:
            advance(now)
            guard stage == .running else { return }
            clock.pause(at: now)
        case .countdown:
            break
        default:
            return
        }
        stage = .paused
        voice.silence()
    }

    /// Back to the three seconds to get in position, then on from the same point
    func resume() {
        guard stage == .paused else { return }
        startLead()
    }

    /// Stopping early keeps the reps fully finished so far
    func stop() {
        if stage == .running { advance(Date()) }
        guard stage != .finished else { return }
        clock.pause(at: Date())
        reached = frame?.completed ?? 0
        completedAll = false
        stage = .finished
        endTimer()
        voice.deactivate()
    }

    func setVoice(_ on: Bool) {
        voiceOn = on
        if on, stage != .finished { voice.activate() } else if !on { voice.deactivate() }
    }

    func scene(_ phase: ScenePhase) {
        switch phase {
        case .background:
            voice.deactivate()
        case .active:
            if voiceOn, stage != .finished, stage != .idle { voice.activate() }
            tick()
        default:
            break
        }
    }

    func shutdown() {
        endTimer()
        voice.deactivate()
    }

    private func startLead() {
        leadEnd = Date().addingTimeInterval(TempoRunner.lead)
        stage = .countdown(Int(TempoRunner.lead))
        voice.say(String(Int(TempoRunner.lead)))
    }

    private func tick() {
        let now = Date()
        switch stage {
        case .countdown(let shown):
            if now < leadEnd {
                let left = Int(leadEnd.timeIntervalSince(now).rounded(.up))
                if left != shown {
                    stage = .countdown(left)
                    voice.say(String(left))
                }
            } else {
                clock.start(at: leadEnd)
                stage = .running
                advance(now)
            }
        case .running:
            advance(now)
        default:
            break
        }
    }

    private func advance(_ now: Date) {
        guard let plan else { return }
        let next = plan.frame(elapsed: clock.elapsed(at: now), target: target)
        if let cue = plan.cue(from: frame, to: next, speakBreath: speakBreath) { voice.say(cue) }
        frame = next
        if next.done { finish(now) }
    }

    private func finish(_ now: Date) {
        clock.pause(at: now)
        reached = target
        completedAll = true
        stage = .finished
        endTimer()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // room to say "done", then the music comes back up
            self?.voice.deactivate()
        }
    }

    private func endTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Guide

struct TempoGuideRequest: Identifiable {
    var id: String // the set
    var exercise: TemplateExercise
    var weight: Double
    var target: Int
}

extension TempoBreath {
    var color: Color {
        switch self {
        case .inhale: return .water
        case .exhale: return .train
        case .hold: return .fuel
        case .steady: return .mint
        }
    }
}

struct TempoGuideView: View {
    var exercise: String
    var weight: Double
    var plan: TempoPlan
    var target: Int
    var finish: (Int) -> Void

    @StateObject private var runner = TempoRunner()
    @AppStorage("tempo.voice") private var voiceOn = true
    @AppStorage("tempo.breath") private var breathOn = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var idleBefore = false

    private var moment: TempoFrame { runner.frame ?? plan.frame(elapsed: 0, target: target) }
    private var unit: String { plan.timed ? "s" : "reps" }

    var body: some View {
        ZStack {
            wash
            VStack(spacing: 14) {
                header
                stageContent
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
        .onAppear {
            idleBefore = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            runner.begin(plan: plan, target: target, voiceOn: voiceOn, speakBreath: breathOn)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = idleBefore
            runner.shutdown()
        }
        .onChange(of: voiceOn) { _, on in runner.setVoice(on) }
        .onChange(of: breathOn) { _, on in runner.speakBreath = on }
        .onChange(of: scenePhase) { _, phase in runner.scene(phase) }
    }

    private var washColor: Color {
        switch runner.stage {
        case .running: return moment.phase.breath.color
        case .finished: return runner.completedAll ? .good : .clear
        default: return .clear
        }
    }

    private var wash: some View {
        ZStack {
            Color.bg
            washColor.opacity(0.26).animation(.easeInOut(duration: 0.3), value: washColor)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise).font(.geist(17, .bold)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.7)
                if weight > 0 { Text("\(kg(weight)) kg").font(.mono(13)).foregroundStyle(Color.soft) }
            }
            Spacer()
            toggle(on: $breathOn, icon: "lungs.fill", off: "lungs", label: "Dizer a respiração", id: "guide.breath")
            toggle(on: $voiceOn, icon: "speaker.wave.2.fill", off: "speaker.slash.fill", label: "Voz", id: "guide.voice")
        }
        .padding(.top, 8)
    }

    private func toggle(on: Binding<Bool>, icon: String, off: String, label: String, id: String) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Image(systemName: on.wrappedValue ? icon : off)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on.wrappedValue ? Color.ink : Color.faint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var stageContent: some View {
        switch runner.stage {
        case .idle: countdown(3)
        case .countdown(let left): countdown(left)
        case .running, .paused: active
        case .finished: finished
        }
    }

    private func countdown(_ left: Int) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Põe-te em posição").font(.geist(30, .bold)).foregroundStyle(Color.ink)
            Text("\(left)").font(.mono(220, .semibold)).foregroundStyle(Color.train).lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityIdentifier("guide.countdown")
            Text(firstMoveHint).font(.geist(19, .semibold)).foregroundStyle(Color.soft).multilineTextAlignment(.center)
            Spacer()
            controls
        }
    }

    private var firstMoveHint: String {
        let first = runner.frame?.phase ?? plan.phases[0]
        return plan.timed ? "\(target) s · \(first.breath.word.lowercased())" : "\(first.word) primeiro · \(first.breath.word.lowercased())"
    }

    private var active: some View {
        VStack(spacing: 12) {
            counter
            TempoTrack(position: moment.position, color: moment.phase.breath.color, icon: trackIcon)
                .frame(maxHeight: .infinity)
            cueWords
            controls
        }
    }

    private var trackIcon: String {
        if plan.timed { return "timer" }
        if moment.phase.to > moment.phase.from { return "arrow.up" }
        if moment.phase.to < moment.phase.from { return "arrow.down" }
        return "pause.fill"
    }

    private var counter: some View {
        let shown = plan.timed ? moment.completed : moment.rep
        let label: String = plan.timed ? "\(shown) de \(moment.target) segundos" : "Repetição \(shown) de \(moment.target)"
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(shown)").font(.mono(116, .semibold)).foregroundStyle(Color.ink)
            Text("/ \(moment.target)\(plan.timed ? " s" : "")").font(.mono(38)).foregroundStyle(Color.soft)
        }
        .lineLimit(1).minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("guide.counter")
    }

    private var cueWords: some View {
        let paused = runner.stage == .paused
        let breath = moment.phase.breath
        return VStack(spacing: 8) {
            Text(paused ? "Em pausa" : moment.phase.word).font(.geist(58, .bold)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(paused ? "Sem pressa" : breath.word).font(.geist(36, .bold)).foregroundStyle(paused ? Color.ink : Color.bg)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(paused ? Color.white.opacity(0.1) : breath.color))
        }
    }

    private var controls: some View {
        let paused = runner.stage == .paused
        return HStack(spacing: 10) {
            bigButton(paused ? "Retomar" : "Pausa", icon: paused ? "play.fill" : "pause.fill", id: "guide.pause") {
                if paused { runner.resume() } else { runner.pause() }
            }
            bigButton("Parar", icon: "stop.fill", id: "guide.stop") { runner.stop() }
        }
    }

    private func bigButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.geist(17, .semibold)).foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: runner.completedAll ? "checkmark.circle.fill" : "stop.circle")
                .font(.system(size: 90, weight: .bold))
                .foregroundStyle(runner.completedAll ? Color.good : Color.soft)
            Text(runner.completedAll ? "Série feita" : "Paraste").font(.geist(46, .bold)).foregroundStyle(Color.ink)
            reachedEditor
            Spacer()
            PrimaryButton(title: "Registar série · \(runner.reached) \(unit)", area: .train) {
                finish(runner.reached)
                dismiss()
            }
            .disabled(runner.reached == 0)
            .opacity(runner.reached == 0 ? 0.4 : 1)
            .accessibilityIdentifier("guide.finish")
            SoftButton(title: "Fechar sem guardar") { dismiss() }
                .accessibilityIdentifier("guide.close")
        }
    }

    private var reachedEditor: some View {
        HStack(spacing: 18) {
            adjust("minus", label: "Menos") { runner.reached = max(0, runner.reached - 1) }
            Text("\(runner.reached) \(unit)").font(.mono(30, .semibold)).foregroundStyle(Color.ink).frame(minWidth: 130)
            adjust("plus", label: "Mais") { runner.reached = min(999, runner.reached + 1) }
        }
    }

    private func adjust(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.ink)
                .frame(width: 52, height: 52)
                .background(Circle().fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The bar that travels up and down in time, tall enough to follow from across a room
private struct TempoTrack: View {
    var position: Double
    var color: Color
    var icon: String

    var body: some View {
        GeometryReader { g in
            let barHeight = min(84, g.size.height * 0.3)
            let y = (g.size.height - barHeight) * CGFloat(1 - min(1, max(0, position)))
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(color.opacity(0.28))
                    .frame(height: g.size.height - y)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(color)
                    .frame(height: barHeight)
                    .overlay(Image(systemName: icon).font(.system(size: 38, weight: .black)).foregroundStyle(Color.bg))
                    .offset(y: y)
            }
        }
        .accessibilityHidden(true)
    }
}
