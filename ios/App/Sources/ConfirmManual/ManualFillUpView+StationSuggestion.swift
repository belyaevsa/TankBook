import TankbookCore

// MARK: - PJ.19 station suggestion (docs/JOURNEYS.md -> J4)

// The ranking lives in core (`StationSuggestion`) as a pure function over
// injected inputs; this extension resolves the device context once per Confirm
// sheet and writes the proposal as a default input. Split into its own file so
// ManualFillUpView stays under the lint ceiling.

extension ManualFillUpView {

    /// Resolves the station ranking once per Confirm sheet. It never blocks the
    /// form and its absence is a non-event: no stations (or no ranking) leaves
    /// the row exactly as it is (docs/ERRORS.md -> Confirm). The permission
    /// question is asked at the earliest moment it can be answered with a
    /// station on file - the first Confirm after the second fill-up - and never
    /// at launch.
    func runStationSuggestion(vehicle: Vehicle) {
        guard !stations.isEmpty else { return }
        let reader = ForecourtLocationReader()

        let priorFillCount = existingEntries.reduce(into: 0) { count, entry in
            if entry is FillUp { count += 1 }
        }
        if priorFillCount >= 1, reader.mayPresentPermissionPrompt(), !reader.hasAskedBefore {
            reader.requestPermissionOnce()
        }

        // Pass 1 (synchronous): rung 3 needs no location, so a car with a
        // recorded station is proposed immediately; a seeded location feeds the
        // distance rungs with no wait at all. RV.150: the seeded fix is also
        // the one a save at a location-less station adopts - the screenshot and
        // UI-test harnesses must not need a second GPS read.
        stationLocationFix = reader.immediateFix
        applyStationProposal(makeProposal(reader: reader,
                                          fix: reader.immediateFix,
                                          vehicle: vehicle),
                             vehicle: vehicle)

        // Pass 2: the distance rungs land once the single location read
        // answers. A pass that arrives after the user picked a station is a
        // no-op (hard rule 13). The closure captures a value copy of the view
        // struct: `@State` wraps shared storage, so mutating `selectedStation`
        // through the copy lands in the box the live view reads (the same
        // pattern as the gateway answer's `self.applyGatewayAnswer`).
        Task { @MainActor [reader] in
            let fix = await reader.readOnce()
            stationLocationFix = fix
            applyStationProposal(makeProposal(reader: reader, fix: fix,
                                              vehicle: vehicle),
                                 vehicle: vehicle)
        }
    }

    func makeProposal(reader: ForecourtLocationReader, fix: GeoCoordinate?,
                      vehicle: Vehicle) -> StationSuggestion.Proposal? {
        StationSuggestion.propose(in: StationSuggestion.Context(
            stations: stations,
            locationAuthorised: reader.isAuthorised,
            currentLocation: fix,
            recentStationIDForVehicle: StationSuggestion.recentStationID(for: existingEntries),
            vehicleFuelKinds: vehicle.fuelKinds))
    }

    /// Writes a proposal as default input, never as a fact (hard rule 13): only
    /// while the user has made no station choice of their own, and the fuel
    /// default only while the fuel row is still its untouched opening value - a
    /// scan's own kind and the user's own pick both win over a station's
    /// last-visit default.
    func applyStationProposal(_ proposal: StationSuggestion.Proposal?,
                              vehicle: Vehicle) {
        guard StationSuggestionApplication.shouldApply(
            userChoseStation: stationChosenByUser,
            pendingSuggestionExists: proposal != nil) else { return }
        guard let proposal else { return }
        selectedStation = proposal.station
        // The last-visit fuel default yields to this entry's own evidence: a
        // kind the scan resolved (even when it equals the vehicle default) and
        // a kind the user picked both win over what a previous visit recorded.
        if prefill?.extraction?.fuelKind == nil,
           let kind = proposal.fuelKindDefault,
           form.fuelKind == (vehicle.fuelKinds.first ?? .petrol95) {
            form.fuelKind = kind
        }
    }
}
