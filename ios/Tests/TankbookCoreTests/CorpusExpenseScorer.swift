import Foundation
@testable import TankbookCore

// RV.277 - the expense class's scorer, in the same shape as the fuel classes.
// The expense folder is a MIXED corpus: ten hand-authored OCR-text fixtures
// (`*.txt`, no photograph) and, since RV.200/RV.277, two photographs whose
// Vision dump is the `.txt` beside them. Both kinds are scored from the `.txt`
// input directly, never from a re-run of Vision: the `.txt` is the fixture, and
// the photograph is only where it came from.
//
// Four asserted cells, all optional in `expected.csv`: the KIND (`category`,
// the one cell the folder scored before RV.277), the `total`, the `currency`
// and the `date`. A blank cell is "the document does not say" and is skipped,
// never scored as a miss - the same rule the fuel scorer applies. `none` in the
// `category` column is a DELIBERATE assertion (the vocabulary must abstain),
// distinct from a blank cell, so it is scored rather than skipped.

/// One expense fixture's ground truth from `expenses/expected.csv`
/// (`filename,category,total,currency,date`).
struct ExpenseExpectedRow: Equatable, Sendable {
    let filename: String
    /// The asserted category. `categoryAsserted` distinguishes `none` (asserted
    /// as an abstention) from a blank cell (not asserted at all).
    let category: ExpenseCategory?
    let categoryAsserted: Bool
    /// Money, so `Decimal` - compared exactly, no numeric tolerance.
    let total: Decimal?
    let currency: CurrencyCode?
    let date: Date?
}

/// The expense class's hits/total over its asserted cells, identical in shape to
/// the fuel classes' `ScoredClass` so the one `AccuracyRatchet` guards it too.
struct ExpenseScore: Equatable, Sendable {
    let name: String
    let hits: Int
    let total: Int

    var scoredClass: ScoredClass { ScoredClass(name: name, hits: hits, total: total) }
}

extension CorpusScorer {
    /// Parses an expense `expected.csv` (header
    /// `filename,category,total,currency,date`). An empty money/date cell stays
    /// `nil` (skipped); the `category` cell is always read, and `none` maps to
    /// an asserted `nil`.
    static func loadExpenseExpected(_ url: URL) throws -> [ExpenseExpectedRow] {
        let csv = try String(contentsOf: url, encoding: .utf8)
        var rows: [ExpenseExpectedRow] = []
        for line in csv.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 2 else { continue }
            let token = cols[1].trimmingCharacters(in: .whitespaces)
            let totalCell = cols.count > 2 ? cols[2].trimmingCharacters(in: .whitespaces) : ""
            let currencyCell = cols.count > 3 ? cols[3].trimmingCharacters(in: .whitespaces) : ""
            let dateCell = cols.count > 4 ? cols[4].trimmingCharacters(in: .whitespaces) : ""
            rows.append(ExpenseExpectedRow(
                filename: cols[0].trimmingCharacters(in: .whitespaces),
                category: expenseCategory(from: token),
                categoryAsserted: !token.isEmpty,
                total: totalCell.isEmpty ? nil : Decimal(string: totalCell),
                currency: currencyCell.isEmpty ? nil : CurrencyCode(rawValue: currencyCell),
                date: dateCell.isEmpty ? nil : ConfirmDate.parse(dateCell)
            ))
        }
        return rows
    }

    /// The `expected.csv` category code -> `ExpenseCategory`. The one place the
    /// code is decoded; `none` is the vocabulary's abstention, not a case.
    static func expenseCategory(from token: String) -> ExpenseCategory? {
        switch token.trimmingCharacters(in: .whitespaces) {
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

    /// Scores the expense class from its `.txt` fixtures. The extractor is the
    /// same `FuelExtractor` the fill-up path runs (RV.277: one finder, per-kind
    /// vocabulary) and the kind is the same `ExpenseCategoryInference` the form
    /// consumes, so the scored pipeline is the app's, not a test-only one.
    static func scoreExpenses(
        name: String,
        fixtures: [(filename: String, lines: [OCRLine])],
        expected: [ExpenseExpectedRow]
    ) -> ExpenseScore {
        var hits = 0
        var total = 0
        for fixture in fixtures {
            guard let want = expected.first(where: { $0.filename == fixture.filename }) else { continue }
            let extraction = FuelExtractor().extract(lines: fixture.lines)
            if want.categoryAsserted {
                total += 1
                if ExpenseCategoryInference.infer(from: fixture.lines) == want.category { hits += 1 }
            }
            if let wantTotal = want.total {
                total += 1
                if extraction.total == wantTotal { hits += 1 }
            }
            if let wantCurrency = want.currency {
                total += 1
                if extraction.currency == wantCurrency { hits += 1 }
            }
            if let wantDate = want.date {
                total += 1
                if let raw = extraction.date, ConfirmDate.parse(raw) == wantDate { hits += 1 }
            }
        }
        return ExpenseScore(name: name, hits: hits, total: total)
    }
}
