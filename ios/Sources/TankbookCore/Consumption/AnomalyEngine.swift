import Foundation

// MARK: - The anomaly the detector may return

/// The metric an anomaly is about. One case today - consumption in L/100km
/// (`Segment.per100`; kWh/100km for an EV, where `Segment.litres` carries kWh).
/// A future metric (cost per km, an EV-only energy rise) adds a case; the
/// detector, the threshold constants and the dismissal keying all work
/// unchanged.
public enum AnomalyMetric: String, Codable, Sendable, Hashable {
    case consumption
}

/// What "the same cause" means for a dismissal: the metric plus the calendar
/// month the evaluated window closes in. A dismissal is keyed by this and only
/// this - dismissing one month's anomaly suppresses that month and nothing
/// else, so "dismiss" can never silently become "mute everything"
/// (docs/JOURNEYS.md J9, "always dismissible with a reason"; muting everything
/// is the opposite of teaching the model). A recompute inside the same month
/// stays suppressed; a later month, or a different metric, is a new cause and
/// may fire on its own.
public struct AnomalyCause: Hashable, Sendable, Codable {
    public let metric: AnomalyMetric
    /// The calendar year of the month the evaluated window closes in.
    public let evaluatedYear: Int
    /// The calendar month (1-12) the evaluated window closes in.
    public let evaluatedMonth: Int

    public init(metric: AnomalyMetric, evaluatedYear: Int, evaluatedMonth: Int) {
        self.metric = metric
        self.evaluatedYear = evaluatedYear
        self.evaluatedMonth = evaluatedMonth
    }

    /// The cause for an evaluation window closing on `date` - the calendar
    /// month containing `date`. Month granularity, not day: the suppression
    /// must survive a recompute a few days later inside the same window.
    public init(metric: AnomalyMetric, evaluatedOn date: Date, calendar: Calendar) {
        self.metric = metric
        self.evaluatedYear = calendar.component(.year, from: date)
        self.evaluatedMonth = calendar.component(.month, from: date)
    }
}

/// A recorded dismissal of an anomaly, with the reason the user gave. This is
/// the data that MAY be persisted - the verdict never is (hard rule 2): the
/// anomaly re-derives on every recompute, and the dismissal is the only thing
/// remembered. It mirrors the reminder precedent exactly
/// (`ReminderStatus.dismissed(reason:)`, `ReminderLifecycle.dismiss`): the
/// reason is carried as data and feeds the insight logic later ("dismissed:
/// sold the tires", docs/JOURNEYS.md J9).
public struct AnomalyDismissal: Hashable, Sendable, Codable {
    public let cause: AnomalyCause
    public let reason: String?
    public let dismissedAt: Date

    public init(cause: AnomalyCause, reason: String?, dismissedAt: Date) {
        self.cause = cause
        self.reason = reason
        self.dismissedAt = dismissedAt
    }
}

/// One side of the anomaly comparison: the window actually compared, its
/// distance-weighted value, and how many segments fed it. P6.1b draws the
/// evidence chart from these without recomputing anything (hard rule 2: the
/// view does no arithmetic).
public struct AnomalyWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// Distance-weighted consumption over the window (L/100km): the same
    /// Σ litres / Σ km x 100 the headline uses (docs/SCHEMA.md -> HEADLINE).
    public let value: Double
    public let segmentCount: Int

    public init(start: Date, end: Date, value: Double, segmentCount: Int) {
        self.start = start
        self.end = end
        self.value = value
        self.segmentCount = segmentCount
    }
}

/// The described anomaly (docs/SCHEMA.md, Derived: consumption -> ANOMALY;
/// docs/JOURNEYS.md J9). P6.1b renders the card from this; every number the
/// card shows is here, so the UI adds no arithmetic. `nil` from the engine
/// means "stays quiet" - a non-nil value is a deliberate, thresholded,
/// seasonally-fair opinion.
public struct ConsumptionAnomaly: Equatable, Sendable {
    public let cause: AnomalyCause
    public let metric: AnomalyMetric
    /// Distance-weighted consumption over the rolling window (L/100km).
    public let rollingValue: Double
    /// Distance-weighted consumption over the seasonally-aligned baseline
    /// window, one year earlier (L/100km).
    public let baselineValue: Double
    /// Relative elevation: (rolling - baseline) / baseline, as a fraction.
    /// J9's "+12%".
    public let magnitude: Double
    /// The window the anomaly refers to: the trailing 90 days.
    public let rollingWindow: AnomalyWindow
    /// The window it was compared against: the same 90 days one year earlier.
    public let baselineWindow: AnomalyWindow

