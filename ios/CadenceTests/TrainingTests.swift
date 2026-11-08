// Phase 2.6 (Treino): the suggested target kept apart from what you did, warm-ups only where a muscle group is new,
// the rest with its reason, the effort answer (RIR), changes of plan with confirmation, pause, the summary's
// proposal that only changes the next target once accepted, and the session left open past 23:59.
// Synthetic data only (see RegressionSupport.swift).
import XCTest
@testable import Cadence

final class TrainingTests: RegressionCase {
    private let legExtension = TemplateExercise(exerciseId: "leg-extension", name: "Leg Extensions", sets: 3, repLow: 8, repHigh: 12)

    private func entry(_ id: String, _ primary: [String], _ secondary: [String] = [], category: String = "strength", mechanic: String? = nil, bodyweight: Bool = false) -> CatalogExercise {
        CatalogExercise(id: id, name: id, category: category, bodyPart: nil, primary: primary, secondary: secondary, bodyweight: bodyweight,
                        instructions: [], tips: [], images: [], mechanic: mechanic)
    }

    private func set(_ weight: Double, _ reps: Int, target: Double? = nil, rir: Int? = nil, done: Bool = true, exercise: String = "leg-extension") -> SetLog {
        SetLog(exerciseId: exercise, weight: weight, reps: reps, rir: rir, done: done, at: done ? 1_000 : nil, targetWeight: target, targetReps: target == nil ? nil : 12)
    }

    private func finished(_ id: String, start: Double, _ sets: [SetLog]) -> WorkoutSession {
        WorkoutSession(id: id, date: Fixed.saturday, name: "Legs", start: start, end: start + 3_600_000, order: [legExtension], sets: sets)
    }

    // MARK: The target apart from what you did

    /// Without history there's no target («escolhes tu»), and nothing is written in weight or reps
    @MainActor
    func testNoHistoryMeansNoTarget() throws {
        let store = try makeStore()
        XCTAssertNil(store.target(for: legExtension))
        let plan = store.plan([legExtension], info: [entry("leg-extension", ["quadriceps"])])
        let sets = plan.flatMap { TrainingRules.sets(for: $0) }
        let working = sets.filter { $0.kind == .working }
        XCTAssertEqual(working.count, 3)
        XCTAssertTrue(working.allSatisfy { $0.targetWeight == nil && $0.targetReps == nil && $0.weight == 0 && $0.reps == 0 && !$0.done })
    }

    /// The planned sets carry the target in their own fields; weight and reps stay empty and nothing is done. Without an
    /// accepted proposal the target is what you did last time, not the progression's +2.5 kg.
    @MainActor
    func testTheSuggestedWeightIsNeverWrittenAsDone() throws {
        let store = try makeStore { $0.add(self.finished("S1", start: 1_000, [self.set(18, 12), self.set(18, 12), self.set(18, 11)])) }
        let target = try XCTUnwrap(store.target(for: legExtension))
        XCTAssertEqual(target.weight, 18)
        XCTAssertEqual(target.reps, 12)
        XCTAssertEqual(target.reason, "da última vez fizeste 18 kg × 12, 12, 11")
        let sets = store.plan([legExtension], info: [nil]).flatMap { TrainingRules.sets(for: $0) }
        XCTAssertTrue(sets.allSatisfy { $0.weight == 0 && $0.reps == 0 && !$0.done && $0.at == nil }, "nothing you didn't do is written as done")
        XCTAssertEqual(sets.filter { $0.kind == .working }.map(\.targetWeight), [18, 18, 18])
    }

