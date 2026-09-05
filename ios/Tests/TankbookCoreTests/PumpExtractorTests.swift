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

    @Test("pump-005 with no currency marker: the total commits, the pair does not")
    func pump005WithoutCurrencyAbstains() {
        // The Dresser-Wayne photo OCRs no currency word, so the band cannot pin
        // the bare board price `5256` to 52.56 - the PRICE therefore abstains.
        //
        // The volume and total do NOT, and the reason is the money-shape rule
        // (`PumpNumber.moneyCandidates`): a total is printed whole or to the
        // minor unit, so `462108` is 4621.08 or 462108 and never 46210.8, and
        // `462108` is 4621.08 or 462108 and never 46210.8. Only 4621.08 can be
        // reached by any plausible fill, so the TOTAL commits. The volume does
        // not: with the price's own scale unpinned, several (volume, price)
        // pairs reach the same total, so it abstains - each field commits on its
        // own evidence rather than being dragged along by a sibling.
        let lines = ["СУММА", "462108", "ЛИТРЫ", "8792",
                     "52.06", "4932 5256", "ЦЕНА ЗА ЛИТР", "55.18"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        #expect(result.unitPrice == nil)
        #expect(result.liters == nil)
        #expect(result.total == decimal("4621.08"))
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
        #expect(result.liters == 87.92)
        #expect(result.total == decimal("4621.08"))
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

    @Test("pump-057: the money shape breaks the factor-of-ten tie the arithmetic cannot")
    func pump057ResolvesThroughTheMoneyShape() {
        // € 10038 (100.38), L 005580 (55.80), €/L 1,799 - the display of the
        // matched pair whose paper (receipt-046) says 55.80 L at 1.799 = 100.38.
        //
        // THE ARITHMETIC ALONE CANNOT CHOOSE, and this fixture is why the money
        // shape exists: `55.80 x 1.799 = 100.38` and `5.58 x 1.799 = 10.038`
        // both close exactly, because the cross-check is scale-invariant. A
        // 5.58 L fill is perfectly real (the pumps print `Vmin 2 LIITRIT`), so
        // no plausibility bound separates them either. What separates them is
        // that a TOTAL is money: `10.038` is three decimals and no currency
        // prints an amount that way, so it is not a candidate at all.
        let lines = ["€", "10038", "L", "005580", "€/L", "1,799"]
        let result = pumpExtractor().extract(textLines: lines, source: .pump)
        #expect(result.unitPrice == decimal("1.799"))
        #expect(result.liters == 55.80)
        #expect(result.total == decimal("100.38"))
    }

    @Test("a three-decimal total is not money, so it never breaks the tie the wrong way")
    func moneyShapeRejectsThreeDecimals() {
        // The mutation guard for the rule above: if `moneyCandidates` admitted
        // three decimals, `5.58 x 1.799 = 10.038` would survive alongside the
        // truth and pump-057 would go back to abstaining - or worse, commit the
        // factor-of-ten reading. Assert the candidate set itself, not just the
        // outcome, so a widening is caught here rather than in the corpus.
        let token = PumpNumber(raw: "10038", hasSeparator: false)
        #expect(token.moneyCandidates() == [10038, 100.38])
        // A whole-tenge total is still money: pump-004 prints `3008` for a
        // 3008.34 fill and pump-006 prints `10980`.
        #expect(PumpNumber(raw: "10980", hasSeparator: false).moneyCandidates().contains(10980))
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
