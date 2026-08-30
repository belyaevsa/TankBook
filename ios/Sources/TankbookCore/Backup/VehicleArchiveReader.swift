import Foundation

// The per-car archive reader (docs/SCHEMA.md -> "Backup format" and "Scope: a
// user-held export is PER CAR").
//
// The load-bearing behaviour: **scope is read from the manifest, never inferred
// from `vehicleCount`.** A one-car user's full account and a one-car export are
// indistinguishable by count; the manifest says which this is, and the importer
// branches on it and refuses a mismatch.
//
// Rejection is whole, never partial: every payload is schema-validated and
// typed-decoded BEFORE any blob is written and any row is saved, and the rows
// commit in one transaction. A truncated, corrupt or schema-failing archive
// leaves the repository exactly as it was.

public struct VehicleArchiveReader {
    public let repository: TankbookRepository
    public let blobStore: any BlobStore
    public let policy: ArchiveSchemaPolicy

    public init(repository: TankbookRepository, blobStore: any BlobStore,
                policy: ArchiveSchemaPolicy = .current) {
        self.repository = repository
        self.blobStore = blobStore
        self.policy = policy
    }

    /// Reads `manifest.json` and nothing else. Never needs the passphrase - the
    /// restore UI opens it first, before it knows whether data.json is sealed.
    public static func readManifest(at directory: URL) throws -> VehicleArchiveManifest {
        let url = directory.appendingPathComponent(VehicleArchiveManifest.fileName)
        guard let data = try? Data(contentsOf: url) else {
            throw VehicleArchiveError.missingManifest
        }
        let tree: JSONValue
        do {
            tree = try JSONValue.parse(data)
        } catch {
            throw VehicleArchiveError.malformedManifest("manifest.json is not valid JSON")
        }
        return try VehicleArchiveManifest.parse(tree)
    }

    /// Imports an archive. Branches on the manifest's declared scope.
    ///
    /// - `.singleCar` (the P5.5b import button) imports the archive's car(s);
    ///   an account-scope archive is refused.
    /// - `.accountRestore` refuses any local archive - a per-car archive is not
    ///   a full restore (the load-bearing refusal), and a whole-account restore
    ///   is `RestoreEngine`'s job over the sync stream, not this importer's.
    public func importArchive(
        at directory: URL,
        mode: VehicleArchiveImportMode = .singleCar,
        passphrase: String? = nil,
        kdfIterations: Int = ArchiveCrypto.kdfIterations
    ) throws -> VehicleArchiveImportResult {
        let manifest = try Self.readManifest(at: directory)
        try Self.guardScope(manifest.scope, mode: mode)
        guard !manifest.passphraseProtected || passphrase != nil else {
            throw VehicleArchiveError.passphraseRequired
        }
        let (contents, stagedBlobs) = try decodeContents(at: directory, passphrase: passphrase,
                                                         kdfIterations: kdfIterations)
        try commit(contents: contents, stagedBlobs: stagedBlobs)

        return VehicleArchiveImportResult(
            scope: manifest.scope,
            vehicleIds: contents.vehicles.map(\.id),
            vehicleCount: contents.vehicles.count,
            entryCount: contents.entryCount,
            attachmentCount: contents.attachments.count,
            blobCount: stagedBlobs.count)
    }

    /// Opens, validates and typed-decodes an archive WITHOUT committing
    /// anything (PJ.36). The whole-account round-trip test reads an account
    /// archive through this path and compares the decoded contents hash-equal
    /// against what the writer collected - the local importer still refuses
    /// `.account` scope on commit, by design; reading is not importing.
    func decodeContents(
        at directory: URL,
        passphrase: String? = nil,
        kdfIterations: Int = ArchiveCrypto.kdfIterations
    ) throws -> (VehicleArchiveContents, [String: Data]) {
        let manifest = try Self.readManifest(at: directory)
        let (data, effectiveVersion) = try readDataTree(manifest: manifest, at: directory,
                                                        passphrase: passphrase,
                                                        kdfIterations: kdfIterations)
        var contents = try validateContents(data: data, effectiveVersion: effectiveVersion)
        let stagedBlobs = try stageBlobs(contents: contents, manifest: manifest, at: directory,
                                         passphrase: passphrase, kdfIterations: kdfIterations)
        // The decoded contents carry the staged bytes so the whole-account
        // round-trip (PJ.36) compares the FULL contents hash-equal - blobs and
        // all - against what the writer collected. `commit` uses `stagedBlobs`
        // directly, never this copy.
        contents.blobs = stagedBlobs
        return (contents, stagedBlobs)
    }