    /// The summary's proposal changes the next target only once accepted; Desfazer puts the earlier one back. Then the
    /// next session's sets carry it, and it stays until another proposal is accepted.
    @MainActor
    func testAProposalChangesTheNextTargetOnlyOnceAccepted() throws {
        let last = finished("S1", start: 1_000, [set(18, 12), set(18, 12), set(18, 12)])
        let store = try makeStore { $0.add(last) }
        let proposal = try XCTUnwrap(store.proposals(after: last).first)
        XCTAssertEqual(proposal.weight, 20.5)
        XCTAssertTrue(proposal.changes)
        XCTAssertEqual(store.target(for: legExtension)?.weight, 18, "proposed, not applied")
        XCTAssertTrue(store.all(TrainingTarget.self).isEmpty, "a proposal alone saves nothing")

        let before = store.acceptTarget(proposal, from: last, at: 5_000)
        XCTAssertNil(before)
        let accepted = try XCTUnwrap(store.target(for: legExtension))
        XCTAssertEqual(accepted.weight, 20.5)
        XCTAssertTrue(accepted.reason.hasPrefix("aceitaste no fim do último treino"))
        XCTAssertEqual(store.record(TrainingTarget.self, "next:leg-extension")?.session, "S1")

        store.restoreTarget("leg-extension", to: before)
        XCTAssertNil(store.record(TrainingTarget.self, "next:leg-extension"), "Desfazer removes it")
        XCTAssertEqual(store.target(for: legExtension)?.weight, 18)

        // Accepted again, and the next session done with it: its sets carry 20.5 and the target stays there
        store.acceptTarget(proposal, from: last, at: 5_000)
        let next = finished("S2", start: 10_000, [set(20.5, 10, target: 20.5), set(20.5, 10, target: 20.5), set(20.5, 9, target: 20.5)])
        store.save(next)
        let carried = try XCTUnwrap(store.target(for: legExtension))
        XCTAssertEqual(carried.weight, 20.5)
        XCTAssertTrue(carried.reason.hasPrefix("o mesmo objetivo da última vez"))
        let after = try XCTUnwrap(store.proposals(after: next).first)
        XCTAssertEqual(after.weight, 20.5)
        XCTAssertFalse(after.changes, "below the top: the next target stays as it is")
    }

    /// Ajustar saves your own target for next time, with its own reason
    @MainActor
    func testAdjustingSavesYourOwnTarget() throws {
        let last = finished("S1", start: 1_000, [set(18, 12), set(18, 12), set(18, 12)])
        let store = try makeStore { $0.add(last) }
        let proposal = try XCTUnwrap(store.proposals(after: last).first)
        store.acceptTarget(proposal, weight: 19, reps: 10, from: last, at: 5_000)
        let t = try XCTUnwrap(store.target(for: legExtension))
        XCTAssertEqual(t.weight, 19)
        XCTAssertEqual(t.reps, 10)
        XCTAssertEqual(store.record(TrainingTarget.self, "next:leg-extension")?.reason, "ajustado por ti")
    }

    /// Registering writes what you did and keeps the target; it also ends a pause
    func testRegisteringKeepsTheTarget() {
        var s = WorkoutSession(id: "W", date: Fixed.saturday, name: "Legs", start: 1_000, order: [legExtension],
                               sets: [set(0, 0, target: 20, done: false)])
        s.pausedAt = 2_000
        s.register(0, weight: 22.5, reps: 11, rir: 2, at: 3_000)
        XCTAssertEqual(s.sets[0].weight, 22.5)
        XCTAssertEqual(s.sets[0].reps, 11)
        XCTAssertEqual(s.sets[0].rir, 2)
        XCTAssertTrue(s.sets[0].done)
        XCTAssertEqual(s.sets[0].targetWeight, 20, "the target stays as it was")
        XCTAssertEqual(s.sets[0].targetReps, 12)
        XCTAssertNil(s.pausedAt)
    }

    /// The steppers start from what you set, else the target, else the set before, else nothing and the top of the range
    func testStartingValues() {
        let previous = set(20, 9)
        func start(_ s: SetLog, _ p: SetLog?) -> String {
            let v = TrainingRules.startingValues(s, previous: p, repHigh: 12)
            return "\(kg(v.weight))×\(v.reps)"
        }
        XCTAssertEqual(start(set(0, 0, target: 22.5, done: false), previous), "22.5×12")
        XCTAssertEqual(start(set(25, 8, target: 22.5, done: false), previous), "25×8", "touched: yours")
        XCTAssertEqual(start(set(0, 0, done: false), previous), "20×9")
        XCTAssertEqual(start(set(0, 0, done: false), nil), "0×12")
    }

