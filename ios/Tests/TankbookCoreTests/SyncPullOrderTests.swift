import Foundation
import Testing
@testable import TankbookCore

// A pull page is ordered by scn, and scn is per record: a car edited after its
// entries were logged carries a HIGHER scn than every entry, so a device
// pulling the account from zero (a fresh install, a restore) receives the
// entries before the car they reference. The entry tables carry a foreign key
// to the vehicle, so the first entry must not wedge the whole pull - the cursor
// would never advance and every later cycle would replay the same page.

private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)

@Test func pullAppliesEntryWhoseVehicleArrivesLaterOnTheSamePage() async throws {
    let repo = try makeSyncRepository()
    let transport = SyncTransportDouble()
    let vehicle = makeSyncVehicle()
    let fillUp = makeSyncFillUp(vehicleId: vehicle.id)
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(fillUp, scn: 1), makePullRecord(vehicle, scn: 2)],
        nextSince: 2, more: false, schemaPolicy: policy))
    let cursor = InMemorySyncCursorStore()
    let engine = makeSyncEngine(repository: repo, transport: transport, cursor: cursor)

    let outcome = await engine.synchronize()

    #expect(!outcome.serverUnavailable)
    #expect(outcome.pulled == 2)
    #expect(try repo.rowCount(in: TankbookSchema.vehicle) == 1)
    #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 1)
    #expect(try cursor.load() == 2)
}

@Test func pullAppliesEntryWhoseVehicleArrivesOnALaterPage() async throws {
    let repo = try makeSyncRepository()
    let transport = SyncTransportDouble()
    let vehicle = makeSyncVehicle()
    let fillUp = makeSyncFillUp(vehicleId: vehicle.id)
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(fillUp, scn: 1)],
        nextSince: 1, more: true, schemaPolicy: policy))
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(vehicle, scn: 2)],
        nextSince: 2, more: false, schemaPolicy: policy))
    let cursor = InMemorySyncCursorStore()
    let engine = makeSyncEngine(repository: repo, transport: transport, cursor: cursor, pullPageLimit: 1)

    let outcome = await engine.synchronize()

    #expect(!outcome.serverUnavailable)
    #expect(outcome.pulled == 2)
    #expect(try repo.rowCount(in: TankbookSchema.vehicle) == 1)
    #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 1)
    #expect(try cursor.load() == 2)
}

@Test func pullMovesPastAnEntryWhoseVehicleIsOnNoPageAndSaysSo() async throws {
    let repo = try makeSyncRepository()
    let transport = SyncTransportDouble()
    let orphan = makeSyncFillUp(vehicleId: UUID.v7())
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(orphan, scn: 1)],
        nextSince: 1, more: false, schemaPolicy: policy))
    let cursor = InMemorySyncCursorStore()
    let sink = InMemorySink()
    let log = TankbookLog(sink: sink, context: { LogContext(appVersion: "test") })
    let engine = SyncEngine(repository: repo, transport: transport, cursorStore: cursor, log: log)

    let outcome = await engine.synchronize()

    #expect(!outcome.serverUnavailable)
    #expect(outcome.pulled == 0)
    #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 0)
    #expect(try cursor.load() == 1)
    let orphaned = sink.all().filter { $0.event == "sync.orphaned" }
    #expect(orphaned.count == 1)
    #expect(sink.rendered().contains { $0.contains("sync.orphaned") && $0.contains("fillUp:\(orphan.id.uuidString)") })
}

@Test func pullFailureNamesItsClassInTheLog() async throws {
    let repo = try makeSyncRepository()
    let transport = SyncTransportDouble()
    transport.enqueuePullError(.invalidResponse)
    let sink = InMemorySink()
    let log = TankbookLog(sink: sink, context: { LogContext(appVersion: "test") })
    let engine = SyncEngine(repository: repo, transport: transport, cursorStore: InMemorySyncCursorStore(), log: log)

    let outcome = await engine.synchronize()

    #expect(outcome.serverUnavailable)
    #expect(sink.rendered().contains { $0.contains("sync.pull.failed") && $0.contains("error=SyncServerError.invalidResponse") })
}
