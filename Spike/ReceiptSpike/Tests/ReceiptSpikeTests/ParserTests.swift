import Testing
@testable import ReceiptSpike

@Suite struct ParserTests {
    let parser = FuelReceiptParser()

    @Test func germanReceipt() {
        let lines = [
            "SHELL STATION 1234",
            "Datum: 12.08.2026 14:32",
            "SuperPlus E5",
            "Menge: 42,30 L",
            "Preis: 1,679 EUR/L",
            "GESAMT EUR 71,02",
            "MwSt 19% 11,34",
        ]
        let r = parser.parse(lines: lines)
        #expect(r.liters == 42.30)
        #expect(r.unitPrice == 1.679)
        #expect(r.total == 71.02)
        #expect(r.currency == "EUR")
        #expect(r.fuelType == "E5")
        #expect(r.date == "12.08.2026")
        #expect(r.crossCheckPassed)
    }

    @Test func polishReceipt() {
        let lines = [
            "ORLEN STACJA 55",
            "PB95 38,00 l x 6,12 zl",
            "RAZEM PLN 232,56",
        ]
        let r = parser.parse(lines: lines)
        #expect(r.liters == 38.0)
        #expect(r.unitPrice == 6.12)
        #expect(r.total == 232.56)
        #expect(r.currency == "PLN")
        #expect(r.crossCheckPassed)
    }

    @Test func pumpDisplayNoKeywords() {
        // A pump display often OCRs to bare numbers, no labels at all.
        let lines = ["71.02", "42.30", "1.679"]
        let r = parser.parse(lines: lines)
        #expect(r.liters == 42.30)
        #expect(r.unitPrice == 1.679)
        #expect(r.total == 71.02)
        #expect(r.crossCheckPassed)
    }

    @Test func thousandsGrouping() {
        #expect(parser.decimals(in: "1 234,56") == [1234.56])
        #expect(parser.decimals(in: "1.234,56") == [1234.56])
        #expect(parser.decimals(in: "SUMA 232,56 PLN") == [232.56])
    }

    @Test func crossCheckRejectsMismatch() {
        let r = FuelExtraction(liters: 40, unitPrice: 1.7, total: 71.02)
        #expect(!r.crossCheckPassed)
    }
}