    // MARK: Effort (RIR)

    /// With nothing left in reserve on the last set, the load doesn't go up; with some, it does
    @MainActor
    func testNoRepsInReserveKeepsTheLoad() throws {
        let zero = try makeStore { $0.add(self.finished("S1", start: 1_000, [self.set(18, 12), self.set(18, 12), self.set(18, 12, rir: 0)])) }
        let s = zero.suggestion(for: legExtension)
        XCTAssertEqual(s.weight, 18)
        XCTAssertEqual(s.reason, "Mesmo peso: chegaste ao topo sem repetições em reserva, por isso a carga não sobe")
        let two = try makeStore { $0.add(self.finished("S1", start: 1_000, [self.set(18, 12), self.set(18, 12), self.set(18, 12, rir: 2)])) }
        XCTAssertEqual(two.suggestion(for: legExtension).weight, 20.5)
    }

    /// The question goes on the last working set of each exercise only
    func testTheEffortQuestionIsOnlyOnTheLastWorkingSet() {
        let s = WorkoutSession(id: "W", date: Fixed.saturday, name: "Legs", order: [legExtension], sets: [
            SetLog(exerciseId: "leg-extension", kind: .warmup, weight: 0, reps: 0),
            set(0, 0, target: 20, done: false), set(0, 0, target: 20, done: false),
        ])
        XCTAssertEqual([0, 1, 2].map { s.isLastWorking($0) }, [false, false, true])
    }

    // MARK: Warm-ups

    /// Only the first exercise of each muscle group new in the session; the others name the one that warmed it. An
    /// exercise whose groups aren't known gets them.
    func testWarmUpsOnlyWhereAGroupIsNew() {
        let groups: [Set<String>] = [["hamstrings", "glutes"], ["quads"], ["calves"], ["hamstrings"], ["glutes", "quads"], [], ["quads", "chest"]]
        XCTAssertEqual(TrainingRules.warmedBy(groups), [nil, nil, nil, 0, 0, nil, nil])
    }

    /// The design's leg day: the run gets none and warms nothing; the hamstring curl was warmed by the stiff-legged deadlift
    @MainActor
    func testAPlannedLegDay() throws {
        let store = try makeStore { $0.profile.barKg = 20 }
        let t = { (id: String) in TemplateExercise(exerciseId: id, name: id) }
        let plan = store.plan([t("treadmill-running"), t("stiff-leg-deadlift"), t("leg-extension"), t("leg-curl")], info: [
            entry("treadmill-running", ["gastrocnemius", "quadriceps"], category: "cardio"),
            entry("stiff-leg-deadlift", ["gluteus_maximus", "hamstrings"]),
            entry("leg-extension", ["quadriceps"]),
            entry("leg-curl", ["hamstrings"]),
        ])
        XCTAssertEqual(plan.map(\.warmups.count), [0, 1, 1, 0])
        XCTAssertEqual(plan.map(\.warmedBy), [nil, nil, nil, 1])
        XCTAssertEqual(plan[1].warmups, [WarmupSet(weight: nil, reps: 10)], "no history: one light set, the weight is yours")
    }

    /// The warm-up sets themselves keep the 40/60/80% ramp; below it, one light set at half the target
    @MainActor
    func testWarmUpSets() throws {
        let store = try makeStore { $0.profile.barKg = 20 }
        let ramp = store.warmupSets(for: SetTarget(weight: 60, reps: 8, reason: ""))
        XCTAssertEqual(ramp, store.warmups(for: 60).map { WarmupSet(weight: $0.weight, reps: $0.reps) })
        XCTAssertEqual(ramp.map { "\($0.weight ?? 0)×\($0.reps)" }, ["25.0×8", "35.0×5", "47.5×3"])
        XCTAssertEqual(store.warmupSets(for: SetTarget(weight: 20, reps: 10, reason: "")), [WarmupSet(weight: 10, reps: 10)])
        XCTAssertEqual(store.warmupSets(for: nil), [WarmupSet(weight: nil, reps: 10)])
    }

