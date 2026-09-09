import Foundation
import os
import Testing
@testable import TankbookCore

// RV.157 - the debounced write trigger (docs/SYNC.md: the cycle runs "after
// every local write (debounced)"). The write half lives in `SyncWriteScheduler`
// (core) and is driven here through the REAL seams: a repository write fires the
// database write signal (`TankbookDatabase.writeSignal`), the signal pokes the
// scheduler, and the scheduler's `run` drives a real coordinator over a real
// repository + transport double. Asserting coordinator.cycleCounts() (never a
// "a sync happened" boolean) is what makes the coalescing assertions exact.

// MARK: - Helpers

private func waitUntil(timeoutNanoseconds: UInt64 = 3_000_000_000,
                       _ condition: @escaping @Sendable () async -> Bool) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !(await condition()) {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("timed out waiting for the condition")
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

// MARK: - The debounced write trigger, driven through the repository seam

@MainActor
@Suite("Debounced write trigger (RV.157)")
struct SyncWriteTriggerTests {

    /// One local write schedules exactly ONE cycle. The write is a repository
    /// upsert; the signal it fires pokes the scheduler; the scheduler's run is
    /// a real coordinator over the same repository. Asserted on the coordinator
    /// cycle count, never a "a sync happened" boolean.
    @Test func oneLocalWriteSchedulesExactlyOneCycle() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let transport = SyncTransportDouble()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport))

        let scheduler = makeScheduler(repo: repo, coordinator: coordinator)
        arm(scheduler, repo: repo)

        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)
        // Wait for the cycle's OUTCOME (the row pushed clean), not just its
        // start: the coordinator counts a cycle before the engine has finished.
        // Poll the (Sendable) transport, never the non-Sendable repository.
        await waitUntil { !transport.recordedPushBatches.isEmpty }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(try repo.fetchDirtyRows().isEmpty,
                "the pushed row is clean after the one cycle")

        #expect(coordinator.cycleCounts().total == 1,
                "one local write must schedule exactly one cycle")
        #expect(!transport.recordedPushBatches.isEmpty,
                "the one cycle must actually push the dirty row")
        // No second cycle may follow the first: the engine's own writes are
        // suppressed (RV.157) so they cannot re-poke the scheduler.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(coordinator.cycleCounts().total == 1,
                "the engine's own writes must not schedule a second cycle")
    }

    /// N writes inside the debounce window still schedule ONE cycle - a burst
    /// (an import commit, a backfill) is one cycle, never one per write.
    @Test func aBurstInsideTheWindowSchedulesOneCycle() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let transport = SyncTransportDouble()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport))

        let scheduler = makeScheduler(repo: repo, coordinator: coordinator)
        arm(scheduler, repo: repo)

        for _ in 0..<5 {
            try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)
        }
        await waitUntil { coordinator.cycleCounts().total == 1 }

        #expect(coordinator.cycleCounts().total == 1,
                "a burst inside the window must schedule exactly one cycle")
        // Wait for the cycle to actually push (the coordinator counts a cycle
        // at its start, before the engine has finished).
        await waitUntil { !transport.recordedPushBatches.isEmpty }
        #expect(transport.recordedPushBatches.first?.count == 5,
                "the one cycle pushes the whole burst, not one cycle per row")
        #expect(try repo.fetchDirtyRows().isEmpty,
                "the one cycle cleaned the whole burst")
        try? await Task.sleep(for: .milliseconds(150))
        #expect(coordinator.cycleCounts().total == 1,
                "a burst must not trail a second cycle")
    }

    /// The trigger defers under Low Power Mode and drains through the
    /// `LowPowerResumer` when the mode ends - the same deferral the foreground
    /// pass gets, owned by the trigger so a poke during the mode is not lost.
    @Test func writeTriggerDefersUnderLowPowerAndDrainsThroughTheResumer() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let power = MutablePowerState(lowPower: true)
        let center = NotificationCenter()
        let resumer = LowPowerResumer(powerState: power, notificationCenter: center)
        await resumer.start()
        let transport = SyncTransportDouble()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport,
                                   powerState: power),
            powerState: power)

        let scheduler = SyncWriteScheduler(window: .milliseconds(20),
                                           powerState: power, resumer: resumer)
        configure(scheduler, repo: repo, coordinator: coordinator)
        arm(scheduler, repo: repo)

        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)
        // The mode is on: the poke must NOT run a cycle; it registers with the
        // resumer instead.
        await waitUntil { await resumer.pendingCount == 1 }
        #expect(coordinator.cycleCounts().total == 0,
                "under Low Power Mode the trigger must defer, not run a cycle")
        #expect(transport.recordedPushBatches.isEmpty,
                "a deferred cycle must not touch the transport")

        // The mode ends: the resumer drains the registered cycle.
        power.isLowPowerModeEnabled = false
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await waitUntil { !transport.recordedPushBatches.isEmpty }

        #expect(coordinator.cycleCounts().total == 1,
                "the deferred cycle drains through the resumer when the mode ends")
        #expect(try repo.fetchDirtyRows().isEmpty,
                "the drained cycle pushed the dirty row")
    }

    /// A signed-out write schedules no cycle: the trigger's `isArmed` gate
    /// (the app wires it to `session != nil`) makes the poke a cheap no-op.
    /// The scheduler must not even schedule a fire, so no cycle starts and
    /// finds nothing.
    @MainActor
    @Test func signedOutWriteSchedulesNoCycle() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: SyncTransportDouble()))

        let scheduler = SyncWriteScheduler(window: .milliseconds(20))
        scheduler.isArmed = { false }   // the app wires this to session != nil
        scheduler.run = { _ = await coordinator.syncNow(trigger: .background) }
        arm(scheduler, repo: repo)

        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)
        try? await Task.sleep(for: .milliseconds(120))

        #expect(coordinator.cycleCounts().total == 0,
                "a signed-out write must never schedule a cycle")
    }

    /// The save never awaits the scheduled work and never fails because of it
    /// (hard rule 1): the write commits locally even when the transport is
    /// down, and the poke returns before any cycle has run.
    @MainActor
    @Test func aSaveNeverAwaitsTheScheduledCycle() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let transport = SyncTransportDouble()
        transport.setFailAll(true)   // the transport is unavailable/erroring
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport))

        let scheduler = makeScheduler(repo: repo, coordinator: coordinator)
        arm(scheduler, repo: repo)

        // The save itself: it must return (the dirty row is present) with no
        // cycle having run yet - the schedule is async, never awaited.
        let fill = makeSyncFillUp(vehicleId: vehicle.id)
        try repo.upsertFillUp(fill, syncState: .dirty)
        #expect(try repo.fetchDirtyRows().contains { $0.id == fill.id },
                "the save committed locally")
        #expect(coordinator.cycleCounts().total == 0,
                "the save must not await the scheduled cycle")

        // The debounced cycle then runs and fails against the dead transport -
        // the row stays dirty and nothing threw at the save.
        await waitUntil { coordinator.cycleCounts().total == 1 }
        #expect(try repo.fetchDirtyRows().contains { $0.id == fill.id },
                "a failed cycle leaves the save's row dirty - nothing was lost")
    }

    // MARK: - Seam helpers (mirror the app's AppSync wiring)

    private func arm(_ scheduler: SyncWriteScheduler, repo: TankbookRepository) {
        let signal = repo.database.writeSignal
        signal.observer = { [weak scheduler] in
            Task { @MainActor in scheduler?.noteWrite() }
        }
    }

    private func makeScheduler(repo: TankbookRepository,
                               coordinator: SyncCoordinator) -> SyncWriteScheduler {
        let scheduler = SyncWriteScheduler(window: .milliseconds(20))
        configure(scheduler, repo: repo, coordinator: coordinator)
        return scheduler
    }

    private func configure(_ scheduler: SyncWriteScheduler,
                           repo: TankbookRepository,
                           coordinator: SyncCoordinator) {
        scheduler.isArmed = { true }
        scheduler.isBusy = { coordinator.isSyncing }
        scheduler.hasWork = { ((try? repo.fetchDirtyRows())?.isEmpty == false) }
        scheduler.isRetryPending = { coordinator.scheduledRetryDelay() != nil }
        scheduler.run = { _ = await coordinator.syncNow(trigger: .background) }
    }
}
