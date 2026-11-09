// Pip's chests, collection and house (asked for by the user on 9 Nov). Points only ever come from your real day, as
// before; here they turn into chests. What a chest gives is kept as a record (pipChest), so what you own is exactly
// what you opened. Nothing is ever taken away: a bad day earns less, it never costs anything.
//   Wood: one for every 100 points. Silver: one for each level reached. Gold: one for every 7 closed days in a row.
// A chest never gives something you already have. The art comes from ios/art (pip_wardrobe.py, pip_room.py).
import Foundation

enum PipRarity: Int, CaseIterable, Comparable {
    case common, rare, epic, legendary
    static func < (a: PipRarity, b: PipRarity) -> Bool { a.rawValue < b.rawValue }
    var label: String {
        switch self {
        case .common: return "Comum"
        case .rare: return "Raro"
        case .epic: return "Épico"
        case .legendary: return "Lendário"
        }
    }
    /// 0xRRGGBB, for the ring around a piece and the glow when it comes out of a chest
    var hex: UInt32 {
        switch self {
        case .common: return 0xA3ABBD
        case .rare: return 0x4DA3FF
        case .epic: return 0xB37BFF
        case .legendary: return 0xFFC53D
        }
    }
}

private func piece(_ id: String, _ name: String, _ slot: String, _ rarity: PipRarity, _ layer: String, _ emoji: String) -> PipAccessory {
    PipAccessory(id: id, name: name, slot: slot, level: 0, layer: "Acc " + layer, icon: "gift.fill", rarity: rarity, emoji: emoji)
}

/// What Pip wears that comes from chests. `id` is the head picture's suffix and `layer` the Lottie layer, as in pip_wardrobe.py
let pipChestAccessories: [PipAccessory] = [
    piece("party-hat", "Chapéu de festa", "head", .common, "Party hat", "🥳"),
    piece("beanie", "Gorro", "head", .common, "Beanie", "🧶"),
    piece("cap", "Boné", "head", .common, "Cap", "🧢"),
    piece("flower", "Flor", "head", .common, "Flower", "🌸"),
    piece("head-bow", "Laço de cabeça", "head", .common, "Head bow", "🎀"),
    piece("top-hat", "Cartola", "head", .rare, "Top hat", "🎩"),
    piece("chef-hat", "Chapéu de chef", "head", .rare, "Chef hat", "🍳"),
    piece("cowboy", "Chapéu de cowboy", "head", .rare, "Cowboy hat", "🤠"),
    piece("grad-cap", "Capelo", "head", .rare, "Grad cap", "🎓"),
    piece("santa", "Gorro de Natal", "head", .rare, "Santa hat", "🎅"),
    piece("pirate", "Chapéu de pirata", "head", .epic, "Pirate hat", "☠️"),
    piece("wizard", "Chapéu de feiticeiro", "head", .epic, "Wizard hat", "🧙"),
    piece("viking", "Capacete viking", "head", .epic, "Viking helmet", "🛡️"),
    piece("crown", "Coroa", "head", .legendary, "Crown", "👑"),
    piece("halo", "Auréola", "head", .legendary, "Halo", "😇"),
    piece("heart-glasses", "Óculos de coração", "face", .rare, "Heart glasses", "😍"),
    piece("monocle", "Monóculo", "face", .rare, "Monocle", "🧐"),
    piece("eye-patch", "Pala de pirata", "face", .rare, "Eye patch", "🦜"),
    piece("mustache", "Bigode", "face", .common, "Mustache", "🥸"),
    piece("clown-nose", "Nariz vermelho", "face", .common, "Clown nose", "🤡"),
    piece("ski-goggles", "Óculos de ski", "face", .epic, "Ski goggles", "🥽"),
    piece("3d-glasses", "Óculos 3D", "face", .rare, "3D glasses", "🍿"),
    piece("visor", "Visor do futuro", "face", .legendary, "Visor", "🤖"),
    piece("cheek-star", "Estrela na bochecha", "face", .common, "Cheek star", "⭐️"),
    piece("tie", "Gravata", "neck", .common, "Tie", "👔"),
    piece("bandana", "Bandana", "neck", .common, "Bandana", "🐶"),
    piece("bell", "Coleira com guizo", "neck", .common, "Bell collar", "🔔"),
    piece("pearls", "Colar de pérolas", "neck", .rare, "Pearls", "🦪"),
    piece("lei", "Colar de flores", "neck", .rare, "Lei", "🌺"),
    piece("gold-chain", "Corrente com diamante", "neck", .epic, "Gold chain", "💎"),
    piece("winter-scarf", "Cachecol de inverno", "neck", .rare, "Winter scarf", "🧣"),
    piece("amulet", "Amuleto", "neck", .legendary, "Amulet", "🔮"),
    piece("cape", "Capa de herói", "back", .epic, "Cape", "🦸"),
    piece("wings", "Asas", "back", .legendary, "Wings", "🪽"),
    piece("butterfly", "Asas de borboleta", "back", .epic, "Butterfly wings", "🦋"),
    piece("balloon", "Balão", "back", .rare, "Balloon", "🎈"),
]

