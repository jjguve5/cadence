// Phase 2.3: what the European Portuguese interface needs beyond the translated words themselves.
import XCTest
@testable import Cadence

final class PortugueseTextTests: XCTestCase {
    /// A built plate's name puts the cooking method after the food, agreeing with it: the method is saved into the
    /// meal's name, so "Pescada cozido" would stay in the history
    func testTheCookingMethodAgreesWithTheFood() {
        XCTAssertEqual(CookMethod.boiled.after("Pescada"), "cozida")
        XCTAssertEqual(CookMethod.grilled.after("Febras"), "grelhadas")
        XCTAssertEqual(CookMethod.scrambled.after("Ovos"), "mexidos")
        XCTAssertEqual(CookMethod.boiled.after("Ovos"), "cozidos")
        XCTAssertEqual(CookMethod.grilled.after("Lombo de porco"), "grelhado")
        XCTAssertEqual(CookMethod.baked.after("Perna de frango"), "assada")
        XCTAssertEqual(CookMethod.stewed.after("Carne picada"), "estufada", "carne is feminine though it ends in e")
        XCTAssertEqual(CookMethod.fried.after("Lulas"), "fritas")
        XCTAssertEqual(CookMethod.breaded.after("Tofu"), "panado")
        // every protein with every method it offers gives one of the four endings
        for p in MealBuilder.proteins {
            for m in p.methods {
                let word = m.after(p.name)
                XCTAssertTrue(["o", "a", "os", "as"].contains { word.hasSuffix($0) }, "\(p.name) \(word)")
                XCTAssertEqual(word, word.lowercased(), "\(p.name) \(word)")
            }
        }
    }

    /// Moving something to tomorrow in Portuguese, with or without the accent, moves it (and keeps the keyword)
    func testMovingToTomorrowReadsTheAccent() {
        let today = "2026-11-03"
        for text in ["Mudar estudo para amanhã", "Mudar estudo para amanha", "mudar estudo para Amanhã"] {
            XCTAssertEqual(QuickCapture.parse(text, today: today), .move(keyword: "estudo", toDay: "2026-11-04"), text)
        }
        XCTAssertEqual(QuickCapture.parse("Move studying to tomorrow", today: today), .move(keyword: "studying", toDay: "2026-11-04"), "English still works")
    }
}
