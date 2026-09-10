import Foundation

// MARK: - The expense.category.suggest line (RV.200, docs/LOGGING.md §4)

/// The shape-only record of one Expense-mode scan's category suggestion,
/// emitted at the expense save. It answers the two questions a wrong guess
/// makes worth asking - did the scan infer a kind, and did the user keep it? -
/// with the category CODE and a boolean, never the receipt's text, title or
/// merchant (hard rule 12). `userCorrected` is the same signal `capture.pipeline`
/// records for fuel fields, measured where it is finally knowable: at the save,
/// comparing the suggestion with what was stored.
///
/// It lives beside `CaptureCommitLog` rather than in `LogEvents.swift`, which is
/// already over its file-length limit.
public struct ExpenseCategorySuggestion: LogEvent {
    public let eventName = "expense.category.suggest"
    public let category = LogCategory.capture
    public let level = LogLevel.info
    public let fields: [LogField]

    /// `suggested` is the inference's answer (nil when it named no kind);
    /// `saved` is the category the expense was actually written with. The
    /// corrected flag is false when nothing was suggested - there was no
    /// proposal to correct - and false when the suggestion was accepted.
    public init(suggested: ExpenseCategory?, saved: ExpenseCategory) {
        fields = [
            .safe("suggested", Self.code(suggested)),
            .safe("userCorrected", (suggested != nil && suggested != saved) ? "true" : "false")
        ]
    }

    /// The stable code for a category, never its localised label: `.other("wash")`
    /// is `other:wash` and an unrecognised scan is `none`. A code is Safe; the
    /// `.other` payload is the app's own machine token, not the user's text
    /// (docs/SCHEMA.md).
    public static func code(_ category: ExpenseCategory?) -> String {
        guard let category else { return "none" }
        switch category {
        case .insurance: return "insurance"
        case .tax: return "tax"
        case .parking: return "parking"
        case .toll: return "toll"
        case .fine: return "fine"
        case .accessory: return "accessory"
        case .parts: return "parts"
        case .other(let value): return "other:\(value)"
        }
    }
}