    /// Opens, decrypts and version-upcasts `data.json`, returning the parsed
    /// tree plus the version every payload must be validated against.
    private func readDataTree(manifest: VehicleArchiveManifest, at directory: URL,
                              passphrase: String?, kdfIterations: Int) throws -> (ArchiveDataTree, Int) {
        let dataURL = directory.appendingPathComponent(ArchiveDataJSON.fileName)
        let raw = try ArchiveFileIO.readData(dataURL)
        let dataBytes: Data
        if manifest.passphraseProtected {
            dataBytes = try ArchiveCrypto.open(raw, passphrase: passphrase ?? "",
                                               iterations: kdfIterations)
        } else {
            dataBytes = raw
        }
        let tree: JSONValue
        do {
            tree = try JSONValue.parse(dataBytes)
        } catch {
            throw VehicleArchiveError.malformedData("data.json is not valid JSON")
        }
        var data = try ArchiveDataJSON.parse(tree)
        let effectiveVersion = try upcast(data: &data, from: manifest.schemaVersion)
        return (data, effectiveVersion)
    }

    /// Validates EVERY payload (schema, then typed decode) before anything is
    /// written. This is the whole-rejection step: a failure here means nothing
    /// was staged and nothing will be committed.
    private func validateContents(data: ArchiveDataTree, effectiveVersion: Int) throws -> VehicleArchiveContents {
        var contents = VehicleArchiveContents()
        for item in data.singleTypedArrays {
            for payload in item.payloads {
                let record = try validateAndDecode(payload, entityType: item.entityType,
                                                   version: effectiveVersion)
                append(record, to: &contents)
            }
        }
        for entry in data.entries {
            let record = try validateAndDecode(entry.payload, entityType: entry.entityType,
                                               version: effectiveVersion)
            append(record, to: &contents)
        }
        return contents
    }

    /// Reads the attachment blobs the archive physically carries, verifying each
    /// against its content address. An absent blob is the lazy-fetch case (its
    /// original lives on the sync server); a present blob that does not hash to
    /// its address is corruption and rejects the whole archive.
    private func stageBlobs(contents: VehicleArchiveContents, manifest: VehicleArchiveManifest,
                            at directory: URL, passphrase: String?,
                            kdfIterations: Int) throws -> [String: Data] {
        var staged: [String: Data] = [:]
        for attachment in contents.attachments {
            let sha = attachment.file.sha256
            let url = ArchiveFileIO.blobURL(sha256: sha, in: directory)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let blobRaw = try ArchiveFileIO.readData(url)
            let bytes = manifest.passphraseProtected
                ? try ArchiveCrypto.open(blobRaw, passphrase: passphrase ?? "", iterations: kdfIterations)
                : blobRaw
            guard BlobHash.sha256(bytes) == sha else {
                throw VehicleArchiveError.blobHashMismatch(sha)
            }
            staged[sha] = bytes
        }
        return staged
    }

    /// Lands the blobs, then commits every record in ONE transaction. A failure
    /// rolls the filesystem back with the database - a partially applied archive
    /// is worse than a stale one (the same rule as the catalog pack and remote
    /// config).
    private func commit(contents: VehicleArchiveContents, stagedBlobs: [String: Data]) throws {
        var createdBlobs: [String] = []
        do {
            for (sha, bytes) in stagedBlobs {
                if try blobStore.data(for: sha) == nil { createdBlobs.append(sha) }
                try blobStore.save(bytes, for: sha)
            }
            try repository.applyArchiveRecords(contents.importRecords)
        } catch {
            for sha in createdBlobs { try? blobStore.remove(sha256: sha) }
            throw error
        }
    }

    // MARK: - Scope branching

    /// The branch on `manifest.scope`. The manifest is the ONLY source of the
    /// decision - `vehicleCount` is never consulted, because a one-car user's
    /// full account and a one-car export are indistinguishable by count.
    static func guardScope(_ scope: ArchiveScope, mode: VehicleArchiveImportMode) throws {
        switch (mode, scope) {
        case (.singleCar, .vehicle):
            return
        case (.singleCar, .account):
            throw VehicleArchiveError.scopeMismatch(expected: .singleCar, declared: .account)
        case (.accountRestore, .vehicle):
            throw VehicleArchiveError.scopeMismatch(expected: .accountRestore, declared: .vehicle)
        case (.accountRestore, .account):
            // A whole-account archive is the sync restore path's input (F7),
            // not the local importer's. Refuse rather than fake it.
            throw VehicleArchiveError.scopeMismatch(expected: .accountRestore, declared: .account)
        }
    }

    // MARK: - Versioning

