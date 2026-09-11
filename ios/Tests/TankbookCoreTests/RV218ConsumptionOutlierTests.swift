import Testing
import Foundation
@testable import TankbookCore

// RV.218 - the F2 residue's "consumption outlier check on save". A fill whose
// closing segment implies a figure outside the vehicle powertrain's plausible
// band raises the CHECK 5 warn; the figure is the engine's own `Segment.per100`
// (hard rule 2 - one derivation), and the fill always saves (docs/SCHEMA.md,
// "Bands are wide and soft on purpose").

private let day: TimeInterval = 86_400
private let epoch = Date(timeIntervalSince1970: 1_752_000_000)

private func outlierVehicle(powertrain: Powertrain = .ice) -> Vehicle {
    Vehicle(
        id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
        name: "Test car", make: nil, model: nil, year: nil, plate: nil,
        powertrain: powertrain, fuelKinds: [.petrol95], tankCapacityL: 71,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l,
                             consumption: .lPer100, energy: .kWhPer100),
        photo: nil, paceLimitKmPerDay: 1500, initialOdometer: 100_000)
}

private func outlierFill(vehicleId: UUID, date: Date, odometer: Int, volumeL: Double,
                         id: UUID = UUID.v7()) -> FillUp {
    FillUp(
        id: id, createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: odometer,
        money: nil, note: nil, attachments: [], provenance: .manual,
        conflict: .none, purchaseGroupId: nil, volumeL: volumeL, unitPrice: nil,
        fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
        stationId: nil, crossCheck: .notApplicable, extraction: nil)
}

private func consumptionFlag(_ validation: TimelineValidator.EntryValidation?)
    -> TimelineValidator.Flag? {
    validation?.flags.first { $0.kind == .consumption }
}

// MARK: - L1: the flag fires, and only when it should

@Test func absurdConsumptionAgainstThePreviousFillIsFlagged() {
    let car = outlierVehicle()
    let prior = outlierFill(vehicleId: car.id, date: epoch, odometer: 100_000, volumeL: 42.3)
    // 8 L over the 500 km since the previous full fill = 1.6 L/100km, below the
    // ICE floor of 3 - the F2 residue's misread litre.
    let candidate = outlierFill(vehicleId: car.id, date: epoch + 5 * day,
                                odometer: 100_500, volumeL: 8)

    let validation = TimelineValidator.validate(entries: [prior, candidate], vehicle: car)
        .first { $0.entryID == candidate.id }

    guard case .consumption(let per100, let range) = consumptionFlag(validation)?.detail else {
        Issue.record("expected a consumption flag, got \(String(describing: validation?.flags))")
        return
    }
    // Oracle: the engine's own segment for the pair (not a second formula).
    let segment = ConsumptionEngine.segments(for: [prior, candidate],
                                             tankCapacityL: car.tankCapacityL)
        .first { $0.closingFillID == candidate.id }
    #expect(per100 == segment?.per100)
    #expect(!range.contains(per100))
    #expect(validation?.conflict == .flagged(kind: .consumption, detectedAt: candidate.createdAt))
    #expect(validation?.isSaveable == true)
}

@Test func plausibleConsumptionProducesNoFlag() {
    let car = outlierVehicle()
    let prior = outlierFill(vehicleId: car.id, date: epoch, odometer: 100_000, volumeL: 42.3)
    // 40 L over 500 km = 8.0 L/100km, inside the ICE band 3...40.
    let candidate = outlierFill(vehicleId: car.id, date: epoch + 5 * day,
                                odometer: 100_500, volumeL: 40)

    let validation = TimelineValidator.validate(entries: [prior, candidate], vehicle: car)
        .first { $0.entryID == candidate.id }

    #expect(consumptionFlag(validation) == nil,
            "a plausible figure must stay quiet, got \(String(describing: validation?.flags))")
    #expect(validation?.conflict == ConflictState.none)
}

@Test func aFirstFillWithNoPredecessorProducesNoFlag() {
    let car = outlierVehicle()
    // One full fill opens a segment but closes none: there is no implied
    // consumption to judge, so the check stays silent (never a guess).
    let only = outlierFill(vehicleId: car.id, date: epoch, odometer: 100_000, volumeL: 8)

    let validation = TimelineValidator.validate(entries: [only], vehicle: car)
        .first { $0.entryID == only.id }

    #expect(consumptionFlag(validation) == nil)
    #expect(validation?.conflict == ConflictState.none)
}

@Test func aPriceOutlierIsNotAConsumptionOutlier() {
    // The corpus's AI-100 at 450 RUB/L is a PRICE outlier: the volume and the
    // distance are ordinary, so the consumption figure is ordinary and the
    // check must not confuse the two. The money is never read here.
    let car = outlierVehicle()
    let prior = outlierFill(vehicleId: car.id, date: epoch, odometer: 100_000, volumeL: 42.3)
    let candidate = outlierFill(vehicleId: car.id, date: epoch + 5 * day,
                                odometer: 100_500, volumeL: 40)

    let validation = TimelineValidator.validate(entries: [prior, candidate], vehicle: car)
        .first { $0.entryID == candidate.id }

    #expect(consumptionFlag(validation) == nil)
}