    // MARK: Rest

    func testRestFollowsTheExerciseAndTheSet() {
        XCTAssertEqual(TrainingRules.rest(.compound, reps: 6, templateRest: 90).seconds, 150, "compound and heavy: 2:30")
        XCTAssertEqual(TrainingRules.rest(.compound, reps: 8, templateRest: 90).seconds, 120, "compound with 8 or more: 2:00")
        XCTAssertEqual(TrainingRules.rest(.isolation, reps: 6, templateRest: 90).seconds, 90, "heavy isolation: 1:30")
        XCTAssertEqual(TrainingRules.rest(.isolation, reps: 12, templateRest: 90).seconds, 75, "light isolation: 1:15")
        XCTAssertEqual(TrainingRules.rest(nil, reps: 12, templateRest: 105).seconds, 105, "unknown exercise: the template's")
        XCTAssertEqual(TrainingRules.rest(.compound, reps: 10, templateRest: 90).reason, "exercício composto, série de 10 repetições.")
        XCTAssertEqual(TrainingRules.restClock(150), "2:30")
        XCTAssertEqual(TrainingRules.restClock(75), "1:15")
    }

    func testCompoundOrIsolation() {
        XCTAssertEqual(TrainingRules.mechanic(entry("x", ["quadriceps"], mechanic: "compound")), .compound, "RepDB's field first")
        XCTAssertEqual(TrainingRules.mechanic(entry("squat", ["gluteus_maximus", "quadriceps"])), .compound)
        XCTAssertEqual(TrainingRules.mechanic(entry("bench", ["pectoralis_major"], ["anterior_deltoid", "triceps_brachii"])), .compound)
        XCTAssertEqual(TrainingRules.mechanic(entry("leg-extension", ["quadriceps"])), .isolation)
        XCTAssertEqual(TrainingRules.mechanic(entry("leg-curl", ["hamstrings"], ["gastrocnemius"])), .isolation)
    }

    // MARK: Changes of plan

    private func threeExercises() -> WorkoutSession {
        let a = TemplateExercise(exerciseId: "a", name: "A", sets: 2), b = TemplateExercise(exerciseId: "b", name: "B", sets: 1), c = TemplateExercise(exerciseId: "c", name: "C", sets: 1)
        return WorkoutSession(id: "W", date: Fixed.saturday, name: "Legs", start: 1_000, order: [a, b, c], sets: [
            set(0, 0, target: 20, done: false, exercise: "a"), set(0, 0, target: 20, done: false, exercise: "a"),
            set(0, 0, done: false, exercise: "b"), set(0, 0, done: false, exercise: "c"),
        ])
    }

    /// The current set follows the order of the exercises and leaves skipped ones out; skipped is not failed
    func testReorderAndSkip() {
        var s = threeExercises()
        XCTAssertEqual(s.currentSet()?.exercise.exerciseId, "a")
        s.register(0, weight: 20, reps: 12, rir: nil)
        s.register(1, weight: 20, reps: 11, rir: nil)
        XCTAssertEqual(s.next(after: "a")?.exerciseId, "b")
        s.moveUp("c", before: "b")
        XCTAssertEqual(s.order.map(\.exerciseId), ["a", "c", "b"])
        XCTAssertEqual(s.reordered, ["c"], "marked «trocado de ordem»")
        XCTAssertEqual(s.currentSet()?.exercise.exerciseId, "c")
        s.skip("c", reason: ExerciseSkipReason.time.rawValue)
        XCTAssertTrue(s.isSkipped("c"))
        XCTAssertEqual(s.currentSet()?.exercise.exerciseId, "b")
        XCTAssertEqual(s.sets.filter(\.done).count, 2, "every registered set stays")
    }

