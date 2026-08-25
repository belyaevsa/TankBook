import Foundation

/// The COMPLETE transition's entry hand-off (docs/SCHEMA.md -> "Reminder
/// lifecycle (normative)": completing a reminder prompts "log the cost?" and
/// opens a pre-filled entry). Two decisions the completion sheet and the entry
/// screens must agree on live here, so the sheet's Skip path and the entry
/// screen's save path write identically:
///
/// 1. which entry a reminder category pre-fills - a `ServiceRecord` for
///    service work, an `Expense` for insurance (the one non-service reminder
///    category; docs/JOURNEYS.md J7c: "one tap opens the service/expense entry
///    pre-filled"); and
/// 2. how a completion's two rows (the completed history + the next occurrence)
///    persist, so both paths produce the same on-disk result.
public enum ReminderCompletion {

    /// The entry the "type amount" pre-fill opens.
    public enum EntryKind: Equatable, Sendable {
        case service(ServiceCategory)
        case expense(ExpenseCategory)
    }

    /// The pre-fill defaults an entry screen starts from. Every field is a
    /// DEFAULT INPUT the user edits (hard rule 13), never a fact - the
    /// completion is keyed on the entry id the save produces, not on these
    /// values, so editing any of them before saving changes nothing about the
    /// reminder transition itself.
    public struct Prefill: Equatable, Sendable {
        public var title: String
        public var kind: EntryKind
        public var odometer: Int?

        public init(title: String, kind: EntryKind, odometer: Int?) {
            self.title = title
            self.kind = kind
            self.odometer = odometer
        }
    }

    /// Maps a reminder category to the entry the completion pre-fill opens.
    /// `.insurance` is the only non-service reminder category; every service
    /// category maps to its `ServiceCategory` twin, and `.custom`/`.other`
    /// fall through to `.other` (free text) so a bespoke reminder still lands
    /// on the service path with its title pre-filled.
    public static func entryKind(for category: ReminderCategory) -> EntryKind {
        switch category {
        case .insurance: return .expense(.insurance)
        case .other(let value): return .service(.other(value))
        default: return .service(serviceCategoryMap[category] ?? .other(""))
        }
    }

    /// The service-category twins of the fixed service reminder categories
    /// (`.custom`/`.other`/`.insurance` are absent - they are handled above).
    private static let serviceCategoryMap: [ReminderCategory: ServiceCategory] = [
        .oil: .oil,
        .brakes: .brakes,
        .tires: .tires,
        .battery: .battery,
        .filters: .filters,
        .inspection: .inspection,
        .repair: .repair,
        .parts: .parts,
        .wash: .wash
    ]

    /// The pre-fill a completion produces: the reminder's title and category
    /// plus the current odometer. The app applies these to the editable entry
    /// form (they are defaults, not facts - hard rule 13).
    public static func prefill(for reminder: Reminder,
                               currentOdometer: Int?) -> Prefill {
        Prefill(title: reminder.title,
                kind: entryKind(for: reminder.category),
                odometer: currentOdometer)
    }

    /// Persists a completion's two rows: the completed reminder (now history)
    /// and, when recurrence produced one, the next occurrence. Both the sheet's
    /// Skip path (`.done(nil)`) and the entry screen's save path
    /// (`.done(entryId)`) write through here so they cannot diverge.
    public static func persist(_ result: ReminderLifecycle.CompleteResult,
                               repository: TankbookRepository) throws {
        try repository.upsertReminder(result.completed)
        if let next = result.nextOccurrence {
            try repository.upsertReminder(next)
        }
    }
}
