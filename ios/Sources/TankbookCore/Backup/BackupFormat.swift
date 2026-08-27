import Foundation

// The portable, versioned per-car archive (docs/SCHEMA.md -> "Backup format
// (portable, versioned)" and "Scope: a user-held export is PER CAR").
//
//     manifest.json   always readable, even when the archive is protected
//     data.json       the entity payloads, tombstones included
//     attachments/    content-addressed blobs (sha256 filenames)
//
// The scope marker is MANDATORY and is the load-bearing decision this type
// makes explicit: a reader branches on `manifest.scope`, and MUST NEVER infer
// it from `vehicleCount == 1` - a one-car user's full account and a one-car
// export are indistinguishable by count. See `VehicleArchiveReader`.

/// What the archive contains (docs/SCHEMA.md -> "Scope: a user-held export is
/// PER CAR").
public enum ArchiveScope: String, Codable, Sendable, Equatable {
    /// Exactly the listed vehicles' data: one car in the user-held case. Import
    /// lands as a car; it is never a full restore.
    case vehicle
    /// A whole-account archive (backend snapshot / the F7 restore stream). Not
    /// what the export button produces, and not importable as a car.
    case account
}

/// What a caller asks the importer to do. The importer branches on the
/// archive's declared `scope` and REFUSES a mismatch - a vehicle archive fed to
/// the account-restore path would treat one car's data as the whole garage, the
/// exact failure docs/SCHEMA.md names.
public enum VehicleArchiveImportMode: Sendable, Equatable {
    /// The P5.5b import button: an archive becomes a car. Refuses `scope ==
    /// .account` (a whole-account archive is not a car, and importing it as one
    /// would silently drop every other car).
    case singleCar
    /// The F7 / backend-snapshot restore path. Refuses `scope == .vehicle` (a
    /// per-car archive is not a full account restore). Whole-account restore is
    /// `RestoreEngine`'s job (docs/SYNC.md) - the local importer only guards
    /// the boundary.
    case accountRestore
}

/// Every way opening or importing an archive fails. Errors name the next step
/// (docs/ERRORS.md, hard rule 7) - a caller maps each to copy.
public enum VehicleArchiveError: Error, Equatable, Sendable {
    /// The requested vehicle does not exist in the repository (writer-side).
    case vehicleNotFound
    /// `manifest.json` is missing or does not parse.
    case missingManifest
    /// `data.json` is missing (or, when protected, cannot be produced from the
    /// archive's files).
    case missingData
    /// The manifest is present but violates the format (a required field
    /// missing, an unknown scope spelling, a malformed id). The archive is
    /// rejected whole.
    case malformedManifest(String)
    /// The archive was written by a newer app than this build understands
    /// (manifest `schemaVersion` > the reader's current version).
    case unsupportedSchemaVersion(Int)
    /// The archive's declared `scope` does not match the requested import mode.
    /// Never inferred from counts - always read from the manifest.
    case scopeMismatch(expected: VehicleArchiveImportMode, declared: ArchiveScope)
    /// The archive is passphrase-protected (manifest `passphraseProtected` is
    /// true) and no passphrase was supplied.
    case passphraseRequired
    /// The passphrase did not open the archive (AES-GCM authentication failed).
    case wrongPassphrase
    /// A payload failed its registered JSON Schema or its typed decode. The
    /// whole archive is rejected - a partially applied archive is worse than a
    /// stale one.
    case invalidPayload(String)
    /// An attachment blob in the archive does not hash to its content address.
    case blobHashMismatch(String)
    /// The data.json structure is not the documented shape.
    case malformedData(String)
    /// An underlying file-system or database failure.
    case underlying(String)

    /// Short stable codes for logging/UI mapping (docs/ERRORS.md severity
    /// vocabulary). Never localised copy - callers compose that.
    public var errorCode: String {
        switch self {
        case .vehicleNotFound: "archive_vehicle_not_found"
        case .missingManifest: "archive_missing_manifest"
        case .missingData: "archive_missing_data"
        case .malformedManifest: "archive_malformed_manifest"
        case .unsupportedSchemaVersion: "archive_unsupported_version"
        case .scopeMismatch: "archive_scope_mismatch"
        case .passphraseRequired: "archive_passphrase_required"
        case .wrongPassphrase: "archive_wrong_passphrase"
        case .invalidPayload: "archive_invalid_payload"
        case .blobHashMismatch: "archive_blob_hash_mismatch"
        case .malformedData: "archive_malformed_data"
        case .underlying: "archive_underlying"
        }
    }
}

