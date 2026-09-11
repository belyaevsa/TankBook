import Testing
import Foundation
@testable import TankbookCore

// RV.104: the user can accept a flagged entry, and the acceptance is a STORED,
// SYNCED fact the validator takes as INPUT - never a UI filter (a UI-only fix
// is undone by the next sync re-validation) and never a stored verdict for the
// user to overwrite (hard rule 2). These are the L1 assertions the row turns on
// (docs/TASKS.md RV.104), plus the L2 sync round-trip.
//
// Every fixture is the REAL case the row is about: an entry flagged because
// years of history carry a gap nobody remembers (a sold-and-rebought car, an
// odometer swap) - never a freshly created entry, which the "vacuous traps"
// section names as the fixture too clean to test the rule.

private let day: TimeInterval = 86_400
private let epoch = Date(timeIntervalSince1970: 1_752_000_000)

private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

private func vehicle(paceLimit: Double = 1500) -> Vehicle {
    Vehicle(
        id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
        name: "Test car", make: nil, model: nil, year: nil, plate: nil,
        powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil, paceLimitKmPerDay: paceLimit)
}

private func fill(date: Date, odometer: Int, id: UUID = UUID.v7()) -> FillUp {
    FillUp(
        id: id, createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: UUID.v7(), date: date, odometer: odometer, money: nil,
        note: nil, attachments: [], provenance: .manual, conflict: .none,
        purchaseGroupId: nil, volumeL: 40, unitPrice: nil, fuelKind: .petrol95,
        fuelGrade: nil, isFull: true, tankLevelAfterPct: nil, stationId: nil,
        crossCheck: .notApplicable, extraction: nil)
}

/// The owner's real gap: a car logged at 150 000 km in 2019, then a fill years
/// later at 82 000 km - a sold-and-rebought car, an odometer swap, a gap nobody
/// remembers. The validator flags the later entry `.order` (its odometer does
/// not fit between its date-neighbours); nothing about the gap can ever be
/// "fixed" without inventing numbers for a year the user cannot remember.
private struct RealGap {
    var earlier: FillUp
    var gapped: FillUp

    init() {
        let earlierDate = epoch
        let gappedDate = epoch + 6 * 365 * day
        earlier = fill(date: earlierDate, odometer: 150_000)
        gapped = fill(date: gappedDate, odometer: 82_000)
        gapped.conflict = .flagged(kind: .order, detectedAt: gappedDate)
    }

    var entries: [any Entry] { [earlier, gapped] }

    func acceptance(_ reason: String = "the car was sold and rebought") -> FlagAcceptance {
        FlagAcceptance(
            kind: .order,
            acceptedOdometer: gapped.odometer,
            acceptedDate: gapped.date,
            reason: reason,
            acceptedAt: gapped.date.addingTimeInterval(day))
    }

    /// The same write an accept does: conflict cleared, acceptance recorded.
    func accepted() -> RealGap {
        var copy = self
        copy.gapped.conflict = .none
        copy.gapped.flagAcceptance = acceptance()
        return copy
    }
}

// MARK: - L1: the acceptance survives a re-validation (the row's headline)

@Test func anAcceptedEntrySurvivesRevalidationAcrossARealGap() {
    var timeline = RealGap().accepted()

    // Assert by RE-RUNNING the validator over the same entries - the L1 trap
    // names an in-memory "it looks cleared" assertion as vacuous, because the
    // stored conflict re-derives on the next sync/import/archive re-validation.
    let firstPass = TimelineValidator.validate(entries: timeline.entries, vehicle: vehicle())
    let firstResult = firstPass.first { $0.entryID == timeline.gapped.id }
    #expect(firstResult?.conflict == ConflictState.none,
            "the accepted entry must not re-flag on a re-validation")
    #expect(firstResult?.acceptance == timeline.gapped.flagAcceptance,
            "the acceptance stays on the entry while it is the reason the flag stays down")

    // And a SECOND re-validation is still quiet - re-validation is what sync
    // apply, import commit and archive import all run.
    let secondPass = TimelineValidator.validate(entries: timeline.entries, vehicle: vehicle())
    #expect(secondPass.first { $0.entryID == timeline.gapped.id }?.conflict == ConflictState.none)
}

