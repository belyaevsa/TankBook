import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.230: a service, an expense or a charge edited into a timeline conflict is
/// flagged by the save AND the edit form exposes that flag for rendering. The
/// save path (`EditEntryView.writeNonFill`) already stamped the conflict before
/// this row; the defect was that `EditEntryNonFillView` rendered no warning at
/// all, so the flag could never be seen or cleared from the entry (hard rules 7
/// and 8). These tests pin both halves from all three kinds, because all three
/// share the one write and the one fix rule (`F9aFixPresentation`).
///
/// ORACLE: `EditEntryView.writeNonFill` (`EditEntryView+NonFillSave.swift`) and
/// `EditEntryNonFillForm.odometerConflict` (`EditEntryNonFillConflict.swift`).
@MainActor
final class RV230NonFillConflictTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private var epoch: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    private enum NonFillKind: CaseIterable {
        case service, expense, charge

        var label: String {
            switch self {
            case .service: return "service"
            case .expense: return "expense"
            case .charge: return "charge"
            }
        }
    }

    private func makeVehicle() throws -> (TankbookRepository, Vehicle) {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 0)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    /// The date-neighbour the edit's odometer falls below: a fill at 118 500.
    private func priorFill(vehicle: Vehicle) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
               vehicleId: vehicle.id, date: epoch, odometer: 118_500,
               money: nil, note: nil, attachments: [], provenance: .manual,
               conflict: .none, purchaseGroupId: nil, volumeL: 40,
               unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil, isFull: true,
               tankLevelAfterPct: 100, stationId: nil,
               crossCheck: .notApplicable, extraction: nil)
    }

    /// The entry being edited, ten days after the prior fill and reading BELOW
    /// it - the conflict the row is about.
    private func entry(_ kind: NonFillKind, vehicle: Vehicle) -> any Entry {
        let date = epoch.addingTimeInterval(10 * day)
        switch kind {
        case .service:
            return ServiceRecord(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: 117_900,
                money: Money(amount: 148, currency: .eur, homeCurrency: .eur),
                note: nil, attachments: [], provenance: .manual, conflict: .none,
                purchaseGroupId: nil, vendor: "Bosch Service", items: [],
                usedParts: [], tireSetId: nil)
        case .expense:
            return Expense(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: 117_900,
                money: Money(amount: 12, currency: .eur, homeCurrency: .eur),
                note: nil, attachments: [], provenance: .manual, conflict: .none,
                purchaseGroupId: nil, category: .other("car wash"),
                title: "Car wash", recurrence: nil, installedInServiceId: nil)
        case .charge:
            return ChargeSession(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: 117_900,
                money: Money(amount: 9, currency: .eur, homeCurrency: .eur),
                note: nil, attachments: [], provenance: .manual, conflict: .none,
                purchaseGroupId: nil, energyKWh: 30, unitPrice: nil,
                chargeType: .acPublic, provider: "Ionity")
        }
    }

    private func storedEntry(_ repository: TankbookRepository, id: UUID) throws -> any Entry {
        try XCTUnwrap(repository.liveEntry(id: id), "the edit must leave a live entry")
    }

    /// The shared assertion: the save stamps the order flag AND the form the
    /// screen renders exposes the same conflict with the single odometer fix.
    private func assertConflictSurfaces(_ kind: NonFillKind) throws {
        let (repository, vehicle) = try makeVehicle()
        let prior = priorFill(vehicle: vehicle)
        let target = entry(kind, vehicle: vehicle)
        let form = EditEntryView.pristineNonFillForm(for: target, vehicle: vehicle)

        // The view model the screen reads: one odometer fix, never the fill-up
        // ranking, and it names the neighbour the order check failed against.
        let conflict = form.odometerConflict(for: target, vehicle: vehicle,
                                             existingEntries: [prior], distanceUnit: .km)
        let surfaced = try XCTUnwrap(conflict,
                                     "\(kind.label): the out-of-order edit must surface a conflict")
        XCTAssertEqual(surfaced.suggestions, [.fixOdometer(from: nil, to: nil)],
                       "\(kind.label): the warn presents the single odometer fix (RV.211/RV.230)")
        XCTAssertNotNil(surfaced.quote,
                        "\(kind.label): an order conflict names the conflicting entry")

        // The save stamps the flag the view model exposed, so opening the entry
        // again renders the same warning.
        try EditEntryView.writeNonFill(target, vehicle: vehicle, form: form,
                                       otherEntries: [prior], repository: repository)
        let stored = try storedEntry(repository, id: target.id)
        guard case .flagged(let flagKind, _) = stored.conflict else {
            return XCTFail("\(kind.label): the save must stamp .flagged, got \(stored.conflict)")
        }
        XCTAssertEqual(flagKind, .order, "\(kind.label): the stamped flag is the order conflict")
    }

    func testServiceEditIntoAConflictIsFlaggedAndExposed() throws {
        try assertConflictSurfaces(.service)
    }

    func testExpenseEditIntoAConflictIsFlaggedAndExposed() throws {
        try assertConflictSurfaces(.expense)
    }

    func testChargeEditIntoAConflictIsFlaggedAndExposed() throws {
        try assertConflictSurfaces(.charge)
    }

    /// A charge is a travel-measuring entry, a service or expense an annotation;
    /// the fix rule gives all three the same single fix, so they cannot drift.
    func testAllThreeKindsPresentTheSameSingleFix() {
        let ranked: [TimelineValidator.ResolutionSuggestion] = [
            .fixDate(from: nil, to: nil, requiresExplicitConfirmation: false),
            .fixOdometer(from: nil, to: nil)
        ]
        let service = F9aFixPresentation.fixes(ranked, for: .service)
        XCTAssertEqual(F9aFixPresentation.fixes(ranked, for: .expense), service)
        XCTAssertEqual(F9aFixPresentation.fixes(ranked, for: .charge), service)
        XCTAssertEqual(service, [.fixOdometer(from: nil, to: nil)])
    }

    /// The edit heals: correcting the odometer to sit above the neighbour drops
    /// the view model's conflict, so the warn clears as the user fixes it - the
    /// same live behaviour the fill-up odometer card has.
    func testCorrectingTheOdometerClearsTheExposedConflict() throws {
        let (_, vehicle) = try makeVehicle()
        let prior = priorFill(vehicle: vehicle)
        let target = entry(.service, vehicle: vehicle)
        var form = EditEntryView.pristineNonFillForm(for: target, vehicle: vehicle)
        form.odometer = OdometerFormat.grouped(118_600)

        XCTAssertNil(form.odometerConflict(for: target, vehicle: vehicle,
                                           existingEntries: [prior], distanceUnit: .km),
                     "a reading above the neighbour must not flag")
    }
}
