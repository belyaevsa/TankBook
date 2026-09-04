import Foundation
import Testing
@testable import TankbookCore

// RV.48 - the vocabulary and marker gaps found by reading the live OCR of all
// 46 receipt fixtures. Each test names the fixture it came from and the number
// of corpus cells it moved, so a later reader can tell a real rule from a
// fixture-shaped one.

@Suite("RV.48 extraction vocabulary and markers")
struct ReceiptExtractionVocabularyTests {

    /// receipt-031 and receipt-037 print the litre marker as an UPPERCASE
    /// Cyrillic `Л` (U+041B). The marker class held only lowercase `л`
    /// (U+043B) and Latin `L`, so neither line was recognised as the fuel line;
    /// the ladder fell through to the first operand pair on the page, which on
    /// receipt-031 is the `БЕЗ СКИДКИ` list-price line, and abstained. Worth
    /// four cells.
    @Test("an uppercase Cyrillic Л marks the volume")
    func uppercaseCyrillicLitreMarker() {
        let result = FuelExtractor().extract(textLines: [
            "АИ-95",
            "БЕЗ СКИДКИ 30.000 Х 71.05 Р. = 2 131.50",
            "69.98 Х 30 Л",
            "ИТОГ",
            "=2099.40"
        ])
        #expect(result.liters == 30.0)
        #expect(result.unitPrice == Decimal(string: "69.98"))
    }

    /// receipt-036 spells the marker out - `лит` - and prints the whole fill on
    /// one line with TWO multiplication signs: `Аи-98 х25.00 лит х99.99 РУБ`.
    /// The leftmost `num op num` match is `98 х 25.00`, so the octane of the
    /// grade name became the unit price and the total came back as 25 x 98 =
    /// 2450.00 against a printed 2499.75. A grade number is not an operand.
    @Test("a grade number is not an operand, and лит is a marker")
    func gradeNumberIsNotAnOperand() {
        let result = FuelExtractor().extract(textLines: [
            "Аи-98 х25.00 лит х99.99 РУБ",
            "СУММА:",
            "2499.75 РУБ"
        ])
        #expect(result.liters == 25.0)
        #expect(result.unitPrice == Decimal(string: "99.99"))
        #expect(result.total == Decimal(string: "2499.75"))
    }

    /// receipt-036 again: the Russian total label is Cyrillic `СУММА`, and the
    /// vocabulary carried only the Latin `SUMMA` of the Estonian receipts. The
    /// two are different code points and `uppercased()` never bridges them.
    @Test("Cyrillic СУММА is a total label and СУММА НДС is still not")
    func cyrillicSummaIsATotalLabel() {
        #expect(TotalLabel.classify("СУММА:") == .primary)
        #expect(TotalLabel.classify("SUMMA") == .primary)
        // The exclusion list is checked first, so the VAT line stays out.
        #expect(TotalLabel.classify("СУММА НДС 22%") == nil)
        #expect(TotalLabel.classify("СУММА БЕЗ НДС") == nil)
    }

    /// The Circle K loyalty grade names are the product string on every
    /// Estonian receipt in the corpus (001, 038, 039, 042, 045, 046) and name a
    /// fuel nowhere else in the vocabulary. The zero is matched as `[0OÓ]`
    /// because the corpus carries `B0`, `BO` and `BÓ` for the same grade.
    @Test("Circle K loyalty grades resolve to a fuel kind")
    func circleKLoyaltyGrades() {
        #expect(FuelKindNormalizer.normalize("D B0 miles") == .diesel)
        #expect(FuelKindNormalizer.normalize("D BO miles") == .diesel)
        #expect(FuelKindNormalizer.normalize("D BÓ miles") == .diesel)
        #expect(FuelKindNormalizer.normalize("95E0 miles") == .petrol95)
        // The MILES suffix is required, so a bare D or a bare 95 elsewhere on
        // the receipt cannot reach this path.
        #expect(FuelKindNormalizer.normalize("D B0") == nil)
        #expect(FuelKindNormalizer.normalize("Pump 5") == nil)
    }

    /// A Russian fiscal receipt is denominated in roubles by law, and it names
    /// its fiscal system even when it prints no currency word Vision can read -
    /// which is 28 of the corpus's 39 currency cells.
    @Test("a Russian fiscal receipt resolves RUB from document evidence")
    func russianFiscalEvidenceResolvesRUB() {
        let result = FuelExtractor().extract(textLines: [
            "ООО\"КЕДР\" АЗС-98",
            "Кассовый чек",
            "1 БеНЗИН АИ-95-К5 Ультра",
            "269.00*20",
            "ИТОГ",
            "=5380.00",
            "ЗН ККТ 00106900898136",
            "ИНН 9108000588",
            "ПРИХОД"
        ])
        #expect(result.currency == .rub)
    }

    /// The precedence that keeps the new gate honest: `receipt-033` is a
    /// KAZAKH receipt printed in Russian. Kazakhstan is tested first, and the
    /// Kazakh document carries no `ИНН` or `ККТ` of its own.
    @Test("a Kazakh receipt in Russian is still KZT, not RUB")
    func kazakhstanStillOutranksRussia() {
        let result = FuelExtractor().extract(textLines: [
            "ТОО \"ЛУКОЙЛ Лубриканте Центральная Азия\"",
            "ККС Сериясы/НДС Серия 60001 Nº0040002",
            "ТРК 1:АИ-92-К4",
            "24.690 Х 243.00=6000.00",
            "ЖИЫНЫ/ИТОГ",
            "=6000.00",
            "consumer.kofd.kz"
        ])
        #expect(result.currency == .kzt)
    }

    /// An Estonian receipt carries none of the Russian evidence and must stay
    /// on its own explicit marker.
    @Test("an Estonian receipt is EUR and never RUB")
    func estonianReceiptIsUnaffected() {
        let result = FuelExtractor().extract(textLines: [
            "Circle K Sikupilli teenindusjaam",
            "D B0 miles      55,80L      100,38",
            "Pump 5 Hind  1,799 EUR/L",
            "KOKKU                       100,38"
        ])
        #expect(result.currency == .eur)
    }

    /// A receipt that says nothing about its currency still says nothing. The
    /// gate reads the fiscal system, never the language: Russian is printed in
    /// several countries, and a guessed currency is a wrong fact stated
    /// confidently (hard rule 13).
    @Test("a Russian-language receipt with no fiscal evidence stays nil")
    func languageAloneIsNotEvidence() {
        let result = FuelExtractor().extract(textLines: [
            "Топливная карта",
            "АИ-95",
            "39.000",
            "ИТОГ",
            "=2747.16"
        ])
        #expect(result.currency == nil)
    }
}
