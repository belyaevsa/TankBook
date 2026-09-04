import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

// RV.56 - the receipt total is the last field that still returned a WRONG
// number. Three receipts returned a confident-wrong total (receipt-017 the
// pre-discount subtotal, receipt-018 the VAT amount, receipt-025 the grand
// total of a mixed receipt), and two returned nil for a fixable reason
// (receipt-001's `Käibemaks kokku` matched the total word `KOKKU`, receipt-038
// had no labelled total at all). Each test below reproduces the committed OCR
// lines - quoted exactly as Vision read them, misreads included - and pins the
// corrected total, so a regression names the receipt.

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

/// An OCR line centred at the given midX/midY - the two coordinates the total
/// finder's label/value pairing reads.
private func line(_ text: String, midX: CGFloat, midY: CGFloat) -> OCRLine {
    OCRLine(text: text, boundingBox: CGRect(x: midX - 0.05, y: midY - 0.01,
                                            width: 0.1, height: 0.02))
}

@Suite("RV.56: the receipt total no longer returns a wrong number")
struct RV56TotalTests {

    @Test("receipt-017: a СКИДКА line makes the payment value the charged total")
    func receipt017DiscountChargesThePaymentLine() {
        // `ИТОГ` prints the pre-discount 961.80 on its own baseline; the СКИДКА
        // line reconciles it to the charged 961.00 on the payment line.
        let result = FuelExtractor().extract(lines: [
            line("=961.80 РУБ", midX: 0.621, midY: 0.701),
            line("48.09 X 20", midX: 0.271, midY: 0.694),
            line("=160.30 РУБ", midX: 0.622, midY: 0.681),
            line("=961.80 РУБ", midX: 0.623, midY: 0.661),
            line("ИТОГ:", midX: 0.237, midY: 0.661),
            line("=961.00 РУБ", midX: 0.624, midY: 0.642),
            line("СКИДКА =-0.80 РУБ", midX: 0.328, midY: 0.641),
            line("#160.30 РУБ", midX: 0.625, midY: 0.623),
            line("СУММА НДС 20%", midX: 0.285, midY: 0.621),
            line("=961.00 РУБ", midX: 0.626, midY: 0.602),
            line("НАЛИЧНЫМИ:", midX: 0.265, midY: 0.601)
        ])
        #expect(result.total == decimal("961.00"))
    }

    @Test("receipt-018: a negative VAT amount is never read as the total")
    func receipt018NegativeVATIsNotTheTotal() {
        // The VAT amount is printed `-3555.89` one row below the ИТОГ label; the
        // real total `=19719.00` sits a row above it. A total is never negative.
        let result = FuelExtractor().extract(lines: [
            line("=19719.00", midX: 0.675, midY: 0.584),
            line("ИТОГ", midX: 0.406, midY: 0.570),
            line("-3555.89", midX: 0.725, midY: 0.563),
            line("СУММА НДС 22%", midX: 0.436, midY: 0.551),
            line("=19719.00", midX: 0.722, midY: 0.547),
            line("НАЛИЧНЫМИ", midX: 0.415, midY: 0.534),
            line("=19719.00", midX: 0.723, midY: 0.529)
        ])
        #expect(result.total == decimal("19719.00"))
    }

    @Test("receipt-025: a mixed receipt's total is the fuel line, not the grand total")
    func receipt025MixedTotalIsTheFuelLine() {
        // The service `69.28 X 1` precedes the fuel `43.38 Х 38.28`; the fuel
        // line's own product is 1660.59 while the grand total is 1729.87. Hard
        // rule 4: the fill-up amount is the fuel line.
        let result = FuelExtractor().extract(lines: [
            line("Услуга по регистрации покупки", midX: 0.373, midY: 0.677),
            line("69.28 X 1", midX: 0.229, midY: 0.658),
            line("#69.28 РУБ", midX: 0.674, midY: 0.651),
            line("ТРК-2 АИ-95-К5", midX: 0.265, midY: 0.631),
            line("43.38 Х 38.28", midX: 0.257, midY: 0.604),
            line("#1660.59 РУб", midX: 0.661, midY: 0.601),
            line("НДС 20%", midX: 0.211, midY: 0.581),
            line("=276.77 РУБ", midX: 0.670, midY: 0.576),
            line("ИТОГ:", midX: 0.194, midY: 0.553),
            line("=1729.87 РУБ", midX: 0.664, midY: 0.552),
            line("СУММА БЕЗ НДС", midX: 0.254, midY: 0.525),
            line("#69.28 РУБ", midX: 0.679, midY: 0.525),
            line("=276.77 РУБ", midX: 0.673, midY: 0.499),
            line("СУММА НДС 20%", midX: 0.254, midY: 0.498),
            line("БЕЗНАЛИЧНЫМИ:", midX: 0.251, midY: 0.473),
            line("=1729.87 РУБ", midX: 0.668, midY: 0.472)
        ])
        #expect(result.total == decimal("1660.59"))
    }

