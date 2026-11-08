// Wardrobe: clothes and shoes (photo with the background removed on the phone), the outfit of the day from the
// weather and your plan, learning what you like, clean → worn → wash, laundry loads that wash together, the gym bag.
// Phase 2.10: the five laundry stages (sugerida, para lavar, em lavagem, a secar, disponível) on top of the four saved
// states, the count back to zero only at «Arrumada», loads only with known care, and the assisted add.
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

struct Garment: Record, Equatable {
    static let kind = "garment"
    var id = UUID().uuidString
    var name: String
    var type = "top" // base, top, layer, outer, bottom, shoes, gym
    var colors: [String] = [] // hex
    var warmth = 2 // 1 light ... 5 very warm
    var rainproof = false
    var style = "casual" // casual, smart, sport
    var washGroup = "darks 30°"
    var wearsBeforeWash = 3
    var wears = 0
    var state = "clean" // clean, worn, wash, drying
    var lastWorn: String?
    var accepted = 0
    var swapped = 0
    var thumb: String? // small base64 JPEG
    var price: Double?
    var totalWears = 0
    /// «Em lavagem» (phase 2.10): in the machine. Only on a piece whose state is "wash"; an optional field on top of
    /// the four saved states, so an older build reads the piece as «para lavar»
    var washing: Bool?
    /// What the app filled in and you haven't confirmed (the assisted add, phase 2.10): today only "washGroup", when
    /// you didn't choose how the piece washes. Nil for everything you set yourself (every piece added before)
    var unsure: [String]?

    var image: UIImage? { thumb.flatMap { Data(base64Encoded: $0) }.flatMap(UIImage.init) }
    var neutral: Bool { colors.allSatisfy { c in ["000000", "FFFFFF", "808080", "1C1C1C", "F5F5F5", "2D3E63", "C8B89A", "8B8F97", "1A2540", "4A3527"].contains(c.uppercased()) || c.isEmpty } }

    func isUnsure(_ attribute: String) -> Bool { unsure?.contains(attribute) == true }

    /// The laundry stage shown (design v17: five). Worked out from the saved state and `washing`; «Sugerida» (still
    /// worn, one use from the wash limit or past it) is never saved
    var stage: LaundryStage {
        switch state {
        case "drying": return .drying
        case "wash": return washing == true ? .washing : .toWash
        case "worn": return wears >= max(1, wearsBeforeWash - 1) ? .suggested : .available
        default: return .available
        }
    }

    /// Can go into an outfit: clean, or worn fewer times than its wash limit (phase 2.10: a piece worn once can be
    /// suggested again). At its limit, for washing, in the machine or drying: never
    var wearable: Bool { washing != true && (state == "clean" || (state == "worn" && wears < wearsBeforeWash)) }

    /// Maybe the same piece (Nova peça): the same category, and the same name or a very close colour. Only a warning
    static func similar(_ a: Garment, _ b: Garment) -> Bool {
        guard a.type == b.type else { return false }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespacesAndNewlines) }
        if !fold(a.name).isEmpty && fold(a.name) == fold(b.name) { return true }
        guard let ha = a.colors.first, let hb = b.colors.first, let x = hexComponents(ha), let y = hexComponents(hb) else { return false }
        let distance = ((x.r - y.r) * (x.r - y.r) + (x.g - y.g) * (x.g - y.g) + (x.b - y.b) * (x.b - y.b)).squareRoot()
        return distance < 0.12
    }
}

/// A saved hex colour ("2D3E63") as 0...1 components
func hexComponents(_ hex: String) -> (r: Double, g: Double, b: Double)? {
    guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
    return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}

