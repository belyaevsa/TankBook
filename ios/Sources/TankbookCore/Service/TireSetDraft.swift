import Foundation

/// The save-ready shape of the tire-set name form (docs/SCHEMA.md -> TireSet).
/// The typed screen holds raw text; this value type is the decision layer
/// between that string and the persisted `TireSet`, and every rule here tests
/// without a simulator (docs/TESTING.md, L1) - the same pattern as
/// `ServiceEntryDraft` and `ReminderDraft`.
///
/// The one invariant the form exists for: a tire set with no name is not a
/// set. A blank name refuses to save and names its next step (hard rule 7).
public struct TireSetDraft: Equatable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }

    /// Whether the form can save, as a decision the view and its tests share.
    public enum SaveReadiness: Equatable, Sendable {
        case ready
        /// The name is blank: nothing to call the set.
        case nameMissing
    }

    public var readiness: SaveReadiness {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .nameMissing : .ready
    }

    /// Builds the new `TireSet` the repository persists - THE create path,
    /// shared by the form and the L1 tests. A draft that is not `.ready` still
    /// builds (callers gate save on `readiness`).
    public func build(vehicleId: UUID, now: Date = Date()) -> TireSet {
        TireSet(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, name: name, purchaseExpenseId: nil)
    }

    /// The rename path: applies the form's name to an existing set in place,
    /// keeping its id, creation stamp and purchase link (P3.2 may set
    /// `purchaseExpenseId`; a rename must never overwrite it).
    public func applied(to existing: TireSet, now: Date = Date()) -> TireSet {
        var updated = existing
        updated.updatedAt = now
        updated.name = name
        return updated
    }
}
