// Local data protection. The phone is the source of truth, so cadence.json follows three rules: a file that exists
// but can't be read is never written over; every write goes to a separate file, is read back and checked, and only
// then replaces the original in one step; and validated copies are kept on the phone. These are plain file functions
// with the disk passed in, so every failure path can be tested.
import Foundation

/// Why a write didn't happen. The original file is intact in every case.
enum StorageError: Error, Equatable {
    case encoding(String)     // the data has a value JSON can't hold (a number that isn't a number)
    case verification(String) // what would be written, or what was written, isn't what is in memory
    case noSpace
    case write(String)

    /// For the person, in Portuguese
    var message: String {
        switch self {
        case .encoding: return "Há um valor inválido nos dados e não foi possível convertê-los. Nada foi gravado por cima."
        case .verification: return "A gravação não passou na verificação. O ficheiro anterior continua intacto."
        case .noSpace: return "Espaço insuficiente no iPhone. Liberta espaço para o Cadence poder guardar."
        case .write(let detail): return "Não foi possível gravar no iPhone (\(detail)). O ficheiro anterior continua intacto."
        }
    }
}

/// What reading the data file found
enum LoadResult {
    case fresh                                // no file yet: a new install
    case ok(Saved, Data)                      // everything was read
    case cannotOpen(String)                   // the file is there but couldn't be opened (locked, I/O)
    case corrupt(String)                      // not a Cadence data file: empty, cut short, not JSON
    case incompatible(Saved, [String], Data)  // read, but these categories couldn't be
}

/// Whether the app may change data. Anything but .ok blocks every change until the data is safe.
enum StorageState: Equatable {
    case ok
    case protected(StorageProblem)
    case unsaved(String) // a write failed: the message for the person
}

struct StorageProblem: Equatable {
    enum Kind: Equatable { case cannotOpen, corrupt, incompatible }
    var kind: Kind
    var detail: String
    var categories: [String]
}

/// A validated copy on the phone
struct LocalCopy: Identifiable, Equatable {
    var url: URL
    var date: Date
    var records: Int
    var beforeUpdate: Bool
    var id: String { url.lastPathComponent }
}

struct RotationResult: Equatable {
    var created: [String] = []
    var beforeUpdateDone = false
    var lowSpace = false
    var error: String?
}

enum Storage {
    /// Categories the server can send again (Fitbit data). Everything else is personal and lives only here.
    static let recoverable: Set<String> = ["health", "healthErrors", "device", "lastHealth"]
    static let keepDaily = 3, keepBeforeUpdate = 2
    static let dailyPrefix = "diaria-", beforeUpdatePrefix = "antes-da-atualizacao-", archiveFolder = "arquivo"

    /// The disk, behind two functions, so tests can make writing fail or report little free space
    struct Disk {
        var write: (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        var freeBytes: (URL) -> Int64? = { url in
            let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            return (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        }
        static let real = Disk()
    }

    /// Sorted keys, so the same data always gives the same bytes
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    // MARK: Reading

    static func load(from file: URL, fm: FileManager = .default) -> LoadResult {
        guard fm.fileExists(atPath: file.path) else { return .fresh }
        let data: Data
        do { data = try Data(contentsOf: file) } catch { return .cannotOpen(error.localizedDescription) }
        guard !data.isEmpty else { return .corrupt("o ficheiro está vazio") }
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return .corrupt("o conteúdo não é legível") }
        guard saved.recognised else { return .corrupt("não parece um ficheiro do Cadence") }
        return saved.unreadable.isEmpty ? .ok(saved, data) : .incompatible(saved, saved.unreadable, data)
    }

    // MARK: Writing

