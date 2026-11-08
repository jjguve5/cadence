// Apple Health, read directly with HealthKit. For someone without a Fitbit it is the whole source (sleep, HRV,
// resting HR, steps, ...); with a Fitbit it only adds weight and water. HealthKit needs an entitlement that a free
// Apple ID may not grant to a sideloaded app: when it's missing, `problem` says so and nothing else changes.
import Foundation
import HealthKit

final class AppleHealth {
    static let shared = AppleHealth()
    private let store = HKHealthStore()
    private(set) var problem: String?

    struct Water { var id: String; var date: String; var minute: Int; var ml: Double }
    struct Reading { var days: [HealthDay]; var weights: [(date: String, kg: Double)]; var water: [Water] }

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private func q(_ id: HKQuantityTypeIdentifier) -> HKQuantityType { HKQuantityType(id) }

    private func types(everything: Bool) -> Set<HKObjectType> {
        var t: Set<HKObjectType> = [q(.bodyMass), q(.dietaryWater)]
        guard everything else { return t }
        t.formUnion([HKCategoryType(.sleepAnalysis), q(.heartRateVariabilitySDNN), q(.restingHeartRate), q(.stepCount), q(.activeEnergyBurned),
                     q(.basalEnergyBurned), q(.appleExerciseTime), q(.oxygenSaturation), q(.respiratoryRate), q(.vo2Max)])
        return t
    }

