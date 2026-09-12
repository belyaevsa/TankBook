import Foundation
import Testing
@testable import TankbookCore

// RV.270 - a fuel kind committed from till boilerplate.
//
// receipt-062 and receipt-063 are one RN-Tver Chkalovskaya till, one slip
// layout, two minutes apart. 063 resolves `АИ95ФИРМ`; 062's product line OCRs
// as `МИ95ФИРМ` at confidence 1.00 (`АИ` -> `МИ`), so the 95 marker is gone.
// The parser then read `СУГ` out of the footnote
// `1 ед.=1 литр для нефтепродуктов/СУГ` - a line EVERY RN-Tver slip prints -
// and committed `fuelKind = lpg` on a petrol fill. The footnote lists what the
// till can sell; it is never the grade this fill used. That is the receipt-side
// twin of the pump rule (`fixtures/pump/README.md`): a visible grade is evidence
// the station sells it, never that this fill used it.
//
// These are L1 tests over the OCR dumps, quoted exactly as Vision read them
// (misreads included), so a tidied-up copy of the vocabulary cannot make a test
// pass that the corpus would fail. The fix belongs in where a fuel-kind marker
// may come from, never in teaching the normaliser `МИ95` - that glyph is
// Vision's, and the next slip will misread differently.
@Suite("RV.270 fuel kind from till boilerplate")
struct RV270FuelKindBoilerplateTests {

    /// receipt-062, the full OCR dump. `МИ95ФИРМ` is the product line and the
    /// two unit legends below it are boilerplate. The `Е0`/`ЕМ` spellings are
    /// why the RV.48 noise filter's `ед.=` pattern does not catch them.
    private static let receipt062 = [
        "AO \"PH-TBLI",
        "ИКаЛЬНЫй ОтЧет ********",
        "АСІ \"РН-ТВЕРЬ\"",
        "ЗК чКаловСкая TN250",
        "ИНН: 6905035353",
        "ООО \"РН-Карт\"",
        "ТЕЛ: 8<800>200-10-70",
        "Терминаг ID: 90001685",
        "PDS NO:",
        "ЧЕК 3194/6768",
        "Оплата",
        "Операшия проведена успешно",
        "625487200682",
        "HFIN:",
        "PetroLPLUS",
        "NFPLBbEL:",
        "7013330012055589222",
        "KEPTO PPR",
        "1724Y4",
        "КОД АВГОРИЗаШИИ:",
        "8",
        "КОД Ответа:",
        "11/09/26 07:32:21",
        "„JЕТТа (ХОСТ-МСК):",
        "11/09/26 07:38:37",
        "ХЕТа СТЕРМИНаЛ):",
        "TDВЄP",
        "единиц",
        "СУмма",
        "МИ95ФИРМ",
        "30.00",
        "2139.00",
        "И1ОГО",
        "2139.00",
        "ВІЗЕДЕН OFFLINE ПИН-КОД",
        "подпись клиента не требуется",
        "..---Справочная инФормация--------",
        "ЦЕна За Вд.",
        "71.30",
        "1 Е0.=] ЛИТР ДЛЯ НЕФТЕПРОДУКТОВ/СУГ",
        "1 ЕМ.*1 МЗ ДЛЯ КПГ",
        "шежнжж нефискальный отчет********",
        ".JЕта ВРемя",
        "HHH",
        "11.09.26 07:33",
        "5905035353",
        "РН ККТ",
        "0000148: 56015857",
        "KKT",
        "00106304548452",
        "738444000123284L"
    ]

