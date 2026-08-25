import Testing
import Foundation
@testable import TankbookCore

// MARK: - Shared fixtures (file-private, used by both suites below)

/// Fixed "now" for deterministic windows: 2025-07-06 (UTC).
private let duplicateAsOf = Date(timeIntervalSince1970: 1_752_000_000)
private let duplicateDay: TimeInterval = 86_400
private let duplicateMinute: TimeInterval = 60

private func duplicateVehicle(id: UUID = UUID.v7()) -> Vehicle {
    Vehicle(
        id: id, createdAt: duplicateAsOf - 40 * duplicateDay,
        updatedAt: duplicateAsOf - 40 * duplicateDay,
        deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
        plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
        tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                              energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500,
        initialOdometer: 118_000)
}

private func duplicateMoney(_ amount: String) -> Money {
    Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
}

/// A fixture fill-up. `createdAt` defaults to `date` so a caller can make one
/// member of a pair "earlier" by setting it explicitly.
private func duplicateFill(vehicleID: UUID, date: Date, odometer: Int?,
                           litres: Double, amount: String = "71.02",
                           isFull: Bool, createdAt: Date? = nil,
                           attachments: [AttachmentID] = [],
                           note: String? = nil,
                           conflict: ConflictState = .none,
                           purchaseGroupID: UUID? = nil,
                           fiscalIdentity: FiscalDocumentIdentity? = nil) -> FillUp {
    let stamp = createdAt ?? date
    return FillUp(
        id: UUID.v7(), createdAt: stamp, updatedAt: stamp, deletedAt: nil,
        vehicleId: vehicleID, date: date, odometer: odometer,
        money: duplicateMoney(amount), note: note, attachments: attachments,
        provenance: .manual, conflict: conflict, purchaseGroupId: purchaseGroupID,
        volumeL: litres, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
        isFull: isFull, tankLevelAfterPct: isFull ? 100 : nil, stationId: nil,
        crossCheck: .notApplicable, extraction: nil, fiscalIdentity: fiscalIdentity)
}

private func duplicateRepository() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

// MARK: - Heuristic boundaries

/// The S2 duplicate heuristic (docs/SYNC.md, S2): same vehicle, dates within 30
/// minutes, volume within 5% flags the pair. Every boundary is asserted on BOTH
/// sides, at a small volume and a large one, because 5% of 10 L and 5% of 60 L
/// are very different absolute numbers (docs/TESTING.md, L1 - pure, no
/// simulator).
struct DuplicateDetectorTests {

