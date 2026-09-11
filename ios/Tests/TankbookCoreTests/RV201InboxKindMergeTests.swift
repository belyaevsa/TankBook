import Foundation
import Testing
@testable import TankbookCore

// RV.201 - the inbox merge generalised over entry KIND. Before this row every
// function took `entry: FillUp`, so a service invoice or a shop receipt had
// nowhere to arrive late to and the per-field ask had nothing to offer them.
// This suite is the row's spine: it drives the SAME `GatewayInboxPolicy.merged`
// from a fill-up, a service and an expense in one file, so the three kinds
// cannot drift into three implementations. The model is
// `GatewayInboxPolicyTests`: pin WHICH state, never "a thing happened".
//
// The blank-vs-differs rule is hard rule 13: a blank fills, a DIFFERING value
// is offered and never applied without a tick. The service cases are the ones
// the RV.201 mutation turns red.

@Suite("RV.201 inbox merge over entry kind")
struct RV201InboxKindMergeTests {

    // MARK: - Fixtures

    private static let entryDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func savedFillUp(volume: Double = 42.30, unitPrice: Decimal? = 1.679) -> FillUp {
        let now = Date()
        return FillUp(
            id: UUID(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: UUID(), date: entryDate, odometer: 120_000,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: volume, unitPrice: unitPrice,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
    }

    private static func savedService(vendor: String? = "Old Garage",
                                     total: Decimal? = Decimal(string: "200.00")!,
                                     itemTitle: String = "Oil change") -> ServiceRecord {
        let now = Date()
        return ServiceRecord(
            id: UUID(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: UUID(), date: entryDate, odometer: 120_000,
            money: total.map { Money(amount: $0, currency: .eur, homeCurrency: .eur) },
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: vendor,
            items: [ServiceItem(title: itemTitle, category: .oil,
                                cost: Money(amount: Decimal(string: "80.00")!, currency: .eur, homeCurrency: .eur))],
            usedParts: [], tireSetId: nil)
    }

    private static func savedExpense(category: ExpenseCategory = .accessory) -> Expense {
        let now = Date()
        return Expense(
            id: UUID(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: UUID(), date: entryDate, odometer: nil,
            money: Money(amount: Decimal(string: "12.40")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: category, title: "Shop")
    }

    private static func fuelRecognition() -> InboxRecognition {
        .fuel(GatewayExtraction(
            total: .init(value: Decimal(string: "99.99")!, confidence: 0.92),
            volume: .init(value: 55.00, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.500")!, confidence: 0.88),
            fuelKind: .init(value: .diesel, confidence: 0.70),
            currency: .init(value: .eur, confidence: 0.60),
            pipeline: "test"))
    }

    /// A service reading that DIFFERS on vendor, line item and total, and agrees
    /// on date and currency.
    private static func serviceRecognition() -> InboxRecognition {
        .service(ServiceRecognition(
            vendor: .init(value: "New Garage", confidence: 0.9),
            total: .init(value: Decimal(string: "250.00")!, confidence: 0.9),
            currency: .init(value: .eur, confidence: 0.9),
            lineItems: [.init(title: "Brake pads", category: .brakes,
                              cost: Money(amount: Decimal(string: "120.00")!, currency: .eur, homeCurrency: .eur))]))
    }

    /// A service reading that only FILLS the blank vendor and line item, with no
    /// differing value.
    private static func serviceBlankFillingRecognition() -> InboxRecognition {
        .service(ServiceRecognition(
            vendor: .init(value: "New Garage", confidence: 0.9),
            total: .init(value: Decimal(string: "200.00")!, confidence: 0.9),
            currency: .init(value: .eur, confidence: 0.9),
            lineItems: [.init(title: "Oil change", category: .oil,
                              cost: Money(amount: Decimal(string: "80.00")!, currency: .eur, homeCurrency: .eur))]))
    }

    private static func expenseRecognition(category: ExpenseCategory = .parking,
                                           total: Decimal = Decimal(string: "12.40")!) -> InboxRecognition {
        .expense(ExpenseRecognition(
            total: .init(value: total, confidence: 0.9),
            category: .init(value: category, confidence: 0.8)))
    }

    // MARK: - The spine: ONE function over any entry kind

    @Test("the same merge serves a fill-up, a service and an expense")
    func oneMergeServesEveryKind() {
        // Fuel: tick the volume, leave the rest.
        let fuel = Self.savedFillUp()
        let fuelMerged = GatewayInboxPolicy.merged(entry: .fillUp(fuel),
                                                   recognition: Self.fuelRecognition(),
                                                   taking: [.volume])
        guard case .fillUp(let fuelResult) = fuelMerged else {
            Issue.record("a fuel recognition on a fill-up must stay a fill-up")
            return
        }
        #expect(fuelResult.volumeL == 55.00)

        // Service: tick the vendor, leave the rest.
        let service = Self.savedService()
        let serviceMerged = GatewayInboxPolicy.merged(entry: .service(service),
                                                      recognition: Self.serviceRecognition(),
                                                      taking: [.vendor])
        guard case .service(let serviceResult) = serviceMerged else {
            Issue.record("a service recognition on a service must stay a service")
            return
        }
        #expect(serviceResult.vendor == "New Garage")
        #expect(serviceResult.money?.amount == Decimal(string: "200.00")!,
                "an unticked total is not applied")

        // Expense: tick the category, leave the total.
        let expense = Self.savedExpense()
        let expenseMerged = GatewayInboxPolicy.merged(entry: .expense(expense),
                                                      recognition: Self.expenseRecognition(),
                                                      taking: [.category])
        guard case .expense(let expenseResult) = expenseMerged else {
            Issue.record("an expense recognition on an expense must stay an expense")
            return
        }
        #expect(expenseResult.category == .parking)
        #expect(expenseResult.money?.amount == Decimal(string: "12.40")!,
                "an unticked total is not applied")
    }

    // MARK: - A differing value is offered, never applied without a tick

    @Test("a differing service reading makes an item and applies nothing")
    func serviceDifferingReadingIsOfferedNotApplied() {
        let original = Self.savedService()
        let recognition = Self.serviceRecognition()
        #expect(GatewayInboxPolicy.shouldOffer(recognition: recognition, entry: .service(original)),
                "a differing service reading is worth an item")
        let item = GatewayInboxPolicy.item(recognition: recognition, entry: .service(original))
        #expect(item != nil, "the differing reading must produce an inbox item, not a write")

        // No tick: byte-identical, `updatedAt` included (hard rule 13).
        let untouched = GatewayInboxPolicy.merged(entry: .service(original),
                                                  recognition: recognition,
                                                  taking: [])
        #expect(untouched == .service(original),
                "a differing value with no tick must never be applied")

        // Tick the vendor: exactly that field moves.
        let merged = GatewayInboxPolicy.merged(entry: .service(original),
                                               recognition: recognition,
                                               taking: [.vendor])
        guard case .service(let result) = merged else { return }
        #expect(result.vendor == "New Garage")
        #expect(result.money?.amount == original.money?.amount, "an unticked total is untouched")
        #expect(result.items.map(\.title) == original.items.map(\.title), "an unticked line is untouched")
        #expect(result.updatedAt > original.updatedAt, "an applied change bumps updatedAt")
    }

    @Test("a blank service field fills under the existing rule")
    func serviceBlankFieldFills() {
        let blank = Self.savedService(vendor: nil)
        let recognition = Self.serviceBlankFillingRecognition()
        let offers = GatewayInboxPolicy.offers(recognition: recognition, entry: .service(blank))
        let vendor = offers.first { $0.field == .vendor }
        #expect(vendor?.disposition == .fillsBlank,
                "a blank vendor is a fill, not a replacement")

        let merged = GatewayInboxPolicy.merged(entry: .service(blank),
                                               recognition: recognition,
                                               taking: [.vendor])
        guard case .service(let result) = merged else { return }
        #expect(result.vendor == "New Garage")
        #expect(result.updatedAt > blank.updatedAt)
    }

    @Test("a differing expense category is offered and never applied without a tick")
    func expenseDifferingCategoryIsOfferedNotApplied() {
        let original = Self.savedExpense(category: .accessory)
        let recognition = Self.expenseRecognition(category: .parking)
        #expect(GatewayInboxPolicy.shouldOffer(recognition: recognition, entry: .expense(original)))
        #expect(GatewayInboxPolicy.item(recognition: recognition, entry: .expense(original)) != nil)

        let untouched = GatewayInboxPolicy.merged(entry: .expense(original),
                                                  recognition: recognition,
                                                  taking: [])
        #expect(untouched == .expense(original),
                "a differing category with no tick must never be applied")

        let merged = GatewayInboxPolicy.merged(entry: .expense(original),
                                               recognition: recognition,
                                               taking: [.category])
        guard case .expense(let result) = merged else { return }
        #expect(result.category == .parking)
    }

