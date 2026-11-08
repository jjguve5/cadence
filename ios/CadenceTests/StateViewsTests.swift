// Phase 2.1b: the shared state system and Desfazer (design v17, «Estados · legenda» and «Interações · confirmar e desfazer»)
import XCTest
@testable import Cadence

final class StateViewsTests: XCTestCase {
    /// Every state has a word and an icon, so it never depends on colour alone; the six main ones are told apart by
    /// their icon and their word
    func testEveryStateHasItsOwnWordAndIcon() {
        for s in DataState.allCases {
            XCTAssertFalse(s.label.isEmpty, "\(s)")
            XCTAssertFalse(s.icon.isEmpty, "\(s)")
        }
        let main: [DataState] = [.confirmed, .imported, .estimated, .suggested, .pending, .noData]
        XCTAssertEqual(main.map(\.label), ["Confirmado", "Importado", "Estimado", "Sugerido", "Pendente", "Sem dados"])
        XCTAssertEqual(Set(main.map(\.icon)).count, main.count, "one icon per main state")
        XCTAssertEqual(Set(DataState.allCases.map(\.label)).count, DataState.allCases.count, "one word per state")
    }

    /// Specialised states keep their family's meaning: a draft or a load drying is pending, never confirmed
    func testSpecialisedStatesKeepTheirFamily() {
        XCTAssertEqual(DataState.draft.family, .pending)
        XCTAssertEqual(DataState.washing.family, .pending)
        XCTAssertEqual(DataState.drying.family, .pending)
        XCTAssertEqual(DataState.done.family, .confirmed)
        XCTAssertEqual(DataState.ignored.family, .off)
    }

    /// Desfazer applies to the last action only and runs once; a new action replaces the old one, whose undo never
    /// runs; an old expiry can't hide the new one
    @MainActor
    func testUndoOnlyTheLastActionAndOnlyOnce() {
        let center = UndoCenter()
        var undone: [String] = []
        center.show("Água +250 ml") { undone.append("water") }
        let first = center.current?.id
        center.show("Duche registado") { undone.append("shower") }
        XCTAssertEqual(center.current?.text, "Duche registado")
        center.expire(first!)
        XCTAssertNotNil(center.current, "an older action's timer doesn't hide the new one")
        center.undo()
        center.undo()
        XCTAssertEqual(undone, ["shower"], "only the last action, once")
        XCTAssertNil(center.current)
    }

    /// Past its time the action can't be undone here any more; dismissing runs nothing
    @MainActor
    func testExpiredOrDismissedActionsDoNotUndo() {
        let center = UndoCenter()
        var undone = 0
        center.show("Comprado") { undone += 1 }
        center.expire(center.current!.id)
        center.undo()
        center.show("Arrumada") { undone += 1 }
        center.dismiss()
        center.undo()
        XCTAssertEqual(undone, 0)
    }

    /// Desfazer lasts 5 s (design: «dura 5 s»), longer only with VoiceOver on
    @MainActor
    func testUndoLastsFiveSeconds() {
        let center = UndoCenter()
        XCTAssertEqual(center.seconds, 5)
        XCTAssertGreaterThan(center.voiceOverSeconds, center.seconds)
    }
}
