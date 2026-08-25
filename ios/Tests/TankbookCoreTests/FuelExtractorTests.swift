import Foundation
import Testing
@testable import TankbookCore

// P2.2 parser port tests: the pure text -> fields core, driven by the OCR line
// sequences documented in Spike/ReceiptSpike/fixtures/*/README.md. No Vision,
// no images - these are the fast, deterministic checks (docs/TESTING.md L1).

private struct StubBandProvider: FuelPriceBandProvider {
    var band: FuelPriceBand?
    var history: Double?

    init(band: FuelPriceBand? = nil, history: Double? = nil) {
        self.band = band
        self.history = history
    }

    func band(currency: CurrencyCode?, fuelKind: FuelKind?, date: Date?) -> FuelPriceBand? { band }
    func historicalPrice(currency: CurrencyCode?, fuelKind: FuelKind?) -> Double? { history }
}

// MARK: - Volume / unit price resolution (the swap fix)

@Suite("Fuel extractor: volume and unit price")
struct FuelExtractorVolumePriceTests {

    @Test("the l-marker names the volume on either side of the operator")
    func unitMarkerNamesVolume() {
        let extractor = FuelExtractor()
        let first = extractor.extract(textLines: ["40 л Х 195.00"])
        #expect(first.liters == 40.0)
        #expect(first.unitPrice == 195.00)

        let second = extractor.extract(textLines: ["62.89*66.810л"])
        #expect(second.liters == 66.810)
        #expect(second.unitPrice == 62.89)
    }

    @Test("an unmarked pair resolves through the injected band, never by guessing")
    func bandResolvesUnmarkedPair() {
        let provider = StubBandProvider(band: FuelPriceBand(low: 80, high: 120))
        let extractor = FuelExtractor(bandProvider: provider)
        let result = extractor.extract(textLines: ["43.61 Х 99.40"])
        #expect(result.liters == 43.61)
        #expect(result.unitPrice == 99.40)
    }

    @Test("an unmarked pair with no history and no band is undecided -> nil")
    func unmarkedWithoutProviderIsUndecided() {
        let extractor = FuelExtractor()
        let result = extractor.extract(textLines: ["205.00*20", "Л =4100.00", "ИТОГ", "=4100.00"])
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
        #expect(result.total == 4100.00)
    }

    @Test("the labelled column names quantity and price by x position")
    func labelledColumnNamesFields() {
        // receipt-013: headers "Цена за ед.", "Кол.", "Сумма" sit on one row,
        // the item row (АИ-95-К5 + its three numbers) on the row below, with
        // the numbers aligned to the header columns.
        let lines = [
            "Цена за", "Наименование", "Кол.", "Сумма",
            "АИ-95-К5", "71.25", "50", "3562.50",
            "ИТОГО:", "3562.50", "Безналичными", "3562.50"
        ]
        let boxes: [OCRLine] = [
            OCRLine(text: "Цена за", boundingBox: box(x: 0.4, y: 3)),
            OCRLine(text: "Наименование", boundingBox: box(x: 0.2, y: 3)),
            OCRLine(text: "Кол.", boundingBox: box(x: 0.6, y: 3)),
            OCRLine(text: "Сумма", boundingBox: box(x: 0.8, y: 3)),
            OCRLine(text: "АИ-95-К5", boundingBox: box(x: 0.2, y: 2)),
            OCRLine(text: "71.25", boundingBox: box(x: 0.4, y: 2)),
            OCRLine(text: "50", boundingBox: box(x: 0.6, y: 2)),
            OCRLine(text: "3562.50", boundingBox: box(x: 0.8, y: 2)),
            OCRLine(text: "ИТОГО:", boundingBox: box(x: 0.2, y: 1)),
            OCRLine(text: "3562.50", boundingBox: box(x: 0.8, y: 1))
        ]
        let extractor = FuelExtractor()
        let result = extractor.extract(lines: boxes)
        #expect(result.liters == 50.0)
        #expect(result.unitPrice == 71.25)
        #expect(result.total == 3562.50)
    }
}

// MARK: - Total finder (the reading-order fix)

@Suite("Fuel extractor: total finder")
struct FuelExtractorTotalTests {

    @Test("receipt-002: the total is the modal, not the VAT line")
    func receipt002IgnoresVAT() {
        let lines = [
            "1 АН-100-K5 АИ-100-K5 (3 ТРК)", "n=19719.00", "450.00*43.820",
            "НДС 22%", "ПОДАКЦИЗНЫЙ ТОВАР", "=19719.00", "ИТОГ", "=3555.89",
            "СУММА НДС 22%", "=19719.00", "НАЛИЧНЫМИ", "=19719.00", "ПОЛУЧЕНО НАЛИЧНЫМИ"
        ]
        let extractor = FuelExtractor()
        let result = extractor.extract(textLines: lines)
        #expect(result.total == 19719.00)
    }