/// A piece of Pip's house: the picture is "room-<id>". No rarity: it comes with the house.
struct PipRoomItem: Identifiable, Equatable {
    var id: String
    var name: String
    var slot: String
    var rarity: PipRarity?
    var emoji: String

    init(_ id: String, _ name: String, _ rarity: PipRarity?, _ emoji: String) {
        self.id = id
        self.name = name
        self.slot = String(id.split(separator: "-").first ?? "")
        self.rarity = rarity
        self.emoji = emoji
    }
}

/// The room's layers, bottom first: the pictures are stacked in this order, and Pip stands on the rug
let pipRoomSlots = ["wall", "floor", "window", "decor", "left", "right", "rug"]

/// What a slot shows when nothing was chosen
let pipRoomDefaults = ["wall": "wall-cream", "floor": "floor-wood", "window": "window-day"]

let pipRoomItems: [PipRoomItem] = [
    PipRoomItem("wall-cream", "Parede creme", nil, "🏠"),
    PipRoomItem("wall-stripes", "Riscas azuis", .common, "🟦"),
    PipRoomItem("wall-mint", "Parede menta", .common, "🍃"),
    PipRoomItem("wall-dots", "Bolinhas", .rare, "🍬"),
    PipRoomItem("wall-brick", "Tijolo", .rare, "🧱"),
    PipRoomItem("wall-forest", "Floresta", .epic, "🌿"),
    PipRoomItem("wall-night", "Céu estrelado", .epic, "🌌"),
    PipRoomItem("wall-royal", "Parede real", .legendary, "⚜️"),
    PipRoomItem("floor-wood", "Soalho", nil, "🪵"),
    PipRoomItem("floor-check", "Xadrez", .common, "🏁"),
    PipRoomItem("floor-carpet", "Alcatifa", .rare, "🧵"),
    PipRoomItem("floor-grass", "Relva", .rare, "🌱"),
    PipRoomItem("floor-marble", "Mármore", .epic, "🏛️"),
    PipRoomItem("window-day", "Dia de sol", nil, "☀️"),
    PipRoomItem("window-sunset", "Pôr do sol", .common, "🌇"),
    PipRoomItem("window-night", "Noite de lua", .rare, "🌙"),
    PipRoomItem("window-snow", "Neve", .rare, "❄️"),
    PipRoomItem("window-space", "Espaço", .legendary, "🪐"),
    PipRoomItem("decor-picture", "Quadro", .common, "🖼️"),
    PipRoomItem("decor-clock", "Relógio", .common, "🕓"),
    PipRoomItem("decor-bunting", "Bandeirinhas", .rare, "🎉"),
    PipRoomItem("decor-poster", "Póster do foguetão", .rare, "🚀"),
    PipRoomItem("decor-trophy", "Prateleira de troféus", .epic, "🏆"),
    PipRoomItem("decor-lights", "Luzinhas", .epic, "✨"),
    PipRoomItem("left-plant", "Planta", .common, "🪴"),
    PipRoomItem("left-cactus", "Cato", .common, "🌵"),
    PipRoomItem("left-bookshelf", "Estante", .rare, "📚"),
    PipRoomItem("left-lamp", "Candeeiro", .rare, "💡"),
    PipRoomItem("left-aquarium", "Aquário", .epic, "🐠"),
    PipRoomItem("right-beanbag", "Pufe", .common, "🫘"),
    PipRoomItem("right-armchair", "Poltrona", .rare, "🛋️"),
    PipRoomItem("right-table", "Mesa do lanche", .rare, "🍰"),
    PipRoomItem("right-bed", "Cama", .epic, "🛏️"),
    PipRoomItem("right-arcade", "Máquina de jogos", .epic, "🕹️"),
    PipRoomItem("right-treasure", "Tesouro", .legendary, "💰"),
    PipRoomItem("rug-round", "Tapete redondo", .common, "🟢"),
    PipRoomItem("rug-stripes", "Tapete às riscas", .common, "🟥"),
    PipRoomItem("rug-heart", "Tapete coração", .rare, "💗"),
    PipRoomItem("rug-star", "Tapete estrela", .rare, "🌟"),
]

