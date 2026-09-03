#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import TankbookCore

/// UI-test / screenshot seeding for the attachment states of the receipt strip.
///
/// - `-seedPhotoSyncing` (P4.6): the full rendition has NOT landed - the inline
///   thumbnail arrived inside the record payload, `relativePath` points at a
///   file that does not exist and the content-addressed cache has no entry, so
///   `BlobService.isBlobAvailable` is false, the chip shimmers and RV.9's
///   viewer opens on its "not on this device yet" state.
/// - `-seedPhotoLocal` (RV.9): the same entry with the full rendition written to
///   disk, so the viewer opens on the zoomable photo.
/// - `-seedPhotoPDF` (RV.9): the attachment is a PDF on disk - the state an
///   image view would render as a blank screen.
///
/// The entry is openable and editable in every one of them (hard rule 1).
enum PhotoSyncingTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        let variant: Variant?
        if arguments.contains("-seedPhotoSyncing") {
            variant = .syncing
        } else if arguments.contains("-seedPhotoLocal") {
            variant = .local
        } else if arguments.contains("-seedPhotoPDF") {
            variant = .pdf
        } else {
            variant = nil
        }
        guard let variant else { return }
        seed(variant)
    }

    enum Variant {
        case syncing
        case local
        case pdf
    }

    @MainActor
    private static func seed(_ variant: Variant) {
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
            kind: variant == .pdf ? .pdf : .photo,
            file: fileRef(for: variant),
            extractedTimestamp: scannedAt,
            ocrText: "SHELL 71.02 42.30 1.679",
            thumbnailBase64: variant == .pdf ? nil : Self.thumbnailBase64())
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

    /// The syncing variant points at a blob that is nowhere on the device; the
    /// other two write the real bytes and reference them by their own hash, so
    /// `BlobService.localData` finds them without a network round-trip.
    @MainActor
    private static func fileRef(for variant: Variant) -> LocalFileRef {
        switch variant {
        case .syncing:
            return LocalFileRef(
                sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                relativePath: "photos/pending/9f86d081.jpg")
        case .local, .pdf:
            let data = variant == .pdf ? samplePDF() : sampleJPEG(size: 900)
            guard let data, let saved = try? VehiclePhotoStore.save(data, id: UUID.v7()) else {
                return LocalFileRef(sha256: "", relativePath: "")
            }
            return LocalFileRef(sha256: saved.sha256, relativePath: saved.relativePath)
        }
    }

    /// A real ~120px JPEG, base64 - the chip renders it, never a dead glyph.
    private static func thumbnailBase64() -> String? {
        guard let data = sampleJPEG(size: 120) else { return nil }
        return try? AttachmentRendition.thumbnailBase64(for: data, kind: .photo)
    }

    /// A small grey receipt-shaped sample (text bars) so the thumbnail and the
    /// full rendition are legible in a screenshot rather than a flat colour.
    private static func sampleJPEG(size: Int) -> Data? {
        guard let context = CGContext(data: nil, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let scale = CGFloat(size) / 120
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(gray: 0.3, alpha: 1))
        for bar in [(34.0, 72.0), (56.0, 48.0), (78.0, 60.0)] {
            context.fill(CGRect(x: 24 * scale, y: bar.0 * scale,
                                width: bar.1 * scale, height: 10 * scale))
        }
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// A one-page PDF - the shape a service invoice is stored in
    /// (docs/SCHEMA.md), and the state an image view renders as nothing.
    private static func samplePDF() -> Data? {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else { return nil }
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(box)
        context.setFillColor(CGColor(gray: 0.25, alpha: 1))
        for bar in [700.0, 640.0, 580.0] {
            context.fill(CGRect(x: 60, y: bar, width: 380, height: 22))
        }
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }
}
#endif
