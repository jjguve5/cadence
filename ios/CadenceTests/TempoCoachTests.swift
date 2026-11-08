// The guided set's model: phase order per exercise, breathing, counting from elapsed time, and typed numbers.
import XCTest
@testable import Cadence

final class TempoCoachTests: XCTestCase {
    private func kinds(_ id: String, _ name: String = "") -> [TempoPhase.Kind] {
        TempoPlan.forExercise(id: id, name: name).phases.map(\.kind).filter { $0 != .hold }
    }

    private let lowerThenLift: [TempoPhase.Kind] = [.eccentric, .concentric]
    private let liftThenLower: [TempoPhase.Kind] = [.concentric, .eccentric]

    // A plan with whole seconds: 3 down, 1 up, so a rep is 4 seconds
    private let simple = TempoPlan(phases: [.lower(3), .lift(1)])

    func testLoweringFirstExercises() {
        for id in ["squat", "bench-press", "ohp", "incline-db-press", "leg-press", "push-up", "dips", "lunge", "db-fly", "skull-crusher", "romanian-deadlift", "dragon-flag", "nordic-hamstring-curl", "db-pullover"] {
            XCTAssertEqual(kinds(id), lowerThenLift, id)
        }
    }

    func testLiftingFirstExercises() {
        for id in ["pull-up", "chin-ups", "barbell-row", "bicep-curl", "deadlift", "hex-bar-deadlift", "db-shrug", "leg-extension", "leg-curl", "lateral-raise", "hip-thrust", "face-pull", "reverse-curl", "rear-delt-fly", "step-ups"] {
            XCTAssertEqual(kinds(id), liftThenLower, id)
        }
    }

    func testClassifiesFromTheNameWhenTheIdSaysNothing() {
        XCTAssertEqual(kinds("x1", "Barbell Back Squat"), lowerThenLift)
        XCTAssertEqual(kinds("x2", "Pull-Up"), liftThenLower)
        XCTAssertEqual(kinds("x3", "Bent-Over Row"), liftThenLower)
    }

    func testWholeWordsOnly() {
        XCTAssertEqual(kinds("x", "Narrow Grip Bench Press"), lowerThenLift, "narrow isn't a row")
        XCTAssertEqual(kinds("x", "Something Unknown"), liftThenLower, "the default is lift first")
    }

    func testPulldownsPullTheBarDownFirst() {
        for id in ["lat-pulldown", "tricep-pushdown", "straight-arm-pulldown"] {
            let plan = TempoPlan.forExercise(id: id, name: "")
            XCTAssertEqual(plan.phases.first?.kind, .concentric, id)
            XCTAssertEqual(plan.phases.first?.breath, .exhale, id)
            XCTAssertEqual(plan.phases.first?.to, 0, "the handle travels down during the effort")
            XCTAssertEqual(plan.phases.last?.kind, .eccentric, id)
            XCTAssertEqual(plan.phases.last?.to, 1, id)
        }
    }

    func testHoldsWhereSensible() {
        XCTAssertTrue(TempoPlan.forExercise(id: "pull-up", name: "").phases.contains { $0.kind == .hold })
        XCTAssertTrue(TempoPlan.forExercise(id: "bench-press", name: "").phases.contains { $0.kind == .hold })
        XCTAssertFalse(TempoPlan.forExercise(id: "squat", name: "").phases.contains { $0.kind == .hold })
    }

    func testBreathingFollowsThePhase() {
        for id in ["squat", "bench-press", "pull-up", "barbell-row", "bicep-curl", "lat-pulldown", "db-shrug", "dragon-flag"] {
            for phase in TempoPlan.forExercise(id: id, name: "").phases {
                switch phase.kind {
                case .eccentric: XCTAssertEqual(phase.breath, .inhale, id)
                case .concentric: XCTAssertEqual(phase.breath, .exhale, id)
                case .hold: XCTAssertEqual(phase.breath, .hold, id)
                }
            }
        }
    }

    func testBarMovesTheRightWay() {
        let squat = TempoPlan.forExercise(id: "squat", name: "")
        XCTAssertEqual(squat.phases[0].from, 1)
        XCTAssertEqual(squat.phases[0].to, 0)
        let curl = TempoPlan.forExercise(id: "bicep-curl", name: "")
        XCTAssertEqual(curl.phases[0].from, 0)
        XCTAssertEqual(curl.phases[0].to, 1)
    }

    func testTimedHolds() {
        for id in ["plank", "side-plank", "wall-sit", "dead-hang", "l-sit", "squat-hold", "cobra-stretch", "suitcase-carry"] {
            let plan = TempoPlan.forExercise(id: id, name: "")
            XCTAssertTrue(plan.timed, id)
            XCTAssertEqual(plan.phases.first?.breath, .steady, id)
        }
        for id in ["plank-knee-tuck", "hanging-leg-raise", "walking-lunge", "reverse-plank-dips", "pseudo-planche-push-ups"] {
            XCTAssertFalse(TempoPlan.forExercise(id: id, name: "").timed, id)
        }
        let plank = TempoPlan.forExercise(id: "plank", name: "")
        XCTAssertEqual(plank.frame(elapsed: 12.5, target: 30).completed, 12)
        XCTAssertFalse(plank.frame(elapsed: 29.9, target: 30).done)
        XCTAssertTrue(plank.frame(elapsed: 30, target: 30).done)
    }

