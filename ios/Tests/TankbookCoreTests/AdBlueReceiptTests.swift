import Foundation
import Testing
@testable import TankbookCore

/// An AdBlue line is never the fuel line (docs/EXTRACTION.md -> AdBlue): an
/// AdBlue-only receipt pre-fills a top-up, and a fuel + AdBlue receipt keeps
/// the fuel line for the fill and offers the AdBlue line as a top-up in the
/// purchase group.
@Suite("AdBlue on a receipt")
struct AdBlueReceiptTests {
    private func lines(_ texts: [String]) -> [OCRLine] { texts.map { OCRLine(text: $0) } }

    /// receipt-111 as Vision read it (Neste Vesse, Tallinn): the product prints
    /// as `ADBLUE` under `Toode:`, the operands on label-per-line rows.
    private let receipt111 = [
        "NESTE", "120 MESTE EXPRESS VESOE", "TALLINN,", "PETERBURI TEE 52", "NESTE FESTI AS",
        "SÖPRUSE PST. 155 TALLINN", "REG.NR. 10167511", "KMKR EE 100062906",
        "Kuupäev: 30.09.2026 14:35", "Kviitung Nr.", "913", "Terminal Nr:", "5", "Tankur Nr:", "07",
        "Toode:", "ADBLUE", "Hind:", "0,899 EUR/L", "Nogus L:", "5,75 L", "EUR kokku:", "5,19 EUR",
        "EUR KM 0%", "KM EUR", "EUR KOKKU", "24,00", "4,17", "1,00", "5,17", "Mobiilimakse 7487",
    ]

    /// A diesel receipt that also sold AdBlue, in both orders.
    private let dieselThenAdBlue = [
        "АЗС №12", "ДТ-Л-К5", "40.00 Л х 60.00 = 2400.00", "AdBlue", "10.00 Л х 89.90 = 899.00",
        "ИТОГ 3299.00",
    ]
    private let adBlueThenDiesel = [
        "АЗС №12", "AdBlue", "10.00 Л х 89.90 = 899.00", "ДТ-Л-К5", "40.00 Л х 60.00 = 2400.00",
        "ИТОГ 3299.00",
    ]

    @Test func theVocabularyNamesAdBlueAndNothingElse() {
        for text in ["ADBLUE", "AdBlue®", "Ad Blue 10L", "AUS 32", "Мочевина AdBlue", "Diesel Exhaust Fluid"] {
            #expect(AdBlueVocabulary.names(text), "\(text)")
        }
        for text in ["ДТ-Л-К5", "DIESEL", "Neste Futura 95", "BLUE CARD", "PADBLUEX"] {
            #expect(!AdBlueVocabulary.names(text), "\(text)")
        }
        #expect(!FuelExtractor.namesFuel("Diesel Exhaust Fluid"), "a fuel word inside an AdBlue name is not fuel")
    }

    @Test func anAdBlueOnlyReceiptIsATopUp() {
        let extraction = FuelExtractor().extract(lines: lines(receipt111))
        #expect(extraction.isAdBlue == true)
        #expect(extraction.fuelKind == nil)
        #expect(extraction.liters == 5.75)
        #expect(extraction.unitPrice == Decimal(string: "0.899"))
    }

    @Test func aFuelReceiptIsNotATopUp() {
        let extraction = FuelExtractor().extract(lines: lines([
            "АЗС №12", "ДТ-Л-К5", "40.00 Л х 60.00 = 2400.00", "ИТОГ 2400.00",
        ]))
        #expect(extraction.isAdBlue == nil)
        #expect(extraction.fuelKind == .diesel)
    }

    @Test(arguments: [true, false])
    func theFuelLineIsTheDieselLineInEitherOrder(adBlueFirst: Bool) throws {
        let receipt = lines(adBlueFirst ? adBlueThenDiesel : dieselThenAdBlue)
        let extraction = FuelExtractor().extract(lines: receipt)
        #expect(extraction.isAdBlue == nil, "a receipt with fuel on it is a fill-up")
        #expect(extraction.fuelKind == .diesel)
        #expect(extraction.liters == 40)
        #expect(extraction.unitPrice == Decimal(60))

        let detection = MixedReceiptDetector.detect(lines: receipt, extraction: extraction, qrAnchor: nil)
        guard case .mixed(let items, let fuelLine, _) = detection else {
            Issue.record("the AdBlue line makes the receipt mixed: \(detection)")
            return
        }
        #expect(fuelLine == Decimal(2400), "the fill-up records the diesel line, never the AdBlue line")
        let adBlue = try #require(items.first)
        #expect(items.count == 1)
        #expect(adBlue.isAdBlue)
        #expect(adBlue.adBlueLitres == 10)
        #expect(adBlue.unitPrice == Decimal(string: "89.9"))
        #expect(adBlue.amount == Decimal(899))
    }

    /// The AdBlue item ends at its own operand pair: a coffee printed after it
    /// is an expense line, never a second AdBlue top-up.
    @Test func theItemAfterTheAdBlueLineStaysItsOwnLine() {
        let receipt = lines(["DIESEL 42.30 л X 1.679", "ADBLUE", "10.00 л X 0.899",
                             "COFFEE L", "1 X 4.80", "84.81", "TOTAL", "84.81"])
        let extraction = FuelExtraction(liters: 42.30, unitPrice: Decimal(string: "1.679"), total: Decimal(string: "71.02"),
                                        currency: .eur, fuelKind: .diesel)
        let items = MixedReceiptDetector.detect(lines: receipt, extraction: extraction, qrAnchor: nil).lines
        #expect(items.map(\.isAdBlue) == [true, false])
        #expect(items.last?.title == "COFFEE L")
        #expect(items.first?.amount == Decimal(string: "8.99"))
    }

    @Test func anAcceptedAdBlueLineSavesAsATopUpInTheGroupNotAnExpense() throws {
        let receipt = lines(dieselThenAdBlue)
        let extraction = FuelExtractor().extract(lines: receipt)
        let detection = MixedReceiptDetector.detect(lines: receipt, extraction: extraction, qrAnchor: nil)
        let water = ReceiptLineItem(title: "Вода", amount: Decimal(129), category: .other("other"), isCarRelated: false)
        let detected = detection.lines + [water]
        let group = try #require(ReceiptGroupPlanner.plan(
            detection: .mixed(lines: detected, fuelLine: 2400, grandTotal: 3428),
            fillUpAmount: 2400, acceptedLineIDs: Set(detected.map(\.id))))
        let plan = ScannedSavePlan(attachmentID: UUID.v7(), provenance: .receiptScan, extraction: nil)
        let vehicle = UUID.v7()
        let station = UUID.v7()
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let money: (Decimal) -> Money = { Money(amount: $0, currency: .rub, homeCurrency: .rub) }

        let expenses = plan.expenses(from: group, vehicleId: vehicle, date: day, createdAt: day, money: money)
        let topUps = plan.adBlueFills(from: group, vehicleId: vehicle, date: day, odometer: 120_000,
                                      stationId: station, createdAt: day, money: money)
        #expect(expenses.map(\.title) == ["Вода"], "the AdBlue line is never an Expense")
        let topUp = try #require(topUps.first)
        #expect(topUps.count == 1)
        #expect(topUp.volumeL == 10)
        #expect(topUp.purchaseGroupId == group.purchaseGroupId)
        #expect(topUp.attachments == expenses[0].attachments, "the group shares one receipt photo")
        #expect(topUp.odometer == 120_000 && topUp.stationId == station, "the fill's own stop")
        #expect(topUp.money?.amount == Decimal(899))
    }
}
