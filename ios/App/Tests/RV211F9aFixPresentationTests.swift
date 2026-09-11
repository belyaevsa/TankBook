import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.211: a service and an expense present ONE odometer fix for an F9a timeline
/// conflict, never the fill-up's ranked list. The fill-up ranking exists to
/// arbitrate a printed receipt date against a typed odometer; a service's
/// conflict is not that question, so `F9aFixPresentation` collapses the non-fill
/// kinds to `.fixOdometer`. These tests assert the rule from BOTH entry kinds
/// through the same function, so the two cannot drift, and from the service form
/// state that actually renders the warn.
///
/// ORACLE: `F9aFixPresentation.fixes` and the `ServiceEntryFormState` call site
/// it feeds (`ios/Sources/TankbookCore/Validation/F9aFixPresentation.swift`,
/// `ios/App/Sources/ServiceEntry/ServiceEntryFormState.swift`).
final class RV211F9aFixPresentationTests: XCTestCase {

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

    /// The validator's ranked list for an order conflict with no receipt: date
    /// first, odometer second. The non-fill kinds must NOT present this.
    private var rankedSuggestions: [TimelineValidator.ResolutionSuggestion] {
        [.fixDate(from: nil, to: nil, requiresExplicitConfirmation: false),
         .fixOdometer(from: nil, to: nil)]
    }

    /// L1 from both non-fill kinds: the same function, the same single fix.
    func testServiceAndExpensePresentTheSameSingleOdometerFix() {
        XCTAssertEqual(F9aFixPresentation.fixes(rankedSuggestions, for: .service),
                       [.fixOdometer(from: nil, to: nil)],
                       "a service presents the single odometer fix (RV.211)")
        XCTAssertEqual(F9aFixPresentation.fixes(rankedSuggestions, for: .expense),
                       [.fixOdometer(from: nil, to: nil)],
                       "an expense presents the single odometer fix (RV.211)")
        XCTAssertEqual(F9aFixPresentation.fixes(rankedSuggestions, for: .service),
                       F9aFixPresentation.fixes(rankedSuggestions, for: .expense),
                       "the two non-fill kinds must not drift")
    }

    /// The fill-up keeps the validator's ranked order untouched - the rule
    /// collapses only the non-fill kinds.
    func testFillUpKeepsTheRankedList() {
        XCTAssertEqual(F9aFixPresentation.fixes(rankedSuggestions, for: .fillUp),
                       rankedSuggestions,
                       "a fill-up must still render the validator's ranked list")
    }

    /// L1, and it FAILS if the service path stops consulting the rule: the form
    /// state a service renders carries exactly one odometer fix, not the
    /// validator's ranked list.
    func testServiceFormStateCarriesTheSingleOdometerFix() throws {
        var form = ServiceEntryFormState()
        form.odometer = "10020"
        form.date = epoch.addingTimeInterval(10 * day)

        let conflict = try XCTUnwrap(
            form.odometerConflict(vehicle: makeVehicle(),
                                  existingEntries: [makeFill(date: epoch, odometer: 10_000),
                                                    makeFill(date: epoch.addingTimeInterval(5 * day),
                                                             odometer: 10_050)],
                                  distanceUnit: .km),
            "the out-of-order service must flag")

        XCTAssertEqual(conflict.suggestions, [.fixOdometer(from: nil, to: nil)],
                       "the service warn must present one fix, never the fill-up ranking")
        XCTAssertNotNil(conflict.quote, "the order conflict names the conflicting entry")
    }

    /// A service with no odometer never flags - the single fix is only presented
    /// when there is a conflict to resolve.
    func testServiceWithoutOdometerDoesNotFlag() {
        var form = ServiceEntryFormState()
        form.date = epoch.addingTimeInterval(10 * day)
        XCTAssertNil(form.odometerConflict(vehicle: makeVehicle(),
                                           existingEntries: [makeFill(date: epoch, odometer: 10_000)],
                                           distanceUnit: .km))
    }
}
