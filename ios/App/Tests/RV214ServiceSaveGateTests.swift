import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.214 - what names a service well enough to save on. The service CREATE
/// gate demanded a TITLED line item (`hasTitledItem`), but `EntryTitle`'s
/// service chain (RV.187) already names a service from its vendor, else its
/// first named line, else that line's category. So a vendor-only record and a
/// vendor-less untitled lump sum - the invoice splitter's honest fallback -
/// were nameable while Save stayed disabled.
///
/// The rule is one function both doors call (`ServiceEntryDraft.serviceSaveReadiness`,
/// RV.212's shape): a vendor or a line item makes the record, a wholly blank
/// service is refused. The tests drive the app's own form types and persist
/// through the same `ServiceEntryDraft.build` the create screen calls, then
/// assert the Log row the user would actually read - never merely that Save is
/// enabled (RV.206's vacuous trap one entry kind over).
@MainActor
final class RV214ServiceSaveGateTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeVehicle() throws -> (TankbookRepository, Vehicle) {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
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
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    /// The Log row the user reads, resolved through the one title chain
    /// (`EntryTitle`, RV.187) - the oracle for every save below.
    private func logRowTitle(_ entry: any Entry, vehicle: Vehicle) -> String? {
        let stream = LogStream(vehicle: vehicle, entries: [entry])
        let logEntry = stream.sections
            .flatMap(\.rows)
            .compactMap { row -> LogStream.LogEntry? in
                if case .entry(let value) = row { return value }
                return nil
            }
            .first
        return logEntry.map { EntryTitle.text($0, stations: []) }
    }

    private func save(_ form: ServiceEntryFormState, vehicle: Vehicle,
                      repository: TankbookRepository) throws -> ServiceRecord {
        let record = form.draft(vehicle: vehicle)
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
        try repository.upsertServiceRecord(record)
        return try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
    }

    // MARK: - L1, FAILS BEFORE THIS ROW: a vendor-only service is a record

    /// The gate's original reason was that a title was the only thing naming a
    /// service when it was written (P3.1a, `90ad0deb`). RV.187 added the vendor
    /// fallback, so a vendor alone names the row - and the vendor is content
    /// enough that the record is not blank. The vendor-only create form is the
    /// exact state `hasTitledItem` refused.
    func testAServiceWithOnlyAVendorIsSaveableAndItsLogRowReadsTheVendor() throws {
        let (repository, vehicle) = try makeVehicle()
        var form = ServiceEntryFormState()
        form.vendor = "Bosch Service"

        XCTAssertEqual(form.saveReadiness, .ready,
                       "a vendor names the service (RV.187) and is content - a title is not required")

        let saved = try save(form, vehicle: vehicle, repository: repository)
        XCTAssertEqual(saved.vendor, "Bosch Service")
        XCTAssertEqual(saved.items, [])
        XCTAssertEqual(logRowTitle(saved, vehicle: vehicle), "Bosch Service",
                       "the Log row must name the vendor-only service from its vendor")
    }

    // MARK: - L1: the vendor-less untitled lump sum is saveable

    /// The invoice splitter's honest fallback when the vendor did not read: one
    /// untitled line carrying the whole total, its `.other("")` category naming
    /// it "Other" (RV.187). The old gate blocked it; the new rule accepts it.
    func testAVendorlessUntitledLumpSumIsSaveableAndItsLogRowReadsTheCategory() throws {
        let (repository, vehicle) = try makeVehicle()
        var form = ServiceEntryFormState()
        form.items = [ServiceEntryItemDraft(title: "", category: .oil, cost: "148.00")]

        XCTAssertEqual(form.saveReadiness, .ready,
                       "an untitled line is named by its category (RV.187), so it is a record")

        let saved = try save(form, vehicle: vehicle, repository: repository)
        XCTAssertEqual(saved.vendor, nil)
        XCTAssertEqual(saved.items.first?.title, "")
        XCTAssertEqual(saved.items.first?.category, .oil)
        XCTAssertEqual(logRowTitle(saved, vehicle: vehicle), "Oil",
                       "the Log row must name the vendor-less lump sum from its category")
    }

