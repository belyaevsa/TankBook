import Foundation
import Testing
@testable import TankbookCore

/// PJ.55 - `Station.favorite` finally has a production writer, and the writer is
/// proven by the feature it feeds, never by the field it flips. The ranking
/// (`StationSuggestion`, PJ.19) reads `favorite` for rung 1; before this row the
/// only writers were the import path (always `false`) and a dozen test seeds, so
/// rung 1 could never fire. These tests set the favourite through the SAME
/// repository write the Garage toggle calls, then assert the LADDER reordered -
/// the field is the mechanism, the order is the feature.
@Suite struct PJ55StationFavoriteTests {

    private let origin = GeoCoordinate(latitude: 59.4378, longitude: 24.7536)
    private let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A station whose location is `deltaDegrees` north of the fixture origin
    /// (~111 m per 0.001 degrees), so a small delta sits inside the 300 m gate
    /// and a larger one outside it.
    private func station(_ name: String, deltaDegrees: Double,
                         favorite: Bool = false, lastUsedAt: Date? = nil,
                         id: UUID = UUID.v7()) -> Station {
        Station(id: id, createdAt: reference, updatedAt: reference,
                deletedAt: nil, name: name, brand: nil,
                location: GeoCoordinate(latitude: origin.latitude + deltaDegrees,
                                        longitude: origin.longitude),
                favorite: favorite,
                defaults: Station.Defaults(fuelKind: nil, fuelGrade: nil),
                lastUsedAt: lastUsedAt)
    }

    /// The winner of the ladder over the repository's LIVE stations - the same
    /// inputs the Confirm sheet hands in.
    private func winner(_ repository: TankbookRepository) throws -> Station? {
        StationSuggestion.propose(in: StationSuggestion.Context(
            stations: try repository.liveStations(),
            locationAuthorised: true,
            currentLocation: origin,
            recentStationIDForVehicle: nil,
            vehicleFuelKinds: [.petrol95]))?.station
    }

    /// The row's oracle: a favourite within 300 m beats a CLOSER non-favourite.
    /// The ranking is a priority ladder, not a nearest-first sort, so setting
    /// the farther station favourite must move it to the top. Asserting the
    /// flag flipped would pass on a writer that never reached the ladder.
    @Test func favouritingAStationPersistsAndRung1OutranksANearerNonFavourite() throws {
        let repo = try makeSyncRepository()
        let nearerNonFavourite = station("Nearer", deltaDegrees: 0.0002,
                                         lastUsedAt: reference)
        let fartherFavourite = station("Farther", deltaDegrees: 0.001)
        try repo.upsertStation(nearerNonFavourite)
        try repo.upsertStation(fartherFavourite)

        // Before: no favourite, so rung 2 picks the nearer last-used station.
        #expect(try winner(repo)?.id == nearerNonFavourite.id,
                "with no favourite the nearer last-used station leads")

        // The user sets the farther one as favourite through the write the
        // Garage toggle calls.
        #expect(try repo.setStationFavorite(id: fartherFavourite.id, true),
                "setting a favourite is a write")

        // It persisted, and the ladder REORDERED.
        let stored = try #require(try repo.station(id: fartherFavourite.id))
        #expect(stored.favorite, "the favourite must be stored, not only in memory")
        #expect(try winner(repo)?.id == fartherFavourite.id,
                "rung 1 must fire: a favourite within 300 m beats the nearer non-favourite")
    }

    /// Reversibility is the other half of hard rule 13: un-favouriting is a real
    /// write and it persists, so the ladder falls back to its lower rungs.
    @Test func unfavouritingPersistsAndTheLadderFallsBack() throws {
        let repo = try makeSyncRepository()
        let nearer = station("Nearer", deltaDegrees: 0.0002, lastUsedAt: reference)
        let farther = station("Farther", deltaDegrees: 0.001, favorite: true)
        try repo.upsertStation(nearer)
        try repo.upsertStation(farther)
        #expect(try winner(repo)?.id == farther.id, "the favourite leads first")

        #expect(try repo.setStationFavorite(id: farther.id, false),
                "clearing a favourite is a write")
        #expect(try repo.station(id: farther.id)?.favorite == false)
        #expect(try winner(repo)?.id == nearer.id,
                "cleared, the ladder falls back to the nearer last-used station")
    }

    /// Hard rule 13: a favourite is never inferred. Using a station many times -
    /// the save stamp writes `lastUsedAt` and `defaults` on every visit - must
    /// not make it a favourite. Only the user says so.
    @Test func useNeverInfersAFavourite() throws {
        let repo = try makeSyncRepository()
        let stationID = UUID.v7()
        try repo.upsertStation(station("Frequent", deltaDegrees: 0.001, id: stationID))

        for visit in 0..<5 {
            try repo.stampStation(id: stationID, fuelKind: .petrol95, fuelGrade: nil,
                                  locationFix: nil,
                                  at: reference.addingTimeInterval(Double(visit) * 86_400))
        }
        #expect(try repo.station(id: stationID)?.favorite == false,
                "many visits must not infer a favourite")

        // The user's explicit choice is the only writer, and a later stamp
        // preserves it (the stamp never touches `favorite`).
        try repo.setStationFavorite(id: stationID, true)
        try repo.stampStation(id: stationID, fuelKind: .petrol98, fuelGrade: nil,
                              locationFix: nil, at: reference.addingTimeInterval(10 * 86_400))
        #expect(try repo.station(id: stationID)?.favorite == true,
                "a save stamp must never overwrite the user's favourite")
    }
}