/// The colour family of a saved hex colour, for the Roupeiro's «Cor» filter (shown only, never saved)
func colourFamily(_ hex: String) -> String? {
    guard let c = hexComponents(hex) else { return nil }
    let high = max(c.r, c.g, c.b), low = min(c.r, c.g, c.b), d = high - low
    if high < 0.18 { return "Preto" }
    if d / high < 0.18 { return high > 0.85 ? "Branco" : "Cinzento" }
    var hue: Double
    if high == c.r { hue = (c.g - c.b) / d } else if high == c.g { hue = (c.b - c.r) / d + 2 } else { hue = (c.r - c.g) / d + 4 }
    hue *= 60
    if hue < 0 { hue += 360 }
    if hue < 15 || hue >= 340 { return "Vermelho" }
    if hue < 50 { return high < 0.55 ? "Castanho" : d / high < 0.35 ? "Bege" : "Laranja" }
    if hue < 70 { return "Amarelo" }
    if hue < 170 { return "Verde" }
    if hue < 255 { return "Azul" }
    if hue < 290 { return "Roxo" }
    return "Rosa"
}

/// The five laundry stages of the design, in its order. Shown only: the saved states stay the four of Garment.state
enum LaundryStage: CaseIterable {
    case suggested, toWash, washing, drying, available

    var label: String {
        switch self {
        case .suggested: return "Sugerida"
        case .toWash: return "Para lavar"
        case .washing: return "Em lavagem"
        case .drying: return "A secar"
        case .available: return "Disponível"
        }
    }

    /// The state label it shows with (never colour alone)
    var dataState: DataState {
        switch self {
        case .suggested: return .suggested
        case .toWash: return .pending
        case .washing: return .washing
        case .drying: return .drying
        case .available: return .confirmed
        }
    }
}

struct OutfitLog: Record, Equatable {
    static let kind = "outfit"
    var id: String { date }
    var date = Day.today
    var items: [String]
    var worn = false
}

let garmentTypes = ["base": "Camada interior", "top": "Parte de cima", "layer": "Camisola / camada", "outer": "Casaco / sobretudo", "bottom": "Calças / calções", "shoes": "Calçado", "gym": "Roupa de treino"]
let washGroups = ["darks 30°", "whites 40°", "colours 30°", "delicates", "towels 60°", "gym 30°"]

/// The wash groups stay stored as above (Garment.washGroup, laundry records); this is the name shown
func washGroupLabel(_ group: String) -> String {
    ["darks 30°": "escuros 30°", "whites 40°": "brancos 40°", "colours 30°": "cores 30°", "delicates": "delicados", "towels 60°": "toalhas 60°", "gym 30°": "treino 30°"][group] ?? group
}

/// Garment.state stays "clean", "worn", "wash" or "drying"; this is the word shown
func garmentStateLabel(_ state: String) -> String {
    ["clean": "disponível", "worn": "usada", "wash": "para lavar", "drying": "a secar"][state] ?? state
}

/// Garment.style stays "casual", "smart" or "sport"; this is the word shown
func garmentStyleLabel(_ style: String) -> String {
    ["casual": "Casual", "smart": "Formal", "sport": "Desportivo"][style] ?? style
}

enum Cutout {
    /// Lifts the subject off the background (Vision, on the phone) and makes a small thumbnail
    static func thumbnail(_ image: UIImage) -> (UIImage, String?) {
        var result = image
        if let cg = image.cgImage {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            if (try? handler.perform([request])) != nil, let obs = request.results?.first,
               let buffer = try? obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true) {
                let ci = CIImage(cvPixelBuffer: buffer)
                if let out = CIContext().createCGImage(ci, from: ci.extent) { result = UIImage(cgImage: out) }
            }
        }
        let side: CGFloat = 220
        let scale = side / max(result.size.width, result.size.height)
        let size = CGSize(width: result.size.width * scale, height: result.size.height * scale)
        let thumb = UIGraphicsImageRenderer(size: size).image { _ in result.draw(in: CGRect(origin: .zero, size: size)) }
        return (thumb, thumb.pngData()?.base64EncodedString())
    }

    /// The dominant colour, for matching
    static func color(_ image: UIImage) -> String? {
        guard let ci = CIImage(image: image) else { return nil }
        let f = CIFilter.areaAverage()
        f.inputImage = ci
        f.extent = ci.extent
        guard let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return String(format: "%02X%02X%02X", px[0], px[1], px[2])
    }
}

