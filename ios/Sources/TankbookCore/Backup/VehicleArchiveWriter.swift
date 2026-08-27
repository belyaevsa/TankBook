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
        try write(contents, to: directory, appVersion: appVersion,
                  passphrase: passphrase, kdfIterations: kdfIterations, now: now)
        let manifestURL = directory.appendingPathComponent(VehicleArchiveManifest.fileName)
        let manifestData = try ArchiveFileIO.readData(manifestURL)
        return try VehicleArchiveManifest.parse(JSONValue.parse(manifestData))
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

    // MARK: - Writing

    private func write(_ contents: VehicleArchiveContents, to directory: URL,
                       appVersion: String, passphrase: String?,
                       kdfIterations: Int, now: Date) throws {
        let schemaVersion = policy.currentVersion
        let manifest = VehicleArchiveManifest(
            schemaVersion: schemaVersion,
            scope: .vehicle,
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
    }
}
