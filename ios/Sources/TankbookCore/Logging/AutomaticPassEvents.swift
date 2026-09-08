import Foundation

// RV.139 - shape-only observability for the automatic foreground pass
// (docs/LOGGING.md §4). The pass in `TabRoots.runAutomaticPass` awaits six
// work items in order (config, monthly summary, sync, rates, the two outbox
// drains), and before RV.139b nothing recorded that it started, which step it
// reached, or that it finished - so a pass that stalled at step 3 read in the
// log exactly like a pass that never ran. This event is the skeleton: one
// `automatic.pass` line per mark, emitted BEFORE the step it names is awaited,
// so a hang mid-step still leaves every mark up to and including it already
// written. Absence of the line means `runAutomaticPass` never ran.

/// One mark on the automatic foreground pass. Stable codes only - Safe class,
/// never a domain value (hard rule 12). `.started` precedes the first step,
/// each step code precedes its own await, `.finished` follows the last.
public enum AutomaticPassMark: String, Sendable, CaseIterable, Equatable {
    /// The pass began. Emitted before the first step's await, so "the pass was
    /// reached at all" is itself observable - the absence that RV.139 could
    /// not separate from "it stalled before step 1".
    case started
    /// Reaching `configService.refresh()`.
    case config
    /// Reaching the monthly-summary re-arm.
    case summary
    /// Reaching the opportunistic sync cycle.
    case sync
    /// Reaching `AppRates.refresh()` - the step whose silence RV.139 chased.
    case rates
    /// Reaching the delivery-outbox drain.
    case delivery
    /// Reaching the feedback-outbox flush.
    case feedback
    /// The pass returned from its last step.
    case finished
}

/// One mark of the automatic foreground pass (`automatic.pass`). Shape only: a
/// step code and nothing else - the pass touches config, sync and money, so the
/// event carries no value that could leak any of them by construction.
public struct AutomaticPass: LogEvent {
    public let eventName = "automatic.pass"
    public let category = LogCategory.ui
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(step: AutomaticPassMark) {
        fields = [
            .safe("step", step.rawValue),
        ]
    }
}
