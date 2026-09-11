import TankbookCore
import XCTest
@testable import Tankbook

/// RV.201 - the app-side half of the generalized inbox: the tick ids the UI
/// test keys on, `AppInbox.resolve` writing the RIGHT entity for the item's
/// kind, and a late answer for an entry that no longer exists being handled
/// rather than crashed. The merge itself is L1 in
/// `TankbookCoreTests/RV201InboxKindMergeTests`.
@MainActor
final class RV201InboxEntryKindTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        UserDefaults.standard.removeObject(forKey: AppInbox.storageKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: AppInbox.storageKey)
    }

    private func makeVehicle() throws -> (TankbookRepository, Vehicle) {
        let repository = try AppStore.repository()
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "RV201 Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    // MARK: - Distinct tick ids

    func testEveryOfferedFieldHasADistinctTickID() {
        let fields: [FieldRef] = [
            .date, .fuelKind, .volume, .unitPrice, .total, .currency,
            .station, .vendor, .energy, .category, .lineItem(0), .lineItem(1)
        ]
        let ids = fields.map { InboxValueFormat.tickID($0) }
        XCTAssertEqual(Set(ids).count, ids.count,
                       "two offered fields share a tick id, so a UI test could not tell them apart: \(ids)")
        XCTAssertEqual(InboxValueFormat.tickID(.vendor), "inboxTick_vendor")
        XCTAssertEqual(InboxValueFormat.tickID(.category), "inboxTick_category")
        XCTAssertEqual(InboxValueFormat.tickID(.lineItem(0)), "inboxTick_lineItem_0")
        XCTAssertEqual(InboxValueFormat.tickID(.lineItem(1)), "inboxTick_lineItem_1")
        XCTAssertNotEqual(InboxValueFormat.tickID(.vendor), InboxValueFormat.tickID(.category))
        XCTAssertFalse(ids.contains("inboxTick_other"),
                       "the old shared bucket must be gone")
    }

    // MARK: - resolve writes the right entity

    func testResolveWritesTheServiceEntity() throws {
        let (repository, vehicle) = try makeVehicle()
        let now = Date()
        let service = ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "200.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Old Garage", items: [], usedParts: [], tireSetId: nil)
        try repository.upsertServiceRecord(service)

        let recognition = InboxRecognition.service(ServiceRecognition(
            vendor: .init(value: "New Garage", confidence: 1.0)))
        let item = GatewayInboxItem(id: UUID.v7(), entryId: service.id, createdAt: now,
                                    recognition: recognition)
        let inbox = AppInbox(noteEntryChanged: {})
        inbox.resolve(item, as: .update(fields: [.vendor]))

        XCTAssertEqual(try repository.serviceRecord(id: service.id)?.vendor, "New Garage",
                       "an accepted service offer must write the ServiceRecord")
        XCTAssertNil(try repository.fillUp(id: service.id),
                     "resolve must not write a FillUp for a service item")
        XCTAssertTrue(inbox.isEmpty, "a resolved item clears")
    }

    func testResolveWritesTheExpenseEntity() throws {
        let (repository, vehicle) = try makeVehicle()
        let now = Date()
        let expense = Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: nil,
            money: Money(amount: Decimal(string: "12.40")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: .accessory, title: "Shop")
        try repository.upsertExpense(expense)

        let recognition = InboxRecognition.expense(ExpenseRecognition(
            category: .init(value: .parking, confidence: 1.0)))
        let item = GatewayInboxItem(id: UUID.v7(), entryId: expense.id, createdAt: now,
                                    recognition: recognition)
        let inbox = AppInbox(noteEntryChanged: {})
        inbox.resolve(item, as: .update(fields: [.category]))

        XCTAssertEqual(try repository.expense(id: expense.id)?.category, .parking,
                       "an accepted expense offer must write the Expense")
    }

    // MARK: - A late answer for an entry that no longer exists

    func testAnAnswerForAMissingEntryIsHandledNotCrashed() {
        let inbox = AppInbox(noteEntryChanged: {})
        let recognition = InboxRecognition.service(ServiceRecognition(
            vendor: .init(value: "New Garage", confidence: 1.0)))
        let item = GatewayInboxItem(id: UUID.v7(), entryId: UUID.v7(), createdAt: Date(),
                                    recognition: recognition)

        inbox.resolve(item, as: .update(fields: [.vendor]))
        XCTAssertTrue(inbox.isEmpty,
                      "the item clears even when its entry is gone - nothing is left pending forever")
    }

    // MARK: - The label table is shared, not a third one

    func testTheInboxLabelsComeFromTheOneSharedTable() {
        for field: FieldRef in [.vendor, .category, .lineItem(0), .total, .volume] {
            XCTAssertEqual(InboxValueFormat.label(field), FieldLabel.text(field),
                           "the inbox must not own a second label table (RV.201)")
        }
        XCTAssertFalse(FieldLabel.text(.vendor).isEmpty)
        XCTAssertFalse(FieldLabel.text(.category).isEmpty)
        XCTAssertFalse(FieldLabel.text(.lineItem(0)).isEmpty)
    }

    // MARK: - RV.216 the line-item label counts from one

    /// `FieldRef.lineItem` is an INDEX into `items`; the user counts from one, so
    /// only the label is offset. Both halves are asserted here - the displayed
    /// number AND the ref still addressing `items[0]` - because offsetting the ref
    /// itself would make the merge write the wrong line.
    func testLineItemLabelCountsFromOneWhileTheRefStaysAnIndex() throws {
        XCTAssertEqual(FieldLabel.text(.lineItem(0)),
                       String(format: L10n.localize("Row %@"), "1"),
                       "the first line is Row 1, not Row 0")
        XCTAssertEqual(FieldLabel.text(.lineItem(1)),
                       String(format: L10n.localize("Row %@"), "2"),
                       "the second line is Row 2")

        // The test runner loads one locale; read both catalog entries so the
        // words are pinned in EN and RU, where the label runs longest.
        let catalog = try Self.readCatalog()
        let en = try Self.localizedValue(catalog, key: "Row %@", language: "en")
        let ru = try Self.localizedValue(catalog, key: "Row %@", language: "ru")
        XCTAssertEqual(String(format: en, "1"), "Row 1")
        XCTAssertEqual(String(format: ru, "1"), "Строка 1")

        // `.lineItem(0)` still addresses the first saved item through the merge.
        let (repository, vehicle) = try makeVehicle()
        let now = Date()
        let service = ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "200.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Old Garage",
            items: [ServiceItem(title: "Oil change", category: .oil,
                                cost: Money(amount: Decimal(string: "80.00")!,
                                            currency: .eur, homeCurrency: .eur))],
            usedParts: [], tireSetId: nil)
        try repository.upsertServiceRecord(service)

        let recognition = InboxRecognition.service(ServiceRecognition(
            lineItems: [.init(title: "Brake pads", category: .brakes,
                              cost: Money(amount: Decimal(string: "120.00")!,
                                          currency: .eur, homeCurrency: .eur))]))
        let merged = GatewayInboxPolicy.merged(entry: .service(service),
                                               recognition: recognition,
                                               taking: [.lineItem(0)])
        guard case .service(let result) = merged else {
            XCTFail("a service merge must stay a service")
            return
        }
        XCTAssertEqual(result.items.first?.title, "Brake pads",
                       "the ref addresses items[0]; the 1-based label must not move it")
    }

    // MARK: - Catalog reading (the ServerErrorCodeL10nTests pattern)

    private static func readCatalog() throws -> [String: Any] {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        var candidate = thisFile.deletingLastPathComponent() // ios/App/Tests
        for _ in 0..<3 { candidate = candidate.deletingLastPathComponent() } // -> repo root
        let catalogURL = candidate.appendingPathComponent("ios/App/Sources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "cannot parse Localizable.xcstrings at \(catalogURL.path)")
    }

    private static func localizedValue(_ catalog: [String: Any],
                                       key: String,
                                       language: String) throws -> String {
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[key] as? [String: Any],
                                  "missing catalog key: \(key)")
        let localizations = entry["localizations"] as? [String: Any]
        let languageEntry = localizations?[language] as? [String: Any]
        let stringUnit = languageEntry?["stringUnit"] as? [String: Any]
        return try XCTUnwrap(stringUnit?["value"] as? String,
                             "missing \(language) value for \(key)")
    }
}
