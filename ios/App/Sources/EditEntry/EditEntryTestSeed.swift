import Foundation
import TankbookCore

/// UI-test / screenshot seeding for the Edit entry screen. `-seedEditEntry`
/// writes the smallest history that renders the artboard state
/// (design/screens/EditEntry.dc.html): a vehicle, one prior fill so the target
/// entry has an odometer delta, and the target fill itself - a full tank at
/// Shell with a scanned receipt, the exact figures the artboard shows
/// (71.02 € / 42.30 L / 1.679, 119 486 km). Idempotent, like the other seeds:
/// once a vehicle exists it does nothing, so app data survives across launches.
enum EditEntryTestSeed {
    @MainActor
    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedEditEntry") else { return }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_579)
        try? repository.upsertVehicle(vehicle)

        let shell = Station(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Shell", brand: nil, location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil),
            lastUsedAt: nil)
        try? repository.upsertStation(shell)

        // The prior fill six days earlier anchors the "+907 km" odometer delta.
        let priorDate = now.addingTimeInterval(-6 * 86_400)
        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: priorDate, updatedAt: priorDate, deletedAt: nil,
            vehicleId: vehicle.id, date: priorDate, odometer: 118_579,
            money: Money(amount: Decimal(string: "70.15")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.1, unitPrice: Decimal(string: "1.666")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil))

        // The receipt with the printed timestamp that anchors the scan line.
        let scannedAt = Calendar.current.date(bySettingHour: 21, minute: 47, second: 0, of: priorDate) ?? priorDate
        let receipt = Attachment(
            id: UUID.v7(), createdAt: scannedAt, updatedAt: scannedAt, deletedAt: nil,
            kind: .photo, file: LocalFileRef(sha256: UUID().uuidString,
                                             relativePath: "seed/\(UUID().uuidString).jpg"),
            extractedTimestamp: scannedAt, ocrText: "SHELL 71.02 42.30 1.679")
        try? repository.upsertAttachment(receipt)

        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: scannedAt, updatedAt: scannedAt, deletedAt: nil,
            vehicleId: vehicle.id, date: scannedAt, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [receipt.id], provenance: .receiptScan,
            conflict: .none, purchaseGroupId: nil,
            volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: shell.id, crossCheck: .verified, extraction: nil))
    }
}
