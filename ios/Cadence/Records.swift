// Typed records for the areas added after step 1 (food, water, workouts...). They sync as generic JSON records
// and are decoded once per change, then cached.
import Foundation

protocol Record: Codable, Identifiable where ID == String {
    static var kind: String { get }
}

@MainActor
extension Store {
    func all<T: Record>(_ type: T.Type) -> [T] {
        if let cached = recordCache[T.kind] as? [T] { return cached }
        let decoded = records(T.kind).values.compactMap { $0.decode(T.self) }
        recordCache[T.kind] = decoded
        return decoded
    }

    func record<T: Record>(_ type: T.Type, _ id: String) -> T? { records(T.kind)[id]?.decode(T.self) }

    func save<T: Record>(_ record: T) {
        put(T.kind, record.id, JSONValue.from(record))
        if let food = record as? FoodEntry { habitsHear(saved: food) }
    }

    func remove<T: Record>(_ record: T) {
        put(T.kind, record.id, nil)
        if let food = record as? FoodEntry { habitsHear(removed: food) }
    }
}
