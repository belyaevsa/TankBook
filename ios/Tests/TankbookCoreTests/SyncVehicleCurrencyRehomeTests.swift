import Foundation
import os
import Testing
@testable import TankbookCore

// RV.143 - a home-currency change that ARRIVES BY SYNC re-homes the receiving
// device's pending entries, exactly as RV.140's Vehicle-detail save does on the
// device where the currency was typed. S9's field-level merge delivers the new
// `homeCurrency`; without this trigger the editing device shows resolved rows
// and every other device keeps them rate-pending. The pass is the ONE
// `MoneyBackfillService.rehome` - the sync path calls it through the
// `HomeCurrencyRehomer` seam, never a second copy.

private let rehomeCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func rehomeDay(_ day: Int) -> Date {
    Date(timeIntervalSinceReferenceDate: Double(day) * 86_400)
}

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

/// A pending `FillUp`: USD paid against an EUR home - the owner's imported row
/// that the currency change must resolve.
private func pendingUSDFill(vehicleId: UUID, date: Date, odometer: Int,
                            amount: String) -> FillUp {
    FillUp(
        id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: odometer,
        money: Money(amount: decimal(amount), currency: .usd, homeCurrency: .eur),
        note: nil, attachments: [], provenance: .manual, conflict: .none,
        purchaseGroupId: nil, volumeL: 42.3, unitPrice: nil, fuelKind: .petrol95,
        fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
        crossCheck: .notApplicable, extraction: nil
    )
}

/// A snapshotted PLN row: history that was true when recorded (home EUR) and
/// must survive a later home-currency change byte-identical (hard rule 3).
private func snapshottedPLNFill(vehicleId: UUID, date: Date, odometer: Int) -> FillUp {
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
        .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: date, source: .ecb))
    return FillUp(
        id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: odometer, money: money,
        note: nil, attachments: [], provenance: .manual, conflict: .none,
        purchaseGroupId: nil, volumeL: 42.3, unitPrice: nil, fuelKind: .petrol95,
        fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
        crossCheck: .notApplicable, extraction: nil
    )
}

/// Records every re-home call, so a test can assert the sync trigger invokes
/// the pass - the call, not a second implementation. The production conformer
/// is `MoneyBackfillService`, so this witnesses the seam the save also uses.
private final class SpyHomeCurrencyRehomer: HomeCurrencyRehomer, @unchecked Sendable {
    struct Call: Equatable { let vehicleID: UUID; let newHome: CurrencyCode }
    private let lock = OSAllocatedUnfairLock(initialState: [Call]())

    var calls: [Call] { lock.withLock { $0 } }

    func rehome(_ repository: TankbookRepository, vehicleID: UUID,
                to newHome: CurrencyCode) throws -> MoneyBackfillService.Result {
        lock.withLock { $0.append(Call(vehicleID: vehicleID, newHome: newHome)) }
        return MoneyBackfillService.Result(filledCount: 0, stillPendingCount: 0)
    }
}

@Suite("RV.143: a home currency arriving by sync runs the re-home pass")
struct SyncVehicleCurrencyRehomeTests {
    private func rehomer() -> MoneyBackfillService {
        MoneyBackfillService(store: RateStore(seed: [], calendar: rehomeCalendar))
    }

    /// The row's whole point: a pulled Vehicle whose `homeCurrency` differs from
    /// the stored one re-homes the car's rate-pending entries through the same
    /// pass RV.140 calls, and leaves a snapshotted entry byte-identical.
    @Test func pullingANewHomeCurrencyRehomesPendingEntriesAndTravelsThem() async throws {
        let repo = try makeSyncRepository()
        let vehicleId = UUID.v7()
        var vehicle = makeSyncVehicle(id: vehicleId, homeCurrency: .eur)
        vehicle.updatedAt = rehomeDay(0)
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

        let entryDay = rehomeDay(10)
        let snapshotted = snapshottedPLNFill(vehicleId: vehicleId, date: entryDay, odometer: 100_000)
        try repo.upsertFillUp(snapshotted, syncState: .synced(scn: 2))
        let pending = pendingUSDFill(vehicleId: vehicleId, date: entryDay,
                                     odometer: 100_500, amount: "110.00")
        try repo.upsertFillUp(pending, syncState: .synced(scn: 3))

        let snapshotBefore = try repo.liveFillUps(forVehicle: vehicleId)
            .first { $0.id == snapshotted.id }?.money

        var remote = makeSyncVehicle(id: vehicleId, homeCurrency: .usd)
        remote.updatedAt = rehomeDay(1)
        let transport = SyncTransportDouble()
        transport.enqueuePull(SyncPullResponse(
            records: [makePullRecord(remote, scn: 4)], nextSince: 4, more: false,
            schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1)))

