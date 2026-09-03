import XCTest

/// RV.9 attachment-viewer UI tests. The device walk that filed this task said
/// the receipt "is not clickable" - so the assertions are about the chip being
/// a control the user can HIT, the viewer that opens, and the way back.
///
/// Every visibility assertion uses `isHittable`, never `exists`: XCUITest keeps
/// a covered screen in the hierarchy, so `exists` is true for things nobody can
/// see or touch (two assertions elsewhere in this suite family are vacuous for
/// exactly that reason). Where it matters, the before-state is asserted too -
/// not hittable before the tap, hittable after.
@MainActor
final class AttachmentViewerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", seed, "-presentScreen", "editEntry"]
        app.launch()
        return app
    }

    // MARK: - State 1: the full rendition is on the device

    /// The chip is a button, it is hittable, and tapping it opens the viewer on
    /// the zoomable photo. The viewer's image is asserted NOT hittable before
    /// the tap and hittable after, so a covered-but-present element cannot pass
    /// this test.
    func testTappingTheChipOpensTheViewerOnTheLocalPhoto() {
        let app = launch("-seedPhotoLocal")

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15),
                      "the receipt chip must render")
        XCTAssertTrue(chip.isHittable,
                      "the receipt chip must be a control the user can tap (RV.9)")

        let image = app.descendants(matching: .any)["attachmentViewerImage"]
        XCTAssertFalse(image.isHittable,
                       "the viewer must not be on screen before the chip is tapped")

        chip.tap()

        XCTAssertTrue(image.waitForExistence(timeout: 10),
                      "tapping the chip must open the attachment viewer")
        XCTAssertTrue(image.isHittable,
                      "the full-size photo must be visible, not merely in the hierarchy")
        // The zoom affordance: the gesture itself is driven below, but the hint
        // is what tells the user the photo can be magnified at all.
        XCTAssertTrue(app.descendants(matching: .any)["attachmentViewerZoomHint"].isHittable,
                      "the viewer must name its zoom affordance")
    }

    /// The way back. A viewer that can only be left by a gesture is a trap for
    /// the user who does not know the gesture, so the visible Close control is
    /// what this asserts - and the entry underneath is still editable after.
    func testTheViewerClosesBackToTheEditableEntry() {
        let app = launch("-seedPhotoLocal")

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()

        let close = app.buttons["attachmentViewerCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(close.isHittable, "the viewer needs a visible close control")
        close.tap()

        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 10),
                      "closing the viewer must return to the entry")
        XCTAssertTrue(total.isHittable,
                      "the entry must still be editable after the viewer closes")
        XCTAssertFalse(app.buttons["attachmentViewerCloseButton"].isHittable,
                       "the viewer must be gone, not merely covered")
    }

    /// A pinch on the photo. XCUITest can drive the gesture but cannot read the
    /// resulting zoom scale, so what this pins is that the photo survives the
    /// gesture and stays interactive - the magnification itself is verified by
    /// hand, not here.
    func testThePhotoSurvivesAPinch() {
        let app = launch("-seedPhotoLocal")

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()

        let image = app.descendants(matching: .any)["attachmentViewerImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.pinch(withScale: 3, velocity: 1)
        XCTAssertTrue(image.isHittable,
                      "the photo must still be on screen and interactive after a pinch")
    }

    // MARK: - State 3: not on the device, and nothing to fetch with

    /// The state hard rule 7 is about. `-seedPhotoSyncing` writes an entry whose
    /// full rendition is nowhere on the device, and the app is signed out, so no
    /// fetch is possible: the viewer must SAY so and name the next step rather
    /// than showing an empty frame - and the thumbnail is on screen throughout.
    func testTheNotDownloadedStateNamesItsNextStep() {
        let app = launch("-seedPhotoSyncing")

        let chip = app.buttons["attachmentPhotoSyncing"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15),
                      "the syncing chip must render")
        XCTAssertTrue(chip.isHittable,
                      "a photo that has not downloaded is still openable (hard rule 1)")
        chip.tap()

        let card = app.descendants(matching: .any)["attachmentViewerUnavailable"]
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "the viewer must explain that the full photo is not here")
        XCTAssertTrue(card.isHittable,
                      "the explanation must be visible, not merely present")

        // The headline and the next step, both rendered - the next step is the
        // half a silent empty frame would drop.
        let headline = app.descendants(matching: .any)["attachmentViewerHeadline"]
        XCTAssertTrue(headline.isHittable, "the state must be named")
        XCTAssertEqual(headline.label, "The full photo is not on this device yet")

        let nextStep = app.descendants(matching: .any)["attachmentViewerNextStep"]
        XCTAssertTrue(nextStep.isHittable,
                      "the state must name its next step (hard rule 7)")
        // Which of the two next steps depends on whether this device carries a
        // session: signed out there is nothing to fetch with, signed in the
        // fetch fails offline. Both are "not downloaded", and both must name a
        // step the user can take - that is what hard rule 7 asks for.
        let signedOut = "Sign in from Settings to download the original. This preview came with the entry."
        let failed = "Check your connection and tap Try again. This preview came with the entry."
        XCTAssertTrue([signedOut, failed].contains(nextStep.label),
                      "the next step must be one of the two named ones: \(nextStep.label)")
        if nextStep.label == failed {
            XCTAssertTrue(app.buttons["attachmentViewerRetryButton"].isHittable,
                          "the failed fetch must offer Try again as a control, not as prose")
        }

        // The thumbnail is on screen from the first frame - the payload carries
        // it, so there is never a blank viewer.
        XCTAssertTrue(app.descendants(matching: .any)["attachmentViewerThumbnail"].isHittable,
                      "the inline thumbnail must render while the full photo is missing")

        // And the entry underneath is untouched: close, and it is editable.
        app.buttons["attachmentViewerCloseButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "the entry stays editable throughout (hard rule 1)")
    }

    // MARK: - State 4: the attachment is a PDF

    /// A PDF attachment (service invoices are stored as PDFs byte-identical).
    /// An image view handed PDF bytes shows nothing, which reads as a broken
    /// screen - so the viewer hands it to PDFKit and the test pins that the PDF
    /// surface is what renders.
    func testAPdfAttachmentRendersInThePdfViewer() {
        let app = launch("-seedPhotoPDF")

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15),
                      "the PDF attachment must render a tappable chip")
        XCTAssertTrue(chip.isHittable)
        chip.tap()

        let pdf = app.descendants(matching: .any)["attachmentViewerPDF"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 10),
                      "a PDF must open in the PDF viewer, never a blank image frame")
        XCTAssertTrue(pdf.isHittable,
                      "the PDF must be visible, not merely in the hierarchy")
        XCTAssertFalse(app.descendants(matching: .any)["attachmentViewerUnavailable"].isHittable,
                       "a readable PDF must not fall back to the unavailable state")
    }
}
