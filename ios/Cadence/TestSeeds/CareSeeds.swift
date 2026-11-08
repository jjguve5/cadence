// UI-test scenarios for Higiene (2.5). Only used in test mode (TestSeed.apply runs only with CADENCE_UITEST, on a
// fresh test file): synthetic data, never the real file. Name scenarios "care.<case>" and act only on those.
import Foundation

@MainActor
enum CareSeeds {
    static func apply(_ store: Store, scenario: String) {
        guard scenario.hasPrefix("care.") else { return }
        // The UI tests need a few seconds to reach Desfazer; how it expires is unit-tested (StateViewsTests)
        UndoCenter.shared.seconds = 20
        let today = Day.today
        func at(_ minute: Int, _ day: String) -> Double { Day.at(minute, on: day).timeIntervalSince1970 * 1000 }
        // The morning and night routines, both with the face wash that uses your product; the beard, due tomorrow
        var product = CareProduct(id: "PB", name: "Bioderma Sébium Gel Moussant", size: 200, perUse: 2)
        store.save(CareRoutine(id: "RM", title: "Rotina da manhã", icon: "sun.max", steps: [RoutineStep(id: "RM1", title: "Lavar os dentes", seconds: 120),
                                                                                          RoutineStep(id: "RM2", title: "Lavar a cara", seconds: 60, productId: "PB")]))
        store.save(CareRoutine(id: "RN", title: "Rotina da noite", icon: "moon.stars", steps: [RoutineStep(id: "RN1", title: "Lavar a cara", seconds: 60, productId: "PB"),
                                                                                         RoutineStep(id: "RN2", title: "Lavar os dentes", seconds: 120)]))
        store.save(GroomingItem(id: "GB", title: "Aparar a barba", icon: "scissors", interval: 7, history: [Day.add(-6, to: today)]))
        if scenario == "care.product" {
            // A week of both routines confirmed (twice a day), and «Pouco» said yesterday: it runs out in about 2 weeks,
            // so the shopping suggestion shows (nothing of it is on the list yet)
            for i in 1...7 {
                let d = Day.add(-i, to: today)
                store.save(RoutineLog(id: CareRules.logId(routine: "RM", day: d), routineId: "RM", date: d, steps: ["RM1": at(8 * 60, d), "RM2": at(8 * 60 + 2, d)]))
                store.save(RoutineLog(id: CareRules.logId(routine: "RN", day: d), routineId: "RN", date: d, steps: ["RN1": at(22 * 60, d), "RN2": at(22 * 60 + 2, d)]))
            }
            product.left = 0.25
            product.leftAt = at(12 * 60, Day.add(-1, to: today))
        }
        store.save(product)
    }
}