// MARK: - L1: the keying rule - editing the accepted facts re-flags

@Test func editingTheAcceptedOdometersStillReFlagsTheEntry() {
    var timeline = RealGap().accepted()

    // The user rewrites the odometer in 2027 (docs/SCHEMA.md -> Validation ->
    // Acceptance keying rule: an acceptance covers entry id + odometer + date;
    // change a fact and it stops covering). The new reading is still out of
    // order against the 2019 neighbour, so the entry must flag again.
    timeline.gapped.odometer = 60_000
    timeline.gapped.updatedAt = epoch.addingTimeInterval(8 * 365 * day)

    let result = TimelineValidator.validate(entries: timeline.entries, vehicle: vehicle())
        .first { $0.entryID == timeline.gapped.id }
    #expect(result?.conflict == .flagged(kind: .order, detectedAt: timeline.gapped.createdAt),
            "editing the odometer must re-flag an entry whose new reading still breaks the timeline")
    #expect(result?.acceptance == nil,
            "the stale acceptance must not survive the edit that invalidated it")
}

@Test func editingTheAcceptedDateStillReFlagsTheEntry() {
    // The accepted entry's facts: odometer 58 000 on 2019-01-01, flagged `.order`
    // because 58 000 >= the 55 000 of the 2020 neighbour after it. Accept it.
    let a = fill(date: epoch, odometer: 50_000)
    var b = fill(date: epoch + 365 * day, odometer: 58_000)
    b.conflict = .flagged(kind: .order, detectedAt: b.createdAt)
    b.flagAcceptance = FlagAcceptance(
        kind: .order, acceptedOdometer: 58_000, acceptedDate: b.date,
        reason: "gap", acceptedAt: b.date.addingTimeInterval(day))
    let c = fill(date: epoch + 2 * 365 * day, odometer: 55_000)
    let before = TimelineValidator.validate(entries: [a, b, c], vehicle: vehicle())
        .first { $0.entryID == b.id }
    #expect(before?.conflict == ConflictState.none, "the acceptance must hold before the date edit")

    // Move the accepted entry BEFORE the 2019 entry: odometer 58 000 now sits
    // above its next neighbour (50 000) - still an order violation, and the
    // acceptance no longer covers because the date changed.
    var edited = b
    edited.date = epoch - 6 * 30 * day
    edited.updatedAt = edited.date

    let after = TimelineValidator.validate(entries: [edited, a, c], vehicle: vehicle())
        .first { $0.entryID == b.id }
    #expect(after?.conflict == .flagged(kind: .order, detectedAt: b.createdAt),
            "editing the date must re-flag an entry whose new date still breaks the timeline")
    #expect(after?.acceptance == nil)
}

// MARK: - L1: an entry never accepted flags exactly as it always did

@Test func anEntryNeverAcceptedStillFlagsExactlyAsBefore() {
    var timeline = RealGap()
    let before = TimelineValidator.validate(entries: timeline.entries, vehicle: vehicle())
        .first { $0.entryID == timeline.gapped.id }
    #expect(before?.conflict == .flagged(kind: .order, detectedAt: timeline.gapped.createdAt))
    #expect(before?.acceptance == nil)
    // The flags themselves are unchanged - RV.104 changes nothing about what the
    // validator DETECTS; it only adds the acceptance as an input.
    #expect(before?.flags.contains { $0.kind == .order } == true)
}

@Test func anAcceptanceForADifferentKindDoesNotSilenceTheFlag() {
    // The entry is flagged `.order`; the stored acceptance claims `.pace`. The
    // user accepted a pace flag somewhere else on these facts - not this order
    // violation - so the order flag must still surface (kind-aware, per the
    // keying rule).
    var timeline = RealGap()
    timeline.gapped.flagAcceptance = FlagAcceptance(
        kind: .pace, acceptedOdometer: 82_000, acceptedDate: timeline.gapped.date,
        reason: nil, acceptedAt: timeline.gapped.date.addingTimeInterval(day))

    let result = TimelineValidator.validate(entries: timeline.entries, vehicle: vehicle())
        .first { $0.entryID == timeline.gapped.id }
    #expect(result?.conflict == .flagged(kind: .order, detectedAt: timeline.gapped.createdAt))
    #expect(result?.acceptance == nil)
}

