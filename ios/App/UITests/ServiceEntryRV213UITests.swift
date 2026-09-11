import XCTest

/// RV.213 - the create door's lifetime editor and the offer it raises at the
/// FIRST save (docs/JOURNEYS.md J7/J7d). The edit door got the editor from
/// PJ.22; this is the create half. EN and RU because the km / months row is
/// where Russian runs longest on the narrower create card.
@MainActor
extension ServiceEntryUITests {

    private func launchWithLifetime(russian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-homeResetDatabase", "-seedServiceEntryLifetime",
                    "-presentScreen", "serviceEntry"]
        if russian {
            args += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// The seed states an oil lifetime and a blank odometer: the save must
    /// SUCCEED (RV.212 - neither door refuses a km lifetime without an
    /// odometer) and raise the offer at the first save (RV.213).
    private func assertTheOfferAppears(_ app: XCUIApplication) {
        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isEnabled,
                      "a km lifetime with no odometer must still save (RV.212)")
        save.tap()
        XCTAssertTrue(app.staticTexts["serviceReminderOfferHeadline"]
            .waitForExistence(timeout: 10),
            "a stated lifetime must raise the offer at the first save")
        XCTAssertTrue(app.buttons["serviceReminderOfferCreateButton"].exists,
                      "the offer proposes; it never auto-creates")
    }

    func testCreatingAServiceWithALifetimeRaisesTheOfferAtFirstSave() {
        let app = launchWithLifetime()
        XCTAssertTrue(app.textFields["editEntryServiceItemLifetimeKm"].firstMatch
            .waitForExistence(timeout: 10),
            "the create card must render the lifetime editor")
        XCTAssertTrue(app.textFields["editEntryServiceItemLifetimeMonths"].firstMatch.exists,
                      "the create card must render both lifetime halves")
        assertTheOfferAppears(app)
    }

    func testCreatingAServiceWithALifetimeRaisesTheOfferAtFirstSaveInRussian() {
        let app = launchWithLifetime(russian: true)
        XCTAssertTrue(app.textFields["editEntryServiceItemLifetimeKm"].firstMatch
            .waitForExistence(timeout: 10),
            "the create card must render the lifetime editor in RU")
        assertTheOfferAppears(app)
    }

    /// RV.224: the scanned invoice's date carries the "· invoice" provenance
    /// caption. The caption CLEARING on a manual edit is asserted at L1 (the
    /// graphical picker cannot be driven reliably by XCUITest); this guards the
    /// rendered caption and the identifier the L4 record names.
    func testScannedInvoiceShowsTheDateProvenanceCaption() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedServiceEntryScan",
                               "-presentScreen", "serviceEntry"]
        app.launch()
        XCTAssertTrue(app.staticTexts["serviceEntryDateProvenanceCaption"]
            .waitForExistence(timeout: 10),
            "a scanned invoice's date must carry the '· invoice' caption")
    }
}
