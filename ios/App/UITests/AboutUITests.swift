import XCTest

/// PJ.20 - the About & feedback surface (docs/ERRORS.md -> About & feedback).
/// The feedback composer renders on About, and the offline queue names its next
/// step ("sends automatically when you're online"). The consent's default-off
/// and the queue's consent gate are pinned at L1 (`FeedbackTests`); this suite
/// is the rendered half.
@MainActor
final class AboutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    /// The feedback row renders: category chips, the text editor, the consent
    /// toggle (default off - the value itself is an L1 assertion), the
    /// device-model toggle, and the send button.
    func testFeedbackComposerRenders() {
        let app = launch(["-presentScreen", "about"])

        XCTAssertTrue(app.textViews["feedbackTextEditor"].waitForExistence(timeout: 10),
                      "the feedback text editor renders")
        XCTAssertTrue(app.buttons["feedbackCategory-feature"].exists)
        XCTAssertTrue(app.buttons["feedbackCategory-problem"].exists)
        XCTAssertTrue(app.buttons["feedbackCategory-other"].exists)
        XCTAssertTrue(app.switches["feedbackConsentToggle"].exists,
                      "the consent toggle renders (its default-off is an L1 pin)")
        XCTAssertTrue(app.switches["feedbackDeviceModelToggle"].exists,
                      "the device-model toggle renders")
        XCTAssertTrue(app.buttons["feedbackSendButton"].exists,
                      "the send-feedback button renders")
    }

    /// The queued-offline state: a case submitted with consent while offline is
    /// queued and the copy names the next step - "sends automatically when
    /// you're online" (docs/ERRORS.md). Never an error (hard rule 1).
    func testOfflineQueueNamesItsNextStep() {
        let app = launch(["-presentScreen", "about",
                          "-feedbackConsentOn", "-feedbackTransportOffline",
                          "-feedbackAutoSend"])

        let offline = app.staticTexts["feedbackQueuedOffline"]
        XCTAssertTrue(offline.waitForExistence(timeout: 10),
                      "the offline queued copy renders")
        XCTAssertEqual(offline.label, "Saved – sends automatically when you're online.",
                       "the copy names the next step verbatim")
    }
}