    @Test("declining leaves every kind byte-identical including updatedAt")
    func decliningLeavesEveryKindByteIdentical() {
        let fuel = Self.savedFillUp()
        let service = Self.savedService()
        let expense = Self.savedExpense()

        #expect(GatewayInboxPolicy.merged(entry: .fillUp(fuel),
                                          recognition: Self.fuelRecognition(),
                                          taking: []) == .fillUp(fuel))
        #expect(GatewayInboxPolicy.merged(entry: .service(service),
                                          recognition: Self.serviceRecognition(),
                                          taking: []) == .service(service))
        #expect(GatewayInboxPolicy.merged(entry: .expense(expense),
                                          recognition: Self.expenseRecognition(),
                                          taking: []) == .expense(expense))
    }

    @Test("a recognition of the wrong kind offers nothing")
    func mismatchedKindOffersNothing() {
        let service = Self.savedService()
        #expect(GatewayInboxPolicy.offers(recognition: Self.fuelRecognition(),
                                          entry: .service(service)).isEmpty,
                "a fuel reading on a service is a programming error, never an offer")
        #expect(GatewayInboxPolicy.item(recognition: Self.fuelRecognition(),
                                        entry: .service(service)) == nil)
    }

    @Test("a ticked service line item replaces only that line")
    func serviceLineItemMergeIsPerLine() {
        let original = Self.savedService()
        let recognition = Self.serviceRecognition()
        let merged = GatewayInboxPolicy.merged(entry: .service(original),
                                               recognition: recognition,
                                               taking: [.lineItem(0)])
        guard case .service(let result) = merged else { return }
        #expect(result.items.first?.title == "Brake pads")
        #expect(result.vendor == original.vendor, "an unticked vendor is untouched")
    }

    // MARK: - Durability: an item persisted before RV.201 still loads

    @Test("an item written in the pre-RV.201 shape decodes as a fuel recognition")
    func legacyPersistedItemDecodesAsFuel() throws {
        let entry = Self.savedFillUp()
        let extraction = GatewayExtraction(
            total: .init(value: Decimal(string: "99.99")!, confidence: 0.9),
            pipeline: "legacy")
        let extractionJSON = String(data: try JSONEncoder().encode(extraction), encoding: .utf8)!
        let json = """
        {"id":"\(UUID().uuidString)","entryId":"\(entry.id.uuidString)","createdAt":0,"extraction":\(extractionJSON)}
        """
        let item = try JSONDecoder().decode(GatewayInboxItem.self, from: Data(json.utf8))
        #expect(item.recognition == .fuel(extraction),
                "a pending item persisted before RV.201 must not be dropped on upgrade")
        #expect(item.entryId == entry.id)
    }
}