    @Test("receipt-001: `Käibemaks kokku` is VAT, never the total")
    func receipt001VATTotalIsExcluded() {
        // `Käibemaks kokku` contains the Estonian total word `KOKKU` and used to
        // tie with the real KOKKU, forcing a nil. Excluded, the fuel line
        // (67,00 L x 1,869) then settles the total the label mispairs.
        let result = FuelExtractor().extract(lines: [
            line("Summa", midX: 0.616, midY: 0.731),
            line("1", midX: 0.675, midY: 0.721),
            line("Kogus", midX: 0.462, midY: 0.719),
            line("125,22", midX: 0.613, midY: 0.713),
            line("kirjeldus", midX: 0.314, midY: 0.710),
            line("67,00L", midX: 0.460, midY: 0.703),
            line("D BÓ miles", midX: 0.321, midY: 0.696),
            line("EUR/L", midX: 0.559, midY: 0.695),
            line("1,869", midX: 0.496, midY: 0.690),
            line("4 Hind", midX: 0.414, midY: 0.686),
            line("Pump", midX: 0.344, midY: 0.680),
            line("-1,01 EUR", midX: 0.556, midY: 0.677),
            line("EXTRA SOODUS", midX: 0.338, midY: 0.665),
            line("125,22", midX: 0.618, midY: 0.650),
            line("KOKKU", midX: 0.329, midY: 0.636),
            line("100,98", midX: 0.546, midY: 0.630),
            line("KAIBEMAKSUTA", midX: 0.346, midY: 0.621),
            line("125,22 EUR", midX: 0.643, midY: 0.620),
            line("KK MAKSE", midX: 0.328, midY: 0.606),
            line("Summa", midX: 0.628, midY: 0.589),
            line("Kood", midX: 0.528, midY: 0.586),
            line("Määr", midX: 0.438, midY: 0.583),
            line("Käibemaks", midX: 0.335, midY: 0.579),
            line("24,24", midX: 0.629, midY: 0.574),
            line("1", midX: 0.526, midY: 0.573),
            line("24,00%", midX: 0.451, midY: 0.568),
            line("24% KM", midX: 0.323, midY: 0.563),
            line("24,24", midX: 0.630, midY: 0.559),
            line("Käibemaks kokku", midX: 0.368, midY: 0.551)
        ])
        #expect(result.total == decimal("125.22"))
    }

    @Test("receipt-038: an unlabelled total falls back to the arithmetic fuel line")
    func receipt038UnlabelledTotalFallsBackToTheFuelLine() {
        // Two `Summa` labels tie (the receipt total 79,32 and the VAT column's
        // 15,35), so no labelled total settles. The arithmetic fuel line - 45,22
        // x 1,754 = 79,32 - is the amount the document settles instead.
        let result = FuelExtractor().extract(lines: [
            line("79,32", midX: 0.783, midY: 0.803),
            line("79,32 EUR", midX: 0.418, midY: 0.764),
            line("Summa", midX: 0.273, midY: 0.751),
            line("79,32", midX: 0.295, midY: 0.749),
            line("Summa", midX: 0.453, midY: 0.730),
            line("15,35", midX: 0.475, midY: 0.730),
            line("15,35", midX: 0.493, midY: 0.728),
            line("1,754 EUR/L", midX: 0.312, midY: 0.627),
            line("Kogus", midX: 0.269, midY: 0.546),
            line("45,22L", midX: 0.291, midY: 0.540),
            line("95E0 miles", midX: 0.283, midY: 0.349)
        ])
        #expect(result.total == decimal("79.32"))
    }
}

#if canImport(Vision)
import Vision

// The headline property: ZERO confident-wrong totals in the receipts class.
// Asserted over the WHOLE class - every fixture either matches its expected
// total or returns nil - not as three individual expectations, so a NEW wrong
// total added later fails too.
@Suite("RV.56: zero confident-wrong totals over the whole receipts class (Vision-gated)")
struct RV56TotalPropertyTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")
    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    @Test func noReceiptTotalIsConfidentlyWrong() throws {
        let folder = Self.fixturesRoot.appendingPathComponent("receipts")
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try CorpusScorer.imageFilenames(in: folder)
        let pack = try FuelPriceBandStore.bundledPack()
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))

        var wrong: [String] = []
        for image in images {
            guard let want = expected[image]?.total else { continue }
            let url = folder.appendingPathComponent(image)
            let ocr = try VisionTextRecognizer.recognizeText(in: url, languages: Self.languages)
            let result = extractor.extract(lines: ocr, source: .receipt)
            guard let got = result.total?.corpusBoundaryDouble else { continue }
            if abs(got - want) >= CorpusScorer.tolerance {
                wrong.append("\(image): got \(got), want \(want)")
            }
        }
        #expect(wrong.isEmpty, Comment(stringLiteral: wrong.joined(separator: "\n")))
    }
}
#endif
