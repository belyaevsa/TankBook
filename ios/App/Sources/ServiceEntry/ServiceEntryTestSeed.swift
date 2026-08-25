import Foundation
import UIKit
import TankbookCore

// MARK: - Screenshot + UI-test seeding

/// The ServiceEntry form's pre-fill, shared by the typed seed and the scanned
/// invoice path (P3.1b). Whatever it carries is default input the user edits
/// (hard rule 13), never a separate screen. The scanned path fills `pages`
/// (captured invoices), `dateFromInvoice` (the "· invoice" date caption),
/// `provenance` and `extraction`; the typed seed leaves those at their defaults.
struct ServiceEntryPrefill {
    var vendor = ""
    var items: [ServiceEntryItemDraft] = []
    var odometer = ""
    var date = Date()
    var dateFromInvoice = false
    var pages: [InvoicePage] = []
    var provenance: Provenance = .manual
    var extraction: ExtractionMeta?
}

enum ServiceEntryPrefillSeed {
    /// - `-seedServiceEntry` - the artboard state: Bosch Service, two line
    ///   items (oil 89.00 + brake pads 59.00), odometer 118 930.
    /// - `-seedServiceEntryLumpSum` - the J7 lump sum: one uncategorized item
    ///   ("Annual service") carrying the whole 148.00 total, DIY (no vendor).
    /// - `-seedServiceEntryScan` - the P3.1b scanned invoice: the same two
    ///   items, but scanned (dimmed), the "· invoice" date caption, and a
    ///   three-page strip.
    /// - `-seedServiceEntryScanLumpSum` - the honest failed-split outcome: one
    ///   uncategorized item carrying the whole total, the page strip still
    ///   present, no error anywhere.
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
        if arguments.contains("-seedServiceEntryScan") {
            return ServiceEntryPrefill(
                vendor: "Bosch Service",
                items: [
                    ServiceEntryItemDraft(title: "Ölservice inkl. Filter",
                                          category: .oil, cost: "89.00",
                                          scanned: true),
                    ServiceEntryItemDraft(title: "Bremsbeläge vorn",
                                          category: .brakes, cost: "59.00",
                                          scanned: true)
                ],
                odometer: OdometerFormat.grouped(118_930),
                date: ConfirmDate.parse("09.08.2026") ?? Date(),
                dateFromInvoice: true,
                pages: seedPages(),
                provenance: .receiptScan)
        }
        if arguments.contains("-seedServiceEntryScanLumpSum") {
            return ServiceEntryPrefill(
                vendor: "Bosch Service",
                items: [
                    ServiceEntryItemDraft(title: "Bosch Service",
                                          category: .other(""), cost: "148.00",
                                          scanned: true)
                ],
                odometer: OdometerFormat.grouped(118_930),
                date: ConfirmDate.parse("09.08.2026") ?? Date(),
                dateFromInvoice: true,
                pages: seedPages(),
                provenance: .receiptScan)
        }
        return nil
    }

    /// Three placeholder pages for the scan seeds (simctl cannot drive the
    /// document camera, so the strip renders generated page images).
    private static func seedPages() -> [InvoicePage] {
        let timestamp = Date(timeIntervalSince1970: 1_752_000_000)
        return (0..<3).map { index in
            let id = UUID.v7()
            let attachment = Attachment(
                id: id, createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
                kind: .photo,
                file: LocalFileRef(sha256: "seed-\(index)",
                                   relativePath: "\(id.uuidString).jpg"),
                extractedTimestamp: ConfirmDate.parse("09.08.2026"),
                ocrText: "seed page \(index + 1)")
            return InvoicePage(attachment: attachment, image: InvoicePagePreview.image())
        }
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
            || arguments.contains("-seedServiceEntryLumpSum")
            || arguments.contains("-seedServiceEntryScan")
            || arguments.contains("-seedServiceEntryScanLumpSum") else { return }
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