// MARK: - The validator's output carries what a write path must store

@Test func validationAcceptanceIsNilWhenTheTimelineHeals() {
    // Once the neighbours change so the accepted entry is genuinely in order,
    // there is nothing left to accept: the validator clears the stale
    // acceptance (an acceptance only lives while it suppresses a real flag).
    var timeline = RealGap().accepted()
    // The 2019 neighbour's odometer was itself a typo; correcting it to 60 000
    // makes the 82 000 gap entry strictly increasing - the timeline heals.
    timeline.earlier.odometer = 60_000

    let result = TimelineValidator.validate(entries: timeline.entries, vehicle: vehicle())
        .first { $0.entryID == timeline.gapped.id }
    // The healed timeline has no ORDER flag left, so the stale acceptance is
    // dropped. (CHECK 5's consumption hint may still speak - it is a different
    // question, and its own suite is `RV218ConsumptionOutlierTests`.)
    #expect(result?.flags.contains { $0.kind == .order } == false)
    #expect(result?.acceptance == nil,
            "a healed timeline keeps no stale acceptance - nothing is silently 'accepted' anymore")
}

// MARK: - The repository actions the UI calls (accept / undo)

@Test func repositoryAcceptThenRevalidateKeepsItQuietAndUndoReFlags() throws {
    let repo = try makeSyncRepository()
    let vehicle = makeSyncVehicle()
    try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
    let earlier = makeSyncFillUp(vehicleId: vehicle.id, date: epoch, odometer: 150_000)
    let gapped = makeSyncFillUp(vehicleId: vehicle.id, date: epoch + 6 * 365 * day,
                                odometer: 82_000)
    try repo.upsertFillUp(earlier, syncState: .synced(scn: 2))
    try repo.upsertFillUp(gapped, syncState: .synced(scn: 3))

    // The timeline genuinely flags the falling-odometer pair.
    _ = try repo.revalidateTimeline(vehicleIds: [vehicle.id])
    #expect(try repo.flaggedEntryCount() == 2)

    // Accept one entry from the list; its conflict clears.
    let acceptedID = gapped.id
    #expect(try repo.acceptFlag(id: acceptedID, reason: "sold and rebought"))
    #expect(try repo.liveFillUps(forVehicle: vehicle.id)
        .first { $0.id == acceptedID }?.conflict == ConflictState.none)
    #expect(try repo.flaggedEntryCount() == 1,
            "accepting one entry drops the flagged count by exactly one")

    // A re-validation - what sync apply runs - does NOT bring it back.
    #expect(try repo.revalidateTimeline(vehicleIds: [vehicle.id]) == 0)
    #expect(try repo.liveFillUps(forVehicle: vehicle.id)
        .first { $0.id == acceptedID }?.flagAcceptance != nil)

    // Undo re-flags it: the decision is gone, the validator derives from the
    // entries alone and the still-broken timeline surfaces again (hard rule 8).
    #expect(try repo.undoFlagAcceptance(id: acceptedID))
    #expect(try repo.liveFillUps(forVehicle: vehicle.id)
        .first { $0.id == acceptedID }?.conflict
        == .flagged(kind: .order, detectedAt: repo.liveFillUps(forVehicle: vehicle.id)
            .first { $0.id == acceptedID }!.createdAt))
    #expect(try repo.flaggedEntryCount() == 2)

    // Accepting an id that is not a live flagged entry is a no-op, never a crash.
    #expect(try repo.acceptFlag(id: UUID.v7(), reason: nil) == false)
    // Undoing an entry with no acceptance is a no-op too.
    #expect(try repo.undoFlagAcceptance(id: earlier.id) == false)
}

// MARK: - The covers predicate IS the keying rule

@Test func acceptanceCoversExactFactsOnly() {
    let acceptance = RealGap().acceptance()
    #expect(acceptance.covers(odometer: 82_000, date: RealGap().gapped.date))
    #expect(!acceptance.covers(odometer: 82_001, date: RealGap().gapped.date))
    #expect(!acceptance.covers(odometer: 82_000,
                               date: RealGap().gapped.date.addingTimeInterval(day)))
}

// MARK: - L2: the acceptance survives a sync round-trip (two repositories)

