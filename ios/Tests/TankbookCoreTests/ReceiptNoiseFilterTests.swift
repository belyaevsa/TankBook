import Foundation
import Testing
@testable import TankbookCore

// RV.48 - the cleaning stage, and the four confident-wrong values it exists to
// remove. Each case below is a line from a real corpus fixture; the lines are
// quoted exactly as Vision read them, misreads included (`nr•`, `wNLL`), so a
// tidied-up copy of the vocabulary cannot make a test pass that the corpus
// would fail.

@Suite("RV.48 receipt noise filter")
struct ReceiptNoiseFilterTests {

    // MARK: - The lines that must be classified

    @Test("the four lines that produced confident wrong values are classified")
    func theFourCulpritsAreClassified() {
        #expect(ReceiptNoiseFilter.classify("Reg.kood 10180925, KMKR nr• EE1003L")
                == .estonianRegistration)
        #expect(ReceiptNoiseFilter.classify("ИНН 5009053687") == .russianFiscalIdentifier)
        #expect(ReceiptNoiseFilter.classify("ЗН ККТ 00106900898136") == .russianFiscalIdentifier)
        #expect(ReceiptNoiseFilter.classify("1 ед.=1 литр для нефтепродуктов/суг")
                == .unitConvention)
    }

    @Test("card-terminal furniture is classified in both scripts")
    func cardTerminalLinesAreClassified() {
        #expect(ReceiptNoiseFilter.classify("ССЫЛКА RRN:") == .cardTerminal)
        #expect(ReceiptNoiseFilter.classify("ОДОБРЕНО") == .cardTerminal)
        #expect(ReceiptNoiseFilter.classify("КОД ОТВЕТА:") == .cardTerminal)
        #expect(ReceiptNoiseFilter.classify("STAATUS: 0000") == .estonianRegistration)
        // Vision reads the same acronym in Latin on receipt-044 and in Cyrillic
        // on receipt-036; the canonical key is what makes them one rule.
        #expect(ReceiptNoiseFilter.classify("PH KKT 0001582170062234")
                == .russianFiscalIdentifier)
    }

    @Test("a bare 14-digit run is an identifier, and a shorter one is money")
    func bareIdentifierBoundIsAtFourteenDigits() {
        #expect(ReceiptNoiseFilter.classify("7380440902616162") == .russianFiscalIdentifier)
        // THE BOUND IS THE POINT. A bare short decimal is the total on
        // receipt-015 and the only legible total on receipt-041; a rule that
        // reached down to eight digits would eat both.
        #expect(ReceiptNoiseFilter.classify("5380.00") == nil)
        #expect(ReceiptNoiseFilter.classify("3695.76") == nil)
        #expect(ReceiptNoiseFilter.classify("19719.00") == nil)
    }

    // MARK: - The lines that must NEVER be classified

    @Test("load-bearing lines survive the filter")
    func loadBearingLinesSurvive() {
        // The value finders read these. If any one of them is classified as
        // noise the corpus score falls, which is the failure this test exists
        // to catch before the corpus does.
        let mustSurvive = [
            "1 БеНЗИН АИ-95-К5 Ультра",          // the product line
            "269.00*20",                          // the operand pair
            "99.99 Х 25 Л",                       // the operand pair, marked
            "Аи-98 х25.00 лит х99.99 РУБ",        // the whole fill on one line
            "ИТОГ",                               // the total label
            "=5380.00",                           // its value
            "KOKKU",                              // the Estonian total label
            "D B0 miles",                         // the product line, Estonia
            "Pump 5 Hind 1,799 EUR/L",            // the unit price
            "цена за ед.",                        // the reference-block price label
            "68.30",                              // and its value
            "11.07.26 11:03"                      // the date
        ]
        for line in mustSurvive {
            #expect(ReceiptNoiseFilter.classify(line) == nil,
                    "\(line) must stay a candidate")
        }
    }

    @Test("filtering preserves order and keeps everything it does not classify")
    func candidateLinesPreserveOrder() {
        let lines = [
            OCRLine(text: "1 БеНЗИН АИ-95-К5 Ультра"),
            OCRLine(text: "ИНН 9108000588"),
            OCRLine(text: "269.00*20"),
            OCRLine(text: "ФН 7380440902616162"),
            OCRLine(text: "ИТОГ")
        ]
        let candidates = ReceiptNoiseFilter.candidateLines(lines)
        #expect(candidates.map(\.text) == ["1 БеНЗИН АИ-95-К5 Ультра", "269.00*20", "ИТОГ"])
    }

    // MARK: - End to end: the wrong values are gone

    /// receipt-041: `2X5LT6` is a card AUTHORISATION CODE. It parses as the
    /// operand pair `2 X 5L` - a digit, a multiplication sign, and a number
    /// carrying what looks like a litre marker - so the extractor preferred it
    /// over the real fuel line and reported a 5 litre fill at 2.00 per litre.
    /// The truth is 54.000 L at 68.44.
    @Test("an authorisation code is not an operand pair")
    func authorisationCodeIsNotAFuelLine() {
        let lines = [
            "АИ-95",
            "68.44 X 54.000",
            "2X5LT6",
            "ИТОГ",
            "=3695.76"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        // The honest outcome for this document is an ABSTENTION on the pair -
        // `68.44 X 54.000` carries no marker and no band provider is injected,
        // so hard rule 13 says nil. What must never come back is 5 litres.
        #expect(result.liters != 5.0)
        #expect(result.unitPrice != 2.0)
    }

    /// receipt-044: the fuel kind came from a footnote about units, not from
    /// the product. `суг` in `для нефтепродуктов/суг` made an AI-95 fill LPG,
    /// and the same line offered `1` as the volume.
    @Test("a unit-convention footnote sets neither the volume nor the fuel kind")
    func unitConventionFootnoteIsNotAProductLine() {
        let lines = [
            "AM-95",
            "1 ед.=1 литр для нефтепродуктов/суг",
            "ИТОГ",
            "=1707.50"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.fuelKind != .lpg)
        #expect(result.liters != 1.0)
    }
}