// MARK: - L1: one engine - the flag quotes Trends' own figure

@Test func theFlaggedFigureIsTheEnginesOwnSegmentFigure() {
    let car = outlierVehicle()
    let prior = outlierFill(vehicleId: car.id, date: epoch, odometer: 100_000, volumeL: 42.3)
    let candidate = outlierFill(vehicleId: car.id, date: epoch + 5 * day,
                                odometer: 100_500, volumeL: 8)

    let validation = TimelineValidator.validate(entries: [prior, candidate], vehicle: car)
        .first { $0.entryID == candidate.id }
    guard case .consumption(let per100, _) = consumptionFlag(validation)?.detail else {
        Issue.record("expected a consumption flag")
        return
    }

    // The same call Home/Trends derive from, over the same fills.
    let trendsFigure = ConsumptionEngine.recompute(fills: [prior, candidate],
                                                   tankCapacityL: car.tankCapacityL)
        .first { $0.closingFillID == candidate.id }?.per100
    #expect(per100 == trendsFigure)
    // Independent arithmetic, so the equality above cannot be a shared mistake.
    #expect(abs(per100 - 1.6) < 1e-9, "8 L over 500 km is 1.6 L/100km, got \(per100)")
}

// MARK: - L1: a flagged fill still saves

@Test func aFlaggedOutlierStillSavesWithTheFlag() throws {
    let repo = try makeSyncRepository()
    let car = outlierVehicle()
    try repo.upsertVehicle(car, syncState: .synced(scn: 1))
    let prior = outlierFill(vehicleId: car.id, date: epoch, odometer: 100_000, volumeL: 42.3)
    var candidate = outlierFill(vehicleId: car.id, date: epoch + 5 * day,
                                odometer: 100_500, volumeL: 8)
    try repo.upsertFillUp(prior, syncState: .synced(scn: 2))

    let validation = TimelineValidator.validate(entries: [prior, candidate], vehicle: car)
        .first { $0.entryID == candidate.id }
    // The write path stamps the validator's verdict, exactly as
    // `ManualFillUpView.buildFillUp` does - it is never a refusal.
    candidate.conflict = validation?.conflict ?? .none
    try repo.upsertFillUp(candidate, syncState: .dirty)

    let stored = try repo.liveFillUps(forVehicle: car.id).first { $0.id == candidate.id }
    #expect(stored != nil, "the flagged fill must be persisted, not refused")
    #expect(stored?.conflict == .flagged(kind: .consumption, detectedAt: candidate.createdAt))
}

/// The self-suppression trap: a `.consumption` conflict excludes the segment
/// from `ConsumptionEngine`, so if the check read the engine without clearing
/// its own flag the segment would vanish and the flag would clear on the next
/// re-validation - then re-fire on the one after. `revalidateTimeline` is that
/// next pass (sync apply, undo-acceptance, vehicle edit), so the flag must
/// survive it.
@Test func theConsumptionFlagSurvivesRevalidation() throws {
    let repo = try makeSyncRepository()
    let car = outlierVehicle()
    try repo.upsertVehicle(car, syncState: .synced(scn: 1))
    let prior = outlierFill(vehicleId: car.id, date: epoch, odometer: 100_000, volumeL: 42.3)
    var candidate = outlierFill(vehicleId: car.id, date: epoch + 5 * day,
                                odometer: 100_500, volumeL: 8)
    try repo.upsertFillUp(prior, syncState: .synced(scn: 2))
    candidate.conflict = .flagged(kind: .consumption, detectedAt: candidate.createdAt)
    try repo.upsertFillUp(candidate, syncState: .synced(scn: 3))

    _ = try repo.revalidateTimeline(vehicleIds: [car.id])

    let stored = try repo.liveFillUps(forVehicle: car.id).first { $0.id == candidate.id }
    #expect(stored?.conflict == .flagged(kind: .consumption, detectedAt: candidate.createdAt),
            "the flag must survive a re-validation, not suppress its own evidence")
}

// MARK: - L1: the band is the vehicle's powertrain, not one number for all cars

@Test func theBandComesFromTheVehiclePowertrain() {
    // 2.0 L/100km is impossible for a combustion-only car and ordinary for a
    // plug-in hybrid, so the same fills flag on one and stay quiet on the other.
    let ice = outlierVehicle(powertrain: .ice)
    let phev = outlierVehicle(powertrain: .phev)

    func validation(for car: Vehicle) -> TimelineValidator.EntryValidation? {
        let prior = outlierFill(vehicleId: car.id, date: epoch, odometer: 100_000, volumeL: 42.3)
        let candidate = outlierFill(vehicleId: car.id, date: epoch + 5 * day,
                                    odometer: 100_500, volumeL: 10)
        return TimelineValidator.validate(entries: [prior, candidate], vehicle: car)
            .first { $0.entryID == candidate.id }
    }

    #expect(consumptionFlag(validation(for: ice)) != nil, "2.0 L/100km is below the ICE floor")
    #expect(consumptionFlag(validation(for: phev)) == nil, "2.0 L/100km is ordinary for a PHEV")
}
