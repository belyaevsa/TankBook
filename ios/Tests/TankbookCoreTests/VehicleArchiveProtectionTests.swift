import Foundation
import Testing
@testable import TankbookCore

// P5.5a - the archive's protection and evolution surfaces: the optional
// passphrase (the manifest must still open without it), the v1 -> v2 additive
// migrator fixture, the atomic-write discipline, and the account-scope refusal.
// Round-trip/scope tests live in VehicleArchiveTests.swift.

@Test func protectedExportRoundTripsAndManifestOpensWithoutThePassphrase() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-protected")
    let passphrase = "correct horse battery staple"
    try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo, to: archiveDir,
                                blobSourceDir: seed.blobRoot, passphrase: passphrase)

    // The manifest is always readable - before the passphrase is even known.
    let manifest = try VehicleArchiveReader.readManifest(at: archiveDir)
    #expect(manifest.passphraseProtected)
    #expect(manifest.scope == .vehicle)

    // data.json on disk is not JSON - it is a sealed box.
    let dataURL = archiveDir.appendingPathComponent(ArchiveDataJSON.fileName)
    let raw = try Data(contentsOf: dataURL)
    #expect((try? JSONValue.parse(raw)) == nil, "a protected data.json must not parse as JSON")

    // Without the passphrase: refused, and only because it is required.
    let targetNoKey = try ArchiveTest.makeRepo()
    let blobStoreDirNoKey = try ArchiveTest.makeTempDir("blobstore-protected-nokey")
    do {
        _ = try ArchiveTest.importArchive(archiveDir, into: targetNoKey, blobStoreDir: blobStoreDirNoKey)
        Issue.record("a protected archive without a passphrase must be refused")
    } catch let error as VehicleArchiveError {
        #expect(error == .passphraseRequired)
    }
    try ArchiveTest.assertRepositoryEmpty(targetNoKey, blobStoreDir: blobStoreDirNoKey)

    // A wrong passphrase fails authentication.
    let targetWrong = try ArchiveTest.makeRepo()
    let blobStoreDirWrong = try ArchiveTest.makeTempDir("blobstore-protected-wrong")
    do {
        _ = try ArchiveTest.importArchive(archiveDir, into: targetWrong, blobStoreDir: blobStoreDirWrong,
                              passphrase: "not the passphrase")
        Issue.record("a wrong passphrase must fail")
    } catch let error as VehicleArchiveError {
        #expect(error == .wrongPassphrase)
    }
    try ArchiveTest.assertRepositoryEmpty(targetWrong, blobStoreDir: blobStoreDirWrong)

    // The correct passphrase round-trips - text AND blob bytes.
    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-protected")
    let result = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir,
                                   passphrase: passphrase)
    #expect(result.vehicleCount == 1)
    #expect(try target.liveVehicles().map(\.id) == [seed.volvo])
    let stored = try FileBackedBlobStore(directory: blobStoreDir).data(for: seed.shaLive)
    #expect(stored == Data("JPEG-CONTENT-LIVE".utf8))
}

@Test func unprotectedExportStillOpens() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-unprotected")
    let exported = try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo,
                                              to: archiveDir, blobSourceDir: seed.blobRoot)

    #expect(exported.passphraseProtected == false)
    let manifest = try VehicleArchiveReader.readManifest(at: archiveDir)
    #expect(manifest.passphraseProtected == false)

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-unprotected")
    let result = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)
    #expect(result.vehicleCount == 1)
    #expect(try target.liveVehicles().map(\.id) == [seed.volvo])
}

// MARK: - Test 8: v1 -> v2 migrator fixture (additive evolution)

/// The v1 -> v2 fixture migrator: additive evolution adds one optional field to
/// every fillUp payload and bumps the entries' envelope version. Nothing is
/// removed or rewritten - the shape of additive change docs/SCHEMA.md requires.
private struct CaptureDeviceV2Migrator: ArchiveMigrator {
    var fromVersion: Int { 1 }

    func upcast(_ data: JSONValue) throws -> JSONValue {
        guard var object = data.objectValue else {
            throw VehicleArchiveError.malformedData("migrator received a non-object data.json")
        }
        if case .array(let entries)? = object["entries"] {
            object["entries"] = .array(entries.map { entry in
                guard var envelope = entry.objectValue else { return entry }
                if case .object(var payload)? = envelope["payload"],
                   envelope["entityType"]?.stringValue == FillUp.entityType {
                    payload["captureDeviceId"] = .string("fixture-device")
                    envelope["payload"] = .object(payload)
                }
                envelope["schemaVersion"] = .number("2")
                return .object(envelope)
            })
        }
        return .object(object)
    }
}

