// Local data protection (phase 1). The data file is never written over when it can't be read; writes are atomic
// and checked against what is in memory, record by record; copies are validated; recovery can be undone; and a
// file written by this version still reads in the previous one. Synthetic data only: nothing from a real phone.
import XCTest
@testable import Cadence

final class StorageTests: XCTestCase {
    private var dir: URL!
    private var file: URL { dir.appendingPathComponent("cadence.json") }
    private var copies: URL { dir.appendingPathComponent("cadence-copies", isDirectory: true) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Today's format with one of everything that matters: a habit and its completion (an id with "|"), a closed day
    /// with accents, the profile, readiness feedback, generic records holding objects and plain values (true, text,
    /// numbers), Fitbit days, the sync queue, a deletion waiting to go and the server connection
    static func sample() -> Saved {
        var s = Saved()
        let habit = PromiseItem(id: "P1", title: "Creatina", kind: .mustDo, schedule: Schedule(rule: .daily, start: "2026-11-01", minute: 470), created: 1_793_524_150_000)
        s.promises[habit.id] = habit
        let done = PromiseLog(promiseId: "P1", date: "2026-11-04", status: .done, at: 1_793_790_000_000)
        s.logs[done.id] = done
        s.days["2026-11-03"] = DayEntry(date: "2026-11-03", rating: 4, note: "Dia bom: ação, ténis e \"aspas\" / barra", top3: ["Pernas"], top3Done: [true], closedAt: 1_793_741_954_837.537, score: 45, points: 45, energy: 4)
        s.profile.weightKg = 78
        s.profile.kcalTarget = 3160
        s.profile.areasOff = ["money"]
        s.feedback["2026-11-02"] = ReadinessFeedback(date: "2026-11-02", score: 52, felt: -1)
        s.extra["water"] = ["W1": .object(["id": .string("W1"), "date": .string("2026-11-04"), "minute": .number(891), "ml": .number(250)])]
        s.extra["food"] = ["F1": .object(["id": .string("F1"), "name": .string("+ Proteína Aroma Manga"), "kcal": .number(137.5), "tags": .array([.string("a"), .null])])]
        s.extra["medlog"] = ["M1|2026-11-04|480": .object(["medId": .string("M1"), "taken": .bool(true), "minute": .number(480)])]
        s.extra["gymBag"] = ["2026-11-02": .bool(true)]
        s.extra["showerWhen"] = ["2026-11-06": .string("morning")]
        s.extra["bedshift"] = ["2026-11-01": .number(15)]
        s.health["2026-11-07"] = HealthDay(date: "2026-11-07", sleep: SleepRecord(start: "2026-11-07T00:12:00Z", end: "2026-11-07T06:12:00Z", asleep: 350), steps: 1371, rhr: 56, hrv: 113.9)
        s.device = Device(name: "Air", battery: 34)
        s.healthErrors = ["vo2": "not available"]
        s.lastHealth = 1_794_060_000
        s.connection = Connection(server: "https://example.invalid", token: "t")
        s.dirty = ["water:W1": 3]
        s.tombstones = ["log:X|2026-11-01"]
        s.rev = 192
        s.seeded = true
        return s
    }

    private func bytes() -> Data? { try? Data(contentsOf: file) }

    private func failing(_ error: Error) -> Storage.Disk {
        var d = Storage.Disk()
        d.write = { _, _ in throw error }
        return d
    }

    private func object(_ s: Saved) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Storage.encoder().encode(s)) as? [String: Any])
    }

    // MARK: Reading

    func testMissingFileIsTheOnlyFreshStart() {
        guard case .fresh = Storage.load(from: file) else { return XCTFail("a missing file is a new install") }
    }

    func testEmptyCutShortForeignOrGarbageFilesAreCorruptNeverFresh() throws {
        let full = try Storage.encoder().encode(Self.sample())
        let cut = full.prefix(full.count / 2)
        for content in [Data(), Data("not json at all".utf8), Data("[1,2,3]".utf8), Data("{}".utf8), Data("{\"foo\":1}".utf8), Data(cut)] {
            try content.write(to: file)
            guard case .corrupt = Storage.load(from: file) else { XCTFail("\(content.count) bytes should be corrupt"); continue }
        }
    }

    func testValidFileReadsBackEveryRecordExactly() throws {
        let s = Self.sample()
        try Storage.write(s, to: file)
        guard case .ok(let back, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(back, s) // every field of every record, not just counts
        XCTAssertEqual(back.logs["P1|2026-11-04"], s.logs["P1|2026-11-04"])
        XCTAssertEqual(back.extra["gymBag"]?["2026-11-02"], .bool(true))
        XCTAssertEqual(back.extra["showerWhen"]?["2026-11-06"], .string("morning"))
        XCTAssertEqual(back.days["2026-11-03"]?.note, "Dia bom: ação, ténis e \"aspas\" / barra")
        XCTAssertEqual(back.personalRecords, 10)
    }

    func testAPersonalCategoryThatCantBeReadIsReportedAndTheRestIsIntact() throws {
        var o = try object(Self.sample())
        o["promises"] = ["X": ["title": 5]] // a habit this version can't read
        try JSONSerialization.data(withJSONObject: o).write(to: file)
        guard case .incompatible(let saved, let categories, _) = Storage.load(from: file) else { return XCTFail("should be incompatible") }
        XCTAssertEqual(categories, ["promises"])
        let s = Self.sample()
        XCTAssertEqual(saved.logs, s.logs)
        XCTAssertEqual(saved.extra, s.extra)
        XCTAssertEqual(saved.days, s.days)
        XCTAssertEqual(saved.profile, s.profile)
    }

    func testFitbitDataThatCantBeReadIsReportedAsRecoverable() throws {
        var o = try object(Self.sample())
        o["health"] = ["2026-11-07": ["date": 5]]
        try JSONSerialization.data(withJSONObject: o).write(to: file)
        guard case .incompatible(_, let categories, _) = Storage.load(from: file) else { return XCTFail("should be incompatible") }
        XCTAssertEqual(categories, ["health"])
        XCTAssertTrue(Storage.recoverable.isSuperset(of: categories))
        XCTAssertFalse(Storage.recoverable.contains("promises"))
        XCTAssertFalse(Storage.recoverable.contains("extra"))
    }

    // MARK: Writing

    func testWriteSwapsInOnlyVerifiedBytesAndLeavesNoTemporaryFile() throws {
        let s = Self.sample()
        let written = try Storage.write(s, to: file)
        XCTAssertEqual(bytes(), written)
        XCTAssertEqual(written, try Storage.encoder().encode(s))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path + ".new"))
    }

    func testAFailedWriteLeavesTheOriginalUntouched() throws {
        try Storage.write(Self.sample(), to: file)
        let before = bytes()
        var changed = Self.sample()
        changed.profile.weightKg = 80
        XCTAssertThrowsError(try Storage.write(changed, to: file, disk: failing(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)))) { error in
            guard case .write = error as? StorageError else { return XCTFail("expected a write error, got \(error)") }
        }
        XCTAssertEqual(bytes(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path + ".new"))
    }

    func testAFullDiskLeavesTheOriginalUntouched() throws {
        try Storage.write(Self.sample(), to: file)
        let before = bytes()
        var changed = Self.sample()
        changed.extra["water"]?["W2"] = .object(["id": .string("W2"), "ml": .number(250)])
        XCTAssertThrowsError(try Storage.write(changed, to: file, disk: failing(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))) { error in
            XCTAssertEqual(error as? StorageError, .noSpace)
        }
        var tight = Storage.Disk()
        tight.freeBytes = { _ in 10 }
        XCTAssertThrowsError(try Storage.write(changed, to: file, disk: tight)) { error in
            XCTAssertEqual(error as? StorageError, .noSpace)
        }
        XCTAssertEqual(bytes(), before)
        XCTAssertEqual(StorageError.noSpace.message, "Espaço insuficiente no iPhone. Liberta espaço para o Cadence poder guardar.")
    }

    func testAValueJSONCantHoldIsNeverWritten() throws {
        try Storage.write(Self.sample(), to: file)
        let before = bytes()
        var changed = Self.sample()
        changed.profile.weightKg = .nan
        XCTAssertThrowsError(try Storage.write(changed, to: file)) { error in
            guard case .encoding = error as? StorageError else { return XCTFail("expected an encoding error, got \(error)") }
        }
        XCTAssertEqual(bytes(), before)
    }

    // MARK: Copies on the phone

    func testRotationKeepsThreeDailyAndTwoBeforeUpdateCopiesAndNeverTouchesABrokenOne() throws {
        let data = try Storage.write(Self.sample(), to: file)
        try FileManager.default.createDirectory(at: copies, withIntermediateDirectories: true)
        let broken = copies.appendingPathComponent("\(Storage.dailyPrefix)2026-10-01.json")
        try Data("{\"promises\":".utf8).write(to: broken)
        let days = ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05"]
        for (i, day) in days.enumerated() {
            let r = Storage.rotate(validated: data, copies: copies, today: day, build: "b\(i)", lastBuild: i == 0 ? nil : "b\(i - 1)")
            XCTAssertNil(r.error)
            XCTAssertTrue(r.beforeUpdateDone)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: copies.path)
        let daily = names.filter { $0.hasPrefix(Storage.dailyPrefix) && $0 != broken.lastPathComponent }.sorted()
        XCTAssertEqual(daily, ["diaria-2026-11-03.json", "diaria-2026-11-04.json", "diaria-2026-11-05.json"])
        XCTAssertEqual(names.filter { $0.hasPrefix(Storage.beforeUpdatePrefix) }.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path)) // not valid, so not ours to delete
        let listed = Storage.listCopies(in: copies)
        XCTAssertEqual(listed.count, 5)
        XCTAssertFalse(listed.contains { $0.url.lastPathComponent == broken.lastPathComponent })
        for copy in listed {
            guard case .ok(let back, _) = Storage.load(from: copy.url) else { return XCTFail("\(copy.id) should read") }
            XCTAssertEqual(back, Self.sample())
        }
    }

    func testRotationSkipsWhenSpaceIsShortAndAFailedCopyRemovesNothing() throws {
        let data = try Storage.write(Self.sample(), to: file)
        for day in ["2026-11-01", "2026-11-02", "2026-11-03"] { _ = Storage.rotate(validated: data, copies: copies, today: day, build: "b", lastBuild: "b") }
        let before = try FileManager.default.contentsOfDirectory(atPath: copies.path).sorted()
        var tight = Storage.Disk()
        tight.freeBytes = { _ in 10 }
        XCTAssertTrue(Storage.rotate(validated: data, copies: copies, today: "2026-11-04", build: "b", lastBuild: "b", disk: tight).lowSpace)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: copies.path).sorted(), before)
        let r = Storage.rotate(validated: data, copies: copies, today: "2026-11-05", build: "b", lastBuild: "b", disk: failing(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)))
        XCTAssertNotNil(r.error)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: copies.path).sorted(), before)
    }

    func testRecoveryKeepsTheBrokenFileByteForByteAndCanBeUndone() throws {
        let data = try Storage.write(Self.sample(), to: file)
        _ = Storage.rotate(validated: data, copies: copies, today: "2026-11-07", build: "b", lastBuild: "b")
        let broken = Data("{\"promises\":".utf8)
        try broken.write(to: file)
        let copy = try XCTUnwrap(Storage.listCopies(in: copies).first)
        let kept = try XCTUnwrap(try Storage.recover(file: file, from: copy.url, copies: copies))
        XCTAssertEqual(try Data(contentsOf: kept), broken)
        guard case .ok(let back, _) = Storage.load(from: file) else { return XCTFail("the recovered file should read") }
        XCTAssertEqual(back, Self.sample())
        try Storage.putBack(kept, file: file, copies: copies)
        XCTAssertEqual(bytes(), broken)
    }

    // MARK: The app's store

    @MainActor
    func testAProtectedStoreNeverWritesOverTheFileOrChangesData() async throws {
        let unreadableHabit = Data("{\"promises\":{\"X\":{\"title\":5}},\"seeded\":true}".utf8)
        for (content, kind) in [(unreadableHabit, StorageProblem.Kind.incompatible), (Data("not json".utf8), .corrupt), (Data(), .corrupt)] {
            try content.write(to: file)
            let store = Store(file: file)
            guard case .protected(let problem) = store.storage else { XCTFail("should be protected"); continue }
            XCTAssertEqual(problem.kind, kind)
            XCTAssertFalse(store.canChange)
            store.addWater(250)
            store.save(DayEntry(date: "2026-11-07", note: "x"))
            store.update { $0.weightKg = 90 }
            store.addFeedback(ReadinessFeedback(date: "2026-11-07", score: 50, felt: 1))
            store.handle(URL(string: "cadence://water")!)
            store.persistNow()
            await store.sync()
            await store.refreshAll(force: true)
            store.wentToBackground()
            try await Task.sleep(nanoseconds: 700_000_000)
            XCTAssertEqual(bytes(), content, "the file must be exactly as it was")
            XCTAssertTrue(store.records("water").isEmpty)
            XCTAssertNil(store.days["2026-11-07"])
        }
    }

    @MainActor
    func testAFailedSaveShowsWhatIsUnsavedBlocksChangesAndRetrySavesIt() throws {
        try Storage.write(Self.sample(), to: file)
        let store = Store(file: file)
        XCTAssertEqual(store.storage, .ok)
        store.persistNow() // the save loading schedules, done now with the real disk
        let afterLoad = bytes()
        let savedAt = store.lastSaved
        XCTAssertNotNil(savedAt)
        store.disk = failing(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)))
        store.addWater(250)
        store.persistNow()
        guard case .unsaved(let message) = store.storage else { return XCTFail("should be unsaved") }
        XCTAssertEqual(store.lastSaved, savedAt, "a failed save must not look saved")
        XCTAssertFalse(store.canChange)
        XCTAssertTrue(message.hasPrefix("Espaço insuficiente"))
        XCTAssertEqual(store.unsavedSummary, "água 1")
        XCTAssertEqual(bytes(), afterLoad)
        let waters = store.records("water").count
        store.addWater(250) // blocked until saved
        store.save(DayEntry(date: "2026-11-08"))
        XCTAssertEqual(store.records("water").count, waters)
        XCTAssertNil(store.days["2026-11-08"])
        store.disk = .real
        store.retrySave()
        XCTAssertEqual(store.storage, .ok)
        XCTAssertTrue(store.unsaved.isEmpty)
        guard case .ok(let back, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(back.extra["water"]?.count, waters)
        XCTAssertEqual(back.logs, Self.sample().logs)
        XCTAssertEqual(back.promises, Self.sample().promises)
    }

    /// Regression: loading used to save before the sync queue was loaded, so the file could lose the queue
    @MainActor
    func testTheSyncQueueSurvivesClosingAndReopeningTheStore() async throws {
        try Storage.write(Self.sample(), to: file)
        do {
            let store = Store(file: file)
            XCTAssertEqual(store.pendingSyncCount, 1)
            try await Task.sleep(nanoseconds: 900_000_000) // the save that loading schedules, left to run on its own
        }
        guard case .ok(let afterLoad, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(afterLoad.dirty, Self.sample().dirty)
        XCTAssertEqual(afterLoad.tombstones, Self.sample().tombstones)
        XCTAssertEqual(afterLoad.rev, Self.sample().rev)

        let store = Store(file: file)
        store.addWater(250)
        store.persistNow()
        let reopened = Store(file: file)
        XCTAssertEqual(reopened.pendingSyncCount, 2)
        guard case .ok(let back, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(back.dirty["water:W1"], 3)
        XCTAssertEqual(back.dirty.keys.filter { $0.hasPrefix("water:") }.count, 2)
        XCTAssertEqual(back.tombstones, Self.sample().tombstones)
        XCTAssertEqual(back.rev, 192)
        XCTAssertEqual(back.logs, Self.sample().logs) // and nothing else moved
        XCTAssertEqual(back.promises, Self.sample().promises)
    }

    func testARecoveryThatCantWriteLeavesTheFileAndTheCopyAsTheyWere() throws {
        let data = try Storage.write(Self.sample(), to: file)
        _ = Storage.rotate(validated: data, copies: copies, today: "2026-11-07", build: "b", lastBuild: "b")
        let broken = Data("{\"promises\":".utf8)
        try broken.write(to: file)
        let copy = try XCTUnwrap(Storage.listCopies(in: copies).first)
        let copyBytes = try Data(contentsOf: copy.url)
        XCTAssertThrowsError(try Storage.recover(file: file, from: copy.url, copies: copies, disk: failing(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)))))
        XCTAssertEqual(bytes(), broken)
        XCTAssertEqual(try Data(contentsOf: copy.url), copyBytes)
    }

    // MARK: Things that can't be taken back wait for a verified save

    /// Desk events: acknowledged (and so deleted on the server) only once on disk; a failed save acknowledges nothing;
    /// getting the same events again after an acknowledgement that never arrived adds nothing twice
    @MainActor
    func testDeskEventsAreAcknowledgedOnlyOnceSavedAndNeverKeptTwice() throws {
        try Storage.write(Self.sample(), to: file)
        let events = [DeskInput(kind: "eyes", answer: "done", at: 1_794_000_000_000, minutes: nil),
                      DeskInput(kind: "stand", answer: "skipped", at: 1_794_000_600_000, minutes: 5)]
        let store = Store(file: file)

        // 1. Saved: the newest time may be acknowledged, and the events are already on disk
        XCTAssertEqual(DeskSync.keep(events, in: store), 1_794_000_600_000)
        guard case .ok(let first, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(first.extra["desk"]?.count, 2)
        XCTAssertEqual(first.extra["desk"]?["1794000600000-stand"], store.records("desk")["1794000600000-stand"])

        // 2. The acknowledgement never reached the server, so the same events come again: still two, unchanged
        XCTAssertEqual(DeskSync.keep(events, in: store), 1_794_000_600_000)
        guard case .ok(let again, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(again.extra["desk"], first.extra["desk"])

        // 3. Saving fails: nothing may be acknowledged, the file keeps what it had, and after a retry the event is kept once
        let third = [DeskInput(kind: "active", answer: "", at: 1_794_001_200_000, minutes: 40)]
        let before = bytes()
        store.disk = failing(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)))
        XCTAssertNil(DeskSync.keep(third, in: store))
        XCTAssertEqual(bytes(), before)
        XCTAssertNil(DeskSync.keep(third, in: store)) // blocked while unsaved
        store.disk = .real
        store.retrySave()
        XCTAssertEqual(DeskSync.keep(third, in: store), 1_794_001_200_000)
        guard case .ok(let after, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(after.extra["desk"]?.count, 3)
    }

    /// A 200 from the server isn't proof: only what it sends back counts as taken
    func testASyncReplyClearsOnlyWhatTheServerSentBack() {
        let sent = ["water:W1": 3, "log:P1|2026-11-04": 4, "gymBag:2026-11-02": 5, "food:F1": 6]
        var dirty = sent
        dirty["food:F1"] = 7   // changed again while the request was on its way
        dirty["water:W9"] = 8  // new, not in this request
        let r = Store.settle(sent: sent, dirty: dirty, returned: ["water:W1", "food:F1"])
        XCTAssertEqual(r.dirty, ["log:P1|2026-11-04": 4, "gymBag:2026-11-02": 5, "food:F1": 7, "water:W9": 8])
        XCTAssertEqual(r.refused, ["gymBag:2026-11-02", "log:P1|2026-11-04"])
        let all = Store.settle(sent: ["water:W1": 3], dirty: ["water:W1": 3], returned: ["water:W1"])
        XCTAssertTrue(all.dirty.isEmpty)
        XCTAssertTrue(all.refused.isEmpty)
    }

    @MainActor
    func testCommitSaysWhetherTheChangeIsReallyOnDisk() throws {
        try Storage.write(Self.sample(), to: file)
        let store = Store(file: file)
        XCTAssertTrue(store.commit())
        store.disk = failing(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError))
        store.addWater(250)
        XCTAssertFalse(store.commit())
        XCTAssertFalse(store.commit()) // stays false until a retry works
        store.disk = .real
        store.retrySave()
        XCTAssertTrue(store.commit())
    }

    @MainActor
    func testAStoreOnAValidFileKeepsEveryRecordWhenItSaves() throws {
        try Storage.write(Self.sample(), to: file)
        let store = Store(file: file)
        store.persistNow()
        guard case .ok(let back, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(back, Self.sample()) // the sync queue, deletions and revision too
    }

    // MARK: Fields that are there but can't be read are never replaced by defaults

    private func profile(_ json: String) throws -> Profile { try JSONDecoder().decode(Profile.self, from: Data(json.utf8)) }

    func testProfileFieldMissingInAnOlderFileTakesItsDefault() throws {
        let p = try profile(#"{"weightKg":78}"#)
        XCTAssertEqual(p.weightKg, 78)
        XCTAssertEqual(p.stepGoal, Profile().stepGoal)
        XCTAssertEqual(p.areasOff, [])
        XCTAssertNil(p.kcalTarget)
        XCTAssertNil(p.setup)
        let empty = try profile("{}")
        XCTAssertEqual(empty, Profile())
        XCTAssertNil(try profile(#"{"kcalTarget":null}"#).kcalTarget) // an optional left empty
    }

    func testProfileFieldPresentAndValidIsRead() throws {
        var p = Profile()
        p.name = "Teste"; p.weightKg = 80.5; p.stepGoal = 10000; p.male = false; p.kcalTarget = 3160; p.fatTarget = 70
        p.plates = [20, 10]; p.areasOff = ["money", "people"]; p.healthSource = "apple"; p.setupDone = true
        p.setup = SetupInputs()
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testProfileFieldPresentButInvalidIsNotReplaced() {
        for json in [#"{"weightKg":null}"#, #"{"setup":{"age":25}}"#, #"{"plates":[20,"x"]}"#, #"{"stepGoal":8000.5}"#] {
            XCTAssertThrowsError(try profile(json), json)
        }
    }

    func testProfileFieldWithAnIncompatibleTypeIsNotReplaced() {
        for json in [#"{"weightKg":"78"}"#, #"{"areasOff":"money"}"#, #"{"male":1}"#, #"{"kcalTarget":"3160"}"#, #"{"setup":[]}"#] {
            XCTAssertThrowsError(try profile(json), json)
        }
    }

    /// The whole chain: a profile field that can't be read protects the file, which is left exactly as it was
    @MainActor
    func testAnUnreadableProfileFieldProtectsTheFile() throws {
        var o = try object(Self.sample())
        var p = try XCTUnwrap(o["profile"] as? [String: Any])
        p["weightKg"] = "78"
        o["profile"] = p
        let content = try JSONSerialization.data(withJSONObject: o)
        try content.write(to: file)
        guard case .incompatible(let saved, let categories, _) = Storage.load(from: file) else { return XCTFail("should be incompatible") }
        XCTAssertEqual(categories, ["profile"])
        XCTAssertEqual(saved.logs, Self.sample().logs)
        let store = Store(file: file)
        guard case .protected(let problem) = store.storage else { return XCTFail("should be protected") }
        XCTAssertEqual(problem.categories, ["profile"])
        store.persistNow()
        XCTAssertEqual(bytes(), content)
    }

    func testSessionsReadOlderAndEmptyListFieldsButNeverShowUnreadableSetsAsNone() throws {
        let decode = { (json: String) in try JSONDecoder().decode(WorkoutSession.self, from: Data(json.utf8)) }
        let older = try decode(#"{"id":"S1","order":[]}"#)
        XCTAssertEqual(older.name, "Workout")
        XCTAssertTrue(older.sets.isEmpty)
        XCTAssertEqual(try decode(#"{"id":"S2","name":"Pernas","order":[],"sets":[],"notes":[]}"#).notes, [:]) // PHP's empty object
        XCTAssertThrowsError(try decode(#"{"id":"S3","order":[],"sets":"x"}"#))
        XCTAssertThrowsError(try decode(#"{"id":"S4","order":[],"notes":{"a":5}}"#))
        XCTAssertThrowsError(try decode(#"{"id":"S5","order":[],"start":"ontem"}"#))
    }

    /// A stored session that can't be read is left out, not shown empty, and its record survives every save untouched
    @MainActor
    func testAnUnreadableSessionRecordIsKeptAsItIsThroughSaves() throws {
        var s = Self.sample()
        let unreadable: JSONValue = .object(["id": .string("S9"), "order": .array([]), "sets": .string("x")])
        s.extra["session"] = ["S9": unreadable]
        try Storage.write(s, to: file)
        let store = Store(file: file)
        XCTAssertEqual(store.storage, .ok)
        XCTAssertTrue(store.all(WorkoutSession.self).isEmpty)
        store.addWater(250)
        store.persistNow()
        guard case .ok(let back, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(back.extra["session"]?["S9"], unreadable)
    }

    // MARK: Going back to the previous build

    func testAFileWrittenNowReadsInThePreviousVersion() throws {
        let s = Self.sample()
        let data = try Storage.write(s, to: file)
        let old = try JSONDecoder().decode(PreviousSaved.self, from: data)
        XCTAssertEqual(old.promises, s.promises)
        XCTAssertEqual(old.logs, s.logs)
        XCTAssertEqual(old.days, s.days)
        XCTAssertEqual(old.profile, s.profile)
        XCTAssertEqual(old.feedback, s.feedback)
        XCTAssertEqual(old.extra, s.extra)
        XCTAssertEqual(old.health, s.health)
        XCTAssertEqual(old.device, s.device)
        XCTAssertEqual(old.healthErrors, s.healthErrors)
        XCTAssertEqual(old.lastHealth, s.lastHealth)
        XCTAssertEqual(old.connection, s.connection)
        XCTAssertEqual(old.dirty, s.dirty)
        XCTAssertEqual(old.tombstones, s.tombstones)
        XCTAssertEqual(old.rev, s.rev)
        XCTAssertEqual(old.seeded, s.seeded)
    }

    func testAFileWrittenByThePreviousVersionReadsIdentically() throws {
        try JSONEncoder().encode(PreviousSaved(Self.sample())).write(to: file) // the old writer: no sorted keys
        guard case .ok(let back, _) = Storage.load(from: file) else { return XCTFail("should read") }
        XCTAssertEqual(back, Self.sample())
    }
}

/// The data file as the build before phase 1 read and wrote it, field for field
private struct PreviousSaved: Codable {
    var promises: [String: PromiseItem] = [:]
    var logs: [String: PromiseLog] = [:]
    var days: [String: DayEntry] = [:]
    var profile = Profile()
    var feedback: [String: ReadinessFeedback] = [:]
    var extra: [String: [String: JSONValue]] = [:]
    var health: [String: HealthDay] = [:]
    var device: Device?
    var healthErrors: [String: String] = [:]
    var lastHealth: Double?
    var connection = Connection()
    var dirty: [String: Int] = [:]
    var tombstones: [String] = []
    var rev: Int?
    var seeded = false

    init(_ s: Saved) {
        promises = s.promises; logs = s.logs; days = s.days; profile = s.profile; feedback = s.feedback; extra = s.extra
        health = s.health; device = s.device; healthErrors = s.healthErrors; lastHealth = s.lastHealth
        connection = s.connection; dirty = s.dirty; tombstones = s.tombstones; rev = s.rev; seeded = s.seeded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        promises = v(.promises, [:]); logs = v(.logs, [:]); days = v(.days, [:]); profile = v(.profile, Profile())
        feedback = v(.feedback, [:]); extra = v(.extra, [:]); health = v(.health, [:]); device = (try? c.decodeIfPresent(Device.self, forKey: .device)) ?? nil
        healthErrors = v(.healthErrors, [:]); lastHealth = (try? c.decodeIfPresent(Double.self, forKey: .lastHealth)) ?? nil
        connection = v(.connection, Connection()); dirty = v(.dirty, [:]); tombstones = v(.tombstones, [])
        rev = (try? c.decodeIfPresent(Int.self, forKey: .rev)) ?? nil; seeded = v(.seeded, false)
    }
}
