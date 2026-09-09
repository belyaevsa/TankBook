import Foundation
import Testing
@testable import TankbookCore

/// RV.150 - the station stamp is an ordinary `.dirty` station edit: two devices
/// converge on the same Station fields after a sync round, and a save that
/// changes nothing produces no push. Station is a record-level LWW entity (only
/// `Vehicle` merges field-level, SYNC.md S9), so the convergence question is
/// exactly the RV.14/RV.35 one: a pushed-then-pulled-back station must settle
/// `.synced` and never re-dirty (RecordMerge.recordsEqual compares decoded
/// `Station` values, RecordMerge.swift:150).
@Suite struct RV150StationSyncTests {

    private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private let fix = GeoCoordinate(latitude: 59.4378, longitude: 24.7536)

    private func makeStation(id: UUID = UUID.v7(),
                             lastUsedAt: Date? = nil,
                             fuelKind: FuelKind = .petrol95,
                             location: GeoCoordinate? = nil) -> Station {
        Station(id: id, createdAt: t0, updatedAt: t0, deletedAt: nil,
                name: "Prima Auto", brand: "Prima Group", location: location,
                favorite: false,
                defaults: Station.Defaults(fuelKind: fuelKind, fuelGrade: nil),
                lastUsedAt: lastUsedAt)
    }

    private func decodeStation(_ payload: JSONValue) throws -> Station {
        try PayloadCodec.decode(
            PayloadEnvelope(entityType: Station.entityType,
                            schemaVersion: PayloadCodec.currentSchemaVersion,
                            payload: payload),
            as: Station.self).entity
    }

    /// The RV.150 save's effect on the station, driven exactly as the app save
    /// drives it: stamp the live row.
    @Test func twoDevicesConvergeOnTheStampedStationAndANoOpSavePushesNothing() async throws {
        let stationID = UUID.v7()
        let stampTime = t0.addingTimeInterval(3 * 86_400)

        let repoA = try makeSyncRepository()
        let repoB = try makeSyncRepository()
        for repo in [repoA, repoB] {
            // The by-hand-user shape that hides this defect (RV.150's vacuous
            // trap): the seed station carries NO location and NO lastUsedAt.
            try repo.upsertStation(makeStation(id: stationID), syncState: .synced(scn: 1))
        }

        // Device A saves a fill-up at the station: the stamp writes lastUsedAt,
        // the bought kind and the adopted fix.
        let stampA = try repoA.stampStation(id: stationID, fuelKind: .petrol98,
                                            fuelGrade: nil, locationFix: fix,
                                            at: stampTime)
        #expect(stampA, "the by-hand station must be stamped by the save")

        let transportA = SyncTransportDouble()
        let outcomeA = await makeSyncEngine(repository: repoA, transport: transportA).synchronize()
        #expect(outcomeA.pushed == 1, "the stamped station is one ordinary dirty edit")
        let pushes = transportA.recordedPushBatches.flatMap { $0 }
        guard pushes.count == 1, pushes.first?.entityType == Station.entityType else {
            Issue.record("the push must carry exactly the station edit")
            return
        }
        let pushed = try decodeStation(pushes[0].payload)
        #expect(pushed.lastUsedAt == stampTime)
        #expect(pushed.defaults.fuelKind == .petrol98)
        #expect(pushed.location == fix)

        // The server stores the push; B pulls exactly that stream.
        let records = pushes.enumerated().map { index, change in
            SyncPullRecord(id: change.id, entityType: change.entityType,
                           schemaVersion: change.schemaVersion,
                           scn: Int64(10 + index), payload: change.payload,
                           clientUpdatedAt: change.clientUpdatedAt, deleted: change.deleted,
                           originDeviceName: "device A")
        }
        let transportB = SyncTransportDouble()
        transportB.enqueuePull(SyncPullResponse(records: records, nextSince: 12,
                                                more: false, schemaPolicy: policy))
        let outcomeB = await makeSyncEngine(repository: repoB, transport: transportB).synchronize()
        #expect(outcomeB.pushed == 0, "B has no local edits to push")

        let stationB = try repoB.station(id: stationID)
        #expect(stationB?.lastUsedAt == stampTime, "the stamp's lastUsedAt converges to B")
        #expect(stationB?.defaults.fuelKind == .petrol98, "the bought kind converges to B")
        #expect(stationB?.location == fix, "the adopted coordinate converges to B")
        guard case .synced = try repoB.localSyncRecord(id: stationID,
                                                       entityType: Station.entityType)?.syncState else {
            Issue.record("the pulled station must settle .synced on B")
            return
        }

        // B makes a save that changes nothing about the station (its stamp is
        // already the current row): nothing is written, nothing is pushed.
        let noOp = try repoB.stampStation(id: stationID, fuelKind: .petrol98,
                                          fuelGrade: nil, locationFix: fix,
                                          at: stampTime)
        #expect(!noOp, "a save that changes nothing writes nothing ([RV.136])")
        #expect(try repoB.fetchDirtyRows().isEmpty)
        let secondB = await makeSyncEngine(repository: repoB, transport: transportB).synchronize()
        #expect(secondB.pushed == 0 && transportB.recordedPushBatches.isEmpty,
                "a no-op save must not reach the server")

        // And the echo guard holds on A: a further sync on an idle account (the
        // pull returns A's own station back) pushes nothing - the station is
        // never re-dirtied by its own echo.
        let echoA = SyncTransportDouble()
        echoA.enqueuePull(SyncPullResponse(
            records: records, nextSince: 12, more: false, schemaPolicy: policy))
        _ = await makeSyncEngine(repository: repoA, transport: echoA).synchronize()
        let settled = await makeSyncEngine(repository: repoA, transport: transportA).synchronize()
        #expect(settled.pushed == 0, "an idle account pushes nothing after convergence")
        #expect(try repoA.fetchDirtyRows().isEmpty,
                "the station settles synced, never dirty (no echo loop)")
    }
}