/// The v2 policy: current version 2, the fixture migrator from v1, and - because
/// v2 is additive over v1 - the bundled v1 schemas still accept every v2 payload
/// (their `additionalProperties` is true, docs/SYNC.md -> payload contract).
private func v2Policy() -> ArchiveSchemaPolicy {
    ArchiveSchemaPolicy(
        currentVersion: 2,
        migrators: [1: CaptureDeviceV2Migrator()],
        schemaLoader: { _, entityType in
            ArchiveSchemaPolicy.bundledSchema(version: 1, entityType: entityType)
        })
}

@Test func v1ArchiveUpgradesThroughTheMigratorAndRoundTrips() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-v1")

    // Written by a v1 app (the default policy).
    let exported = try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo,
                                              to: archiveDir, blobSourceDir: seed.blobRoot)
    #expect(exported.schemaVersion == 1)

    // Read by a v2 app: the migrator runs, the archive imports.
    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-v2")
    let result = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir,
                                   policy: v2Policy())
    #expect(result.vehicleCount == 1)
    #expect(try target.liveFillUps(forVehicle: seed.volvo).map(\.id) == [seed.fillLive])

    // A v2 app re-exports the imported car at v2.
    let reExportDir = try ArchiveTest.makeTempDir("archive-v2-re-export")
    let reblobDir = try ArchiveTest.makeTempDir("reblobs")
    let reWriter = VehicleArchiveWriter(repository: target,
                                        blobSource: FileBackedBlobSource(directory: reblobDir),
                                        policy: v2Policy())
    let reExported = try reWriter.writeArchive(
        vehicleID: seed.volvo, to: reExportDir, appVersion: "10.0.0",
        kdfIterations: ArchiveCrypto.testIterations, now: ArchiveTest.time0)
    #expect(reExported.schemaVersion == 2)
    #expect(reExported.entryCount == 5)
}

@Test func v2PolicyWithoutTheMigratorRefusesAV1Archive() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-no-migrator")
    _ = try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo, to: archiveDir, blobSourceDir: seed.blobRoot)

    // currentVersion 2 but NO migrator registered: the climb from v1 cannot
    // happen, and the archive must refuse rather than guess.
    let policy = ArchiveSchemaPolicy(
        currentVersion: 2,
        migrators: [:],
        schemaLoader: { _, _ in nil })
    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-no-migrator")
    do {
        _ = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir, policy: policy)
        Issue.record("a v1 archive with no registered migrator must be refused")
    } catch let error as VehicleArchiveError {
        if case .underlying = error {
            // expected: no migrator registered from archive schema v1
        } else {
            Issue.record("expected underlying(missing migrator), got \(error)")
        }
    }
    try ArchiveTest.assertRepositoryEmpty(target, blobStoreDir: blobStoreDir)
}

@Test func aNewerArchiveRefusesOnAnOlderReader() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-too-new")
    _ = try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo, to: archiveDir,
                                    blobSourceDir: seed.blobRoot, policy: v2Policy())

    // A v1 app (the default policy, currentVersion 1) reads the v2 archive.
    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-too-new")
    do {
        _ = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)
        Issue.record("an archive from a newer app must be refused, not guessed at")
    } catch let error as VehicleArchiveError {
        #expect(error == .unsupportedSchemaVersion(2))
    }
    try ArchiveTest.assertRepositoryEmpty(target, blobStoreDir: blobStoreDir)
}

// MARK: - Test 9: atomic write - no .tmp residue, final files parse

@Test func writerLeavesNoTemporaryFilesAndEverythingParses() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-atomic")
    try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo, to: archiveDir, blobSourceDir: seed.blobRoot)

    // Recursively: no `.tmp-` residue anywhere in the archive.
    let enumerator = FileManager.default.enumerator(at: archiveDir, includingPropertiesForKeys: nil)
    var residue: [String] = []
    while let url = enumerator?.nextObject() as? URL {
        if url.lastPathComponent.contains(".tmp-") { residue.append(url.path) }
    }
    #expect(residue.isEmpty, "no temp files may survive: \(residue)")

    // The manifest parses; data.json parses.
    let manifest = try VehicleArchiveReader.readManifest(at: archiveDir)
    #expect(manifest.vehicleCount == 1)
    #expect(manifest.entryCount == 5)
    let dataURL = archiveDir.appendingPathComponent(ArchiveDataJSON.fileName)
    let dataTree = try JSONValue.parse(try Data(contentsOf: dataURL))
    let data = try ArchiveDataJSON.parse(dataTree)
    #expect(data.entryCount == 5)
    #expect(data.vehicles.count == 1)

    // Every archived blob parses as raw bytes and the blob store is clean.
    let blobDir = ArchiveFileIO.attachmentsDirectory(in: archiveDir)
    let blobFiles = try FileManager.default.contentsOfDirectory(at: blobDir, includingPropertiesForKeys: nil)
    #expect(blobFiles.count == 3)
    for blob in blobFiles {
        #expect(!blob.lastPathComponent.contains(".tmp-"))
        let bytes = try Data(contentsOf: blob)
        #expect(BlobHash.sha256(bytes) == blob.lastPathComponent)
    }
}

