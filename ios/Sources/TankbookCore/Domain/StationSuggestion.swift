import Foundation

/// PJ.19: the Confirm sheet's station pre-selection, implemented exactly as
/// docs/JOURNEYS.md -> J4 ("Station suggestion - the logic") writes it. The
/// ladder, first match wins:
///
/// 1. a **favourite** station within 300 m of the device;
/// 2. the **last-used** station within 300 m;
/// 3. the **most recently used** station for this car, regardless of distance -
///    this rung needs no location permission and is what most users get most of
///    the time;
/// 4. nothing - the row stays as it is.
///
/// Rungs 1-2 need location; rungs 3-4 never do. This type is PURE over injected
/// inputs - no CoreLocation, no simulator, no permission - so the ladder is
/// testable exactly as written. The app layer resolves the device's fix and
/// authorisation (docs/TESTING.md, L1) and hands them in.
public enum StationSuggestion {

    /// The distance gate for the location rungs (docs/JOURNEYS.md -> J4).
    public static let maxDistanceMeters: Double = 300

    /// Everything the ladder reads, resolved by the caller. `locationAuthorised`
    /// and `currentLocation` together decide whether the distance rungs may run;
    /// a denied permission simply means the ranking runs without them.
    public struct Context: Equatable {
        public let stations: [Station]
        public let locationAuthorised: Bool
        public let currentLocation: GeoCoordinate?
        /// Rung 3's input: the station this car's most recent fill-up used,
        /// when any. Derived from the fill history, never from a station's
        /// `lastUsedAt` - that field is not maintained per vehicle, and rung 3
        /// is explicitly "for this car".
        public let recentStationIDForVehicle: UUID?
        /// The car's declared fuel kinds: a station's last-visit fuel kind is a
        /// default input only when the car can take it (hard rule 13), gated by
        /// the same offer set the fuel chips render.
        public let vehicleFuelKinds: [FuelKind]

        public init(stations: [Station],
                    locationAuthorised: Bool,
                    currentLocation: GeoCoordinate?,
                    recentStationIDForVehicle: UUID?,
                    vehicleFuelKinds: [FuelKind]) {
            self.stations = stations
            self.locationAuthorised = locationAuthorised
            self.currentLocation = currentLocation
            self.recentStationIDForVehicle = recentStationIDForVehicle
            self.vehicleFuelKinds = vehicleFuelKinds
        }
    }

    /// The winning proposal: the ranked station plus its last-visit fuel kind
    /// when the car offers it. `nil` from `propose` means nothing qualifies (no
    /// stations; no permission AND no station history for the car; nothing
    /// within range and no recent station) - a missing proposal is a non-event,
    /// never an error (docs/ERRORS.md -> Confirm), and the sheet shows exactly
    /// what it shows without the feature.
    public struct Proposal: Equatable {
        public let station: Station
        /// The station's recorded last-visit fuel kind
        /// (`Station.defaults.fuelKind`) when the vehicle's offer set contains
        /// it; nil when the station records none or the car does not take it. A
        /// kind the car does not offer is never applied; the station itself
        /// still proposes.
        public let fuelKindDefault: FuelKind?

        init(station: Station, vehicleFuelKinds: [FuelKind]) {
            self.station = station
            let offered = FuelKind.offeredKinds(for: Set(vehicleFuelKinds))
            self.fuelKindDefault = station.defaults.fuelKind.flatMap {
                offered.contains($0) ? $0 : nil
            }
        }
    }

    /// The proposal for the current sheet, or nil when no rung qualifies.
    public static func propose(in context: Context) -> Proposal? {
        guard let station = winner(in: context) else { return nil }
        return Proposal(station: station, vehicleFuelKinds: context.vehicleFuelKinds)
    }

    /// Rung 3's input, derived where the fill history lives: the station of the
    /// vehicle's most recent fill-up that names one, newest first per
    /// `EntryOrder`. A fill that records no station is skipped; a non-fill entry
    /// cannot name a station.
    public static func recentStationID(for entries: [any Entry]) -> UUID? {
        let filled = entries.compactMap { $0 as? FillUp }.filter { $0.stationId != nil }
        guard let latest = filled.max(by: { EntryOrder.ascending($0, $1) }) else {
            return nil
        }
        return latest.stationId
    }

    /// Great-circle distance between two coordinates, in metres. The domain has
    /// no CoreLocation, so the app layer converts its `CLLocation` to a
    /// `GeoCoordinate` and the ranking measures its own distance (haversine over
    /// a spherical Earth; the 300 m gate is far below the error this
    /// approximation admits).
    public static func distanceMeters(from origin: GeoCoordinate,
                                      to destination: GeoCoordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let dLat = (destination.latitude - origin.latitude) * .pi / 180
        let dLon = (destination.longitude - origin.longitude) * .pi / 180
        let halfChordSquared = sin(dLat / 2) * sin(dLat / 2)
            + cos(origin.latitude * .pi / 180)
            * cos(destination.latitude * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        let centralAngle = 2 * atan2(sqrt(halfChordSquared),
                                     sqrt(1 - halfChordSquared))
        return earthRadiusMeters * centralAngle
    }

    // MARK: - The ladder

    private static func winner(in context: Context) -> Station? {
        guard !context.stations.isEmpty else { return nil }

        // Rungs 1-2 need the permission AND a fix; rung 3 never does.
        if context.locationAuthorised, let fix = context.currentLocation {
            let withinRange = context.stations.compactMap { station -> (Station, Double)? in
                guard let location = station.location else { return nil }
                let distance = distanceMeters(from: fix, to: location)
                guard distance <= maxDistanceMeters else { return nil }
                return (station, distance)
            }

            // Rung 1: the nearest favourite within range.
            if let nearestFavourite = withinRange
                .filter({ $0.0.favorite })
                .min(by: { $0.1 < $1.1 })?.0 {
                return nearestFavourite
            }

            // Rung 2: the most recently used station within range. A favourite
            // within range already won rung 1, so the pick here is among the
            // stations actually used; an in-range station nobody has visited is
            // not "last-used" and falls through to rung 3 like an empty range.
            if let mostRecent = withinRange
                .filter({ $0.0.lastUsedAt != nil })
                .max(by: { ($0.0.lastUsedAt ?? .distantPast) < ($1.0.lastUsedAt ?? .distantPast) })?.0 {
                return mostRecent
            }
        }

        // Rung 3: this car's most recently used station, regardless of distance.
        // This is what a user with no permission (or no fix) gets: the ranking
        // runs without its distance rungs, never as an error (docs/ERRORS.md).
        if let id = context.recentStationIDForVehicle,
           let recent = context.stations.first(where: { $0.id == id }) {
            return recent
        }
        return nil
    }
}

/// Hard rule 13, in decision form: a later ranking pass may replace a station
/// the APP suggested, but never one the USER chose. The sheet tracks which of
/// the two its current selection is - a menu pick flips `userChoseStation`, a
/// suggestion application does not - and consults this before every pass.
public enum StationSuggestionApplication {

    /// Whether a pending proposal may be written to the entry's station.
    public static func shouldApply(userChoseStation: Bool,
                                   pendingSuggestionExists: Bool) -> Bool {
        !userChoseStation && pendingSuggestionExists
    }
}
