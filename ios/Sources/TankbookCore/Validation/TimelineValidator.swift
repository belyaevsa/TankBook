import Foundation

/// Timeline validation (docs/SCHEMA.md, Validation). Pure functions: validation
/// NEVER blocks a save - it returns results, and flagged entries are saveable
/// (they surface an amber badge and the consumption engine excludes their
/// segments). Checked on every write; the `conflict` flags are written onto the
/// entry, not raised at read time.
public enum TimelineValidator {

    /// A single detected timeline violation for an entry.
    public struct Flag: Equatable, Sendable {
        public let kind: ConflictState.ConflictKind
        public let detail: Detail

        public enum Detail: Equatable, Sendable {
            /// CHECK 1: the odometer does not fit between its date-neighbours.
            /// The dates are the neighbours' `date` values, so the ConfirmManual
            /// sheet can quote the conflicting entry ("Aug 17 already recorded
            /// 119 486 km." - docs/ERRORS.md -> Confirm -> F9a).
            case order(previousOdometer: Int?, previousDate: Date?,
                       nextOdometer: Int?, nextDate: Date?)
            /// CHECK 2: implied km/day against a neighbour exceeds the limit.
            case pace(kmPerDay: Double, limitKmPerDay: Double)
        }
    }

    /// An ordered resolution suggestion list. When an attachment carries an
    /// `extractedTimestamp` (receipt/QR), the printed date is ground truth:
    /// "fix odometer" ranks FIRST, and changing the date is marked as requiring
    /// explicit confirmation (docs/SCHEMA.md, PRIORITY).
    public enum ResolutionSuggestion: Equatable, Sendable {
        case fixOdometer(from: Int?, to: Int?)
        case fixDate(from: Date?, to: Date?, requiresExplicitConfirmation: Bool)
    }

    /// The validation result for one entry.
    public struct EntryValidation: Equatable, Sendable {
        public let entryID: UUID
        /// `.flagged` when any check failed (and no covering acceptance exists);
        /// `.none` otherwise. Written to the entry on save - it is ALWAYS
        /// saveable.
        public let conflict: ConflictState
        public let flags: [Flag]
        /// CHECK 3 for FillUp entries; `nil` for other entry types.
        public let crossCheck: CrossCheckState?
        /// Ordered resolution suggestions; empty when nothing is flagged.
        public let suggestions: [ResolutionSuggestion]
        /// The stored acceptance to write onto the entry alongside `conflict`
        /// (RV.104). Non-nil ONLY when it is currently suppressing a real flag -
        /// i.e. the entry was accepted and the accepted facts still hold. Every
        /// other case returns nil so a stale acceptance is cleared when the
        /// entry re-flags or the timeline genuinely heals.
        public let acceptance: FlagAcceptance?
        /// RV.117a: the odometer readings valid for this entry's date and the
        /// dates valid for its odometer (docs/SCHEMA.md -> Validation -> Valid
        /// range). Derived in the SAME pass as the flags - same neighbour walk,
        /// same `limit` - so the two can never disagree. Nil only when the entry
        /// records no odometer: there is then no field whose range could be
        /// shown. Computed whether or not the entry currently flags (RV.104's
        /// accepted entries still get one), never stored, never auto-applied
        /// (hard rules 2 and 13).
        public let validRange: TimelineValidRange?

        /// A flagged entry is never blocked from saving - the flag is advisory.
        public var isSaveable: Bool { true }
    }

    /// The INVARIANT: for the vehicle's entries with an odometer, sorted by
    /// date, odometer strictly increases.
    public static func invariantHolds(entries: [any Entry]) -> Bool {
        let odometers = entries.sorted(by: entryOrder).compactMap(\.odometer)
        return zip(odometers, odometers.dropFirst()).allSatisfy { $0 < $1 }
    }

