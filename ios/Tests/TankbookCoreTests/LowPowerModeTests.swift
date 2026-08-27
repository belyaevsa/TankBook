import Foundation
import os
import Testing
@testable import TankbookCore

// P6.8 - Respect Low Power Mode (docs/SYNC.md -> Low Power Mode): background and
// opportunistic work defers while the mode is on; the user's own taps never do.
// The load-bearing distinction is the trigger, and the power state is always an
// injected value - every test flips a `MutablePowerState`, never the host's
// `ProcessInfo`, because a test that read the real state would only pass on the
// machine that ran it.

// MARK: - Test doubles

/// The `PowerStateProvider` test double: a lock-guarded boolean a test flips, so
/// "the mode is on/off" is a test decision, never the host's state.
final class MutablePowerState: PowerStateProvider, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    init(lowPower: Bool) { lock.withLock { $0 = lowPower } }

    var isLowPowerModeEnabled: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

/// Counts invocations of a drain closure, thread-safely.
final class RecordingClosure: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: (count: 0, ran: false))

    var count: Int { lock.withLock { $0.count } }
    var didRun: Bool { lock.withLock { $0.ran } }

    func run() async {
        lock.withLock { state in
            state.count += 1
            state.ran = true
        }
    }
}

/// A `RateFetcher` that counts fetches and returns an empty pack.
private final class CountingRateFetcher: RateFetcher, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    var fetchCount: Int { lock.withLock { $0 } }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate] {
        lock.withLock { $0 += 1 }
        return []
    }
}

/// A `VehicleCatalogFetcher` that counts fetches and answers "nothing new" (a
/// 304). The fetch is what the deferral must skip; what it would return does
/// not matter to this suite.
private final class CountingCatalogFetcher: VehicleCatalogFetcher, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    var fetchCount: Int { lock.withLock { $0 } }

    func fetchPack(sinceVersion: Int) async throws -> VehicleCatalogPack? {
        lock.withLock { $0 += 1 }
        return nil
    }
}

private func waitUntil(timeoutNanoseconds: UInt64 = 2_000_000_000,
                       _ condition: @escaping @Sendable () async -> Bool) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !(await condition()) {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("timed out waiting for the condition")
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func tempCacheDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("tankbook-lowpower-tests-\(UUID().uuidString)")
}

private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// A minimal bundled seed, so a refresh against it is a real, gated fetch.
private func makeBundledSeed() -> [VehicleCatalogEntry] {
    [
        VehicleCatalogEntry(make: "Volvo", model: "V60", generation: "SPA",
                            years: [2018, nil], powertrain: .ice,
                            fuelKinds: [.petrol95, .diesel], tankCapacityL: 71,
                            batteryCapacityKWh: nil, packVersion: 2)
    ]
}

private let pullPolicy = SyncSchemaPolicy(minSupported: 1, current: 1)

// MARK: - The policy value

@Suite("Low Power Mode (P6.8)")
struct LowPowerModeTests {

    // MARK: The policy is a pure function of the injected boolean

