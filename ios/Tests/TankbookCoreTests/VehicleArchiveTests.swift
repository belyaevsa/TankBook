import Foundation
import Testing
@testable import TankbookCore

// P5.5a - the per-car backup archive (docs/SCHEMA.md -> "Backup format" and
// "Scope: a user-held export is PER CAR"). Test scaffolding lives in
// VehicleArchiveTestSupport.swift; the passphrase/evolution/atomic-write tests
// live in VehicleArchiveProtectionTests.swift.
//
// The load-bearing test is the one for scope: a reader must branch on
// `manifest.scope`, NEVER on `vehicleCount == 1` - a one-car user's full
// account and a one-car export are indistinguishable by count. Every test uses
// REAL temp directories for the archive, the blob source and the blob store:
// the atomic write and the content-addressed bytes are part of what is under
// test, not something to mock away.

// MARK: - Test 1: tombstones survive the round-trip

@Test func roundTripCarriesTombstones() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-tombstones")
    let exported = try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo,
                                              to: archiveDir, blobSourceDir: seed.blobRoot)

    #expect(exported.scope == .vehicle)

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-tombstones")
    let result = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)

    #expect(result.vehicleCount == 1)
    #expect(result.entryCount == 5)   // 2 fills + 1 charge + 1 service + 1 expense, tombstones included

    // The tombstoned fill-up is present AND still tombstoned - a tombstone that
    // does not survive is a deletion that comes back (hard rule 8).
    let fills = try target.fillUpsIncludingDeleted(forVehicle: seed.volvo)
    #expect(fills.map(\.id).contains(seed.fillDeleted))
    #expect(try target.liveFillUps(forVehicle: seed.volvo).map(\.id) == [seed.fillLive])
    let deletedFill = fills.first { $0.id == seed.fillDeleted }!
    #expect(deletedFill.deletedAt != nil)
    #expect(deletedFill.deletedAt == ArchiveTest.time2)

    // Same for the tombstoned reminder.
    let reminders = try target.remindersIncludingDeleted(forVehicle: seed.volvo)
    #expect(reminders.map(\.id).contains(seed.reminderDeleted))
    #expect(reminders.first { $0.id == seed.reminderDeleted }!.deletedAt != nil)
    #expect(try target.liveReminders(forVehicle: seed.volvo).map(\.id) == [seed.reminderLive])

    // And the tombstoned station/attachment referenced by a tombstoned entry.
    let deletedStation = try target.stationsIncludingDeleted().first { $0.id == seed.stationDeleted }
    #expect(deletedStation != nil)
    #expect(deletedStation?.deletedAt != nil)
    let deletedAttachment = try target.attachmentsIncludingDeleted().first { $0.id == seed.attachmentDeleted }
    #expect(deletedAttachment != nil)
    #expect(deletedAttachment?.deletedAt != nil)
}

// MARK: - Test 2: attachments carry bytes and their sha256, not just references

@Test func roundTripCarriesAttachmentBytesAndTheirHash() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-attachments")
    try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo, to: archiveDir, blobSourceDir: seed.blobRoot)

    // The blob is physically in the archive, addressed by its content hash.
    let archiveBlobURL = ArchiveFileIO.blobURL(sha256: seed.shaLive, in: archiveDir)
    #expect(FileManager.default.fileExists(atPath: archiveBlobURL.path),
            "the archive must carry the attachment bytes, not just the reference")
    let archivedBytes = try Data(contentsOf: archiveBlobURL)
    #expect(BlobHash.sha256(archivedBytes) == seed.shaLive)
    #expect(archivedBytes == Data("JPEG-CONTENT-LIVE".utf8))

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-attachments")
    _ = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)

    // The byte-addressed store returns the exact bytes - a reference alone
    // would leave this nil.
    let stored = try FileBackedBlobStore(directory: blobStoreDir).data(for: seed.shaLive)
    #expect(stored == Data("JPEG-CONTENT-LIVE".utf8))

    // The attachment record carries the same content address.
    let imported = try target.liveAttachments().first { $0.id == seed.attachmentLive }
    #expect(imported?.file.sha256 == seed.shaLive)
    #expect(imported?.file.relativePath == "photos/2026/07/seed.jpg")
}

// MARK: - Test 3: scope, both directions