    /// The same lump sum in the bare `.other("")` category renders "Other" - a
    /// real label, not the bare type name and not a blank row (RV.206's
    /// `.other("")` decision, one entry kind over).
    func testABareOtherLumpSumNamesTheSavedRowAsOther() throws {
        let (repository, vehicle) = try makeVehicle()
        var form = ServiceEntryFormState()
        form.items = [ServiceEntryItemDraft(title: "", category: .other(""), cost: "148.00")]

        XCTAssertEqual(form.saveReadiness, .ready)
        let saved = try save(form, vehicle: vehicle, repository: repository)
        XCTAssertEqual(logRowTitle(saved, vehicle: vehicle), "Other",
                       "the bare .other(\"\") still names the row 'Other'")
    }

    // MARK: - L1: the blank service is still refused, and the hint names the gap

    /// Deleting the gate outright is the vacuous trap. A service with no vendor,
    /// no items and no amount has no name and nothing to save, so it stays
    /// refused and the disabled-save hint names what is missing (hard rule 7).
    func testAWhollyBlankServiceIsRefusedAndTheHintNamesWhatIsMissing() {
        let form = ServiceEntryFormState()
        XCTAssertEqual(form.saveReadiness, .empty,
                       "a wholly blank service must not save as an empty record")
        XCTAssertEqual(form.saveHint, L10n.localize("Add a vendor or a line item to save"),
                       "the hint must name the missing vendor-or-line step, not the old title demand")
        XCTAssertFalse(form.saveHint?.isEmpty ?? true)
    }

    // MARK: - L1: create and edit apply the SAME rule

    /// The two doors call the one core function, asserted from both so they
    /// cannot drift: a vendor-only record and a blank record read identically on
    /// the create form and the edit form.
    func testCreateAndEditApplyTheSameRule() {
        var create = ServiceEntryFormState()
        create.vendor = "Bosch Service"
        var edit = EditEntryNonFillForm()
        edit.vendor = "Bosch Service"
        XCTAssertEqual(create.saveReadiness, edit.serviceSaveReadiness)
        XCTAssertEqual(create.saveReadiness, .ready)

        let blankCreate = ServiceEntryFormState()
        let blankEdit = EditEntryNonFillForm()
        XCTAssertEqual(blankCreate.saveReadiness, blankEdit.serviceSaveReadiness)
        XCTAssertEqual(blankCreate.saveReadiness, .empty)

        var titledCreate = ServiceEntryFormState()
        titledCreate.items = [ServiceEntryItemDraft(title: "Oil service", category: .oil)]
        var titledEdit = EditEntryNonFillForm()
        titledEdit.items = [ServiceEntryItemDraft(title: "Oil service", category: .oil)]
        XCTAssertEqual(titledCreate.saveReadiness, titledEdit.serviceSaveReadiness)
        XCTAssertEqual(titledCreate.saveReadiness, .ready)
    }

    /// The brief's exact shape one door over: a service with a vendor AND an
    /// amount and NO items. The edit screen has the independent Amount field, so
    /// this is where that record is reachable; it persists through the edit
    /// door's own write and the Log reads the vendor.
    func testTheEditDoorWritesAVendorAndAmountWithNoItemsAndTheLogReadsTheVendor() throws {
        let (repository, vehicle) = try makeVehicle()
        let now = Date()
        let original = ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: nil, money: nil, note: nil,
            attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: nil, items: [], usedParts: [],
            tireSetId: nil)
        try repository.upsertServiceRecord(original)

        var form = EditEntryNonFillForm()
        form.vendor = "Bosch Service"
        form.amount = "148.00"
        XCTAssertEqual(form.serviceSaveReadiness, .ready)
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let saved = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(saved.items, [])
        XCTAssertEqual(saved.money?.amount, Decimal(string: "148.00"),
                       "the amount persists with the vendor-only record")
        XCTAssertEqual(logRowTitle(saved, vehicle: vehicle), "Bosch Service",
                       "the edit door must write the vendor the Log names")
    }
}