func pipSlotName(_ slot: String) -> String {
    let names = ["head": "Cabeça", "face": "Cara", "neck": "Pescoço", "back": "Costas", "wall": "Parede", "floor": "Chão", "window": "Janela",
                 "decor": "Na parede", "left": "Canto esquerdo", "right": "Canto direito", "rug": "Tapete"]
    return names[slot] ?? slot
}

/// Something a chest can give: a piece to wear or a piece of the house
struct PipPrize: Identifiable, Equatable {
    var id: String
    var name: String
    var slot: String
    var rarity: PipRarity
    var emoji: String
    var isRoom: Bool
    /// "Para a cabeça do Pip", "Para a casa · Parede"
    var place: String { isRoom ? "Para a casa · \(pipSlotName(slot))" : "Para o Pip · \(pipSlotName(slot))" }
}

let pipPrizes: [PipPrize] =
    pipChestAccessories.map { PipPrize(id: $0.id, name: $0.name, slot: $0.slot, rarity: $0.rarity ?? .common, emoji: $0.emoji ?? "🎁", isRoom: false) }
    + pipRoomItems.compactMap { item in item.rarity.map { PipPrize(id: item.id, name: item.name, slot: item.slot, rarity: $0, emoji: item.emoji, isRoom: true) } }

enum ChestKind: String, CaseIterable, Identifiable {
    case gold, silver, wood // the best first: that's the order they're opened in
    var id: String { rawValue }
    var name: String {
        switch self {
        case .gold: return "Baú de ouro"
        case .silver: return "Baú de prata"
        case .wood: return "Baú de madeira"
        }
    }
    var how: String {
        switch self {
        case .gold: return "7 dias fechados seguidos"
        case .silver: return "subir de nível"
        case .wood: return "cada \(ChestRules.pointsPerChest) pontos"
        }
    }
    /// The chance of each rarity, in 100
    var odds: [(PipRarity, Double)] {
        switch self {
        case .wood: return [(.common, 70), (.rare, 25), (.epic, 5), (.legendary, 0)]
        case .silver: return [(.common, 25), (.rare, 50), (.epic, 22), (.legendary, 3)]
        case .gold: return [(.common, 0), (.rare, 35), (.epic, 45), (.legendary, 20)]
        }
    }
}

/// A chest you opened and what came out. One record each, id "<kind>-<n>", so the same chest is never opened twice.
struct PipChest: Record, Equatable {
    static let kind = "pipChest"
    var id: String
    var chest: String
    var prize: String
    var date = Day.today
    var at = nowMs()
}

enum ChestRules {
    static let pointsPerChest = 100
    static let shakes = 3

    /// How many times 7 closed days in a row happened (each run of 14 counts twice)
    static func weekRuns(_ closed: [String]) -> Int {
        var runs = 0, run = 0
        var previous: String?
        for day in Set(closed).sorted() {
            run = previous.map { Day.add(1, to: $0) == day } == true ? run + 1 : 1
            if run % 7 == 0 { runs += 1 }
            previous = day
        }
        return runs
    }

    /// The closed days in a row up to `day` (or the day before it, while today is still open)
    static func currentRun(_ closed: [String], upTo day: String) -> Int {
        let set = Set(closed)
        var d = set.contains(day) ? day : Day.add(-1, to: day)
        var run = 0
        while set.contains(d) {
            run += 1
            d = Day.add(-1, to: d)
        }
        return run
    }

    static func earned(_ kind: ChestKind, points: Int, level: Int, closed: [String]) -> Int {
        switch kind {
        case .wood: return max(0, points) / pointsPerChest
        case .silver: return max(0, level - 1)
        case .gold: return weekRuns(closed)
        }
    }

