import XCTest

/// RV.284: a row the server rejected structurally carries the "not synced" badge
/// on its Home log card (a sync slash, distinct from the conflict chevron). Its
/// tap opens the editor - the next step is "edit it to retry", never a re-push
/// of the same rejected bytes.
@MainActor
final class RV284RejectedEntryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRejectedEntryBadgeRoutesToEditEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeRejected"]
        app.launch()

        let badge = app.buttons["rejectedEntryBadgeButton"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        badge.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
    }
}
