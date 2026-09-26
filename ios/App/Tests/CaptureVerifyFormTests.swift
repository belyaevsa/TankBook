import XCTest
import TankbookCore
@testable import Tankbook

/// The capture verify screen's three numbers: recognition fills what the user
/// has not typed, never what they have (hard rule 13), and the numbers reach
/// the entry as the user left them.
final class CaptureVerifyFormTests: XCTestCase {
    private func prefill(_ extraction: FuelExtraction) -> ConfirmPrefill {
        ConfirmPrefill(extraction: extraction)
    }

    func testRecognitionFillsTheThreeFieldsInTheCarsUnits() {
        var form = CaptureVerifyForm()
        form.applyRecognition(prefill(FuelExtraction(liters: 42.3, unitPrice: 1.679, total: 71.02)), volumeUnit: .l)
        XCTAssertEqual(form.total, "71.02")
        XCTAssertEqual(form.volume, "42.30")
        XCTAssertEqual(form.unitPrice, "1.679")
    }

    func testALateRecognitionNeverReplacesWhatTheUserTyped() {
        var form = CaptureVerifyForm()
        form.set(.total, to: "72.00")
        form.applyRecognition(prefill(FuelExtraction(liters: 42.3, unitPrice: 1.679, total: 71.02)), volumeUnit: .l)
        XCTAssertEqual(form.total, "72.00", "the typed total is the user's")
        XCTAssertEqual(form.volume, "42.30", "an untouched field still fills")
    }

    func testTheNumbersDisagreeWhenTheyDoNotMultiplyUp() {
        var form = CaptureVerifyForm()
        form.applyRecognition(prefill(FuelExtraction(liters: 42.3, unitPrice: 1.679, total: 71.02)), volumeUnit: .l)
        XCTAssertEqual(form.crossCheck(volumeUnit: .l), .verified)
        form.set(.total, to: "80.00")
        if case .mismatch? = form.crossCheck(volumeUnit: .l) {} else {
            XCTFail("80.00 against 42.30 x 1.679 must disagree")
        }
    }

    func testTheNumbersReachTheEntryAsTheUserLeftThem() {
        var form = CaptureVerifyForm()
        form.applyRecognition(prefill(FuelExtraction(liters: 42.3)), volumeUnit: .l)
        form.set(.total, to: "71.02")
        XCTAssertEqual(form.numbers, CaptureVerifiedNumbers(total: "71.02", volume: "42.30", unitPrice: ""))
    }
}
