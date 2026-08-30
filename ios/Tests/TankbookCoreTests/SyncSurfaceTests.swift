import Foundation
import Testing
@testable import TankbookCore

// PR.13 - the Settings sync surface renders two DIFFERENT rows for offline and
// for a server 5xx (docs/ERRORS.md -> Settings, rows 155-157):
//
//   - offline            -> "Will sync when you're back online" (passive, never
//                           an error, no next step).
//   - server 5xx         -> "Sync service unreachable - your data is safe..."
//                           with Try again (a next step, but reassurance, never
//                           amber).
//
// Before PR.13 one `transportUnavailable` flag drove both, so a user on a plane
// and a user whose server returns 5xx read the same sentence. Each test below
// pins WHICH of the two states came out and WHICH row it renders - not merely
// that "an error appeared", which is exactly the vacuous assertion the split
// exists to make impossible.

@Suite("Sync surface split: offline vs server-unavailable (PR.13)")
struct SyncSurfaceTests {

    // MARK: - The two states resolve to two different rows

    @Test("serverUnavailable resolves to the service-unreachable row, never offline")
    func serverUnavailableResolvesToServerUnreachable() {
        // A 5xx names the service being down even with a queue pending: the next
        // step is "Try again", not "back online".
        let withQueue = SyncSurfaceState(isSignedIn: true, dirtyCount: 5, serverUnavailable: true)
        #expect(SyncSurface.status(withQueue) == .serverUnreachable)
        let noQueue = SyncSurfaceState(isSignedIn: true, serverUnavailable: true)
        #expect(SyncSurface.status(noQueue) == .serverUnreachable)
    }

    @Test("offline never resolves to the service-unreachable row")
    func offlineNeverResolvesToServerUnreachable() {
        let offlineNoQueue = SyncSurfaceState(isSignedIn: true, offline: true)
        #expect(SyncSurface.status(offlineNoQueue) == .synced,
                "offline with nothing to push is the ordinary synced reassurance, not an error")
        let offlineWithQueue = SyncSurfaceState(isSignedIn: true, dirtyCount: 5, offline: true)
        #expect(SyncSurface.status(offlineWithQueue) == .waitingToSync)
    }

    @Test("isOfflineWithQueue is the offline row alone, never the 5xx row")
    func offlineRowIsOfflineOnly() {
        #expect(SyncSurface.isOfflineWithQueue(
            SyncSurfaceState(isSignedIn: true, dirtyCount: 5, offline: true)))
        #expect(!SyncSurface.isOfflineWithQueue(
            SyncSurfaceState(isSignedIn: true, offline: true)),
            "offline with nothing waiting names no row")
        #expect(!SyncSurface.isOfflineWithQueue(
            SyncSurfaceState(isSignedIn: true, dirtyCount: 5, serverUnavailable: true)),
            "a 5xx is never 'Will sync when you're back online'")
    }

    // MARK: - The engine pins which of the two states came out

    @Test("a transport failure sets offline and never serverUnavailable")
    func engineMapsOffline() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

        let transport = SyncTransportDouble()
        transport.enqueuePullError(.offline)
        let outcome = await makeSyncEngine(repository: repo, transport: transport).synchronize()

        #expect(outcome.offline, "the offline state must come out as offline")
        #expect(!outcome.serverUnavailable, "offline must not read as a 5xx")
    }

    @Test("a 5xx sets serverUnavailable and never offline")
    func engineMapsServerUnavailable() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

        let transport = SyncTransportDouble()
        transport.enqueuePullError(.serverUnavailable)
        let outcome = await makeSyncEngine(repository: repo, transport: transport).synchronize()

        #expect(outcome.serverUnavailable, "the 5xx state must come out as serverUnavailable")
        #expect(!outcome.offline, "a 5xx must not read as offline")
    }

    // MARK: - S7: nothing is lost either way

    @Test("rows stay dirty whether the failure was offline or a 5xx")
    func rowsStayDirtyEitherWay() async throws {
        for error in [SyncServerError.offline, SyncServerError.serverUnavailable] {
            let repo = try makeSyncRepository()
            let vehicle = makeSyncVehicle()
            try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
            try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

            let transport = SyncTransportDouble()
            transport.enqueuePullError(error)
            _ = await makeSyncEngine(repository: repo, transport: transport).synchronize()

            #expect(try repo.fetchDirtyRows().count == 1,
                    "\(error) leaves the queue dirty - nothing is lost (S7)")
        }
    }
}