    /// What a chest gives among what's missing: `roll` (0..<1) picks the rarity by the chest's odds, `which` (0..<1) the
    /// piece. When nothing of that rarity is left, the nearest rarity below, then above. nil when nothing is missing.
    static func pick(_ kind: ChestKind, from missing: [PipPrize], roll: Double, which: Double) -> PipPrize? {
        guard !missing.isEmpty else { return nil }
        var wanted = PipRarity.common
        var left = min(max(roll, 0), 0.999999) * 100
        for (rarity, chance) in kind.odds {
            if left < chance { wanted = rarity; break }
            left -= chance
            wanted = rarity
        }
        let below = PipRarity.allCases.filter { $0 <= wanted }.sorted(by: >)
        let above = PipRarity.allCases.filter { $0 > wanted }.sorted()
        for rarity in below + above {
            let pool = missing.filter { $0.rarity == rarity }
            if !pool.isEmpty { return pool[min(pool.count - 1, Int(min(max(which, 0), 0.999999) * Double(pool.count)))] }
        }
        return nil
    }
}

@MainActor
extension Store {
    /// What you own from chests
    var pipOwned: Set<String> { Set(all(PipChest.self).map(\.prize)) }

    var pipMissing: [PipPrize] {
        let owned = pipOwned
        return pipPrizes.filter { !owned.contains($0.id) }
    }

    func owns(_ a: PipAccessory) -> Bool { a.rarity == nil ? a.level <= level.level : pipOwned.contains(a.id) }
    func owns(_ item: PipRoomItem) -> Bool { item.rarity == nil || pipOwned.contains(item.id) }

    private var closedDays: [String] { days.values.filter { $0.closedAt != nil }.map(\.date) }

    func chestsEarned(_ kind: ChestKind) -> Int {
        ChestRules.earned(kind, points: totalPoints, level: level.level, closed: closedDays)
    }

    func chestsOpened(_ kind: ChestKind) -> Int { all(PipChest.self).filter { $0.chest == kind.rawValue }.count }

    /// The chests waiting to be opened, the best first. None when there's nothing left to win.
    var chestsReady: [ChestKind] {
        let missing = pipMissing.count
        guard missing > 0 else { return [] }
        let ready = ChestKind.allCases.flatMap { kind in Array(repeating: kind, count: max(0, chestsEarned(kind) - chestsOpened(kind))) }
        return Array(ready.prefix(missing))
    }

    var pointsToNextChest: Int { ChestRules.pointsPerChest - max(0, totalPoints) % ChestRules.pointsPerChest }

    /// Closed days in a row towards the next gold chest (0–6)
    var goldRun: Int { ChestRules.currentRun(closedDays, upTo: Day.today) % 7 }

    /// Opens one chest of this kind, if one is waiting: saves what came out and returns it
    @discardableResult
    func openChest(_ kind: ChestKind, roll: Double = Double.random(in: 0..<1), which: Double = Double.random(in: 0..<1)) -> PipPrize? {
        guard canChange else { return nil }
        let opened = chestsOpened(kind)
        guard chestsEarned(kind) > opened, let prize = ChestRules.pick(kind, from: pipMissing, roll: roll, which: which) else { return nil }
        save(PipChest(id: "\(kind.rawValue)-\(opened + 1)", chest: kind.rawValue, prize: prize.id))
        return prize
    }

    /// Puts a prize to use: Pip wears it, or it goes into the house
    func use(_ prize: PipPrize) {
        put("pipLook", prize.slot, .string(prize.id))
    }

    /// The house as it is now, bottom layer first: what you chose for each slot if you own it, or what comes with the house
    func pipRoom() -> [PipRoomItem] {
        let look = records("pipLook")
        var room: [PipRoomItem] = []
        for slot in pipRoomSlots {
            if case .string(let id)? = look[slot], let item = pipRoomItems.first(where: { $0.id == id && $0.slot == slot }), owns(item) {
                room.append(item)
            } else if let id = pipRoomDefaults[slot], let item = pipRoomItems.first(where: { $0.id == id }) {
                room.append(item)
            }
        }
        return room
    }

    /// nil empties the slot (a slot that comes with the house goes back to its own)
    func place(_ item: PipRoomItem?, slot: String) {
        put("pipLook", slot, .string(item?.id ?? "none"))
    }
}
