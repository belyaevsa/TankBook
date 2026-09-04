import Foundation
import Testing
@testable import TankbookCore

// RV.56 - the three unanimous fixes, pinned per fixture. Every test below is
// driven through the REAL extractor with the OCR lines quoted exactly as
// `diagnostics/receipt-ocr-lines.txt` shows them (misreads included), and each
// asserts the VALUE, never merely "non-nil": a field that is right for the
// wrong reason would otherwise pass.
//
// Three of the fixes are GEOMETRY-dependent - the leading-minus rejection and
// the net-versus-gross redundancy fallback both only fire when Vision's
// bounding boxes place a value on the label's baseline - so those get explicit
// `extract(lines:)` tests with real coordinates. A text-line test whose line
// would parse the same without the fix is the vacuous trap the brief warns
// against, and this file avoids it.

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

private func close(_ value: Decimal?, _ expected: String) -> Bool {
    guard let value else { return false }
    return abs(value - decimal(expected)) < decimal("0.005")
}

/// A line whose bounding box centres on (`midX`, `midY`), matching the
/// `[y= x= w=]` columns of the diagnostics dump (which print `midY`/`midX`).
private func line(_ text: String, midY: CGFloat, midX: CGFloat) -> OCRLine {
    OCRLine(text: text, boundingBox: CGRect(x: midX - 0.05, y: midY - 0.025,
                                            width: 0.1, height: 0.05))
}

// MARK: - 1. The zero-operand guard (receipt-034)

@Suite("RV.56: the zero-operand guard")
struct RV56ZeroOperandTests {

    /// `30.61 Х 0.00` under "Цена определена договором": exactly one operand is
    /// a printed zero, which names the PRICE, never the volume. The volume is
    /// the one certain number on the line; the price stays nil. This is the
    /// guard that also closes the live trap where ladder step 3 (the user's own
    /// price history) would otherwise return a zero-litre fill at a price that
    /// is really a volume.
    @Test("receipt-034: a zero operand names the price; the volume survives")
    func zeroOperandNamesPrice() {
        let lines = [
            "ТРК №8 Бензин автомобильный ЭКТО",
            "Plus (AИ-95-К5), л",
            "30.61 Х 0.00",
            "Е0.00.НДС 22%",
            "Цена определена договором",
            "ИТОГ",
            "0.00"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.liters == 30.61, "the non-zero operand is the volume")
        #expect(result.unitPrice == nil, "the printed zero is not a price")
        #expect(result.total == nil, "the printed zero total is not money")
    }

    /// A `0,00L`-marked void (receipt-039's shape) is a zero VOLUME, not a zero
    /// price: the marker path resolves it and the zero-litres guard nils it.
    @Test("a marked zero volume is a void, never a zero-litre fill")
    func markedZeroVolumeIsVoid() {
        let result = FuelExtractor().extract(textLines: ["0,00L", "1,744 EUR/L"])
        #expect(result.liters == nil)
        #expect(result.unitPrice == decimal("1.744"))
    }
}

// MARK: - 2. The leading-minus disambiguator (receipt-018)

@Suite("RV.56: a leading minus is never a total")
struct RV56LeadingMinusTests {

    /// The real geometry: `ИТОГ` shares a baseline with `-3555.89` (its
    /// `СУММА НДС` amount) while the real total `=19719.00` sits one row ABOVE.
    /// `NumberScanner.value` silently drops the sign, so the value finder must
    /// reject a `-`-prefixed line itself.
    @Test("receipt-018: the VAT line begins with a minus and is not the total")
    func leadingMinusIsNotATotal() {
        let lines: [OCRLine] = [
            line("1 АЙ-100-KS АЙ-100-K5 (3 ТРК)", midY: 0.646, midX: 0.501),
            line("=19719.00", midY: 0.584, midX: 0.675),
            line("ИТОГ", midY: 0.570, midX: 0.406),
            line("-3555.89", midY: 0.563, midX: 0.725),
            line("СУММА НДС 22%", midY: 0.551, midX: 0.436),
            line("=19719.00", midY: 0.547, midX: 0.722),
            line("НАЛИЧНЫМИ", midY: 0.534, midX: 0.415),
            line("=19719.00", midY: 0.529, midX: 0.723)
        ]
        let result = FuelExtractor().extract(lines: lines)
        #expect(result.total == decimal("19719.00"),
                "the value above the label is the total, the VAT line is not")
    }

    /// The same fixture through the plain-text convenience path, quoting the
    /// dump verbatim. This pins the VALUE even where the geometry test pins the
    /// mechanism.
    @Test("receipt-018 text lines resolve the total, not the VAT line")
    func leadingMinusTextLines() {
        let lines = [
            "кассовый чек", "наличный расчет", "1 АЙ-100-KS АЙ-100-K5 (3 ТРК)",
            "л-19719.00", "450.00*43.820", "НДС 22%", "ПОДАКЦИЗНЫЙ ТОВАР",
            "=19719.00", "ИТОГ", "-3555.89", "СУММА НДС 22%", "=19719.00",
            "НАЛИЧНЫМИ", "=19719.00", "ПОЛУЧЕНО НАПИЧНЫМИ"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.total == decimal("19719.00"))
    }
}

