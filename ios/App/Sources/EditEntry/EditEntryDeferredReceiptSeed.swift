#if DEBUG
import CoreGraphics
import Foundation
import SwiftUI
import TankbookCore
import UIKit

/// RV.243 screenshot seam: the entry a DEFERRED expense save writes. Kept out
/// of `EditEntryTestSeed.swift` (which sits at the linter's file-length ceiling)
/// the same way the service poses live in their own file. The photograph is
/// persisted from the capture staged at scan start, before the read resolved
/// anything (no OCR text, no extraction record), through the REAL save seam
/// (`ExpenseEntryView.writeExpense`) - so the frame is the shipped shape, not a
/// painted state. `-presentScreen editEntry` opens the newest entry, so this
/// expense is the only row.
enum EditEntryDeferredReceiptSeed {
    @MainActor
    static func seedIfRequested(arguments: [String]) {
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

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
        let image = renderer.image { context in
            UIColor(Theme.Palette.dash).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            UIColor(Theme.Palette.inkSoft).setFill()
            context.fill(CGRect(x: 120, y: 220, width: 660, height: 90))
            context.fill(CGRect(x: 120, y: 420, width: 660, height: 90))
            context.fill(CGRect(x: 120, y: 620, width: 660, height: 90))
        }
        // The capture the scan staged before its read finished - the photograph
        // alone, exactly what a save that beats the read holds.
        let session = ExpenseEntrySession()
        session.stageScan(image)
        guard let capture = session.consumePendingCapture() else { return }
        var form = ExpenseEntryFormState()
        form.category = .parts
        form.title = "Winter wiper blades"
        form.amount = "12.40"
        guard let amount = form.amountDecimal else { return }
        _ = try? ExpenseEntryView.writeExpense(
            form: form, vehicle: vehicle, amount: amount, scan: capture,
            repository: repository)
    }
}
#endif
