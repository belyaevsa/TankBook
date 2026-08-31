import XCTest

/// P1.6 Edit entry UI tests. The seed is the golden D1 history
/// (`-seedHomeEditHistory`): eight full fills over ~15 weeks, so the headline
/// is the documented 6.9 and an edit to the newest fill's odometer moves it to
/// a known value. Assertions cover the three behaviours that carry the task:
/// the delta toast (old -> new, and its absence on a no-op save), the delete
/// confirmation (the one place red lives), and the amber cross-check/timeline
/// mechanics that keep save-anyway working with the flag written.
@MainActor
final class EditEntryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeEditHistory"]
        app.launch()
        return app
    }

    // MARK: - PJ.2 the receipt card after a scanned save

    /// The scanned fill-up from `-seedEditEntry` is shaped exactly as a PJ.2
    /// scanned save writes it (one receipt Attachment, scan provenance, the
    /// extraction record) - and the edit screen must show its receipt card.
    func testReceiptCardRendersAfterScannedSave() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntry", "-presentScreen", "editEntry"]
        app.launch()

        // The receipt photo chip is the strip's left tile (inline thumbnail,
        // zero blob fetches)...
        let chip = app.descendants(matching: .any)
            .matching(identifier: "attachmentPhotoChip").firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "the scanned fill-up must render its receipt photo chip")
        // ...and the strip's caption is the "Receipt photo" label.
        XCTAssertTrue(app.staticTexts["Receipt photo"].waitForExistence(timeout: 5),
                      "the receipt card caption must render")
    }

    /// The newest fill (1 day ago, 119 486 km) is the top log row - the edit
    /// target for every test.
    private func openNewestFill(_ app: XCUIApplication) {
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
    }

    /// Replaces a text field's contents without the text-selection edit menu
    /// (unreliable on the iOS 26 simulator): tap the field's right edge so the
    /// cursor lands at the end of a trailing-aligned value, delete the current
    /// text one keystroke at a time, then type the replacement. When the
    /// keyboard is up it can cover the lower cards, so it is dropped first
    /// (the edit screen's scroll view dismisses the keyboard on scroll).
    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.swipeDown()
        }
        // Bring the field into the upper half: a trailing-aligned field too
        // close to the bottom cannot summon the number pad, and the tap then
        // leaves it without keyboard focus.
        var attempts = 0
        while field.frame.minY > 300 && attempts < 8 {
            app.scrollViews.firstMatch.swipeUp()
            attempts += 1
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                  count: current.count))
        }
        field.typeText(text)
    }

    // MARK: - PJ.48 add a receipt to a typed entry

    /// The corpus fixtures live on the host; the simulator shares the host
    /// filesystem, so the app under test reads a fixture by its host path -
    /// passed through `-attachReceiptFixtureImage` - and OCRs it for real.
    private var fixturesRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EditEntryUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures")
            .path
    }

    /// The "Add receipt" affordance exists only when there is no attachment:
    /// a typed entry shows it, a scanned entry (already carrying its receipt)
    /// does not.
    func testAddReceiptShowsOnlyWithoutAnAttachment() {
        let typed = XCUIApplication()
        typed.launchArguments = ["-homeResetDatabase", "-seedEditEntryTyped",
                                 "-presentScreen", "editEntry"]
        typed.launch()
        XCTAssertTrue(typed.buttons["editAddReceiptButton"].waitForExistence(timeout: 10),
                      "a typed entry with no receipt must offer 'Add receipt'")

        let scanned = XCUIApplication()
        scanned.launchArguments = ["-homeResetDatabase", "-seedEditEntry",
                                   "-presentScreen", "editEntry"]
        scanned.launch()
        let chip = scanned.descendants(matching: .any)
            .matching(identifier: "attachmentPhotoChip").firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "a scanned entry must render its receipt chip")
        XCTAssertFalse(scanned.buttons["editAddReceiptButton"].exists,
                       "'Add receipt' must not show when a receipt already exists")
    }

    /// Attaching a receipt to a typed entry writes the photo and links it: the
    /// receipt card renders the chip and, after Save, the Log shows the
    /// paperclip. The typed values are never touched (the merge is blank-only;
    /// the byte-identical guarantee is pinned at L1).
    func testAttachReceiptWritesThePhotoAndTheLogShowsAPaperclip() {
        let fixture = fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntryTyped",
                               "-presentScreen", "editEntry",
                               "-attachReceiptFixtureImage", fixture]
        app.launch()

        let add = app.buttons["editAddReceiptButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        // The "Photos" door resolves the fixture directly (the out-of-process
        // picker cannot be driven), so this is the real attach path.
        let photos = app.buttons["Photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        photos.tap()

        // Wait for the OCR to settle - `editAttachReady` flips on only when the
        // reading finished and the attach is ready to save.
        let ready = app.otherElements["editAttachReady"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15),
                      "the attach must settle into the ready state after OCR")

        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        let paperclip = app.descendants(matching: .any)
            .matching(identifier: "logEntryAttachment").firstMatch
        XCTAssertTrue(paperclip.waitForExistence(timeout: 5),
                      "the Log must show the paperclip for the entry that gained a receipt")
    }

    // MARK: - The delta toast

    func testToastShowsOldToNewAfterEditThatMovesConsumption() {
        let app = launch()
        openNewestFill(app)

        // The newest fill's odometer 119 486 -> 120 486 re-bases the last
        // segment: headline 6.9 -> 5.6, both from the engine.
        let odometer = app.textFields["manualFillUpOdometerField"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 5))
        replaceText(in: odometer, with: "120486", app: app)

        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        let toast = app.staticTexts["Consumption updated: 6.9 → 5.6 L/100km"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5),
                      "delta toast did not appear after an edit that moved consumption")
        XCTAssertTrue(app.buttons["deltaToast"].exists)
    }

    func testNoToastAfterNoOpEdit() {
        let app = launch()
        openNewestFill(app)

        // Save without changing anything: the recompute result is identical, so
        // no toast - claiming an update that did not happen is worse than none.
        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["deltaToast"].waitForExistence(timeout: 2),
                       "no-op edit must not show a delta toast")
    }

    // MARK: - Delete confirmation

    func testDeleteShowsConfirmationAndCancelLeavesEntryIntact() {
        let app = launch()
        openNewestFill(app)

        app.buttons["editEntryDeleteButton"].tap()

        // The system confirmation appears - the one place red lives.
        let alert = app.alerts["Delete this entry?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["Delete"].exists)

        // Cancel leaves the entry intact: still on the edit screen with all its
        // fields, and back on Home the log row is still there.
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "logEntryButton").count, 8,
                       "cancelling delete must leave all eight entries in the log")
    }

    // MARK: - Amber mechanics keep save-anyway working, flag kept

    func testSaveAnywayKeepsConflictFlagAfterCrossCheckAndTimelineWarnings() {
        let app = launch()
        openNewestFill(app)

        // Break the cross-check: 42.30 L x 1.679 = 71.02, so a 60.00 total is a
        // mismatch. The amber line refuses to lock.
        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        replaceText(in: total, with: "60.00", app: app)
        XCTAssertTrue(app.staticTexts["manualFillUpCrossCheckMismatch"].waitForExistence(timeout: 5))

        // Break the timeline: 100 000 km is below the previous fill's 118 843.
        let odometer = app.textFields["manualFillUpOdometerField"]
        replaceText(in: odometer, with: "100000", app: app)
        XCTAssertTrue(app.staticTexts["manualFillUpOdometerWarning"].waitForExistence(timeout: 5))

        // Save-anyway still works - the bar is not disabled by either warning -
        // and the flag is KEPT: Home shows the conflict badge and the excluded
        // count.
        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        let badge = app.buttons["conflictBadgeButton"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5),
                      "save-anyway must keep the conflict flag visible on Home")
        XCTAssertTrue(app.staticTexts["1 entry excluded"].exists)
    }

    // MARK: - P5.2b the manual rate is editable "again afterwards" (rule 13)

    /// A rate the user set before loads back into the edit screen's conversion
    /// card as Manual and stays changeable - the clause the task exists for: a
    /// rate settable only once, at Confirm, is the bug hard rule 13 names.
    func testEditCanChangeAManualRateThatWasAlreadySet() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntryManualRate",
                               "-presentScreen", "editEntry"]
        app.launch()

        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10))
        let card = app.otherElements["manualFillUpConversionCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5),
                      "a foreign entry on Edit must render the conversion card")
        XCTAssertTrue(app.staticTexts["manualFillUpConvertedValue"].exists)
        let rateLine = app.staticTexts["manualFillUpRateLine"]
        XCTAssertTrue(rateLine.exists)
        XCTAssertTrue(rateLine.label.contains("Manual"),
                      "a manually-rated entry must render its own source, got '\(rateLine.label)'")

        // The stored manual rate loads into the editable field - 289.50 PLN at
        // 4.0 -> 72.38 EUR.
        let field = app.textFields["manualFillUpManualRateField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "4.0000",
                       "the stored manual rate must load into the field, got '\(field.value ?? "")'")

        // Change it: 289.50 / 4.5 = 64.33, and the card updates in place.
        replaceText(in: field, with: "4.5", app: app)
        let value = app.staticTexts["manualFillUpConvertedValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertTrue(value.label.contains("64.33"),
                      "changing the rate must re-convert, got '\(value.label)'")

        // Save and reopen: the new manual rate persists.
        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))

        openNewestFill(app)
        let reopened = app.textFields["manualFillUpManualRateField"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.value as? String, "4.5000",
                       "the changed manual rate must persist, got '\(reopened.value ?? "")'")
    }

    // MARK: - PR.14 the "Changed by sync" row is real data

    private func textContaining(_ app: XCUIApplication, _ substring: String) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
    }

    /// The row reads the REAL overwrite log: the seeded device is "iPad", so the
    /// row must name "iPad" - a hardcoded "iPhone" (or any other constant) would
    /// fail this. "Restore my version" then round-trips the user's odometer back
    /// into the field and the row disappears.
    func testChangedBySyncRowReadsTheRealOverwriteLogAndRestores() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntrySyncOverwritten",
                               "-presentScreen", "editEntry"]
        app.launch()

        let restore = app.buttons["editSyncRestoreButton"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10),
                      "a seeded overwrite must render the row's Restore action")
        XCTAssertTrue(textContaining(app, "iPad").exists,
                      "the row names the device from the log, never a constant")
        XCTAssertTrue(textContaining(app, "Changed by sync").exists,
                      "the row carries the 'Changed by sync' sentence")

        // The synced version shows 119 486; restore returns the user's 118 486.
        restore.tap()

        let odometer = app.textFields["manualFillUpOdometerField"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 5))
        let restored = (odometer.value as? String) ?? ""
        XCTAssertTrue(restored.contains("118"),
                      "restore returns the user's odometer (118 486), got '\(restored)'")
        XCTAssertFalse(restored.contains("119"),
                       "the synced odometer (119 486) is replaced, got '\(restored)'")
        XCTAssertFalse(app.buttons["editSyncRestoreButton"].exists,
                       "the row disappears once the user has chosen")
    }

    /// The RU sentence renders the device name and the sync verb - the row must
    /// localise like every other surface, never an English-in-RU drift.
    func testChangedBySyncRowRendersInRussian() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntrySyncOverwritten",
                               "-presentScreen", "editEntry",
                               "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        XCTAssertTrue(app.buttons["Восстановить мою версию"].waitForExistence(timeout: 10),
                      "the RU restore action renders")
        XCTAssertTrue(textContaining(app, "Изменено при синхронизации").exists,
                      "the RU sentence renders")
        XCTAssertTrue(textContaining(app, "iPad").exists,
                      "the device name renders in RU too")
    }

    // MARK: - PR.14 the post-batch toast names the real flagged count

    /// The toast's N comes from `SyncOutcome.flaggedEntries`: the sync pulls an
    /// out-of-order fill, `revalidateTimeline` flags both entries of the
    /// reversed pair, so the toast must say "2 entries" - a hardcoded constant
    /// (the old fixture's "2", or any other number) fails when it disagrees.
    /// `-freezeSyncState` keeps the automatic cycles from racing this, so the
    /// single "Sync now" is the one batch that flags.
    func testSyncToastShowsTheFlaggedBatchCount() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-freezeSyncState",
                               "-seedSettingsSynced", "-seedSyncFlaggedBatch",
                               "-syncFlaggedPullStub", "-presentScreen", "settings"]
        app.launch()

        let syncNow = app.buttons["settingsSyncNowButton"]
        XCTAssertTrue(syncNow.waitForExistence(timeout: 10))
        syncNow.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        let toast = app.staticTexts["Synced. 2 entries need a look"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10),
                      "the post-batch toast must name the actual flagged count")
    }
}