    func testRepCountingByElapsedTime() {
        XCTAssertEqual(simple.frame(elapsed: 0, target: 10).rep, 1)
        XCTAssertEqual(simple.frame(elapsed: 0, target: 10).completed, 0)
        XCTAssertEqual(simple.frame(elapsed: 3.9, target: 10).rep, 1)
        XCTAssertEqual(simple.frame(elapsed: 4, target: 10).rep, 2)
        XCTAssertEqual(simple.frame(elapsed: 4, target: 10).completed, 1)
        XCTAssertEqual(simple.frame(elapsed: 15.5, target: 10).rep, 4)
    }

    func testPhaseAndProgressInsideARep() {
        let early = simple.frame(elapsed: 1.5, target: 10)
        XCTAssertEqual(early.phaseIndex, 0)
        XCTAssertEqual(early.phase.word, "Desce")
        XCTAssertEqual(early.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(early.position, 0.5, accuracy: 0.0001)
        let late = simple.frame(elapsed: 3.5, target: 10)
        XCTAssertEqual(late.phaseIndex, 1)
        XCTAssertEqual(late.phase.breath, .exhale)
        XCTAssertEqual(late.progress, 0.5, accuracy: 0.0001)
    }

    func testDoneDetection() {
        XCTAssertFalse(simple.frame(elapsed: 39.99, target: 10).done)
        let end = simple.frame(elapsed: 40, target: 10)
        XCTAssertTrue(end.done)
        XCTAssertEqual(end.completed, 10)
        XCTAssertEqual(end.rep, 10)
        XCTAssertTrue(simple.frame(elapsed: 5000, target: 10).done, "a phone locked for ages comes back finished")
    }

    func testStrangeInputsStaySafe() {
        XCTAssertEqual(simple.frame(elapsed: -5, target: 10).rep, 1, "the clock moved backwards")
        XCTAssertEqual(simple.frame(elapsed: 0, target: 0).target, 1)
    }

    func testClockSurvivesPausesAndGaps() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var clock = TempoClock()
        XCTAssertEqual(clock.elapsed(at: t0), 0)
        clock.start(at: t0)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(10)), 10, accuracy: 0.001)
        clock.pause(at: t0.addingTimeInterval(10))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(100)), 10, accuracy: 0.001)
        clock.start(at: t0.addingTimeInterval(100))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(105)), 15, accuracy: 0.001)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(50)), 10, accuracy: 0.001, "never runs backwards")
    }

    func testCues() {
        let first = simple.frame(elapsed: 0, target: 3)
        XCTAssertEqual(simple.cue(from: nil, to: first, speakBreath: true), "1. inspira")
        XCTAssertEqual(simple.cue(from: nil, to: first, speakBreath: false), "1")
        XCTAssertNil(simple.cue(from: first, to: simple.frame(elapsed: 1, target: 3), speakBreath: true), "same phase, nothing new to say")
        let lift = simple.frame(elapsed: 3, target: 3)
        XCTAssertEqual(simple.cue(from: first, to: lift, speakBreath: true), "expira")
        XCTAssertNil(simple.cue(from: first, to: lift, speakBreath: false))
        let done = simple.frame(elapsed: 12, target: 3)
        XCTAssertEqual(simple.cue(from: lift, to: done, speakBreath: false), "Feito")
        XCTAssertNil(simple.cue(from: done, to: done, speakBreath: false))
    }

    func testCueCatchesUpWithoutABacklog() {
        let before = simple.frame(elapsed: 1, target: 10)
        let after = simple.frame(elapsed: 25, target: 10)
        XCTAssertEqual(simple.cue(from: before, to: after, speakBreath: true), "7. inspira", "only the rep it is on now")
    }

    func testTimedCuesCountEveryFiveAndTheLastThree() {
        let plank = TempoPlan.forExercise(id: "plank", name: "")
        func cue(_ from: Double, _ to: Double) -> String? { plank.cue(from: plank.frame(elapsed: from, target: 30), to: plank.frame(elapsed: to, target: 30), speakBreath: true) }
        XCTAssertNil(cue(1.5, 2.5))
        XCTAssertEqual(cue(4.5, 5.5), "5")
        XCTAssertEqual(cue(26.5, 27.5), "27")
        XCTAssertEqual(cue(29.5, 30.5), "Feito")
    }

    func testTypedWeights() {
        XCTAssertEqual(NumberInput.weight("82,5"), 82.5)
        XCTAssertEqual(NumberInput.weight("82.5"), 82.5)
        XCTAssertEqual(NumberInput.weight(" 80 "), 80)
        XCTAssertEqual(NumberInput.weight("80,"), 80)
        XCTAssertEqual(NumberInput.weight(",5"), 0.5)
        XCTAssertEqual(NumberInput.weight("0"), 0)
        XCTAssertNil(NumberInput.weight(""))
        XCTAssertNil(NumberInput.weight(","))
        XCTAssertNil(NumberInput.weight("1,234.5"))
        XCTAssertNil(NumberInput.weight("abc"))
        XCTAssertNil(NumberInput.weight("-5"))
        XCTAssertNil(NumberInput.weight("nan"))
        XCTAssertNil(NumberInput.weight("1e3"))
        XCTAssertNil(NumberInput.weight("5000"))
    }

    func testTypedReps() {
        XCTAssertEqual(NumberInput.reps("12"), 12)
        XCTAssertEqual(NumberInput.reps(" 8 "), 8)
        XCTAssertEqual(NumberInput.reps("0"), 0)
        XCTAssertNil(NumberInput.reps(""))
        XCTAssertNil(NumberInput.reps("8,5"))
        XCTAssertNil(NumberInput.reps("-1"))
        XCTAssertNil(NumberInput.reps("1000"))
    }
}
