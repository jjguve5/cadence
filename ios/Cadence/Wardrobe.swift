// Wardrobe: clothes and shoes (photo with the background removed on the phone), the outfit of the day from the
// weather and your plan, learning what you like, clean → worn → wash, laundry loads that wash together, the gym bag.
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

    var image: UIImage? { thumb.flatMap { Data(base64Encoded: $0) }.flatMap(UIImage.init) }
    var neutral: Bool { colors.allSatisfy { c in ["000000", "FFFFFF", "808080", "1C1C1C", "F5F5F5", "2D3E63", "C8B89A", "8B8F97", "1A2540", "4A3527"].contains(c.uppercased()) || c.isEmpty } }
}

struct OutfitLog: Record, Equatable {
    static let kind = "outfit"
    var id: String { date }
    var date = Day.today
    var items: [String]
    var worn = false
}

let garmentTypes = ["base": "Base layer", "top": "Top", "layer": "Jumper / layer", "outer": "Jacket / coat", "bottom": "Trousers / shorts", "shoes": "Shoes", "gym": "Gym kit"]
let washGroups = ["darks 30°", "whites 40°", "colours 30°", "delicates", "towels 60°", "gym 30°"]

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

    /// Picks clean items for the weather and the day: enough warmth for the layers, rainproof outer and shoes when it
    /// rains, one colour accent at most, nothing worn the last two days, and more of what you usually accept.
    func outfit(for day: String = Day.today) -> [Garment] {
        if let log = record(OutfitLog.self, day) { return log.items.compactMap { record(Garment.self, $0) } }
        let call = weatherCall()
        let layers = call?.layers ?? 2
        let rain = call?.umbrella ?? false
        let smart = Agenda.shared.events(on: day).contains { e in ["seminar", "meeting", "presentation", "interview", "defesa", "reunião"].contains { e.title.lowercased().contains($0) } }
        let recent = Set((1...2).compactMap { record(OutfitLog.self, Day.add(-$0, to: day)) }.flatMap(\.items))
        let clean = garments.filter { $0.state == "clean" && $0.type != "gym" && !recent.contains($0.id) }
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
        for var g in items {
            g.wears += 1
            g.totalWears += 1
            g.accepted += 1
            g.lastWorn = day
            g.state = g.wears >= g.wearsBeforeWash ? "wash" : "worn"
            save(g)
        }
        save(OutfitLog(date: day, items: items.map(\.id), worn: true))
    }

    func swap(_ g: Garment, in day: String = Day.today) {
        var x = g
        x.swapped += 1
        save(x)
        var current = outfit(for: day).map(\.id)
        let alternatives = garments.filter { $0.type == g.type && $0.state == "clean" && $0.id != g.id }
        if let alt = alternatives.randomElement(), let i = current.firstIndex(of: g.id) { current[i] = alt.id }
        save(OutfitLog(date: day, items: current))
    }

    /// Loads that wash together, once a group fills a machine
    func laundryLoads(capacity: Int = 11) -> [(group: String, items: [Garment], full: Bool)] {
        let dirty = garments.filter { $0.state == "wash" }
        return Dictionary(grouping: dirty, by: \.washGroup).map { (group: $0.key, items: $0.value, full: $0.value.count >= capacity) }.sorted { $0.items.count > $1.items.count }
    }

    func washed(_ group: String) {
        for var g in garments where g.state == "wash" && g.washGroup == group { g.state = "drying"; g.wears = 0; save(g) }
        put("laundry", "\(Day.today)-\(group)", .number(nowMs()))
        Reminders.shared.reschedule()
    }

    func putAway(_ group: String? = nil) {
        for var g in garments where g.state == "drying" && (group == nil || g.washGroup == group) { g.state = "clean"; save(g) }
    }

    /// On training days: is there clean gym kit?
    func gymBag(on day: String = Day.today) -> (needed: Bool, clean: [Garment]) {
        let trains = all(PlanBlock.self).contains { $0.date == day && $0.type == "training" } || templates.contains { $0.weekdays.contains(Day.weekday(day)) }
        return (trains, garments.filter { $0.type == "gym" && $0.state == "clean" })
    }
}