// MARK: - 3. The discount-aware total (receipt-017)

@Suite("RV.56: the discount line between extension and total")
struct RV56DiscountTests {

    /// `ИТОГ:` pairs with the pre-discount extension `=961.80` while the charged
    /// `=961.00` prints beside `СКИДКА =-0.80`. The charged figure is the total.
    @Test("receipt-017: the discounted total wins over the pre-discount extension")
    func discountedTotalWins() {
        let lines = [
            "ТРК-6 ДТ-Е-К5 Танеко", "=961.80 РУБ", "48.09 X 20", "=160.30 РУБ",
            "НДС 20%", "=961.80 РУБ", "ИТОГ:", "=961.00 РУБ", "СКИДКА =-0.80 РУБ",
            "#160.30 РУБ", "СУММА НДС 20%", "=961.00 РУБ", "НАЛИЧНЫМИ:"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.total == decimal("961.00"),
                "961.80 minus the printed 0.80 discount is the charged total")
    }

    /// A discount that reconciles NOTHING must not change the total: the
    /// reconciliation only fires when the discounted value is actually printed.
    @Test("a discount line alone does not move an unrelated total")
    func discountReconciliationDoesNotFireSpuriously() {
        let lines = ["ИТОГ", "4334.00", "В ТОМ ЧИСЛЕ ВАША СКИДКА = 0.83", "ОКРУГЛЕНИЕ", "0.83"]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.total == decimal("4334.00"))
    }
}

// MARK: - 4. Net versus gross (receipt-001, receipt-038)

@Suite("RV.56: the Estonian net-versus-gross total")
struct RV56NetGrossTests {

    /// The real geometry of receipt-001: `KOKKU` shares its baseline with the
    /// `KÄIBEMAKSUTA` net `100,98`, the gross `125,22` sits one row up, and the
    /// `Käibemaks kokku` VAT line poisons the modal into an unbreakable tie. The
    /// redundancy fallback then picks the gross - printed four times.
    @Test("receipt-001: the gross total wins over the net and the VAT")
    func receipt001GrossWins() {
        let lines: [OCRLine] = [
            line("125,22", midY: 0.713, midX: 0.613),
            line("125,22", midY: 0.650, midX: 0.618),
            line("KOKKU", midY: 0.636, midX: 0.329),
            line("100,98", midY: 0.630, midX: 0.546),
            line("125,22 EUR", midY: 0.620, midX: 0.643),
            line("KK MAKSE", midY: 0.606, midX: 0.328),
            line("24,24", midY: 0.574, midX: 0.629),
            line("24,24", midY: 0.559, midX: 0.630),
            line("Käibemaks kokku", midY: 0.551, midX: 0.368)
        ]
        let result = FuelExtractor().extract(lines: lines)
        #expect(result.total == decimal("125.22"))
    }

    /// The same fixture through the verbatim text lines: the gross repeats and
    /// wins regardless of the pairing path.
    @Test("receipt-001 text lines resolve the gross total")
    func receipt001TextLines() {
        let lines = [
            "Summa", "1", "Kogus", "125,22", "kirjeldus", "67,00L", "D BÓ miles",
            "EUR/L", "1,869", "4 Hind", "Pump", "-1,01 EUR", "EXTRA SOODUS",
            "125,22", "KOKKU", "100,98", "KAIBEMAKSUTA", "125,22 EUR", "KK MAKSE",
            "Summa", "Kood", "Määr", "Käibemaks", "24,24", "1", "24,00%",
            "24% KM", "24,24", "Käibemaks kokku"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.total == decimal("125.22"))
    }

