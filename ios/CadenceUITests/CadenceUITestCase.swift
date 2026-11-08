// The UI tests' shared helpers, for the test files each area adds from phase 2.4 on (one file per area, so phases
// don't collide in one file). Same rules as CadenceUITests: test mode (CADENCE_UITEST), synthetic data, no sleeps,
// elements found by identifier, tabs found through their screens (tab buttons have no reliable identifier).
import XCTest

class CadenceUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let app { shot("end-\(name)") }
        app?.terminate()
    }

    enum Tab: String, CaseIterable {
        case today, plan, body, hygiene, life
        var screen: String { "\(rawValue).screen" }
    }

    /// `areasOff` starts with those areas switched off; `portuguese` sets the system language and region to Portugal
    @discardableResult
    func launch(_ scenario: String, minute: Int = 8 * 60, reset: Bool = true, areasOff: [String] = [], portuguese: Bool = false) -> XCUIApplication {
        let a = XCUIApplication()
        a.launchEnvironment = ["CADENCE_UITEST": scenario, "CADENCE_UITEST_MINUTE": String(minute), "CADENCE_UITEST_RESET": reset ? "1" : "0"]
        if !areasOff.isEmpty { a.launchEnvironment["CADENCE_UITEST_AREAS_OFF"] = areasOff.joined(separator: ",") }
        if portuguese { a.launchArguments += ["-AppleLanguages", "(pt-PT)", "-AppleLocale", "pt_PT"] }
        a.launch()
        XCTAssertTrue(a.descendants(matching: .any)[Tab.today.screen].firstMatch.waitForExistence(timeout: 20), "Cadence didn't reach the Today tab")
        app = a
        return a
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Opens a tab by trying the buttons until its screen shows
    func open(_ tab: Tab, file: StaticString = #filePath, line: UInt = #line) {
        if el(tab.screen).exists { return }
        let buttons = app.tabBars.buttons
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 5), "no tab bar", file: file, line: line)
        for i in 0..<buttons.count {
            buttons.element(boundBy: i).tap()
            if el(tab.screen).waitForExistence(timeout: 3) { return }
        }
        XCTFail("no tab in the bar opens \(tab.screen)", file: file, line: line)
    }

    func waitGone(_ e: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "still there: \(e)", file: file, line: line)
    }

    /// Scrolls until the element can be tapped
    @discardableResult
    func reveal(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = el(id)
        _ = e.waitForExistence(timeout: 3)
        var tries = 0
        while !(e.exists && e.isHittable) && tries < 10 { app.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(e.exists && e.isHittable, "\(id) never became tappable", file: file, line: line)
        return e
    }

    func shot(_ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }
}

extension XCUIElement {
    /// Clears a text field and types into it
    func replaceText(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