    /// Validates every entry in the timeline against its date-neighbours.
    ///
    /// - CHECK 1 (order): the entry's odometer must fit between its neighbours.
    /// - CHECK 2 (pace): implied km/day against each neighbour must be ≤
    ///   `vehicle.paceLimitKmPerDay`.
    /// - CHECK 3 (cross-check): `volumeL x unitPrice ≈ amount` for FillUps.
    /// - PRIORITY: entries whose attachment has an `extractedTimestamp` treat
    ///   the date as ground truth when ranking resolution suggestions.
    public static func validate(entries: [any Entry], vehicle: Vehicle,
                                attachments: [Attachment] = []) -> [EntryValidation] {
        let attachmentsByID = Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0) })
        let sorted = entries.sorted(by: entryOrder)
        return sorted.indices.map { index in
            validate(sorted[index], at: index, in: sorted,
                     limit: vehicle.paceLimitKmPerDay, attachmentsByID: attachmentsByID)
        }
    }

    /// CHECK 3: `volumeL x unitPrice ≈ amount` within tolerance
    /// `max(0.02, amount x 0.005)` (docs/SCHEMA.md, Validation -> CHECK 3).
    /// The tolerance constant is owned by `ConfirmConfidenceGate` - the one
    /// named home for the confirm screen's thresholds (P2.3) - so the
    /// validator and the confirm sheet can never disagree about the boundary.
    public static func crossCheck(volumeL: Double, unitPrice: Decimal?,
                                  amount: Decimal?) -> CrossCheckState {
        guard let unitPrice, let amount else { return .notApplicable }
        let computed = Decimal(volumeL) * unitPrice
        let tolerance = ConfirmConfidenceGate.crossCheckTolerance(amount: amount)
        let difference = abs(computed - amount)
        return difference <= tolerance ? .verified : .mismatch(field: .total)
    }

    // MARK: Private

    private static func validate(_ entry: any Entry, at index: Int, in sorted: [any Entry],
                                 limit: Double,
                                 attachmentsByID: [UUID: Attachment]) -> EntryValidation {
        var flags: [Flag] = []
        var validRange: TimelineValidRange?
        let crossCheck = crossCheckIfApplicable(entry)

        if let odo = entry.odometer {
            var previous: (odometer: Int, date: Date)?
            var next: (odometer: Int, date: Date)?
            var back = index - 1
            while back >= 0 {
                if let value = sorted[back].odometer {
                    previous = (value, sorted[back].date)
                    break
                }
                back -= 1
            }
            var forward = index + 1
            while forward < sorted.count {
                if let value = sorted[forward].odometer {
                    next = (value, sorted[forward].date)
                    break
                }
                forward += 1
            }

            validRange = Self.validRange(odometer: odo, date: entry.date, previous: previous,
                                         next: next, limit: limit)

            // CHECK 1 - order: must fit strictly between date-neighbours.
            if let previous, odo <= previous.odometer {
                flags.append(Flag(kind: .order,
                                  detail: .order(previousOdometer: previous.odometer, previousDate: previous.date,
                                                 nextOdometer: next?.odometer, nextDate: next?.date)))
            }
            if let next, odo >= next.odometer {
                flags.append(Flag(kind: .order,
                                  detail: .order(previousOdometer: previous?.odometer, previousDate: previous?.date,
                                                 nextOdometer: next.odometer, nextDate: next.date)))
            }

            // CHECK 2 - pace: implied km/day against each neighbour.
            if let previous {
                let days = dayDiff(previous.date, entry.date)
                if days > 0 {
                    let pace = Double(abs(odo - previous.odometer)) / days
                    if pace > limit {
                        flags.append(Flag(kind: .pace,
                                          detail: .pace(kmPerDay: pace, limitKmPerDay: limit)))
                    }
                }
            }
            if let next {
                let days = dayDiff(entry.date, next.date)
                if days > 0 {
                    let pace = Double(abs(next.odometer - odo)) / days
                    if pace > limit {
                        flags.append(Flag(kind: .pace,
                                          detail: .pace(kmPerDay: pace, limitKmPerDay: limit)))
                    }
                }
            }
        }

        let receiptDateIsGroundTruth = entry.attachments.contains {
            attachmentsByID[$0]?.extractedTimestamp != nil
        }
        // RV.104: the acceptance is the validator's INPUT. A flag the user
        // accepted - matching kind, and the entry's odometer/date unchanged
        // since the acceptance (docs/SCHEMA.md -> Validation -> Acceptance,
        // keying rule) - does not surface as a conflict. The acceptance is kept
        // on the entry only while it is suppressing a real flag; otherwise it is
        // returned nil so a write path clears a stale one (an accepted entry is
        // still flaggable again - hard rule 8).
        let conflictAndAcceptance = Self.suppressed(flags, on: entry)
        let conflict = conflictAndAcceptance.conflict

        return EntryValidation(
            entryID: entry.id,
            conflict: conflict,
            flags: flags,
            crossCheck: crossCheck,
            suggestions: suggestions(flags: flags, receiptDateIsGroundTruth: receiptDateIsGroundTruth),
            acceptance: conflictAndAcceptance.acceptance,
            validRange: validRange
        )
    }

    /// RV.104: resolves the conflict + acceptance pair a write path must stamp.
    ///
    /// - Flags empty: `.none`, no acceptance (nothing to accept - a stale
    ///   acceptance on a timeline that has healed is dropped).
    /// - Flags non-empty, no covering acceptance: `.flagged` with the first
    ///   kind, no acceptance (the accepted facts changed, or this was never
    ///   accepted - it flags exactly as before RV.104).
    /// - Flags non-empty AND a covering acceptance of the displayed kind:
    ///   `.none`, keeping the acceptance (the user's "this is fine" survives
    ///   this re-validation).
    private static func suppressed(_ flags: [Flag], on entry: any Entry)
        -> (conflict: ConflictState, acceptance: FlagAcceptance?) {
        guard let first = flags.first,
              let acceptance = entry.flagAcceptance,
              acceptance.kind == first.kind,
              acceptance.covers(odometer: entry.odometer, date: entry.date) else {
            let conflict = flags.first.map {
                ConflictState.flagged(kind: $0.kind, detectedAt: entry.createdAt)
            } ?? .none
            return (conflict, nil)
        }
        return (.none, acceptance)
    }

    /// PRIORITY: with a receipt timestamp the printed date is ground truth, so
    /// "fix odometer" ranks first and a date change needs explicit confirmation.
    /// Without one, fixing the date is the plain first resort.
    private static func suggestions(flags: [Flag],
                                    receiptDateIsGroundTruth: Bool) -> [ResolutionSuggestion] {
        guard !flags.isEmpty else { return [] }
        let hasOrder = flags.contains { $0.kind == .order }

        if receiptDateIsGroundTruth {
            var result: [ResolutionSuggestion] = [.fixOdometer(from: nil, to: nil)]
            if hasOrder {
                result.append(.fixDate(from: nil, to: nil, requiresExplicitConfirmation: true))
            }
            return result
        }
        var result: [ResolutionSuggestion] = []
        if hasOrder {
            result.append(.fixDate(from: nil, to: nil, requiresExplicitConfirmation: false))
        }
        result.append(.fixOdometer(from: nil, to: nil))
        return result
    }

    // MARK: - Valid range (RV.117a)

    /// The intervals an entry's two fields may take without flagging. Both are
    /// intersections of the SAME two constraints the flags enforce, over the
    /// SAME neighbour pair this pass already walked:
    ///
    /// - odometer (for the entry's date): strictly above the previous reading
    ///   and at most `previous + limit x days(previous -> entry)`; strictly
    ///   below the next reading and at least `next - limit x days(entry ->
    ///   next)`. The upper end is therefore NOT `next - 1` when the pace toward
    ///   the previous is the tighter bound (the Drivvo case, docs/COMPETITORS.md
    ///   - on 13/07 the odometer must be between 490 500 and 490 983, not
    ///   "below 491 206").
    /// - dates (for the entry's odometer): the instants strictly between the
    ///   neighbours on which that reading keeps both neighbours and stays within
    ///   the pace limit. The bounds are pace-derived and inclusive; the exact
    ///   neighbour instants are outside the claimed domain because there a
    ///   same-day tie reorders the timeline or the `days > 0` guard drops a
    ///   pace bound - the fixed-neighbourhood model no longer applies there.
    ///
    /// A missing neighbour leaves that side OPEN (`nil`), never a sentinel. A
    /// neighbourhood whose constraints cross - `lower > upper` - yields `.none`:
    /// no value is valid, and an inverted "between 490 983 and 490 500" would be
    /// nonsense.
    private static func validRange(odometer: Int, date: Date,
                                   previous: (odometer: Int, date: Date)?,
                                   next: (odometer: Int, date: Date)?,
                                   limit: Double) -> TimelineValidRange {
        TimelineValidRange(
            odometer: odometerRange(date: date, previous: previous, next: next, limit: limit),
            dates: dateRange(odometer: odometer, previous: previous, next: next, limit: limit)
        )
    }

    /// The inclusive integer odometer readings valid for a date. Mirrors the
    /// same-day guard: a same-day neighbour contributes no pace bound (the
    /// `days > 0` guard in `validate(_:at:in:)`), so that side of the interval
    /// is bounded by order alone.
    private static func odometerRange(date: Date,
                                      previous: (odometer: Int, date: Date)?,
                                      next: (odometer: Int, date: Date)?,
                                      limit: Double) -> ValidRange<Int> {
        var lower: Int?
        var upper: Int?
        if let previous {
            lower = previous.odometer + 1
            let days = dayDiff(previous.date, date)
            if days > 0 {
                upper = paceUpperBound(from: previous.odometer, days: days, limit: limit)
            }
        }
        if let next {
            let orderUpper = next.odometer - 1
            upper = upper.map { Swift.min($0, orderUpper) } ?? orderUpper
            let days = dayDiff(date, next.date)
            if days > 0 {
                let paceLower = paceLowerBound(toward: next.odometer, days: days, limit: limit)
                lower = lower.map { Swift.max($0, paceLower) } ?? paceLower
            }
        }
        if let lower, let upper, lower > upper { return .none }
        return .bounded(lower: lower, upper: upper)
    }

    /// The inclusive dates on which `odometer` keeps its two neighbours and the
    /// implied pace to each stays within the limit.
    private static func dateRange(odometer: Int,
                                  previous: (odometer: Int, date: Date)?,
                                  next: (odometer: Int, date: Date)?,
                                  limit: Double) -> ValidRange<Date> {
        // An odometer at or below the previous reading (or at or above the next)
        // cannot sit between the two at ANY date - the order constraint fails for
        // every instant the pair remains its neighbours.
        if let previous, odometer <= previous.odometer { return .none }
        if let next, odometer >= next.odometer { return .none }
        guard limit > 0 else {
            return (previous == nil && next == nil) ? .bounded(lower: nil, upper: nil) : .none
        }
        var lower: Date?
        if let previous {
            let daysNeeded = Double(odometer - previous.odometer) / limit
            lower = previous.date.addingTimeInterval(daysNeeded * 86_400)
        }
        var upper: Date?
        if let next {
            let daysNeeded = Double(next.odometer - odometer) / limit
            upper = next.date.addingTimeInterval(-daysNeeded * 86_400)
        }
        if let lower, let upper, lower > upper { return .none }
        return .bounded(lower: lower, upper: upper)
    }

    /// The largest integer odometer whose implied pace from a previous reading
    /// over `days` does not exceed the limit. Verified against the validator's
    /// own expression (`Double(x - p) / days > limit`) so the boundary cannot
    /// drift from the flag by a floating-point rounding.
    private static func paceUpperBound(from previousOdometer: Int, days: Double, limit: Double) -> Int {
        var x = Int((Double(previousOdometer) + limit * days).rounded(.down))
        while Double(x + 1 - previousOdometer) <= limit * days { x += 1 }
        while Double(x - previousOdometer) > limit * days { x -= 1 }
        return x
    }

    /// The smallest integer odometer whose implied pace toward a next reading
    /// over `days` does not exceed the limit.
    private static func paceLowerBound(toward nextOdometer: Int, days: Double, limit: Double) -> Int {
        var x = Int((Double(nextOdometer) - limit * days).rounded(.up))
        while Double(nextOdometer - x) > limit * days { x += 1 }
        return x
    }

    private static func crossCheckIfApplicable(_ entry: any Entry) -> CrossCheckState? {
        guard let fill = entry as? FillUp else { return nil }
        return crossCheck(volumeL: fill.volumeL, unitPrice: fill.unitPrice,
                          amount: fill.money?.amount)
    }

    private static func dayDiff(_ a: Date, _ b: Date) -> Double {
        abs(a.timeIntervalSince(b)) / 86400
    }

    private static func entryOrder(_ a: any Entry, _ b: any Entry) -> Bool {
        // The one chronological order the validator, the engines and the log
        // share (docs/SCHEMA.md, Entry -> ordering rule). Two same-day fills
        // are ordered by odometer, so a pair the import wrote in arbitrary id
        // order never looks like a falling odometer (RV.87).
        EntryOrder.ascending(a, b)
    }
}
