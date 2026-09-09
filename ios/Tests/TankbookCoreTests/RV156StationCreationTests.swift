import Foundation
import Testing
@testable import TankbookCore

/// RV.156 - the typed door into the station set (docs/JOURNEYS.md -> J4).
/// Before it, `upsertStation` had no non-seed caller in the app, so a user who
/// types entries had an empty station set forever: PJ.19's ranking had nothing
/// to rank and RV.150's stamp had nothing to stamp. Creation goes through the
/// SAME deterministic name-to-Station rule the import path uses
/// (`ImportStationResolver.station(for:)`), never a random UUID, so two devices
/// typing the same name mint the same id and converge instead of duplicating
/// (RV.115's merge problem is deliberately not forked). These tests pin the one
/// minting rule, the blank-name decision, the ordinary `.dirty` write + sync,
/// and the composition with RV.150's save stamp.
@Suite struct RV156StationCreationTests {

    private static let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)

    private func makeRepository() throws -> TankbookRepository {
        try TankbookRepository(database: TankbookDatabase.inMemory())
    }

    // MARK: - One minting rule, deterministic across devices

    @Test func theSameNameTypedTwiceYieldsOneStationWithTheDeterministicId() throws {
        let repo = try makeRepository()
        let t0 = Self.reference

        // " Shell " trims to the same name: the second call must resolve the
        // first record, never mint a second one.
        let first = try repo.createStation(named: "Shell", at: t0)
        #expect(first != nil, "a named station must be creatable")
        let again = try repo.createStation(named: " Shell ", at: t0.addingTimeInterval(60))
        #expect(again?.id == first?.id,
                "the same name typed twice must resolve to the same station")

        let live = try repo.liveStations()
        #expect(live.count == 1, "one station on file, never two")
        #expect(live.first?.name == "Shell", "the typed name is trimmed")
        #expect(try repo.fetchDirtyRows().count == 1,
                "only the first call writes; the match writes nothing")

        // The id is the import resolver's deterministic digest of the name -
        // the property that makes two devices typing the same name converge.
        let deterministic = ImportStationResolver.station(for: "Shell",
                                                          existing: [], now: t0)
        #expect(first?.id == deterministic.id,
                "creation must go through the shared deterministic minting rule")
    }

    @Test func twoDevicesTypingTheSameNameMintTheSameId() throws {
        // No shared state: each device resolves against its own empty set, and
        // the ids still agree - the convergence is a property of the rule.
        let repoA = try makeRepository()
        let repoB = try makeRepository()
        let stationA = try repoA.createStation(named: "Газпром", at: Self.reference)
        let stationB = try repoB.createStation(named: "Газпром", at: Self.reference)
        #expect(stationA != nil && stationB != nil)
        #expect(stationA?.id == stationB?.id,
                "independent devices must mint the same station for the same name")
    }

    @Test func aBlankOrWhitespaceOnlyNameCreatesNothing() throws {
        let repo = try makeRepository()
        #expect(try repo.createStation(named: "   \n ", at: Self.reference) == nil,
                "a station's row and Log title live on its name - blank is a cancel")
        #expect(try repo.createStation(named: "", at: Self.reference) == nil)
        #expect(try repo.liveStations().isEmpty)
        #expect(try repo.fetchDirtyRows().isEmpty)
    }

    // MARK: - An ordinary .dirty write that syncs like any other entity

    @Test func aCreatedStationIsADirtyWriteThatPushesAndConverges() async throws {
        let t0 = Self.reference
        let repoA = try makeSyncRepository()
        guard let station = try repoA.createStation(named: "Shell", at: t0) else {
            Issue.record("the named station must be creatable")
            return
        }
        guard case .dirty = try repoA.localSyncRecord(id: station.id,
                                                      entityType: Station.entityType)?.syncState else {
            Issue.record("the created station must be written .dirty")
            return
        }

        // One sync round pushes it as an ordinary station edit.
        let transportA = SyncTransportDouble()
        let outcomeA = await makeSyncEngine(repository: repoA,
                                            transport: transportA).synchronize()
        #expect(outcomeA.pushed == 1, "the created station is one ordinary dirty edit")
        let pushes = transportA.recordedPushBatches.flatMap { $0 }
        guard pushes.count == 1, pushes.first?.entityType == Station.entityType else {
            Issue.record("the push must carry exactly the created station")
            return
        }
        let pushed = try decodeStation(pushes[0].payload)
        #expect(pushed.id == station.id)
        #expect(pushed.name == "Shell")

        // A second device pulls it and settles .synced - record-level LWW,
        // exactly like any stamped station (RV.150).
        let records = pushes.enumerated().map { index, change in
            SyncPullRecord(id: change.id, entityType: change.entityType,
                           schemaVersion: change.schemaVersion,
                           scn: Int64(10 + index), payload: change.payload,
                           clientUpdatedAt: change.clientUpdatedAt, deleted: change.deleted,
                           originDeviceName: "device A")
        }
        let repoB = try makeSyncRepository()
        let transportB = SyncTransportDouble()
        transportB.enqueuePull(SyncPullResponse(records: records, nextSince: 12,
                                                more: false, schemaPolicy: policy))
        _ = await makeSyncEngine(repository: repoB, transport: transportB).synchronize()
        #expect(try repoB.liveStations().map(\.name) == ["Shell"],
                "the created station converges to the second device")
        guard case .synced = try repoB.localSyncRecord(id: station.id,
                                                       entityType: Station.entityType)?.syncState else {
            Issue.record("the pulled station must settle .synced")
            return
        }
    }

    // MARK: - Composition with RV.150's save stamp

    @Test func theR150StampFillsLastUsedAtAndDefaultsOnACreatedStationAtItsNextSave() throws {
        let repo = try makeRepository()
        let mint = Self.reference
        let save = mint.addingTimeInterval(2 * 86_400)
        guard let created = try repo.createStation(named: "Prima Auto", at: mint) else {
            Issue.record("the named station must be creatable")
            return
        }
        #expect(created.favorite == false)
        #expect(created.defaults.fuelKind == nil,
                "creation asks for a name only - defaults wait for the first save")

        // The next save at the station stamps what was actually bought.
        #expect(try repo.stampStation(id: created.id, fuelKind: .petrol98,
                                      fuelGrade: nil, locationFix: nil, at: save))
        let stamped = try repo.station(id: created.id)
        #expect(stamped?.lastUsedAt == save,
                "the save stamps lastUsedAt on the created station")
        #expect(stamped?.defaults.fuelKind == .petrol98,
                "the save records the bought defaults on the created station")
    }

    private func decodeStation(_ payload: JSONValue) throws -> Station {
        try PayloadCodec.decode(
            PayloadEnvelope(entityType: Station.entityType,
                            schemaVersion: PayloadCodec.currentSchemaVersion,
                            payload: payload),
            as: Station.self).entity
    }
}