    /// Walks the archive's declared version up to the policy's current version
    /// through the registered migrators. Returns the version every payload will
    /// be validated against.
    private func upcast(data: inout ArchiveDataTree, from declared: Int) throws -> Int {
        guard declared <= policy.currentVersion else {
            throw VehicleArchiveError.unsupportedSchemaVersion(declared)
        }
        guard declared < policy.currentVersion else { return declared }
        var version = declared
        var tree = JSONValue.object([
            "vehicles": .array(data.vehicles),
            "entries": .array(data.entries.map { entry in
                .object([
                    "entityType": .string(entry.entityType),
                    "schemaVersion": .number(String(entry.schemaVersion)),
                    "payload": entry.payload
                ])
            }),
            "reminders": .array(data.reminders),
            "stations": .array(data.stations),
            "tariffs": .array(data.tariffs),
            "attachments": .array(data.attachments)
        ])
        while version < policy.currentVersion {
            guard let migrator = policy.migrators[version] else {
                throw VehicleArchiveError.underlying("no migrator registered from archive schema v\(version)")
            }
            tree = try migrator.upcast(tree)
            version += 1
        }
        data = try ArchiveDataJSON.parse(tree)
        return version
    }

    // MARK: - Validation + decode

    /// Schema-validates one payload against the effective version, then typed-
    /// decodes it through `PayloadCodec` - the single entity encoder the whole
    /// pipeline shares. The typed decode always runs at the codec's current
    /// contract version (unknown additive fields are preserved, not dropped).
    private func validateAndDecode(_ payload: JSONValue, entityType: String,
                                   version: Int) throws -> ArchiveImportRecord {
        guard let schema = policy.schemaLoader(version, entityType) else {
            throw VehicleArchiveError.invalidPayload(
                "no registered schema for \(entityType) at v\(version)")
        }
        let violations = JSONSchemaValidator.validate(instance: payload, schema: schema)
        guard violations.isEmpty else {
            let first = violations.first.map { "\($0.pointer): \($0.message)" } ?? "unknown"
            throw VehicleArchiveError.invalidPayload(
                "\(entityType) fails its schema at \(first)")
        }
        let envelope = PayloadEnvelope(entityType: entityType,
                                       schemaVersion: PayloadCodec.currentSchemaVersion,
                                       payload: payload)
        return try typedDecode(envelope, entityType: entityType)
    }

    /// The flat entity-type dispatch (one branch per SyncedEntity). Mirrors the
    /// sync client's `applyRecord` switch - the single payload codec serves both.
    private func typedDecode(_ envelope: PayloadEnvelope, entityType: String) throws -> ArchiveImportRecord {
        switch entityType {
        case Vehicle.entityType:
            return .vehicle(try decodeEntity(Vehicle.self, envelope: envelope, entityType: entityType))
        case FillUp.entityType:
            return .fillUp(try decodeEntity(FillUp.self, envelope: envelope, entityType: entityType))
        case ChargeSession.entityType:
            return .chargeSession(try decodeEntity(ChargeSession.self, envelope: envelope, entityType: entityType))
        case ServiceRecord.entityType:
            return .serviceRecord(try decodeEntity(ServiceRecord.self, envelope: envelope, entityType: entityType))
        case Expense.entityType:
            return .expense(try decodeEntity(Expense.self, envelope: envelope, entityType: entityType))
        case Reminder.entityType:
            return .reminder(try decodeEntity(Reminder.self, envelope: envelope, entityType: entityType))
        case Station.entityType:
            return .station(try decodeEntity(Station.self, envelope: envelope, entityType: entityType))
        case Tariff.entityType:
            return .tariff(try decodeEntity(Tariff.self, envelope: envelope, entityType: entityType))
        case Attachment.entityType:
            return .attachment(try decodeEntity(Attachment.self, envelope: envelope, entityType: entityType))
        default:
            throw VehicleArchiveError.invalidPayload("unexpected entity type '\(entityType)'")
        }
    }

    private func decodeEntity<E: SyncedEntity>(_ type: E.Type, envelope: PayloadEnvelope,
                                               entityType: String) throws -> E {
        do {
            return try PayloadCodec.decode(envelope, as: E.self).entity
        } catch let error as PayloadCodec.Error {
            throw VehicleArchiveError.invalidPayload("\(entityType) does not decode: \(error)")
        }
    }

    private func append(_ record: ArchiveImportRecord, to contents: inout VehicleArchiveContents) {
        switch record {
        case .vehicle(let value): contents.vehicles.append(value)
        case .fillUp(let value): contents.fillUps.append(value)
        case .chargeSession(let value): contents.chargeSessions.append(value)
        case .serviceRecord(let value): contents.serviceRecords.append(value)
        case .expense(let value): contents.expenses.append(value)
        case .reminder(let value): contents.reminders.append(value)
        case .station(let value): contents.stations.append(value)
        case .tariff(let value): contents.tariffs.append(value)
        case .attachment(let value): contents.attachments.append(value)
        }
    }
}
