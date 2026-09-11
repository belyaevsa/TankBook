import Foundation
import Testing
@testable import TankbookCore

// RV.200 - an Expense-mode scan must read the KIND of expense, not only its
// money. These are L1 tests over the extractor's INPUT: each fixture is the
// OCR text a receipt of that kind prints, and the expected category is the
// fixture's own name plus `expected.csv` - hand-written, never the extractor's
// output (the oracle rule in Spike/ReceiptSpike/fixtures/README.md).
//
// Nine fixtures are hand-authored text (the corpus held no non-fuel receipt
// photograph when RV.200 was filed); `parking-tallinn-airport-et.txt` is the
// Vision dump of the one photograph the folder now holds. The oracle is still
// independent of the code under test: the vocabulary never writes a fixture,
// and the fixture never runs the vocabulary.

@Suite("RV.200 expense-category inference")
struct RV200ExpenseCategoryInferenceTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()  // TankbookCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()  // repo
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/expenses")

    /// One `expected.csv` row: the fixture file and the category its NAME says
    /// it is.
    private struct Row {
        let filename: String
        let expected: ExpenseCategory?
    }

    private static func expectedRows() throws -> [Row] {
        let url = fixturesRoot.appendingPathComponent("expected.csv")
        let csv = try String(contentsOf: url, encoding: .utf8)
        return csv.split(separator: "\n").dropFirst().compactMap { line in
            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cells.count == 2 else { return nil }
            let filename = cells[0].trimmingCharacters(in: .whitespaces)
            let token = cells[1].trimmingCharacters(in: .whitespaces)
            return Row(filename: filename, expected: category(token))
        }
    }

    /// The `expected.csv` code -> `ExpenseCategory`, the only place a code is
    /// decoded. An unknown token is a fixture typo, not a silent nil.
    private static func category(_ token: String) -> ExpenseCategory? {
        switch token {
        case "none": return nil
        case "insurance": return .insurance
        case "tax": return .tax
        case "parking": return .parking
        case "toll": return .toll
        case "fine": return .fine
        case "accessory": return .accessory
        case "parts": return .parts
        case "other:wash": return .other("wash")
        default: return nil
        }
    }

    private static func lines(_ filename: String) throws -> [OCRLine] {
        let text = try String(contentsOf: fixturesRoot.appendingPathComponent(filename),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { OCRLine(text: String($0)) }
    }

    private static func infer(_ filename: String) throws -> ExpenseCategory? {
        ExpenseCategoryInference.infer(from: try lines(filename))
    }

    /// The corpus-style sweep: every fixture must infer the category its file
    /// name names. The count is asserted so a fixture silently dropped from the
    /// folder cannot make the suite pass over an empty set.
    @Test("every expense fixture infers the category its filename oracle names")
    func everyFixtureMatchesItsFilenameOracle() throws {
        let rows = try Self.expectedRows()
        #expect(rows.count == 11, "the expense fixture set changed size: \(rows.count)")
        for row in rows {
            let inferred = try Self.infer(row.filename)
            let oracle = String(describing: row.expected)
            let got = String(describing: inferred)
            #expect(inferred == row.expected,
                    "\(row.filename): filename oracle \(oracle), got \(got)")
        }
    }

    /// The named acceptance case. Oracle: `parking-ru.txt` - a Russian parking
    /// ticket, a photograph of which the corpus does not yet hold.
    @Test("a parking receipt yields .parking")
    func parkingReceiptYieldsParking() throws {
        #expect(try Self.infer("parking-ru.txt") == .parking)
    }

    /// The corpus's first non-fuel PHOTOGRAPH, read through Vision: a Tallinn
    /// Airport car-park ticket that names its kind only in Estonian
    /// (`PARKIMISTEENUS`, `Lennujaam parkla`). Oracle: the `.txt` beside the
    /// `.jpg` is the OCR dump, and the category is the file name's.
    @Test("an Estonian parking ticket yields .parking")
    func estonianParkingTicketYieldsParking() throws {
        #expect(try Self.infer("parking-tallinn-airport-et.txt") == .parking)
    }

    /// The escape hatch, not a forced standard case: `ExpenseCategory` has no
    /// native wash, so a car wash must land on `.other("wash")` exactly as the
    /// mixed-receipt detector's suggestion does.
    @Test("a car wash yields .other(\"wash\")")
    func carWashYieldsOtherWash() throws {
        #expect(try Self.infer("wash-ru.txt") == .other("wash"))
    }

    /// A fuel receipt names no separable expense kind: the vocabulary must
    /// abstain rather than force a category, and the form keeps its default.
    /// Oracle: `ambiguous-fuel-ru.txt`.
    @Test("a receipt that names no kind yields nil")
    func unrecognisedReceiptYieldsNil() throws {
        #expect(try Self.infer("ambiguous-fuel-ru.txt") == nil)
    }

    /// The RU set is the one the product owner's own receipts carry, so at
    /// least one fixture is Russian. Oracle: `parking-ru.txt`.
    @Test("the Russian vocabulary resolves a Russian receipt")
    func russianVocabularyResolvesRussianReceipt() throws {
        #expect(try Self.infer("parking-ru.txt") == .parking)
        #expect(try Self.infer("toll-ru.txt") == .toll)
        #expect(try Self.infer("fine-ru.txt") == .fine)
        #expect(try Self.infer("insurance-ru.txt") == .insurance)
        #expect(try Self.infer("tax-ru.txt") == .tax)
        #expect(try Self.infer("parts-ru.txt") == .parts)
        #expect(try Self.infer("accessory-ru.txt") == .accessory)
    }

    /// The EN half must work too - a vocabulary that only reads Russian is half
    /// a feature. Oracle: `parking-en.txt`.
    @Test("the English vocabulary resolves an English receipt")
    func englishVocabularyResolvesEnglishReceipt() throws {
        #expect(try Self.infer("parking-en.txt") == .parking)
    }

    /// A paid parking ticket carries both "парковка" and "платный" - parking
    /// precedes toll in the ordered rules, so the more specific reading wins.
    @Test("a paid parking ticket reads as parking, not toll")
    func paidParkingReadsAsParking() {
        let inferred = ExpenseCategoryInference.infer(fromText: "ПЛАТНАЯ ПАРКОВКА ЦЕНТР")
        #expect(inferred == .parking)
    }

    /// The shape-only event that makes a wrong guess visible in production: the
    /// category CODE and a boolean, never the receipt's text. A kept suggestion
    /// and a corrected one are distinguishable, and no suggestion is not a
    /// correction (hard rule 12).
    @Test("the category suggestion event carries codes and a boolean, never text")
    func categorySuggestionEventIsShapeOnly() {
        let kept = ExpenseCategorySuggestion(suggested: .parking, saved: .parking)
        #expect(kept.fields.contains(.safe("suggested", "parking")))
        #expect(kept.fields.contains(.safe("userCorrected", "false")))

        let corrected = ExpenseCategorySuggestion(suggested: .parking, saved: .toll)
        #expect(corrected.fields.contains(.safe("suggested", "parking")))
        #expect(corrected.fields.contains(.safe("userCorrected", "true")))

        // Nothing was suggested: the form's default is not a "corrected" guess.
        let none = ExpenseCategorySuggestion(suggested: nil, saved: .accessory)
        #expect(none.fields.contains(.safe("suggested", "none")))
        #expect(none.fields.contains(.safe("userCorrected", "false")))

        // The escape hatch keeps its machine code, never a localised label.
        let wash = ExpenseCategorySuggestion(suggested: .other("wash"), saved: .other("wash"))
        #expect(wash.fields.contains(.safe("suggested", "other:wash")))
    }
}