// MARK: - The two confident-wrong litres of the RN-Tver terminal slips

/// receipt-068 (photographed sideways) and receipt-072 (upright): two RN-Tver
/// PetrolPlus slips whose litres came out as `1.0` (the unit legend, garbled
/// past the `=` glyph) and `10630454945` (the `РН ККТ` register number with a
/// trailing Latin `L` read as a litre marker). Both lines belong to classes
/// the filter already names; these are the shapes that reached the operand
/// path anyway.
@Suite("Garbled unit legends and lettered identifiers are noise")
struct ReceiptNoiseFilterGarbledShapesTests {

    @Test("every garbled unit-legend read classifies as the unit convention",
          arguments: [
              "1 ед.=1 литр для нефтепродуктов/суг",          // receipt-044, the shape the rule was written for
              "1 ВД.«1 ЛИТР ДЛЯ НЕМТЕПРОДУКТОВ/СУГ",           // receipt-068, `ЕД` -> `ВД`, `=` -> `«`
              "1 ед.-1 МЗ для кт",                              // receipt-068, `=` -> `-`
              "1 На, 9), ЛИТР АЛЯ НЕИТЕ РОДИТІВ С.2",           // receipt-068 on macOS 27: only the structure survives
              "1 ед.+1 NЗ для КПГ"                              // receipt-068 on macOS 27: `=` -> `+`
          ])
    func garbledUnitLegendIsNoise(line: String) {
        #expect(ReceiptNoiseFilter.classify(line) == .unitConvention)
    }

    @Test("a long digit run with a letter on its tail is an identifier, never a volume",
          arguments: ["0010630454945L", "738444090123284L", "625987284600ł"])
    func letteredIdentifierIsNoise(line: String) {
        #expect(ReceiptNoiseFilter.classify(line) == .russianFiscalIdentifier)
    }

    /// The 19-digit card number is caught one rule earlier, as card-terminal
    /// furniture; either class keeps it off the operand path.
    @Test func longBareRunIsNoiseOfSomeClass() {
        #expect(ReceiptNoiseFilter.classify("7013330012055589222") != nil)
    }

    /// The vacuous trap: a bound that eats real values. Marked volumes with a
    /// separator and bare totals stay readable.
    @Test("marked volumes and bare totals are still value lines",
          arguments: ["23.07L", "7.68L", "5380.00", "3695.76", "30.00", "15.00", "40 л", "1069.50"])
    func realValuesAreNotNoise(line: String) {
        #expect(ReceiptNoiseFilter.classify(line) == nil)
    }

    /// receipt-072's line set, as Vision reads it: the register number under
    /// `ККТ` must never become the volume. The honest outcomes are the marked
    /// `15.00` or an abstention.
    @Test func registerNumberWithATrailingLIsNotTheVolume() {
        let lines = [
            "KKT", "6905035353", "Ккт", "0000143.56015857", "0010630454945L", "738444090123284L",
            "АО \"РН-ТВЕРЬ\" АЗК TN250", "ИНН: 6905035353", "СУМма", "единиЦ",
            "1069.50", "15.00", "ЛИРБФИРН", "1069.50", "71.30", "ШЕна за ед.",
            "1 ЕД.=1 ЛИТР дЛя нефтепродУктов/СУГ", "1 ед.=1 мЗ для КПГ", "0010630454945L"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.liters == nil || result.liters == 15.0,
                "got \(String(describing: result.liters)) - the register number must never be the volume")
    }

    /// receipt-068's line set: the garbled legend must not become one litre.
    @Test func garbledLegendIsNotOneLitre() {
        let lines = [
            "2049.00", "2049.00", "PetroLPLus", "625987284600ł", "30.00", "ЕДИНИЦ",
            "PH-Тверь", "АЗК 15", "1 На, 9), ЛИТР АЛЯ НЕИТЕ РОДИТІВ С.2",
            "ИНН: 6905035353", "1 ед.+1 NЗ для КПГ", "Шена з8 ед.", "ИТОГО", "ЛИ-95", "ТОваР"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.liters != 1.0)
    }
}
