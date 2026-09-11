import Testing
import Foundation
@testable import TankbookCore

/// RV.197: the log stream's presence is a function of the entry count, never of
/// account state. Before this row a guest could log a fill-up and never see it,
/// because the guest Home omitted the log entirely while the signed-in Home
/// rendered it - a hard rule 1 failure (no screen is ever sync-gated). The
/// decision lives in `HomeLayout`, whose only input is the derived `HomeStats`;
/// there is no session parameter for a branch to consult, so the same data
/// produces the same answer for a guest and a signed-in user.
@Suite("HomeLayout: the log stream is gated on entries, never account state (RV.197)")
struct HomeLayoutTests {

    private static let asOf = Date(timeIntervalSince1970: 1_752_000_000)

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: asOf, updatedAt: asOf,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func fill() -> FillUp {
        let date = asOf - 86_400
        return FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: 118_000,
            money: Money(amount: Decimal(string: "50")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true,
            tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    /// The reported walk: a fill-up exists, so the log stream renders - and the
    /// function takes no account/session input that could hide it.
    @Test func anEntryRendersTheLogStream() {
        let stats = HomeStats(vehicle: Self.vehicle(), entries: [Self.fill()], asOf: Self.asOf)
        #expect(HomeLayout.logArea(for: stats) == .stream,
                "one entry must render the log stream for any user, signed in or not")
    }

    /// Zero entries is the empty area - the guest's capture card, the signed-in
    /// empty-entries card.
    @Test func noEntriesRendersTheEmptyArea() {
        let stats = HomeStats(vehicle: Self.vehicle(), entries: [], asOf: Self.asOf)
        #expect(HomeLayout.logArea(for: stats) == .empty)
    }

    /// No car yet: there is no stats object, and the area is empty rather than a
    /// crash or an invented stream.
    @Test func noCarRendersTheEmptyArea() {
        #expect(HomeLayout.logArea(for: nil) == .empty)
    }
}
