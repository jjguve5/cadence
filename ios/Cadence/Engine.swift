// The daily intelligence engine: pure functions over a snapshot of the day, so every rule is testable and
// explainable. Robust personal baselines, readiness with its confidence, conservative sleep debt, up to three
// recommendations with their evidence, when to offer a minimum viable day, and calibration statistics.
// Nothing here reads the Store; DayContext is built from it in EngineBridge.swift.
import Foundation

enum Provenance: String, Codable {
    case measured, reported, calculated, estimated, predicted, missing
}

enum Confidence: Int, Comparable, Codable {
    case low = 0, moderate = 1, high = 2
    static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }
    var label: String { ["low", "moderate", "high"][rawValue] }
    func lowered() -> Confidence { Confidence(rawValue: max(0, rawValue - 1)) ?? .low }
}

/// Median and MAD: one bad night barely moves it
struct RobustBaseline: Equatable {
    var median: Double
    var spread: Double // MAD × 1.4826, floored
    var n: Int

    func z(_ v: Double) -> Double { (v - median) / spread }

    static func of(_ values: [Double], minimum: Int = 7, floorFraction: Double = 0.03) -> RobustBaseline? {
        guard values.count >= minimum else { return nil }
        let med = Engine.median(values)
        let mad = Engine.median(values.map { abs($0 - med) }) * 1.4826
        return RobustBaseline(median: med, spread: max(mad, abs(med) * floorFraction, 0.0001), n: values.count)
    }
}

struct ReadinessResult: Equatable {
    var score: Int
    var confidence: Confidence
    var hrvZ: Double?
    var rhrZ: Double?
    var sleepRatio: Double?
    var notes: [String]
}

struct DayContext {
    var minute: Int
    // sleep
    var sleepMinutes: Int?
    var sleepNeed: Int
    var sleepBaseline: RobustBaseline?
    var sleepDebt: Int
    // physiology
    var hrv: Double?
    var hrvBaseline: RobustBaseline?
    var rhr: Double?
    var rhrBaseline: RobustBaseline?
    var readiness: ReadinessResult?
    var illnessSigns: [String]
    var lastSyncHours: Double?
    // plans
    var trainingToday: String?
    var deepWorkPlanned: Bool
    var meetingsMinutes: Int
    var deadline: (title: String, daysLeft: Int, behind: Bool)?
    var openMustDos: [(title: String, late: Bool)]
    var proteinGap: Double?
    var airBattery: Int?
    // the person
    var recentEnergy: [Int] // close-the-day energy, newest first
    var suppressedKinds: Set<String>
    var minimumDay: Bool
    var readinessUseful: Bool? // from calibration: nil = not enough evidence yet
}

enum RecAction: Equatable {
    case doMustDo(String), protectFocus, trainByFeel, earlierBedtime(Int), offerMinimumDay, placeDeepWork(String), logFood, syncAir, chargeAir, none
}

struct Recommendation: Identifiable, Equatable {
    var kind: String
    var title: String
    var why: String
    var evidence: [String]
    var confidence: Confidence
    var action: RecAction
    var actionLabel: String
    var priority: Int
    var id: String { kind }
}

enum Engine {
    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    // MARK: Readiness

