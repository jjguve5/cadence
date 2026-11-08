// Everything the app knows, saved on the phone first (offline) and synced with the PHP server: records go up when
// they change here and come down when they changed elsewhere. Health days come from health.php.
import Combine
import Foundation
import SwiftUI

struct SyncChange: Codable {
    var type: String
    var id: String
    var deleted: Bool?
    var data: JSONValue?
    var updated: Double?
}

private struct SyncReply: Decodable {
    var rev: Int
    var changes: [SyncChange]
}

/// What's on disk. dirty: "type:id" changed here and not yet on the server, with a version so a change made during
/// a sync isn't taken as sent. Deleted ids wait in `tombstones` until the server has them.
struct Saved: Codable, Equatable {
    var promises: [String: PromiseItem] = [:]
    var logs: [String: PromiseLog] = [:]
    var days: [String: DayEntry] = [:]
    var profile = Profile()
    var feedback: [String: ReadinessFeedback] = [:]
    var extra: [String: [String: JSONValue]] = [:] // record types added by later steps, kept generically
    var health: [String: HealthDay] = [:]
    var device: Device?
    var healthErrors: [String: String] = [:]
    var lastHealth: Double?
    var connection = Connection()
    var dirty: [String: Int] = [:]
    var tombstones: [String] = []
    var rev: Int?
    var seeded = false
    // Not saved. What reading found: categories that were in the file but couldn't be read by this version, and
    // whether the file looked like a Cadence file at all. Storage.load turns these into "protected", never into empty data.
    var unreadable: [String] = []
    var recognised = true

    enum CodingKeys: String, CodingKey {
        case promises, logs, days, profile, feedback, extra, health, device, healthErrors, lastHealth, connection, dirty, tombstones, rev, seeded
    }

    init() {}

