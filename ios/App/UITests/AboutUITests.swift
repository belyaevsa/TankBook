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
        // `-feedbackQueueReset`: the queue file outlives `-homeResetDatabase`, so
        // a queued row from an earlier queued-offline test would otherwise ride
        // this launch - and RV.127's foreground flush posts it on unseeded runs.
        app.launchArguments = ["-homeResetDatabase", "-feedbackQueueReset"] + arguments
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

    // MARK: - OB.4 Attach diagnostics (docs/LOGGING.md §5)

    /// The opt-in is OFF on first open (the key is removed, reproducing a fresh
    /// install - so a default-on mutation fails THIS test, not a later one) and
    /// the preview is unreachable until the toggle is turned on. The toggle
    /// being on is what reveals the preview affordance; nothing else does.
    func testDiagnosticsConsentIsOffOnFirstOpenAndPreviewUnreachableUntilOn() {
        let app = launch(["-presentScreen", "about", "-diagnosticsConsentReset"])

        let toggle = app.switches["diagnosticsConsentToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                      "the Attach diagnostics toggle renders on About")
        // The diagnostics card sits below the (tall) feedback composer, so it
        // can be off-screen at launch; scroll it into view before interacting.
        scrollUntilHittable(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0",
                       "the opt-in must default to OFF on first open (docs/LOGGING.md §5)")
        XCTAssertFalse(app.buttons["diagnosticsPreviewButton"].exists,
                       "the preview must be unreachable while the opt-in is off")

        // Tap the switch capsule itself (the element's centre can sit over the
        // label text when the row is wide), then assert the value actually
        // flipped and the preview affordance appeared.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1",
                       "tapping the opt-in toggle must switch it on")
        XCTAssertTrue(app.buttons["diagnosticsPreviewButton"].waitForExistence(timeout: 5),
                      "turning the opt-in on must reveal the preview affordance")
    }

    /// Scrolls the About scroll view until `element` sits comfortably above the
    /// owned tab bar (docs/DESIGN.md: pushed screens end above it). `isHittable`
    /// alone is not enough - an element whose lower half is UNDER the bar is
    /// reported hittable, but a tap on its centre lands on the bar and no-ops.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while element.frame.midY > Self.safeInteractionZone || !element.isHittable, attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
    }

    /// Taps are only trustworthy above this line: anything lower can be under
    /// the app's owned tab bar (~760 pt on this device), which swallows taps.
    private static let safeInteractionZone: CGFloat = 700

    /// The preview opens from About and shows the REAL bundle over REAL seeded
    /// data - the row-count markers prove the preview reflects the seeded
    /// database (a preview over an empty database would prove nothing) - and
    /// contains none of the seeded station/note/amount strings. This is the
    /// user-facing half of the privacy promise: what the user reads is what
    /// would be sent, and it carries no domain value.
    func testDiagnosticsPreviewOpensFromAboutAndShowsNoSeededValues() {
        let app = launch(["-presentScreen", "about",
                          "-diagnosticsConsentOn", "-seedDiagnosticsData"])

        let previewButton = app.buttons["diagnosticsPreviewButton"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 10),
                      "the preview affordance renders once the opt-in is on")
        previewButton.tap()

        let preview = app.staticTexts["diagnosticsPreviewText"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15),
                      "the preview sheet opens with the diagnostics text")
        XCTAssertTrue(app.buttons["diagnosticsShareButton"].exists,
                      "the share affordance sits on the preview")

        let text = preview.label
        // It IS the full bundle, not a summary: the header, a generated-at
        // stamp and the seeded row counts all appear. (Mutation 4 renders a
        // summary instead of the full text; a summary carries none of these.)
        XCTAssertTrue(text.contains("Tankbook diagnostics"),
                      "preview must show the real bundle header")
        XCTAssertTrue(text.contains("generatedAt="),
                      "preview must show the bundle's metadata lines")
        XCTAssertTrue(text.contains("rowCount.fillUp=1"),
                      "preview must reflect the seeded database (fillUp=1)")
        XCTAssertTrue(text.contains("rowCount.vehicle=1"),
                      "preview must reflect the seeded database (vehicle=1)")
        XCTAssertTrue(text.contains("rowCount.station=1"),
                      "preview must reflect the seeded database (station=1)")
        XCTAssertTrue(text.contains("dirtyCount="),
                      "preview must carry the sync section")

        // The sweep over the whole previewed text - the strings the seed wrote
        // into the database must appear nowhere (hard rule 12).
        XCTAssertFalse(text.contains("Zvezda-Lubricants-77"),
                       "the seeded station name must not appear in the preview")
        XCTAssertFalse(text.contains("timing-belt-service-ob4"),
                       "the seeded note must not appear in the preview")
        XCTAssertFalse(text.contains("64.20"),
                       "the seeded amount must not appear in the preview")
    }
}
