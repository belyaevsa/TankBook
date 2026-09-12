import TankbookCore
import XCTest
@testable import Tankbook

/// RV.246 - a late expense read carries the receipt's printed date, so the inbox
/// can offer a differing date. `ExpenseRecognition` used to carry the amount and
/// the category only; the date the form already pre-fills (`ExpensePrefill.date`)
/// now rides the same parse into `ExpenseRecognition.date`, one shape with the
/// service recognition. `Expense.date` is non-optional, so a differing date is
/// always an offered replacement, never a silent fill (hard rule 13).
@MainActor
final class RV246LateExpenseDateTests: XCTestCase {

    private func savedExpense(date: Date) -> Expense {
        let now = Date()
        return Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: nil,
            money: Money(amount: Decimal(string: "12.40")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: .accessory, title: "Shop")
    }

    /// The recognition the REAL Expense-mode read produces from a receipt whose
    /// printed date is `receiptDate`. This is the producer the inbox reads from;
    /// the test must not hand-build a recognition and leave the producer untested.
    private func recognition(receiptDate: String) -> InboxRecognition {
        let extraction = FuelExtraction(total: 20.00, currency: .eur, date: receiptDate)
        return .expense(ExpenseScanOutcome.recognition(from: extraction, preset: .parking))
    }

    func testADifferingReceiptDateIsOfferedFromTheRealRecognition() throws {
        let savedDay = try XCTUnwrap(ConfirmDate.parse("10.08.2026"))
        let entry = savedExpense(date: savedDay)

        let offers = GatewayInboxPolicy.offers(recognition: recognition(receiptDate: "17.08.2026"),
                                               entry: .expense(entry))

        XCTAssertTrue(offers.contains { $0.field == .date },
                      "an expense read with a differing receipt date must offer .date")
    }

    func testAnAgreeingReceiptDateIsNotOffered() throws {
        let savedDay = try XCTUnwrap(ConfirmDate.parse("17.08.2026"))
        let entry = savedExpense(date: savedDay)

        let offers = GatewayInboxPolicy.offers(recognition: recognition(receiptDate: "17.08.2026"),
                                               entry: .expense(entry))

        XCTAssertFalse(offers.contains { $0.field == .date },
                       "a receipt date on the saved day is agreement, not a decision")
    }

    func testTickingTheReceiptDateAppliesItToTheExpense() throws {
        let savedDay = try XCTUnwrap(ConfirmDate.parse("10.08.2026"))
        let receiptDay = try XCTUnwrap(ConfirmDate.parse("17.08.2026"))
        let entry = savedExpense(date: savedDay)

        let merged = GatewayInboxPolicy.merged(entry: .expense(entry),
                                               recognition: recognition(receiptDate: "17.08.2026"),
                                               taking: [.date])
        guard case .expense(let result) = merged else {
            XCTFail("an expense merge must stay an expense")
            return
        }
        XCTAssertEqual(result.date, receiptDay, "a ticked receipt date replaces the saved date")
    }

    /// The user's own date is never overwritten by the read: a differing date is
    /// offered as a SUGGESTION (a `.differs` disposition, never a fill), and
    /// nothing moves until the user ticks it (hard rule 13).
    func testAUserChangedDateIsOfferedAsASuggestionAndNeverApplied() throws {
        let savedDay = try XCTUnwrap(ConfirmDate.parse("10.08.2026"))
        let entry = savedExpense(date: savedDay)
        let recognition = recognition(receiptDate: "17.08.2026")

        let offers = GatewayInboxPolicy.offers(recognition: recognition, entry: .expense(entry))
        let dateOffer = try XCTUnwrap(offers.first { $0.field == .date })
        XCTAssertEqual(dateOffer.disposition, .differs,
                       "the user's own date is replaced only if they say so, never filled silently")

        let untouched = GatewayInboxPolicy.merged(entry: .expense(entry), recognition: recognition,
                                                  taking: [])
        guard case .expense(let kept) = untouched else {
            XCTFail("an expense merge must stay an expense")
            return
        }
        XCTAssertEqual(kept.date, savedDay,
                       "computing the offer must not move the date the user set by hand")
    }
}
