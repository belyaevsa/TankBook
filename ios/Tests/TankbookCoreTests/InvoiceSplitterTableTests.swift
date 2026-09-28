import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// An invoice read cell by cell (`service-004`, a Tireman tyre invoice): Vision
/// returns each table cell as its own line, the lines are net of tax and the
/// total is gross. The lines below are the OCR cells with their geometry, so
/// the row rebuild, the tax line and the vendor evidence run as they do on the
/// device.
@Suite("Invoice split over a cell-by-cell table (RV.320)")
struct InvoiceSplitterTableTests {
    private static func cell(_ text: String, y: CGFloat, x: CGFloat, width: CGFloat) -> OCRLine {
        OCRLine(text: text, confidence: 1, boundingBox: CGRect(x: x, y: y - 0.009, width: width, height: 0.018))
    }

    /// `service-004`'s cells, in Vision's own order (not reading order).
    static let tireman: [OCRLine] = [
        cell("Kommentaar: 004TXK", y: 0.942, x: 0.066, width: 0.171),
        cell("Kogus Ühikuhind % Müügi", y: 0.855, x: 0.566, width: 0.260),
        cell("Summa", y: 0.852, x: 0.872, width: 0.062),
        cell("Kood", y: 0.852, x: 0.066, width: 0.044),
        cell("Nimetus", y: 0.850, x: 0.161, width: 0.068),
        cell("hind", y: 0.839, x: 0.785, width: 0.041),
        cell("T18", y: 0.810, x: 0.066, width: 0.028),
        cell("60.48", y: 0.810, x: 0.893, width: 0.043),
        cell("18\" 4 rehvi täisvahetus", y: 0.809, x: 0.163, width: 0.162),
        cell("60.48", y: 0.809, x: 0.783, width: 0.043),
        cell("67.20 10", y: 0.809, x: 0.691, width: 0.073),
        cell("3.23", y: 0.781, x: 0.700, width: 0.034),
        cell("SART", y: 0.781, x: 0.066, width: 0.045),
        cell("3.23", y: 0.781, x: 0.790, width: 0.036),
        cell("Rehvitööde kulumaterjalid", y: 0.780, x: 0.163, width: 0.185),
        cell("3.23", y: 0.780, x: 0.901, width: 0.036),
        cell("Rehvide hoiustamine 1 hooaeg kuni 20\"", y: 0.752, x: 0.158, width: 0.292),
        cell("1", y: 0.752, x: 0.602, width: 0.009),
        cell("44.35", y: 0.751, x: 0.892, width: 0.045),
        cell("T0059", y: 0.751, x: 0.064, width: 0.048),
        cell("49.28 10", y: 0.751, x: 0.691, width: 0.073),
        cell("44.35", y: 0.749, x: 0.782, width: 0.044),
        cell("Volitatud isik:", y: 0.280, x: 0.066, width: 0.103),
        cell("108.06 EUR", y: 0.278, x: 0.840, width: 0.096),
        cell("Summa kokku km-ta:", y: 0.278, x: 0.661, width: 0.160),
        cell("25.94 EUR", y: 0.249, x: 0.849, width: 0.087),
        cell("Käibemaks 24%:", y: 0.248, x: 0.693, width: 0.133),
        cell("134.00 EUR", y: 0.220, x: 0.840, width: 0.096),
        cell("ARVE SUMMA:", y: 0.220, x: 0.700, width: 0.121),
        cell("Arve võttis vastu:", y: 0.219, x: 0.064, width: 0.131),
        cell("Maksekaardiga", y: 0.190, x: 0.822, width: 0.114),
        cell("Peterburi", y: 0.165, x: 0.865, width: 0.071),
        cell("Tasumistingimus:", y: 0.164, x: 0.689, width: 0.137),
        cell("keskus", y: 0.138, x: 0.877, width: 0.059),
        cell("Tasuda:", y: 0.109, x: 0.758, width: 0.068),
        cell("0.00 EUR", y: 0.109, x: 0.858, width: 0.078),
        cell("Marju Attemann", y: 0.107, x: 0.254, width: 0.117),
        cell("Arve väljastaja:", y: 0.107, x: 0.066, width: 0.110),
        cell("Email:", y: 0.080, x: 0.066, width: 0.048),
        cell("marju.attemann@tireman.ee", y: 0.079, x: 0.254, width: 0.208)
    ]

    @Test("the total is ARVE SUMMA, not the VAT or the net sum")
    func total() {
        #expect(InvoiceSplitter().split(lines: Self.tireman).total == Decimal(string: "134.00"))
    }

    @Test("three net rows and the VAT line add up to the total")
    func lines() {
        let split = InvoiceSplitter().split(lines: Self.tireman)
        #expect(!split.lumpSum)
        #expect(split.items.map(\.amount) == ["60.48", "3.23", "44.35", "25.94"].map { Decimal(string: $0)! })
        #expect(split.items[0].title == "T18 18\" 4 rehvi täisvahetus")
        #expect(split.items[2].title == "T0059 Rehvide hoiustamine 1 hooaeg kuni 20\"")
        #expect(split.items[3].title == "Käibemaks 24%")
        #expect(split.items[0].category == .tires)
    }

    @Test("the vendor is the issuer's domain, never the comment field")
    func vendor() {
        #expect(InvoiceSplitter().split(lines: Self.tireman).vendor == "Tireman")
    }

    @Test("two pages never share a row")
    func pagesKeepTheirRows() {
        let first = [Self.cell("Oil filter", y: 0.5, x: 0.1, width: 0.2)]
        let second = [Self.cell("12.40", y: 0.5, x: 0.8, width: 0.1)]
        let rows = InvoiceSplitter.rows(first) + InvoiceSplitter.rows(second)
        #expect(rows.map(\.text) == ["Oil filter", "12.40"])
        #expect(InvoiceSplitter.rows(first + second).map(\.text) == ["Oil filter  12.40"])
    }

    @Test("lines without geometry pass through in their order")
    func textOnly() {
        let lines = ["b", "a"].map { OCRLine(text: $0) }
        #expect(InvoiceSplitter.rows(lines) == lines)
    }
}
