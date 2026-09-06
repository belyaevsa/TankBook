import Foundation
import TankbookCore

// RV.86: the multi-car mapping plan (`ImportFlowModel.carPlan`) and the `.cars`
// gate's derived figures. A file the parse groups into several source cars gets
// ONE extra wizard step: the user decides where each car goes (leave out / a
// new car / an existing garage car). Nothing here writes - the decisions only
// re-derive the classification, and the single commit stays in `confirmImport`.

extension ImportFlowModel {
    // MARK: - The mapping plan

    /// Whether the parse exposes more than one distinct source car - the
    /// condition that inserts the `.cars` step. A file with a single distinct
    /// name never sees it (acceptance: today's flow stays byte-for-byte).
    var hasMultipleCars: Bool {
        (parse?.resolvedVehicleGroups.count ?? 0) > 1
    }

    /// The source cars a multi-car parse exposes, in file order of first
    /// appearance.
    var sourceCars: [ImportVehicleGroup] {
        parse?.resolvedVehicleGroups ?? []
    }

    /// Routes the wizard after a parse lands. A multi-car file builds the
    /// mapping plan - every destination starts UNDECIDED, the wizard never
    /// guesses a mapping or funnels into the pre-selected car (hard rule 13) -
    /// and shows the `.cars` step. A single-car file keeps today's flow exactly
    /// (the target car is defaulted, the preview gate follows).
    func routeAfterParse(preferredVehicleID: UUID?) {
        carPlan = []
        if hasMultipleCars {
            targetCar = nil
            carPlan = sourceCars.map { ImportCarRow(group: $0) }
        } else {
            ensureTargetCar(preferredVehicleID: preferredVehicleID)
        }
        rebuildClassification()
    }

    /// Whether the `.cars` gate's Continue may fire: every source car has a
    /// destination (nothing undecided - hard rule 13's "never guess"), every F6
    /// question is answered, and nothing has been committed yet.
    var carsGateIsReady: Bool {
        !carPlan.isEmpty && carPlan.allSatisfy(\.isDecided) && canConfirm && !didConfirm
    }

    /// True while at least one source car still lacks a destination - the
    /// mapping screen's hint state (Continue stays disabled).
    var carsGateHasUndecided: Bool {
        carPlan.contains { !$0.isDecided }
    }

    // MARK: - Decisions

    /// Records the user's destination choice for one source car and reclassifies
    /// every decided lane, so the figures, the review rows and the commit set all
    /// follow in one place.
    func decide(_ destination: ImportCarDestination, forCarAt index: Int) {
        guard carPlan.indices.contains(index) else { return }
        carPlan[index].destination = destination
        rebuildClassification()
    }

    /// "Leave out" - the source car's rows are dropped from the import. A
    /// deliberate decision, never a default.
    func leaveOutCar(at index: Int) {
        decide(.leaveOut, forCarAt: index)
    }

    /// "New car" - the source car becomes a brand-new garage car, named from the
    /// file (the group's own name, editable later in the Garage - hard rule 13).
    /// The vehicle is synthesized ONCE per pick, so every rebuild and the commit
    /// share the same id.
    func importAsNewCar(at index: Int) {
        guard carPlan.indices.contains(index) else { return }
        let name = Self.newVehicleName(for: carPlan[index].group)
        decide(.new(TargetCar.newCar(named: name).vehicleValue), forCarAt: index)
    }

    /// "Import into an existing garage car" - a merge, whose duplicate count the
    /// mapping screen surfaces before anything is written.
    func importIntoExistingVehicle(_ vehicle: Vehicle, at index: Int) {
        decide(.existing(vehicle), forCarAt: index)
    }

    /// The new car's default name: the source file's own vehicle name (trimmed),
    /// falling back to the generic imported-car name when the file named nothing.
    private static func newVehicleName(for group: ImportVehicleGroup) -> String {
        let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.importedCarName : trimmed
    }

    // MARK: - The gate's figures (per source car, never across cars)

    /// The effective candidates belonging to one source car's group (through the
    /// date-format answer, like every other figure - the number the user sees is
    /// the number that lands).
    func carCandidates(_ group: ImportVehicleGroup) -> [ImportCandidate] {
        let wanted = Set(group.sourceRows)
        return effectiveCandidates.filter { wanted.contains($0.sourceRow) }
    }

    /// One source car's own file facts: row count, date range and odometer span.
    /// The span is THAT car's span - the cross-car min..max is the RV.86 lie and
    /// has no place on this screen.
    func carFigures(_ group: ImportVehicleGroup) -> ImportCarFigures {
        let rows = carCandidates(group)
        let dates = rows.map(\.date)
        let odometers = rows.compactMap(\.odometer)
        return ImportCarFigures(count: rows.count,
                                firstDate: dates.min(),
                                lastDate: dates.max(),
                                odometerMin: odometers.min(),
                                odometerMax: odometers.max())
    }

    /// The S2 duplicate count when the source car merges into an EXISTING
    /// destination (hard rule 8's "flagged, not merged"): pairs between the
    /// destination's own existing fills and the lane's incoming kept fills,
    /// through the same engine the single-car preview uses - per car. Zero for a
    /// new car (nothing to collide with) and for a lane left out or undecided.
    func mergeDuplicateCount(for row: ImportCarRow) -> Int {
        guard case .existing(let vehicle) = row.destination else { return 0 }
        let existing = (try? repository.liveFillUps(forVehicle: vehicle.id)) ?? []
        guard !existing.isEmpty else { return 0 }
        let incoming = laneImportFills(vehicleID: vehicle.id)
        return ImportSummary.compute(
            importFills: incoming,
            existingFills: existing,
            tankCapacityL: vehicle.tankCapacityL,
            declaredCurrency: parse?.declaredCurrency).duplicateCount
    }

    /// The fills that will land in one destination vehicle under the current
    /// decisions and review-list edits: its ready fills plus its kept review
    /// fills (a review row's fill is kept unless the user left it out).
    func laneImportFills(vehicleID: UUID) -> [FillUp] {
        let ready = readyFills.filter { $0.vehicleId == vehicleID }
        let kept = reviewRows.filter { row in
            row.fill?.vehicleId == vehicleID && !isSkipped(sourceRow: row.sourceRow)
        }.compactMap(\.fill)
        return ready + kept
    }

    /// The odometer unit a mapping row's figures render in: the chosen
    /// destination's own unit (a merge into a miles car shows miles), else the
    /// screen default while the destination is undecided or left out.
    func distanceUnit(forPlanRow row: ImportCarRow) -> DistanceUnit {
        row.destinationVehicle?.units.distance ?? distanceUnit
    }

    // MARK: - The gate's summary bar

    /// The fills the commit would write (the bar's N), derived exactly as the
    /// single-car preview's confirm count is.
    var plannedFillCount: Int { commitCount }

    /// The distinct garage cars the commit would touch (the bar's M): every
    /// vehicle that receives at least one kept record under the mapping.
    var plannedDestinationCount: Int {
        Set(importRecords.compactMap(\.importVehicleID)).count
    }
}
