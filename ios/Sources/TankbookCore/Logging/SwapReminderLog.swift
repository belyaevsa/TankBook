import Foundation

// MARK: - The tire.swapReminder line (docs/LOGGING.md §4, docs/NOTIFICATIONS.md)

/// The shape-only record of the seasonal swap-reminder proposal a tire mount
/// creates. A reminder that silently fails to schedule is indistinguishable
/// from one nobody accepted, so this event answers both halves of that question
/// with a single outcome - proposed, accepted or declined - and nothing else.
/// Hard rule 12: no date, no tire-set name, no car. The count of these lines is
/// the signal; the fields are only the outcome.
public struct SwapReminderProposal: LogEvent {
    public let eventName = "tire.swapReminder"
    public let category = LogCategory.notifications
    public let level = LogLevel.info
    public let fields: [LogField]

    /// Where the proposal went. `proposed` is emitted when a mount stages the
    /// offer; `accepted` when the user creates the reminder; `declined` when
    /// they choose "Not this time".
    public enum Outcome: String, Sendable {
        case proposed
        case accepted
        case declined
    }

    public init(outcome: Outcome) {
        fields = [.safe("outcome", outcome.rawValue)]
    }
}