// MARK: - Account-scope archives are refused by the per-car importer

@Test func accountScopeArchiveIsRefusedByThePerCarImporter() throws {
    let archiveDir = try ArchiveTest.makeTempDir("archive-account-scope")
    let manifest = VehicleArchiveManifest(
        schemaVersion: 1, scope: .account, vehicleIds: [UUID.v7()],
        exportedAt: ArchiveTest.time0, appVersion: "9.9.9", vehicleCount: 2, entryCount: 0)
    try ArchiveFileIO.atomicWriteJSON(manifest.jsonValue(),
                                      to: archiveDir.appendingPathComponent(VehicleArchiveManifest.fileName))
    let data = JSONValue.object([
        "vehicles": .array([]), "entries": .array([]),
        "reminders": .array([]), "stations": .array([]), "tariffs": .array([])
    ])
    try ArchiveFileIO.atomicWriteJSON(data,
                                      to: archiveDir.appendingPathComponent(ArchiveDataJSON.fileName))

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-account")
    do {
        _ = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)
        Issue.record("an account-scope archive must not be imported as a car")
    } catch let error as VehicleArchiveError {
        #expect(error == .scopeMismatch(expected: .singleCar, declared: .account))
    }
    try ArchiveTest.assertRepositoryEmpty(target, blobStoreDir: blobStoreDir)
}

// MARK: - The manifest read path and counts are informational, not load-bearing

@Test func manifestIsReadableWithoutDataJSONPresent() throws {
    let archiveDir = try ArchiveTest.makeTempDir("archive-manifest-only")
    let manifest = VehicleArchiveManifest(
        schemaVersion: 1, scope: .vehicle, vehicleIds: [UUID.v7()],
        exportedAt: ArchiveTest.time0, appVersion: "9.9.9", vehicleCount: 1, entryCount: 0)
    try ArchiveFileIO.atomicWriteJSON(manifest.jsonValue(),
                                      to: archiveDir.appendingPathComponent(VehicleArchiveManifest.fileName))

    let read = try VehicleArchiveReader.readManifest(at: archiveDir)
    #expect(read.scope == .vehicle)
    #expect(read.schemaVersion == 1)
    #expect(read.vehicleIds.count == 1)
    #expect(read.exportedAt == ArchiveTest.time0)
    #expect(read.appVersion == "9.9.9")

    let missing = try ArchiveTest.makeTempDir("archive-empty")
    do {
        _ = try VehicleArchiveReader.readManifest(at: missing)
        Issue.record("a directory without a manifest must be reported as missing")
    } catch let error as VehicleArchiveError {
        #expect(error == .missingManifest)
    }
}

// MARK: - The bundled schemas stay byte-identical to the generated source

/// The reader validates every payload against the JSON Schemas BUNDLED with the
/// app (`Schemas/v1/` in the package). That bundled copy must never drift from
/// `docs/schemas/v1` (the generated source of truth the PayloadContractTests
/// check the codec against) - a silent drift would make the reader validate a
/// different contract than the sync pipeline uses.
@Test func bundledSchemasStayByteIdenticalToTheGeneratedSource() throws {
    let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent() // TankbookCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root
    let generatedDir = repoRoot.appendingPathComponent("docs/schemas/v1")

    let entityTypes = ["vehicle", "fillUp", "chargeSession", "serviceRecord", "expense",
                       "reminder", "station", "tariff", "tireSet", "attachment", "preferences"]
    for entityType in entityTypes {
        let bundled = try Data(contentsOf: try #require(
            Bundle.module.url(forResource: entityType, withExtension: "schema.json",
                              subdirectory: "Schemas/v1"),
            "missing bundled schema for \(entityType)"))
        let generated = try Data(contentsOf: generatedDir.appendingPathComponent("\(entityType).schema.json"))
        #expect(bundled == generated,
                "Schemas/v1/\(entityType).schema.json drifted from docs/schemas/v1")
    }
}