    public init(cause: AnomalyCause, metric: AnomalyMetric,
                rollingValue: Double, baselineValue: Double, magnitude: Double,
                rollingWindow: AnomalyWindow, baselineWindow: AnomalyWindow) {
        self.cause = cause
        self.metric = metric
        self.rollingValue = rollingValue
        self.baselineValue = baselineValue
        self.magnitude = magnitude
        self.rollingWindow = rollingWindow
        self.baselineWindow = baselineWindow
    }
}

// MARK: - The detector

/// The pure anomaly detector (docs/JOURNEYS.md J9, docs/SCHEMA.md -> ANOMALY).
///
/// The whole design follows the journey's warning - **false alarms erode trust
/// fastest** - so the detector's job is to stay quiet. A detector that fires
/// often is not a better detector; it is the failure mode the journey names.
/// Everything below follows from that:
///
/// - **Seasonally fair by construction.** The comparison is the rolling value
///   (trailing 90 days) against the SAME window one year earlier, drawn from
///   the trailing 12 months (docs/VISION.md). A winter rise is only an anomaly
///   if it exceeds what last winter did - never "this month vs last month",
///   which fires every November for every user in a cold country.
/// - **Conservative thresholds** (the named constants below, each with its
///   reasoning) - a future change is a deliberate act, not a tweak.
/// - **Sustained, not spiked.** A 90-day distance-weighted average cannot be
///   moved by a single bad tank (that is J9's "over 3 months"), and the
///   recent-window guard refuses to alarm when the drift has already started
///   recovering.
/// - **Insufficient data yields nothing.** Below the segment floor, or with no
///   seasonally-aligned baseline to compare against, the answer is nil -
///   silence, not a low-confidence guess. The consumption engine's floor of 3
///   (docs/SCHEMA.md -> HEADLINE) is the floor here too.
/// - **Dismissal suppresses only its own cause.** An `AnomalyDismissal` for
///   the same `AnomalyCause` keeps that anomaly quiet; a different cause still
///   fires. Persisting the dismissal is fine - persisting the verdict is not
///   (hard rule 2): the anomaly re-derives on every recompute.
///
/// `segments` are the consumption engine's own segments
/// (`ConsumptionEngine.recompute` / `segments`) or the EV engine's
/// (`ConsumptionEngine.evSegments`). This type adds no second consumption
/// model - only a windowed aggregate of the values that engine already
/// produced.
public enum AnomalyEngine {

    /// The window the rolling value is measured over - the "3 months" of
    /// docs/JOURNEYS.md J9's "+12% over 3 months", matching the headline's
    /// 90-day window (docs/SCHEMA.md -> HEADLINE).
    public static let rollingWindowDays = 90

    /// The recent-window guard: the drift must still be present in the last
    /// month, not already recovering. One fill cycle long, so a regular logger
    /// satisfies it and a recovering trend stays quiet. This is the
    /// "sustained" half of SCHEMA.md's "fires when sustained".
    public static let recentWindowDays = 30

    /// The lag between the rolling window and its seasonally-aligned baseline.
    /// The same-length window ending 365 days earlier is the same season's
    /// point in the trailing 12 months - "what last winter did", per
    /// docs/VISION.md. A 365-day lag is within a day of a calendar year (a
    /// leap day drifts a 90-day window by ~1%), irrelevant next to a 12%
    /// threshold; it keeps the engine deterministic across calendar
    /// implementations.
    public static let baselineLagDays = 365

    /// Segments a window needs before its value is usable - the same floor the
    /// consumption engine uses (docs/SCHEMA.md -> HEADLINE, floor of 3).
    /// Below it the window's value is a guess, and silence is the correct
    /// output. Unlike the headline, the anomaly does NOT extend its window to
    /// reach the floor: extension would pull a different season into a
    /// seasonally-fair comparison.
    public static let minimumSegmentsPerWindow = 3

