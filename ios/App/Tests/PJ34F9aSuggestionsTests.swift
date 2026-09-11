import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// PJ.34: the Confirm/edit F9a sheet consumes `TimelineValidator`'s ordered
/// resolution list, and the receipt-priority ranking is only reachable when the
/// confirm path passes the entry's `attachments:` to the validator.
///
/// ORACLE for every order assertion here: `TimelineValidator`'s own documented
/// PRIORITY rule (docs/SCHEMA.md -> Validation) as pinned by
/// `TimelineValidationTests.attachmentTimestampRanksFixOdometerFirst` and
/// `.manualEntryWithoutReceiptRanksDateChangeFirstWithoutConfirmation`
/// (`ios/Tests/TankbookCoreTests/TimelineValidationTests.swift:238-255`). This
/// test adds the half those cannot see: the CONFIRM call site in
/// `ManualFillUpFormState.odometerConflict` must forward the evidence, so the
/// ranking the validator computes is the ranking the sheet renders.
final class PJ34F9aSuggestionsTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private var epoch: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    private func makeVehicle() -> Vehicle {
        Vehicle(id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
                name: "Test Volvo", make: "Volvo", model: "V60", year: 2015, plate: nil,
                powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
                batteryCapacityKWh: nil, homeCurrency: .eur,
                units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                     energy: .kWhPer100),
                photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 0)
    }

    private func makeFill(date: Date, odometer: Int) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
               vehicleId: UUID.v7(), date: date, odometer: odometer,
               money: nil, note: nil, attachments: [], provenance: .manual,
               conflict: .none, purchaseGroupId: nil, volumeL: 40,
               unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil, isFull: true,
               tankLevelAfterPct: 100, stationId: nil,
               crossCheck: .notApplicable, extraction: nil)
    }

    /// A receipt attachment carrying the printed date the ranking trusts.
    private func makeReceipt(timestamp: Date) -> Attachment {
        Attachment(id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp,
                   deletedAt: nil, kind: .photo,
                   file: LocalFileRef(sha256: "sha", relativePath: "receipt.jpg"),
                   extractedTimestamp: timestamp, ocrText: nil)
    }

    /// The out-of-order candidate the sheet is asked to resolve: dated after
    /// both neighbours but below the middle one.
    private func makeConflictForm() -> ManualFillUpFormState {
        var form = ManualFillUpFormState()
        form.odometer = "10020"
        form.date = epoch.addingTimeInterval(10 * day)
        return form
    }

    /// L1, and it FAILS on the pre-PJ.34 code: the confirm call site must pass
    /// the receipt attachment, so a receipt-dated entry gets `.fixOdometer`
    /// FIRST and the date change requires explicit confirmation.
    func testConfirmPathWithReceiptRanksFixOdometerFirst() {
        let car = makeVehicle()
        let first = makeFill(date: epoch, odometer: 10_000)
        let middle = makeFill(date: epoch.addingTimeInterval(5 * day), odometer: 10_050)
        let receiptDate = epoch.addingTimeInterval(5 * day)

        let conflict = makeConflictForm().odometerConflict(
            vehicle: car, existingEntries: [first, middle],
            attachments: [makeReceipt(timestamp: receiptDate)], distanceUnit: .km)

        XCTAssertEqual(
            conflict?.suggestions,
            [.fixOdometer(from: nil, to: nil),
             .fixDate(from: nil, to: nil, requiresExplicitConfirmation: true)],
            "a printed receipt date is ground truth, so fix odometer ranks first")
        XCTAssertEqual(conflict?.receiptDate, receiptDate,
                       "the confirmation must be able to name the receipt's date")
    }

    /// L1: with no attachment the ranking is the typed order - fix date first,
    /// no confirmation - and there is no receipt date to name.
    func testConfirmPathWithoutReceiptRanksFixDateFirst() {
        let car = makeVehicle()
        let first = makeFill(date: epoch, odometer: 10_000)
        let middle = makeFill(date: epoch.addingTimeInterval(5 * day), odometer: 10_050)

        let conflict = makeConflictForm().odometerConflict(
            vehicle: car, existingEntries: [first, middle], distanceUnit: .km)

        XCTAssertEqual(
            conflict?.suggestions,
            [.fixDate(from: nil, to: nil, requiresExplicitConfirmation: false),
             .fixOdometer(from: nil, to: nil)],
            "without a receipt the date change is the plain first resort")
        XCTAssertNil(conflict?.receiptDate)
    }

    /// L1: the rendered order IS the model order. The view iterates
    /// `conflict.suggestions` with no re-ranking, so the first element the
    /// sheet preselects is the validator's first suggestion in both cases.
    /// (The L4 `ConfirmManualUITests` asserts the rendered preselection.)
    func testRenderedOrderIsTheModelOrderInBothRankings() {
        let car = makeVehicle()
        let first = makeFill(date: epoch, odometer: 10_000)
        let middle = makeFill(date: epoch.addingTimeInterval(5 * day), odometer: 10_050)

        let withReceipt = makeConflictForm().odometerConflict(
            vehicle: car, existingEntries: [first, middle],
            attachments: [makeReceipt(timestamp: epoch.addingTimeInterval(5 * day))],
            distanceUnit: .km)
        let withoutReceipt = makeConflictForm().odometerConflict(
            vehicle: car, existingEntries: [first, middle], distanceUnit: .km)

        XCTAssertEqual(withReceipt?.suggestions.first, .fixOdometer(from: nil, to: nil))
        XCTAssertEqual(withoutReceipt?.suggestions.first,
                       .fixDate(from: nil, to: nil, requiresExplicitConfirmation: false))
    }

    /// The confirmation sentence names the receipt's own date (hard rule 7),
    /// and never falls back to a bare "are you sure?".
    func testDateConfirmationNamesTheReceiptDate() throws {
        let car = makeVehicle()
        let first = makeFill(date: epoch, odometer: 10_000)
        let middle = makeFill(date: epoch.addingTimeInterval(5 * day), odometer: 10_050)
        let receiptDate = epoch.addingTimeInterval(5 * day)

        let conflict = try XCTUnwrap(makeConflictForm().odometerConflict(
            vehicle: car, existingEntries: [first, middle],
            attachments: [makeReceipt(timestamp: receiptDate)], distanceUnit: .km))

        let message = conflict.dateConfirmationMessage()
        let expectedDay = Calendar.current.component(.day, from: receiptDate)
        XCTAssertTrue(message.contains("\(expectedDay)"),
                      "the confirmation must name the receipt's day, was '\(message)'")
        XCTAssertTrue(message.localizedCaseInsensitiveContains("receipt")
                        || message.localizedCaseInsensitiveContains("чек"),
                      "the confirmation must name the receipt as the evidence, was '\(message)'")
    }
}
