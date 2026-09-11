import Foundation

/// The link between a `.parts` Expense and the TireSet it bought
/// (docs/SCHEMA.md -> TireSet.purchaseExpenseId, docs/JOURNEYS.md J7b "a tire
/// purchase becomes a TireSet"). The expense is the purchase record; the set is
/// the thing that gets mounted, swapped and measured - one purchase, one set,
/// and the cost counts once (at the expense, hard rule 4).
///
/// The decision layer is pure so the L1 tests drive the same conversion the
/// screen does. The link is written ONCE: a `.parts` expense that already has a
/// live set is not turned into a second one, because two sets sharing a
/// purchase would double the "what did these cost" answer while the odometer
/// spans still counted one set's mileage.
public enum TireSetPurchase {

    /// The live set this expense already bought, if any. A tombstoned set does
    /// not count - archiving a set is "put it away", and re-making one from the
    /// same purchase must be possible afterwards (hard rule 8).
    public static func linkedSet(forExpense expenseId: UUID,
                                 in sets: [TireSet]) -> TireSet? {
        sets.first { $0.deletedAt == nil && $0.purchaseExpenseId == expenseId }
    }

    /// Whether an expense can become a tire set at all: only `.parts`, and only
    /// with a name to carry over. A blank title is not a set name, and a set
    /// with no name violates `TireSetDraft`'s own invariant.
    public static func canBecomeSet(_ expense: Expense) -> Bool {
        expense.category == .parts
            && !expense.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The new set a `.parts` expense becomes, or nil when there is nothing to
    /// make. The set's default name is the expense's own words (a default input
    /// the user edits on the tire-set form, hard rule 13); the purchase link is
    /// the expense's id. `existing` is the vehicle's live sets, so a second call
    /// for the same expense returns nil rather than minting a duplicate.
    public static func makeSet(for expense: Expense,
                               existing: [TireSet],
                               now: Date = Date()) -> TireSet? {
        guard canBecomeSet(expense) else { return nil }
        guard linkedSet(forExpense: expense.id, in: existing) == nil else { return nil }
        return TireSet(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: expense.vehicleId, name: expense.title,
            purchaseExpenseId: expense.id)
    }
}
