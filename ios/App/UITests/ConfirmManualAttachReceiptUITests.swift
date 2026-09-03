import XCTest

// MARK: - PJ.48 the quiet "Attach receipt" row, and RV.11 its anchoring
//
// Split out of ConfirmManualUITests.swift on 2026-09-03 only because that file
// reached its 700-line limit; these are the same suite (the extension keeps the
// helpers) and run with it.

/// The typed door is a peer (J3b): a quiet "Attach receipt" row, never shown
/// where a scan already carried a photo.
extension ConfirmManualUITests {

    func testAttachReceiptRowOnTheTypedPathOpensTheSourceChoice() {
        let app = launch()
        openManualForm(app)
        let row = app.buttons["confirmAttachReceiptRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        scrollClearOfSaveBar(app, row)
        XCTAssertTrue(row.isHittable)
        row.tap()
        let photos = app.buttons["Photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))

        // RV.11: the chooser must be anchored to the ROW THAT OPENED IT.
        //
        // Under iOS 26 a confirmationDialog renders as a popover anchored to the
        // view it is attached to; while it hung off the ScrollView, the popover
        // appeared near the TOP of the screen with its arrow pointing at the
        // middle of the form, while the button the user had just tapped was at
        // the bottom. Reported from a device, and invisible to the assertion
        // above - "Photos exists" was true throughout the bug.
        //
        // Stated as a comparison rather than an absolute coordinate so it holds
        // on iOS 18 too, where the same modifier is a bottom action sheet whose
        // position ignores the anchor entirely: in both presentations the
        // chooser is nearer the row than the top of the window, and only the
        // broken anchoring puts it nearer the top.
        let window = app.windows.firstMatch.frame
        let chooser = photos.frame.midY
        let toRow = abs(chooser - row.frame.midY)
        let toTop = abs(chooser - window.minY)
        XCTAssertLessThan(toRow, toTop,
                          "the source chooser must be anchored to the row that opened it "
                          + "(chooser midY \(chooser), row midY \(row.frame.midY), window top \(window.minY))")
    }

    func testAttachReceiptRowHiddenWhenAScanCarriedAPhoto() {
        let app = launchWithPrefill("-seedConfirmPrefillEmptyPhoto")
        openForm(app)
        XCTAssertFalse(app.buttons["confirmAttachReceiptRow"].exists)
    }
}
