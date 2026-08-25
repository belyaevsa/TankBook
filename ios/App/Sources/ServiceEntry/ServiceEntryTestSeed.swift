import Foundation
import TankbookCore

// MARK: - Screenshot + UI-test seeding

/// The ServiceEntry form's seed pre-fill, the same test-hook pattern as
/// `ConfirmPrefillSeed`: a launch argument pre-populates the typed form so a
/// screenshot or UI test can reach a populated state without driving taps
/// (simctl cannot tap). The pre-fill is default input the user edits (hard
/// rule 13), never a separate screen.
struct ServiceEntryPrefill {
    var vendor = ""
    var items: [ServiceEntryItemDraft] = []
    var odometer = ""
    var date = Date()
}

enum ServiceEntryPrefillSeed {
    /// - `-seedServiceEntry` - the artboard state: Bosch Service, two line
    ///   items (oil 89.00 + brake pads 59.00), odometer 118 930.
    /// - `-seedServiceEntryLumpSum` - the J7 lump sum: one uncategorized item
    ///   ("Annual service") carrying the whole 148.00 total, DIY (no vendor).
    static func from(arguments: [String]) -> ServiceEntryPrefill? {
        if arguments.contains("-seedServiceEntry") {
            return ServiceEntryPrefill(
                vendor: "Bosch Service",
                items: [
                    ServiceEntryItemDraft(title: "Oil service incl. filter",
                                          category: .oil, cost: "89.00"),
                    ServiceEntryItemDraft(title: "Brake pads front",
                                          category: .brakes, cost: "59.00")
                ],
                odometer: OdometerFormat.grouped(118_930))
        }
        if arguments.contains("-seedServiceEntryLumpSum") {
            return ServiceEntryPrefill(
                vendor: "",
                items: [
                    ServiceEntryItemDraft(title: "Annual service",
                                          category: .other(""), cost: "148.00")
                ],
                odometer: OdometerFormat.grouped(118_930))
        }
        return nil
    }
}

/// Seeds one vehicle with `initialOdometer` 118 930 so the ServiceEntry
/// screenshots show the "last known" odometer pre-fill the artboard draws,
/// without a prior entry. Idempotent: once a vehicle exists it does nothing
/// (the capture script's `-homeResetDatabase` clears it first).
enum ServiceEntryTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        // The shared vehicle seed (a car + one prior fill) is what the UI tests
        // launch with; it drives the "last known" odometer pre-fill.
        if arguments.contains("-seedVehicleForUITests") {
            ManualFillUpTestSeed.seedIfRequested()
            return
        }
        guard arguments.contains("-seedServiceEntry")
            || arguments.contains("-seedServiceEntryLumpSum") else { return }
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
            initialOdometer: 118_930)
        try? repository.upsertVehicle(vehicle)
    }
}