@MainActor
extension Store {
    var garments: [Garment] { all(Garment.self) }

    /// Picks wearable items for the weather and the day (clean, or worn below their wash limit): enough warmth for the
    /// layers, rainproof outer and shoes when it rains, one colour accent at most, nothing worn the last two days, and
    /// more of what you usually accept.
    func outfit(for day: String = Day.today) -> [Garment] {
        if let log = record(OutfitLog.self, day) { return log.items.compactMap { record(Garment.self, $0) } }
        let call = weatherCall()
        let layers = call?.layers ?? 2
        let rain = call?.umbrella ?? false
        let smart = Agenda.shared.events(on: day).contains { e in ["seminar", "meeting", "presentation", "interview", "defesa", "reunião"].contains { e.title.lowercased().contains($0) } }
        let lastTwo = Set((1...2).map { Day.add(-$0, to: day) })
        // A piece worn on its own («Vesti hoje» in the Roupeiro) has no outfit log, so its last wear counts too
        let recent = Set((1...2).compactMap { record(OutfitLog.self, Day.add(-$0, to: day)) }.flatMap(\.items))
            .union(garments.filter { g in g.lastWorn.map { lastTwo.contains($0) } ?? false }.map(\.id))
        let clean = garments.filter { $0.wearable && $0.type != "gym" && !recent.contains($0.id) }
        func best(_ type: String, warmth: ClosedRange<Int>? = nil, rainproof: Bool = false, accent: Bool = true) -> Garment? {
            clean.filter { $0.type == type && (warmth?.contains($0.warmth) ?? true) && (!rainproof || $0.rainproof) && (accent || $0.neutral) }
                .max { score($0, smart) < score($1, smart) }
        }
        var out: [Garment] = []
        if let top = best("top") { out.append(top) }
        if layers >= 3, let layer = best("layer", accent: out.allSatisfy(\.neutral)) { out.append(layer) }
        if let bottom = best("bottom", warmth: layers >= 3 ? 2...5 : 1...5, accent: out.allSatisfy(\.neutral)) { out.append(bottom) }
        if layers >= 3 || rain, let outer = best("outer", warmth: layers >= 4 ? 3...5 : 1...5, rainproof: rain) ?? best("outer") { out.append(outer) }
        if let shoes = best("shoes", rainproof: rain) ?? best("shoes") { out.append(shoes) }
        if layers >= 4, let base = best("base") { out.insert(base, at: 0) }
        return out
    }

    private func score(_ g: Garment, _ smart: Bool) -> Double {
        let liked = Double(g.accepted + 1) / Double(g.accepted + g.swapped + 2)
        let rest = Double(g.lastWorn.map { Day.between($0, Day.today) } ?? 14) / 14
        return liked * 2 + min(1, rest) + (smart && g.style == "smart" ? 1.5 : 0) + (!smart && g.style == "sport" ? -0.5 : 0)
    }

    func wear(_ items: [Garment], on day: String = Day.today) {
        for g in items { countWear(g, on: day) }
        save(OutfitLog(date: day, items: items.map(\.id), worn: true))
    }

    /// One use, counted only when you confirm you wore it. At its wash limit the piece stays where it is and shows as
    /// «Sugerida para lavar» (Garment.stage); only «Para lavar» sends it to the laundry (design v17, decision 96)
    private func countWear(_ garment: Garment, on day: String) {
        var g = garment
        g.wears += 1
        g.totalWears += 1
        g.accepted += 1
        g.lastWorn = day
        g.state = "worn"
        save(g)
    }