    /// Encodes, checks that the bytes read back as exactly what is in memory, writes them next to the file, reads that
    /// back, and only then swaps it in. Any failure leaves the original untouched.
    @discardableResult
    static func write(_ saved: Saved, to file: URL, fm: FileManager = .default, disk: Disk = .real) throws -> Data {
        let data: Data
        do { data = try encoder().encode(saved) } catch { throw StorageError.encoding(String(describing: error)) }
        guard let back = try? JSONDecoder().decode(Saved.self, from: data), back.unreadable.isEmpty, back == saved else {
            throw StorageError.verification("a leitura de controlo não coincide")
        }
        try writeBytes(data, to: file, fm: fm, disk: disk)
        return data
    }

    /// Writes bytes as they are (copies, archives, recovery), with the same write-check-swap steps
    static func writeBytes(_ data: Data, to file: URL, fm: FileManager = .default, disk: Disk = .real) throws {
        if let free = disk.freeBytes(file), free < Int64(data.count) * 2 + 1_000_000 { throw StorageError.noSpace }
        let temp = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".new")
        defer { try? fm.removeItem(at: temp) }
        do { try disk.write(data, temp) } catch { throw classify(error) }
        guard (try? Data(contentsOf: temp)) == data else { throw StorageError.verification("o ficheiro gravado é diferente") }
        do {
            if fm.fileExists(atPath: file.path) { _ = try fm.replaceItemAt(file, withItemAt: temp) } else { try fm.moveItem(at: temp, to: file) }
        } catch { throw classify(error) }
        guard (try? Data(contentsOf: file)) == data else { throw StorageError.verification("o ficheiro final é diferente") }
    }