    @Test static func twentyNineMinutesApartFlags() {
        let vehicleID = UUID.v7()
        let fillA = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                  litres: 42, isFull: true)
        let fillB = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 29 * duplicateMinute,
                                  odometer: 118_000, litres: 42, isFull: true)
        #expect(DuplicateDetector.isDuplicate(fillA, fillB))
        #expect(DuplicateDetector.pairs(in: [fillA, fillB]).count == 1)
    }

    @Test static func thirtyMinutesExactlyFlags() {
        let vehicleID = UUID.v7()
        let fillA = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                  litres: 42, isFull: true)
        let fillB = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 30 * duplicateMinute,
                                  odometer: 118_000, litres: 42, isFull: true)
        #expect(DuplicateDetector.isDuplicate(fillA, fillB))
    }

    @Test static func thirtyOneMinutesApartDoesNotFlag() {
        let vehicleID = UUID.v7()
        let fillA = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                  litres: 42, isFull: true)
        let fillB = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 31 * duplicateMinute,
                                  odometer: 118_000, litres: 42, isFull: true)
        #expect(!DuplicateDetector.isDuplicate(fillA, fillB))
        #expect(DuplicateDetector.pairs(in: [fillA, fillB]).isEmpty)
    }

    @Test static func volumeWithinFivePercentFlags() {
        let vehicleID = UUID.v7()
        // Small volume: 5% of 10 L is 0.5 L.
        let small = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                  litres: 10, isFull: true)
        let smallNear = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 10 * duplicateMinute,
                                      odometer: 118_000, litres: 10.49, isFull: true)
        #expect(DuplicateDetector.isDuplicate(small, smallNear))

        // Large volume: 5% of 60 L is 3.0 L - a very different absolute number.
        let large = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                  litres: 60, isFull: true)
        let largeNear = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 10 * duplicateMinute,
                                      odometer: 118_000, litres: 62.9, isFull: true)
        #expect(DuplicateDetector.isDuplicate(large, largeNear))
    }

    @Test static func volumeFivePointOnePercentApartDoesNotFlag() {
        let vehicleID = UUID.v7()
        // 10.51 is 5.1% larger than 10.0: beyond the 5% bound at small volumes.
        let small = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                  litres: 10, isFull: true)
        let smallFar = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 10 * duplicateMinute,
                                     odometer: 118_000, litres: 10.51, isFull: true)
        #expect(!DuplicateDetector.isDuplicate(small, smallFar))

        // 63.1 is 5.17% larger than 60.0: beyond the 5% bound at large volumes.
        let large = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                  litres: 60, isFull: true)
        let largeFar = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 10 * duplicateMinute,
                                     odometer: 118_000, litres: 63.1, isFull: true)
        #expect(!DuplicateDetector.isDuplicate(large, largeFar))
    }

    @Test static func differentVehiclesNeverFlagHoweverCloseTheValues() {
        let fillA = duplicateFill(vehicleID: UUID.v7(), date: duplicateAsOf, odometer: 118_000,
                                  litres: 42.3, isFull: true)
        let fillB = duplicateFill(vehicleID: UUID.v7(), date: duplicateAsOf, odometer: 118_000,
                                  litres: 42.3, isFull: true)
        #expect(!DuplicateDetector.isDuplicate(fillA, fillB))
        #expect(DuplicateDetector.pairs(in: [fillA, fillB]).isEmpty)
    }

    @Test static func attachmentWinsTheCountedRole() {
        let vehicleID = UUID.v7()
        let attachment = UUID.v7()
        let withPhoto = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                      litres: 42, isFull: true,
                                      createdAt: duplicateAsOf + 5 * duplicateMinute,
                                      attachments: [attachment])
        let plain = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                  litres: 42, isFull: true)
        #expect(DuplicateDetector.counted(withPhoto, plain) == withPhoto.id)
        #expect(DuplicateDetector.counted(plain, withPhoto) == withPhoto.id)
    }

    @Test static func earlierCreatedCountsWhenNeitherHasAnAttachment() {
        let vehicleID = UUID.v7()
        let earlier = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                    litres: 42, isFull: true, createdAt: duplicateAsOf)
        let later = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 10 * duplicateMinute,
                                  odometer: 118_000, litres: 42, isFull: true,
                                  createdAt: duplicateAsOf + 10 * duplicateMinute)
        #expect(DuplicateDetector.counted(earlier, later) == earlier.id)
        #expect(DuplicateDetector.counted(later, earlier) == earlier.id)
    }

    @Test static func sameDataInEitherInputOrderYieldsTheSamePairs() {
        let vehicleID = UUID.v7()
        let f1 = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 14 * duplicateDay,
                               odometer: 118_000, litres: 42, isFull: true)
        let d1 = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 7 * duplicateDay,
                               odometer: 118_400, litres: 42, isFull: false)
        let d2 = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 7 * duplicateDay + 10 * duplicateMinute,
                               odometer: 118_400, litres: 42, isFull: false)
        let f2 = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - duplicateDay,
                               odometer: 118_800, litres: 42, isFull: true)

        let forward = DuplicateDetector.pairs(in: [f1, d1, d2, f2])
        let reversed = DuplicateDetector.pairs(in: [f2, d2, d1, f1])
        #expect(forward == reversed)
        #expect(forward.count == 1)
        #expect(forward[0].vehicleID == vehicleID)
        #expect(forward[0].countedID == reversed[0].countedID)
    }
}

// MARK: - The single-count invariant, the combined card and the resolutions

/// The substance of P1.8 (docs/SYNC.md S2): until the user decides, only ONE of
/// an unresolved duplicate pair counts in consumption, month totals and every
/// derived figure - stats never double. The counted one is deterministic; the
/// two resolutions ("Keep both" = both count from then on, "Merge" = the richer
/// record survives and the other is tombstoned, recoverable) are each asserted
/// on the actual figures, not on a boolean.
struct DuplicateSingleCountTests {

