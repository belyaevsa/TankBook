import XCTest

/// A review row's odometer renders in ITS destination car's unit, not the
/// wizard's single global one. `ImportFlowModel.distanceUnit(for:)` exists for
/// exactly this and was unreferenced: every cell read `model.distanceUnit`, so
/// a file mapped into a kilometre car and a mile car labelled every row with
/// whichever unit the model happened to hold.
///
/// The test is deliberately an integration one over a MIXED-unit mapping. A
/// unit test of `distanceUnit(for:)` passes against the broken screen, and a
/// single-car import cannot fail either - the global and the per-row unit agree
/// there. Only two cars whose units disagree can tell a fixed screen from a
/// broken one.
@MainActor
final class ImportRowUnitsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-presentScreen", "importWizard"] + arguments
        app.launch()
        return app
    }

    /// Both units appear on the same review list: the rows mapped into the
    /// existing miles car read `mi`, the rows mapped into the new kilometre car
    /// read `km`. Asserting BOTH in one pass is what stops a fix that merely
    /// swaps one global for another.
    func testReviewRowsRenderTheirOwnCarsDistanceUnit() {
        let app = launch(["-seedImportCarsDecided", "-seedImportMixedUnits"])

        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 15),
                      "the decided two-car seed must land on its review list")

        let milesRow = app.otherElements["importReviewRow-1"]
        let kilometreRow = app.otherElements["importReviewRow-4"]
        XCTAssertTrue(milesRow.waitForExistence(timeout: 5))
        XCTAssertTrue(kilometreRow.waitForExistence(timeout: 5))

        let milesLabels = milesRow.staticTexts.allElementsBoundByIndex.map(\.label)
        let kilometreLabels = kilometreRow.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(milesLabels.contains { $0.contains(" mi") },
                      "the Volvo row mapped into the miles car must read mi; labels: \(milesLabels)")
        XCTAssertTrue(kilometreLabels.contains { $0.contains(" km") },
                      "the Audi row mapped into the kilometre car must read km; labels: \(kilometreLabels)")
    }
}