    /// Contextual guidance, not a diagnosis. HRV and resting HR against robust 28-day baselines, blended with the
    /// previous day so one night can't swing it, plus sleep against your own need.
    static func readiness(hrv: Double?, hrvBase: RobustBaseline?, rhr: Double?, rhrBase: RobustBaseline?, sleepMinutes: Int?, sleepNeed: Int,
                          previousHrvZ: Double? = nil, previousRhrZ: Double? = nil, offset: Double = 0) -> ReadinessResult? {
        var parts: [(Double, Double)] = [] // score, weight
        var notes: [String] = []
        var hz: Double?, rz: Double?
        if let hrv, let b = hrvBase {
            var z = max(-3, min(3, b.z(hrv)))
            if let p = previousHrvZ { z = 0.75 * z + 0.25 * max(-3, min(3, p)) }
            hz = z
            parts.append((min(100, max(0, 62 + 16 * z)), 0.4))
        } else { notes.append("HRV not available yet") }
        if let rhr, let b = rhrBase {
            var z = max(-3, min(3, b.z(rhr)))
            if let p = previousRhrZ { z = 0.75 * z + 0.25 * max(-3, min(3, p)) }
            rz = z
            parts.append((min(100, max(0, 62 - 16 * z)), 0.3))
        } else { notes.append("Resting HR not available yet") }
        var ratio: Double?
        if let s = sleepMinutes {
            let r = Double(s) / Double(max(1, sleepNeed))
            ratio = r
            parts.append((min(100, max(0, 100 * (r - 0.55) / 0.45)), 0.3))
        } else { notes.append("Last night's sleep hasn't synced") }
        guard !parts.isEmpty else { return nil }
        let w = parts.map(\.1).reduce(0, +)
        let score = Int(min(100, max(1, parts.map { $0.0 * $0.1 }.reduce(0, +) / w + offset)).rounded())
        var conf: Confidence = parts.count == 3 ? .high : parts.count == 2 ? .moderate : .low
        if let n = [hrvBase?.n, rhrBase?.n].compactMap({ $0 }).min(), n < 14 { conf = min(conf, .moderate) }
        return ReadinessResult(score: score, confidence: conf, hrvZ: hz, rhrZ: rz, sleepRatio: ratio, notes: notes)
    }

    // MARK: Sleep debt

    /// Conservative: the last 7 nights, each shortfall capped at 2 h, extra sleep repays at most 1 h a night,
    /// the total capped at 10 h. An estimate from wearable sleep, which is good at duration and rough at stages.
    static func sleepDebt(nights: [Int], need: Int) -> Int {
        let recent = nights.prefix(7)
        let total = recent.map { n -> Int in
            let gap = need - n
            return gap > 0 ? min(gap, 120) : max(gap, -60)
        }.reduce(0, +)
        return min(600, max(0, total))
    }

    // MARK: Minimum viable day

    static func minimumDayReasons(_ c: DayContext) -> [String] {
        var out: [String] = []
        if c.illnessSigns.count >= 2 { out.append("Several body signals are off together (\(c.illnessSigns.prefix(2).joined(separator: ", ")))") }
        if let s = c.sleepMinutes, s < 330 { out.append("Only \(duration(s)) of sleep") }
        if let r = c.readiness, r.score < 35, r.confidence >= .moderate { out.append("Readiness \(r.score)") }
        if c.meetingsMinutes >= 360 { out.append("\(duration(c.meetingsMinutes)) of calendar events") }
        if let last = c.recentEnergy.first, last <= 1, c.recentEnergy.prefix(2).allSatisfy({ $0 <= 2 }) { out.append("You've reported low energy two days running") }
        return out
    }

    // MARK: Recommendations

