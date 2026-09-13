import Foundation
import TankbookCore

// MARK: - Expense category cases

extension ExpenseCategory {
    /// The categories the Expense entry offers in the chooser, in a stable
    /// order. `.parts` is an ordinary category here - buying a part is just an
    /// expense, never a separate flow (docs/JOURNEYS.md J7b).
    static let entryCases: [ExpenseCategory] = [
        .insurance, .tax, .parking, .toll, .fine, .accessory, .parts, .other("")
    ]
}

// MARK: - Form state

/// Everything the Expense entry collects, plus the derived save gate. The typed
/// amount is the user's own digits, parsed to an exact `Decimal` on save (never
/// `Double`, docs/SCHEMA.md -> Money).
struct ExpenseEntryFormState: Equatable {
    var category: ExpenseCategory = .accessory
    var title = ""
    var amount = ""
    /// The currency the user chose (hard rule 3 - money is a pair). Set to the
    /// car's home currency at load; a foreign scan pre-fills its own.
    var currency: CurrencyCode = .eur
    /// The odometer the user typed, or blank. An expense away from the car has
    /// none, and a blank stays nil - never the "last known" as a fact (hard
    /// rule 13).
    var odometer = ""
    var date = Date()

    // Snapshots for the discard guard (SCREENMAP rule 1): the form is dirty only
    // for real edits, not the category pre-selection or the date default.
    var initialCategory: ExpenseCategory = .accessory
    var initialTitle = ""
    var initialAmount = ""
    var initialCurrency: CurrencyCode = .eur
    var initialOdometer = ""
    var initialDate = Date()

    var amountDecimal: Decimal? {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Decimal(string: trimmed)
    }

    var odometerValue: Int? {
        let trimmed = odometer.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(OdometerFormat.ungrouped(trimmed))
    }

    /// RV.62/RV.279: a scan's pre-fill becomes default input the user edits
    /// (hard rule 13). The total is offered WITH the scan's currency - the form
    /// carries a currency chip row, so a foreign total is no longer withheld as
    /// if it could not be expressed. The currency lands before the amount so
    /// the amount's symbol matches it. Nil values change nothing.
    mutating func apply(_ prefill: ExpensePrefill) {
        if let prefillCurrency = prefill.currency {
            currency = prefillCurrency
        }
        if let total = prefill.total {
            amount = ConfirmFormat.string(decimal: total, fractionDigits: 2)
        }
        if let prefillDate = prefill.date {
            date = prefillDate
        }
    }

    var hasTitle: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Save gate: a non-blank amount. The category always has a value, and the
    /// Log row names the expense from it when the title is empty (RV.187), so a
    /// title is never required to save. Even the bare `.other("")` renders the
    /// localized "Other" - a real category label the user can edit afterwards
    /// (RV.195), never an unnamed row.
    var canSave: Bool { amountDecimal != nil }

    func hasEdits() -> Bool {
        if category != initialCategory { return true }
        if title != initialTitle || amount != initialAmount { return true }
        if currency != initialCurrency { return true }
        if OdometerFormat.ungrouped(odometer) != OdometerFormat.ungrouped(initialOdometer) {
            return true
        }
        if !Calendar.current.isDate(date, inSameDayAs: initialDate) { return true }
        return false
    }
}