    @Test func policyDefersEveryOpportunisticWorkKindWhileTheModeIsOn() {
        for kind in [PowerWorkKind.syncCycle, .blobUpload, .blobPrefetch,
                     .ratePackRefresh, .catalogPackFetch, .timerJob] {
            #expect(LowPowerPolicy.defers(work: kind, trigger: .background, lowPowerMode: true),
                    "\(kind) must defer on a background trigger while the mode is on")
        }
    }

    @Test func policyNeverDefersWhileTheModeIsOff() {
        for kind in [PowerWorkKind.syncCycle, .blobUpload, .blobPrefetch,
                     .ratePackRefresh, .catalogPackFetch, .timerJob] {
            #expect(!LowPowerPolicy.defers(work: kind, trigger: .background, lowPowerMode: false),
                    "\(kind) must run when the mode is off")
        }
    }

    @Test func policyNeverDefersTheUsersOwnTaps() {
        for kind in [PowerWorkKind.syncCycle, .ratePackRefresh, .catalogPackFetch] {
            #expect(!LowPowerPolicy.defers(work: kind, trigger: .userInitiated, lowPowerMode: true),
                    "\(kind) on a user-initiated trigger must run even while the mode is on")
        }
    }

    @Test func policyDefersBlobWorkEvenInsideAUserInitiatedSync() {
        // Blob upload is the heaviest work there is (docs/SYNC.md) and defers
        // whenever the mode is on - even in a sync the user asked for - so the
        // record stays dirty and the entry syncs text-first (S7).
        #expect(LowPowerPolicy.defers(work: .blobUpload, trigger: .userInitiated, lowPowerMode: true))
        #expect(LowPowerPolicy.defers(work: .blobPrefetch, trigger: .userInitiated, lowPowerMode: true))
    }

    // MARK: Tests 1 & 2 - an opportunistic cycle defers only while the mode is on

    @Test func backgroundCycleDefersWhileTheModeIsOnAndTheQueueIsUntouched() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

        let power = MutablePowerState(lowPower: true)
        let transport = SyncTransportDouble()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport, powerState: power),
            powerState: power)

        let outcome = await coordinator.syncNow(trigger: .background)

        // The cycle was postponed - the outcome says so...
        #expect(outcome.deferred, "a background cycle must defer while the mode is on")
        // ...and the queue is exactly as it was: the dirty row is still dirty
        // and no transport call was made. Assert the queue, not just the return
        // value (hard rule 8 - nothing dropped, never lost silently).
        #expect(try repo.fetchDirtyRows().count == 1, "the deferred queue must be unchanged")
        #expect(transport.recordedPullRequests.isEmpty, "a deferred cycle must not pull")
        #expect(transport.recordedPushBatches.isEmpty, "a deferred cycle must not push")
    }

    @Test func backgroundCycleRunsWhileTheModeIsOff() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

        let power = MutablePowerState(lowPower: false)
        let transport = SyncTransportDouble()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport, powerState: power),
            powerState: power)

        let outcome = await coordinator.syncNow(trigger: .background)

        // The same cycle runs when the mode is off - an implementation that
        // always defers passes test 1; only this half tells the difference.
        #expect(!outcome.deferred, "the same cycle must run when the mode is off")
        #expect(outcome.pushed == 1)
        #expect(try repo.fetchDirtyRows().isEmpty, "the pushed row is clean")
    }

    // MARK: Test 3 - a user-initiated sync/restore RUNS while the mode is on

    @Test func userInitiatedSyncRunsWhileTheModeIsOn() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

        let power = MutablePowerState(lowPower: true)
        let transport = SyncTransportDouble()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport, powerState: power),
            powerState: power)

        let outcome = await coordinator.syncNow(trigger: .userInitiated)

        // The test this task exists for: a "sync now" tap the user made must
        // not be silently cancelled - a user staring at a spinner that was
        // cancelled has no next step (hard rule 7) and reads as a hang.
        #expect(!outcome.deferred, "a sync the user asked for must run while the mode is on")
        #expect(outcome.pushed == 1)
        #expect(try repo.fetchDirtyRows().isEmpty)
        #expect(!transport.recordedPullRequests.isEmpty, "the transport was actually reached")
    }

    @Test func restoreRunsWhileTheModeIsOn() async throws {
        let repo = try makeSyncRepository()
        let power = MutablePowerState(lowPower: true)
        let transport = SyncTransportDouble()
        transport.enqueuePull(SyncPullResponse(
            records: [makePullRecord(makeSyncVehicle(), scn: 1)],
            nextSince: 1, more: false, schemaPolicy: pullPolicy))
        let engine = makeSyncEngine(repository: repo, transport: transport, powerState: power)
        let restore = RestoreEngine(engine: engine)

        let outcome = await restore.restore()

        guard case .restored = outcome else {
            Issue.record("a restore the user asked for must complete while the mode is on, got \(outcome)")
            return
        }
        #expect(!transport.recordedPullRequests.isEmpty, "the restore actually pulled")
    }

    // MARK: Test 4 - resume fires on the state change, not only at launch

    @Test func resumeFiresOnThePowerStateChangeNotAtLaunchAndDrains() async throws {
        let power = MutablePowerState(lowPower: true)
        let center = NotificationCenter()
        let resumer = LowPowerResumer(powerState: power, notificationCenter: center)
        await resumer.start()

        // Work is deferred while the mode is on.
        let ran = RecordingClosure()
        await resumer.register(LowPowerResumer.PendingWork(id: UUID(), kind: .ratePackRefresh) {
            await ran.run()
        })
        #expect(resumer.pendingCount == 1)

        // The mode ends...
        power.isLowPowerModeEnabled = false
        // ...but nothing drains yet: resume is keyed to the state CHANGE, not
        // to the mode merely being off. A device that left the mode hours ago
        // must not still be holding its queue because no one re-checked.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(resumer.pendingCount == 1, "drain must not run before the state change notification")
        #expect(!ran.didRun, "no drain before the state change notification")

        // The state change arrives: the deferred work drains.
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await waitUntil { ran.count == 1 }
        #expect(resumer.pendingCount == 0, "the drained work is no longer pending")
        #expect(ran.count == 1, "the deferred work drains on the power-state change")
    }

    @Test func drainDoesNotRunWhileTheModeIsStillOn() async throws {
        let power = MutablePowerState(lowPower: true)
        let center = NotificationCenter()
        let resumer = LowPowerResumer(powerState: power, notificationCenter: center)
        await resumer.start()

        let ran = RecordingClosure()
        await resumer.register(LowPowerResumer.PendingWork(id: UUID(), kind: .syncCycle) {
            await ran.run()
        })

        // A state change while the mode is still on (it turned on, or a spurious
        // duplicate) must not drain - work waits until the mode is actually off.
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(resumer.pendingCount == 1, "drain must not run while the mode is on")
        #expect(!ran.didRun)
    }

    // MARK: Test 5 - saves, edits and deletes are unaffected while the mode is on

    @Test func savesEditsAndDeletesAreUnaffectedWhileTheModeIsOn() async throws {
        // Saves are always local, always immediate (hard rule 1); reading,
        // editing and deleting are the whole local app (docs/SYNC.md -> Low
        // Power Mode, "Never defers"). The power seam has no voice in them - a
        // save while the mode is on must be indistinguishable from a save while
        // it is off.
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

        let power = MutablePowerState(lowPower: true)

        // Save: the row lands, dirty, immediately.
        let fillUp = makeSyncFillUp(vehicleId: vehicle.id)
        try repo.upsertFillUp(fillUp, syncState: .dirty)
        #expect(try repo.fetchDirtyRows().contains { $0.id == fillUp.id })

        // Edit: the row updates in place.
        var edited = fillUp
        edited.note = "edited while the mode was on"
        try repo.upsertFillUp(edited, syncState: .dirty)
        let stored = try repo.liveEntries(forVehicle: vehicle.id).first { $0.id == fillUp.id }
        #expect(stored?.note == "edited while the mode was on")

        // Delete: the row tombstones into the undo window (hard rule 8).
        try repo.softDeleteFillUp(id: fillUp.id)
        #expect(try repo.liveEntries(forVehicle: vehicle.id).isEmpty)
        #expect(try repo.deletedEntries().contains { $0.entry.id == fillUp.id })

        // And the mode did not change the seam's own answer for the user's taps.
        #expect(!LowPowerPolicy.defers(work: .syncCycle, trigger: .userInitiated,
                                       lowPowerMode: power.isLowPowerModeEnabled))
    }

    // MARK: Test 6 - blob upload defers without losing the pending record

    @Test func blobUploadDefersWithoutLosingThePendingRecord() async throws {
        let repo = try makeSyncRepository()
        let rendition = Data("rendition-bytes".utf8)
        let sha256 = BlobHash.sha256(rendition)

        let power = MutablePowerState(lowPower: true)
        let blobTransport = BlobTransportDouble()
        let gate = LocalFileBlobPushGate(
            uploader: BlobUploader(transport: blobTransport),
            source: FixedBlobSource(data: rendition))
        let syncTransport = SyncTransportDouble()
        let engine = makeSyncEngine(repository: repo, transport: syncTransport,
                                    blobGate: gate, powerState: power)

        let attachment = makeSyncAttachment(sha256: sha256)
        try repo.upsertAttachment(attachment)

        // The heaviest work there is defers even inside a user-initiated sync:
        // the blob transport is never touched...
        _ = await engine.synchronize(trigger: .userInitiated)
        #expect(blobTransport.recordedBeginRequests.isEmpty, "a deferred blob must not begin an upload")
        #expect(blobTransport.putRequestCount == 0)
        #expect(blobTransport.commitCount == 0)
        // ...the record did not push...
        #expect(!syncTransport.recordedPushBatches.contains { $0.contains { $0.id == attachment.id } })
        // ...and it stays dirty: nothing was lost, the next cycle retries.
        #expect(try repo.fetchDirtyRows().contains { $0.id == attachment.id })
    }

    @Test func blobUploadRunsWhileTheModeIsOff() async throws {
        let repo = try makeSyncRepository()
        let rendition = Data("rendition-bytes".utf8)
        let sha256 = BlobHash.sha256(rendition)

        let power = MutablePowerState(lowPower: false)
        let blobTransport = BlobTransportDouble()
        blobTransport.setBeginResult(.upload(url: URL(string: "https://storage.example/presigned/put")!,
                                             expiresAt: nil))
        let gate = LocalFileBlobPushGate(
            uploader: BlobUploader(transport: blobTransport),
            source: FixedBlobSource(data: rendition))
        let syncTransport = SyncTransportDouble()
        let engine = makeSyncEngine(repository: repo, transport: syncTransport,
                                    blobGate: gate, powerState: power)

        let attachment = makeSyncAttachment(sha256: sha256)
        try repo.upsertAttachment(attachment)

        _ = await engine.synchronize(trigger: .userInitiated)

        #expect(blobTransport.commitCount == 1, "the blob uploads when the mode is off")
        #expect(syncTransport.recordedPushBatches.contains { $0.contains { $0.id == attachment.id } })
        #expect(try repo.fetchDirtyRows().isEmpty)
    }

    // MARK: The rates and catalog call sites

    @Test func ratePackRefreshDefersWhileTheModeIsOnAndRunsWhenOff() async throws {
        let power = MutablePowerState(lowPower: true)
        let fetcher = CountingRateFetcher()
        let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar, powerState: power)

        #expect(!(await store.refresh()), "the rate pack refresh must defer while the mode is on")
        #expect(fetcher.fetchCount == 0, "a deferred refresh must not hit the network")

        power.isLowPowerModeEnabled = false
        #expect(await store.refresh(), "the same refresh must run when the mode is off")
        #expect(fetcher.fetchCount == 1)
    }

    @Test func ratePackRefreshWithAnExplicitUserInitiatedTriggerRunsWhileTheModeIsOn() async throws {
        let power = MutablePowerState(lowPower: true)
        let fetcher = CountingRateFetcher()
        let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar, powerState: power)

        #expect(await store.refresh(trigger: .userInitiated),
                "a user-initiated rate refresh must run while the mode is on")
        #expect(fetcher.fetchCount == 1)
    }

    @Test func catalogPackFetchDefersWhileTheModeIsOnAndRunsWhenOff() async throws {
        let dir = tempCacheDirectory()
        defer { remove(dir) }
        let power = MutablePowerState(lowPower: true)
        let fetcher = CountingCatalogFetcher()
        let updater = VehicleCatalogUpdater(bundled: makeBundledSeed(), cacheDirectory: dir,
                                            fetcher: fetcher, minimumFetchInterval: 0,
                                            powerState: power)

        #expect(!(await updater.refresh()), "the catalog pack fetch must defer while the mode is on")
        #expect(fetcher.fetchCount == 0, "a deferred fetch must not hit the network")

        power.isLowPowerModeEnabled = false
        #expect(await updater.refresh(), "the same fetch must run when the mode is off")
        #expect(fetcher.fetchCount == 1)
    }
}
