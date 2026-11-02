// Pip's lines and the friend suggestions: enough of them, clean text, and no repeats where repeats were promised.
import XCTest
@testable import Cadence

/// Keeps ledgers as encoded JSON, the way the store does, so a "new launch" only has the saved bytes.
@MainActor
private final class MemoryLedgers: FriendLedgerStore {
    var saved: [String: Data] = [:]

    func friendLedger(_ personId: String) -> FriendLedger? {
        saved[personId].flatMap { try? JSONDecoder().decode(FriendLedger.self, from: $0) }
    }

    func saveFriendLedger(_ ledger: FriendLedger, _ personId: String) {
        saved[personId] = try? JSONEncoder().encode(ledger)
    }
}

final class PipLinesTests: XCTestCase {
    private func allLines(name: String = "", what: String? = "Creatine") -> [String] {
        var out: [String] = []
        for situation in PipSituation.allCases {
            for position in 0..<situation.pool.count {
                out.append(Pip.line(situation, position: position, seed: 42, name: name, what: what))
            }
        }
        return out
    }

    private func freshDefaults(_ function: String = #function) -> UserDefaults {
        let suite = "cadence.tests.\(function)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testAtLeastFiveThousandUniqueLines() {
        let lines = allLines()
        XCTAssertGreaterThanOrEqual(Set(lines).count, 5000)
        let named = allLines(name: "João Nobrega")
        XCTAssertGreaterThanOrEqual(Set(named).count, 5000)
        XCTAssertTrue(named.contains { $0.contains("João") })
        XCTAssertFalse(named.contains { $0.contains("Nobrega") }, "first name only")
    }

    func testEveryPositionOfAPoolIsADifferentLine() {
        for situation in PipSituation.allCases {
            for name in ["", "João"] {
                for seed: UInt64 in [0, 1, 99, 12_345_678_901_234, UInt64.max] {
                    let count = situation.pool.count
                    var seen = Set<String>()
                    for position in 0..<count { seen.insert(Pip.line(situation, position: position, seed: seed, name: name, what: "Creatine")) }
                    XCTAssertEqual(seen.count, count, "\(situation) seed \(seed) name \(name)")
                }
            }
        }
    }

    func testPartsAreClean() {
        XCTAssertGreaterThan(PipLines.named.count, PipSituation.allCases.map { $0.pool.openers.count }.max() ?? 0)
        for situation in PipSituation.allCases {
            let pool = situation.pool
            for part in pool.openers + pool.bodies + pool.closers {
                XCTAssertFalse(part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(situation)")
            }
        }
        for line in allLines() {
            XCTAssertFalse(line.contains("  "), line)
            XCTAssertFalse(line.contains("\u{2014}"), line)
            XCTAssertFalse(line.contains("{"), line)
            XCTAssertEqual(line, line.trimmingCharacters(in: .whitespaces))
        }
    }

    func testSayDoesNotRepeatUntilThePoolIsExhausted() {
        let defaults = freshDefaults()
        let count = PipSituation.focusing.pool.count
        var seen = Set<String>()
        for _ in 0..<count { seen.insert(Pip.say(.focusing, name: "", defaults: defaults)) }
        XCTAssertEqual(seen.count, count)
    }

    func testStableHoldsWithinThePeriodAndMovesAfter() {
        let defaults = freshDefaults()
        let now = Date()
        let first = Pip.stable(.waterBehind, name: "", defaults: defaults, now: now)
        XCTAssertEqual(first, Pip.stable(.waterBehind, name: "", defaults: defaults, now: now))
        let later = Pip.stable(.waterBehind, name: "", defaults: defaults, now: now.addingTimeInterval(2 * 3600))
        XCTAssertNotEqual(first, later)
    }

    func testFactsAndLengthLimit() {
        let line = Pip.line(.proteinBehind, position: 3, seed: 7, name: "", lead: "40 g protein left today.", maxLength: 70)
        XCTAssertTrue(line.hasPrefix("40 g protein left today."))
        let filled = Pip.line(.mustDoOpen, position: 0, seed: 7, name: "", what: "Creatine")
        XCTAssertFalse(filled.contains("{"))
        XCTAssertTrue(filled.lowercased().contains("creatine"))
    }
}

final class FriendMessagesTests: XCTestCase {
    func testAtLeastFiveThousandUniqueLinesInEachLanguage() {
        for language in FriendLanguage.allCases {
            let lines = FriendMessages.allLines(language)
            XCTAssertGreaterThanOrEqual(Set(lines).count, 5000)
            XCTAssertEqual(Set(lines).count, lines.count, "\(language)")
            XCTAssertEqual(lines.count, FriendMessages.poolSize(language))
        }
    }

