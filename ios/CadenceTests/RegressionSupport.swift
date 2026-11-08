// Phase 2.0 regression base: shared setup for RegressionPreservedTests and RegressionPlannedChangeTests.
// Every test builds its own store on its own file in a temporary folder, from synthetic data only. Nothing is read
// from a real phone, the server, Fitbit or Apple Health: the store has no server connection, so it never syncs.
// Dates are fixed (the week of Monday 2 to Sunday 8 November 2026); where the app only offers "today", the test builds
// its data relative to today so the result is the same whatever day it runs.
import XCTest
@testable import Cadence

enum Fixed {
    static let monday = "2026-11-02"
    static let tuesday = "2026-11-03"
    static let wednesday = "2026-11-04"
    static let friday = "2026-11-06"
    static let saturday = "2026-11-07"
    static let sunday = "2026-11-08"
}

extension Saved {
    /// Puts a typed record where the app keeps it: extra[kind][id]
    mutating func add<T: Record>(_ record: T) {
        var all = extra[T.kind] ?? [:]
        all[record.id] = JSONValue.from(record)
        extra[T.kind] = all
    }

    /// A plain value record (the "bedshift", "brushhead", "bought" kind)
    mutating func put(_ type: String, _ id: String, _ value: JSONValue) {
        var all = extra[type] ?? [:]
        all[id] = value
        extra[type] = all
    }
}

class RegressionCase: XCTestCase {
    private var folders: [URL] = []

    /// A store on a fresh file holding exactly what `build` puts in. `seeded` is set so the app adds no starter data.
    @MainActor
    func makeStore(_ build: (inout Saved) -> Void = { _ in }) throws -> Store {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("regression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        var saved = Saved()
        saved.seeded = true
        build(&saved)
        let file = folder.appendingPathComponent("cadence.json")
        _ = try Storage.write(saved, to: file)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "regression-\(UUID().uuidString)"))
        let store = Store(file: file, defaults: defaults)
        XCTAssertEqual(store.storage, .ok, "the synthetic file must load")
        XCTAssertFalse(store.connection.configured, "a test store must never reach a server")
        return store
    }

    override func tearDown() {
        for f in folders { try? FileManager.default.removeItem(at: f) }
        folders = []
        super.tearDown()
    }
}