    @Test("receipt-011: the total is the fuel total, not the VAT amount")
    func receipt011IgnoresVAT() {
        let lines = [
            "1 ДТ-Л-К5 N 1:09005", "=4201.68", "62.89*66.810л", "НДС 20%", "ДТ-Л-К5",
            "=4201.68", "ИТОГ", "=700.28", "СУММА НДС 20%", "=4201.68", "БЕЗНАЛИЧНЫМИ"
        ]
        let extractor = FuelExtractor()
        let result = extractor.extract(textLines: lines)
        #expect(result.total == 4201.68)
        #expect(result.liters == 66.810)
        #expect(result.unitPrice == 62.89)
    }

    @Test("receipt-012: the rounding line is not the total")
    func receipt012IgnoresRounding() {
        let lines = [
            "ТРК-19 СУГ, Л", "52.15 Х 23.99", "=1251.08_НДС 20%", "1251.00", "ИТОГ",
            "0.08", "ОКРУГЛЕНИЕ", "1251.00", "БЕЗНАЛИЧНЫМИ", "=208.51", "СУММА НДС 20%"
        ]
        let extractor = FuelExtractor()
        let result = extractor.extract(textLines: lines)
        #expect(result.total == 1251.00)
    }

    @Test("receipt-009: a mixed receipt's fuel line, not the grand total")
    func receipt009UsesFuelLine() {
        let lines = [
            "95 V-Power АН-95-K5 (1 ТРК)", "26135.24 НДС 22%", "47.56 л Х 129,00",
            "Округление в пользу клиента", "Вода Святой Источник 0.5л",
            "1 т. X 129.00", "6264.24", "ВСЕГО", "ОКРУГЛЕНИЕ", "6264.00", "ИТОГ",
            "6264.00", "БЕЗНАЛИЧНЫМИ"
        ]
        let extractor = FuelExtractor()
        let result = extractor.extract(textLines: lines)
        #expect(result.liters == 47.56)
        #expect(result.unitPrice == 129.00)
        #expect(close(result.total, 6135.24))
    }

    @Test("receipt-007: the ИТОГ value, not the pre-rounding fuel line")
    func receipt007UsesRoundedTotal() {
        let lines = [
            "43.61 Х 99.40", "=4334.83_НДС 22%", "В ТОМ ЧИСЛЕ ВАША СКИДКА = 0.83",
            "ИТОГ", "4334.00", "ОКРУГЛЕНИЕ", "0.83", "СУММА НДС 22%", "=781.69"
        ]
        let extractor = FuelExtractor()
        let result = extractor.extract(textLines: lines)
        #expect(result.total == 4334.00)
    }
}

// MARK: - Fuel kind

@Suite("Fuel extractor: fuel kind normalisation")
struct FuelKindNormalizerTests {

    @Test("diesel spellings map to diesel")
    func dieselVariants() {
        #expect(FuelKindNormalizer.normalize("1 дИЗ. тоПл. ДТ-Л-К5 УЛЬТра") == .diesel)
        #expect(FuelKindNormalizer.normalize("1 ДТ-Л-К5 N 1:09005") == .diesel)
        #expect(FuelKindNormalizer.normalize("ДТ") == .diesel)
        #expect(FuelKindNormalizer.normalize("зимнеекдт-3-к3") == .diesel)
    }

    @Test("petrol grades map to their octane")
    func petrolVariants() {
        #expect(FuelKindNormalizer.normalize("1 БенЗИН АИ-95-К5 Ультра") == .petrol95)
        #expect(FuelKindNormalizer.normalize("Бензин G-Drive 95(АИ-95-К5)") == .petrol95)
        #expect(FuelKindNormalizer.normalize("АИ-92-К Колонка 5") == .petrol92)
        #expect(FuelKindNormalizer.normalize("ТРК Nº3 БЕНЗИН АВТОМОБИЛЬНЫЙ ЭКТО-100 (АИ-100-К5)") == .petrol100)
    }

    @Test("LPG maps to lpg")
    func lpgVariant() {
        #expect(FuelKindNormalizer.normalize("ТРК-19 СУГ, Л") == .lpg)
    }

