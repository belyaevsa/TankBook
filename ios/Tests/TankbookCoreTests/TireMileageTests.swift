import Foundation
import Testing
@testable import TankbookCore

/// P3.3 Tire-set derived mileage (docs/SCHEMA.md -> TireSet, "km on this set
/// is DERIVED"). The span math across mount/unmount records: closed spans sum,
/// the open span runs to the latest known odometer, and every unknowable case
/// is excluded - never estimated. Expectations are written as literals, never
/// recomputed with the same function under test.
@Suite struct TireMileageTests {

    private static let setA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private static let setB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    /// A tire-swap record: a ServiceRecord whose `tireSetId` marks a mounting.
    private func swap(_ setID: UUID, odo: Int?, day: Int, vehicle: UUID? = nil) -> ServiceRecord {
        let date = Date(timeIntervalSince1970: 1_752_000_000 + Double(day) * 86_400)
        return ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicle ?? UUID.v7(), date: date, odometer: odo,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil, items: [],
            usedParts: [], tireSetId: setID, proposedReminderId: nil)
    }

    // MARK: - Closed spans sum (three swaps across two sets)

    @Test func threeSwapsAcrossTwoSetsProduceTheRightTotalsForBoth() {
        // A on at 10 000; B on at 15 000 (A off); A back on at 20 000 (B off).
        let records = [
            swap(Self.setA, odo: 10_000, day: 1),
            swap(Self.setB, odo: 15_000, day: 2),
            swap(Self.setA, odo: 20_000, day: 3)
        ]
        let latest = 20_000

        // A: (15 000 - 10 000) closed, plus (latest 20 000 - 20 000) = 0 open.
        #expect(TireMileage.mileage(for: Self.setA, records: records, latestOdometer: latest) == 5_000)
        // B: (20 000 - 15 000) closed.
        #expect(TireMileage.mileage(for: Self.setB, records: records, latestOdometer: latest) == 5_000)
    }

    @Test func swappingBackOntoASetAddsToItsMileageRatherThanRestartingIt() {
        // A 10 000 -> B 15 000 -> A 20 000 -> B 28 000 -> A 32 000 (open).
        let records = [
            swap(Self.setA, odo: 10_000, day: 1),
            swap(Self.setB, odo: 15_000, day: 2),
            swap(Self.setA, odo: 20_000, day: 3),
            swap(Self.setB, odo: 28_000, day: 4),
            swap(Self.setA, odo: 32_000, day: 5)
        ]
        let latest = 32_000

        // A spans: 15k-10k + 28k-20k = 13 000. B spans: 20k-15k + 32k-28k = 9 000.
        #expect(TireMileage.mileage(for: Self.setA, records: records, latestOdometer: latest) == 13_000)
        #expect(TireMileage.mileage(for: Self.setB, records: records, latestOdometer: latest) == 9_000)
    }

    // MARK: - The open span

    @Test func theOpenSpanRunsToTheLatestKnownOdometer() {
        let records = [swap(Self.setA, odo: 10_000, day: 1)]

        #expect(TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 18_400) == 8_400)
        #expect(TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 22_000) == 12_000)
    }

    @Test func theOpenSpanGrowsWhenALaterFillUpRaisesTheOdometer() {
        let records = [swap(Self.setA, odo: 10_000, day: 1)]

        // The same mounted set, before and after a later fill-up raises the
        // latest known odometer - the total grows by exactly the delta.
        let before = TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 18_400)
        let after = TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 19_400)
        #expect(before == 8_400)
        #expect(after == 9_400)
    }

    // MARK: - "– when unknowable" (both directions)

    @Test func aNeverMountedSetYieldsNil() {
        let records = [swap(Self.setB, odo: 12_000, day: 1)]
        #expect(TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 15_000) == nil)
    }

    @Test func aSpanMissingABoundingOdometerIsExcludedNotEstimated() {
        // The mount record has no odometer (a span whose START is unknown).
        let noStart = [swap(Self.setA, odo: nil, day: 1)]
        #expect(TireMileage.mileage(for: Self.setA, records: noStart, latestOdometer: 15_000) == nil)

        // The closing record has no odometer (a span whose END is unknown), so
        // the mounted set's only span is unknowable.
        let noEnd = [
            swap(Self.setA, odo: 10_000, day: 1),
            swap(Self.setB, odo: nil, day: 2)
        ]
        #expect(TireMileage.mileage(for: Self.setA, records: noEnd, latestOdometer: 15_000) == nil)

        // The open span has no latest odometer at all.
        let noLatest = [swap(Self.setA, odo: 10_000, day: 1)]
        #expect(TireMileage.mileage(for: Self.setA, records: noLatest, latestOdometer: nil) == nil)
    }

    @Test func aSetWithAUsableSpanStillReturnsANumberAlongsideAnUnknowableOne() {
        // B has a usable span; A's only span is unknowable (its mount has no
        // odometer). The rule that returns nil for A must still return a number
        // for B - a one-sided nil would make the feature useless.
        let records = [
            swap(Self.setA, odo: nil, day: 1),
            swap(Self.setB, odo: 10_000, day: 2)
        ]
        #expect(TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 20_000) == nil)
        #expect(TireMileage.mileage(for: Self.setB, records: records, latestOdometer: 20_000) == 10_000)
    }

    @Test func aNonPositiveSpanIsExcluded() {
        // The closing odometer went backwards - a data-entry error, not a
        // negative distance to claim.
        let records = [
            swap(Self.setA, odo: 20_000, day: 1),
            swap(Self.setB, odo: 15_000, day: 2)
        ]
        #expect(TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 15_000) == nil)
    }

    // MARK: - Tombstones and non-swaps are ignored

    @Test func tombstonedAndNonSwapRecordsDoNotContribute() {
        let date = Date(timeIntervalSince1970: 1_752_000_000)
        // A tombstoned swap record (deletedAt != nil) must be ignored.
        let tombstoned = ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: date,
            vehicleId: UUID.v7(), date: date, odometer: 30_000,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil, items: [],
            usedParts: [], tireSetId: Self.setA, proposedReminderId: nil)
        // A live record that is not a swap (no tireSetId) must not end a span.
        let plainService = ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date.addingTimeInterval(86_400), odometer: 12_000,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil, items: [],
            usedParts: [], tireSetId: nil, proposedReminderId: nil)

        let records = [swap(Self.setA, odo: 10_000, day: 1), tombstoned, plainService]
        // The open span runs straight to the latest known odometer: neither the
        // tombstone nor the non-swap record closes it.
        #expect(TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 18_000) == 8_000)
    }

    // MARK: - Derived, never stored (recompute after an edit)

    @Test func editingARecordsOdometerChangesTheMileageWithNoInvalidation() {
        let vehicle = UUID.v7()
        var records = [
            swap(Self.setA, odo: 10_000, day: 1, vehicle: vehicle),
            swap(Self.setB, odo: 15_000, day: 2, vehicle: vehicle)
        ]
        let before = TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 15_000)
        #expect(before == 5_000)

        // Editing the closing record's odometer (the same record identity, a
        // new reading) is picked up by the next computation - there is no
        // cached figure anywhere to invalidate (hard rule 2).
        var edited = records[1]
        edited.odometer = 17_000
        records[1] = edited

        let after = TireMileage.mileage(for: Self.setA, records: records, latestOdometer: 17_000)
        #expect(after == 7_000)
    }
}
