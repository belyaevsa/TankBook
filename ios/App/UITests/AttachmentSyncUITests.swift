import XCTest

/// P4.6 attachment-sync UI test: the "photo syncing" shimmer. The seed
/// (`-seedPhotoSyncing`) writes an entry whose inline thumbnail has arrived in
/// the Attachment payload but whose full rendition blob has not landed, so the
/// receipt chip shimmers. The test asserts the shimmer renders AND that the
/// entry stays openable and editable while it shows - nothing is blocked on a
/// photo (hard rule 1).
@MainActor
final class AttachmentSyncUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPhotoSyncingShimmerRendersAndTheEntryIsEditable() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedPhotoSyncing",
                               "-presentScreen", "editEntry"]
        app.launch()

        // The shimmer is present: the chip carries the "photo syncing" state.
        // The combined accessibility element's concrete XCUITest type depends on
        // SwiftUI's trait inference (image vs container), so match any type.
        let chip = app.descendants(matching: .any)["attachmentPhotoSyncing"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "the photo-syncing shimmer must render on the receipt chip")

        // The entry is openable and editable throughout - the total field and
        // the save bar are both present, never gated on the photo.
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5),
                      "the entry must be editable while the blob is pending")
        XCTAssertTrue(app.buttons["editEntrySaveButton"].exists)
    }

    /// PJ.35: the background prefetch fetches the missing rendition without
    /// the entry ever being opened - opened afterwards, the chip carries no
    /// shimmer. `-runBlobPrefetch` stands in for "a pull just landed".
    func testPrefetchClearsTheShimmerWithoutOpeningTheEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedPhotoRemote",
                               "-seedBlobFetchDelay", "0.2", "-runBlobPrefetch"]
        app.launch()

        // Home lists the seeded entry; give the prefetch its 0.2 s.
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let landed = app.staticTexts["blobPrefetchLanded"]
        XCTAssertTrue(landed.waitForExistence(timeout: 10),
                      "the prefetch never reported completion")
        row.tap()

        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["attachmentPhotoSyncing"].exists,
                       "the rendition was prefetched - the chip must not shimmer")
    }
}