    static func classify(_ error: Error) -> StorageError {
        if let e = error as? StorageError { return e }
        let ns = error as NSError
        let full = (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError) || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC))
        if full { return .noSpace }
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain, u.code == Int(ENOSPC) { return .noSpace }
        return .write(ns.localizedDescription)
    }

    // MARK: Copies on the phone

    static func archiveDir(_ copies: URL) -> URL { copies.appendingPathComponent(archiveFolder, isDirectory: true) }

    static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }

    /// Keeps the original bytes of a file that couldn't be used, before anything replaces it
    @discardableResult
    static func archive(_ data: Data, in copies: URL, reason: String, fm: FileManager = .default, disk: Disk = .real) throws -> URL {
        let dir = archiveDir(copies)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(reason)-\(stamp()).json")
        try writeBytes(data, to: url, fm: fm, disk: disk)
        return url
    }

    /// After a clean read: one copy a day of the file as it was read, and one before each new build of the app.
    /// A copy counts only once it reads back as valid; older copies go only after that, and the last good one stays.
    static func rotate(validated data: Data, copies dir: URL, today: String, build: String, lastBuild: String?,
                       fm: FileManager = .default, disk: Disk = .real) -> RotationResult {
        var result = RotationResult()
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { result.error = error.localizedDescription; return result }
        if let free = disk.freeBytes(dir), free < Int64(data.count) * 3 + 5_000_000 { result.lowSpace = true; return result }
        func makeCopy(_ name: String) -> Bool {
            let url = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path), case .ok = load(from: url, fm: fm) { return true }
            do { try writeBytes(data, to: url, fm: fm, disk: disk) } catch { result.error = classify(error).message; return false }
            guard case .ok = load(from: url, fm: fm) else { try? fm.removeItem(at: url); result.error = "a cópia não passou na validação"; return false }
            result.created.append(name)
            return true
        }
        let daily = makeCopy("\(dailyPrefix)\(today).json")
        if daily { prune(dir, prefix: dailyPrefix, keep: keepDaily, fm: fm) }
        if lastBuild != build {
            let safe = build.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            result.beforeUpdateDone = makeCopy("\(beforeUpdatePrefix)\(today)-\(safe).json")
            if result.beforeUpdateDone { prune(dir, prefix: beforeUpdatePrefix, keep: keepBeforeUpdate, fm: fm) }
        }
        return result
    }

    /// Removes the oldest copies with this prefix beyond `keep`, never touching a copy that isn't valid-and-newer
    static func prune(_ dir: URL, prefix: String, keep: Int, fm: FileManager = .default) {
        let all = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
        let valid = all.filter { if case .ok = load(from: $0, fm: fm) { return true } else { return false } }
            .sorted { (modified($0), $0.lastPathComponent) > (modified($1), $1.lastPathComponent) } // names carry the date
        guard valid.count > keep else { return }
        for url in valid.dropFirst(keep) { try? fm.removeItem(at: url) }
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// Valid copies, newest first
    static func listCopies(in dir: URL, fm: FileManager = .default) -> [LocalCopy] {
        let urls = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter { $0.pathExtension == "json" }
        return urls.compactMap { url -> LocalCopy? in
            guard case .ok(let saved, _) = load(from: url, fm: fm) else { return nil }
            return LocalCopy(url: url, date: modified(url), records: saved.personalRecords, beforeUpdate: url.lastPathComponent.hasPrefix(beforeUpdatePrefix))
        }.sorted { $0.date > $1.date }
    }

    /// Puts a validated copy in place of the data file. Whatever was there is archived first, byte for byte, so this
    /// can be undone. Returns where the previous file was kept (nil when there was none).
    @discardableResult
    static func recover(file: URL, from copy: URL, copies dir: URL, fm: FileManager = .default, disk: Disk = .real) throws -> URL? {
        guard case .ok(_, let data) = load(from: copy, fm: fm) else { throw StorageError.verification("a cópia escolhida não é válida") }
        var kept: URL?
        if fm.fileExists(atPath: file.path) {
            let previous = try Data(contentsOf: file)
            kept = try archive(previous, in: dir, reason: "antes-da-recuperacao", fm: fm, disk: disk)
        }
        try writeBytes(data, to: file, fm: fm, disk: disk)
        guard case .ok = load(from: file, fm: fm) else { throw StorageError.verification("o ficheiro recuperado não se lê") }
        return kept
    }

    /// Undoes a recovery: the archived file goes back exactly as it was, after the current one is archived too
    static func putBack(_ archived: URL, file: URL, copies dir: URL, fm: FileManager = .default, disk: Disk = .real) throws {
        let original = try Data(contentsOf: archived)
        if fm.fileExists(atPath: file.path) {
            try archive(try Data(contentsOf: file), in: dir, reason: "antes-de-desfazer", fm: fm, disk: disk)
        }
        try writeBytes(original, to: file, fm: fm, disk: disk)
    }

    /// Changes with every build installed, so a copy is made before the first run of a new version
    static func buildStamp(_ bundle: Bundle = .main) -> String {
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let date = bundle.executableURL.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        return "\(version)-\(build)-\(Int(date?.timeIntervalSince1970 ?? 0))"
    }

    // MARK: Names for the person

    static func name(ofCategory key: String) -> String {
        ["promises": "Hábitos", "logs": "Conclusões de hábitos", "days": "Dias fechados", "profile": "Perfil e metas",
         "feedback": "Feedback da recuperação", "extra": "Registos (comida, água, treinos, diário…)", "health": "Dados da Fitbit",
         "healthErrors": "Estado da Fitbit", "device": "Estado da Fitbit", "lastHealth": "Estado da Fitbit",
         "connection": "Ligação ao servidor", "dirty": "Alterações por enviar", "tombstones": "Apagamentos por enviar",
         "rev": "Estado da sincronização", "seeded": "Configuração inicial"][key] ?? key
    }

    static func name(ofType type: String) -> String {
        ["water": "água", "food": "comida", "promise": "hábitos", "log": "conclusões", "day": "dias", "profile": "perfil",
         "feedback": "feedback", "shower": "duches", "brush": "escovagem", "session": "treinos", "journal": "diário",
         "mood": "humor", "weight": "peso", "groom": "cuidados pessoais", "med": "medicamentos", "medlog": "tomas"][type] ?? type
    }
}
