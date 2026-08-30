import CoreGraphics
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
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedEditEntryManualRate") {
            seedManualRate()
            return
        }
        if arguments.contains("-seedEditEntryTyped") || arguments.contains("-seedEditEntryTypedAttached") {
            seedTyped(attachReceipt: arguments.contains("-seedEditEntryTypedAttached"))
            return
        }
        guard arguments.contains("-seedEditEntry") else { return }
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
        // Dated NOW, not on the prior fill's day: `-presentScreen editEntry`
        // opens the MOST RECENT entry, and a scanned fill whose timestamp
        // depends on the time of day makes that selection flaky - this seed's
        // scanned fill must always be the newest row.
        let scannedAt = now
        let receipt = Attachment(
            id: UUID.v7(), createdAt: scannedAt, updatedAt: scannedAt, deletedAt: nil,
            kind: .photo, file: LocalFileRef(sha256: UUID().uuidString,
                                             relativePath: "seed/\(UUID().uuidString).jpg"),
            extractedTimestamp: scannedAt, ocrText: "SHELL 71.02 42.30 1.679")
        try? repository.upsertAttachment(receipt)

        // PJ.2: the scanned fill carries the save's extraction record - built
        // through the REAL planner so the seeded row is exactly what a scanned
        // save writes (one receipt photo, scan provenance, per-field meta).
        let scannedPlan = ScannedSavePlanner.plan(
            extraction: FuelExtraction(liters: 42.30, unitPrice: Decimal(string: "1.679")!,
                                       total: Decimal(string: "71.02")!, currency: .eur,
                                       fuelKind: .petrol95),
            cropRects: [.total: CGRect(x: 0, y: 0, width: 120, height: 24),
                        .volume: CGRect(x: 0, y: 28, width: 120, height: 24),
                        .unitPrice: CGRect(x: 0, y: 56, width: 120, height: 24)],
            hasPhoto: true,
            saved: ScannedSaveValues(total: Decimal(string: "71.02")!, volumeL: 42.30,
                                     unitPrice: Decimal(string: "1.679")!, currency: .eur,
                                     fuelKind: .petrol95, date: scannedAt))
        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: scannedAt, updatedAt: scannedAt, deletedAt: nil,
            vehicleId: vehicle.id, date: scannedAt, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [receipt.id], provenance: scannedPlan.provenance,
            conflict: .none, purchaseGroupId: nil,
            volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: shell.id, crossCheck: .verified, extraction: scannedPlan.extraction))
    }

    /// PJ.48: a TYPED fill for the "Add receipt" flow. `-seedEditEntryTyped`
    /// seeds a fully typed fill with no attachment - the state where the receipt
    /// card shows "Add receipt". `-seedEditEntryTypedAttached` seeds the same
    /// fill with a blank `unitPrice` and a receipt photo already linked - the
    /// post-attach state the dimmed-suggestion screenshot renders (the
    /// suggestion itself is applied by the view's `-seedAttachSuggestion` hook).
    @MainActor
    private static func seedTyped(attachReceipt: Bool) {
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

        var attachments: [AttachmentID] = []
        if attachReceipt {
            let attachment = Attachment(
                id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
                kind: .photo,
                file: LocalFileRef(sha256: UUID().uuidString,
                                   relativePath: "seed/\(UUID().uuidString).jpg"),
                extractedTimestamp: nil, ocrText: "SHELL 42.30 1.679")
            try? repository.upsertAttachment(attachment)
            attachments = [attachment.id]
        }

        // The "Add receipt" state seeds a fully typed entry (no blank fields);
        // the post-attach state seeds the corporate-fill shape - no amount, no
        // price - so the attached receipt's OCR has a blank field to suggest,
        // and the suggestion stays DIM: with only liters + the suggested price
        // present the cross-check is .notApplicable, never a verified triple.
        let money: Money? = attachReceipt
            ? nil
            : Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur)
        let unitPrice: Decimal? = attachReceipt ? nil : Decimal(string: "1.679")!
        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: money, note: nil, attachments: attachments, provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: unitPrice,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil))
    }

    /// The hard-rule-13 "and again afterwards" state: a foreign fill-up whose
    /// rate was set by the USER (rateSource == .manual) on an earlier visit.
    /// The Edit screen must load that rate back into its conversion card, show
    /// it as Manual, and let the user change it - the screen where "set it
    /// once, at Confirm" would have been the bug. The fill is dated inside the
    /// bundled rate seed pack, so a feed rate exists for its day too: the
    /// manual rate must still win (the user's number is theirs permanently).
    @MainActor
    private static func seedManualRate() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedEditEntryManualRate") else { return }
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

        // 289.50 PLN at the user's rate 4.0 -> 72.38 EUR. The feed holds
        // 4.25659243 for the same day; only the manual value must show.
        let entryDay = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1)) ?? now
        let money = Money(amount: Decimal(string: "289.50")!, currency: .pln, homeCurrency: .eur)
            .applyingManualRate(Decimal(string: "4.0")!, on: entryDay)
        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: entryDay, updatedAt: entryDay, deletedAt: nil,
            vehicleId: vehicle.id, date: entryDay, odometer: 120_000,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            volumeL: 42.3, unitPrice: Decimal(string: "6.844")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil))
    }
}
