import Foundation

// MARK: - Hard rule 13's blank-fields-only rule, in one place

/// The blank-fields-only rule (hard rule 13: the app suggests, the user
/// decides). A blank field is not a user value, so a suggestion may fill it; a
/// field the user has filled is a fact and is never overwritten.
///
/// Two callers apply the rule to different shapes and share only the decision
/// of what "blank" means, so that decision lives here once rather than as a
/// second rule beside the first:
/// - `ReceiptAttachMerge` over a typed entry's schema-optional fields (`money`
///   and `unitPrice` are blank when absent);
/// - a catalogue pick over the Vehicle edit form's text fields (RV.182:
///   `capacity` is blank when empty or whitespace only).
public enum BlankFieldsOnly {
    /// A schema-optional field is blank when it is absent.
    public static func isBlank<T>(_ value: T?) -> Bool { value == nil }

    /// A form text field is blank when it is empty or whitespace only.
    public static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