    /// «Vesti hoje» on one piece (Roupeiro): one use, as wear() counts it. Today's worn outfit, if there is one, gains
    /// the piece; a suggested outfit is left as it is
    func wearPiece(_ g: Garment, on day: String = Day.today) {
        countWear(g, on: day)
        if var log = record(OutfitLog.self, day), log.worn, !log.items.contains(g.id) {
            log.items.append(g.id)
            save(log)
        }
    }

    /// Desfazer for «Vesti hoje»: the pieces and the day's outfit go back to exactly what they were
    func undoWear(_ before: [Garment], log: OutfitLog?, on day: String = Day.today) {
        restoreGarments(before)
        if let log { save(log) } else if let now = record(OutfitLog.self, day) { remove(now) }
    }

    /// Desfazer for a wardrobe or laundry step: the pieces go back exactly as they were
    func restoreGarments(_ before: [Garment]) {
        for g in before { save(g) }
    }

    func swap(_ g: Garment, in day: String = Day.today) {
        var x = g
        x.swapped += 1
        save(x)
        var current = outfit(for: day).map(\.id)
        let alternatives = garments.filter { $0.type == g.type && $0.wearable && $0.id != g.id }
        if let alt = alternatives.randomElement(), let i = current.firstIndex(of: g.id) { current[i] = alt.id }
        save(OutfitLog(date: day, items: current))
    }

    /// Loads that wash together, once a group fills a machine (pieces already in the machine are left out)
    func laundryLoads(capacity: Int = 11) -> [(group: String, items: [Garment], full: Bool)] {
        let dirty = garments.filter { $0.state == "wash" && $0.washing != true }
        return Dictionary(grouping: dirty, by: \.washGroup).map { (group: $0.key, items: $0.value, full: $0.value.count >= capacity) }.sorted { $0.items.count > $1.items.count }
    }

    /// The group's pieces for washing go to dry. The wear count stays until you put a piece away («Arrumada»)
    func washed(_ group: String) {
        for var g in garments where g.state == "wash" && g.washGroup == group { g.state = "drying"; g.washing = nil; save(g) }
        put("laundry", "\(Day.today)-\(group)", .number(nowMs()))
        Reminders.shared.reschedule()
    }

    /// «Arrumada» for everything drying (or one group): back in the wardrobe as available, the count back to zero.
    /// The history of uses (totalWears) stays
    func putAway(_ group: String? = nil) {
        for g in garments where g.state == "drying" && (group == nil || g.washGroup == group) { putAway(piece: g) }
    }

    /// «Arrumada» for one piece
    func putAway(piece garment: Garment) {
        var g = garment
        g.state = "clean"
        g.wears = 0
        g.washing = nil
        save(g)
    }

    /// «Para lavar»: you send the piece to the Lavandaria, whatever its count; it leaves the available pieces
    func sendToWash(_ garment: Garment) {
        var g = garment
        g.state = "wash"
        g.washing = nil
        save(g)
    }

    /// «Pôr a lavar agora»: the pieces go into the machine («em lavagem», on top of «para lavar»). The load's start is
    /// kept per wash group as before («laundry» records, same id and value as the old «Já lavei»), so the «Lavagem
    /// concluída» reminder two hours later still comes, and older builds read it as they did
    /// Returns the laundry records as they were before, for Desfazer.
    @discardableResult
    func startWashing(_ items: [Garment]) -> [String: JSONValue] {
        for var g in items {
            g.state = "wash"
            g.washing = true
            save(g)
        }
        var before: [String: JSONValue] = [:]
        for group in Set(items.map(\.washGroup)) {
            let id = "\(Day.today)-\(group)"
            if let old = records("laundry")[id] { before[id] = old }
            put("laundry", id, .number(nowMs()))
        }
        Reminders.shared.reschedule()
        return before
    }

