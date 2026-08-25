import Foundation
import Testing
@testable import TankbookCore

/// P3.1b page/attachment lifecycle tests (docs/SCHEMA.md -> Attachment &
/// extraction provenance). The multi-page invariant: pages captured into one
/// record's attachments, `ocrText` retained per page for re-parsing, the
/// invoice's printed date landing on `extractedTimestamp`, and removing a page
/// leaving no orphaned file.
@Suite struct InvoicePageStoreTests {

    /// In-memory stand-in for the app's file store (the real one writes JPEGs
    /// under Application Support). Records writes and removals so the
    /// "no orphaned file" invariant is asserted, not assumed.
    private final class RecordingFiles: AttachmentFileManaging, @unchecked Sendable {
        private(set) var written: [LocalFileRef] = []
        private(set) var removed: [LocalFileRef] = []

        func write(_ data: Data, id: UUID) throws -> LocalFileRef {
            let ref = LocalFileRef(sha256: "sha-\(id.uuidString)",
                                   relativePath: "\(id.uuidString).jpg")
            written.append(ref)
            return ref
        }

        func remove(_ ref: LocalFileRef) throws {
            removed.append(ref)
        }
    }

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private func makeVehicle() -> Vehicle {
        let timestamp = Date(timeIntervalSince1970: 1_752_000_000)
        return Vehicle(
            id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
    }

    // MARK: - Multi-page

    @Test("three pages become three attachments; removing page two leaves two and orphans nothing")
    func multiPageRemovalLeavesNoOrphan() throws {
        let repository = try makeRepository()
        let files = RecordingFiles()
        let store = InvoicePageStore(repository: repository, files: files)

        let page1 = try store.addPage(imageData: Data([0x01]), ocrText: "page one", extractedTimestamp: nil)
        let page2 = try store.addPage(imageData: Data([0x02]), ocrText: "page two", extractedTimestamp: nil)
        let page3 = try store.addPage(imageData: Data([0x03]), ocrText: "page three", extractedTimestamp: nil)

        #expect(try repository.liveAttachments().count == 3)

        try store.removePage(page2)

        let remaining = try repository.liveAttachments()
        #expect(remaining.count == 2)
        #expect(remaining.map(\.id).sorted() == [page1.id, page3.id].sorted())
        // The removed page's file is gone; the others' are not touched.
        #expect(files.removed == [page2.file])
        #expect(files.written.count == 3)
    }

    // MARK: - ocrText and extractedTimestamp

    @Test("ocrText is retained per page and the printed date lands on extractedTimestamp")
    func ocrTextAndTimestampRetained() throws {
        let repository = try makeRepository()
        let store = InvoicePageStore(repository: repository, files: RecordingFiles())
        let printedDate = Date(timeIntervalSince1970: 1_752_000_000)

        let page = try store.addPage(imageData: Data([0x01]),
                                     ocrText: "Ölservice inkl. Filter 89.00",
                                     extractedTimestamp: printedDate)

        let read = try repository.liveAttachments()
        #expect(read.count == 1)
        #expect(read[0].ocrText == "Ölservice inkl. Filter 89.00")
        #expect(read[0].extractedTimestamp == printedDate)
        #expect(read[0].file == page.file)
    }

    @Test("a page with no readable date carries a nil extractedTimestamp")
    func missingTimestampStaysNil() throws {
        let repository = try makeRepository()
        let store = InvoicePageStore(repository: repository, files: RecordingFiles())

        let page = try store.addPage(imageData: Data([0x01]), ocrText: "no date here", extractedTimestamp: nil)

        let read = try repository.liveAttachments()
        #expect(read[0].extractedTimestamp == nil)
        #expect(read[0].id == page.id)
    }

    // MARK: - Linking pages to the record

    @Test("pages link to the ServiceRecord on save and the link round-trips")
    func pagesLinkToTheRecord() throws {
        let repository = try makeRepository()
        let vehicle = makeVehicle()
        try repository.upsertVehicle(vehicle)

        let files = RecordingFiles()
        let store = InvoicePageStore(repository: repository, files: files)
        let page1 = try store.addPage(imageData: Data([0x01]), ocrText: "a", extractedTimestamp: nil)
        let page2 = try store.addPage(imageData: Data([0x02]), ocrText: "b", extractedTimestamp: nil)

        let item = ServiceItem.make(
            title: "Annual service", category: .other(""),
            cost: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur))
        let draft = ServiceEntryDraft(
            vendor: "Bosch Service", items: [item],
            date: Date(timeIntervalSince1970: 1_752_000_000), odometer: 118_930,
            attachments: [page1.id, page2.id], provenance: .receiptScan)
        let record = draft.build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)

        try repository.upsertServiceRecord(record)

        let read = try repository.liveServiceRecords(forVehicle: vehicle.id)
        #expect(read.count == 1)
        #expect(read[0].attachments == [page1.id, page2.id])
        #expect(read[0].provenance == .receiptScan)
    }
}
