import Foundation
import Testing
@testable import TankbookCore

/// An Estonian tyre-shop invoice, as the phone read it: the grand total is
/// `ARVE SUMMA: 134.00 EUR`, beside a `Summa kokku km-ta` net (108.06) and a
/// `Tasuda` due amount (0.00, paid by card). As three primary reads the three
/// tied and the total abstained; and the `Kommentaar: 004TXK` line - the car's
/// plate - was taken as the station. Text and geometry are the invoice's.
@Suite("An Estonian invoice's ARVE SUMMA is its total")
struct PS88InvoiceTotalTests {
    private func line(_ text: String, _ x: CGFloat, _ y: CGFloat) -> OCRLine {
        OCRLine(text: text, boundingBox: CGRect(x: x, y: y, width: 0.15, height: 0.02))
    }

    private var footer: [OCRLine] {
        [
            line("Kommentaar: 004TXK", 0.07, 0.94),
            line("Summa kokku km-ta:", 0.66, 0.28), line("108.06 EUR", 0.85, 0.28),
            line("Käibemaks 24%:", 0.69, 0.25), line("25.94 EUR", 0.86, 0.25),
            line("ARVE SUMMA:", 0.70, 0.22), line("134.00 EUR", 0.84, 0.22),
            line("Tasumistingimus:", 0.67, 0.16), line("Maksekaardiga", 0.83, 0.175),
            line("Tasuda:", 0.76, 0.11), line("0.00 EUR", 0.86, 0.11)
        ]
    }

    @Test("the invoice total is 134.00")
    func arveSummaIsTheTotal() {
        #expect(FuelExtractor().extract(lines: footer).total == Decimal(string: "134.00"))
    }

    @Test("a comment line carrying a plate, and the VAT line, are never the station")
    func commentAndVATAreNotTheStation() {
        let station = StationNameExtractor.stationName(from: footer)
        #expect(station != "Kommentaar: 004TXK")
        #expect(station != "Käibemaks 24%:")
        #expect(StationNameExtractor.stationName(from: [line("Kommentaar: 004TXK", 0.07, 0.94)]) == nil)
    }

    /// The cropped invoice starts at its table: the first confident word the
    /// extractor used to take was the `Müügi` column header.
    private var tableHeader: [OCRLine] {
        [
            line("Müügi", 0.77, 0.85), line("Kood", 0.07, 0.84), line("Ühikuhind %", 0.65, 0.84),
            line("Summa", 0.87, 0.84), line("Nimetus", 0.16, 0.84), line("Kogus", 0.57, 0.84),
            line("Rehvitööde kulumaterjalid", 0.16, 0.77), line("SART", 0.07, 0.77),
            line("3.23", 0.70, 0.77), line("3.23", 0.90, 0.77)
        ]
    }

    @Test("a cropped invoice's table header and line items name no station")
    func tableCellsAreNotTheStation() {
        let found = StationNameExtractor.stationName(from: tableHeader + footer)
        #expect(found == nil, "took \(found ?? "")")
    }

    @Test("a station line on its own row is still the station, beside a table")
    func aStandaloneLineStillNamesTheStation() {
        let receipt = [line("Circle K Peterburi mnt teenindusjaam", 0.1, 0.95)] + tableHeader
        #expect(StationNameExtractor.stationName(from: receipt) == "Circle K Peterburi mnt teenindusjaam")
        // Two cells on a row (a brand and an address fragment) are not a table.
        let pair = [line("Olerex Peetri", 0.1, 0.95), line("Tallinn", 0.6, 0.95)]
        #expect(StationNameExtractor.stationName(from: pair) == "Olerex Peetri")
    }

    @Test("the net and the payment terms are not total labels")
    func netAndTermsAreNotTotals() {
        #expect(TotalLabel.classify("Summa kokku km-ta:") == nil)
        #expect(TotalLabel.classify("Tasumistingimus:") == nil)
        #expect(TotalLabel.classify("ARVE SUMMA:") == .document)
    }
}