    /// Replacing an exercise keeps its registered sets (and it, if it has any); Desfazer puts the plan back and keeps
    /// anything registered since
    func testReplaceAndUndo() {
        var s = threeExercises()
        s.register(0, weight: 20, reps: 12, rir: nil)
        let before = s
        let d = TemplateExercise(exerciseId: "d", name: "D", sets: 2)
        s.replace(s.order[0], with: d, sets: [set(0, 0, done: false, exercise: "d"), set(0, 0, done: false, exercise: "d")])
        XCTAssertEqual(s.order.map(\.exerciseId), ["a", "d", "b", "c"], "A had a registered set, so it stays")
        XCTAssertEqual(s.sets.filter { $0.exerciseId == "a" }.count, 1, "its sets still to do go")
        XCTAssertEqual(s.swapped, ["d": "a"])
        let first = s.sets.firstIndex { $0.exerciseId == "d" } ?? 0
        s.register(first, weight: 15, reps: 10, rir: nil)
        let undone = s.restoringPlan(from: before)
        XCTAssertEqual(undone.order.map(\.exerciseId), ["a", "b", "c"])
        XCTAssertNil(undone.swapped)
        XCTAssertEqual(undone.sets.filter(\.done).count, 2, "the set registered since is kept")

        var fresh = threeExercises()
        fresh.replace(fresh.order[1], with: d, sets: [])
        XCTAssertEqual(fresh.order.map(\.exerciseId), ["a", "d", "c"], "nothing registered: it takes its place")
    }

    /// Ending keeps every registered set and drops only the plan; it's partial when something planned and not skipped
    /// was left to do
    func testFinishing() {
        var s = threeExercises()
        s.register(0, weight: 20, reps: 12, rir: nil)
        var partial = s
        partial.finish(at: 9_000)
        XCTAssertEqual(partial.end, 9_000)
        XCTAssertEqual(partial.partial, true)
        XCTAssertEqual(partial.sets.count, 1)
        XCTAssertTrue(partial.sets.allSatisfy(\.done))

        var whole = s
        whole.register(1, weight: 20, reps: 12, rir: nil)
        whole.register(2, weight: 10, reps: 12, rir: nil)
        whole.skip("c", reason: "")
        whole.finish(at: 9_000)
        XCTAssertNil(whole.partial, "a skipped exercise doesn't make it partial")
        XCTAssertEqual(whole.skipped, ["c": ""])
    }

    // MARK: Left open past 23:59

    /// Yesterday's open session is partial, not in progress, even before it's closed; closing marks it as ended at the
    /// last thing done and as partial, changes nothing else, and happens once
    @MainActor
    func testASessionLeftOpenPastMidnightBecomesPartialOnce() throws {
        let yesterday = Day.add(-1, to: Day.today)
        var open = WorkoutSession(id: "Y", date: yesterday, name: "Legs", start: 1_000, order: [legExtension],
                                  sets: [set(20, 12), set(0, 0, target: 20, done: false)])
        open.sets[0].at = 600_000
        open.pausedAt = 700_000
        let today = WorkoutSession(id: "T", date: Day.today, name: "Push", start: 2_000, order: [])
        let earlier = WorkoutSession(id: "F", date: Day.add(-3, to: Day.today), name: "Pull", start: 500, end: 900, order: [])
        let store = try makeStore { s in
            s.add(open)
            s.add(today)
            s.add(earlier)
        }
        XCTAssertEqual(store.activeSession?.id, "T", "yesterday's isn't in progress")
        XCTAssertTrue(TrainingRules.isPartial(open, today: Day.today))

        XCTAssertEqual(store.closeExpiredSessions(), 1)
        var expected = open
        expected.end = 700_000
        expected.partial = true
        XCTAssertEqual(store.record(WorkoutSession.self, "Y"), expected, "only end and partial change; its sets stay")
        XCTAssertNil(store.record(WorkoutSession.self, "T")?.end)
        XCTAssertEqual(store.record(WorkoutSession.self, "F")?.end, 900)

        let stored = store.records(WorkoutSession.kind)["Y"]
        XCTAssertEqual(store.closeExpiredSessions(), 0, "idempotent")
        XCTAssertEqual(store.records(WorkoutSession.kind)["Y"], stored)
    }

    // MARK: Data

