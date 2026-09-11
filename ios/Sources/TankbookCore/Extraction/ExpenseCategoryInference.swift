import Foundation

// MARK: - RV.200 the expense-category vocabulary
//
// An Expense-mode scan runs the same `CapturePipeline` as a fuel receipt, but
// until this vocabulary existed the category it landed in was never read: the
// form opened at its `.accessory` default for a parking ticket, a toll, a car
// wash and an insurance invoice alike. This is the one seam that reads the
// scan's own OCR lines for a KIND of expense, and it is deliberately a
// SUGGESTION: the result rides `ExpenseEntrySession.pendingPreset` into the
// form's editable category field (hard rule 13), never a stored fact.
//
// Where the vocabulary lives: beside the other extraction vocabularies
// (`FuelKindNormalizer`, `StationNameExtractor`, the AdBlue word list in
// docs/EXTRACTION.md). It is core, pure and image-free, so the mapping is
// L1-testable with plain `[OCRLine]` on macOS - the same tier rule
// `FuelKindNormalizer` obeys.
//
// Bilingual by construction, with the Estonian words the corpus has actually
// met: the separable kinds are identified by the words that print on the
// receipt, and the Russian set is the one the product owner's own receipts
// carry. Every stem is matched through
// `FuelKindNormalizer.canonicalKey`, so a Cyrillic letter Vision reads as its
// Latin twin (docs/EXTRACTION.md -> homoglyph canonicalisation) cannot make a
// word stop matching.
//
// Conservative by construction, and the `nil` answer is the point: a scan that
// names no kind returns nil and the form opens at its default with no error
// (hard rules 7 and 13). A vocabulary that always answers is a vocabulary that
// guesses, and a wrong category presented as a fact is worse than none.

public enum ExpenseCategoryInference {
    /// The category a scan's own lines suggest, or nil when they name no
    /// separable kind. The lines are the extractor's INPUT, never its output:
    /// the suggestion is read from what the receipt printed, not from a value
    /// another extractor already guessed.
    public static func infer(from lines: [OCRLine]) -> ExpenseCategory? {
        infer(fromText: lines.map(\.text).joined(separator: "\n"))
    }

    /// The same inference over raw text. Exposed so a fixture can be read as
    /// one string and a UI seed can hand the vocabulary the lines it staged.
    public static func infer(fromText text: String) -> ExpenseCategory? {
        let key = matchingKey(text)
        for rule in rules where rule.stems.contains(where: { key.contains($0) }) {
            return rule.category
        }
        return nil
    }

    /// Uppercase, then the shared homoglyph canonicalisation, applied to BOTH
    /// the OCR'd text and every stem - the same discipline `FuelKindNormalizer`
    /// uses so the two scripts cannot disagree about a glyph that looks like a
    /// twin.
    private static func matchingKey(_ text: String) -> String {
        FuelKindNormalizer.canonicalKey(text.uppercased())
    }

    private struct Rule {
        let category: ExpenseCategory
        let stems: [String]
    }

    /// Ordered: the first matching rule wins. Parking precedes toll because a
    /// paid parking ticket carries both `ПАРКОВК` and `ПЛАТН`, and parking is
    /// the more specific reading. Wash precedes everything for the same reason
    /// on a forecourt receipt that names a car wash beside a fuel line.
    private static let rules: [Rule] = [
        Rule(category: .other("wash"), stems: keys([
            "МОЙК", "МОЕЧН", "АВТОМОЙК", "ХИМЧИСТК", "WASH", "CARWASH", "CAR WASH"
        ])),
        Rule(category: .parking, stems: keys([
            "ПАРКОВК", "ПАРКОВОЧН", "СТОЯНК", "PARKING", "PARKHAUS", "PARKPLATZ",
            "PARKIMI", "PARKLA"
        ])),
        Rule(category: .toll, stems: keys([
            "ПЛАТН", "ТОЛЛ", "ВЗИМАН", "TOLL", "TOLLWAY",
            "ПЛАТНЫЙ УЧАСТОК", "ПУНКТ ВЗИМАНИЯ"
        ])),
        Rule(category: .fine, stems: keys([
            "ШТРАФ", "ПОСТАНОВЛЕН", "ГИБДД", "АДМИНИСТРАТИВН",
            "PENALTY", "TRAFFIC FINE", "SPEEDING"
        ])),
        Rule(category: .insurance, stems: keys([
            "СТРАХОВ", "ОСАГО", "КАСКО", "ПОЛИС", "INSURANCE", "INSURER"
        ])),
        Rule(category: .tax, stems: keys([
            "НАЛОГ", "ГОСПОШЛИН", "ПОШЛИН", "ТРАНСПОРТНЫЙ",
            "VEHICLE TAX", "ROAD TAX", "INCOME TAX"
        ])),
        Rule(category: .parts, stems: keys([
            "ЗАПЧАСТ", "АВТОЗАПЧАСТ", "ФИЛЬТР", "КОЛОДК", "СВЕЧ", "АМОРТИЗАТОР",
            "РЕМКОМПЛЕКТ", "ГЛУШИТЕЛ", "АККУМУЛЯТОР", "PARTS", "FILTER", "BRAKE"
        ])),
        Rule(category: .accessory, stems: keys([
            "АКСЕССУАР", "КОВРИК", "ЧЕХОЛ", "АРОМАТИЗАТОР", "ДЕРЖАТЕЛЬ", "ACCESSOR"
        ]))
    ]

    private static func keys(_ stems: [String]) -> [String] {
        stems.map(matchingKey)
    }
}
