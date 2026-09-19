#if DEBUG
import Foundation
import TankbookCore

extension InboxTestSeed {
    /// RV.288: the owner's reading of 2026-09-15 - a Circle K display read as
    /// 0.56 L x 1.954 EUR/L with a total of 0.00 - against a saved 15.00 L /
    /// 50.00 EUR. The three numbers cannot coexist, so the policy withholds
    /// them and the card says so; only the currency (read as USD) is offered.
    @MainActor
    static func seedDoesNotAddUpItem() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Self.unitsFromArguments(),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        let entryID = UUID.v7()
        let fill = FillUp(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "50.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 15.00, unitPrice: Decimal(string: "3.333")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(fill)

        let extraction = GatewayExtraction(
            total: .init(value: 0, confidence: 0.30),
            volume: .init(value: 0.56, confidence: 0.50),
            unitPrice: .init(value: Decimal(string: "1.954")!, confidence: 0.90),
            currency: .init(value: .usd, confidence: 0.60),
            pipeline: "seed")
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, extraction: extraction)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }
}
#endif
