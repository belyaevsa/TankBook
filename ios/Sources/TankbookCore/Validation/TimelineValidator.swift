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
        /// `.flagged` when any check failed; `.none` otherwise. Written to the
        /// entry on save - it is ALWAYS saveable.
        public let conflict: ConflictState
        public let flags: [Flag]
        /// CHECK 3 for FillUp entries; `nil` for other entry types.
        public let crossCheck: CrossCheckState?
        /// Ordered resolution suggestions; empty when nothing is flagged.
        public let suggestions: [ResolutionSuggestion]

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
        let conflict: ConflictState = flags.first.map {
            .flagged(kind: $0.kind, detectedAt: entry.createdAt)
        } ?? .none

        return EntryValidation(
            entryID: entry.id,
            conflict: conflict,
            flags: flags,
            crossCheck: crossCheck,
            suggestions: suggestions(flags: flags, receiptDateIsGroundTruth: receiptDateIsGroundTruth)
        )
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

    private static func crossCheckIfApplicable(_ entry: any Entry) -> CrossCheckState? {
        guard let fill = entry as? FillUp else { return nil }
        return crossCheck(volumeL: fill.volumeL, unitPrice: fill.unitPrice,
                          amount: fill.money?.amount)
    }

    private static func dayDiff(_ a: Date, _ b: Date) -> Double {
        abs(a.timeIntervalSince(b)) / 86400
    }

    private static func entryOrder(_ a: any Entry, _ b: any Entry) -> Bool {
        if a.date != b.date { return a.date < b.date }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
}