/// The manifest: the first thing a reader opens (the restore UI reads it before
/// anything else, docs/SCHEMA.md -> "manifest.json is always readable"). It is
/// deliberately plain JSON even when `data.json` is passphrase-protected.
public struct VehicleArchiveManifest: Equatable, Sendable {
    /// The archive format / payload-contract version (`ArchiveSchemaPolicy`).
    public var schemaVersion: Int
    /// The load-bearing field. Read, never inferred.
    public var scope: ArchiveScope
    /// The vehicles this archive carries (one for a user-held export).
    public var vehicleIds: [UUID]
    /// When the archive was written.
    public var exportedAt: Date
    /// The app version that wrote it (diagnostics only, never branch on it).
    public var appVersion: String
    /// Redundant summary of `vehicles` - informational, never a substitute for
    /// `scope`.
    public var vehicleCount: Int
    /// Redundant summary of the entries - informational.
    public var entryCount: Int
    /// Whether `data.json` and the attachment blobs are AES-GCM sealed. The
    /// manifest itself is never sealed.
    public var passphraseProtected: Bool

    public init(schemaVersion: Int, scope: ArchiveScope, vehicleIds: [UUID],
                exportedAt: Date, appVersion: String, vehicleCount: Int, entryCount: Int,
                passphraseProtected: Bool = false) {
        self.schemaVersion = schemaVersion
        self.scope = scope
        self.vehicleIds = vehicleIds
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.vehicleCount = vehicleCount
        self.entryCount = entryCount
        self.passphraseProtected = passphraseProtected
    }

    // MARK: - JSON

    static let fileName = "manifest.json"

    func jsonValue() -> JSONValue {
        .object([
            "schemaVersion": .number(String(schemaVersion)),
            "scope": .string(scope.rawValue),
            "vehicleIds": .array(vehicleIds.map { .string($0.uuidString.lowercased()) }),
            "exportedAt": .string(PayloadFormat.dateString(exportedAt)),
            "appVersion": .string(appVersion),
            "vehicleCount": .number(String(vehicleCount)),
            "entryCount": .number(String(entryCount)),
            "passphraseProtected": .bool(passphraseProtected)
        ])
    }

    static func parse(_ tree: JSONValue) throws -> VehicleArchiveManifest {
        guard let object = tree.objectValue else {
            throw VehicleArchiveError.malformedManifest("manifest must be a JSON object")
        }
        func requireInt(_ key: String) throws -> Int {
            guard case .number(let token)? = object[key], let value = Int(token) else {
                throw VehicleArchiveError.malformedManifest("missing or non-integer '\(key)'")
            }
            return value
        }
        func requireString(_ key: String) throws -> String {
            guard case .string(let value)? = object[key], !value.isEmpty else {
                throw VehicleArchiveError.malformedManifest("missing or empty '\(key)'")
            }
            return value
        }
        let schemaVersion = try requireInt("schemaVersion")
        let scopeRaw = try requireString("scope")
        guard let scope = ArchiveScope(rawValue: scopeRaw) else {
            throw VehicleArchiveError.malformedManifest("unknown scope '\(scopeRaw)'")
        }
        guard case .array(let ids)? = object["vehicleIds"] else {
            throw VehicleArchiveError.malformedManifest("missing 'vehicleIds' array")
        }
        var vehicleIds: [UUID] = []
        for id in ids {
            guard case .string(let raw) = id, let uuid = UUID(uuidString: raw) else {
                throw VehicleArchiveError.malformedManifest("malformed vehicleId in 'vehicleIds'")
            }
            vehicleIds.append(uuid)
        }
        let exportedAtRaw = try requireString("exportedAt")
        guard let exportedAt = PayloadFormat.date(from: exportedAtRaw) else {
            throw VehicleArchiveError.malformedManifest("malformed 'exportedAt' date")
        }
        let passphraseProtected: Bool
        if case .bool(let value)? = object["passphraseProtected"] {
            passphraseProtected = value
        } else {
            // Absent means v1 semantics (never protected); additive optional.
            passphraseProtected = false
        }
        return VehicleArchiveManifest(
            schemaVersion: schemaVersion,
            scope: scope,
            vehicleIds: vehicleIds,
            exportedAt: exportedAt,
            appVersion: try requireString("appVersion"),
            vehicleCount: try requireInt("vehicleCount"),
            entryCount: try requireInt("entryCount"),
            passphraseProtected: passphraseProtected)
    }
}

/// What an import wrote, so the F6-style review can present raw facts
/// (numbers, never a green checkmark - docs/JOURNEYS.md F7's principle).
public struct VehicleArchiveImportResult: Equatable, Sendable {
    public let scope: ArchiveScope
    public let vehicleIds: [UUID]
    public let vehicleCount: Int
    public let entryCount: Int
    /// Attachment records written (references, tombstones included).
    public let attachmentCount: Int
    /// Blob byte files actually landed in the local store.
    public let blobCount: Int

    public init(scope: ArchiveScope, vehicleIds: [UUID], vehicleCount: Int,
                entryCount: Int, attachmentCount: Int, blobCount: Int) {
        self.scope = scope
        self.vehicleIds = vehicleIds
        self.vehicleCount = vehicleCount
        self.entryCount = entryCount
        self.attachmentCount = attachmentCount
        self.blobCount = blobCount
    }
}