    // A category that's missing is simply empty (an older file); one that's there but can't be read is noted in
    // `unreadable` instead of being silently replaced by an empty one
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var failed: [String] = []
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T {
            guard c.contains(k), (try? c.decodeNil(forKey: k)) != true else { return def }
            do { return try c.decode(T.self, forKey: k) } catch { failed.append(k.stringValue); return def }
        }
        promises = v(.promises, [:]); logs = v(.logs, [:]); days = v(.days, [:]); profile = v(.profile, Profile())
        feedback = v(.feedback, [:]); extra = v(.extra, [:]); health = v(.health, [:]); device = v(.device, nil as Device?)
        healthErrors = v(.healthErrors, [:]); lastHealth = v(.lastHealth, nil as Double?)
        connection = v(.connection, Connection()); dirty = v(.dirty, [:]); tombstones = v(.tombstones, [])
        rev = v(.rev, nil as Int?); seeded = v(.seeded, false)
        unreadable = failed
        recognised = !c.allKeys.isEmpty
    }

    /// Personal records: everything except Fitbit data and sync bookkeeping
    var personalRecords: Int { promises.count + logs.count + days.count + feedback.count + extra.values.reduce(0) { $0 + $1.count } }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var promises: [String: PromiseItem] = [:]
    @Published private(set) var logs: [String: PromiseLog] = [:]
    @Published private(set) var days: [String: DayEntry] = [:]
    @Published private(set) var profile = Profile()
    @Published private(set) var feedback: [String: ReadinessFeedback] = [:]
    @Published private(set) var extra: [String: [String: JSONValue]] = [:]
    @Published private(set) var health: [String: HealthDay] = [:]
    @Published private(set) var device: Device?
    @Published private(set) var healthErrors: [String: String] = [:]
    @Published private(set) var lastHealth: Date?
    @Published var connection = Connection() { didSet { if connection != oldValue { persist() } } }
    @Published private(set) var syncing = false
    @Published private(set) var syncError: String?
    @Published private(set) var needsGoogle = false
    @Published private(set) var appleHealthProblem: String?
    @Published var tick = Date() // redraws time-based views
    @Published var openWorkout: OpenSession?
    @Published var brushingOpen = false
    @Published var readingOpen = false
    @Published var captureOpen = false
    // Local data protection (Storage.swift): anything but .ok blocks every change until the data is safe
    @Published private(set) var storage: StorageState = .ok
    @Published private(set) var lastSaved: Date?
    @Published private(set) var storageNote: String?
    @Published private(set) var localCopies: [LocalCopy] = []
    @Published private(set) var lastRecoveryArchive: URL?
    @Published private(set) var syncRefused: [String] = [] // sent, answered 200, but not taken by the server: still queued
    private(set) var unsaved: [String: Int] = [:] // "type:id" changed since the last verified write, with its version
    var canChange: Bool { storage == .ok }

    var recordCache: [String: Any] = [:] // decoded typed records, per type (see Records.swift)
    // Worked out once per change: one redraw asks for these hundreds of times. Emptied whenever anything is about to change.
    var planCache: [String: SleepPlan] = [:]
    var busyCache: [String: [Busy]] = [:]
    var readinessCache: [String: Readiness?] = [:]
    var activeCache: [PromiseItem]?
    private var cacheWatch: [AnyCancellable] = []

    private func emptyCaches() {
        planCache = [:]; busyCache = [:]; readinessCache = [:]; activeCache = nil
    }
    private var dirty: [String: Int] = [:]
    private var tombstones: [String] = []
    private var rev: Int?
    private var version = 0
    // UI tests use their own file in a temporary folder; the real file is never touched in that mode
    private let file: URL
    private let copiesDir: URL
    private let rotates: Bool
    private let defaults: UserDefaults
    var disk = Storage.Disk.real // tests make writing fail or the disk look full
    var dataFileURL: URL { file }
    /// Set when the copy made before a new build's first sync failed: nothing syncs until a copy exists
    @Published private(set) var syncHold: String?

    /// `file`, `rotate` and `defaults` are for unit tests: a store on its own file, with copies only when asked
    init(file custom: URL? = nil, rotate: Bool = false, defaults: UserDefaults = .standard) {
        file = custom ?? (TestMode.active ? TestMode.storeFile : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cadence.json"))
        copiesDir = file.deletingLastPathComponent().appendingPathComponent("cadence-copies", isDirectory: true)
        rotates = (custom == nil && !TestMode.active) || rotate
        self.defaults = defaults
        objectWillChange.sink { [weak self] _ in self?.emptyCaches() }.store(in: &cacheWatch)
        Agenda.shared.objectWillChange.sink { [weak self] _ in self?.emptyCaches() }.store(in: &cacheWatch)
        if custom == nil, TestMode.active {
            if TestMode.reset { try? FileManager.default.removeItem(at: file) }
            let fresh = !FileManager.default.fileExists(atPath: file.path)
            loadSaved()
            if fresh {
                connection = Connection(server: "https://uitest.invalid", token: "uitest")
                TestSeed.apply(self, scenario: TestMode.scenario ?? "normal")
            }
            return
        }
        loadSaved()
    }

    /// Reads the data file. Only a missing file starts fresh: one that's there but can't be read, or has a category
    /// this version can't read, puts the app in protected mode and is left exactly as it is.
    private func loadSaved() {
        switch Storage.load(from: file) {
        case .fresh:
            storage = .ok
            seed()
        case .ok(let saved, let data):
            storage = .ok
            // The copies come first, from the bytes exactly as read (sync queue, deletions and revision included),
            // before anything is written or synced
            rotateCopies(data)
            adopt(saved)
            if !saved.seeded { seed() }
        case .cannotOpen(let why):
            storage = .protected(StorageProblem(kind: .cannotOpen, detail: why, categories: []))
        case .corrupt(let why):
            storage = .protected(StorageProblem(kind: .corrupt, detail: why, categories: []))
        case .incompatible(let saved, let categories, let data):
            // Fitbit data can come again from the server, but only once the original is archived and the server is set up
            let onlyFitbit = Set(categories).isSubset(of: Storage.recoverable) && saved.connection.configured && saved.profile.usesBand
            if onlyFitbit, let kept = try? Storage.archive(data, in: copiesDir, reason: "dados-fitbit-incompativeis", disk: disk) {
                storage = .ok
                adopt(saved)
                storageNote = "Os dados da Fitbit guardados no iPhone eram de um formato que esta versão não lê. O ficheiro original ficou arquivado (\(kept.lastPathComponent)) e os dados voltam a ser pedidos ao servidor."
                if !saved.seeded { seed() }
            } else {
                storage = .protected(StorageProblem(kind: .incompatible, detail: "", categories: categories))
            }
        }
        if storage != .ok { localCopies = Storage.listCopies(in: copiesDir) }
    }

    private func adopt(_ saved: Saved) {
        promises = saved.promises; logs = saved.logs; days = saved.days; profile = saved.profile
        feedback = saved.feedback; extra = saved.extra; health = saved.health; device = saved.device
        healthErrors = saved.healthErrors; lastHealth = saved.lastHealth.map { Date(timeIntervalSince1970: $0) }
        dirty = saved.dirty; tombstones = saved.tombstones; rev = saved.rev
        connection = saved.connection // last: its didSet saves, and the queue above must already be loaded by then
    }

    /// One validated copy a day and one before each new build, made right here, before anything can be written or
    /// synced. If a new build's first copy can't be made, syncing stays off until it can (retried at each refresh).
    private func rotateCopies(_ data: Data) {
        guard rotates else { return }
        let build = Storage.buildStamp(), last = defaults.string(forKey: "storageBuild")
        let r = Storage.rotate(validated: data, copies: copiesDir, today: Day.today, build: build, lastBuild: last, disk: disk)
        if r.beforeUpdateDone { defaults.set(build, forKey: "storageBuild") }
        localCopies = Storage.listCopies(in: copiesDir)
        if last != build, !r.beforeUpdateDone {
            syncHold = "Não foi possível fazer a cópia de segurança antes da primeira sincronização desta versão" + (r.lowSpace ? " (pouco espaço livre)" : r.error.map { " (\($0))" } ?? "") + ". A sincronização fica parada até a cópia ser feita."
        } else {
            syncHold = nil
            if r.lowSpace { storageNote = "Pouco espaço livre no iPhone: hoje não foi feita a cópia local." }
            else if let e = r.error { storageNote = "A cópia local de hoje falhou: \(e)" }
        }
    }

    /// While syncing is held, each refresh tries the copy again from the file as it is now
    private func retryHeldCopy() {
        guard syncHold != nil, storage == .ok, case .ok(_, let data) = Storage.load(from: file) else { return }
        rotateCopies(data)
    }

    /// Every change is in memory at once and on disk moments later, away from the main thread, so tapping never waits
    private var saveWork: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "cadence.save", qos: .utility)

    private func persist() {
        guard storage == .ok else { return } // protected: never written over; unsaved: only an explicit retry writes
        saveWork?.cancel()
        let s = savedState(), target = file, d = disk, upTo = version
        if TestMode.active { finishWrite(Result { try Storage.write(s, to: target, disk: d) }, upTo: upTo); return } // UI tests kill the app straight after a change
        let work = DispatchWorkItem { [weak self] in
            let result = Result { try Storage.write(s, to: target, disk: d) }
            Task { @MainActor in self?.finishWrite(result, upTo: upTo) }
        }
        saveWork = work
        saveQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func finishWrite(_ result: Result<Data, Error>, upTo: Int) {
        switch result {
        case .success:
            lastSaved = Date()
            unsaved = unsaved.filter { $0.value > upTo }
            if case .unsaved = storage { storage = .ok }
        case .failure(let error):
            if case .protected = storage { return }
            storage = .unsaved(Storage.classify(error).message)
        }
    }

    /// Going to the background, or "Tentar guardar outra vez": writes now. Never in protected mode.
    func persistNow() {
        if case .protected = storage { return }
        saveWork?.cancel()
        let s = savedState(), target = file, d = disk, upTo = version
        let result = saveQueue.sync { Result { try Storage.write(s, to: target, disk: d) } }
        finishWrite(result, upTo: upTo)
    }

    func retrySave() { persistNow() }

    /// Saves now and says whether it's really on disk. Anything that can't be taken back (an acknowledgement to the
    /// server, a set shown as done on the lock screen, a reminder answered) happens only after this returns true.
    @discardableResult
    func commit() -> Bool {
        guard storage == .ok else { return false }
        persistNow()
        return storage == .ok
    }

    /// "Tentar outra vez" on the recovery screen, and on coming back to the app when the file couldn't be opened
    func retryLoad() {
        guard case .protected = storage else { return }
        loadSaved()
    }

    /// Puts a validated local copy in place; the file it replaces is archived first and can be put back
    @discardableResult
    func recover(from copy: LocalCopy) throws -> URL? {
        let kept = try Storage.recover(file: file, from: copy.url, copies: copiesDir, disk: disk)
        lastRecoveryArchive = kept
        storage = .protected(StorageProblem(kind: .corrupt, detail: "", categories: [])) // so loadSaved reads it fresh
        loadSaved()
        if let kept { storageNote = "Recuperado a partir da cópia de \(copy.date.formatted(date: .abbreviated, time: .shortened)). O ficheiro anterior ficou guardado (\(kept.lastPathComponent))." }
        return kept
    }

    /// Undoes the last recovery: the file from before it goes back exactly as it was
    func undoRecovery() throws {
        guard let kept = lastRecoveryArchive else { return }
        saveWork?.cancel()
        let target = file, dir = copiesDir, d = disk
        try saveQueue.sync { try Storage.putBack(kept, file: target, copies: dir, disk: d) }
        lastRecoveryArchive = nil
        storage = .protected(StorageProblem(kind: .corrupt, detail: "", categories: []))
        loadSaved()
    }

    /// "água 2, comida 1" for the changes not yet on disk
    var unsavedSummary: String {
        let byType = Dictionary(grouping: unsaved.keys) { String($0.split(separator: ":", maxSplits: 1).first ?? "") }
        return byType.map { "\(Storage.name(ofType: $0.key)) \($0.value.count)" }.sorted().joined(separator: ", ")
    }

    var personalRecordCount: Int { promises.count + logs.count + days.count + feedback.count + extra.values.reduce(0) { $0 + $1.count } }
    var pendingSyncCount: Int { dirty.count }

    private func savedState() -> Saved {
        var s = Saved()
        s.promises = promises; s.logs = logs; s.days = days; s.profile = profile; s.feedback = feedback; s.extra = extra
        s.health = health; s.device = device; s.healthErrors = healthErrors; s.lastHealth = lastHealth?.timeIntervalSince1970
        s.connection = connection; s.dirty = dirty; s.tombstones = tombstones; s.rev = rev; s.seeded = true
        return s
    }

    private func mark(_ key: String) {
        version += 1
        dirty[key] = version
        unsaved[key] = version
        guard storage == .ok else { return } // nothing written or sent until the data is safe
        persist()
        scheduleSnapshot()
        Reminders.shared.reschedule()
        scheduleSync()
    }

    private var snapshotTask: Task<Void, Never>?

    private func scheduleSnapshot() {
        guard widgetsAvailable else { return }
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.writeSnapshot()
        }
    }

    /// The first promises, so the app is useful on day one
    private func seed() {
        let creatine = PromiseItem(title: "Creatine", icon: "pills.fill", kind: .mustDo, schedule: Schedule(rule: .daily, minute: 20 * 60 + 30), tiny: nil)
        let shake = PromiseItem(title: "Protein shake", icon: "takeoutbag.and.cup.and.straw.fill", schedule: Schedule(rule: .everyNDays, every: 2, minute: 17 * 60), kcal: 180, protein: 32)
        let read = PromiseItem(title: "Read 30 min", icon: "book.fill", schedule: Schedule(rule: .daily, minute: 23 * 60 + 15, anchor: "windDown", offset: 0), tiny: "Read two pages")
        let brush = PromiseItem(title: "Brush teeth, night", icon: "mouth.fill", schedule: Schedule(rule: .daily, minute: 23 * 60 + 25, anchor: "lightsOut", offset: -10))
        for p in [creatine, shake, read, brush] { promises[p.id] = p; dirty["promise:\(p.id)"] = 1 }
        dirty["profile:me"] = 1
        persist()
    }

    /// UI-test scenarios only
    func loadTestHealth(_ list: [HealthDay], device: Device) {
        for d in list { health[d.date] = d }
        self.device = device
        lastHealth = Date()
        persist()
    }

    // MARK: - Promises

    // Every change goes through one of these; while the data isn't safe (protected or a failed save) they do nothing,
    // so memory never drifts from what's on disk

    func save(_ promise: PromiseItem) {
        guard canChange else { return }
        promises[promise.id] = promise
        mark("promise:\(promise.id)")
    }

    func delete(_ promise: PromiseItem) {
        guard canChange else { return }
        promises[promise.id] = nil
        tombstones.append("promise:\(promise.id)")
        mark("promise:\(promise.id)")
    }

    /// `source` is nil for an answer you gave, or the data source for one imported from it (see PromiseLog.source)
    func log(_ promise: PromiseItem, on day: String = Day.today, _ status: LogStatus, source: String? = nil) {
        guard canChange else { return }
        let entry = PromiseLog(promiseId: promise.id, date: day, status: status, source: source)
        logs[entry.id] = entry
        mark("log:\(entry.id)")
        Reminders.shared.clear(promise: promise.id, day: day)
        // Routines that log food: ticking the 17:00 shake adds its calories and protein
        if status != .skipped, promise.kcal != nil || promise.protein != nil {
            save(FoodEntry(id: "promise-\(promise.id)-\(day)", date: day, minute: time(of: promise, on: day), name: promise.title, kcal: promise.kcal ?? 0, protein: promise.protein ?? 0, promiseId: promise.id))
        }
    }

    func undo(_ promise: PromiseItem, on day: String = Day.today) {
        guard canChange else { return }
        let id = "\(promise.id)|\(day)"
        logs[id] = nil
        if let food = record(FoodEntry.self, "promise-\(promise.id)-\(day)") { remove(food) }
        tombstones.append("log:\(id)")
        mark("log:\(id)")
    }

    func status(_ promise: PromiseItem, on day: String = Day.today) -> LogStatus? { logs["\(promise.id)|\(day)"]?.status }

    /// Where a day's answer came from: nil when you gave it (or there is none), otherwise the data source it was imported from
    func answerSource(_ promise: PromiseItem, on day: String = Day.today) -> String? { logs["\(promise.id)|\(day)"]?.source }

    var activePromises: [PromiseItem] {
        if let activeCache { return activeCache }
        let sorted = promises.values.filter(\.active).map { (time(of: $0), $0) }.sorted { $0.0 < $1.0 }.map(\.1)
        activeCache = sorted
        return sorted
    }

    func due(on day: String = Day.today) -> [PromiseItem] { activePromises.filter { $0.schedule.isDue(on: day) } }

    func openMustDos(on day: String = Day.today) -> [PromiseItem] { due(on: day).filter { $0.kind == .mustDo && status($0, on: day) == nil } }

    /// "6/6 this week": done so far against due so far, Monday to today
    func week(_ promise: PromiseItem, upTo day: String = Day.today) -> (done: Int, due: Int, total: Int) {
        let start = Day.weekStart(day)
        var done = 0, due = 0
        for i in 0...max(0, Day.between(start, day)) {
            let d = Day.add(i, to: start)
            guard promise.schedule.isDue(on: d) else { continue }
            due += 1
            if let s = status(promise, on: d), s != .skipped { done += 1 }
        }
        return (done, due, promise.schedule.dueInWeek(of: day))
    }

    // MARK: - Days and profile

    func day(_ key: String = Day.today) -> DayEntry { days[key] ?? DayEntry(date: key) }

    func save(_ entry: DayEntry) {
        guard canChange else { return }
        days[entry.date] = entry
        mark("day:\(entry.date)")
    }

    func update(_ change: (inout Profile) -> Void) {
        guard canChange else { return }
        var p = profile
        change(&p)
        guard p != profile else { return }
        profile = p
        mark("profile:me")
    }

    func addFeedback(_ f: ReadinessFeedback) {
        guard canChange else { return }
        feedback[f.date] = f
        // Each "feels wrong" moves the score 2 points the way you felt, up to ±10
        let recent = feedback.values.sorted { $0.date > $1.date }.prefix(10)
        let offset = max(-10, min(10, Double(recent.map(\.felt).reduce(0, +)) * 2))
        update { $0.readinessOffset = offset }
        mark("feedback:\(f.date)")
    }

    /// Records of later steps (meals, sets, money...) live here until they get their own model
    func records(_ type: String) -> [String: JSONValue] { extra[type] ?? [:] }

    func put(_ type: String, _ id: String, _ value: JSONValue?) {
        guard canChange else { return }
        var all = extra[type] ?? [:]
        all[id] = value
        extra[type] = all
        recordCache[type] = nil
        if value == nil { tombstones.append("\(type):\(id)") }
        mark("\(type):\(id)")
    }

    // MARK: - Sync

    private var syncTask: Task<Void, Never>?
    private var syncFailures = 0
    private var syncPausedUntil = Date.distantPast
    private var lastRefreshAll = Date.distantPast

    /// The phone is the source of truth and the server a copy: changes go up in one batch, 30 seconds after the last
    /// one, so a burst of sets and reps is a single request. When the server refuses, it waits longer each time.
    func scheduleSync() {
        guard Date() >= syncPausedUntil else { return } // the retry already scheduled carries these changes too
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    private func syncFailed(_ message: String) {
        syncError = message
        syncFailures += 1
        let wait = Engine.syncBackoff(failures: syncFailures)
        syncPausedUntil = Date().addingTimeInterval(wait)
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Leaving the app: save, plan the notifications and send what's waiting, since nothing else will run for a while
    func wentToBackground() {
        persistNow()
        Reminders.shared.flush()
        guard storage == .ok, !dirty.isEmpty, Date() >= syncPausedUntil else { return }
        syncTask?.cancel()
        let app = UIApplication.shared
        var id = UIBackgroundTaskIdentifier.invalid
        id = app.beginBackgroundTask { app.endBackgroundTask(id) }
        Task { await sync(); app.endBackgroundTask(id) }
    }

    func request(_ path: String, body: Data? = nil) -> URLRequest? {
        guard !TestMode.active, connection.configured, let url = URL(string: connection.server.trimmingCharacters(in: .whitespaces) + "/" + path) else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 90)
        r.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        r.setValue(connection.token, forHTTPHeaderField: "X-Cadence-Token")
        if let body {
            r.httpMethod = "POST"
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private func encodeRecord(_ key: String) -> SyncChange? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let (type, id) = (parts[0], parts[1])
        let value: JSONValue?
        switch type {
        case "promise": value = promises[id].flatMap { JSONValue.from($0) }
        case "log": value = logs[id].flatMap { JSONValue.from($0) }
        case "day": value = days[id].flatMap { JSONValue.from($0) }
        case "profile": value = JSONValue.from(profile)
        case "feedback": value = feedback[id].flatMap { JSONValue.from($0) }
        default: value = extra[type]?[id]
        }
        return SyncChange(type: type, id: id, deleted: value == nil ? true : nil, data: value, updated: nowMs())
    }

    private func apply(_ c: SyncChange) {
        let gone = c.deleted == true || c.data == nil
        switch c.type {
        case "promise": promises[c.id] = gone ? nil : c.data?.decode(PromiseItem.self)
        case "log": logs[c.id] = gone ? nil : c.data?.decode(PromiseLog.self)
        case "day": days[c.id] = gone ? nil : c.data?.decode(DayEntry.self)
        case "profile": if !gone, let p = c.data?.decode(Profile.self) { profile = p }
        case "feedback": feedback[c.id] = gone ? nil : c.data?.decode(ReadinessFeedback.self)
        default:
            var all = extra[c.type] ?? [:]
            all[c.id] = gone ? nil : c.data
            extra[c.type] = all
            recordCache[c.type] = nil
        }
    }

    func sync() async {
        guard storage == .ok, syncHold == nil, connection.configured, !syncing, Date() >= syncPausedUntil else { return }
        syncing = true
        defer { syncing = false }
        let sent = dirty
        let since = rev ?? 0
        let changes = sent.keys.compactMap(encodeRecord)
        struct Body: Encodable { var since: Int; var changes: [SyncChange] }
        guard let body = try? JSONEncoder().encode(Body(since: since, changes: changes)), let req = request("sync.php", body: body) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { syncFailed(code == 403 ? "The server refused this for now: saved on the phone, retrying later" : "Sync failed (\(code)): saved on the phone"); return }
            let reply = try JSONDecoder().decode(SyncReply.self, from: data)
            let settled = Self.settle(sent: sent, dirty: dirty, returned: Set(reply.changes.map { "\($0.type):\($0.id)" }))
            dirty = settled.dirty
            syncRefused = settled.refused
            tombstones.removeAll { sent[$0] != nil && dirty[$0] == nil }
            // A full download (no revision yet, or a server that went back) can hold older copies of what is here:
            // the phone's version stays and goes up again; only what the phone doesn't have is added
            let full = since == 0 || reply.rev < since
            var keptLocal = 0
            for c in reply.changes where dirty["\(c.type):\(c.id)"] == nil {
                let key = "\(c.type):\(c.id)"
                switch Self.resolve(c, local: encodeRecord(key)?.data, fullDownload: full) {
                case .apply: apply(c)
                case .skip: break
                case .keepLocal:
                    version += 1
                    dirty[key] = version
                    keptLocal += 1
                }
            }
            if keptLocal > 0 {
                storageNote = "Na sincronização completa, \(keptLocal) registo(s) do iPhone eram diferentes dos do servidor: ficou a versão do iPhone, que volta a ser enviada."
                scheduleSync()
            }
            if reply.changes.contains(where: { $0.type == WeightEntry.kind }) { followLatestWeight() }
            rev = reply.rev
            syncError = nil
            syncFailures = 0
            persist()
            if !reply.changes.isEmpty { Reminders.shared.reschedule() }
        } catch {
            syncFailed("Offline: changes wait on the phone")
        }
    }

    enum Resolution: Equatable { case apply, skip, keepLocal }

    /// What to do with a record the server sent. Normally the server's copy is newer and is applied. In a full
    /// download, though, the phone is the source of truth: a record it doesn't have is added, an identical one is left,
    /// and a different one, or a deletion of something the phone still has, keeps the phone's version.
    nonisolated static func resolve(_ change: SyncChange, local: JSONValue?, fullDownload: Bool) -> Resolution {
        guard fullDownload else { return .apply }
        let gone = change.deleted == true || change.data == nil
        guard let local else { return gone ? .skip : .apply }
        if !gone, change.data == local { return .skip }
        return .keepLocal
    }

    /// What a sync reply proves. A 200 isn't enough: the server skips some records without an error (ids with "|",
    /// values that aren't objects). Every record it takes comes back in the reply with its new revision, so a change
    /// counts as sent only when it comes back; the rest stay queued and are listed. A change made while the request was
    /// on its way stays queued too.
    nonisolated static func settle(sent: [String: Int], dirty: [String: Int], returned: Set<String>) -> (dirty: [String: Int], refused: [String]) {
        var left = dirty
        var refused: [String] = []
        for (key, version) in sent where dirty[key] == version {
            if returned.contains(key) { left[key] = nil } else { refused.append(key) }
        }
        return (left, refused.sorted())
    }

    /// Targets use the profile weight, so it follows the newest weigh-in, typed or from Apple Health
    func followLatestWeight() {
        guard let w = all(WeightEntry.self).max(by: { $0.date < $1.date }), abs(w.kg - profile.weightKg) > 0.01 else { return }
        update { $0.weightKg = w.kg }
    }

    // MARK: - Health

    func refreshHealth(force: Bool = false) async {
        guard storage == .ok else { return }
        if !force, let last = lastHealth, Date().timeIntervalSince(last) < 15 * 60 { return }
        if !profile.usesBand { await refreshAppleHealth(everything: true); return }
        await refreshAppleHealth(everything: false)
        guard connection.configured else { return }
        let days = health.count < 30 || UserDefaults.standard.integer(forKey: "healthSchema") < 2 ? 90 : 14
        guard let req = request("health.php?days=\(days)") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 409 { needsGoogle = true; return }
            guard code == 200 else { return }
            let reply = try JSONDecoder().decode(HealthReply.self, from: data)
            if UserDefaults.standard.integer(forKey: "healthSchema") < 2 { health = [:]; UserDefaults.standard.set(2, forKey: "healthSchema") }
            for d in reply.days { health[d.date] = d }
            device = reply.device
            healthErrors = reply.errors ?? [:]
            lastHealth = Date()
            needsGoogle = false
            persist()
            autoComplete()
            writeSnapshot()
        } catch {}
    }

    /// Apple Health: everything when it's the source, otherwise just weight and water next to the Fitbit data
    func refreshAppleHealth(everything: Bool) async {
        guard !TestMode.active, storage == .ok else { return }
        guard let r = await AppleHealth.shared.read(days: everything && health.count < 30 ? 90 : 30, everything: everything) else {
            appleHealthProblem = AppleHealth.shared.problem
            return
        }
        appleHealthProblem = nil
        if everything {
            for d in r.days { health[d.date] = d }
            device = Device(name: "Apple Health", battery: nil, batteryStatus: nil, lastSync: ISO8601DateFormatter().string(from: Date()))
            lastHealth = Date()
        }
        // typed weights win; a later Health reading replaces an earlier one
        for w in r.weights {
            let old = record(WeightEntry.self, w.date)
            if old == nil || (old?.source == "health" && abs((old?.kg ?? 0) - w.kg) > 0.01) { save(WeightEntry(date: w.date, kg: (w.kg * 10).rounded() / 10, source: "health")) }
        }
        for x in r.water where record(WaterEntry.self, x.id) == nil { save(WaterEntry(id: x.id, date: x.date, minute: x.minute, ml: x.ml.rounded())) }
        followLatestWeight()
        persist()
        if everything { autoComplete(); writeSnapshot() }
    }

    func googleURL() -> URL? {
        guard connection.configured else { return nil }
        var c = URLComponents(string: connection.server + "/google.php")
        c?.queryItems = [URLQueryItem(name: "token", value: connection.token)]
        return c?.url
    }

    func googleConnected() {
        needsGoogle = false
        Task { await refreshHealth(force: true) }
    }

    /// cadence://setup?server=...&token=... from the setup QR code
    func handle(_ url: URL) {
        guard url.scheme == "cadence", storage == .ok else { return } // links that change data wait until the data is safe
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if url.host == "setup", let server = value("server"), let token = value("token") {
            connection = Connection(server: server, token: token)
            Task { await sync(); await refreshHealth(force: true) }
        } else if url.host == "google" {
            googleConnected()
        } else if url.host == "workout" {
            let id = value("id").flatMap { $0.isEmpty ? nil : $0 } ?? activeSession?.id
            if let id { openWorkout = OpenSession(id: id) }
        } else if url.host == "brush" {
            brushingOpen = true
        } else if url.host == "read" {
            readingOpen = true
        } else if url.host == "water" {
            addWater(250)
            commit() // from a widget: on disk before anything else happens
        } else if url.host == "capture" {
            captureOpen = true
        }
    }

    /// Everything this phone knows, as one JSON document
    func exportJSON() -> String {
        var all: [String: JSONValue] = [:]
        all["promises"] = JSONValue.from(Array(promises.values))
        all["logs"] = JSONValue.from(Array(logs.values))
        all["days"] = JSONValue.from(Array(days.values))
        all["profile"] = JSONValue.from(profile)
        all["health"] = JSONValue.from(Array(health.values))
        for (type, records) in extra { all[type] = .array(Array(records.values)) }
        guard let data = try? JSONEncoder().encode(all) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Coming back to the app shouldn't mean a round of requests every time; pull to refresh forces it
    func refreshAll(force: Bool = false) async {
        guard storage == .ok, force || Date().timeIntervalSince(lastRefreshAll) > 5 * 60 else { return }
        retryHeldCopy() // no copy before this build's first sync, no sync
        lastRefreshAll = Date()
        if force { syncPausedUntil = .distantPast }
        await sync()
        await refreshHealth()
        await Agenda.shared.refresh()
        await Agenda.shared.pullDeskEvents()
        await PipNudge.shared.refresh()
        tick = Date()
    }
}