    @Test("a station number is not a fuel grade")
    func stationNumberIsNotAGrade() {
        #expect(FuelKindNormalizer.isProductLine("ООО\"КЕДР\" АЗС-98") == false)
        #expect(FuelKindNormalizer.normalize("ООО\"КЕДР\" АЗС-98") == nil)
    }

    @Test("a pump display yields no fuel kind")
    func pumpHasNoFuelKind() {
        let lines = ["ЛИТРЫ", "43.61", "ЦЕНА/ЛИТР", "99.40", "РУБЛИ", "4334.83"]
        let extractor = FuelExtractor()
        let result = extractor.extract(textLines: lines, source: .pump)
        #expect(result.fuelKind == nil)
    }

    // MARK: - receipt-034: the B2B contract receipt

    /// "ДТ" occurs inside "ПОДТВЕРЖДЕНА" - the card-terminal line printed on
    /// every Russian card receipt ("Операция подтверждена вводом ПИН"). A bare
    /// substring match classified `receipt-034`'s АИ-95 fill as **diesel**, and
    /// `fuelKind` is a stored domain field, so that is a confident wrong value.
    ///
    /// The test asserts BOTH directions on purpose: a rule that simply stopped
    /// matching "ДТ" would pass the first half while silently breaking every
    /// real diesel receipt in the corpus - and one did, immediately. The corpus
    /// case `"зимнеекдт-3-к3"` is OCR with the words glued together, so a
    /// word-START rule rejects a genuine diesel line. What actually separates
    /// the two is the character that FOLLOWS: a grade code runs into a
    /// separator, a digit or the end of the line, never into more letters.
    @Test("a fuel word inside a longer word is not a fuel word")
    func fuelFamiliesMatchAtWordStartsOnly() {
        #expect(FuelKindNormalizer.normalize("Операция подтверждена Вводом") == nil)
        #expect(FuelKindNormalizer.normalize("ПОДТВЕРЖДЕНА") == nil)
        #expect(!FuelKindNormalizer.isProductLine("подтверждена Вводом"))

        // Real product lines still resolve - prefixes and hyphenated forms.
        #expect(FuelKindNormalizer.normalize("ДТ-Л-К5") == .diesel)
        #expect(FuelKindNormalizer.normalize("ДИЗЕЛЬНОЕ ТОПЛИВО") == .diesel)
        #expect(FuelKindNormalizer.normalize("ДТ-Е-К5 Танеко") == .diesel)
        #expect(FuelKindNormalizer.normalize("АИ-95-К5") == .petrol95)
        #expect(FuelKindNormalizer.normalize("СУГ") == .lpg)
        #expect(FuelKindNormalizer.normalize("МЕТАН CNG") == .cng)
        // Glued OCR must keep working: the rule is about what follows a grade
        // code, not about where a word begins.
        #expect(FuelKindNormalizer.normalize("зимнеекдт-3-к3") == .diesel)
    }

    /// A printed zero is "the price is not on this receipt", never "the fuel was
    /// free". `receipt-034` is a **B2B contract fuel card**: the price is settled
    /// between the fleet and the network, so the driver's copy prints
    /// `30.61 X 0.00` / `ИТОГ 0.00` under "Цена определена договором".
    ///
    /// Storing 0.00 biases stats silently rather than loudly: `costPerKm` keeps
    /// the fill's odometer span in the denominator while it contributes nothing
    /// to the numerator, so every corporate fill drags the rate down. `money` is
    /// optional end to end and `costPerKm` already skips entries without it, so
    /// nil is the representation the rest of the app expects.
    @Test("a contract-priced receipt yields no money at all, never a zero")
    func zeroMoneyIsAbsentNotFree() {
        let lines = ["ТРК №8 Бензин автомобильный ЭКТО",
                     "Plus (АИ-95-К5), л",
                     "30.61 Х 0.00",
                     "Цена определена договором",
                     "ИТОГ",
                     "0.00"]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.total == nil, "a zero total must not be stored as money")
        #expect(result.unitPrice == nil, "a zero unit price must not be stored as money")
        // The volume is real and must survive: consumption is computed from it,
        // and a B2B fill is a perfectly good consumption data point.
        #expect(result.fuelKind == .petrol95)

        // The degenerate cross-check: 30.61 x 0.00 == 0.00 is arithmetically
        // perfect and carries no information. It must not read as verified.
        #expect(!result.crossCheckPassed)
    }
}

// MARK: - Helpers

private func box(x: CGFloat, y: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: 0.1, height: 0.5)
}

private func close(_ value: Double?, _ expected: Double) -> Bool {
    guard let value else { return false }
    return abs(value - expected) < 0.005
}
