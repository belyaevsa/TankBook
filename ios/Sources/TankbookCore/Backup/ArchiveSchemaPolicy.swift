import Foundation

// Schema-version policy for the portable archive (docs/SCHEMA.md -> "Rules:
// additive schema evolution only; a schemaVersion bump requires a migrator").
//
// The archive's `schemaVersion` is the payload-contract version its payloads
// were encoded with (the same number that rides in the sync envelope). Today it
// is 1 everywhere. The policy decouples the archive reader from the sync codec:
// a future build bumps the policy's `currentVersion` and registers a migrator,
// and old archives upcast before they validate or import.

/// A declarative, whole-archive upcast: old-version payloads become
/// current-version payloads (docs/SCHEMA.md -> additive evolution only - new
/// optional fields, never a rewrite).
public protocol ArchiveMigrator: Sendable {
    /// The version this migrator reads.
    var fromVersion: Int { get }
    /// Upcasts `data` (the parsed `data.json` object) one version step.
    /// Mechanical JSON surgery on the tree; unknown keys survive untouched.
    func upcast(_ data: JSONValue) throws -> JSONValue
}

/// The reader's schema-version world view: which version is current, how old
/// archives get there, and where the JSON Schemas to validate against come
/// from. Tests supply a higher `currentVersion` plus a fixture migrator to
/// prove additive evolution; production uses `current`.
public struct ArchiveSchemaPolicy: Sendable {
    /// The version the reader understands as "now". Archives above this are
    /// refused as too new; archives below it are run through `migrators`.
    public var currentVersion: Int
    /// `migrators[fromVersion]` upcasts an archive one step. Chained for a
    /// multi-step climb (v1 -> v2 -> v3).
    public var migrators: [Int: any ArchiveMigrator]
    /// Returns the registered JSON Schema for `(version, entityType)`. The
    /// production loader reads the schemas bundled with the app
    /// (`Schemas/v1/`); a higher-version policy supplies its own.
    public var schemaLoader: @Sendable (_ version: Int, _ entityType: String) -> JSONValue?

    public init(currentVersion: Int,
                migrators: [Int: any ArchiveMigrator] = [:],
                schemaLoader: @escaping @Sendable (Int, String) -> JSONValue?) {
        self.currentVersion = currentVersion
        self.migrators = migrators
        self.schemaLoader = schemaLoader
    }

    /// Production policy: payload-contract v1, no migrators yet (v1 is current),
    /// and the schemas bundled with the app.
    public static let current = ArchiveSchemaPolicy(
        currentVersion: PayloadCodec.currentSchemaVersion,
        migrators: [:],
        schemaLoader: ArchiveSchemaPolicy.bundledSchema)

    /// Loads `Schemas/v1/<entityType>.schema.json` from the package bundle.
    /// The tests assert these stay byte-identical to `docs/schemas/v1` (the
    /// generated source), so the bundled copy cannot drift silently.
    static func bundledSchema(version: Int, entityType: String) -> JSONValue? {
        guard version == PayloadCodec.currentSchemaVersion else { return nil }
        guard let url = Bundle.module.url(forResource: entityType,
                                         withExtension: "schema.json",
                                         subdirectory: "Schemas/v1") else { return nil }
        guard let data = try? Data(contentsOf: url),
              let tree = try? JSONValue.parse(data) else { return nil }
        return tree
    }
}
