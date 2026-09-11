import Foundation
import Testing

// RV.163 - the source-scan guard that every persisted entity in docs/SCHEMA.md
// has a production writer a hand-typing user can reach. RV.156 was the shape it
// exists to catch: `upsertStation` was DEFINED and called only by the import
// path and test seeds, so PJ.19's ranking, RV.150's stamping and the Garage
// stations list all stood on a set nothing could populate - a green suite and a
// correctly rendered, permanently dead label.
//
// The guard binds the doc's `## Entities` `###` headings to the repository's
// write calls and walks both `ios/Sources/TankbookCore` and `ios/App/Sources`.
// A writer is a CALL to a repository write function (`.upsertVehicle(`,
// `createStation(`, ...) - never a definition, never a bare mention. The
// exclusions are the whole design:
//   1. a test seed is not a writer - `*TestSeed*`/`*TestSupport*` files and
//      anything inside `#if DEBUG`;
//   2. the import path is not a writer - the file that writes a `Station` from
//      a foreign file is exactly what made RV.156 invisible;
//   3. sync is not a writer - a record arriving from another device was created
//      somewhere, and if that somewhere is only ever another device the entity
//      is still uncreatable here;
//   4. the repository's own write surface (`Persistence/`, `Repository*.swift`,
//      `Migrations.swift`) is not a writer host - it DEFINES and internally
//      composes the write API; RV.156's `upsertStation` was called there by the
//      stamp and by sync while no user flow could reach it.
//
// `Entry (common envelope)` is written as one of its four concrete types;
// `ServiceRecord & Expense` is one heading covering two persisted rows.
// `ExchangeRate` is a local cache, deliberately NOT synced: its writer is the
// /rates fetch -> persist path, never sync. Entities that legitimately have no
// production writer are a deliberate, reasoned exception list; a bare entry
// fails the guard's own self-check, and a spec whose heading left the doc is
// stale and fails too. The scanner is `EntityWriterScanner` (same target).
@Suite("Every SCHEMA entity has a production writer (RV.163)")
struct SchemaEntityWriterGuardTests {

    /// Entities allowed to have NO production writer, each with its reason. Empty
    /// today - every heading resolves to a reachable writer (the specs' notes
    /// say which) - but a future import/sync-only entity is recorded here rather
    /// than silently passing. A bare entry fails `reasonProblem`.
    private static let documentedExceptions: [EntityWriterScanner.DocumentedException] = []

