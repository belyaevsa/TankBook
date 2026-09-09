import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

// RV.153 - a computed total must never beat a printed one (docs/EXTRACTION.md
// -> "Printed total vs derived product"). Two corpus fixtures broke the RV.56
// whole-class property the same way: the arithmetic product of two OCR'd
// operands overrode a total the receipt printed and the parser read correctly.
// receipt-055 misreads `77,56L` as `17,56L` (product 33.96 against printed
// `KOKKU 150,00` / `KK MAKSE 150,00`); receipt-057's unit price is occluded so
// the line reads `.05 x 57.000` (product 285.0 against printed `=3935.85`,
// read twice). These L1 tests pin the rule over the OCR TEXT - no Vision, no
// image - quoted from the app's own recognition of the two fixtures.

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

private func stubBand(_ low: Double, _ high: Double) -> FuelExtractor {
    FuelExtractor(bandProvider: StubBand(band: FuelPriceBand(low: low, high: high)))
}

private struct StubBand: FuelPriceBandProvider {
    let band: FuelPriceBand
    func band(currency: CurrencyCode?, fuelKind: FuelKind?, date: Date?) -> FuelPriceBand? { band }
    func historicalPrice(currency: CurrencyCode?, fuelKind: FuelKind?) -> Double? { nil }
}

/// An OCR line centred at the given midX/midY - the two coordinates the total
/// finder's label/value pairing reads.
private func line(_ text: String, midX: CGFloat, midY: CGFloat) -> OCRLine {
    OCRLine(text: text, boundingBox: CGRect(x: midX - 0.05, y: midY - 0.01,
                                            width: 0.1, height: 0.02))
}

@Suite("RV.153: a printed total outranks a computed one")
struct RV153TotalPrecedenceTests {

    // receipt-055: the volume OCRs as `17,56L` (truth 77,56L), so the product is
    // 33.96 - but the receipt prints its total twice, `KOKKU 150,00` and
    // `KK MAKSE 150,00 EUR`, both read at confidence 1.00. The printed total,
    // corroborated by two independent label reads, is the amount.
    @Test("receipt-055: a misread volume must not outrank the printed 150.00")
    func printedTotalBeatsMisreadVolumeProduct() {
        let result = FuelExtractor().extract(lines: [
            line("98E0 miles+", midX: 0.424, midY: 0.477),
            line("17,56L", midX: 0.571, midY: 0.477),
            line("1,934 EUR/L", midX: 0.645, midY: 0.463),
            line("KOKKU", midX: 0.417, midY: 0.415),
            line("150,00", midX: 0.733, midY: 0.416),
            line("KK MAKSE", midX: 0.413, midY: 0.384),
            line("150,00 EUR2", midX: 0.766, midY: 0.382)
        ])
        #expect(result.liters == 17.56)
        #expect(result.unitPrice == decimal("1.934"))
        #expect(result.total == decimal("150.00"),
                "17,56 x 1,934 = 33,96 must not outrank the printed 150,00")
    }

    // receipt-057: the unit price is occluded, so the fuel line reads
    // `.05 x 57.000` and the operands resolve to 5 L at 57 - a product of 285.
    // The line's own printed sum `=3935.85` sits beside the pair at confidence
    // 1.00 and is the amount; the derived 285 is a misread factor times a real
    // volume.
    @Test("receipt-057: a printed line sum beats the product of a misread factor")
    func printedLineSumBeatsOccludedFactorProduct() {
        let result = stubBand(50, 80).extract(lines: [
            line("Бензин G-Drive 95(АИ-95-К5)", midX: 0.4, midY: 0.6),
            line(".05 x 57.000", midX: 0.276, midY: 0.580),
            line("=3935.85", midX: 0.634, midY: 0.577)
        ])
        #expect(result.total == decimal("3935.85"),
                "5 x 57.000 = 285 must not outrank the printed 3935.85")
    }

    // The arithmetic fallback keeps working where it was designed to: a
    // label-free display states no total, so liters x unitPrice IS the amount
    // (Spike/ReceiptSpike/README.md: "this alone handles label-free pump
    // displays"). This is the pump-shaped rescue path a "printed always wins"
    // rule must not delete.
    @Test("a label-free pump-shaped display still resolves by arithmetic")
    func labelFreePumpStillResolvesByArithmetic() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
        let result = extractor.extract(textLines: [
            "7€", "SUMMA", "12522", "LIITRIT", "67.00", "1869 HIND/1L"
        ], source: .pump)
        #expect(result.liters == 67.00)
        #expect(result.unitPrice == decimal("1.869"))
        #expect(result.total == decimal("125.22"),
                "67.00 x 1.869 = 125.22 is the amount when nothing is printed")
    }

    // A printed total read ONCE that the product contradicts is not evidence
    // strong enough to prefer over the product - and the product of two OCR'd
    // factors is not strong enough to prefer over it. Neither side is
    // corroborated, so the parser abstains rather than commit a plausible wrong
    // number (hard rule 13; RV.56's whole point is that a confident-wrong total
    // is worse than a nil the user fills).
    @Test("a single uncorroborated printed total that contradicts the product abstains")
    func uncorroboratedDisagreementAbstains() {
        let result = FuelExtractor().extract(lines: [
            line("17,56L", midX: 0.571, midY: 0.477),
            line("1,934 EUR/L", midX: 0.645, midY: 0.463),
            line("KOKKU", midX: 0.417, midY: 0.415),
            line("150,00", midX: 0.733, midY: 0.416)
        ])
        #expect(result.total == nil,
                "neither 150.00 nor 33.96 may be committed when only one read supports each")
    }
}
