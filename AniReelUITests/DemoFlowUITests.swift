import XCTest

/// Walks the main flow for the CI demo recording (codemagic.yaml): onboarding → feed → camera
/// (demo frames in the Simulator) → third style → a 4-second clip → result → Done.
/// Styles run Core ML models, so the record button only enables once the model produces frames;
/// the second style (Q 版) ships no model and is skipped. With no models bundled this test fails
/// at the first wait, which is the intended signal.
/// Every lookup goes through accessibility identifiers, so it runs in any locale.
final class DemoFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMainFlowDemo() {
        let app = XCUIApplication()
        app.launch()

        let skip = app.buttons["onboarding.skip"]
        if skip.waitForExistence(timeout: 8) {
            skip.tap()
        }

        let shoot = app.buttons["shell.camera"]
        XCTAssertTrue(shoot.waitForExistence(timeout: 15), "Tab shell camera button never appeared")
        pause(1.5)
        app.swipeUp()
        pause(2)
        shoot.tap()

        let demoBadge = app.descendants(matching: .any).matching(identifier: "camera.demoBadge").firstMatch
        XCTAssertTrue(demoBadge.waitForExistence(timeout: 20), "Camera with demo frames never appeared")
        let record = app.buttons["camera.record"]
        // First model load compiles for the Simulator and runs on its CPU: allow plenty of time.
        waitUntilEnabled(record, timeout: 120)
        pause(3)

        let thirdStyle = app.buttons.matching(identifier: "camera.styleTab").element(boundBy: 2)
        XCTAssertTrue(thirdStyle.waitForExistence(timeout: 10), "Third style tab missing")
        thirdStyle.tap()
        waitUntilEnabled(record, timeout: 120)
        pause(3)

        record.tap()
        pause(4)
        record.tap()

        // Saving asks for add-only Photos access unless CI granted it ahead of time.
        let done = app.buttons["result.done"]
        let deadline = Date().addingTimeInterval(25)
        while !done.exists, Date() < deadline {
            allowSystemAlertIfShown()
            _ = done.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(done.exists, "Result screen never appeared")
        pause(2.5)
        done.tap()

        XCTAssertTrue(shoot.waitForExistence(timeout: 10), "Did not return to the tab shell")
        pause(2)
    }

    /// Taps the confirming button of a system permission alert; it is the last button in every locale.
    @MainActor
    private func allowSystemAlertIfShown() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.exists else { return }
        let buttons = alert.buttons
        if buttons.count > 0 {
            buttons.element(boundBy: buttons.count - 1).tap()
        }
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isEnabled == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: timeout), .completed, "\(element) never became enabled")
    }

    /// Holds still so the recording shows each step.
    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "pause")], timeout: seconds)
    }
}
