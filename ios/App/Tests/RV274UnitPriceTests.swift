import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.274 - the last readers of a stored per-litre price. RV.234 made the price
/// LABELS per the car's volume unit and RV.272 built `displayUnitPrice` for the
/// Confirm pre-fill, but the recognised page and the inbox comparison still
/// printed the stored per-litre figure under that per-gallon label. These L1
/// selectors fail on the litre figure.
final class RV274UnitPriceTests: XCTestCase {

    private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

    private func fillUp(unitPrice: Decimal?) -> FillUp {
        let now = Date()
        return FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: UUID.v7(), date: now, odometer: 120_000,
            money: Money(amount: decimal("71.02"), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: unitPrice,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil)
    }

    // MARK: - The recognised page (AttachmentValueFormat)

    /// The stored price is per litre by contract; the row's label is the car's
    /// own unit, so a gallons car must read the per-gallon price.
    func testRecognisedPageUnitPriceConvertsToTheCarsUnit() throws {
        let meta = ExtractionMeta(fields: [
            .unitPrice: FieldExtraction(cropRect: nil, confidence: 0.9, userCorrected: false,
                                        value: .money(decimal("1.679"))),
            .currency: FieldExtraction(cropRect: nil, confidence: 0.9, userCorrected: false,
                                       value: .currency(.eur))
        ], pipeline: "test")

        let us = AttachmentValueFormat.rows(from: meta, volumeUnit: .galUS)
        guard case .numeric(let figure, let unit)? = us.first(where: { $0.ref == .unitPrice })?.value else {
            return XCTFail("the unit price row must render as a numeric figure")
        }
        XCTAssertEqual(figure, "6.356", "a stored 1.679 €/L must read 6.356 per US gallon")
        XCTAssertEqual(unit, "€")

        let metric = AttachmentValueFormat.rows(from: meta, volumeUnit: .l)
        guard case .numeric(let metricFigure, _)? = metric.first(where: { $0.ref == .unitPrice })?.value else {
            return XCTFail("the metric unit price row must render")
        }
        XCTAssertEqual(metricFigure, "1.679", "metric is unchanged")
    }

    // MARK: - The inbox comparison (InboxValueFormat)

    /// The user's saved price is stored per litre; the row's label is per the
    /// car's unit.
    func testInboxYoursUnitPriceConvertsToTheCarsUnit() {
        let entry = InboxEntry.fillUp(fillUp(unitPrice: decimal("1.679")))
        XCTAssertEqual(InboxValueFormat.yours(.unitPrice, entry: entry, volumeUnit: .galUS),
                       "6.356\u{00A0}€", "the saved 1.679 €/L must read per US gallon")
        XCTAssertEqual(InboxValueFormat.yours(.unitPrice, entry: entry, volumeUnit: .l),
                       "1.679\u{00A0}€", "metric is unchanged")
    }

    /// The receipt's reading is normalized to a per-litre price by the extractor;
    /// the row renders the car's own unit.
    func testInboxReceiptUnitPriceConvertsToTheCarsUnit() {
        let entry = InboxEntry.fillUp(fillUp(unitPrice: nil))
        let extraction = GatewayExtraction(
            unitPrice: .init(value: decimal("1.679"), confidence: 0.9),
            currency: .init(value: .eur, confidence: 0.9),
            pipeline: "seed")
        let recognition = InboxRecognition.fuel(extraction)
        XCTAssertEqual(
            InboxValueFormat.receipt(.unitPrice, entry: entry, recognition: recognition, volumeUnit: .galUS),
            "6.356\u{00A0}€", "the receipt's 1.679 €/L must read per US gallon")
        XCTAssertEqual(
            InboxValueFormat.receipt(.unitPrice, entry: entry, recognition: recognition, volumeUnit: .l),
            "1.679\u{00A0}€", "metric is unchanged")
    }
}