    /// Up to three, most useful first. Each carries its observations and how sure it is; nothing is based on data
    /// that hasn't arrived, and kinds you keep dismissing go quiet for a while.
    static func recommendations(_ c: DayContext) -> [Recommendation] {
        var out: [Recommendation] = []
        let stale = (c.lastSyncHours ?? 99) > 8
        let morning = c.minute < 13 * 60, evening = c.minute >= 17 * 60

        // Safety and commitments first: deterministic
        for m in c.openMustDos where m.late {
            out.append(Recommendation(kind: "mustdo", title: "\(m.title) now", why: "It's a must-do and its time has passed.", evidence: ["Scheduled earlier today, not answered yet"], confidence: .high, action: .doMustDo(m.title), actionLabel: "Done", priority: 100))
            break
        }

        // A lighter day, offered, never imposed
        let reasons = minimumDayReasons(c)
        if !c.minimumDay, !reasons.isEmpty, morning || c.minute < 16 * 60 {
            out.append(Recommendation(kind: "minimumday", title: "Make today a minimum viable day", why: "Keep the essentials, drop the optional, and count it as a full day. Medicines and must-dos stay as they are.", evidence: reasons, confidence: reasons.count >= 2 ? .high : .moderate, action: .offerMinimumDay, actionLabel: "Switch on", priority: 90))
        }

        // Short sleep with important work: protect the best focus window
        let shortSleep: Bool = {
            guard let s = c.sleepMinutes else { return false }
            if let b = c.sleepBaseline { return Double(s) < b.median - 60 }
            return s < c.sleepNeed - 75
        }()
        if shortSleep, c.deepWorkPlanned || (c.deadline.map { $0.daysLeft <= 7 } ?? false), morning {
            var ev = ["Slept \(duration(c.sleepMinutes ?? 0))" + (c.sleepBaseline.map { ", your usual is \(duration(Int($0.median)))" } ?? "")]
            if let d = c.deadline { ev.append("\(d.title) due in \(d.daysLeft) days") }
            var why = "After a short night, attention is best early and fades sooner. Put the hard thinking first and keep meetings later."
            if let t = c.trainingToday { why += " Keep \(t), and let your warm-up decide how hard to go." }
            out.append(Recommendation(kind: "focus", title: "Protect your morning focus block", why: why, evidence: ev, confidence: c.sleepBaseline != nil ? .moderate : .low, action: .protectFocus, actionLabel: "Start focus", priority: 80))
        }

        // Training on a low-readiness day: decide by feel, never an automatic cut
        if let t = c.trainingToday, let r = c.readiness, r.score < 50 {
            var ev = ["Readiness \(r.score) (\(r.confidence.label) confidence)"]
            if let z = r.hrvZ, z < -1 { ev.append("HRV below your usual") }
            if let z = r.rhrZ, z > 1 { ev.append("Resting HR above your usual") }
            var conf = r.confidence.lowered()
            if c.readinessUseful == false { conf = .low; ev.append("Your readiness hasn't predicted your sessions well so far") }
            out.append(Recommendation(kind: "trainfeel", title: "Train, and let the warm-up decide", why: "\(t) stays on the plan. If the warm-up sets feel heavy, stop each set a rep or two earlier; if they feel normal, train as planned. Readiness is a hint, not an instruction.", evidence: ev, confidence: conf, action: .trainByFeel, actionLabel: "Open the session", priority: 70))
        }

        // A deadline falling behind
        if let d = c.deadline, d.behind, !c.deepWorkPlanned, c.minute < 18 * 60 {
            out.append(Recommendation(kind: "deadline", title: "Place a deep-work block for \(d.title)", why: "At the current pace it finishes after the deadline. One block today keeps it on track.", evidence: ["Due in \(d.daysLeft) days", "Pace from your last 14 days of progress"], confidence: .moderate, action: .placeDeepWork(d.title), actionLabel: "Place it", priority: 65))
        }

        // Sleep debt: a small, realistic change tonight
        if c.sleepDebt >= 180 {
            let earlier = c.sleepDebt >= 360 ? 30 : 20
            out.append(Recommendation(kind: "bedtime", title: "Lights out \(earlier) minutes earlier tonight", why: "Small, regular paybacks work better than one long lie-in, which shifts your body clock.", evidence: ["About \(duration(c.sleepDebt)) short over the last 7 nights (an estimate)"], confidence: c.sleepBaseline != nil ? .moderate : .low, action: .earlierBedtime(earlier), actionLabel: "Set it", priority: evening ? 75 : 55))
        }

        // Protein in the evening
        if let g = c.proteinGap, g >= 30, c.minute >= 16 * 60, c.minute < 21 * 60 {
            out.append(Recommendation(kind: "protein", title: "\(Int(g)) g protein left today", why: "Spreading protein over the day supports recovery from training; a shake or a fridge portion closes most of it.", evidence: ["From what you've logged today"], confidence: .moderate, action: .logFood, actionLabel: "Log food", priority: 55))
        }

        // Data that hasn't arrived
        if stale, c.sleepMinutes == nil, morning {
            out.append(Recommendation(kind: "sync", title: "Sync your Air", why: "Today's sleep and HRV haven't arrived, so readiness and the plan are running on yesterday.", evidence: [c.lastSyncHours.map { "Last sync \(Int($0)) hours ago" } ?? "No sync yet"], confidence: .high, action: .syncAir, actionLabel: "Open Fitbit", priority: 60))
        }
        if let b = c.airBattery, b <= 15 {
            out.append(Recommendation(kind: "battery", title: "Charge your Air", why: "Below 15%, tonight's sleep and HRV may be lost.", evidence: ["Battery \(b)%"], confidence: .high, action: .chargeAir, actionLabel: "OK", priority: 45))
        }

        // Stale data lowers confidence in anything built on physiology
        if stale {
            for i in out.indices where ["focus", "trainfeel", "bedtime"].contains(out[i].kind) {
                out[i].confidence = out[i].confidence.lowered()
                out[i].evidence.append("Air data is \(Int(c.lastSyncHours ?? 0)) hours old")
            }
        }
        return Array(out.filter { !c.suppressedKinds.contains($0.kind) || $0.kind == "mustdo" }.sorted { $0.priority > $1.priority }.prefix(3))
    }

