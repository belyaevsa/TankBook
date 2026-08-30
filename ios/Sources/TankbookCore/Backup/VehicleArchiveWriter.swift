import Foundation

// The per-car archive writer (docs/SCHEMA.md -> "Scope: a user-held export is
// PER CAR"). Given a vehicle id it produces exactly that car's data: the
// `Vehicle`, every entry type, its reminders and tariffs, the stations its
// entries reference, the matching attachments, every tombstone, and the blob
// bytes it can still find. Manifest always first and always plain - the restore
// UI reads it before anything else.

public struct VehicleArchiveWriter {
    public let repository: TankbookRepository
    /// Reads each attachment's rendition bytes (the sync blob). Content
    /// addressing means a file whose bytes hash to `Attachment.file.sha256` is
    /// guaranteed correct - anything else is a local-integrity failure and the
    /// export refuses rather than ship a corrupt archive.
    public let blobSource: any BlobSource
    /// The schema version the archive is written at.
    public let policy: ArchiveSchemaPolicy

    public init(repository: TankbookRepository, blobSource: any BlobSource,
                policy: ArchiveSchemaPolicy = .current) {
        self.repository = repository
        self.blobSource = blobSource
        self.policy = policy
    }

    /// Writes the per-car archive for `vehicleID` into `directory`.
    /// `passphrase == nil` exports unprotected; a passphrase AES-GCM-seals
    /// `data.json` and every attachment blob (the manifest stays plain).
    /// `kdfIterations` defaults to the production 100k PBKDF2 round; tests pass
    /// `ArchiveCrypto.testIterations` to stay fast.
    @discardableResult
    public func writeArchive(
        vehicleID: UUID,
        to directory: URL,
        appVersion: String = LogContext.currentAppVersion(),
        passphrase: String? = nil,
        kdfIterations: Int = ArchiveCrypto.kdfIterations,
        now: Date = Date()
    ) throws -> VehicleArchiveManifest {
        let contents = try collect(vehicleID: vehicleID)
        return try write(contents, scope: .vehicle, to: directory, appVersion: appVersion,
                         passphrase: passphrase, kdfIterations: kdfIterations, now: now)
    }

    /// Writes the WHOLE-ACCOUNT archive (PJ.36): every vehicle - live or
    /// tombstoned - with every entry type, reminders, stations, tariffs, the
    /// matching attachments and every blob the device still holds. Declares
    /// `scope: "account"`, the shape the F7 restore path consumes; a per-car
    /// import must refuse it, and the reader's account-restore branch refuses
    /// it too - this is a user-held hand-off, not a local restore input
    /// (docs/SCHEMA.md -> "Scope: a user-held export is PER CAR").
    @discardableResult
    public func writeAccountArchive(
        to directory: URL,
        appVersion: String = LogContext.currentAppVersion(),
        passphrase: String? = nil,
        kdfIterations: Int = ArchiveCrypto.kdfIterations,
        now: Date = Date()
    ) throws -> VehicleArchiveManifest {
        let contents = try collectAll()
        return try write(contents, scope: .account, to: directory, appVersion: appVersion,
                         passphrase: passphrase, kdfIterations: kdfIterations, now: now)
    }

    /// The whole-account contents this writer collects (PJ.36): the round-trip
    /// test compares it hash-equal against what the reader decodes back, so the
    /// collection rule and the decode rule are pinned to agree.
    func accountContents() throws -> VehicleArchiveContents {
        try collectAll()
    }

    // MARK: - Collection (the per-car rule)

    private func collect(vehicleID: UUID) throws -> VehicleArchiveContents {
        guard let vehicle = try repository.vehicleIncludingDeleted(id: vehicleID) else {
            throw VehicleArchiveError.vehicleNotFound
        }
        var contents = VehicleArchiveContents()
        contents.vehicles = [vehicle]

        let fillUps = try repository.fillUpsIncludingDeleted(forVehicle: vehicleID)
        let charges = try repository.chargeSessionsIncludingDeleted(forVehicle: vehicleID)
        let services = try repository.serviceRecordsIncludingDeleted(forVehicle: vehicleID)
        let expenses = try repository.expensesIncludingDeleted(forVehicle: vehicleID)
        contents.fillUps = fillUps
        contents.chargeSessions = charges
        contents.serviceRecords = services
        contents.expenses = expenses
        contents.reminders = try repository.remindersIncludingDeleted(forVehicle: vehicleID)

        // Stations: the ones this car's entries reference - live or tombstoned,
        // because a tombstoned station a live entry still points at must import
        // with it (nothing lost silently, hard rule 8).
        let referencedStationIDs = Set(fillUps.compactMap(\.stationId))
        contents.stations = try repository.stationsIncludingDeleted()
            .filter { referencedStationIDs.contains($0.id) }

        // Tariffs: this car's own, plus any shared (vehicleId == nil) tariff
        // one of its charges references - a charge that names a tariff must
        // import that tariff or the reference dangles.
        let referencedTariffIDs = Set(charges.compactMap(\.tariffId))
        contents.tariffs = try repository.tariffsIncludingDeleted()
            .filter { $0.vehicleId == vehicleID || referencedTariffIDs.contains($0.id) }

        // Attachments: referenced by any entry (live or tombstoned), plus the
        // vehicle photo.
        var referencedAttachmentIDs = Set<AttachmentID>()
        let entryLists: [any Entry] = fillUps + charges + services + expenses
        for entry in entryLists {
            referencedAttachmentIDs.formUnion(entry.attachments)
        }
        if let photo = vehicle.photo {
            referencedAttachmentIDs.insert(photo)
        }
        let attachments = try repository.attachmentsIncludingDeleted()
            .filter { referencedAttachmentIDs.contains($0.id) }
        contents.attachments = attachments

        // Blob bytes. A blob the device no longer holds (its original lives on
        // the sync server) is skipped, not fatal: the reference still imports
        // and the blob lazy-fetches exactly as a synced attachment would.
        var blobs: [String: Data] = [:]
        for attachment in attachments {
            guard let data = try blobSource.renditionData(for: attachment) else { continue }
            let sha = attachment.file.sha256
            guard BlobHash.sha256(data) == sha else {
                throw VehicleArchiveError.underlying(
                    "blob \(sha) does not hash to its content address; refusing a corrupt export")
            }
            blobs[sha] = data
        }
        contents.blobs = blobs
        return contents
    }