    /// A segment F1 -> F2 with two near-identical fills (D1, D2) logged for one
    /// physical fill in between. Unresolved, only ONE of D1/D2 may contribute
    /// liters and spend.
    private static func scenario() -> (fills: [FillUp], vehicleID: UUID) {
        let vehicleID = UUID.v7()
        let fills = [
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 14 * duplicateDay,
                          odometer: 118_000, litres: 42, amount: "68.46", isFull: true),
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 7 * duplicateDay,
                          odometer: 118_400, litres: 42, amount: "71.02", isFull: false),
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 7 * duplicateDay + 10 * duplicateMinute,
                          odometer: 118_400, litres: 42, amount: "71.02", isFull: false),
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - duplicateDay,
                          odometer: 118_800, litres: 42, amount: "68.46", isFull: true)
        ]
        return (fills, vehicleID)
    }

    @Test static func unresolvedPairContributesOnceToConsumption() {
        let scenario = Self.scenario()
        let stats = HomeStats(vehicle: duplicateVehicle(id: scenario.vehicleID),
                              entries: scenario.fills, asOf: duplicateAsOf)

        // The segment F1 -> F2 consumes the liters of ONE of the pair plus the
        // closing fill: 42 + 42 = 84, not 126. That is the number that would
        // double without the invariant.
        #expect(stats.headline?.totalLitres == 84)
        #expect(stats.headline?.totalKm == 800)
        if let headline = stats.headline {
            #expect(abs(headline.value - 10.5) < 0.001)
        }
    }

    @Test static func unresolvedPairContributesOnceToMonthTotal() {
        // All four fills inside the calendar month containing `asOf`, so the
        // month-spend vital isolates the pair.
        let vehicleID = UUID.v7()
        let fills = [
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 3 * duplicateDay,
                          odometer: 118_000, litres: 42, amount: "68.46", isFull: true),
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 2 * duplicateDay,
                          odometer: 118_400, litres: 42, amount: "71.02", isFull: false),
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 2 * duplicateDay + 10 * duplicateMinute,
                          odometer: 118_400, litres: 42, amount: "71.02", isFull: false),
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - duplicateDay,
                          odometer: 118_800, litres: 42, amount: "68.46", isFull: true)
        ]
        let stats = HomeStats(vehicle: duplicateVehicle(id: vehicleID), entries: fills,
                              asOf: duplicateAsOf)
        // 68.46 + 71.02 + 68.46, with the second 71.02 set aside.
        #expect(stats.monthSpend == Decimal(string: "207.94"))
    }

    @Test static func countedOneIsDeterministicAcrossInputOrderForTheFigures() {
        let scenario = Self.scenario()
        let vehicle = duplicateVehicle(id: scenario.vehicleID)
        let forward = HomeStats(vehicle: vehicle, entries: scenario.fills, asOf: duplicateAsOf)
        let reversed = HomeStats(vehicle: vehicle, entries: scenario.fills.reversed(), asOf: duplicateAsOf)

        #expect(forward.headline == reversed.headline)
        #expect(forward.monthSpend == reversed.monthSpend)
        #expect(forward.excludedEntryCount == reversed.excludedEntryCount)
    }

    // MARK: - The excluded-count footnote number matches the engine's flags

    @Test static func excludedCountMatchesUnresolvedPairs() {
        let scenario = Self.scenario()
        let stats = HomeStats(vehicle: duplicateVehicle(id: scenario.vehicleID),
                              entries: scenario.fills, asOf: duplicateAsOf)
        #expect(stats.excludedEntryCount == 1)
    }

    @Test static func excludedCountAddsConflictFlagsAndDuplicateExclusions() {
        let scenario = Self.scenario()
        var flagged = scenario.fills[3]
        flagged.conflict = .flagged(kind: ConflictState.ConflictKind.order, detectedAt: duplicateAsOf)
        let entries: [any Entry] = scenario.fills.map { $0.id == flagged.id ? flagged : $0 }
        let stats = HomeStats(vehicle: duplicateVehicle(id: scenario.vehicleID),
                              entries: entries, asOf: duplicateAsOf)
        // One duplicate-excluded fill plus one conflict-flagged fill.
        #expect(stats.excludedEntryCount == 2)
    }

    // MARK: - The combined card in the stream

    @Test static func unresolvedPairRendersAsOneCombinedCardRow() {
        let scenario = Self.scenario()
        let stream = LogStream(vehicle: duplicateVehicle(id: scenario.vehicleID),
                               entries: scenario.fills, calendar: calendar)
        let duplicates = stream.allRows.filter {
            if case .duplicate = $0 { return true } else { return false }
        }
        #expect(duplicates.count == 1)
        // The pair's two fills became one row: 3 rows total (two real fills +
        // one card), not 4.
        #expect(stream.rowCount(collapsedGroupIDs: []) == 3)
        guard case .duplicate(let group) = duplicates[0] else {
            Issue.record("expected a duplicate group")
            return
        }
        // The counted member drives the card's identity and date.
        let countedID = DuplicateDetector.counted(scenario.fills[1], scenario.fills[2])
        #expect(group.counted.id == countedID)
        #expect(group.excluded.id != countedID)
    }

    @Test static func duplicateCardContributesOnceToMonthDividerTotal() {
        let vehicleID = UUID.v7()
        let fills = [
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 3 * duplicateDay,
                          odometer: 118_000, litres: 42, amount: "68.46", isFull: true),
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 2 * duplicateDay,
                          odometer: 118_400, litres: 42, amount: "71.02", isFull: false),
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - 2 * duplicateDay + 10 * duplicateMinute,
                          odometer: 118_400, litres: 42, amount: "71.02", isFull: false),
            duplicateFill(vehicleID: vehicleID, date: duplicateAsOf - duplicateDay,
                          odometer: 118_800, litres: 42, amount: "68.46", isFull: true)
        ]
        let stream = LogStream(vehicle: duplicateVehicle(id: vehicleID), entries: fills,
                               calendar: calendar)
        #expect(stream.sections.count == 1)
        #expect(stream.sections[0].totalSpend == Decimal(string: "207.94"))
    }

    // MARK: - Keep both: both count from then on

    @Test static func keepBothSuppressesThePairAndBothCountAfterwards() throws {
        let scenario = Self.scenario()
        let pair = try #require(DuplicateDetector.pairs(in: scenario.fills).first)

        // Pure layer: passing the resolution key suppresses the pair.
        #expect(DuplicateDetector.pairs(in: scenario.fills, resolved: [pair.key]).isEmpty)

        // End to end through the repository: record "keep both", reload, and
        // BOTH entries count - the month total is the full four amounts.
        let repository = try duplicateRepository()
        try repository.upsertVehicle(duplicateVehicle(id: scenario.vehicleID))
        for fill in scenario.fills {
            try repository.upsertFillUp(fill)
        }
        try repository.upsertDuplicateResolution(DuplicateResolution(
            id: UUID.v7(), createdAt: duplicateAsOf, updatedAt: duplicateAsOf, deletedAt: nil,
            countedEntryID: pair.countedID, excludedEntryID: pair.excludedID,
            resolution: .keepBoth))

        let keys = try repository.resolvedDuplicateKeys()
        #expect(keys.contains(pair.key))

        let live = try repository.liveFillUps(forVehicle: scenario.vehicleID)
        let stats = HomeStats(vehicle: duplicateVehicle(id: scenario.vehicleID),
                              entries: live, asOf: duplicateAsOf,
                              duplicateResolutions: try repository.resolvedDuplicateKeys())
        #expect(stats.headline?.totalLitres == 126)
        #expect(stats.excludedEntryCount == 0)
    }

    // MARK: - Merge: the richer record survives, the other becomes a tombstone

    @Test static func mergeKeepsTheRicherRecordAndTombstonesTheOther() throws {
        let repository = try duplicateRepository()
        let vehicle = duplicateVehicle()
        try repository.upsertVehicle(vehicle)

        let attachment = UUID.v7()
        let winner = duplicateFill(vehicleID: vehicle.id, date: duplicateAsOf, odometer: 118_000,
                                   litres: 42, isFull: true,
                                   createdAt: duplicateAsOf - 5 * duplicateMinute,
                                   attachments: [attachment])
        let loser = duplicateFill(vehicleID: vehicle.id, date: duplicateAsOf + 10 * duplicateMinute,
                                  odometer: nil, litres: 42, isFull: true,
                                  createdAt: duplicateAsOf + 5 * duplicateMinute,
                                  note: "logged from the phone")
        try repository.upsertFillUp(winner)
        try repository.upsertFillUp(loser)

        // The merge survivor: the winner keeps its id and takes the loser's
        // fields (note, odometer), and the attachment wins.
        let merged = DuplicateMerge.merge(winner: winner, loser: loser)
        #expect(merged.id == winner.id)
        #expect(merged.attachments.contains(attachment))
        #expect(merged.note == "logged from the phone")
        #expect(merged.odometer == 118_000)
        #expect(merged.vehicleId == vehicle.id)

        // Persist the merge: survivor written, loser tombstoned.
        try repository.upsertFillUp(merged)
        try repository.softDeleteFillUp(id: loser.id)

        let live = try repository.liveFillUps(forVehicle: vehicle.id)
        #expect(live.map(\.id) == [merged.id])

        // Nothing is lost silently: the loser lands in Recently deleted...
        let deleted = try repository.deletedEntries()
        #expect(deleted.contains { $0.id == loser.id })
        #expect(deleted.count == 1)

        // ...and is recoverable: restore brings it back into the live set.
        try repository.restoreEntry(id: loser.id)
        #expect(try repository.liveFillUps(forVehicle: vehicle.id).count == 2)
    }

    @Test static func mergeSurvivorIsExactlyTheCountedEntry() {
        let vehicleID = UUID.v7()
        let attachment = UUID.v7()
        let withPhoto = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                      litres: 42, isFull: true, attachments: [attachment])
        let plain = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 10 * duplicateMinute,
                                  odometer: 118_000, litres: 42, isFull: true)
        let pair = DuplicateDetector.pairs(in: [withPhoto, plain])
        #expect(pair.count == 1)
        // The counted entry IS the merge winner - so consumption is continuous
        // across a Merge: nothing jumps when the user resolves.
        #expect(pair[0].countedID == DuplicateMerge.merge(winner: withPhoto, loser: plain).id)
    }

    // MARK: - Persistence round-trip and scope

    @Test static func duplicateResolutionSurvivesTheDatabase() throws {
        let repository = try duplicateRepository()
        let counted = UUID.v7()
        let excluded = UUID.v7()
        let resolution = DuplicateResolution(
            id: UUID.v7(), createdAt: duplicateAsOf, updatedAt: duplicateAsOf, deletedAt: nil,
            countedEntryID: counted, excludedEntryID: excluded,
            resolution: .keepBoth)
        try repository.upsertDuplicateResolution(resolution)
        #expect(try repository.liveDuplicateResolutions() == [resolution])
        #expect(try repository.resolvedDuplicateKeys().count == 1)
    }

    @Test static func purchaseGroupMembersAreNotFlaggedAsDuplicates() {
        let vehicleID = UUID.v7()
        let groupID = UUID.v7()
        // Two members of ONE receipt - not a double-logged fill.
        let fuel = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                 litres: 42, isFull: true, purchaseGroupID: groupID)
        let wash = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: nil,
                                 litres: 42, isFull: true, purchaseGroupID: groupID)
        #expect(DuplicateDetector.pairs(in: [fuel, wash]).isEmpty)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

