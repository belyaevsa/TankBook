import Foundation
import TankbookCore

/// RV.117b: the timeline neighbourhood behind an F9a conflict, as a derived
/// view model. Consumed by `TimelineNeighbourhoodCard`; produced ONLY by
/// `ManualFillUpFormState.timelineNeighbourhood`, which reads the intervals
/// from the validator's own `EntryValidation.validRange` - the view never
/// recomputes a bound (docs/SCHEMA.md -> Validation -> Valid range).
///
/// Everything here is derived, never stored (hard rule 2): the chart points
/// are the entry's odometer-bearing neighbours re-walked in the SAME order the
/// validator uses (`EntryOrder.ascending`), so the drawn neighbourhood and the
/// sentence the card prints can never disagree about which entry is which.
struct TimelineNeighbourhood: Equatable {
    /// One plotted point: the offending entry or an odometer-bearing neighbour.
    struct Point: Equatable, Identifiable {
        let id: UUID
        let date: Date
        let odometer: Int
        /// The flagged entry itself. Drawn amber and off the trend - and marked
        /// by more than colour (a distinct glyph and an accessibility label).
        let isOffending: Bool
    }

    /// An odometer-bearing neighbour's facts, as the bracket rows and the chart
    /// need them.
    struct Neighbour: Equatable {
        let date: Date
        let odometer: Int
    }

    /// The entry being questioned, as the form holds it (its date, its reading).
    let entryDate: Date
    let entryOdometer: Int
    /// The validator's intervals for the entry's date and odometer. Read from
    /// the validation, never computed here (the row's named trap).
    let validRange: TimelineValidRange
    /// The odometer-bearing entries around the entry, chronological, the
    /// offending point included at its own position.
    let points: [Point]
    /// The immediate previous neighbour (the bracket row's "previous entry"),
    /// nil when the entry is the oldest odometer-bearing row.
    let previous: Neighbour?
    /// The immediate next neighbour, nil when the entry is the newest.
    let next: Neighbour?
    /// The point immediately before the offending one, when one exists.
    var previousPoint: Point? {
        guard let index = offendingIndex, index > 0 else { return nil }
        return points[index - 1]
    }

    /// The offending point's position in `points`.
    var offendingIndex: Int? {
        points.firstIndex(where: \.isOffending)
    }
}

extension ManualFillUpFormState {
    /// Runs the form's candidate through the timeline validator and, when it
    /// flags and carries a `validRange`, returns the derived neighbourhood the
    /// F9a panel draws. Both doors - Edit entry opened on a stored flag and
    /// the live conflict as the user types - land here, so the panel tracks the
    /// candidate exactly as the odometer card's warning does.
    ///
    /// `nil` means "no neighbourhood to show": the entry records no odometer,
    /// the candidate no longer flags, or the validator handed back no range. A
    /// `nil` return renders NO panel and no empty box.
    func timelineNeighbourhood(vehicle: Vehicle,
                               existingEntries: [any Entry]) -> TimelineNeighbourhood? {
        guard let odo = odometerValue else { return nil }
        let candidate = candidate(vehicle: vehicle)
        let timeline = existingEntries + [candidate]

        // The intervals are the validator's own output - the SAME pass, the SAME
        // neighbour walk and the SAME pace limit that decided the flag, so the
        // sentence and the amber warning can never disagree.
        let validations = TimelineValidator.validate(entries: timeline, vehicle: vehicle)
        guard let validation = validations.first(where: { $0.entryID == candidate.id }),
              // The panel is the order/pace timeline's picture and interval: a
              // CHECK 5 consumption hint leaves the odometer and date internally
              // consistent, so it has no off-trend point to chart and no range
              // to state (its own warn renders on the odometer card).
              validation.flags.contains(where: { $0.kind != .consumption }),
              let validRange = validation.validRange else {
            return nil
        }

        // Plot points: re-walk the timeline in the validator's own order and
        // take up to two odometer-bearing neighbours each side - the Drivvo
        // shape (two before, the offending point, two after) when they exist.
        let sorted = timeline.sorted(by: EntryOrder.ascending)
        guard let index = sorted.firstIndex(where: { $0.id == candidate.id }) else { return nil }

        var behind: [TimelineNeighbourhood.Neighbour] = []
        var back = index - 1
        while back >= 0, behind.count < 2 {
            if let reading = sorted[back].odometer {
                behind.append(TimelineNeighbourhood.Neighbour(date: sorted[back].date, odometer: reading))
            }
            back -= 1
        }
        var ahead: [TimelineNeighbourhood.Neighbour] = []
        var forward = index + 1
        while forward < sorted.count, ahead.count < 2 {
            if let reading = sorted[forward].odometer {
                ahead.append(TimelineNeighbourhood.Neighbour(date: sorted[forward].date, odometer: reading))
            }
            forward += 1
        }

        var points = behind.reversed().map {
            TimelineNeighbourhood.Point(id: UUID(), date: $0.date,
                                        odometer: $0.odometer, isOffending: false)
        }
        points.append(TimelineNeighbourhood.Point(id: UUID(), date: candidate.date,
                                                  odometer: odo, isOffending: true))
        points.append(contentsOf: ahead.map {
            TimelineNeighbourhood.Point(id: UUID(), date: $0.date,
                                        odometer: $0.odometer, isOffending: false)
        })

        return TimelineNeighbourhood(
            entryDate: candidate.date,
            entryOdometer: odo,
            validRange: validRange,
            points: points,
            previous: behind.first,
            next: ahead.first)
    }
}

