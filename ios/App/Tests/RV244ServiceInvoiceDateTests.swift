import TankbookCore
import XCTest
@testable import Tankbook

/// RV.244 - a late service read now carries the invoice date it parsed, so the
/// inbox can offer a differing date. `InvoiceSplitResult.date` is a `Date`; the
/// recognition used to want a raw `String` the scanner never produced, so the
/// offer was structurally impossible. The scanner now carries the parsed date
/// (one shape: a parsed date is a date) and the policy compares it by calendar
/// day.
@MainActor
final class RV244ServiceInvoiceDateTests: XCTestCase {

    private func savedService(date: Date) -> ServiceRecord {
        let now = Date()
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: 120_000,
            money: Money(amount: Decimal(string: "80.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Old Garage", items: [], usedParts: [], tireSetId: nil)
    }

    /// The recognition the REAL scanner produces from an invoice whose printed
    /// date is `invoiceDate`. This is the producer the inbox reads from - the
    /// test must not hand-build a recognition and leave the producer untested.
    private func recognition(invoiceDate: String) -> InboxRecognition {
        let split = InvoiceSplitter().split(textLines: [
            "Old Garage",
            invoiceDate,
            "Oil change 80.00",
            "TOTAL 80.00"
        ])
        return .service(ServiceInvoiceScanner.recognition(from: split, homeCurrency: .eur))
    }

    func testADifferingInvoiceDateIsOfferedFromTheRealScanner() throws {
        let savedDay = try XCTUnwrap(ConfirmDate.parse("10.08.2026"))
        let entry = savedService(date: savedDay)

        let offers = GatewayInboxPolicy.offers(recognition: recognition(invoiceDate: "17.08.2026"),
                                               entry: .service(entry))

        XCTAssertTrue(offers.contains { $0.field == .date },
                      "a service read with a differing invoice date must offer .date")
    }

    func testAnAgreeingInvoiceDateIsNotOffered() throws {
        let savedDay = try XCTUnwrap(ConfirmDate.parse("17.08.2026"))
        let entry = savedService(date: savedDay)

        let offers = GatewayInboxPolicy.offers(recognition: recognition(invoiceDate: "17.08.2026"),
                                               entry: .service(entry))

        XCTAssertFalse(offers.contains { $0.field == .date },
                       "an invoice date on the saved day is agreement, not a decision")
    }

    func testTickingTheInvoiceDateAppliesItToTheRecord() throws {
        let savedDay = try XCTUnwrap(ConfirmDate.parse("10.08.2026"))
        let invoiceDay = try XCTUnwrap(ConfirmDate.parse("17.08.2026"))
        let entry = savedService(date: savedDay)

        let merged = GatewayInboxPolicy.merged(entry: .service(entry),
                                               recognition: recognition(invoiceDate: "17.08.2026"),
                                               taking: [.date])
        guard case .service(let result) = merged else {
            XCTFail("a service merge must stay a service")
            return
        }
        XCTAssertEqual(result.date, invoiceDay, "a ticked invoice date replaces the saved date")
    }
}