    /// The new fields are optional: an older session reads with none of them, a session without them writes none, and
    /// an empty object the server sent back as [] reads as empty
    func testTheNewFieldsAreOptional() throws {
        let old = try JSONDecoder().decode(WorkoutSession.self, from: Data(#"{"id":"S1","name":"Pernas","order":[],"sets":[{"id":"x","exerciseId":"a","kind":"working","weight":20,"reps":10,"done":true}]}"#.utf8))
        XCTAssertNil(old.pausedAt)
        XCTAssertNil(old.partial)
        XCTAssertNil(old.skipped)
        XCTAssertNil(old.reordered)
        XCTAssertNil(old.swapped)
        XCTAssertNil(old.sets[0].targetWeight)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any]).keys
        XCTAssertTrue(Set(keys).isDisjoint(with: ["pausedAt", "partial", "skipped", "reordered", "swapped"]))
        let php = try JSONDecoder().decode(WorkoutSession.self, from: Data(#"{"id":"S2","order":[],"skipped":[],"reordered":{},"swapped":null}"#.utf8))
        XCTAssertEqual(php.skipped, [:])
        XCTAssertEqual(php.reordered, [])
        XCTAssertNil(php.swapped)
        XCTAssertThrowsError(try JSONDecoder().decode(WorkoutSession.self, from: Data(#"{"id":"S3","order":[],"skipped":{"a":5}}"#.utf8)))
    }

    /// The target's record id: only [A-Za-z0-9_.:-], up to 80 characters
    func testTargetIds() {
        XCTAssertEqual(TrainingRules.targetId("leg-extension"), "next:leg-extension")
        XCTAssertEqual(TrainingRules.targetId("a b/ç"), "next:a_b__")
        let long = TrainingRules.targetId(String(repeating: "x", count: 200))
        XCTAssertEqual(long.count, 80)
    }

    // MARK: Words

    func testSummaryWords() {
        XCTAssertEqual(TrainingRules.setsText([set(20, 11), set(20, 10), set(20, 10)]), "20 kg × 11, 10, 10")
        XCTAssertEqual(TrainingRules.setsText([set(20, 11), set(17.5, 10)]), "20 kg × 11, 17.5 kg × 10")
        XCTAssertEqual(TrainingRules.setsText([set(0, 8), set(0, 7)]), "8, 7 reps")
        XCTAssertEqual(TrainingRules.change(now: [set(22, 10)], before: [set(20, 12)]), "+2 kg")
        XCTAssertEqual(TrainingRules.change(now: [set(40, 15), set(40, 14)], before: [set(40, 14), set(40, 13)]), "+2 reps")
        XCTAssertEqual(TrainingRules.change(now: [set(30, 12)], before: [set(30, 12)]), "igual")
        XCTAssertEqual(TrainingRules.change(now: [set(30, 12)], before: []), "1.ª vez")
        XCTAssertEqual(TrainingRules.belowTarget([set(30, 12, target: 30), set(30, 12, target: 30), set(30, 8, target: 30)]), "a 3.ª abaixo do objetivo")
        XCTAssertNil(TrainingRules.belowTarget([set(30, 12)]), "no target, nothing below it")
        XCTAssertEqual(TrainingRules.groupsText(["hamstrings", "glutes"]), "glúteos e isquiotibiais")
        XCTAssertEqual(TrainingRules.sentence("Mesmo peso: tenta 12"), "mesmo peso: tenta 12")
    }

    func testAlternativesShareAMainGroup() {
        let current = entry("leg-extension", ["quadriceps"])
        let all = [current, entry("goblet-squat", ["quadriceps", "gluteus_maximus"]), entry("sissy-squat", ["quadriceps"], bodyweight: true),
                   entry("leg-press", ["quadriceps"]), entry("curl", ["biceps_brachii"]), entry("stretch", ["quadriceps"], category: "stretching")]
        let options = TrainingRules.alternatives(to: current, from: all, excluding: ["leg-press"], known: [])
        XCTAssertEqual(options.map(\.id), ["goblet-squat", "sissy-squat"], "same group, strength, not in the session; weights first")
        XCTAssertEqual(TrainingRules.alternatives(to: current, from: all, excluding: [], known: ["leg-press"]).first?.id, "leg-press", "one you've done first")
    }
}
