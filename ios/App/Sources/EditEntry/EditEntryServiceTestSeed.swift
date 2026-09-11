#if DEBUG
import Foundation
import TankbookCore

/// The three service poses the Edit-entry screen seeds: PJ.23's editable line
/// items (the agreeing state), and RV.199's mismatch and mixed-currency totals.
/// Split out of `EditEntryTestSeed` so that enum stays under the linter's
/// body-length ceiling; its `seedIfRequested` calls this first.
enum EditEntryServiceTestSeed {
    /// Handles `-seedEditEntryService`, `-seedEditEntryServiceMismatch` and
    /// `-seedEditEntryServiceMixedCurrency`. Returns true when one was requested
    /// and seeded, so the caller stops.
    @MainActor
    static func seedIfRequested(arguments: [String]) -> Bool {
        if arguments.contains("-seedEditEntryServiceConflict") {
            seedServiceConflict()
            return true
        }
        if arguments.contains("-seedEditEntryServiceMismatch") {
            seedServiceMismatch()
            return true
        }
        if arguments.contains("-seedEditEntryServiceMixedCurrency") {
            seedServiceMixedCurrency()
            return true
        }
        if arguments.contains("-seedEditEntryService") {
            seedService()
            return true
        }
        return false
    }

    /// RV.230 screenshot/test seam: a SERVICE whose odometer breaks the car's
    /// timeline, opened in Edit entry. The prior fill at 118 500 km makes the
    /// service's 117 900 km an F9a order conflict, so the edit screen's odometer
    /// card must render the amber warn and its single Fix - the surface this
    /// row adds. The service is the newest entry, so `-presentScreen editEntry`
    /// opens it. Like the other resetting seeds, it wipes first under
    /// `-homeResetDatabase` so an EN-then-RU capture pair both start from the
    /// same state.
    @MainActor
    private static func seedServiceConflict() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        try? repository.upsertFillUp(HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 15, odometer: 118_500, litres: 41.2,
                                  amount: "66.90", price: "1.624", stationID: nil)))

        let now = Date()
        try? repository.upsertServiceRecord(ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 117_900,
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Bosch Service",
            items: [ServiceItem(title: "Oil service incl. filter", category: .oil,
                                cost: Money(amount: Decimal(string: "89.00")!,
                                            currency: .eur, homeCurrency: .eur),
                                partNumber: "MANN W 712/75",
                                lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))],
            usedParts: [], tireSetId: nil))
    }

    /// PJ.23 screenshot/test seam: a SERVICE record with two line items, the
    /// first carrying a `partNumber` and a `lifetime` that the edit screen does
    /// not show but must not drop. It is the newest entry, so
    /// `-presentScreen editEntry` opens it. One item is a fixed category
    /// (`.oil`) and the other a custom `.other(...)`, so the frame shows both
    /// the chooser and the free-text field. Like the other resetting seeds, it
    /// wipes first under `-homeResetDatabase` so an EN-then-RU capture pair
    /// both start from the same state.
    ///
    /// The stored Amount equals the item sum (148.00), so the frame renders the
    /// agreeing state - the RV.199 line-sum row is present and quiet. The
    /// mismatch and mixed-currency poses below differ only in `money`/`items`.
    @MainActor
    private static func seedService() {
        seedServiceRecord(
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            vendor: nil,
            items: [
                ServiceItem(title: "Oil service incl. filter", category: .oil,
                            cost: Money(amount: Decimal(string: "89.00")!,
                                        currency: .eur, homeCurrency: .eur),
                            partNumber: "MANN W 712/75",
                            lifetime: ServiceItem.Lifetime(km: 15_000, months: 12)),
                ServiceItem(title: "Brake pads front", category: .other("Bremsbeläge VA"),
                            cost: Money(amount: Decimal(string: "59.00")!,
                                        currency: .eur, homeCurrency: .eur))
            ])
    }

    /// RV.199 screenshot/test seam: a service whose stored Amount (160.00)
    /// differs from its line sum (89.00 + 59.00 = 148.00) - the honest invoice
    /// shape the row exists for (tax, a discount, an un-itemised line). The
    /// money card must state the line sum beside the Amount and mark the
    /// disagreement as ATTENTION, never rewrite the stored total (hard rule 13).
    @MainActor
    private static func seedServiceMismatch() {
        seedServiceRecord(
            money: Money(amount: Decimal(string: "160.00")!, currency: .eur, homeCurrency: .eur),
            vendor: "Bosch Service",
            items: [
                ServiceItem(title: "Oil service incl. filter", category: .oil,
                            cost: Money(amount: Decimal(string: "89.00")!,
                                        currency: .eur, homeCurrency: .eur),
                            partNumber: "MANN W 712/75",
                            lifetime: ServiceItem.Lifetime(km: 15_000, months: 12)),
                ServiceItem(title: "Brake pads front", category: .brakes,
                            cost: Money(amount: Decimal(string: "59.00")!,
                                        currency: .eur, homeCurrency: .eur))
            ])
    }

    /// RV.199 screenshot/test seam: a service whose line items are in two
    /// currencies (89.00 EUR + 59.00 USD), so no single line total exists. The
    /// money card must state the per-currency breakdown and never a summed
    /// cross-currency figure (hard rule 3, the RV.145 rule).
    @MainActor
    private static func seedServiceMixedCurrency() {
        seedServiceRecord(
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            vendor: "Bosch Service",
            items: [
                ServiceItem(title: "Oil service incl. filter", category: .oil,
                            cost: Money(amount: Decimal(string: "89.00")!,
                                        currency: .eur, homeCurrency: .eur)),
                ServiceItem(title: "Brake pads front", category: .brakes,
                            cost: Money(amount: Decimal(string: "59.00")!,
                                        currency: .usd, homeCurrency: .eur))
            ])
    }

    /// The shared service seed body: reset once per launch, one EUR Volvo, one
    /// service as the newest entry. The three poses above differ only in the
    /// stored `money`, the vendor and the items.
    @MainActor
    private static func seedServiceRecord(money: Money, vendor: String?,
                                          items: [ServiceItem]) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_579)
        try? repository.upsertVehicle(vehicle)

        try? repository.upsertServiceRecord(ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: vendor,
            items: items, usedParts: [], tireSetId: nil))
    }
}
#endif