@Test func acceptanceSurvivesASyncRoundTripAndTheSecondDeviceDoesNotReFlag() async throws {
    // Device A: vehicle + the two fills of a real gap - a falling odometer flags
    // BOTH boundary entries (each is a separate per-entry acceptance, exactly
    // the past-years cluster the owner works through one row at a time).
    let repositoryA = try makeSyncRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeSyncVehicle(id: vehicleID)
    try repositoryA.upsertVehicle(vehicle, syncState: .synced(scn: 1))

    var earlier = makeSyncFillUp(vehicleId: vehicleID, date: epoch, odometer: 150_000)
    earlier.createdAt = epoch
    var gapped = makeSyncFillUp(vehicleId: vehicleID, date: epoch + 6 * 365 * day,
                                odometer: 82_000)
    gapped.createdAt = gapped.date
    // Both entries genuinely flag against each other (docs/SCHEMA.md CHECK 1).
    earlier.conflict = .flagged(kind: .order, detectedAt: earlier.createdAt)
    gapped.conflict = .flagged(kind: .order, detectedAt: gapped.createdAt)
    try repositoryA.upsertFillUp(earlier, syncState: .synced(scn: 2))

    // The accept on both, as the user would work the list: conflict cleared,
    // acceptance recorded, row dirty (it pushes).
    let acceptEarlier = FlagAcceptance(
        kind: .order, acceptedOdometer: 150_000, acceptedDate: earlier.date,
        reason: "sold and rebought", acceptedAt: gapped.date.addingTimeInterval(day))
    earlier.conflict = .none
    earlier.flagAcceptance = acceptEarlier
    earlier.updatedAt = gapped.date
    try repositoryA.upsertFillUp(earlier)

    let acceptGapped = FlagAcceptance(
        kind: .order, acceptedOdometer: 82_000, acceptedDate: gapped.date,
        reason: "sold and rebought", acceptedAt: gapped.date.addingTimeInterval(day))
    gapped.conflict = .none
    gapped.flagAcceptance = acceptGapped
    gapped.updatedAt = gapped.date.addingTimeInterval(day)
    try repositoryA.upsertFillUp(gapped)   // .dirty: the next push carries it

    // A's dirty row encodes WITH the acceptance in the payload.
    let local = try #require(try repositoryA.localSyncRecord(
        id: gapped.id, entityType: FillUp.entityType))
    let encoded = try PayloadCodec.decode(
        PayloadEnvelope(entityType: local.record.entityType,
                        schemaVersion: local.record.schemaVersion,
                        payload: local.record.payload),
        as: FillUp.self).entity
    #expect(encoded.flagAcceptance == acceptGapped,
            "the acceptance must ride the record's payload (no server change)")

    // Device B pulls both records and applies them, then re-validates exactly as
    // a sync merge does (docs/SYNC.md S3).
    let repositoryB = try makeSyncRepository()
    try repositoryB.upsertVehicle(vehicle, syncState: .synced(scn: 1))
    let earlierOnB = try PayloadCodec.decode(
        PayloadEnvelope(entityType: FillUp.entityType,
                        schemaVersion: PayloadCodec.currentSchemaVersion,
                        payload: try PayloadCodec.encode(earlier).payload),
        as: FillUp.self).entity
    _ = try repositoryB.applyRemoteRecord(
        makeSyncRecord(earlierOnB, clientUpdatedAt: earlier.updatedAt), scn: 2)
    _ = try repositoryB.applyRemoteRecord(local.record, scn: 3)

    let reflagged = try repositoryB.revalidateTimeline(vehicleIds: [vehicleID])
    #expect(reflagged == 0,
            "the second device must not re-flag what the first device accepted")

    let stored = try repositoryB.liveFillUps(forVehicle: vehicleID)
        .first { $0.id == gapped.id }
    #expect(stored?.conflict == ConflictState.none)
    #expect(stored?.flagAcceptance == acceptGapped,
            "the acceptance survives the round-trip and rides the entry on the second device")
    #expect(try repositoryB.liveFillUps(forVehicle: vehicleID)
        .first { $0.id == earlier.id }?.flagAcceptance == acceptEarlier)
    #expect(try repositoryB.flaggedEntryCount() == 0)
}