    /// Desfazer for «Pôr a lavar agora»: the pieces as they were, and each laundry record as it was. A load started
    /// earlier the same day keeps its start; a record written just now gets a value the reminder ignores, rather than a
    /// deletion, so nothing new waits in the queue (this id has never reached the server)
    func undoStartWashing(_ items: [Garment], laundryBefore: [String: JSONValue]) {
        restoreGarments(items)
        for group in Set(items.map(\.washGroup)) {
            let id = "\(Day.today)-\(group)"
            put("laundry", id, laundryBefore[id] ?? .bool(false))
        }
        Reminders.shared.reschedule()
    }

    /// «Já lavei»: out of the machine, the pieces go to dry. Nothing is marked washed without this tap
    func hangToDry(_ items: [Garment]) {
        for var g in items where g.state == "wash" {
            g.state = "drying"
            g.washing = nil
            save(g)
        }
        // nothing of the group left in the machine: no «estender» reminder for it (a value the reminder ignores)
        for group in Set(items.map(\.washGroup)) where !garments.contains(where: { $0.washGroup == group && $0.washing == true }) {
            let id = "\(Day.today)-\(group)"
            if case .number = records("laundry")[id] { put("laundry", id, .bool(false)) }
        }
        Reminders.shared.reschedule()
    }

    /// A load to plan (Planear lavagem): the group's pieces for washing whose care you set yourself, and the pieces
    /// waiting to be washed whose wash group the app only guessed, which never go in by themselves («Desconhecido»)
    func loadPlan(_ group: String) -> (known: [Garment], unknown: [Garment]) {
        let waiting = garments.filter { $0.stage == .toWash || $0.stage == .suggested }
        let known = waiting.filter { $0.stage == .toWash && $0.washGroup == group && !$0.isUnsure("washGroup") }
        let unknown = waiting.filter { $0.isUnsure("washGroup") }
        return (known.sorted { $0.name < $1.name }, unknown.sorted { $0.name < $1.name })
    }

    /// Training days left this week (the day included) against the clean training kit. A need only when there is
    /// more training than clean kit and some kit is waiting to be washed; `group` is where most of that kit washes
    func gymKitNeed(on day: String = Day.today) -> (trainings: Int, clean: Int, group: String)? {
        let sunday = Day.add(6, to: Day.weekStart(day))
        var trainings = 0
        var d = day
        while d <= sunday {
            if gymBag(on: d).needed { trainings += 1 }
            d = Day.add(1, to: d)
        }
        let kit = garments.filter { $0.type == "gym" }
        let clean = kit.filter { $0.state == "clean" }.count
        let waiting = kit.filter { $0.stage == .toWash || $0.stage == .suggested }
        let counts = Dictionary(grouping: waiting, by: \.washGroup).mapValues(\.count)
        guard trainings > clean, let group = counts.keys.sorted().max(by: { (counts[$0] ?? 0) < (counts[$1] ?? 0) }) else { return nil }
        return (trainings, clean, group)
    }

    /// A piece you may already have, for the warning in Nova peça (never blocks saving)
    func lookalike(of g: Garment) -> Garment? {
        garments.filter { $0.id != g.id }.sorted { $0.name < $1.name }.first { Garment.similar($0, g) }
    }

    /// «É a mesma»: what the new entry adds (a photo, colours, a price) goes into the piece you already have, without
    /// a second piece. What you had set stays
    func mergeGarment(_ entry: Garment, into existing: Garment) {
        var g = existing
        if g.thumb == nil { g.thumb = entry.thumb }
        if g.colors.isEmpty { g.colors = entry.colors }
        if g.price == nil { g.price = entry.price }
        save(g)
    }

    /// On training days: is there clean gym kit?
    func gymBag(on day: String = Day.today) -> (needed: Bool, clean: [Garment]) {
        let trains = all(PlanBlock.self).contains { $0.date == day && $0.type == "training" } || templates.contains { $0.weekdays.contains(Day.weekday(day)) }
        return (trains, garments.filter { $0.type == "gym" && $0.state == "clean" })
    }
}
