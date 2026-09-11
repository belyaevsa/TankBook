import Foundation
import TankbookCore

/// RV.230: the F9a conflict a non-fill EDIT derives from the form, and the
/// timeline neighbourhood behind it. A service, an expense and a charge all
/// reach F9a through the same write (`writeNonFill`), so all three derive the
/// warn through the same builder and the same fix rule (`F9aFixPresentation`) -
/// the edit screen must show the flag the save stamps, never carry it silently
/// (hard rules 7 and 8).
extension EditEntryNonFillForm {

    /// The warn the odometer card renders for this edit, derived exactly as
    /// `writeNonFill` derives the stored flag: the form's own date and odometer
    /// run through `TimelineValidator` against the car's other entries. Nil when
    /// the entry records no odometer or nothing flags.
    func odometerConflict(for entry: any Entry, vehicle: Vehicle,
                          existingEntries: [any Entry],
                          distanceUnit: DistanceUnit) -> OdometerConflict? {
        OdometerConflict.from(candidate: candidate(for: entry),
                              existingEntries: existingEntries, vehicle: vehicle,
                              kind: Self.presentationKind(of: entry),
                              distanceUnit: distanceUnit)
    }

    /// The neighbourhood panel behind the same conflict. The candidate's own
    /// kind decides the order/pace rules, so a charge is validated as a
    /// travel-measuring entry and a service or expense as an annotation.
    func timelineNeighbourhood(for entry: any Entry, vehicle: Vehicle,
                               existingEntries: [any Entry]) -> TimelineNeighbourhood? {
        TimelineNeighbourhood.derive(candidate: candidate(for: entry),
                                     vehicle: vehicle, existingEntries: existingEntries)
    }

    /// The entry as the form would write it, for validation only: the form's
    /// date and odometer over the stored entry's own concrete kind. The write
    /// path validates `otherEntries + [updated]`; this is that `updated` minus
    /// the fields no timeline check reads.
    func candidate(for entry: any Entry) -> any Entry {
        var copy = entry
        copy.date = date
        copy.odometer = odometerValue
        return copy
    }

    /// The `F9aFixPresentation` kind for an entry. A charge is not a service, so
    /// it gets its own case rather than falling through to `.service`.
    static func presentationKind(of entry: any Entry) -> F9aFixPresentation.EntryKind {
        switch entry {
        case is ChargeSession: return .charge
        case is Expense: return .expense
        default: return .service
        }
    }
}