    /// Asks once (iOS shows its sheet the first time only), then reads the last `days` days
    func read(days: Int, everything: Bool) async -> Reading? {
        guard available else { problem = "O Apple Health não está disponível neste dispositivo"; return nil }
        do {
            try await store.requestAuthorization(toShare: [], read: types(everything: everything))
        } catch {
            problem = "O acesso ao Apple Health não está disponível nesta instalação (\(error.localizedDescription))"
            return nil
        }
        problem = nil
        let cal = Day.calendar
        let end = Date(), start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end)) ?? end
        async let weights = latestPerDay(.bodyMass, unit: .gramUnit(with: .kilo), from: start)
        async let water = samples(.dietaryWater, from: start)
        var out = Reading(days: [], weights: await weights, water: await water.map { s in
            Water(id: "hk-" + s.uuid.uuidString, date: Day.key(s.startDate), minute: Day.minuteOfDay(s.startDate), ml: s.quantity.doubleValue(for: .literUnit(with: .milli)))
        })
        guard everything else { return out }

        async let steps = sums(.stepCount, unit: .count(), from: start)
        async let active = sums(.activeEnergyBurned, unit: .kilocalorie(), from: start)
        async let basal = sums(.basalEnergyBurned, unit: .kilocalorie(), from: start)
        async let exercise = sums(.appleExerciseTime, unit: .minute(), from: start)
        async let hrv = averages(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start)
        async let rhr = averages(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: start)
        async let spo2 = averages(.oxygenSaturation, unit: .percent(), from: start)
        async let breathing = averages(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), from: start)
        async let vo2 = latestPerDay(.vo2Max, unit: HKUnit(from: "ml/kg*min"), from: start)
        async let nights = sleep(from: start)
        let (st, ac, ba, ex, hr, rh, sp, br, vo, sl) = await (steps, active, basal, exercise, hrv, rhr, spo2, breathing, vo2, nights)
        let vo2ByDay = Dictionary(vo.map { ($0.date, $0.kg) }, uniquingKeysWith: { a, _ in a })
        let keys = Set(st.keys).union(hr.keys).union(rh.keys).union(sl.keys)
        out.days = keys.sorted().map { d in
            HealthDay(date: d, sleep: sl[d], naps: nil, steps: st[d], azm: ex[d], calories: ac[d].map { $0 + (ba[d] ?? 0) },
                      rhr: rh[d].map { $0.rounded() }, hrv: hr[d], spo2: sp[d].map { $0 * 100 }, breathing: br[d], temp: nil, vo2: vo2ByDay[d])
        }
        return out
    }

    // MARK: Queries

    private func samples(_ id: HKQuantityTypeIdentifier, from start: Date) async -> [HKQuantitySample] {
        await withCheckedContinuation { done in
            let query = HKSampleQuery(sampleType: q(id), predicate: HKQuery.predicateForSamples(withStart: start, end: nil), limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, _ in
                done.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private func latestPerDay(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async -> [(date: String, kg: Double)] {
        var byDay: [String: Double] = [:]
        for s in await samples(id, from: start) { byDay[Day.key(s.startDate)] = s.quantity.doubleValue(for: unit) } // sorted, so the last of a day wins
        return byDay.sorted { $0.key < $1.key }.map { (date: $0.key, kg: $0.value) }
    }

    private func averages(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async -> [String: Double] {
        var byDay: [String: [Double]] = [:]
        for s in await samples(id, from: start) { byDay[Day.key(s.startDate), default: []].append(s.quantity.doubleValue(for: unit)) }
        return byDay.mapValues { $0.reduce(0, +) / Double($0.count) }
    }

    /// Daily totals with Health's own de-duplication (iPhone and Watch both count steps)
    private func sums(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async -> [String: Double] {
        await withCheckedContinuation { done in
            let query = HKStatisticsCollectionQuery(quantityType: q(id), quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: nil),
                                                    options: .cumulativeSum, anchorDate: Day.calendar.startOfDay(for: start), intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, result, _ in
                var out: [String: Double] = [:]
                result?.enumerateStatistics(from: start, to: Date()) { s, _ in
                    if let v = s.sumQuantity()?.doubleValue(for: unit) { out[Day.key(s.startDate)] = v }
                }
                done.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Each night as one sleep record, keyed by the morning it ends on. Phone and watch can both write sleep, so
    /// the source with the most sleep that night is used, never both added together.
    private func sleep(from start: Date) async -> [String: SleepRecord] {
        let all: [HKCategorySample] = await withCheckedContinuation { done in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: nil), limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, _ in
                done.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        func stage(_ v: Int) -> String? {
            switch HKCategoryValueSleepAnalysis(rawValue: v) {
            case .asleepCore: return "light"
            case .asleepDeep: return "deep"
            case .asleepREM: return "rem"
            case .asleepUnspecified: return "asleep"
            case .awake: return "awake"
            default: return nil // in bed
            }
        }
        // a night belongs to the day its sleep ends on, from 18:00 the evening before
        let byNight = Dictionary(grouping: all) { Day.key($0.endDate.addingTimeInterval(6 * 3600)) }
        var out: [String: SleepRecord] = [:]
        let iso = ISO8601DateFormatter()
        for (night, samples) in byNight {
            let bySource = Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }
            let asleepMinutes = { (s: [HKCategorySample]) in s.filter { stage($0.value).map { $0 != "awake" } ?? false }.map { $0.endDate.timeIntervalSince($0.startDate) / 60 }.reduce(0, +) }
            guard let best = bySource.values.max(by: { asleepMinutes($0) < asleepMinutes($1) }), asleepMinutes(best) >= 60,
                  let first = best.map(\.startDate).min(), let last = best.map(\.endDate).max() else { continue }
            var stages: [String: Int] = [:]
            var timeline: [[JSONValue]] = []
            for s in best { guard let st = stage(s.value) else { continue }
                let a = Int(s.startDate.timeIntervalSince(first) / 60), b = Int(s.endDate.timeIntervalSince(first) / 60)
                stages[st, default: 0] += b - a
                timeline.append([.string(st), .number(Double(a)), .number(Double(b))])
            }
            let asleep = Int(asleepMinutes(best))
            out[night] = SleepRecord(start: iso.string(from: first), end: iso.string(from: last), offset: 0, asleep: asleep, awake: stages["awake"],
                                     inBed: Int(last.timeIntervalSince(first) / 60), toFallAsleep: nil, stages: stages, timeline: timeline)
        }
        return out
    }
}
