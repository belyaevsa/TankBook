import Foundation

/// RV.150: the save-side stamp that makes a `Station` rankable
/// (docs/SCHEMA.md -> Station, docs/JOURNEYS.md -> J4). PJ.19's ranking reads
/// `Station.location`, `Station.lastUsedAt` and `Station.defaults`, and before
/// this row only an import or a test seed populated them - a user who typed
/// every fill-up by hand built a station list the ranking could not order. A
/// fill-up saved at a chosen station now writes all three, and only then:
///
/// - `lastUsedAt` becomes the save's moment - a station confirmed by a fill is
///   "last used" now.
/// - `defaults` records what was actually bought there: the fill's fuel kind,
///   and its grade when the fill names one (a fill with no grade leaves a
///   stored grade alone - blanks-fill-only, the rate-backfill principle).
/// - `location` is adopted from the forecourt fix the Confirm sheet already
///   read (PJ.19), **only when the station has none**. Fill-blanks-only, like
///   the rate backfill (docs/SYNC.md -> S8): a coordinate the station already
///   has is the user's own and is never overwritten, and no fix (no permission,
///   no GPS) writes nothing - a non-event (hard rule 1).
///
/// Everything else about the station - name, brand, favourite, the envelope
/// timestamps - is untouched. A coordinate is a domain value and is never
/// logged (hard rule 12); this type performs no logging at all.
public enum StationStamp {

    /// The stamped station for a fill-up saved at `station`. Pure: no
    /// repository, no logging, no side effects - the caller decides whether
    /// the result differs from the stored row before writing (the RV.136 guard:
    /// a save that changes nothing writes nothing).
    public static func applied(to station: Station,
                               fuelKind: FuelKind?,
                               fuelGrade: String?,
                               locationFix: GeoCoordinate?,
                               at now: Date) -> Station {
        var stamped = station
        stamped.lastUsedAt = now
        stamped.defaults = Station.Defaults(
            fuelKind: fuelKind ?? station.defaults.fuelKind,
            fuelGrade: fuelGrade ?? station.defaults.fuelGrade)
        if station.location == nil, let locationFix {
            stamped.location = locationFix
        }
        return stamped
    }
}
