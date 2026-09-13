import TankbookCore
import XCTest
@testable import Tankbook

/// RV.280 - a late expense read carries the currency the receipt was read in,
/// so a foreign figure is never offered as home money. `ExpenseRecognition`
/// used to carry the amount, the category and (since RV.246) the date, but no
/// currency; `expenseOffers` compared the foreign figure to the home amount and
/// `mergedExpense` applied it with `replacingAmount`, keeping the saved
/// currency (hard rule 3). The producer is the real Expense-mode read
/// (`ExpenseScanOutcome.recognition(from:preset:)`), never a hand-built
/// recognition, so the named mutation (passing `currency: nil` there) turns the
/// foreign-read offer red.
@MainActor
final class RV280LateExpenseCurrencyTests: XCTestCase {

    /// A saved expense in the home currency (EUR), as the typed path writes one.
    private func savedExpense() -> Expense {
        let now = Date()
        return Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: UUID.v7(), date: now, odometer: nil,
            money: Money(amount: Decimal(string: "12.40")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: .accessory, title: "Shop")
    }

    /// The recognition the REAL Expense-mode read produces from a receipt whose
    /// total is `total` in `currency`. This is the producer the inbox reads
    /// from; the test must not hand-build a recognition and leave it untested.
    private func recognition(total: String, currency: CurrencyCode,
                             receiptDate: String = "17.08.2026") -> InboxRecognition {
        let extraction = FuelExtraction(total: Decimal(string: total)!,
                                        currency: currency,
                                        date: receiptDate)
        return .expense(ExpenseScanOutcome.recognition(from: extraction, preset: .parking))
    }

    func testAForeignLateReadOffersTotalAndCurrencyFromTheRealRecognition() {
        let offers = GatewayInboxPolicy.offers(
            recognition: recognition(total: "20.00", currency: .pln),
            entry: .expense(savedExpense()))

        XCTAssertTrue(offers.contains { $0.field == .total },
                      "the read's foreign amount is still offered")
        XCTAssertTrue(offers.contains { $0.field == .currency },
                      "a foreign read must offer its currency, not present the figure as home money")
        XCTAssertEqual(offers.first { $0.field == .currency }?.disposition, .differs,
                       "the saved EUR pair and the read PLN pair disagree")
    }

    func testTakingBothYieldsAPairInTheReadsCurrencyAndResetsTheSnapshot() throws {
        let merged = GatewayInboxPolicy.merged(
            entry: .expense(savedExpense()),
            recognition: recognition(total: "20.00", currency: .pln),
            taking: [.total, .currency])
        guard case .expense(let result) = merged else {
            XCTFail("an expense merge must stay an expense")
            return
        }
        XCTAssertEqual(result.money?.amount, Decimal(string: "20.00")!)
        XCTAssertEqual(result.money?.currency, .pln,
                       "taking both halves leaves the pair in the read's currency")
        XCTAssertTrue(try XCTUnwrap(result.money).isRatePending,
                      "the old home snapshot no longer describes the pair - reset for re-conversion")
    }

    func testTakingTheTotalAloneKeepsTheEntrysCurrency() throws {
        let merged = GatewayInboxPolicy.merged(
            entry: .expense(savedExpense()),
            recognition: recognition(total: "20.00", currency: .pln),
            taking: [.total])
        guard case .expense(let result) = merged else {
            XCTFail("an expense merge must stay an expense")
            return
        }
        XCTAssertEqual(result.money?.amount, Decimal(string: "20.00")!)
        XCTAssertEqual(result.money?.currency, .eur,
                       "taking the amount alone must not move the entry's currency")
    }

    func testAnAgreeingCurrencyIsNotOffered() {
        let offers = GatewayInboxPolicy.offers(
            recognition: recognition(total: "20.00", currency: .eur),
            entry: .expense(savedExpense()))

        XCTAssertTrue(offers.contains { $0.field == .total },
                      "the differing amount is still a decision")
        XCTAssertFalse(offers.contains { $0.field == .currency },
                       "a read in the entry's own currency agrees - it is not a decision")
    }

    /// An inbox row persisted before RV.280 added the field has no `currency`
    /// key. It must decode with nil - "the read said nothing", the entry's own
    /// currency standing - never a guessed home currency (hard rule 3).
    func testARowPersistedBeforeTheFieldDecodesWithNilCurrency() throws {
        let original = ExpenseRecognition(
            total: .init(value: Decimal(string: "20.00")!, confidence: 0.9),
            currency: .init(value: .pln, confidence: 0.9),
            category: .init(value: .parking, confidence: 0.8))
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "currency")

        let decoded = try JSONDecoder().decode(
            ExpenseRecognition.self,
            from: try JSONSerialization.data(withJSONObject: object))

        XCTAssertNil(decoded.currency,
                     "a missing currency key means the read said nothing, never home")
        XCTAssertEqual(decoded.total?.value, Decimal(string: "20.00")!)
    }
}
