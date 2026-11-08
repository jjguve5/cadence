import XCTest
@testable import Cadence

/// The day's sleep is its main one, whatever mark came from Google (decision D39). The rest stay naps; nothing is added up.
final class SleepImportTests: XCTestCase {
    private let day = Fixed.saturday

    private func iso(_ minute: Int, on key: String) -> String { ISO8601DateFormatter().string(from: Day.at(minute, on: key)) }

    private func sleep(from minute: Int, asleep: Int, on key: String? = nil) -> SleepRecord {
        let key = key ?? day
        return SleepRecord(start: iso(minute, on: key), end: iso(minute + asleep, on: key), offset: 0, asleep: asleep, awake: 20, inBed: asleep + 20,
                           toFallAsleep: 5, stages: ["deep": 60], timeline: nil)
    }

    private func nap(from minute: Int, asleep: Int) -> Nap { Nap(start: iso(minute, on: day), end: iso(minute + asleep, on: day), asleep: asleep) }

    /// The bug: a one-hour nap carrying the «main» mark, with the night listed as a nap
    func testANapMarkedMainDoesNotReplaceTheNight() throws {
        let afternoon = sleep(from: 15 * 60, asleep: 60)
        let night = nap(from: 30, asleep: 450)
        let fixed = HealthDay(date: day, sleep: afternoon, naps: [night]).mainSleepFirst()
        XCTAssertEqual(fixed.sleep?.asleep, 450, "the night, not the nap and not the two added up")
        XCTAssertEqual(fixed.sleep?.start, night.start)
        XCTAssertEqual(fixed.naps, [Nap(start: afternoon.start, end: afternoon.end, asleep: 60)], "the nap is still there, as a nap")
    }

    func testADayThatIsAlreadyRightComesBackUntouched() {
        let right = HealthDay(date: day, sleep: sleep(from: 30, asleep: 450), naps: [nap(from: 15 * 60, asleep: 60)])
        XCTAssertEqual(right.mainSleepFirst(), right, "stages and all")
        let noNaps = HealthDay(date: day, sleep: sleep(from: 30, asleep: 450))
        XCTAssertEqual(noNaps.mainSleepFirst(), noNaps)
    }

    /// Only a nap on record: the night is «Sem dados», never «dormiste 1 h»
    func testADayWithOnlyADaytimeNapHasNoNight() throws {
        let afternoon = sleep(from: 15 * 60, asleep: 60)
        let fixed = HealthDay(date: day, sleep: afternoon).mainSleepFirst()
        XCTAssertNil(fixed.sleep)
        XCTAssertEqual(fixed.naps?.map(\.asleep), [60])
    }

    func testNoMainMarkAtAllStillFindsTheNight() {
        let fixed = HealthDay(date: day, sleep: nil, naps: [nap(from: 14 * 60, asleep: 40), nap(from: 60, asleep: 420)]).mainSleepFirst()
        XCTAssertEqual(fixed.sleep?.asleep, 420)
        XCTAssertEqual(fixed.naps?.map(\.asleep), [40])
    }

    /// Not naps: a short night, and a long sleep in the daytime (after a night shift)
    func testAShortNightAndALongDaySleepAreStillTheMainSleep() {
        let shortNight = HealthDay(date: day, sleep: sleep(from: 2 * 60, asleep: 150))
        XCTAssertEqual(shortNight.mainSleepFirst(), shortNight)
        let dayShift = HealthDay(date: day, sleep: sleep(from: 10 * 60, asleep: 420))
        XCTAssertEqual(dayShift.mainSleepFirst(), dayShift)
    }

    func testWhatCountsAsADaytimeNap() {
        XCTAssertFalse(HealthDay.isDaytimeNap(start: iso(9 * 60 - 1, on: day), asleep: 60), "before 9:00")
        XCTAssertTrue(HealthDay.isDaytimeNap(start: iso(9 * 60, on: day), asleep: 60))
        XCTAssertTrue(HealthDay.isDaytimeNap(start: iso(20 * 60 - 1, on: day), asleep: 179))
        XCTAssertFalse(HealthDay.isDaytimeNap(start: iso(20 * 60, on: day), asleep: 60), "from 20:00 it's the night")
        XCTAssertFalse(HealthDay.isDaytimeNap(start: iso(15 * 60, on: day), asleep: 180), "three hours or more isn't a nap")
        XCTAssertFalse(HealthDay.isDaytimeNap(start: "not a date", asleep: 60))
    }
}