/// PJ.55 - the favourite is an ordinary `.dirty` station edit (record-level LWW,
/// docs/SCHEMA.md -> Station). It must survive a sync round trip, and a pull of
/// the device's own pushed record must not re-dirty or reset it (hard rule 13:
/// once the user sets a value, it is theirs; the RV.35/RV.136 echo guard).
@Suite struct PJ55StationFavoriteSyncTests {

    private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func makeStation(id: UUID) -> Station {
        Station(id: id, createdAt: t0, updatedAt: t0, deletedAt: nil,
                name: "Prima Auto", brand: nil, location: nil, favorite: false,
                defaults: Station.Defaults(fuelKind: nil, fuelGrade: nil),
                lastUsedAt: nil)
    }

    private func decodeStation(_ payload: JSONValue) throws -> Station {
        try PayloadCodec.decode(
            PayloadEnvelope(entityType: Station.entityType,
                            schemaVersion: PayloadCodec.currentSchemaVersion,
                            payload: payload),
            as: Station.self).entity
    }

    @Test func theFavouriteSurvivesARoundTripAndAPullNeverResetsIt() async throws {
        let stationID = UUID.v7()
        let repoA = try makeSyncRepository()
        let repoB = try makeSyncRepository()
        for repo in [repoA, repoB] {
            try repo.upsertStation(makeStation(id: stationID), syncState: .synced(scn: 1))
        }

        // A sets the favourite: one ordinary dirty edit.
        #expect(try repoA.setStationFavorite(id: stationID, true))
        let transportA = SyncTransportDouble()
        let outcomeA = await makeSyncEngine(repository: repoA, transport: transportA).synchronize()
        #expect(outcomeA.pushed == 1, "the favourite is one ordinary dirty edit")
        let pushes = transportA.recordedPushBatches.flatMap { $0 }
        guard pushes.count == 1, pushes.first?.entityType == Station.entityType else {
            Issue.record("the push must carry exactly the station edit")
            return
        }
        let pushed = try decodeStation(pushes[0].payload)
        #expect(pushed.favorite, "the favourite must be on the wire")

        // B pulls exactly that stream and converges on the favourite.
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
        #expect(try repoB.station(id: stationID)?.favorite == true,
                "the user's favourite converges to B")
        guard case .synced = try repoB.localSyncRecord(id: stationID,
                                                       entityType: Station.entityType)?.syncState else {
            Issue.record("the pulled station must settle .synced on B")
            return
        }

        // A pulls its own pushed record back: the echo must not reset the
        // favourite nor re-dirty the row (hard rule 13's permanence).
        let echoA = SyncTransportDouble()
        echoA.enqueuePull(SyncPullResponse(records: records, nextSince: 12,
                                           more: false, schemaPolicy: policy))
        _ = await makeSyncEngine(repository: repoA, transport: echoA).synchronize()
        #expect(try repoA.station(id: stationID)?.favorite == true,
                "a pull must not overwrite a user-set favourite")
        let settled = await makeSyncEngine(repository: repoA, transport: transportA).synchronize()
        #expect(settled.pushed == 0, "the favourite settles synced, never re-dirtied")
        #expect(try repoA.fetchDirtyRows().isEmpty)
    }
}
