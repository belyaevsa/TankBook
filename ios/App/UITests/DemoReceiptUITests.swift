import XCTest

/// PJ.42 - the sample receipt from the first-entry card: the real reader on the
/// real verify screen, ending on "Done – now try your own", saving nothing.
@MainActor
final class DemoReceiptUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTheSampleReadsTheBundledReceiptAndSavesNothing() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-clearSessionAtLaunch", "-seedHomeEmptyVehicle"]
        app.launch()

        let tryIt = app.buttons["homeTryDemoReceipt"]
        XCTAssertTrue(tryIt.waitForExistence(timeout: 15), "the first-entry card offers the sample")
        tryIt.tap()

        XCTAssertTrue(app.staticTexts["captureVerifyDemoLabel"].waitForExistence(timeout: 10),
                      "the verify screen says it is a sample")
        // Oracle: the drawing's printed lines, 45,22 L x 1,754 EUR/L = 79,32 EUR.
        let total = app.textFields["captureVerifyTotalField"]
        let read = expectation(for: NSPredicate(format: "value CONTAINS %@", "79.32"), evaluatedWith: total)
        wait(for: [read], timeout: 30)
        XCTAssertFalse(app.buttons["captureVerifyRetakeButton"].exists, "a sample has nothing to re-take")
        XCTAssertFalse(app.buttons["captureVerifyContinueButton"].exists, "a sample continues into nothing")

        app.buttons["captureVerifyDemoDoneButton"].tap()
        XCTAssertTrue(app.buttons["homeTryDemoReceipt"].waitForExistence(timeout: 10),
                      "back on Home with still no entry - the sample saved nothing")
    }
}
