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

    /// Every stored value that is shown has a Portuguese label: a missing one would fall back to the English key on screen
    func testEveryStoredValueShownHasAPortugueseLabel() {
        for a in aisles { XCTAssertNotEqual(shoppingAisleLabel(a), a, "aisle \(a)") }
        for c in moneyCategories { XCTAssertNotEqual(moneyCategoryLabel(c), c, "money category \(c)") }
        for g in washGroups { XCTAssertNotEqual(washGroupLabel(g), g, "wash group \(g)") }
        for st in ["clean", "worn", "wash", "drying"] { XCTAssertNotEqual(garmentStateLabel(st), st, "garment state \(st)") }
        for key in journalQuestions { XCTAssertNotEqual(journalText(key), key, "journal question \(key)") }
    }

    /// A bought mark's id is fixed for a given line: changing the function would orphan the marks already saved
    func testABoughtMarkIdIsStable() {
        XCTAssertEqual(Store.boughtKey(week: "2026-11-02", line: "maçã gala"), "2026-11-02_maca-gala_376f937a")
        XCTAssertEqual(Store.boughtKey(week: "2026-11-02", line: "whey"), "2026-11-02_whey")
    }

    /// The timed tempo coach starts with «Já», in the Portuguese voice
    func testTheTimedCoachStartsInPortuguese() {
        let plank = TempoPlan.forExercise(id: "plank", name: "")
        XCTAssertEqual(plank.cue(from: nil, to: plank.frame(elapsed: 0, target: 30), speakBreath: true), "Já")
    }
}