    // MARK: - Source location

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
    }

    private static var scannedRoots: [(prefix: String, url: URL)] {
        let core = repoRoot.appendingPathComponent("ios/Sources/TankbookCore")
        let app = repoRoot.appendingPathComponent("ios/App/Sources")
        return [("Sources/TankbookCore/", core), ("App/Sources/", app)]
    }

    private static func schemaDoc() throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent("docs/SCHEMA.md"), encoding: .utf8)
    }

    /// Every Swift file under the two scanned roots, tagged with the path the
    /// scanner's host rules read (the same labelling RV.167's walk uses).
    private static func productionSources() throws -> [EntityWriterScanner.SourceFile] {
        var files: [EntityWriterScanner.SourceFile] = []
        let manager = FileManager.default
        for (prefix, root) in scannedRoots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                Issue.record("cannot enumerate \(root.path)")
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let contents = try String(contentsOf: url, encoding: .utf8)
                let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
                files.append(.init(path: prefix + relative, contents: contents))
            }
        }
        return files
    }

    // MARK: - L1: the tree walk

    /// Every `###` entity heading in `docs/SCHEMA.md` has a production writer
    /// outside seeds, the import path, sync and `#if DEBUG`. The failure names
    /// the entity and what a writer would be.
    @Test func everySchemaEntityHasAProductionWriter() throws {
        let schema = try Self.schemaDoc()
        let sources = try Self.productionSources()
        let headings = EntityWriterScanner.entityHeadings(in: schema)

        #expect(!headings.isEmpty, "the doc parse found no entities - a parse bug must not read as green")
        #expect(headings.count >= 10, "the doc must expose every entity heading - got \(headings)")

        for heading in headings {
            #expect(!EntityWriterScanner.writerSymbols(forHeading: heading).isEmpty,
                    "\(heading) must resolve to at least one writer symbol")
        }

        for heading in EntityWriterScanner.staleSpecHeadings(schemaText: schema) {
            Issue.record("""
                stale spec: \(heading) is no longer a SCHEMA entity heading - the heading moved \
                or was removed. Update the spec table deliberately.
                """)
        }
        for spec in EntityWriterScanner.specs {
            if let problem = EntityWriterScanner.noteProblem(in: spec) {
                Issue.record("spec self-check: \(problem)")
            }
        }
        for exception in Self.documentedExceptions {
            if let problem = EntityWriterScanner.reasonProblem(in: exception) {
                Issue.record("exception self-check: \(problem)")
            }
        }

        let unwritten = EntityWriterScanner.unwrittenEntities(
            schemaText: schema, sources: sources, exceptions: Self.documentedExceptions)
        for entity in unwritten {
            Issue.record("""
                \(entity) has no production writer: no call to its repository write function \
                outside test seeds, the import path, sync and #if DEBUG. An entity nothing a \
                hand-typing user can create is RV.156's shape - build the door, or record a \
                reasoned exception in documentedExceptions.
                """)
        }
    }

    // MARK: - L1: the real doc parses to the real headings

    /// The heading list is the binding contract; a doc edit that adds, renames
    /// or removes an entity must be seen here rather than read as green.
    @Test func theRealSchemaDocParsesItsEntityHeadings() throws {
        let headings = EntityWriterScanner.entityHeadings(in: try Self.schemaDoc())
        #expect(headings == [
            "Vehicle",
            "Entry (common envelope)",
            "FillUp",
            "ChargeSession",
            "ServiceRecord & Expense",
            "TireSet",
            "Reminder",
            "Attachment & extraction provenance",
            "Preferences (app-level settings)",
            "Station",
            "ExchangeRate (local cache, deliberately NOT synced)"
        ])
    }

    // MARK: - L1: the named mutation's shape

    /// Reconstructs RV.156 exactly: the entity keeps its table, decoder, import
    /// writer and seeds, and RV.156's creation door is `#if DEBUG`-wrapped, so
    /// no production flow can create one. The guard must report `Station`.
    @Test func removingTheStationCreationPathLeavesStationUnwritten() {
        let sources = [
            EntityWriterScanner.SourceFile(
                path: "Sources/TankbookCore/Persistence/Repository+StationStamp.swift",
                contents: "try upsertStation(updated, syncState: .dirty)"),
            EntityWriterScanner.SourceFile(
                path: "Sources/TankbookCore/Persistence/Repository+Sync.swift",
                contents: "try upsertStation($0, syncState: $1)"),
            EntityWriterScanner.SourceFile(
                path: "Sources/TankbookCore/Import/ImportStation.swift",
                contents: "let station = Station(id: id, name: name)"),
            EntityWriterScanner.SourceFile(
                path: "App/Sources/Home/HomeTestSeed.swift",
                contents: "try? repository.upsertStation(station)"),
            EntityWriterScanner.SourceFile(
                path: "App/Sources/ConfirmManual/ManualFillUpStationRow.swift",
                contents: "#if DEBUG\ntry repository.createStation(named: trimmed)\n#endif"),
            EntityWriterScanner.SourceFile(
                path: "App/Sources/StationSettings/StationsListView.swift",
                contents: "#if DEBUG\ntry repository.createStation(named: trimmed)\n#endif")
        ]
        let unwritten = EntityWriterScanner.unwrittenEntities(
            schemaText: Self.stationOnlySchema, sources: sources, exceptions: [])
        #expect(unwritten == ["Station"],
                "deleting the RV.156 door must leave Station unwritten - got \(unwritten)")
    }

    // MARK: - L1: the exclusions

    @Test func aSeedOnlyWriterIsNotAccepted() {
        let unwritten = unwrittenStation([.init(
            path: "App/Sources/Home/HomeTestSeed.swift",
            contents: "try? repository.upsertStation(station)")])
        #expect(unwritten == ["Station"], "a test seed is not a writer - got \(unwritten)")
    }

    @Test func aDebugOnlyWriterIsNotAccepted() {
        let unwritten = unwrittenStation([.init(
            path: "App/Sources/ConfirmManual/ManualFillUpStationRow.swift",
            contents: "#if DEBUG\ntry repository.createStation(named: trimmed)\n#endif")])
        #expect(unwritten == ["Station"], "a #if DEBUG writer is not a production writer - got \(unwritten)")
    }

    @Test func anImportWriterIsNotAccepted() {
        let unwritten = unwrittenStation([.init(
            path: "Sources/TankbookCore/Import/ImportStation.swift",
            contents: "try upsertStation(station)")])
        #expect(unwritten == ["Station"], "the import path is not a writer - got \(unwritten)")
    }

    @Test func aSyncWriterIsNotAccepted() {
        let unwritten = unwrittenStation([.init(
            path: "Sources/TankbookCore/Sync/SyncEngine.swift",
            contents: "try repository.upsertStation(station)")])
        #expect(unwritten == ["Station"], "sync is not a writer - got \(unwritten)")
    }

    @Test func aCommentOrStringMentioningTheWriterIsNotAccepted() {
        let unwritten = unwrittenStation([.init(
            path: "App/Sources/ConfirmManual/ManualFillUpStationRow.swift",
            contents: "// call repository.upsertStation(station)\nlet hint = \"createStation(named:)\"")])
        #expect(unwritten == ["Station"],
                "a comment or string naming the writer is not a call - got \(unwritten)")
    }

    /// The positive control: the same call in a production feature file counts.
    @Test func aProductionCallIsAccepted() {
        let unwritten = unwrittenStation([.init(
            path: "App/Sources/ConfirmManual/ManualFillUpStationRow.swift",
            contents: "guard let station = try repository.createStation(named: trimmed) else { return }")])
        #expect(unwritten.isEmpty, "a production createStation call is a writer - got \(unwritten)")
    }

    /// A bare definition is not a call - the RV.156 fiction was that the write
    /// function existed while nothing invoked it.
    @Test func aDefinitionIsNotACall() {
        let unwritten = unwrittenStation([.init(
            path: "Sources/TankbookCore/Persistence/Repository.swift",
            contents: "public func upsertStation(_ station: Station) throws {}")])
        #expect(unwritten == ["Station"], "a definition is not a caller - got \(unwritten)")
    }

    // MARK: - L1: a new entity fails; an exception passes

    @Test func aNewEntityHeadingWithNoWriterFails() {
        let schema = "## Entities\n\n### Vehicle\n\n### WarpDrive\n"
        let sources = [EntityWriterScanner.SourceFile(
            path: "App/Sources/AddVehicle/AddVehicleView.swift",
            contents: "try repository.upsertVehicle(result.vehicle)")]
        let unwritten = EntityWriterScanner.unwrittenEntities(schemaText: schema, sources: sources)
        #expect(unwritten == ["WarpDrive"], "a new heading with no writer must fail - got \(unwritten)")
    }

    @Test func aDocumentedExceptionPassesAndAReasonlessOneFails() {
        let exception = EntityWriterScanner.DocumentedException(
            entity: "WarpDrive", reason: "arrives only by import until its door ships")
        let unwritten = EntityWriterScanner.unwrittenEntities(
            schemaText: Self.warpDriveOnlySchema, sources: [], exceptions: [exception])
        #expect(unwritten.isEmpty, "a documented exception must pass - got \(unwritten)")
        #expect(EntityWriterScanner.reasonProblem(in: exception) == nil)

        let bare = EntityWriterScanner.DocumentedException(entity: "WarpDrive", reason: " \n ")
        #expect(EntityWriterScanner.reasonProblem(in: bare) != nil,
                "an exception with no reason must fail the self-check")
    }

    @Test func aSpecForAHeadingTheDocNoLongerHasFails() {
        let stale = EntityWriterScanner.staleSpecHeadings(schemaText: "## Entities\n\n### Vehicle\n")
        #expect(stale.contains("Station"),
                "a spec whose heading left the doc must be flagged stale - got \(stale)")
    }

    // MARK: - Fixtures

    private static let stationOnlySchema = "## Entities\n\n### Station\n"
    private static let warpDriveOnlySchema = "## Entities\n\n### WarpDrive\n"

    private func unwrittenStation(_ sources: [EntityWriterScanner.SourceFile]) -> [String] {
        EntityWriterScanner.unwrittenEntities(
            schemaText: Self.stationOnlySchema, sources: sources, exceptions: [])
    }
}
