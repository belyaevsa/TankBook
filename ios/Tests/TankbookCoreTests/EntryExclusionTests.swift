import Testing
import Foundation
@testable import TankbookCore

/// The excluded-entry population (RV.141): the list an "N entries excluded"
/// footnote must reach. The derivation is the contract - the footnote's count
/// and the destination's rows come from ONE function, so a count of N can never
/// open a list of fewer (or more) entries. These tests pin the two causes
/// (timeline conflict F9a/S3, unresolved duplicate S2) and the union counting.
struct EntryExclusionTests {

    private static let asOf = Date(timeIntervalSince1970: 1_752_000_000)
    private static let day: TimeInterval = 86_400

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Self.asOf - 40 * Self.day, updatedAt: Self.asOf - 40 * Self.day,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func fill(vehicleID: UUID, date: Date, odometer: Int, litres: Double,
                             conflict: ConflictState = .none) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: odometer,
            money: Money(amount: Decimal(string: "50")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: conflict,
            purchaseGroupId: nil, volumeL: litres, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true,
            tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    /// Two fills that the S2 heuristic pairs: same vehicle, 15 minutes apart,
    /// volumes within 5%.
    private static func duplicatePair(vehicleID: UUID) -> (first: FillUp, second: FillUp) {
        let date = Self.asOf - 2 * Self.day
        let first = Self.fill(vehicleID: vehicleID, date: date, odometer: 122_800, litres: 42.3)
        let second = Self.fill(vehicleID: vehicleID, date: date.addingTimeInterval(15 * 60),
                               odometer: 122_800, litres: 42.9)
        return (first, second)
    }

    @Test func cleanHistoryHasNothingExcluded() {
        let vehicle = Self.vehicle()
        let entries: [any Entry] = [
            Self.fill(vehicleID: vehicle.id, date: Self.asOf - 30 * Self.day, odometer: 118_000, litres: 42),
            Self.fill(vehicleID: vehicle.id, date: Self.asOf - 15 * Self.day, odometer: 118_500, litres: 41),
            Self.fill(vehicleID: vehicle.id, date: Self.asOf - 5 * Self.day, odometer: 119_000, litres: 43)
        ]
        let pairs = DuplicateDetector.pairs(in: entries.compactMap { $0 as? FillUp })
        #expect(pairs.isEmpty)
        #expect(ExcludedEntries.derive(in: entries, duplicatePairs: pairs).isEmpty)

        let stats = HomeStats(vehicle: vehicle, entries: entries, asOf: Self.asOf)
        #expect(stats.excludedEntryCount == 0)
        #expect(stats.excluded.isEmpty)
    }

    /// The footnote and the list agree about a duplicate: the pair's EXCLUDED
    /// member is listed with the duplicate reason, the COUNTED member is not,
    /// and the count the footnote shows equals the list's row count.
    @Test func duplicatePairListsOnlyTheExcludedMemberWithTheDuplicateReason() {
        let vehicle = Self.vehicle()
        let pair = Self.duplicatePair(vehicleID: vehicle.id)
        let entries: [any Entry] = [pair.first, pair.second]
        let pairs = DuplicateDetector.pairs(in: [pair.first, pair.second])
        #expect(pairs.count == 1, "the fixture must actually be a duplicate pair")

        let excluded = ExcludedEntries.derive(in: entries, duplicatePairs: pairs)
        #expect(excluded.count == 1)
        #expect(excluded.first?.id == pairs[0].excludedID,
                "only the non-counting member is excluded, never the counted one")
        #expect(excluded.first?.reason == .unresolvedDuplicate)

        let stats = HomeStats(vehicle: vehicle, entries: entries, asOf: Self.asOf)
        #expect(stats.excludedEntryCount == excluded.count,
                "the footnote count and the destination list must be one population")
        #expect(stats.excludedEntryIDs == excluded.map(\.id))
    }

    /// A conflict-flagged entry is excluded with the conflict reason - the cause
    /// whose fix is editing the odometer or the date.
    @Test func conflictEntryCarriesTheTimelineConflictReason() {
        let vehicle = Self.vehicle()
        let flagged = Self.fill(vehicleID: vehicle.id, date: Self.asOf - 2 * Self.day,
                                odometer: 117_900, litres: 43,
                                conflict: .flagged(kind: .order, detectedAt: Self.asOf))
        let entries: [any Entry] = [
            Self.fill(vehicleID: vehicle.id, date: Self.asOf - 15 * Self.day,
                      odometer: 118_500, litres: 41),
            flagged
        ]
        let excluded = ExcludedEntries.derive(in: entries, duplicatePairs: [])
        #expect(excluded.count == 1)
        #expect(excluded.first?.id == flagged.id)
        #expect(excluded.first?.reason == .timelineConflict)
    }

    /// The RV.141 core shape: both causes at once. The union is counted - a
    /// conflicted entry that is ALSO a duplicate's excluded member counts once
    /// and reads as the more severe reason - and the two listed rows state
    /// DIFFERENT reasons (the whole point of listing them).
    @Test func bothCausesUnionIntoSeparateReasonRows() {
        let vehicle = Self.vehicle()
        let pair = Self.duplicatePair(vehicleID: vehicle.id)
        let conflict = Self.fill(vehicleID: vehicle.id, date: Self.asOf - 5 * Self.day,
                                 odometer: 117_900, litres: 43,
                                 conflict: .flagged(kind: .order, detectedAt: Self.asOf))
        let entries: [any Entry] = [
            Self.fill(vehicleID: vehicle.id, date: Self.asOf - 30 * Self.day, odometer: 118_000, litres: 42),
            Self.fill(vehicleID: vehicle.id, date: Self.asOf - 15 * Self.day, odometer: 118_500, litres: 41),
            conflict, pair.first, pair.second
        ]
        let pairs = DuplicateDetector.pairs(in: entries.compactMap { $0 as? FillUp })
        let excluded = ExcludedEntries.derive(in: entries, duplicatePairs: pairs)
        #expect(excluded.count == 2)
        let reasons = Set(excluded.map(\.reason))
        #expect(reasons == [.timelineConflict, .unresolvedDuplicate],
                "the two rows must tell the two causes apart, got \(reasons)")

        let stats = HomeStats(vehicle: vehicle, entries: entries, asOf: Self.asOf)
        #expect(stats.excludedEntryCount == excluded.count)
        #expect(stats.excludedEntryCount == 2)
    }

    /// An entry carrying BOTH flags (a conflicted duplicate member) counts once
    /// and reads as a conflict - never twice, so a count and a list cannot
    /// disagree by double-counting.
    @Test func doubleFlaggedEntryCountsOnceAsAConflict() {
        let vehicle = Self.vehicle()
        let pair = Self.duplicatePair(vehicleID: vehicle.id)
        // Make the pair's excluded member also conflict-flagged. The counted
        // member is the earlier-created first fill, so the second is excluded.
        let conflictedExcluded = Self.fill(vehicleID: vehicle.id, date: pair.second.date,
                                           odometer: 122_800, litres: 42.9,
                                           conflict: .flagged(kind: .order, detectedAt: Self.asOf))
        let entries: [any Entry] = [pair.first, conflictedExcluded]
        let pairs = DuplicateDetector.pairs(in: entries.compactMap { $0 as? FillUp })
        #expect(pairs.count == 1)
        let excluded = ExcludedEntries.derive(in: entries, duplicatePairs: pairs)
        #expect(excluded.count == 1, "one entry excluded once, never twice")
        #expect(excluded.first?.reason == .timelineConflict,
                "the more severe reason wins when an entry carries both")
    }

    /// Newest first: the list the footnote opens reads like the Log.
    @Test func deriveSortsNewestFirst() {
        let vehicle = Self.vehicle()
        let pair = Self.duplicatePair(vehicleID: vehicle.id) // dated asOf - 2 days
        let olderConflict = Self.fill(vehicleID: vehicle.id, date: Self.asOf - 20 * Self.day,
                                      odometer: 117_000, litres: 40,
                                      conflict: .flagged(kind: .order, detectedAt: Self.asOf))
        let entries: [any Entry] = [olderConflict, pair.first, pair.second]
        let pairs = DuplicateDetector.pairs(in: entries.compactMap { $0 as? FillUp })
        let excluded = ExcludedEntries.derive(in: entries, duplicatePairs: pairs)
        #expect(excluded.count == 2)
        #expect(excluded[0].date > excluded[1].date)
    }
}