@Test func vehicleArchiveRoundTripsExactlyOneCarAndCarriesNoOtherCarsData() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)   // two-car garage
    let archiveDir = try ArchiveTest.makeTempDir("archive-scope")
    try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo, to: archiveDir, blobSourceDir: seed.blobRoot)

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-scope")
    let result = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)

    // The point is ABSENCE, not the count: the other car must not exist at all.
    #expect(try target.liveVehicles().count == 1)
    #expect(try target.vehicle(id: seed.tesla) == nil,
            "a vehicle-scoped archive must carry NO other car's data - the other car is absent")
    #expect(try target.liveVehicles().map(\.id) == [seed.volvo])
    #expect(try target.liveFillUps(forVehicle: seed.tesla).isEmpty)
    #expect(result.vehicleIds == [seed.volvo])
}

@Test func readerRefusesToTreatAVehicleArchiveAsAnAccountRestore() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-refusal")
    try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo, to: archiveDir, blobSourceDir: seed.blobRoot)

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-refusal")
    let reader = VehicleArchiveReader(repository: target,
                                      blobStore: FileBackedBlobStore(directory: blobStoreDir))
    do {
        _ = try reader.importArchive(at: archiveDir, mode: .accountRestore)
        Issue.record("a vehicle archive fed to the account-restore path must be refused")
    } catch let error as VehicleArchiveError {
        #expect(error == .scopeMismatch(expected: .accountRestore, declared: .vehicle))
    }
    #expect(try target.liveVehicles().isEmpty, "the refused import wrote nothing")
}

// MARK: - Test 4: scope is read, never inferred

@Test func scopeIsReadNotInferredFromAVehicleCountOfOne() throws {
    // A ONE-car garage: `vehicleCount == 1` holds for BOTH meanings (a one-car
    // user's full account and a one-car export). The manifest must still say
    // which this is, and the reader must still branch on it.
    let origin = try ArchiveTest.makeRepo()
    let volvo = ArchiveTest.makeVolvo(UUID.v7())
    try origin.upsertVehicle(volvo)
    try origin.upsertFillUp(FillUp(
        id: UUID.v7(), createdAt: ArchiveTest.time0, updatedAt: ArchiveTest.time0, deletedAt: nil,
        vehicleId: volvo.id, date: ArchiveTest.time1, odometer: 82_000, money: nil, note: nil,
        attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
        volumeL: 42.3, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
        isFull: true, tankLevelAfterPct: 100, stationId: nil,
        crossCheck: .notApplicable, extraction: nil))

    let archiveDir = try ArchiveTest.makeTempDir("archive-single-car")
    // No attachments in this garage, so a fresh blob source directory suffices.
    let exported = try ArchiveTest.exportVolvo(from: origin, vehicleID: volvo.id, to: archiveDir,
                                   blobSourceDir: try ArchiveTest.makeTempDir("single-blobs"))

    #expect(exported.vehicleCount == 1)
    #expect(exported.scope == .vehicle,
            "the manifest declares its scope; it is never inferred from vehicleCount == 1")

    // The reader branches on the manifest and therefore still refuses to treat
    // this one-car archive as an account restore.
    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-single-car")
    let result = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)
    #expect(result.vehicleCount == 1)
    #expect(try target.liveVehicles().map(\.id) == [volvo.id])

    let reader = VehicleArchiveReader(repository: target,
                                      blobStore: FileBackedBlobStore(directory: blobStoreDir))
    do {
        _ = try reader.importArchive(at: archiveDir, mode: .accountRestore)
        Issue.record("a one-car VEHICLE archive is still a vehicle archive; account restore must refuse it")
    } catch let error as VehicleArchiveError {
        #expect(error == .scopeMismatch(expected: .accountRestore, declared: .vehicle))
    }
}

// MARK: - Test 5: every entry type round-trips, not just FillUp