        let engine = makeSyncEngine(repository: repo, transport: transport,
                                    memory: DatabaseSyncPayloadMemory(repository: repo),
                                    homeCurrencyRehomer: rehomer())
        _ = await engine.synchronize()

        #expect(try repo.vehicle(id: vehicleId)?.homeCurrency == .usd,
                "the pulled vehicle's new home is applied")

        let rows = try repo.liveFillUps(forVehicle: vehicleId)
        let rehomed = try #require(rows.first { $0.id == pending.id }?.money)
        #expect(rehomed.homeCurrency == .usd, "the pending row follows the arriving home")
        #expect(!rehomed.isRatePending, "same-currency money resolves at rate 1, no fetch")
        #expect(rehomed.homeAmount == rehomed.amount)
        #expect(rehomed.rate == Decimal(1))

        let afterSnapshot = try #require(rows.first { $0.id == snapshotted.id }?.money)
        #expect(afterSnapshot == snapshotBefore,
                "a snapshotted entry is never rewritten (hard rule 3)")
        #expect(afterSnapshot.homeCurrency == .eur)

        let pushed = transport.recordedPushBatches.flatMap { $0 }.map(\.id)
        #expect(pushed.contains(pending.id), "the re-homed row is queued dirty and travels")
        #expect(!pushed.contains(snapshotted.id), "the untouched snapshot is not re-queued")
    }

    /// The same function, asserted as a call: the sync trigger goes through the
    /// `HomeCurrencyRehomer` seam with the car and the new home - the exact
    /// method `MoneyBackfillService.rehome` implements and RV.140's save calls.
    @Test func theSyncTriggerCallsTheOneRehomePassWithTheNewHome() async throws {
        let repo = try makeSyncRepository()
        let vehicleId = UUID.v7()
        var vehicle = makeSyncVehicle(id: vehicleId, homeCurrency: .eur)
        vehicle.updatedAt = rehomeDay(0)
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

        var remote = makeSyncVehicle(id: vehicleId, homeCurrency: .usd)
        remote.updatedAt = rehomeDay(1)
        let transport = SyncTransportDouble()
        transport.enqueuePull(SyncPullResponse(
            records: [makePullRecord(remote, scn: 2)], nextSince: 2, more: false,
            schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1)))

        let spy = SpyHomeCurrencyRehomer()
        let engine = makeSyncEngine(repository: repo, transport: transport,
                                    homeCurrencyRehomer: spy)
        _ = await engine.synchronize()

        #expect(spy.calls == [.init(vehicleID: vehicleId, newHome: .usd)],
                "the sync apply calls the shared re-home pass exactly once")
    }

    /// An unchanged currency triggers nothing - the pass is not run on every
    /// pull, and a second pull of the now-settled currency does not run it
    /// again (idempotent at the trigger).
    @Test func anUnchangedCurrencyTriggersNothing() async throws {
        let repo = try makeSyncRepository()
        let vehicleId = UUID.v7()
        var vehicle = makeSyncVehicle(id: vehicleId, homeCurrency: .eur)
        vehicle.updatedAt = rehomeDay(0)
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

        var remote = makeSyncVehicle(id: vehicleId, homeCurrency: .eur)
        remote.updatedAt = rehomeDay(1)
        let transport = SyncTransportDouble()
        transport.enqueuePull(SyncPullResponse(
            records: [makePullRecord(remote, scn: 2)], nextSince: 2, more: false,
            schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1)))

        let spy = SpyHomeCurrencyRehomer()
        let engine = makeSyncEngine(repository: repo, transport: transport,
                                    homeCurrencyRehomer: spy)
        _ = await engine.synchronize()

        #expect(spy.calls.isEmpty, "a pull that changes no currency runs no re-home")
    }

    /// The S9 field-merge shape: the local device renamed the car and the
    /// remote changed its home currency. The merge is a genuine new write, and
    /// the currency that arrived through it still re-homes the pending rows.
    @Test func aFieldMergedHomeCurrencyStillRehomes() async throws {
        let repo = try makeSyncRepository()
        let vehicleId = UUID.v7()
        var baseline = makeSyncVehicle(id: vehicleId, name: "Volvo", homeCurrency: .eur)
        baseline.updatedAt = rehomeDay(0)
        try repo.upsertVehicle(baseline, syncState: .synced(scn: 1))
        let pending = pendingUSDFill(vehicleId: vehicleId, date: rehomeDay(10),
                                     odometer: 100_500, amount: "110.00")
        try repo.upsertFillUp(pending, syncState: .synced(scn: 2))

        var renamed = baseline
        renamed.name = "V60"
        renamed.updatedAt = rehomeDay(4)
        try repo.upsertVehicle(renamed)

        var remote = makeSyncVehicle(id: vehicleId, name: "Volvo", homeCurrency: .usd)
        remote.updatedAt = rehomeDay(8)
        var versions: [String: Date] = [:]
        for field in VehicleMergeFields.all { versions[field] = rehomeDay(0) }
        versions["homeCurrency"] = rehomeDay(8)
        let transport = SyncTransportDouble()
        transport.enqueuePull(SyncPullResponse(
            records: [makePullRecord(remote, scn: 5, fieldVersions: versions)],
            nextSince: 5, more: false,
            schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1)))

        let engine = makeSyncEngine(repository: repo, transport: transport,
                                    memory: DatabaseSyncPayloadMemory(repository: repo),
                                    homeCurrencyRehomer: rehomer())
        _ = await engine.synchronize()

        let merged = try #require(try repo.vehicle(id: vehicleId))
        #expect(merged.name == "V60", "the local rename survives the merge (S9)")
        #expect(merged.homeCurrency == .usd, "the remote currency wins its field (S9)")
        let money = try #require(try repo.liveFillUps(forVehicle: vehicleId)
            .first { $0.id == pending.id }?.money)
        #expect(money.homeCurrency == .usd && !money.isRatePending,
                "a currency that arrived through a field merge re-homes the pending row")
    }

    /// The push-side sibling: an S6 conflict resolves by adopting the server's
    /// newer `homeCurrency`, which is another way the currency ARRIVES. The
    /// conflict path is the same decision as the pull path, so it runs the same
    /// pass rather than leaving the receiving device's rows pending.
    @Test func aConflictThatAdoptsANewHomeCurrencyStillRehomes() async throws {
        let repo = try makeSyncRepository()
        let vehicleId = UUID.v7()
        var baseline = makeSyncVehicle(id: vehicleId, name: "Volvo", homeCurrency: .eur)
        baseline.updatedAt = rehomeDay(0)
        try repo.upsertVehicle(baseline, syncState: .synced(scn: 1))
        let pending = pendingUSDFill(vehicleId: vehicleId, date: rehomeDay(10),
                                     odometer: 100_500, amount: "110.00")
        try repo.upsertFillUp(pending, syncState: .synced(scn: 2))

        var renamed = baseline
        renamed.name = "V60"
        renamed.updatedAt = rehomeDay(2)
        try repo.upsertVehicle(renamed)

        var serverVehicle = makeSyncVehicle(id: vehicleId, name: "V60", homeCurrency: .usd)
        serverVehicle.updatedAt = rehomeDay(4)
        var versions: [String: Date] = [:]
        for field in VehicleMergeFields.all { versions[field] = rehomeDay(0) }
        versions["name"] = rehomeDay(4)
        versions["homeCurrency"] = rehomeDay(4)
        let serverRecord = makePullRecord(serverVehicle, scn: 9, fieldVersions: versions)

        let transport = SyncTransportDouble()
        transport.setAlwaysConflict(current: serverRecord)

        let engine = makeSyncEngine(repository: repo, transport: transport,
                                    memory: DatabaseSyncPayloadMemory(repository: repo),
                                    homeCurrencyRehomer: rehomer())
        _ = await engine.synchronize()

        #expect(try repo.vehicle(id: vehicleId)?.homeCurrency == .usd,
                "the conflict merge adopts the server's home currency")
        let money = try #require(try repo.liveFillUps(forVehicle: vehicleId)
            .first { $0.id == pending.id }?.money)
        #expect(money.homeCurrency == .usd && !money.isRatePending,
                "a currency adopted through a conflict re-homes the pending row")
    }
}