// MARK: - Fiscal identity outranks the heuristic (P2.4b)

/// The corpus case (`Spike/ReceiptSpike/fixtures/receipts/README.md` §5b):
/// `receipt-015` and `receipt-026` are two genuine fills, identical to the
/// kopeck, 34 minutes apart. A fiscal identity difference is a proof the
/// purchases differ, not a heuristic - so `isDuplicate` consults it first.
struct FiscalDuplicateTests {

    /// receipt-026 (fixtures/receipts/receipt-026-kedr-feodosia-95-ru.qr.txt):
    /// `t=20260711T1029&s=5380.00&fn=7384440900998746&i=79802&fp=1119386949&n=1`.
    private static let receipt026Identity = FiscalDocumentIdentity(
        fiscalDriveNumber: "7384440900998746", documentNumber: "79802", fiscalSign: "1119386949")

    /// receipt-015 (fixtures/receipts/README.md §5b) publishes ФД/ФП = 30045 /
    /// 4064907347 but no `fn`. The drive number is set distinctly so all three
    /// components differ from receipt-026; the difference already holds on the
    /// two published components alone.
    private static let receipt015Identity = FiscalDocumentIdentity(
        fiscalDriveNumber: "7384440900998745", documentNumber: "30045", fiscalSign: "4064907347")

