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

    /// The bottom edge of the About content region: the owned tab bar's top on a
    /// pushed screen. Anything below it is under the bar and cannot be seen
    /// without scrolling - `isHittable` lies about this (RV.84).
    func visibleContentBottom(_ app: XCUIApplication) -> CGFloat {
        let window = app.windows.firstMatch.frame
        let tabbar = app.otherElements["tabbar"]
        return tabbar.exists ? tabbar.frame.minY : window.maxY
    }

    /// RV.84's lesson, applied: an element that EXISTS can still be 86% clipped
    /// and report `isHittable == true`. Visibility is a frame question, and the
    /// window's frame is not the visible region - About ends where the owned
    /// tab bar begins.
    func assertFullyVisibleWithoutScrolling(_ element: XCUIElement, in app: XCUIApplication,
                                            file: StaticString = #filePath,
                                            line: UInt = #line) {
        let frame = element.frame
        let bottom = visibleContentBottom(app)
        XCTAssertGreaterThanOrEqual(frame.minY, 0,
                                    "confirmation must start inside the visible region", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, bottom,
                                 "confirmation must sit above the fold - it ended at \(frame.maxY) "
                                 + "but visible content ends at \(bottom). The old line below Send was "
                                 + "under this edge and read as nothing happening.",
                                 file: file, line: line)
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

    // MARK: - RV.160 a send must be acknowledged where the user can see it

    /// The reported defect: after feedback was sent there was no confirmation
    /// that it was sent. One existed but rendered as a muted caption BELOW the
    /// Send button at the bottom of a tall composer inside About's scroll view -
    /// below the fold at the moment of the tap, and under the keyboard when one
    /// was up - while the only loud change was the form emptying. A
    /// confirmation the user cannot see is the same failure as no confirmation.
    /// The fix collapses the composer into a confirmation panel where the
    /// form's top was: visible at ANY scroll position, because the About content
    /// above the composer never moves and the collapse shortens the scroll.
    /// These tests assert the ROW'S claim - the confirmation must be findable
    /// without scrolling (a frame assertion, never `isHittable`, RV.84) - and
    /// that each of the four outcomes is its own distinct element keyed by its
    /// localization key, the queued ones never reading as errors
    /// (docs/ERRORS.md -> About & feedback).

    /// The headline. A `.sent` outcome (the transport seam
    /// `-feedbackTransportSuccess` answers 202) must surface a confirmation the
    /// test can see WITHOUT scrolling: on the unfixed code this row's
    /// "confirmation" sat below the Send button, under the fold, and existed
    /// without being visible.
    func testRV160SentConfirmationIsVisibleWithoutScrolling() {
        let app = launch(["-presentScreen", "about",
                          "-feedbackConsentOn", "-feedbackTransportSuccess",
                          "-feedbackAutoSend"])

        let confirmation = app.staticTexts["feedbackSent"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10),
                      "the sent confirmation must render after a send")
        // The element EXISTS on the unfixed code too (it passed that check for
        // months); the assertion is the frame - visible bounds, not the window.
        assertFullyVisibleWithoutScrolling(confirmation, in: app)
    }

    /// Offline is the outcome reachable with the network off (the launch-args
    /// axis docs/ERRORS.md names). The queued copy is reassurance, never an
    /// error, and it too must be visible without scrolling.
    func testRV160QueuedOfflineConfirmationIsVisibleWithoutScrolling() {
        let app = launch(["-presentScreen", "about",
                          "-feedbackConsentOn", "-feedbackTransportOffline",
                          "-feedbackAutoSend"])

        let confirmation = app.staticTexts["feedbackQueuedOffline"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        assertFullyVisibleWithoutScrolling(confirmation, in: app)
        XCTAssertEqual(confirmation.label, "Saved – sends automatically when you're online.",
                       "the queued copy must read as saved, never as failed (docs/ERRORS.md)")
    }

    /// All four outcomes are distinct states with distinct copy, and a queued
    /// case is not the sent case. Driven through the real outbox by the same
    /// `-feedbackAutoSend` seam the offline/429 tests already use - each launch
    /// forces one wire outcome and the composer must render THAT outcome's key
    /// and none of the others.
    func testRV160EachOutcomeShowsItsOwnConfirmation() {
        let scenarios: [(arguments: [String], expected: String)] = [
            (["-feedbackTransportSuccess"], "feedbackSent"),
            (["-feedbackTransportOffline"], "feedbackQueuedOffline"),
            (["-feedbackRateLimit"], "feedbackRateLimited"),
            (["-feedbackTransportServerError"], "feedbackQueuedRetry")
        ]
        for scenario in scenarios {
            let app = launch(["-presentScreen", "about",
                              "-feedbackConsentOn"] + scenario.arguments
                             + ["-feedbackAutoSend"])
            let expected = app.staticTexts[scenario.expected]
            XCTAssertTrue(expected.waitForExistence(timeout: 10),
                          "the \(scenario.expected) outcome must render for \(scenario.arguments)")
            for other in Self.allOutcomeIdentifiers where other != scenario.expected {
                XCTAssertFalse(app.staticTexts[other].exists,
                               "\(scenario.expected) must not also render \(other)")
            }
        }
    }

    private static let allOutcomeIdentifiers = [
        "feedbackSent",
        "feedbackQueuedOffline",
        "feedbackRateLimited",
        "feedbackQueuedRetry"
    ]

    // MARK: - RV.159 the two consents must not read as one object

    /// The headline (docs/DEFECT-PATTERNS.md -> "Comprehension"): both opt-ins
    /// render and both carry distinct accessibility identifiers, yet a user
    /// could not tell them apart - so they enabled "Attach diagnostics" and
    /// believed they had satisfied the send gate. The fix makes the GATE a
    /// different kind of object from the optional attachment: the consent sits
    /// in its own section under the "Before you send" eyebrow (the SectionEyebrow
    /// idiom), the diagnostics opt-in does not. This asserts THAT property -
    /// the header exists, sits above the consent switch, and sits BELOW the
    /// diagnostics card - never merely that both toggles exist (they did before
    /// the fix). The mutation (remove the header, restore the consent's bare
    /// modifiers) makes `feedbackConsentHeader` vanish and this test go red.
    func testRV159TheGatingConsentIsAHeadedSectionAndDiagnosticsIsNot() {
        let app = launch(["-presentScreen", "about",
                          "-feedbackConsentReset", "-diagnosticsConsentReset"])

        let header = app.staticTexts["feedbackConsentHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10),
                      "the gating consent must sit under its own 'Before you send' heading")
        let consent = app.switches["feedbackConsentToggle"]
        XCTAssertTrue(consent.exists, "the gating consent toggle renders")
        XCTAssertLessThan(header.frame.minY, consent.frame.minY,
                          "the heading must sit directly above the consent it gates")
        XCTAssertLessThan(header.frame.maxY, consent.frame.minY,
                          "the heading must end above the consent toggle, not overlap it")

        let diagnostics = app.switches["diagnosticsConsentToggle"]
        XCTAssertTrue(diagnostics.exists, "the diagnostics opt-in renders")
        XCTAssertLessThan(diagnostics.frame.minY, header.frame.minY,
                          "the diagnostics opt-in is a separate card ABOVE the composer, "
                              + "not a member of the 'Before you send' section - the header must "
                              + "not be heading both controls")
    }

    /// The dead end the row was filed for: a user writes feedback, enables the
    /// WRONG toggle ("Attach diagnostics" - which shares the "attach" language
    /// and, before RV.159, the exact look of the consent), presses Send, and is
    /// refused. The refusal must name the improve-scanning switch IN THE WORDS
    /// ON THAT SWITCH - diagnostics consent is a different property and must
    /// not satisfy `FeedbackModel.send()`'s gate (docs/ERRORS.md).
    func testRV159SendingWithOnlyDiagnosticsOnIsRefusedNamingTheConsentSwitch() {
        let app = launch(["-presentScreen", "about",
                          "-feedbackConsentReset", "-diagnosticsConsentOn",
                          "-feedbackAutoSend"])

        let diagnostics = app.switches["diagnosticsConsentToggle"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10))
        XCTAssertEqual(diagnostics.value as? String, "1",
                       "the scenario needs 'Attach diagnostics' ON")
        let consent = app.switches["feedbackConsentToggle"]
        XCTAssertEqual(consent.value as? String, "0",
                       "the improve-scanning consent must still be OFF - it is a "
                           + "separate property from the diagnostics opt-in")

        let refusal = app.staticTexts["feedbackConsentRequired"]
        XCTAssertTrue(refusal.waitForExistence(timeout: 10),
                      "Send with only diagnostics on must be refused")
        let switchWords = consent.label
        XCTAssertFalse(switchWords.isEmpty,
                       "the consent switch must expose the words on it")
        XCTAssertTrue(refusal.label.contains(switchWords),
                      "the refusal must name the toggle it refers to in the words on "
                          + "that toggle - got '\(refusal.label)' for switch words "
                          + "'\(switchWords)'")
    }

    /// The mirror: with ONLY the improve-scanning consent on, Send succeeds
    /// (the RV.160 collapse shows `feedbackSent`), and the diagnostics opt-in
    /// rides nothing - it is OFF and its preview is unreachable. The diagnostics
    /// attachment is a separate path entirely (docs/LOGGING.md §5, the share
    /// sheet), never a passenger on `POST /feedback`.
    func testRV159SendingWithOnlyTheConsentOnSucceedsAndNoDiagnosticsRideAlong() {
        let app = launch(["-presentScreen", "about",
                          "-feedbackConsentOn", "-diagnosticsConsentReset",
                          "-feedbackTransportSuccess", "-feedbackAutoSend"])

        let sent = app.staticTexts["feedbackSent"]
        XCTAssertTrue(sent.waitForExistence(timeout: 10),
                      "with the improve-scanning consent ON, Send must succeed")
        let diagnostics = app.switches["diagnosticsConsentToggle"]
        XCTAssertTrue(diagnostics.exists)
        XCTAssertEqual(diagnostics.value as? String, "0",
                       "the diagnostics opt-in must not ride the send - it was never on")
        XCTAssertFalse(app.buttons["diagnosticsPreviewButton"].exists,
                       "with the diagnostics opt-in off its preview must be unreachable")
    }

    /// L4, EN at the largest text size: the headed consent block - a two-line
    /// toggle label beside the switch is exactly where a longer type scale
    /// clips - must render with its heading above the switch and the full label
    /// intact.
    func testRV159ConsentBlockRendersAtXLInEnglish() {
        let app = launch(["-presentScreen", "about",
                          "-feedbackConsentReset", "-diagnosticsConsentOn",
                          "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryXL"])
        assertRV159ConsentBlockSurvivesXL(app,
                                          consentLabel: "Send this case to help improve scanning")
    }

    /// L4, RU at the largest text size: Russian runs 20-30% longer, so the
    /// switch label ("Отправить этот случай для улучшения распознавания") is
    /// the overflow case the EN pass cannot see.
    func testRV159ConsentBlockRendersAtXLInRussian() {
        let app = launch(["-presentScreen", "about",
                          "-feedbackConsentReset", "-diagnosticsConsentOn",
                          "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryXL",
                          "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
        assertRV159ConsentBlockSurvivesXL(app,
                                          consentLabel: "Отправить этот случай для улучшения распознавания")

        // Restore the app's persisted language: `-AppleLanguages` writes to
        // UserDefaults, which survives launches, so a suite running after this
        // RU launch must not inherit Russian (P6.13 run, 2026-08-31).
        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }

    private func assertRV159ConsentBlockSurvivesXL(_ app: XCUIApplication,
                                                   consentLabel: String) {
        let header = app.staticTexts["feedbackConsentHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10),
                      "the 'Before you send' heading must render at the largest text size")
        let consent = app.switches["feedbackConsentToggle"]
        XCTAssertTrue(consent.waitForExistence(timeout: 10),
                      "the consent switch must render at the largest text size")
        XCTAssertLessThan(header.frame.maxY, consent.frame.minY,
                          "the heading must stay above the consent at the largest text size")
        XCTAssertTrue(consent.label.contains(consentLabel),
                      "the switch label must be intact at the largest text size, "
                          + "got '\(consent.label)'")
        let diagnostics = app.switches["diagnosticsConsentToggle"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10),
                      "the diagnostics opt-in must render beside it at the largest text size")
        // A two-line label beside a switch clips off the window's edge when the
        // row does not yield; assert the switch stays inside the window.
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(consent.frame.minX, window.minX - 1,
                                    "the consent row must not clip off the left at XL")
        XCTAssertLessThanOrEqual(consent.frame.maxX, window.maxX + 1,
                                 "the consent row must not clip off the right at XL")
    }
}
