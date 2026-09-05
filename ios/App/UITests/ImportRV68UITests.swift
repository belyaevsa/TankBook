import XCTest

/// RV.68 - the L4 half of "a cancellation is not an offline state". Lives in
/// its own file so `ImportUITests.swift` stays under the file-length floor
/// (the same pattern `CaptureUITests` uses for its extension suites).
@MainActor
final class ImportRV68UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    // MARK: - RV.68 a cancelled load is not offline

    /// The transport's FIRST formats request is cancelled - the shape of a
    /// SwiftUI `.task` cancelled by a view update - and every later request is
    /// healthy. The old catch-all turned that cancellation into "Importing
    /// needs a connection" on an online device; the wizard must not render the
    /// offline card for a request that was stopped before it had a conclusion.
    /// The assertion is the card's ABSENCE (the defect was that it rendered too
    /// eagerly), never that an error surfaced.
    func testACancelledLoadNeverShowsTheOfflineCard() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-importCancelFirstFormats"])
        XCTAssertFalse(app.staticTexts["Importing needs a connection"].waitForExistence(timeout: 6),
                       "a cancelled formats load must not render the offline card")
        XCTAssertFalse(app.descendants(matching: .any)["importOfflineCard"].exists,
                       "the offline card element must not be present after a cancelled load")
    }
}
