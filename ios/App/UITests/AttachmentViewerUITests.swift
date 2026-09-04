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

    private func launch(_ seed: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", seed, "-presentScreen", "editEntry"] + extra
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

    // MARK: - RV.17: the recognised data, share, and the download progress

    /// The recognised data is "just an additional photo": a second page reached
    /// by swiping, not chrome over the receipt. `-seedPhotoLocal` carries the
    /// OCR line, the scan timestamp and - RV.48 - the parse's per-field
    /// assignment, so the page shows meaning with the raw lines demoted behind
    /// a disclosure.
    func testTheRecognisedDataPageIsReachableWhenPresent() {
        let app = launch("-seedPhotoLocal")

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()

        let image = app.descendants(matching: .any)["attachmentViewerImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 10),
                      "the photo page must open first")

        app.swipeLeft()

        let recognised = app.descendants(matching: .any)["attachmentViewerRecognised"]
        XCTAssertTrue(recognised.waitForExistence(timeout: 10),
                      "the recognised data must be reachable by swiping to the next page")
        XCTAssertTrue(recognised.isHittable,
                      "the recognised data must be visible, not merely in the hierarchy")
        // RV.48: the assigned fields are the headline, the raw lines the evidence.
        XCTAssertTrue(app.descendants(matching: .any)["attachmentViewerRecognisedFields"].isHittable,
                      "the assigned fields must render on the recognised page")
        // The raw OCR lines are demoted behind a disclosure, never deleted: the
        // disclosure label is present and the raw text is collapsed out of sight.
        XCTAssertTrue(app.staticTexts["Read from the receipt"].waitForExistence(timeout: 5),
                      "the raw OCR lines must be offered behind a disclosure")
        XCTAssertFalse(app.descendants(matching: .any)["attachmentViewerOcrText"].exists,
                       "the raw OCR lines must start collapsed, not as a headline")
    }

    /// RV.48 the whole point: the recognised page shows what the parse CONCLUDED,
    /// not line soup. The seeded assignment is 71.02 EUR total, 42.30 L volume,
    /// 1.679 EUR/L price, petrol95, EUR - the values the parser read off the
    /// receipt, each asserted as a value (never merely that the card renders).
    func testTheRecognisedPageShowsTheAssignedValues() {
        let app = launch("-seedPhotoLocal")

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["attachmentViewerImage"]
            .waitForExistence(timeout: 10))
        app.swipeLeft()

        let fields = app.descendants(matching: .any)["attachmentViewerRecognisedFields"]
        XCTAssertTrue(fields.waitForExistence(timeout: 10),
                      "the assigned-field card must render")
        XCTAssertTrue(fields.isHittable,
                      "the assigned-field card must be visible, not merely present")

        // The values the parse assigned - asserted as concrete values within the
        // card, so a card that renders nothing still fails. petrol95 renders as
        // its grade "95" (docs/SCHEMA.md fuel kind labels).
        XCTAssertTrue(fields.staticTexts["71.02"].exists, "the assigned total must render")
        XCTAssertTrue(fields.staticTexts["42.30"].exists, "the assigned volume must render")
        XCTAssertTrue(fields.staticTexts["1.679"].exists, "the assigned unit price must render")
        XCTAssertTrue(fields.staticTexts["95"].exists, "the assigned fuel kind must render")
        XCTAssertTrue(fields.staticTexts["EUR"].exists, "the assigned currency must render")
    }

    /// A parse that assigned nothing says so, instead of an empty card (RV.48's
    /// L4 requirement). `-seedPhotoNothingAssigned` carries the raw lines and the
    /// timestamp but no assignment, so the page exists and states it plainly.
    func testNothingAssignedSaysSo() {
        let app = launch("-seedPhotoNothingAssigned")

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["attachmentViewerImage"]
            .waitForExistence(timeout: 10))
        app.swipeLeft()

        let nothing = app.descendants(matching: .any)["attachmentViewerNothingRecognised"]
        XCTAssertTrue(nothing.waitForExistence(timeout: 10),
                      "a nothing-assigned receipt must say so, never an empty card")
        XCTAssertTrue(nothing.isHittable,
                      "the nothing-assigned statement must be visible, not merely present")
        XCTAssertFalse(app.descendants(matching: .any)["attachmentViewerRecognisedFields"].exists,
                       "no assigned-field card must render when nothing was assigned")
    }

    /// With nothing recognised, the surface is absent rather than empty: no
    /// pager, so a swipe cannot reveal a second page that is not in the
    /// hierarchy at all.
    func testTheRecognisedPageIsAbsentWhenNothingWasRead() {
        let app = launch("-seedPhotoLocalNoOCR")

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()

        let image = app.descendants(matching: .any)["attachmentViewerImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 10),
                      "the local photo must open")

        app.swipeLeft()
        XCTAssertFalse(app.descendants(matching: .any)["attachmentViewerRecognised"].exists,
                       "with no recognised data the page must be absent, never an empty page")
    }

    /// Share is offered only once the full rendition is local. A share sheet
    /// over the 44 pt thumbnail is worse than no share sheet, so in the
    /// not-local state the button is absent from the hierarchy entirely (not
    /// merely disabled - XCUITest keeps disabled controls in the tree).
    func testShareIsOfferedOnlyOnceTheFullRenditionIsLocal() {
        let app = launch("-seedPhotoLocal")
        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()

        let share = app.buttons["attachmentViewerShareButton"]
        XCTAssertTrue(share.waitForExistence(timeout: 10),
                      "share must be offered once the full rendition is local")
        XCTAssertTrue(share.isHittable,
                      "the share button must be hittable, not merely present")

        let syncing = launch("-seedPhotoSyncing")
        let syncingChip = syncing.buttons["attachmentPhotoSyncing"]
        XCTAssertTrue(syncingChip.waitForExistence(timeout: 15))
        syncingChip.tap()

        XCTAssertTrue(syncing.descendants(matching: .any)["attachmentViewerUnavailable"]
            .waitForExistence(timeout: 10),
                      "the not-downloaded state must render")
        XCTAssertFalse(syncing.buttons["attachmentViewerShareButton"].exists,
                       "share must not be offered while the full rendition is missing")
    }

    /// The wait looks like work: with a slow seeded transport the progress
    /// indication is on screen for the whole fetch and the share affordance
    /// stays withheld until the full rendition lands. If the fetch were instant
    /// the downloading line would be gone by the time this asserts it, so the
    /// test fails on a fetch that proves nothing.
    func testTheDownloadShowsProgressForTheWholeFetch() {
        let app = launch("-seedPhotoRemote", extra: ["-seedBlobFetchDelay", "8"])

        let chip = app.buttons["attachmentPhotoSyncing"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15),
                      "a not-local photo is still openable (hard rule 1)")
        chip.tap()

        let downloading = app.descendants(matching: .any)["attachmentViewerDownloading"]
        XCTAssertTrue(downloading.waitForExistence(timeout: 10),
                      "the download must show progress while the fetch runs")
        XCTAssertTrue(downloading.isHittable,
                      "the progress indication must be visible, not merely present")
        XCTAssertFalse(app.buttons["attachmentViewerShareButton"].exists,
                       "share must stay withheld while the fetch is in flight")

        let image = app.descendants(matching: .any)["attachmentViewerImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 20),
                      "the full rendition must arrive once the fetch completes")
        let share = app.buttons["attachmentViewerShareButton"]
        XCTAssertTrue(share.waitForExistence(timeout: 10),
                      "share must appear once the full rendition is local")
        XCTAssertTrue(share.isHittable)
    }

    // MARK: - RV.37 delete and replace

    /// The corpus fixtures live on the host; the simulator shares the host
    /// filesystem, so the app under test reads a fixture by its host path -
    /// passed through `-attachReceiptFixtureImage` - and OCRs it for real.
    private var fixturesRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AttachmentViewerUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures")
            .path
    }

    /// Delete removes the receipt from the entry: the viewer is dismissed and
    /// the strip falls back to "Add receipt" with no chip left behind. The
    /// 30-day recoverability of the tombstone is pinned at L1; this is the
    /// user-visible half of the delete (hard rule 8).
    func testDeleteRemovesTheReceiptFromTheEntry() {
        let app = launch("-seedPhotoLocal")

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()

        let delete = app.buttons["attachmentViewerDeleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        XCTAssertTrue(delete.isHittable, "delete must be a control the user can hit")
        delete.tap()

        // The system confirmation is the one place red lives.
        let alert = app.alerts["Delete this receipt?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "deleting must ask for confirmation (destructive)")
        XCTAssertTrue(alert.buttons["Delete"].exists)
        alert.buttons["Delete"].tap()

        // The viewer closes and the entry is left with no receipt.
        XCTAssertTrue(app.buttons["editAddReceiptButton"].waitForExistence(timeout: 10),
                      "deleting the receipt must leave the entry offering Add receipt again")
        XCTAssertFalse(app.descendants(matching: .any)["attachmentPhotoChip"].exists,
                       "the receipt chip must be gone after delete")
    }

    /// Replace swaps the photo and the ask appears - the whole feature. The
    /// three options are present, with "Leave it as it is" the default.
    func testReplaceSwapsThePhotoAndAsksToReRead() {
        let fixture = fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = launch("-seedPhotoLocal", extra: ["-attachReceiptFixtureImage", fixture])

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()

        let replace = app.buttons["attachmentViewerReplaceButton"]
        XCTAssertTrue(replace.waitForExistence(timeout: 10))
        XCTAssertTrue(replace.isHittable, "replace must be a control the user can hit")
        replace.tap()

        // The "Photos" door resolves the fixture directly (the out-of-process
        // picker cannot be driven), so this is the real replace path.
        let photos = app.buttons["Photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        photos.tap()

        XCTAssertTrue(app.buttons["Leave it as it is"].waitForExistence(timeout: 15),
                      "after the swap the re-read ask must appear")
        XCTAssertTrue(app.buttons["Update entry"].exists,
                      "the ask must offer updating the entry")
        XCTAssertTrue(app.buttons["Use a different receipt"].exists,
                      "the ask must offer replacing with another receipt")
    }

    /// Declining the re-read leaves every field byte-identical. The seed leaves
    /// total and price BLANK and liters typed at 42.30; the fixture's OCR reads
    /// a total and a price. Asserting the VALUES - the blank total is still
    /// blank, the typed liters unchanged - is what catches a decline that
    /// overwrote anyway (a dialog that only showed would pass a weaker check).
    func testDecliningTheReReadLeavesEveryFieldByteIdentical() {
        let fixture = fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = launch("-seedEditEntryTypedAttached",
                         extra: ["-attachReceiptFixtureImage", fixture])

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()

        app.buttons["attachmentViewerReplaceButton"].tap()
        let photos = app.buttons["Photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        photos.tap()

        let leave = app.buttons["Leave it as it is"]
        XCTAssertTrue(leave.waitForExistence(timeout: 15))
        leave.tap()

        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue((total.value as? String ?? "").isEmpty,
                      "declining the re-read must leave the blank total blank")
        XCTAssertEqual(app.textFields["manualFillUpLitersField"].value as? String, "42.30",
                       "declining the re-read must leave the typed liters byte-identical")
    }

    /// Accepting the re-read fills only fields that were blank and leaves a
    /// user-typed value untouched: the blank total is filled from the receipt,
    /// the typed liters stay exactly as the user entered them.
    func testAcceptingTheReReadFillsOnlyBlankFields() {
        let fixture = fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = launch("-seedEditEntryTypedAttached",
                         extra: ["-attachReceiptFixtureImage", fixture])

        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()

        app.buttons["attachmentViewerReplaceButton"].tap()
        let photos = app.buttons["Photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        photos.tap()

        let update = app.buttons["Update entry"]
        XCTAssertTrue(update.waitForExistence(timeout: 15))
        update.tap()

        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertFalse((total.value as? String ?? "").isEmpty,
                       "accepting the re-read must fill the blank total from the receipt")
        XCTAssertEqual(app.textFields["manualFillUpLitersField"].value as? String, "42.30",
                       "accepting the re-read must never overwrite a typed value")
    }

    /// The `-openAttachmentViewerReplaceAsk` screenshot seam presents the ask
    /// over the viewer (simctl cannot drive the replace flow). It reaches the
    /// SAME state a real replace does, so the committed screenshot shows the
    /// real ask - this pins that the seam works.
    func testTheReplaceAskScreenshotSeamPresentsTheAsk() {
        let app = launch("-seedPhotoLocal",
                         extra: ["-openAttachmentViewer", "-openAttachmentViewerReplaceAsk"])

        XCTAssertTrue(app.buttons["Leave it as it is"].waitForExistence(timeout: 10),
                      "the screenshot seam must present the re-read ask")
        XCTAssertTrue(app.buttons["Update entry"].exists,
                      "the ask must offer updating the entry")
        XCTAssertTrue(app.buttons["Use a different receipt"].exists,
                      "the ask must offer replacing with another receipt")
    }
}
