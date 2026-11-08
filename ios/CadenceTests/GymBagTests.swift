import XCTest
@testable import Cadence

/// The gym bag as the user listed it (decision D42): fixed items, and the clothes from the wardrobe by the weather
final class GymBagTests: XCTestCase {
    private let shirt = Garment(id: "S", name: "T-shirt de treino", type: "gym")
    private let shorts = Garment(id: "C", name: "Calções pretos", type: "gym")
    private let trousers = Garment(id: "L", name: "Calças de treino", type: "gym")
    private let jacket = Garment(id: "J", name: "Casaco de treino", type: "gym")

    private func ids(_ kit: [Garment], layers: Int?, rain: Bool = false) -> [String] {
        NightRules.bagClothes(kit: kit, layers: layers, rain: rain).map(\.id)
    }

    func testTheFixedItemsAreTheOnesAskedFor() {
        XCTAssertEqual(NightRules.bagBasics.map(\.title), ["Toalha de banho", "Toalha de treino", "Garrafa", "Cadeado", "Cuecas", "Meias", "Sabão", "Champô", "Sapatilhas", "Chinelos"])
        XCTAssertEqual(Set(NightRules.bagBasics.map(\.id)).count, NightRules.bagBasics.count, "each one is ticked on its own")
    }

    func testShortsWhenWarmTrousersAndAJacketWhenCold() {
        let kit = [jacket, shorts, trousers, shirt]
        XCTAssertEqual(ids(kit, layers: 2), ["g.S", "g.C"], "warm: t-shirt and shorts, no jacket")
        XCTAssertEqual(ids(kit, layers: 3), ["g.S", "g.L", "g.J"], "cold: trousers and a jacket")
        XCTAssertEqual(ids(kit, layers: 1, rain: true), ["g.S", "g.C", "g.J"], "warm but raining: the jacket too")
    }

    func testWithoutAForecastNothingIsAssumed() {
        XCTAssertEqual(ids([jacket, shorts, shirt], layers: nil), ["g.S", "g.C"], "no jacket")
        XCTAssertEqual(NightRules.bagClothes(kit: [], layers: nil, rain: false).map(\.title), ["T-shirt", "Calças ou calções"])
    }

    func testAPieceNotAvailableIsNeverOffered() {
        var wet = shorts
        wet.state = "drying"
        XCTAssertEqual(ids([wet, trousers, shirt], layers: 1), ["g.S", "g.L"], "the shorts are drying: the trousers instead")
        XCTAssertEqual(ids([wet, shirt], layers: 1), ["g.S"], "nothing else to offer: it shows apart as not available")
    }

    func testWithNoPieceOfAKindItIsStillOnTheListByName() {
        XCTAssertEqual(NightRules.bagClothes(kit: [], layers: 1, rain: false).map(\.title), ["T-shirt", "Calções"])
        XCTAssertEqual(NightRules.bagClothes(kit: [], layers: 4, rain: false).map(\.title), ["T-shirt", "Calças", "Casaco"])
    }

    func testTheLeastWornPieceGoesFirst() {
        var worn = shirt
        worn.state = "worn"
        worn.wears = 1
        let other = Garment(id: "S2", name: "T-shirt azul", type: "gym")
        XCTAssertEqual(ids([worn, other], layers: 1).first, "g.S2")
    }

    func testWhichPartOfTheKitAPieceIs() {
        func slot(_ name: String, _ type: String = "gym") -> NightRules.BagSlot { NightRules.bagSlot(Garment(name: name, type: type)) }
        XCTAssertEqual(slot("CALÇÕES azuis"), .shorts)
        XCTAssertEqual(slot("Leggings"), .trousers)
        XCTAssertEqual(slot("Sweatshirt"), .jacket, "not a t-shirt")
        XCTAssertEqual(slot("Tshirt branca"), .shirt)
        XCTAssertEqual(slot("Toalha de treino"), .other, "a fixed item, not one from the wardrobe")
        XCTAssertEqual(slot("Preto", "bottom"), .trousers, "a piece of a known type goes by its type")
    }
}
