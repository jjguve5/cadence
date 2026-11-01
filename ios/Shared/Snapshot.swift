// What the home-screen and lock-screen widgets show, written by the app into the shared App Group container.
// Sideloading can rename the group, so both sides try the likely names and use the first that exists.
import Foundation

struct Snapshot: Codable {
    var score: Int
    var readiness: Int?
    var readinessLabel: String?
    var next: String?
    var nextTime: String?
    var mustDos: [String]
    var water: Double
    var waterGoal: Double
    var protein: Double
    var proteinGoal: Double
    var mood: String // Pip's head image name
    var level: Int
    var updated: Date
}

enum SharedBox {
    static func container() -> URL? {
        var bundle = Bundle.main.bundleIdentifier ?? "com.jjguve5.cadence"
        if bundle.hasSuffix(".widgets") { bundle = String(bundle.dropLast(".widgets".count)) }
        for group in ["group.com.jjguve5.cadence", "group." + bundle] {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) { return url }
        }
        return nil
    }

    static var file: URL? { container()?.appendingPathComponent("snapshot.json") }

    static func write(_ s: Snapshot) -> Bool {
        guard let file, let data = try? JSONEncoder().encode(s) else { return false }
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    static func read() -> Snapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