    // MARK: Calibration

    struct Calibration: Equatable {
        var n: Int
        var spearman: Double?
        var modelError: Double?
        var baselineError: Double?
        var verdict: String
    }

    /// Does the prediction beat simply guessing your own average? Spearman rank correlation and mean absolute
    /// error against that naive baseline; under 10 pairs it says so instead of showing a number.
    static func calibrate(_ pairs: [(predicted: Double, observed: Double)]) -> Calibration {
        let n = pairs.count
        guard n >= 10 else { return Calibration(n: n, spearman: nil, modelError: nil, baselineError: nil, verdict: n == 0 ? "No pairs yet" : "\(n) of 10 pairs needed") }
        let obsMean = pairs.map(\.observed).reduce(0, +) / Double(n)
        // put predictions on the outcome's scale by their own ranks before comparing errors
        let model = pairs.map { abs($0.predicted - $0.observed) }.reduce(0, +) / Double(n)
        let base = pairs.map { abs(obsMean - $0.observed) }.reduce(0, +) / Double(n)
        let rho = spearman(pairs.map(\.predicted), pairs.map(\.observed))
        let verdict: String
        if let rho, rho >= 0.3, model <= base * 0.95 { verdict = "Useful: it beats guessing your average" }
        else if let rho, rho >= 0.15 { verdict = "Weak: a hint at best" }
        else { verdict = "Not useful yet: no better than your average" }
        return Calibration(n: n, spearman: rho, modelError: model, baselineError: base, verdict: verdict)
    }

    static func ranks(_ v: [Double]) -> [Double] {
        let sorted = v.enumerated().sorted { $0.element < $1.element }
        var r = [Double](repeating: 0, count: v.count)
        var i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count && sorted[j + 1].element == sorted[i].element { j += 1 }
            let avg = Double(i + j) / 2 + 1
            for k in i...j { r[sorted[k].offset] = avg }
            i = j + 1
        }
        return r
    }

    static func spearman(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 3 else { return nil }
        let ra = ranks(a), rb = ranks(b)
        let ma = ra.reduce(0, +) / Double(ra.count), mb = rb.reduce(0, +) / Double(rb.count)
        let cov = zip(ra, rb).map { ($0 - ma) * ($1 - mb) }.reduce(0, +)
        let va = ra.map { ($0 - ma) * ($0 - ma) }.reduce(0, +), vb = rb.map { ($0 - mb) * ($0 - mb) }.reduce(0, +)
        guard va > 0, vb > 0 else { return nil }
        return cov / sqrt(va * vb)
    }

    // MARK: Experiments

    struct ExperimentResult: Equatable {
        var before: Double
        var during: Double
        var difference: Double
        var effectSize: Double // difference in pooled SDs
        var nBefore: Int
        var nDuring: Int
        var summary: String
    }

    /// Before against during, with the size of the change in pooled standard deviations, and plain words about
    /// what that can and can't mean
    static func experiment(before: [Double], during: [Double]) -> ExperimentResult? {
        guard before.count >= 5, during.count >= 5 else { return nil }
        func mean(_ v: [Double]) -> Double { v.reduce(0, +) / Double(v.count) }
        func variance(_ v: [Double]) -> Double { let m = mean(v); return v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(max(1, v.count - 1)) }
        let mb = mean(before), md = mean(during)
        let pooled = sqrt(((Double(before.count) - 1) * variance(before) + (Double(during.count) - 1) * variance(during)) / Double(before.count + during.count - 2))
        let d = pooled > 0 ? (md - mb) / pooled : 0
        let size = abs(d) < 0.2 ? "no clear change" : abs(d) < 0.5 ? "a small change" : abs(d) < 0.8 ? "a moderate change" : "a large change"
        return ExperimentResult(before: mb, during: md, difference: md - mb, effectSize: d, nBefore: before.count, nDuring: during.count,
                                summary: "\(size.prefix(1).uppercased() + size.dropFirst()) (\(before.count) days before, \(during.count) during). Other things changed too, so this is a pattern, not proof.")
    }
}
