import Foundation
import Testing
@testable import TankbookCore

// P2.10 - KZT is never detected. The tenge marker `тг` OCRs as `гг` on the
// Kazakh receipt (receipt-033 prints `(6000,00 гг)`), so the marker family
// alone cannot resolve it - the currency must come from the document's own
// evidence (docs/SCHEMA.md types money as a pair, so an undetected currency is
// a fill-up that cannot be converted). These are the fast, deterministic
// checks; the L5 gate scores the same behaviour against the live corpus.

@Suite("Fuel extractor: currency (P2.10)")
struct FuelExtractorCurrencyTests {

    /// receipt-033 (ЛУКОЙЛ Лубрикантс Центральная Азия, Astana, KZ): the tenge
    /// marker `тг` OCRs as `гг` (`(6000,00 гг)`), so the marker family cannot
    /// resolve it. The document still names its country: the OFD host
    /// `consumer.kofd.kz`, the tax authority `КГД`, the Kazakh VAT acronym
    /// `ККС` and the Kazakh total label `ЖИЫНЫ`. KZT is the only legal tender
    /// in Kazakhstan, so the country IS the currency.
    @Test("receipt-033: the Kazakh receipt resolves KZT from document evidence")
    func receipt033ResolvesKZT() {
        let lines = [
            "ТОО \"ЛУКОЙЛ Лубриканте Центральная Азия\"",
            "ККС Сериясы/НДС Серия 60001 Nº0040002",
            "ТРК 1:АИ-92-К4",
            "24.690 Х 243.00=6000.00",
            "ЖИЫНЫ/ИТОГ",
            "=6000.00",
            "ПЛАТЕЖНАЯ КАРТА",
            "=6000.00",
            "Сонын ішінде ККС/в т.ч. НДС 16%",
            "БКМ МКК (МТH) Коды/Код ККМ КГД (PHM) :",
            "consumer.kofd.kz",
            "Трана. продажи: 244344 (6000,00 гг)"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.currency == .kzt)
        // The rest of the fixture is untouched by this fix: the unmarked
        // operand pair stays undecided (P2.9), so only currency moves.
        #expect(result.fuelKind == .petrol92)
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    /// The brief filed receipt-035 as KZ ("the same country and card family"),
    /// but the fixture is Russian: expected.csv says RUB, the README calls it
    /// "the same corporate card as receipt-034", and its OCR carries no tenge
    /// evidence at all - no `гг`, no КГД/kofd.kz, no 16% VAT, no Kazakh text.
    /// The correct outcome is therefore ABSTENTION, not a KZT guess: hard rule
    /// 13 says a nil beats a confident wrong answer. This test pins that the
    /// KZT rule does not overreach onto the RU fuel-card fixture.
    @Test("receipt-035: a Russian fuel-card receipt is not dragged to KZT")
    func receipt035IsNotDraggedToKZT() {
        let lines = [
            "ТРК(МРК,ГНК): 6",
            "Бензин G-Drive 95(АИ-95-К5)",
            "=2747.16",
            "70.44 X 39.000",
            "лимита:",
            "=2747.16",
            "итоГО:",
            "указана цена на азс на дату",
            "продажи.",
            "топливная карта"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.currency == nil)
    }

    /// receipt-017 (Татнефть, 24.06.20): a RUB receipt that resolves RUB via
    /// the printed `РУБ` marker. The loosened KZT matcher must not drag it to
    /// KZT - the explicit marker wins, and the document carries no KZ evidence
    /// anyway.
    @Test("receipt-017: a RUB receipt still resolves RUB")
    func receipt017StillResolvesRUB() {
        let lines = [
            "ТРК-6 ДТ-Е-К5 Танеко",
            "=961.80 РУБ",
            "48.09 X 20",
            "=160.30 РУБ",
            "НДС 20%",
            "=961.80 РУБ",
            "ИТОГ:",
            "=961.00 РУБ",
            "СКИДКА =-0.80 РУБ"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.currency == .rub)
    }

    /// An explicit marker outranks the KZ gate even on a document that also
    /// carries KZ-looking evidence: a printed ₽/руб names the currency; the
    /// country tokens are only consulted when no marker was readable. Without
    /// this ordering a single KZ token on a RU document would drag it to KZT.
    @Test("an explicit RUB marker outranks the KZ evidence gate")
    func explicitMarkerOutranksKazakhstanEvidence() {
        let lines = [
            "ИТОГ",
            "=961.00 РУБ",
            "Сонын ішінде ККС/в т.ч. НДС 16%",
            "Трана. продажи: 244344 (6000,00 гг)"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.currency == .rub)
    }

    /// The point of the task: where the document does not say, nil. receipt-033
    /// stripped of every KZ token - the same digits, the same money-first
    /// total - must NOT resolve KZT, or the rule is a magnitude heuristic in
    /// disguise (6000.00 tenge and 6000.00 roubles are the same digits; only
    /// the document says which).
    @Test("a KZT-sized receipt without document evidence returns nil")
    func noEvidenceReturnsNil() {
        let stripped = [
            "ТРК 1:АИ-92-К4",
            "24.690 Х 243.00=6000.00",
            "ИТОГ",
            "=6000.00"
        ]
        let result = FuelExtractor().extract(textLines: stripped)
        #expect(result.currency == nil)
    }

    /// The misread marker `гг` after a digit is ALSO the Russian years
    /// abbreviation ("2019-2026 гг."), so it must never name a currency alone.
    @Test("the tenge marker misread alone is not a currency")
    func misreadMarkerAloneIsNotEnough() {
        let result = FuelExtractor().extract(textLines: ["2019-2026 гг", "ИТОГ", "6000.00"])
        #expect(result.currency == nil)
    }

    /// A correctly-read tenge marker resolves KZT outright: `тг` beside a
    /// number, the `₸` sign, the word, the code.
    @Test("a correctly-read tenge marker resolves KZT")
    func correctTengeMarkerResolvesKZT() {
        #expect(FuelExtractor().extract(textLines: ["Итого", "6000.00 тг"]).currency == .kzt)
        #expect(FuelExtractor().extract(textLines: ["Итого", "6000,00 ₸"]).currency == .kzt)
        #expect(FuelExtractor().extract(textLines: ["6000.00 тенге"]).currency == .kzt)
        #expect(FuelExtractor().extract(textLines: ["Итого", "6000.00 KZT"]).currency == .kzt)
    }

    /// The brief's evidence list - the marker plus the VAT rate - resolves KZT
    /// even with no uniquely-Kazakh token in the document: receipt-033's
    /// `(6000,00 гг)` misread corroborated by the 16% KZ VAT rate. `гг` alone
    /// is not enough (see the years test above); the two together are.
    @Test("the misread marker corroborated by the KZ VAT rate resolves KZT")
    func misreadMarkerPlusVATResolvesKZT() {
        let lines = [
            "в т.ч. НДС 16%",
            "Трана. продажи: 244344 (6000,00 гг)"
        ]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.currency == .kzt)
    }
}