    /// receipt-038's shape: two `Summa` labels pair with the gross `79,32` and
    /// the VAT `15,35`, tying the modal; the gross prints four times and wins
    /// the redundancy fallback.
    @Test("receipt-038: the gross total wins over the VAT")
    func receipt038GrossWins() {
        let lines: [OCRLine] = [
            line("79,32", midY: 0.803, midX: 0.783),
            line("79,32 EUR", midY: 0.764, midX: 0.418),
            line("Summa", midY: 0.751, midX: 0.273),
            line("79,32", midY: 0.749, midX: 0.295),
            line("79,32", midY: 0.739, midX: 0.377),
            line("Summa", midY: 0.730, midX: 0.453),
            line("15,35", midY: 0.730, midX: 0.475),
            line("15,35", midY: 0.728, midX: 0.493),
            line("-0,23 EUR", midY: 0.657, midX: 0.782),
            line("63,97", midY: 0.638, midX: 0.393),
            line("1,754 EUR/L", midY: 0.627, midX: 0.312),
            line("KOKKU", midY: 0.339, midX: 0.362),
            line("KK MAKSE", midY: 0.332, midX: 0.400),
            line("SUMMA", midY: 0.303, midX: 0.780)
        ]
        let result = FuelExtractor().extract(lines: lines)
        #expect(result.total == decimal("79.32"))
    }

    /// A receipt with no repeated value must keep abstaining, never guess: two
    /// `Summa` labels pair with two different values (a tie), and neither value
    /// repeats, so the redundancy fallback has no single dominant value.
    @Test("an all-unique document abstains rather than picking a value")
    func allUniqueDocumentAbstains() {
        let lines: [OCRLine] = [
            line("Summa", midY: 0.750, midX: 0.270),
            line("79,32", midY: 0.749, midX: 0.295),
            line("Summa", midY: 0.730, midX: 0.450),
            line("15,35", midY: 0.730, midX: 0.475)
        ]
        let result = FuelExtractor().extract(lines: lines)
        #expect(result.total == nil)
    }
}

// MARK: - 5. The fiscal QR composed into the extraction

@Suite("RV.56: the fiscal QR in the scored extraction")
struct RV56QRTests {

    /// The QR date overrides the (absent or garbled) OCR date. Without the QR
    /// this extraction has no date at all, so this test fails if the QR is not
    /// composed.
    @Test("the QR date fills a date the OCR did not read")
    func qrDateFillsOcrAbsence() throws {
        let anchor = try FiscalQRParser.parse(
            "t=20241125T1318&s=3058.00&fn=7281440701457733&i=108108&fp=91817583&n=1",
            timeZone: .current).anchor
        let result = FuelExtractor().extract(textLines: ["ИТОГ", "3058.00"], qrAnchor: anchor)
        #expect(result.date == "25.11.2024")
    }

    /// On a disagreement the QR total is authoritative. The OCR here grabs a VAT
    /// line as the total; the fiscal total corrects it. Asserting the QR value
    /// means this test fails if the QR is absent.
    @Test("a QR that disagrees with the OCR total is authoritative")
    func qrAuthoritativeOnDisagreement() throws {
        let anchor = try FiscalQRParser.parse(
            "t=20260711T1512&s=19719.00&fn=7384440901284566&i=17074&fp=2081817959&n=1",
            timeZone: .current).anchor
        // The VAT amount sits above ИТОГ so the OCR total finder grabs it; the
        // operands resolve nothing, so hard rule 4 cannot correct it - only the
        // QR can.
        let lines = [
            "450.00*43.820", "=3555.89", "ИТОГ", "=19719.00", "СУММА НДС 22%",
            "НАЛИЧНЫМИ", "=19719.00"
        ]
        let withQR = FuelExtractor().extract(textLines: lines, qrAnchor: anchor)
        #expect(withQR.total == decimal("19719.00"))
    }

    /// Hard rule 4: on a mixed receipt the QR carries the GRAND total and must
    /// not override the fuel line.
    @Test("a mixed receipt keeps its fuel line against the QR grand total")
    func mixedReceiptKeepsFuelLine() throws {
        let anchor = try FiscalQRParser.parse(
            "t=20190320T1256&s=1729.87&fn=8710000101682165&i=43800&fp=3906107117&n=1",
            timeZone: .current).anchor
        // The fuel pair resolves (marker `л`); the QR grand total differs by a
        // service line. The fuel line stands.
        let lines = [
            "ТРК-2 АИ-95-К5", "43.38 л Х 38.28", "#1660.59 РУБ", "ИТОГ", "1729.87"
        ]
        let result = FuelExtractor().extract(textLines: lines, qrAnchor: anchor)
        #expect(result.liters == 43.38)
        #expect(result.unitPrice == decimal("38.28"))
        #expect(close(result.total, "1660.59"),
                "the fuel line stands against the QR grand total 1729.87")
    }
}