    /// receipt-063, the same till two minutes later. Its product line reads
    /// cleanly and its footnote resolves to the same boilerplate.
    private static let receipt063 = [
        "слири кл",
        "ne boлce",
        "ЗаПОЛИНТеЛСм",
        "-сє не волсе 316 eл",
        "АО \"РН-ТВЕРЬ\" АЗК TN250",
        "АЗК TN250",
        "АО \"РН-ТВЕРЬ\"",
        "KACCA-S",
        "**ж**** Нефискальный отчёт *******",
        "АD \"РН-ТВЕРЬ\"",
        "АЗК Чкаловская TN250",
        "ИНН: 6905035353",
        "ООО \"РН-Карт\"",
        "ТЕЛ: 8<800>200-10-70",
        "Терминал ID: 90014882",
        "POS Nº:",
        "чек 358/7506",
        "АВТОРИЗаЦИЯ",
        "І УСпешНо",
        "Операция проведена",
        "625487202034",
        "RRN:",
        "aтаn",
        "PetroLPlus",
        "AppLabeL:",
        "7013330012055589222",
        "Карта PPR",
        "LMRSE1",
        "КОД АВТОРИЗаЦИИ:",
        "Код ответа:",
        "11/09/26 07:34:36",
        "Дата (ХОСТ-МСК):",
        "11/09/26 07:40:51",
        "дата стерминал):",
        "СУММа",
        "единиц",
        "Товар",
        "713.00",
        "10.00",
        "АИ95ФИРМ",
        "713.00",
        "ИТОГО",
        "ВВЕДЕН OFFLINE ПИН-КОД",
        "подпись клиента не требуется",
        "--СПравочная ИНФорМацИЯ-",
        "026 г.",
        "71.30",
        "цена за ед.",
        "1 ед. =1 Литр для неФтепродУктов/СУГ",
        "1 ед.=1 М3 ДЛЯ КПГ",
        "** Нефискальный отчёт *******",
        "**Ж*",
        "11.09.26 07:41",
        "6905035353",
        "Дата Время",
        "0009495685064270",
        "ИНН",
        "00108726057221",
        "PH KKT",
        "KKT",
        "7382440900209544",
        "18HI",
        "1ЫE С"
    ]

    /// The whole failure, on 062's own dump. A nil kind is an empty field the
    /// user fills; `lpg` is a fact they must notice (hard rule 13).
    @Test("receipt-062 does not read lpg from the till's unit legend")
    func receipt062DoesNotCommitBoilerplateLpg() {
        let result = FuelExtractor().extract(textLines: Self.receipt062)
        #expect(result.fuelKind != .lpg,
                "the `/СУГ` footnote is till boilerplate, never this fill's kind")
        #expect(result.fuelKind == nil || result.fuelKind == .petrol95,
                "the slip says АИ95; a lost marker abstains, it never invents lpg")
    }

    /// The sibling still resolves. 063's product line reads `АИ95ФИРМ`, so the
    /// guard must reject the legend without swallowing a real grade.
    @Test("receipt-063 still resolves petrol95")
    func receipt063StillResolvesPetrol95() {
        let result = FuelExtractor().extract(textLines: Self.receipt063)
        #expect(result.fuelKind == .petrol95)
    }

    /// The boilerplate shapes named by the brief, in both the clean and the
    /// OCR-damaged spellings, must not be product lines. The positive half is
    /// asserted too: a rule that rejected every line would pass the negatives.
    @Test("unit legends and slash-lists are not product lines")
    func boilerplateIsNotAProductLine() {
        #expect(!FuelKindNormalizer.isProductLine("1 ед.=1 литр для нефтепродуктов/СУГ"))
        #expect(!FuelKindNormalizer.isProductLine("1 Е0.=] ЛИТР ДЛЯ НЕФТЕПРОДУКТОВ/СУГ"))
        #expect(!FuelKindNormalizer.isProductLine("1 ед.=1 М3 ДЛЯ КПГ"))
        #expect(!FuelKindNormalizer.isProductLine("1 ЕМ.*1 МЗ ДЛЯ КПГ"))
        #expect(!FuelKindNormalizer.isProductLine("для нефтепродуктов/СУГ"))

        // A real product line is untouched.
        #expect(FuelKindNormalizer.isProductLine("АИ-95-К5"))
        #expect(FuelKindNormalizer.isProductLine("ДТ-Л-К5"))
        #expect(FuelKindNormalizer.isProductLine("ТРК-19 СУГ, Л"))
    }
}
