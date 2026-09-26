import XCTest

/// "Send diagnostics" (About -> Experiments): reached by its row, it names what
/// goes, sends on the tap and shows the id to pass on; a failed send names its
/// next step and leaves Send in place. The send is stubbed
/// (`-diagnosticsCaseStub`), so the test asserts what the tester sees, not the
/// network.
@MainActor
final class DiagnosticsCaseUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func open(_ stub: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-presentScreen", "about", "-diagnosticsCaseStub", stub]
        app.launch()
        let row = app.buttons["sendDiagnosticsRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the experiment's row is in About")
        row.tap()
        XCTAssertTrue(app.buttons["diagnosticsCaseSendButton"].waitForExistence(timeout: 10))
        return app
    }

    func testASendShowsTheIdToPassOn() {
        let app = open("sent")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " lines")).firstMatch
            .waitForExistence(timeout: 10), "the log's size is named before anything is sent")
        app.buttons["diagnosticsCaseSendButton"].tap()
        let id = app.staticTexts["diagnosticsCaseId"]
        XCTAssertTrue(id.waitForExistence(timeout: 10))
        XCTAssertEqual(id.label, "K7Q2M-9XDRA")
        XCTAssertTrue(app.buttons["diagnosticsCaseCopyButton"].isHittable)
    }

    func testAFailedSendNamesItsNextStepAndCanBeSentAgain() {
        let app = open("offline")
        app.buttons["diagnosticsCaseSendButton"].tap()
        let failure = app.descendants(matching: .any)["diagnosticsCaseFailure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        XCTAssertEqual(failure.label, "No connection – connect and send again.")
        XCTAssertTrue(app.buttons["diagnosticsCaseSendButton"].isEnabled, "Send stays, so the next step can be taken")
    }

    func testTheLogThatGoesCanBeRead() {
        let app = open("sent")
        app.buttons["diagnosticsCaseSeeLog"].tap()
        let text = app.staticTexts["diagnosticsCaseLogText"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertTrue(text.label.contains("Tankbook diagnostics"), "the preview is the text that is sent")
    }
}