    /// Segments the recent-window guard needs. One segment - the recent guard
    /// is a confirmation that the drift is still present, not a statistic of
    /// its own; the primary signal is the 90-day rolling value, which already
    /// needs the full floor.
    public static let minimumRecentSegments = 1

    /// The fire threshold: the rolling value must exceed the seasonally-aligned
    /// baseline by this fraction before the anomaly exists. The upper end of
    /// docs/SCHEMA.md's "+10-12%" and exactly J9's "+12%": below it the
    /// elevation is within normal wobble, and a conservative engine stays
    /// quiet. Lowering this is a product decision about false-alarm tolerance,
    /// not a tuning tweak - the journey says false alarms erode trust fastest.
    public static let minimumRelativeDrift = 0.12

    /// Returns the anomaly, or nil when the detector stays quiet. Silence is
    /// a first-class outcome, tested as one: a new user, a sparse history, a
    /// seasonal rise that last year matched, an already-recovering drift, and
    /// a dismissed cause all return nil here.
    public static func detect(segments: [Segment],
                              asOf: Date,
                              dismissals: Set<AnomalyDismissal> = [],
                              calendar: Calendar = .current) -> ConsumptionAnomaly? {
        let day: TimeInterval = 86_400
        let rollingEnd = asOf
        let rollingStart = rollingEnd.addingTimeInterval(-Double(rollingWindowDays) * day)
        let baselineEnd = rollingEnd.addingTimeInterval(-Double(baselineLagDays) * day)
        let baselineStart = baselineEnd.addingTimeInterval(-Double(rollingWindowDays) * day)

        // Both windows must exist and be usable. A missing seasonally-aligned
        // baseline (history younger than ~12 months) yields nothing - a new
        // user gets no anomaly, ever, until there is a full prior year to
        // compare against.
        guard let rolling = windowValue(segments, from: rollingStart, to: rollingEnd,
                                        minSegments: minimumSegmentsPerWindow),
              let baseline = windowValue(segments, from: baselineStart, to: baselineEnd,
                                         minSegments: minimumSegmentsPerWindow),
              baseline.value > 0 else { return nil }

        let magnitude = (rolling.value - baseline.value) / baseline.value
        guard magnitude >= minimumRelativeDrift else { return nil }

        // The "sustained, still present" half: the recent window must be
        // elevated too, so a rise that has already recovered does not fire
        // while its 90-day average still carries it.
        let recentStart = rollingEnd.addingTimeInterval(-Double(recentWindowDays) * day)
        guard let recent = windowValue(segments, from: recentStart, to: rollingEnd,
                                       minSegments: minimumRecentSegments),
              (recent.value - baseline.value) / baseline.value >= minimumRelativeDrift else { return nil }

        let cause = AnomalyCause(metric: .consumption, evaluatedOn: asOf, calendar: calendar)
        guard !dismissals.contains(where: { $0.cause == cause }) else { return nil }

        return ConsumptionAnomaly(
            cause: cause,
            metric: .consumption,
            rollingValue: rolling.value,
            baselineValue: baseline.value,
            magnitude: magnitude,
            rollingWindow: AnomalyWindow(start: rollingStart, end: rollingEnd,
                                         value: rolling.value, segmentCount: rolling.segmentCount),
            baselineWindow: AnomalyWindow(start: baselineStart, end: baselineEnd,
                                          value: baseline.value, segmentCount: baseline.segmentCount)
        )
    }

    /// Distance-weighted consumption over segments closing inside (start, end]:
    /// Σ litres / Σ km x 100 - exactly the engine's HEADLINE formula
    /// (docs/SCHEMA.md), applied to a caller-chosen window. `nil` when the
    /// window holds fewer than `minSegments` or has no usable distance.
    private static func windowValue(_ segments: [Segment], from start: Date, to end: Date,
                                    minSegments: Int) -> (value: Double, segmentCount: Int)? {
        let inWindow = segments.filter { $0.closes > start && $0.closes <= end }
        guard inWindow.count >= minSegments else { return nil }
        let totalLitres = inWindow.reduce(0) { $0 + $1.litres }
        let totalKm = inWindow.reduce(0) { $0 + $1.km }
        guard totalKm > 0 else { return nil }
        return (totalLitres / totalKm * 100, inWindow.count)
    }
}
