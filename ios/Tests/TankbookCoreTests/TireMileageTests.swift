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
    private func swap(_ setID: UUID, odo: Int?, day: Int, vehicle: UUID? = nil,
                      reading: TireReading? = nil) -> ServiceRecord {
        let date = Date(timeIntervalSince1970: 1_752_000_000 + Double(day) * 86_400)
        return ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicle ?? UUID.v7(), date: date, odometer: odo,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil, items: [],
            usedParts: [], tireSetId: setID, tireReading: reading)
    }

    // MARK: - The set's history (stints)

    @Test func twoSetsSwappedThreeTimesGiveEachStintItsSpanAndARunningTotal() {
        // A on 10 000 -> B on 15 000 -> A on 20 000 -> B on 28 000 (open, latest 31 500).
        let records = [
            swap(Self.setA, odo: 10_000, day: 1, reading: TireReading(treadDepthMm: 8.0)),
            swap(Self.setB, odo: 15_000, day: 2),
            swap(Self.setA, odo: 20_000, day: 3, reading: TireReading(treadDepthMm: 6.5, note: "even")),
            swap(Self.setB, odo: 28_000, day: 4)
        ]
        let latest = 31_500

        let stintsA = TireMileage.stints(for: Self.setA, records: records, latestOdometer: latest)
        #expect(stintsA.map(\.km) == [5_000, 8_000])
        #expect(stintsA.map(\.totalKm) == [5_000, 13_000])
        #expect(stintsA.map(\.startOdometer) == [10_000, 20_000])
        #expect(stintsA.map(\.endOdometer) == [15_000, 28_000])
        #expect(stintsA.allSatisfy { !$0.isOnCar })
        #expect(stintsA.map { $0.reading?.treadDepthMm } == [8.0, 6.5])
        #expect(stintsA[1].reading?.note == "even")

        let stintsB = TireMileage.stints(for: Self.setB, records: records, latestOdometer: latest)
        #expect(stintsB.map(\.km) == [5_000, 3_500])
        #expect(stintsB.map(\.totalKm) == [5_000, 8_500])
        // The last stint is open: on the car, running to the latest odometer.
        #expect(stintsB.map(\.isOnCar) == [false, true])
        #expect(stintsB.last?.endOdometer == 31_500)
        #expect(stintsB.last?.endDate == nil)

        // The total is the history's last running total.
        #expect(TireMileage.mileage(for: Self.setA, records: records, latestOdometer: latest) == 13_000)
        #expect(TireMileage.mileage(for: Self.setB, records: records, latestOdometer: latest) == 8_500)
    }

    @Test func aStintWithAMissingOdometerIsUnknownAndTheTotalCarriesOn() {
        // A on 10 000 -> B with no odometer -> A on 20 000 -> B on 24 000.
        let records = [
            swap(Self.setA, odo: 10_000, day: 1),
            swap(Self.setB, odo: nil, day: 2),
            swap(Self.setA, odo: 20_000, day: 3),
            swap(Self.setB, odo: 24_000, day: 4)
        ]
        let stints = TireMileage.stints(for: Self.setA, records: records, latestOdometer: 24_000)
        #expect(stints.map(\.km) == [nil, 4_000])
        #expect(stints.map(\.totalKm) == [nil, 4_000])
        #expect(TireMileage.stints(for: UUID.v7(), records: records, latestOdometer: 24_000).isEmpty)
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
            usedParts: [], tireSetId: Self.setA)
        // A live record that is not a swap (no tireSetId) must not end a span.
        let plainService = ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date.addingTimeInterval(86_400), odometer: 12_000,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil, items: [],
            usedParts: [], tireSetId: nil)

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
