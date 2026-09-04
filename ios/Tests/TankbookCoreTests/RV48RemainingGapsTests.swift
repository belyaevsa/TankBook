import Foundation
import Testing
@testable import TankbookCore

// RV.48 STAGE THREE - the four remaining deterministic gaps in receipt
// extraction. Each test names the fixture it came from and quotes the lines
// exactly as the live OCR dump printed them (misreads included), so a tidied
// vocabulary cannot make a test pass that the corpus would fail.

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

/// An OCR line centred at the given midX/midY, the two coordinates the value
/// finders read. Used for the geometry-dependent gaps (the reference-block
/// price and the labelled quantity), which `extract(textLines:)` (zero boxes)
/// cannot exercise.
private func line(_ text: String, midX: CGFloat, midY: CGFloat) -> OCRLine {
    OCRLine(text: text, boundingBox: CGRect(x: midX - 0.05, y: midY - 0.01,
                                            width: 0.1, height: 0.02))
}

@Suite("RV.48 stage three: the four remaining gaps")
struct RV48RemainingGapsTests {

    // MARK: - Gap 1: the Estonian unit price is on the SAME line as its label

    @Test("receipt-046: a self-describing EUR/L line carries its price, not the pump number")
    func selfDescribingUnitPrice() {
        // receipt-046 prints "Pump 5 Hind 1,799 EUR/L" - the pump number 5 and
        // the price 1,799 on the one line. The value is the number immediately
        // before the per-unit marker.
        let result = FuelExtractor().extract(textLines: [
            "Pump 5 Hind 1,799 EUR/L",
            "55,80L",
            "KOKKU",
            "100,38"
        ])
        #expect(result.unitPrice == decimal("1.799"))
        #expect(result.liters == 55.80)
    }

    @Test("receipt-038: the price is inline, and the octane in the product line is not a volume")
    func selfDescribingPriceAndProductLine() {
        // "95E0 miles" is the product line; its "95" must never become the
        // volume. "1,754 EUR/L" carries the price; "45,22L" the volume.
        let result = FuelExtractor().extract(textLines: [
            "1,754 EUR/L",
            "Kogus",
            "45,22L",
            "95E0 miles"
        ])
        #expect(result.unitPrice == decimal("1.754"))
        #expect(result.liters == 45.22)
        #expect(result.fuelKind == .petrol95)
    }

    // MARK: - Gap 2: a product name split across lines

    @Test("receipt-042: a split Circle K grade whose 'D B0' is garbled stays unresolved")
    func splitGarbledGradeAbstains() {
        // receipt-042 OCRs "D B0 miles" as "miles" on one line and ") BC"
        // (the garbled grade) on the shared baseline beside it. Joining them
        // yields ") BC miles", which the vocabulary does not recognise - and
        // any rule loose enough to read "D B0" out of ") BC" is resolution by
        // resemblance (HIGH-WATER.md). So the kind stays nil on purpose.
        #expect(FuelKindNormalizer.normalize(") BC miles") == nil)
        #expect(FuelKindNormalizer.normalize("miles") == nil)
        // The legible form still resolves - the abstention is about the smear,
        // not the vocabulary.
        #expect(FuelKindNormalizer.normalize("D B0 miles") == .diesel)
    }

    // MARK: - Gap 3: the smeared octane, corroborated by the Euro-5 suffix

    @Test("receipt-032: AM-95-K5 resolves petrol95, and AM-95 without the suffix does not")
    func corroboratedSmearedOctane() {
        // И smears to M in thermal print, and M is not a homoglyph of И. The
        // -K5 Euro-5 suffix is the corroboration: it is itself a fuel token on
        // the same line. Without it, resemblance alone is not resolution.
        #expect(FuelKindNormalizer.normalize("AM-95-K5 PuLsar-95 N 5:00000") == .petrol95)
        #expect(FuelKindNormalizer.normalize("95PuLsar AM-95-K5") == .petrol95)
        #expect(FuelKindNormalizer.normalize("AM-95") == nil)
        #expect(FuelKindNormalizer.isProductLine("AM-95-K5"))
        #expect(!FuelKindNormalizer.isProductLine("AM-95"))
    }

    @Test("receipt-018: the АЙ-100 smear with -K5 resolves petrol100")
    func corroboratedSmearedOctane100() {
        // "АЙ-100-K5" is "АИ-100-К5" with the И smeared to Й. The -K5 suffix
        // corroborates it, and 100 is a retail grade.
        #expect(FuelKindNormalizer.normalize("1 АЙ-100-KS АЙ-100-K5 (3 ТРК)") == .petrol100)
    }

    @Test("receipt-027: АИ-96 with -K5 still resolves nothing - 96 is not a grade")
    func corroborationDoesNotInventAGrade() {
        // The corroboration turns a smeared PREFIX into the canonical grade; it
        // does not create a grade the octane switch does not have. 96 is not a
        // retail grade, so receipt-027 stays unresolved exactly as HIGH-WATER.md
        // settled.
        #expect(FuelKindNormalizer.normalize("ЭКТО Plus (АИ-96-К5), л") == nil)
    }

    @Test("receipt-032 through the extractor: the band unlocks after the kind resolves")
    func bandUnlocksFor032() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
        let result = extractor.extract(textLines: [
            "AM-95-K5 PuLsar-95 N 5:00000",
            "73.15*20",
            "ЗН ККТ 00106906149101"
        ])
        #expect(result.fuelKind == .petrol95)
        #expect(result.liters == 20.0)
        #expect(result.unitPrice == decimal("73.15"))
    }

    // MARK: - Gap 4: the Russian labelled column and the reference-block price

    @Test("receipt-023: the quantity column and the reference-block price")
    func receipt023LabelledColumnAndReferencePrice() {
        let lines = [
            line("товар", midX: 0.086, midY: 0.457),
            line("единиц", midX: 0.290, midY: 0.459),
            line("сУмма", midX: 0.435, midY: 0.457),
            line("AИ-95", midX: 0.090, midY: 0.439),
            line("20.00", midX: 0.295, midY: 0.438),
            line("1366.00", midX: 0.424, midY: 0.438),
            line("цена за ед.", midX: 0.125, midY: 0.339),
            line("68.30", midX: 0.431, midY: 0.338)
        ]
        let result = FuelExtractor().extract(lines: lines)
        #expect(result.liters == 20.0)
        #expect(result.unitPrice == decimal("68.30"))
    }

    @Test("receipt-030: the label-value quantity and price rows")
    func receipt030LabelValueRows() {
        let lines = [
            line("Цена за ед. пр.", midX: 0.226, midY: 0.452),
            line("43,55 ₽", midX: 0.872, midY: 0.452),
            line("Колич. пр.", midX: 0.164, midY: 0.415),
            line("11,000", midX: 0.885, midY: 0.415)
        ]
        let result = FuelExtractor().extract(lines: lines)
        #expect(result.liters == 11.0)
        #expect(result.unitPrice == decimal("43.55"))
    }

    @Test("receipt-044: the quantity column resolves and the reference price sits slightly below-right")
    func receipt044QuantityAndReferencePrice() {
        let lines = [
            line("единиц", midX: 0.339, midY: 0.440),
            line("25.00", midX: 0.345, midY: 0.418),
            line("1707.50", midX: 0.488, midY: 0.421),
            line("цена за ед.", midX: 0.156, midY: 0.296),
            line("68.30", midX: 0.498, midY: 0.307)
        ]
        let result = FuelExtractor().extract(lines: lines)
        #expect(result.liters == 25.0)
        #expect(result.unitPrice == decimal("68.30"))
    }
}