    /// The whole-account collection (PJ.36): everything the repository holds,
    /// tombstones included. For an account archive there is no "referenced
    /// only" filter to apply - every station, tariff and attachment IS the
    /// account's data, and every vehicle's entries ride with it (nothing lost
    /// silently, hard rule 8).
    private func collectAll() throws -> VehicleArchiveContents {
        var contents = VehicleArchiveContents()
        let vehicles = try repository.allVehiclesIncludingDeleted()
        contents.vehicles = vehicles
        for vehicle in vehicles {
            contents.fillUps += try repository.fillUpsIncludingDeleted(forVehicle: vehicle.id)
            contents.chargeSessions += try repository.chargeSessionsIncludingDeleted(forVehicle: vehicle.id)
            contents.serviceRecords += try repository.serviceRecordsIncludingDeleted(forVehicle: vehicle.id)
            contents.expenses += try repository.expensesIncludingDeleted(forVehicle: vehicle.id)
            contents.reminders += try repository.remindersIncludingDeleted(forVehicle: vehicle.id)
        }
        contents.stations = try repository.stationsIncludingDeleted()
        contents.tariffs = try repository.tariffsIncludingDeleted()

        var referencedAttachmentIDs = Set<AttachmentID>()
        let entryLists: [any Entry] = contents.fillUps + contents.chargeSessions
            + contents.serviceRecords + contents.expenses
        for entry in entryLists {
            referencedAttachmentIDs.formUnion(entry.attachments)
        }
        for vehicle in vehicles {
            if let photo = vehicle.photo {
                referencedAttachmentIDs.insert(photo)
            }
        }
        let attachments = try repository.attachmentsIncludingDeleted()
            .filter { referencedAttachmentIDs.contains($0.id) }
        contents.attachments = attachments

        // Blob bytes. Same rule as the per-car writer: a blob the device no
        // longer holds is skipped, not fatal - the reference still travels and
        // lazy-fetches exactly as a synced attachment would.
        var blobs: [String: Data] = [:]
        for attachment in attachments {
            guard let data = try blobSource.renditionData(for: attachment) else { continue }
            let sha = attachment.file.sha256
            guard BlobHash.sha256(data) == sha else {
                throw VehicleArchiveError.underlying(
                    "blob \(sha) does not hash to its content address; refusing a corrupt export")
            }
            blobs[sha] = data
        }
        contents.blobs = blobs
        return contents
    }

    // MARK: - Writing

    private func write(_ contents: VehicleArchiveContents, scope: ArchiveScope, to directory: URL,
                       appVersion: String, passphrase: String?,
                       kdfIterations: Int, now: Date) throws -> VehicleArchiveManifest {
        let schemaVersion = policy.currentVersion
        let manifest = VehicleArchiveManifest(
            schemaVersion: schemaVersion,
            scope: scope,
            vehicleIds: contents.vehicles.map(\.id),
            exportedAt: now,
            appVersion: appVersion,
            vehicleCount: contents.vehicles.count,
            entryCount: contents.entryCount,
            passphraseProtected: passphrase != nil)

        // Manifest is always written plain (docs/SCHEMA.md: always readable).
        try ArchiveFileIO.atomicWriteJSON(manifest.jsonValue(),
                                          to: directory.appendingPathComponent(VehicleArchiveManifest.fileName))

        // data.json: plain, or one AES-GCM box when protected.
        let dataTree = try ArchiveDataJSON.encode(contents, schemaVersion: schemaVersion)
        let dataBytes = try dataTree.jsonData()
        let dataURL = directory.appendingPathComponent(ArchiveDataJSON.fileName)
        if let passphrase {
            let sealed = try ArchiveCrypto.seal(dataBytes, passphrase: passphrase, iterations: kdfIterations)
            try ArchiveFileIO.atomicWrite(sealed, to: dataURL)
        } else {
            try ArchiveFileIO.atomicWrite(dataBytes, to: dataURL)
        }

        // Blobs: content-addressed; each individually sealed when protected.
        for (sha, bytes) in contents.blobs {
            let url = ArchiveFileIO.blobURL(sha256: sha, in: directory)
            if let passphrase {
                let sealed = try ArchiveCrypto.seal(bytes, passphrase: passphrase, iterations: kdfIterations)
                try ArchiveFileIO.atomicWrite(sealed, to: url)
            } else {
                try ArchiveFileIO.atomicWrite(bytes, to: url)
            }
        }
        return manifest
    }
}