// MARK: - The bidirectional statement (RV.117b item 3)

/// The panel's two sentences, each built from ONE side of the validator's
/// range. Copy is a full localised phrase per case - never a unit label spliced
/// onto a shared stem (hard rule 10) - and every number/date in a slot is
/// already formatted before it reaches the phrase.
///
/// Cases:
/// - `.bounded` with both ends -> the "between" sentence.
/// - one `nil` end -> "no earlier/no later/at least/at most", never a sentinel.
/// - `.none` on the date side -> the row's whole point: the odometer is the
///   field to question (docs/SCHEMA.md -> Validation -> Valid range).
/// - `.none` on both sides -> the neighbourhood itself is inconsistent (a
///   multi-year import can produce it); the card says so instead of going blank.
enum TimelineNeighbourhoodSentences {
    /// "On <date>, the odometer must be between X and Y km" (and its open and
    /// `.none` forms) - the readings valid for the entry's DATE. `nil` means the
    /// side constrains nothing (both bounds open), so the card prints nothing
    /// for it.
    static func odometer(_ range: ValidRange<Int>, dateText: String,
                         unit: DistanceUnit) -> String? {
        switch range {
        case .none:
            return String(format: L10n.localize("On %1$@, no odometer reading fits the entries around it."),
                          dateText)
        case .bounded(let lower, let upper):
            let lowerText = lower.map(OdometerFormat.grouped)
            let upperText = upper.map(OdometerFormat.grouped)
            switch (lowerText, upperText) {
            case let (lower?, upper?):
                return between(key: unit == .km
                    ? "On %1$@, the odometer must be between %2$@ and %3$@ km."
                    : "On %1$@, the odometer must be between %2$@ and %3$@ mi.",
                               dateText: dateText, lower: lower, upper: upper)
            case (nil, let upper?):
                return String(format: L10n.localize(unit == .km
                    ? "On %1$@, the odometer must be at most %2$@ km."
                    : "On %1$@, the odometer must be at most %2$@ mi."),
                              dateText, upper)
            case (let lower?, nil):
                return String(format: L10n.localize(unit == .km
                    ? "On %1$@, the odometer must be at least %2$@ km."
                    : "On %1$@, the odometer must be at least %2$@ mi."),
                              dateText, lower)
            case (nil, nil):
                return nil
            }
        }
    }

    /// "If the odometer is X km, the date must be between A and B" (and its
    /// open and `.none` forms) - the dates valid for the entry's ODOMETER.
    static func dates(_ range: ValidRange<Date>, odometerText: String,
                      unit: DistanceUnit) -> String? {
        switch range {
        case .none:
            return String(format: L10n.localize(unit == .km
                ? "If the odometer is %1$@ km, no date between the neighbouring entries works – check the odometer."
                : "If the odometer is %1$@ mi, no date between the neighbouring entries works – check the odometer."),
                          odometerText)
        case .bounded(let lower, let upper):
            let lowerText = lower.map { EntryDateText.dayMonth($0) }
            let upperText = upper.map { EntryDateText.dayMonth($0) }
            switch (lowerText, upperText) {
            case let (lower?, upper?):
                return String(format: L10n.localize(unit == .km
                    ? "If the odometer is %1$@ km, the date must be between %2$@ and %3$@."
                    : "If the odometer is %1$@ mi, the date must be between %2$@ and %3$@."),
                              odometerText, lower, upper)
            case (nil, let upper?):
                return String(format: L10n.localize(unit == .km
                    ? "If the odometer is %1$@ km, the date must be no later than %2$@."
                    : "If the odometer is %1$@ mi, the date must be no later than %2$@."),
                              odometerText, upper)
            case (let lower?, nil):
                return String(format: L10n.localize(unit == .km
                    ? "If the odometer is %1$@ km, the date must be no earlier than %2$@."
                    : "If the odometer is %1$@ mi, the date must be no earlier than %2$@."),
                              odometerText, lower)
            case (nil, nil):
                return nil
            }
        }
    }

    private static func between(key: String, dateText: String,
                                lower: String, upper: String) -> String {
        String(format: L10n.localize(key), dateText, lower, upper)
    }
}