/// The wiring pins (the RV.150 logging-gate text-scan pattern): the L1 tests
/// drive the repository directly, so a scan guards that the APP paths and the
/// repository both route through the ONE shared minting rule - a regression to
/// a random UUID in the row would pass every repository test and still break
/// cross-device convergence.
@Suite struct RV156StationCreationWiringTests {

    private static var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
    }

    private func read(_ relative: String) throws -> String {
        try String(contentsOf: Self.iosRoot.appendingPathComponent(relative),
                   encoding: .utf8)
    }

    @Test func theRepositoryCreateRoutesThroughTheSharedResolver() throws {
        let contents = try read("Sources/TankbookCore/Persistence/Repository+StationCreate.swift")
        #expect(contents.contains("ImportStationResolver.station(for:"),
                "the repository must mint through the shared deterministic resolver")
        #expect(!contents.contains("UUID("),
                "creation must never fall back to a random UUID")
    }

    @Test func theEntryRowAndGarageListCreateThroughTheRepository() throws {
        let row = try read("App/Sources/ConfirmManual/ManualFillUpStationRow.swift")
        let list = try read("App/Sources/StationSettings/StationsListView.swift")
        for file in [row, list] {
            #expect(file.contains("createStation(named:"),
                    "every station-creation surface must call repository.createStation")
            #expect(!file.contains("Station(id: UUID"),
                    "no surface may mint a station directly")
        }
    }
}