    @Test static func corpusIdenticalFillsWithDifferentFiscalIdentitiesAreNeverDuplicates() {
        let vehicleID = UUID.v7()
        // receipt-026 10:29 and receipt-015 11:03 - 34 minutes apart, identical
        // volume (20 L) and total (5380.00). Different fiscal identities: not
        // duplicates, regardless of the 30-minute window.
        let fill026 = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                    litres: 20, amount: "5380.00", isFull: true,
                                    fiscalIdentity: receipt026Identity)
        let fill015 = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 34 * duplicateMinute,
                                    odometer: 118_000, litres: 20, amount: "5380.00", isFull: true,
                                    fiscalIdentity: receipt015Identity)
        #expect(!DuplicateDetector.isDuplicate(fill026, fill015))
        #expect(DuplicateDetector.pairs(in: [fill026, fill015]).isEmpty)

        // Move one fill to FOUR minutes apart: today's heuristic alone would flag
        // it (same vehicle, 4 min, identical volume), but the differing identities
        // still veto it. This half is the test - the 34-minute half passes by luck
        // of the clock on the un-wired detector.
        let fill015Moved = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 4 * duplicateMinute,
                                         odometer: 118_000, litres: 20, amount: "5380.00", isFull: true,
                                         fiscalIdentity: receipt015Identity)
        #expect(!DuplicateDetector.isDuplicate(fill026, fill015Moved))
        #expect(DuplicateDetector.pairs(in: [fill026, fill015Moved]).isEmpty)
    }

    @Test static func equalFiscalIdentitiesAreDuplicatesOutsideTheWindow() {
        let vehicleID = UUID.v7()
        // The same receipt scanned twice, two days apart. Equal identities: a
        // duplicate, no matter how far outside the 30-minute window.
        let first = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                  litres: 20, amount: "5380.00", isFull: true,
                                  fiscalIdentity: receipt026Identity)
        let rescan = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 2 * duplicateDay,
                                   odometer: 118_000, litres: 20, amount: "5380.00", isFull: true,
                                   fiscalIdentity: receipt026Identity)
        #expect(DuplicateDetector.isDuplicate(first, rescan))
        #expect(DuplicateDetector.pairs(in: [first, rescan]).count == 1)
    }

    @Test static func nilIdentityFallsBackToTheHeuristicUnchanged() {
        let vehicleID = UUID.v7()
        // Both nil: the heuristic decides, byte-for-byte as before.
        let within = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                   litres: 42, isFull: true)
        let near = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 29 * duplicateMinute,
                                 odometer: 118_000, litres: 42, isFull: true)
        let far = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 31 * duplicateMinute,
                                odometer: 118_000, litres: 42, isFull: true)
        #expect(DuplicateDetector.isDuplicate(within, near))
        #expect(!DuplicateDetector.isDuplicate(within, far))

        // One identity present, one nil: also the heuristic, not the veto and not
        // the equality proof.
        let withIdentity = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                         litres: 42, isFull: true, fiscalIdentity: receipt026Identity)
        #expect(DuplicateDetector.isDuplicate(withIdentity, near))
        #expect(!DuplicateDetector.isDuplicate(withIdentity, far))
    }

    @Test static func singleCountInvariantHoldsForFiscalIdentityPairs() {
        // A re-scan forms exactly ONE pair (so stats count once, docs/SYNC.md S2),
        // and the counted/excluded choice is the unchanged deterministic one.
        let vehicleID = UUID.v7()
        let earlier = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf, odometer: 118_000,
                                    litres: 20, amount: "5380.00", isFull: true,
                                    createdAt: duplicateAsOf, fiscalIdentity: receipt026Identity)
        let rescan = duplicateFill(vehicleID: vehicleID, date: duplicateAsOf + 2 * duplicateDay,
                                   odometer: 118_000, litres: 20, amount: "5380.00", isFull: true,
                                   createdAt: duplicateAsOf + 2 * duplicateDay,
                                   fiscalIdentity: receipt026Identity)
        let pairs = DuplicateDetector.pairs(in: [earlier, rescan])
        #expect(pairs.count == 1)
        #expect(DuplicateDetector.counted(earlier, rescan) == earlier.id)
        #expect(DuplicateDetector.counted(rescan, earlier) == earlier.id)
    }
}
