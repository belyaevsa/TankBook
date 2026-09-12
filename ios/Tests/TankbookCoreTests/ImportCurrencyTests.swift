import Foundation
import Testing
@testable import TankbookCore

// RV.113/RV.263 - the currency question at L1: the answer reaches every
// committed row, and a currency the file DECLARES is a correctable default,
// never a fact (hard rule 13). Split from `ImportTests.swift` so that file
// stays under the repo's lint floors.

// MARK: - RV.113 the currency answer reaches every committed row

@Suite("Import currency answer (RV.113)")
struct ImportCurrencyAnswerTests {

    private static func emptyCurrencyCandidate(_ row: Int, amount: String) -> ImportCandidate {
        ImportCandidate(
            entityType: "fillUp", date: Date(timeIntervalSinceReferenceDate: 0),
            odometer: 491_206, volumeL: 40, unitPrice: "220",
            money: ImportMoney(amount: amount, currency: ""),
            fuelKind: "petrol92", isFull: true, tankLevelAfterPct: nil, note: nil,
            vehicleName: nil, provenance: ImportProvenance(tag: "import", source: "drivvo"),
            sourceRow: row)
    }

    @Test func aCurrencyQuestionWithEmptyOptionsIsDetected() {
        let parse = ImportParseResponse(
            importId: "id", format: "drivvo", scope: "vehicle",
            candidates: [], unparsed: [],
            ambiguities: [ImportAmbiguity(kind: "currency", options: [], rowCount: 2)])
        #expect(parse.hasCurrencyQuestion == true)
        #expect(parse.needsCurrencyAnswer == true,
                "a file with no currency column must be asked before it commits a guess")
    }

    /// RV.263: a file that DECLARES a currency is not a fact - the server emits
    /// the `currency` ambiguity with the declared code as its one option so the
    /// user can correct it (hard rule 13). The card must render for it too, but
    /// the pre-fill is already the answer, so it does not gate the commit.
    @Test func aFileThatDeclaresACurrencyStillHasACurrencyQuestion() {
        let parse = ImportParseResponse(
            importId: "id", format: "mfm", scope: "vehicle",
            candidates: [], unparsed: [],
            ambiguities: [ImportAmbiguity(kind: "currency", options: ["USD"], rowCount: 2)])
        #expect(parse.hasCurrencyQuestion == true,
                "a declared currency must be offered for correction, never imported as a fact")
        #expect(parse.needsCurrencyAnswer == false,
                "the declared code is the pre-filled answer, so no tap is needed")
        #expect(parse.declaredCurrency == .usd)
    }

    /// RV.263: answering a DECLARED currency with a different one re-homes every
    /// money-carrying candidate - the fix the card exists to offer.
    @Test func answeringADeclaredCurrencyReHomesTheCandidates() {
        let candidate = ImportCandidate(
            entityType: "fillUp", date: Date(timeIntervalSinceReferenceDate: 0),
            odometer: 491_206, volumeL: 40, unitPrice: "220",
            money: ImportMoney(amount: "8442", currency: "USD"),
            fuelKind: "petrol92", isFull: true, tankLevelAfterPct: nil, note: nil,
            vehicleName: nil, provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: 1)
        let parse = ImportParseResponse(
            importId: "id", format: "mfm", scope: "vehicle",
            candidates: [candidate], unparsed: [],
            ambiguities: [ImportAmbiguity(kind: "currency", options: ["USD"], rowCount: 1)])
        let rehomed = parse.candidates.map { $0.applyingCurrency(.rub) }
        #expect(rehomed[0].money?.currency == "RUB")
        #expect(rehomed[0].money?.amount == "8442",
                "the answer changes only the currency, never the amount")
    }

    /// RV.263: the commit gate distinguishes the two currency cases. A declared
    /// currency commits with no tap (the pre-fill is the answer); a no-column
    /// file blocks until the user picks, because a guess is exactly what F6
    /// forbids.
    @Test func aDeclaredCurrencyCommitsWithoutATapAndANoColumnFileDoesNot() {
        let declared = ImportParseResponse(
            importId: "id", format: "mfm", scope: "vehicle",
            candidates: [], unparsed: [],
            ambiguities: [ImportAmbiguity(kind: "currency", options: ["USD"], rowCount: 2)])
        #expect(declared.canCommit(dateFormatAnswer: nil, currencyAnswer: nil) == true,
                "a declared currency is pre-filled, so it needs no tap to commit")

        let noColumn = ImportParseResponse(
            importId: "id", format: "drivvo", scope: "vehicle",
            candidates: [], unparsed: [],
            ambiguities: [ImportAmbiguity(kind: "currency", options: [], rowCount: 2)])
        #expect(noColumn.canCommit(dateFormatAnswer: nil, currencyAnswer: nil) == false,
                "a no-column file must not commit a guessed currency")
        #expect(noColumn.canCommit(dateFormatAnswer: nil, currencyAnswer: .rub) == true,
                "answering the currency question unblocks the commit")
    }

    @Test func applyingCurrencyFillsTheEmptyCurrencyOnMoneyAndItems() {
        let money = ImportMoney(amount: "8442", currency: "")
        let item = ImportServiceItem(title: "Oil change",
                                     category: ImportCategoryTag(tag: "oil"), cost: money)
        let service = ImportCandidate(
            entityType: "serviceRecord", date: Date(timeIntervalSinceReferenceDate: 0),
            odometer: 491_206, volumeL: nil, unitPrice: nil, money: money,
            fuelKind: nil, isFull: nil, tankLevelAfterPct: nil, note: nil,
            vehicleName: nil, provenance: ImportProvenance(tag: "import", source: "drivvo"),
            sourceRow: 1, items: [item])

        let answered = service.applyingCurrency(.rub)
        #expect(answered.money?.currency == "RUB")
        #expect(answered.items?[0].cost?.currency == "RUB")
        #expect(answered.money?.amount == "8442",
                "the answer changes only the currency, never the amount")
    }

    @Test func makeFillWithAnAnsweredCurrencyProducesTheAnsweredMoney_NeverAHardcodedDefault() {
        // The empty-currency candidate, once answered, becomes money in the
        // ANSWERED currency - never nil (a dropped amount) and never a
        // hardcoded default. This is the trap the row exists to close: a parser
        // that guessed a default would pass every count assertion.
        let answered = Self.emptyCurrencyCandidate(1, amount: "8442").applyingCurrency(.kzt)
        let fill = ImportConverter.makeFill(from: answered, vehicle: ImportFixture.vehicle,
                                            source: "drivvo")
        #expect(fill?.money?.currency == .kzt)
        #expect(fill?.money?.amount == Decimal(string: "8442"))
    }

    @Test func anUnansweredEmptyCurrencyCandidateYieldsNoMoney_RatherThanAGuessedOne() {
        // Before the answer, the empty currency resolves to nil - the amount is
        // not silently retyped into a guessed currency (hard rule 3, hard rule
        // 13). The wizard's default is applied on top, never inside the converter.
        let fill = ImportConverter.makeFill(from: Self.emptyCurrencyCandidate(1, amount: "8442"),
                                            vehicle: ImportFixture.vehicle, source: "drivvo")
        #expect(fill?.money == nil)
    }
}