    func testPartsAreClean() {
        for language in FriendLanguage.allCases {
            for category in FriendCategory.allCases {
                let pool = category.pool(language)
                for part in pool.openers + pool.bodies + pool.closers {
                    XCTAssertFalse(part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            for name in ["Ana", ""] {
                for line in FriendMessages.allLines(language, name: name) {
                    XCTAssertFalse(line.contains("  "), line)
                    XCTAssertFalse(line.contains("\u{2014}"), line)
                    XCTAssertFalse(line.contains("{"), line)
                    XCTAssertFalse(line.contains(",!") || line.contains(",?") || line.contains(" ,"), line)
                }
            }
        }
    }

    func testPortugueseStaysEuropean() {
        let brazilian = ["você", "vocês", "legal", "celular", "a gente", "fazendo", "falando", "pensando", "te amo"]
        for line in FriendMessages.allLines(.pt) {
            let lower = line.lowercased()
            for word in brazilian { XCTAssertFalse(lower.contains(word), line) }
        }
    }

    @MainActor
    func testNoRepeatsAcrossALongDrawForOnePerson() {
        let ledgers = MemoryLedgers()
        var seen = Set<String>()
        for _ in 0..<3000 {
            let s = FriendMessages.next(for: "ana", language: .pt, in: ledgers)
            seen.insert(FriendMessages.text(s, personId: "ana", name: "Ana"))
        }
        XCTAssertEqual(seen.count, 3000)
    }

    @MainActor
    func testRepeatsAreAllowedAcrossPeople() {
        let ledgers = MemoryLedgers()
        var ana = Set<String>(), rui = Set<String>()
        for _ in 0..<3000 {
            ana.insert(FriendMessages.text(FriendMessages.next(for: "ana", language: .en, in: ledgers), personId: "ana", name: ""))
            rui.insert(FriendMessages.text(FriendMessages.next(for: "rui", language: .en, in: ledgers), personId: "rui", name: ""))
        }
        XCTAssertFalse(ana.isDisjoint(with: rui))
        XCTAssertNotEqual(ana, rui)
    }

    @MainActor
    func testTrackingSurvivesARelaunch() {
        let first = MemoryLedgers()
        var seen = Set<String>()
        for _ in 0..<50 { seen.insert(FriendMessages.next(for: "ana", language: .pt, in: first).id) }
        FriendMessages.setLanguage(.en, for: "ana", in: first)

        let relaunched = MemoryLedgers()
        relaunched.saved = first.saved
        XCTAssertEqual(FriendMessages.language(for: "ana", in: relaunched), .en)
        for _ in 0..<50 { seen.insert(FriendMessages.next(for: "ana", language: .pt, in: relaunched).id) }
        XCTAssertEqual(seen.count, 100)
    }

    @MainActor
    func testLanguageDefaultsToPortugueseAndIsPerPerson() {
        let ledgers = MemoryLedgers()
        XCTAssertEqual(FriendMessages.language(for: "ana", in: ledgers), .pt)
        FriendMessages.setLanguage(.en, for: "ana", in: ledgers)
        XCTAssertEqual(FriendMessages.language(for: "ana", in: ledgers), .en)
        XCTAssertEqual(FriendMessages.language(for: "rui", in: ledgers), .pt)
    }

    @MainActor
    func testFillKeepsWhatsShownAndReplacesWhatsUsed() {
        let ledgers = MemoryLedgers()
        FriendMessages.fill(for: "ana", language: .pt, in: ledgers)
        let shown = FriendMessages.showing(for: "ana", language: .pt, in: ledgers)
        XCTAssertEqual(shown.count, FriendMessages.showCount)
        FriendMessages.fill(for: "ana", language: .pt, in: ledgers)
        XCTAssertEqual(FriendMessages.showing(for: "ana", language: .pt, in: ledgers), shown, "reopening must not burn or change lines")

        FriendMessages.markUsed(shown[0], for: "ana", in: ledgers)
        FriendMessages.fill(for: "ana", language: .pt, in: ledgers)
        let after = FriendMessages.showing(for: "ana", language: .pt, in: ledgers)
        XCTAssertEqual(after.count, FriendMessages.showCount)
        XCTAssertFalse(after.map(\.id).contains(shown[0].id))
    }

    func testBirthdayAndLongGapLinesOnlyWhenTheyFit() {
        var p = Person(name: "Ana")
        p.lastContact = "2026-06-01"
        XCTAssertFalse(FriendMessages.categories(for: p, today: "2026-06-05").contains(.beenAWhile))
        XCTAssertTrue(FriendMessages.categories(for: p, today: "2026-08-01").contains(.beenAWhile))
        XCTAssertFalse(FriendMessages.categories(for: p, today: "2026-08-01").contains(.birthday))
        p.birthday = "08-05"
        XCTAssertTrue(FriendMessages.categories(for: p, today: "2026-08-01").contains(.birthday))
        XCTAssertTrue(FriendMessages.categories(for: p, today: "2026-08-10").contains(.birthday))
        p.birthday = "01-03"
        XCTAssertTrue(FriendMessages.categories(for: p, today: "2026-12-30").contains(.birthday), "across new year")
    }
}