@Test func everyEntryTypeRoundTrips() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-entry-types")
    try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo, to: archiveDir, blobSourceDir: seed.blobRoot)

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-entry-types")
    _ = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)

    #expect(try target.liveFillUps(forVehicle: seed.volvo).map(\.id) == [seed.fillLive])
    #expect(try target.liveChargeSessions(forVehicle: seed.volvo).map(\.id) == [seed.chargeLive])
    #expect(try target.liveExpenses(forVehicle: seed.volvo).map(\.id) == [seed.expenseLive])

    let services = try target.liveServiceRecords(forVehicle: seed.volvo)
    #expect(services.map(\.id) == [seed.serviceLive])
    let service = services.first!
    #expect(service.vendor == "Bosch Service")
    // The ordered item list must survive - it lives in a child table, the
    // easiest thing for a restore to drop.
    #expect(service.items.map(\.title) == ["Engine oil", "Cabin filter"])
    #expect(service.items[0].category == .oil)
    #expect(service.items[0].cost?.amount == ArchiveTest.decimal("89.00"))
}

// MARK: - Test 6: a corrupt archive is rejected whole

@Test func truncatedDataJSONIsRejectedWhole() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)
    let archiveDir = try ArchiveTest.makeTempDir("archive-corrupt")
    try ArchiveTest.exportVolvo(from: origin, vehicleID: seed.volvo, to: archiveDir, blobSourceDir: seed.blobRoot)

    // Truncate data.json mid-stream - a plausible corruption from a failed
    // write or a partial copy.
    let dataURL = archiveDir.appendingPathComponent(ArchiveDataJSON.fileName)
    let original = try Data(contentsOf: dataURL)
    try original.prefix(original.count / 2).write(to: dataURL, options: .atomic)

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-corrupt")
    do {
        _ = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)
        Issue.record("a truncated archive must be rejected")
    } catch let error as VehicleArchiveError {
        #expect(error == .malformedData("data.json is not valid JSON"))
    }
    try ArchiveTest.assertRepositoryEmpty(target, blobStoreDir: blobStoreDir)
}

@Test func schemaViolatingPayloadIsRejectedWhole() throws {
    // A hand-written archive whose fillUp payload fails the registered JSON
    // Schema (volumeL is a string, not a number). The manifest is valid; the
    // payload is not - and the import must land nothing.
    let vehicleID = UUID.v7()
    let archiveDir = try ArchiveTest.makeTempDir("archive-schema-violation")
    let manifest = VehicleArchiveManifest(
        schemaVersion: 1, scope: .vehicle, vehicleIds: [vehicleID],
        exportedAt: ArchiveTest.time0, appVersion: "9.9.9", vehicleCount: 1, entryCount: 1)
    try ArchiveFileIO.atomicWriteJSON(manifest.jsonValue(),
                                      to: archiveDir.appendingPathComponent(VehicleArchiveManifest.fileName))
    let data = JSONValue.object([
        "vehicles": .array([]),
        "entries": .array([
            .object([
                "entityType": .string("fillUp"),
                "schemaVersion": .number("1"),
                "payload": .object([
                    "id": .string(vehicleID.uuidString.lowercased()),
                    "createdAt": .string(PayloadFormat.dateString(ArchiveTest.time0)),
                    "updatedAt": .string(PayloadFormat.dateString(ArchiveTest.time0)),
                    "vehicleId": .string(vehicleID.uuidString.lowercased()),
                    "date": .string(PayloadFormat.dateString(ArchiveTest.time0)),
                    "attachments": .array([]),
                    "provenance": .object(["tag": .string("manual")]),
                    "conflict": .object(["tag": .string("none")]),
                    "crossCheck": .object(["tag": .string("verified")]),
                    "volumeL": .string("not-a-number"),
                    "fuelKind": .string("petrol95"),
                    "isFull": .bool(true)
                ])
            ])
        ]),
        "reminders": .array([]),
        "stations": .array([]),
        "tariffs": .array([])
    ])
    try ArchiveFileIO.atomicWriteJSON(data,
                                      to: archiveDir.appendingPathComponent(ArchiveDataJSON.fileName))

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("blobstore-schema-violation")
    do {
        _ = try ArchiveTest.importArchive(archiveDir, into: target, blobStoreDir: blobStoreDir)
        Issue.record("a schema-violating archive must be rejected")
    } catch let error as VehicleArchiveError {
        if case .invalidPayload = error {
            // expected
        } else {
            Issue.record("expected invalidPayload, got \(error)")
        }
    }
    try ArchiveTest.assertRepositoryEmpty(target, blobStoreDir: blobStoreDir)
}

// MARK: - Test 7: the optional passphrase, both directions
