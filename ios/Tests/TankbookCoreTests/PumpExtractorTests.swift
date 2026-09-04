import Foundation
import Testing
@testable import TankbookCore

// B2 - the pump-shaped ladder, tested from the OCR dump's own line sequences.
// No Vision, no images: these pin the deterministic behaviour of the
// separator-liberal tokenizer, the label anchors and the scale search
// (docs/TESTING.md L1). Each fixture's lines are quoted from the committed
// `diagnostics/pump-ocr-dump.txt`; the geometry paths are pinned separately by
// DigitRepairTests' constructed Dresser-Wayne layout.

private func pumpExtractor() -> FuelExtractor {
    let pack = try! FuelPriceBandStore.bundledPack()
    return FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
}

private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

@Suite("Pump extractor: the pump-shaped ladder")
struct PumpExtractorTests {

    // MARK: - pump-001: separator lost on two of three

    @Test("pump-001 reads the two separator-less fields and the intact volume")
    func pump001RecoversLostSeparators() {
        // SUMMA 12522 (truth 125.22), LIITRIT 67.00, price 1869 (truth 1.869).
        // The volume keeps its separator so it is unambiguous; the EUR marker
        // pins the price scale and the cross-check pins the total.
        let lines = ["7€", "SUMMA", "12522", "LIITRIT", "67.00", "1869 HIND/1L"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        #expect(result.liters == 67.00)
        #expect(result.unitPrice == decimal("1.869"))
        #expect(result.total == decimal("125.22"))
    }

    // MARK: - pump-003: all three lost, different divisors, factor-of-ten tie

    @Test("pump-003 pins only the price; the volume factor-of-ten tie abstains")
    func pump003AbstainsOnTheVolumeTie() {
        // СТОИМОСтЬ 208863 (20886.25), ЛИТРЫ 8525 (85.25), ЦЕНА 2450 (245.0).
        let lines = ["СТОИМОСтЬ", "208863", "ТЕНГЕ", "ЛИТРЫ", "8525",
                     "ЦЕНА ЗА 1 ЛИТР", "2450"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        // The KZT band pins the price to 245.0; 85.25 vs 8.525 is a factor-of-ten
        // tie no automatic filter may break.
        #expect(result.unitPrice == decimal("245.0"))
        #expect(result.liters == nil)
        #expect(result.total == nil)
    }

    // MARK: - pump-005: four board prices, the cross-check picks the last

    @Test("pump-005 with no currency marker abstains - the scale cannot be pinned")
    func pump005WithoutCurrencyAbstains() {
        // The Dresser-Wayne photo OCRs no currency word, so the band cannot pin
        // the bare board price `5256` to 52.56 (525.6 and 5256 also close the
        // scale-invariant arithmetic). A wrong scale is the worst outcome in
        // this class, so the whole display abstains rather than guess.
        let lines = ["СУММА", "462108", "ЛИТРЫ", "8792",
                     "52.06", "4932 5256", "ЦЕНА ЗА ЛИТР", "55.18"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        #expect(result.unitPrice == nil)
        #expect(result.liters == nil)
        #expect(result.total == nil)
    }

    @Test("pump-005 with a currency marker: the band pins the one price that closes")
    func pump005BandPinsTheRightBoardPrice() {
        // The same display, with the RUB marker the photo's own OCR dropped
        // (Russian pumps print it - pump-007 `РУБЛИ`, pump-008 `РУБ`). The band
        // rejects 525.6 / 5256 / 5.256, and of the four surviving board prices
        // only 52.56 x 87.92 = 4621.08 closes.
        let lines = ["СУММА", "462108 РУБ", "ЛИТРЫ", "8792",
                     "52.06", "4932 5256", "ЦЕНА ЗА ЛИТР", "55.18"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        #expect(result.unitPrice == decimal("52.56"))
        #expect(result.liters == nil)
        #expect(result.total == nil)
    }

    // MARK: - pump-010: the preset whose arithmetic legitimately does not close

    @Test("pump-010 is not repaired into a fake volume")
    func pump010IsNotRepaired() {
        // Итого 1000.00 reads 00.0U (angled glass); the volume 13.17 reads 13.1.
        // 13.17 x 75.95 = 1000.26 against a printed 1000.00: nothing is misread,
        // so nothing may be "fixed" by moving the volume.
        let lines = ["ИтоГО", "00.0U", "Литров", "13.1", "Количество", "75.95", "Цена за Л"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        #expect(result.digitRepair == nil)
        #expect(result.liters == nil)
        #expect(result.total == nil)
        #expect(result.unitPrice == nil)
    }

    // MARK: - pump-016: the idle pump refuses

    @Test("pump-016 refuses rather than logging a zero-litre fill")
    func pump016IdleRefuses() {
        let lines = ["EUR", "LIITRIT", "0.00", "Vmin 2 LIITRIT", "EUR/1L", "1.769", "1884"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        #expect(result.liters == nil)
        #expect(result.total == nil)
        #expect(result.unitPrice == nil)
    }

    // MARK: - pump-034: the charged price is on no board

    @Test("pump-034 does not read a board price as the transaction price")
    func pump034BoardPriceIsNotTheTransaction() {
        // The product dispensed (D B0) is on no board: none of the four board
        // prices is the charged price, so the price must stay empty.
        let lines = ["SUMM", "160.5", "LIITRIT", "729",
                     "HIN", "1759", "1819", "1834", "1934"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        #expect(result.unitPrice == nil)
        #expect(result.liters == nil)
    }

    // MARK: - pump-057: the matched pair, and the zero-padded factor-of-ten tie

    @Test("pump-057 pins the price; the zero-padded volume stays a factor-of-ten tie")
    func pump057ResolvesThePriceAndAbstainsOnTheVolume() {
        // € 10038 (100.38), L 005580 (55.80), €/L 1,799. The paired receipt-046
        // prints 55.80 L, but the display's `005580` is equally consistent with
        // 5.58 L (a real small fill - the pumps print `Vmin 2 LIITRIT`), so the
        // volume and total abstain and only the EUR-pinned price commits.
        let lines = ["€", "10038", "L", "005580", "€/L", "1,799"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        #expect(result.unitPrice == decimal("1.799"))
        #expect(result.liters == nil)
        #expect(result.total == nil)
    }
}

// MARK: - The tokenizer and the scale search, directly

@Suite("Pump number tokenizer")
struct PumpNumberTests {

    @Test("a separator-carrying token has exactly one candidate")
    func separatedTokenIsUnambiguous() {
        let token = PumpNumber(raw: "67.00", hasSeparator: true)
        #expect(token.candidates() == [67.00])
    }

    @Test("a bare token searches four decimal scales")
    func bareTokenSearchesItsScale() {
        let token = PumpNumber(raw: "12522", hasSeparator: false)
        #expect(token.candidates() == [12522.0, 1252.2, 125.22, 12.522])
    }

    @Test("a bare token is not discarded the way the receipt scanner discards it")
    func bareTokenIsNotDiscarded() {
        // `NumberScanner.decimals` returns nothing for `12522` (mandatory
        // separator); the pump tokenizer keeps it.
        #expect(NumberScanner.decimals(in: "12522").isEmpty)
        #expect(NumberScanner.pumpNumbers(in: "12522").map(\.raw) == ["12522"])
    }
}
