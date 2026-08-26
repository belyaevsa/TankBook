import CoreGraphics
import Foundation
import ImageIO
import TankbookCore

/// UI-test / screenshot seeding for the P4.6 "photo syncing" state: an entry
/// whose attachment's inline thumbnail has arrived (inside the record payload)
/// but whose full rendition blob has not landed - `relativePath` points at a
/// file that does not exist and the content-addressed cache has no entry, so
/// `BlobService.isBlobAvailable` is false and the receipt chip shimmers. The
/// entry is openable and editable throughout (hard rule 1).
enum PhotoSyncingTestSeed {
    @MainActor
    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedPhotoSyncing") else { return }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2021,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_579)
        try? repository.upsertVehicle(vehicle)

        let scannedAt = now.addingTimeInterval(-3600)
        let attachment = Attachment(
            id: UUID.v7(), createdAt: scannedAt, updatedAt: scannedAt, deletedAt: nil,
            kind: .photo,
            file: LocalFileRef(sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                               relativePath: "photos/pending/9f86d081.jpg"),
            extractedTimestamp: scannedAt,
            ocrText: "SHELL 71.02 42.30 1.679",
            thumbnailBase64: Self.thumbnailBase64())
        try? repository.upsertAttachment(attachment)

        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: scannedAt, updatedAt: scannedAt, deletedAt: nil,
            vehicleId: vehicle.id, date: scannedAt, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [attachment.id], provenance: .receiptScan, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil))
    }

    /// A real ~120px JPEG, base64 - the chip renders it, never a dead glyph.
    private static func thumbnailBase64() -> String? {
        guard let data = sampleJPEG() else { return nil }
        return try? AttachmentRendition.thumbnailBase64(for: data, kind: .photo)
    }

    /// A small grey receipt-shaped sample (two text bars) so the thumbnail is
    /// legible in a screenshot rather than a flat colour.
    private static func sampleJPEG() -> Data? {
        let size = 120
        guard let context = CGContext(data: nil, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(gray: 0.3, alpha: 1))
        context.fill(CGRect(x: 24, y: 34, width: 72, height: 10))
        context.fill(CGRect(x: 24, y: 56, width: 48, height: 10))
        context.fill(CGRect(x: 24, y: 78, width: 60, height: 10))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
