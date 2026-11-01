// Everything the app knows, saved on the phone first (offline) and synced with the PHP server: records go up when
// they change here and come down when they changed elsewhere. Health days come from health.php.
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
private struct Saved: Codable {
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

    init() {}

    // Every field optional on the way in, so a new field in an update never loses what's saved
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
    @Published var tick = Date() // redraws time-based views

    var recordCache: [String: Any] = [:] // decoded typed records, per type (see Records.swift)
    private var dirty: [String: Int] = [:]
    private var tombstones: [String] = []
    private var rev: Int?
    private var version = 0
    private let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cadence.json")

    private init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            promises = saved.promises; logs = saved.logs; days = saved.days; profile = saved.profile
            feedback = saved.feedback; extra = saved.extra; health = saved.health; device = saved.device
            healthErrors = saved.healthErrors; lastHealth = saved.lastHealth.map { Date(timeIntervalSince1970: $0) }
            connection = saved.connection; dirty = saved.dirty; tombstones = saved.tombstones; rev = saved.rev
            if !saved.seeded { seed() }
        } else {
            seed()
        }
    }

    private func persist() {
        var s = Saved()
        s.promises = promises; s.logs = logs; s.days = days; s.profile = profile; s.feedback = feedback; s.extra = extra
        s.health = health; s.device = device; s.healthErrors = healthErrors; s.lastHealth = lastHealth?.timeIntervalSince1970
        s.connection = connection; s.dirty = dirty; s.tombstones = tombstones; s.rev = rev; s.seeded = true
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: file, options: .atomic) }
    }

    private func mark(_ key: String) {
        version += 1
        dirty[key] = version
        persist()
        Reminders.shared.reschedule()
        scheduleSync()
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

    // MARK: - Promises

    func save(_ promise: PromiseItem) {
        promises[promise.id] = promise
        mark("promise:\(promise.id)")
    }

    func delete(_ promise: PromiseItem) {
        promises[promise.id] = nil
        tombstones.append("promise:\(promise.id)")
        mark("promise:\(promise.id)")
    }

    func log(_ promise: PromiseItem, on day: String = Day.today, _ status: LogStatus) {
        let entry = PromiseLog(promiseId: promise.id, date: day, status: status)
        logs[entry.id] = entry
        mark("log:\(entry.id)")
        Reminders.shared.clear(promise: promise.id, day: day)
        // Routines that log food: ticking the 17:00 shake adds its calories and protein
        if status != .skipped, promise.kcal != nil || promise.protein != nil {
            save(FoodEntry(id: "promise-\(promise.id)-\(day)", date: day, minute: time(of: promise, on: day), name: promise.title, kcal: promise.kcal ?? 0, protein: promise.protein ?? 0, promiseId: promise.id))
        }
    }

    func undo(_ promise: PromiseItem, on day: String = Day.today) {
        let id = "\(promise.id)|\(day)"
        logs[id] = nil
        if let food = record(FoodEntry.self, "promise-\(promise.id)-\(day)") { remove(food) }
        tombstones.append("log:\(id)")
        mark("log:\(id)")
    }

    func status(_ promise: PromiseItem, on day: String = Day.today) -> LogStatus? { logs["\(promise.id)|\(day)"]?.status }

    var activePromises: [PromiseItem] { promises.values.filter(\.active).sorted { time(of: $0) < time(of: $1) } }

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
        days[entry.date] = entry
        mark("day:\(entry.date)")
    }

    func update(_ change: (inout Profile) -> Void) {
        var p = profile
        change(&p)
        guard p != profile else { return }
        profile = p
        mark("profile:me")
    }

    func addFeedback(_ f: ReadinessFeedback) {
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
        var all = extra[type] ?? [:]
        all[id] = value
        extra[type] = all
        recordCache[type] = nil
        if value == nil { tombstones.append("\(type):\(id)") }
        mark("\(type):\(id)")
    }

    // MARK: - Sync

    private var syncTask: Task<Void, Never>?

    func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    func request(_ path: String, body: Data? = nil) -> URLRequest? {
        guard connection.configured, let url = URL(string: connection.server.trimmingCharacters(in: .whitespaces) + "/" + path) else { return nil }
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
        guard connection.configured, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let sent = dirty
        let changes = sent.keys.compactMap(encodeRecord)
        struct Body: Encodable { var since: Int; var changes: [SyncChange] }
        guard let body = try? JSONEncoder().encode(Body(since: rev ?? 0, changes: changes)), let req = request("sync.php", body: body) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { syncError = code == 403 ? "The server refused the token" : "Sync failed (\(code))"; return }
            let reply = try JSONDecoder().decode(SyncReply.self, from: data)
            for (key, v) in sent where dirty[key] == v { dirty[key] = nil }
            tombstones.removeAll { sent[$0] != nil && dirty[$0] == nil }
            for c in reply.changes where dirty["\(c.type):\(c.id)"] == nil { apply(c) }
            rev = reply.rev
            syncError = nil
            persist()
            Reminders.shared.reschedule()
        } catch {
            syncError = "Offline: changes wait on the phone"
        }
    }

    // MARK: - Health

    func refreshHealth(force: Bool = false) async {
        guard connection.configured else { return }
        if !force, let last = lastHealth, Date().timeIntervalSince(last) < 15 * 60 { return }
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
        } catch {}
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
        guard url.scheme == "cadence" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if url.host == "setup", let server = value("server"), let token = value("token") {
            connection = Connection(server: server, token: token)
            Task { await sync(); await refreshHealth(force: true) }
        } else if url.host == "google" {
            googleConnected()
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

    func refreshAll() async {
        await sync()
        await refreshHealth()
        await Agenda.shared.refresh()
        await Agenda.shared.pullDeskEvents()
        tick = Date()
    }
}
