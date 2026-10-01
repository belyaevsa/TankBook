import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// PJ.41 - "Add expense from this receipt": an expense added later to a logged
/// receipt shares that receipt's photo by reference and its purchase group, so
/// the Log shows one purchase. Driven through the same save seam the Expense
/// sheet calls (`ExpenseEntryView.writeExpense`) and read back from the store.
@MainActor
final class PJ41ExpenseFromReceiptTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_789_000_000)

    private func makeStore() throws -> (TankbookRepository, Vehicle) {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: day, updatedAt: day, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    /// A logged fill-up with one receipt photo, optionally already in a group.
    private func makeSource(_ repository: TankbookRepository, vehicle: Vehicle,
                            group: UUID? = nil) throws -> (FillUp, Attachment) {
        let attachment = Attachment(id: UUID.v7(), createdAt: day, updatedAt: day,
                                    deletedAt: nil, kind: .photo,
                                    file: LocalFileRef(sha256: "sha", relativePath: "receipt.jpg"),
                                    extractedTimestamp: day, ocrText: nil)
        try repository.upsertAttachment(attachment)
        let fill = FillUp(id: UUID.v7(), createdAt: day, updatedAt: day, deletedAt: nil,
                          vehicleId: vehicle.id, date: day, odometer: 119_000,
                          money: Money(amount: Decimal(string: "71.02")!, currency: .eur,
                                       homeCurrency: .eur),
                          note: nil, attachments: [attachment.id], provenance: .receiptScan,
                          conflict: .none, purchaseGroupId: group, volumeL: 42.3,
                          unitPrice: Decimal(string: "1.679")!, fuelKind: .petrol95,
                          fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
                          stationId: nil, crossCheck: .verified, extraction: nil)
        try repository.upsertFillUp(fill)
        return (fill, attachment)
    }

    private func carWashForm() -> ExpenseEntryFormState {
        var form = ExpenseEntryFormState()
        form.category = .accessory
        form.amount = "12.50"
        form.currency = .eur
        form.date = day
        return form
    }

    private func storedSource(_ repository: TankbookRepository, vehicle: Vehicle, id: UUID) throws -> (any Entry)? {
        try repository.liveEntries(forVehicle: vehicle.id).first { $0.id == id }
    }

    /// The source had no group: the save makes one and writes it to BOTH rows.
    /// Oracle: the group id read back from the store for each of the two rows.
    func testASourceWithoutAGroupAndTheExpenseShareANewOne() throws {
        let (repository, vehicle) = try makeStore()
        let (fill, _) = try makeSource(repository, vehicle: vehicle)
        let link = ExpenseReceiptLink(source: fill)

        let (expense, _) = try ExpenseEntryView.writeExpense(
            form: carWashForm(), vehicle: vehicle, amount: Decimal(string: "12.50")!,
            scan: nil, repository: repository, receiptLink: link)

        let group = try XCTUnwrap(expense.purchaseGroupId, "the expense joins a purchase group")
        let source = try XCTUnwrap(try storedSource(repository, vehicle: vehicle, id: fill.id))
        XCTAssertEqual(source.purchaseGroupId, group,
                       "the source joins the SAME group, or the Log shows two separate moments")
    }

    /// The source already had a group: the expense joins it and the source is not rewritten.
    func testASourceThatHasAGroupKeepsItAndTheExpenseJoinsIt() throws {
        let (repository, vehicle) = try makeStore()
        let existing = UUID.v7()
        let (fill, _) = try makeSource(repository, vehicle: vehicle, group: existing)

        let (expense, _) = try ExpenseEntryView.writeExpense(
            form: carWashForm(), vehicle: vehicle, amount: Decimal(string: "12.50")!,
            scan: nil, repository: repository, receiptLink: ExpenseReceiptLink(source: fill))

        XCTAssertEqual(expense.purchaseGroupId, existing)
        let source = try XCTUnwrap(try storedSource(repository, vehicle: vehicle, id: fill.id))
        XCTAssertEqual(source.purchaseGroupId, existing)
        XCTAssertEqual(source.updatedAt, fill.updatedAt, "an already-grouped source is not rewritten")
    }

    /// The photo is shared by reference: the expense carries the source's
    /// attachment id and no second attachment row is stored.
    func testTheExpenseReferencesTheSameReceiptPhotoAndStoresNoCopy() throws {
        let (repository, vehicle) = try makeStore()
        let (fill, attachment) = try makeSource(repository, vehicle: vehicle)
        let before = try repository.liveAttachments().count

        let (expense, _) = try ExpenseEntryView.writeExpense(
            form: carWashForm(), vehicle: vehicle, amount: Decimal(string: "12.50")!,
            scan: nil, repository: repository, receiptLink: ExpenseReceiptLink(source: fill))

        XCTAssertEqual(expense.attachments, [attachment.id])
        XCTAssertEqual(try repository.liveAttachments().count, before, "no second copy of the photo")
    }

    /// Opening the form stages a link and writes nothing: a cancelled expense
    /// leaves the source without a group.
    func testStagingTheLinkWritesNothing() throws {
        let (repository, vehicle) = try makeStore()
        let (fill, _) = try makeSource(repository, vehicle: vehicle)
        _ = ExpenseReceiptLink(source: fill)

        let source = try XCTUnwrap(try storedSource(repository, vehicle: vehicle, id: fill.id))
        XCTAssertNil(source.purchaseGroupId)
        XCTAssertEqual(try repository.liveEntries(forVehicle: vehicle.id).count, 1)
    }

    /// The Log renders the two as ONE purchase.
    func testTheLogShowsTheFillUpAndTheExpenseAsOnePurchase() throws {
        let (repository, vehicle) = try makeStore()
        let (fill, _) = try makeSource(repository, vehicle: vehicle)
        _ = try ExpenseEntryView.writeExpense(
            form: carWashForm(), vehicle: vehicle, amount: Decimal(string: "12.50")!,
            scan: nil, repository: repository, receiptLink: ExpenseReceiptLink(source: fill))

        let stream = LogStream(vehicle: vehicle,
                               entries: try repository.liveEntries(forVehicle: vehicle.id))
        let groups = stream.sections.flatMap(\.rows).compactMap { row -> LogStream.LogGroup? in
            if case .group(let group) = row { return group }
            return nil
        }
        XCTAssertEqual(groups.count, 1, "one grouped purchase")
        XCTAssertEqual(groups.first?.members.count, 2)
    }
}
