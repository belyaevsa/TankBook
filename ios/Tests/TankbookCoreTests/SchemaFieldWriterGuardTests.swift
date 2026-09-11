import Foundation
import Testing

// RV.196 - the field-level extension of RV.163's entity-writer guard. RV.163
// proves a SCHEMA entity has a production writer; PJ.55 was the instance it
// could not see, because `Station` HAD a writer while `Station.favorite` had
// none. `FieldWriterScanner` asks the question one level down, and this suite
// is its calibration: one live miss (`Station.favorite` fixed by PJ.55 must NOT
// be reported) and one live hit (`Preferences.notifications.anomalies`, which
// appears only in the decoder, must be).
//
// The oracle for every expectation is a source line, named at the call:
//   - `Station.favorite` is written by `setStationFavorite` at
//     `StationSettingsView.swift:178`, whose assignment lives at
//     `Repository+StationStamp.swift:71` - a repository DEFINITION, so the call
//     is the writer, never the definition.
//   - `Preferences.notifications.anomalies` is read only by the decoder at
//     `Records+Extras.swift:247`; a decoder restores what was stored and cannot
//     originate a value, which is exactly the shape that hid PJ.55.
@Suite("Every SCHEMA field has a production writer (RV.196)")
struct SchemaFieldWriterGuardTests {

    /// Fields allowed to have NO production writer, each with a reason a human
    /// wrote. Every entry names a live gap the field-level scan found; a field
    /// that gains a writer must lose its exception (`staleExceptions` fails the
    /// guard when it does not), so the list cannot rot into a skip list.
    private static let documentedExceptions: [FieldWriterScanner.DocumentedException] = [
        .init(field: "FillUp.fiscalIdentity",
              reason: "The fiscal QR identity is decoded and compared by DuplicateDetector "
                  + "(DuplicateDetector.swift:100), but no production save writes it onto a FillUp - "
                  + "only the decoder and the init default do. Reported by RV.196; a product-owner "
                  + "decision (store it on the scanned save, or drop the field)."),
        .init(field: "Preferences.eagerMediaOnWiFi",
              reason: "The blob pipeline reads the eager-download flag but no screen sets it; it "
                  + "appears only in the decoder (Records+Extras.swift:249). Reported by RV.196."),
        .init(field: "Preferences.notifications.anomalies",
              reason: "The app has no anomaly-notification toggle - the anomaly card is in-app only - "
                  + "so the field is decoded (Records+Extras.swift:247) and merged but never set. "
                  + "Reported by RV.196; the product owner decides toggle-or-drop."),
        .init(field: "Preferences.notifications.reminders",
              reason: "No surface sets the reminders notification category; only the decoder "
                  + "(Records+Extras.swift:246) reads it. Reported by RV.196."),
        .init(field: "Preferences.proFeedbackDiagnostics",
              reason: "The About-screen diagnostics toggle the field documents was never built; the "
                  + "field is decoded (Records+Extras.swift:251) and synced but unwritable. "
                  + "Reported by RV.196."),
        .init(field: "ServiceRecord.proposedReminderId",
              reason: "The doc links it to the reminder the user accepted, but every production "
                  + "construction passes nil (ServiceEntryDraft.swift:122, "
                  + "ServiceEntryFormState.swift:205) and no update path sets it. Reported by RV.196."),
        .init(field: "ServiceItem.lifetime.km",
              reason: "The item's km lifetime is preserved on save "
                  + "(ServiceEntryItemDraft.serviceItem, ServiceEntryFormState.swift) but no editor "
                  + "can set it, so it is never a non-nil value. PJ.22 builds the lifetime editor "
                  + "and the reminder proposal it drives; remove this exception in that same change."),
        .init(field: "ServiceItem.lifetime.months",
              reason: "The item's months lifetime is preserved on save "
                  + "(ServiceEntryItemDraft.serviceItem, ServiceEntryFormState.swift) but no editor "
                  + "can set it, so it is never a non-nil value. PJ.22 builds the lifetime editor "
                  + "and the reminder proposal it drives; remove this exception in that same change."),
        .init(field: "TireSet.purchaseExpenseId",
              reason: "The purchase link is only ever written nil (TireSetDraft.build, "
                  + "TireSetDraft.swift:35) and read nowhere. PJ.26 adds the 'make this a tire set' "
                  + "door from a .parts Expense that writes it; remove this exception in that same "
                  + "change."),
        .init(field: "Station.brand",
              reason: "Only ever written as nil when a station is minted (ImportStation.swift:42); "
                  + "brand normalisation is RV.115/RV.180's reference-data work, which owns this "
                  + "field. Out of scope for RV.196.")
    ]

    /// A heading whose fields are legitimately out of this row's scope, with the
    /// reason. The scanner checks the four concrete entry types, so an entity
    /// exception suppresses every field under the heading at once.
    private static let documentedEntityExceptions: [String: String] = [
        "ChargeSession": "The EV capture path is [v1.x] and unbuilt (PJ.12): a ChargeSession is "
            + "created only by import/sync and the decoder, so its fields have no production "
            + "construction yet. The entity-level guard already resolves the heading's writer; the "
            + "brief says not to re-report its fields one by one."
    ]

    // MARK: - Source location

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
    }

    private static func schemaDoc() throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent("docs/SCHEMA.md"), encoding: .utf8)
    }

    private static func productionSources() throws -> [FieldWriterScanner.SourceFile] {
        var files: [FieldWriterScanner.SourceFile] = []
        let roots = [
            ("Sources/TankbookCore/", repoRoot.appendingPathComponent("ios/Sources/TankbookCore")),
            ("App/Sources/", repoRoot.appendingPathComponent("ios/App/Sources"))
        ]
        for (prefix, root) in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]) else {
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

    // MARK: - L1: the real tree, with the reasoned exceptions

    /// Every field the SCHEMA entities name has a production writer, or is one of
    /// the reasoned exceptions above. The named mutation is deleting the
    /// favourite's production call: the guard then reports `Station.favorite`.
    @Test func everySchemaFieldHasAProductionWriterOrReasonedException() throws {
        let schema = try Self.schemaDoc()
        let sources = try Self.productionSources()
        let headings = EntityWriterScanner.entityHeadings(in: schema)

        #expect(!headings.isEmpty, "the doc parse found no entities - a parse bug must not read as green")
        assertEveryHeadingResolves(headings, sources: sources)
        reportSelfCheckProblems(schema: schema, sources: sources)

        let unwritten = FieldWriterScanner.unwrittenFields(
            schemaText: schema, sources: sources,
            exceptions: Self.documentedExceptions,
            entityExceptions: Self.documentedEntityExceptions)
        for field in unwritten {
            Issue.record("""
                \(field) has no production writer: no assignment, no non-default init argument and \
                no reachable repository write call outside test seeds, sync, #if DEBUG and the \
                decoder. A field a reader consumes and nothing can set is PJ.55's shape - build \
                the door, or record a reasoned exception in documentedExceptions.
                """)
        }
    }

    private func assertEveryHeadingResolves(_ headings: [String],
                                            sources: [FieldWriterScanner.SourceFile]) {
        for heading in headings {
            if heading == "Entry (common envelope)" { continue }
            let typeNames = FieldWriterScanner.typeNames(forHeading: heading)
            #expect(!typeNames.isEmpty, "\(heading) must resolve to a Swift type")
            for typeName in typeNames {
                #expect(!FieldWriterScanner.fields(forType: typeName, in: sources).isEmpty,
                        "\(heading) -> \(typeName) must expose readable fields")
            }
        }
    }

    private func reportSelfCheckProblems(schema: String,
                                         sources: [FieldWriterScanner.SourceFile]) {
        for spec in FieldWriterScanner.entityFieldSpecs {
            if let problem = FieldWriterScanner.noteProblem(in: spec) {
                Issue.record("field spec self-check: \(problem)")
            }
        }
        for heading in FieldWriterScanner.staleSpecHeadings(schemaText: schema) {
            Issue.record("stale field spec: \(heading) is no longer a SCHEMA entity heading")
        }
        for exception in Self.documentedExceptions {
            if let problem = FieldWriterScanner.reasonProblem(in: exception) {
                Issue.record("exception self-check: \(problem)")
            }
        }
        for field in FieldWriterScanner.staleExceptions(
            schemaText: schema, sources: sources,
            exceptions: Self.documentedExceptions,
            entityExceptions: Self.documentedEntityExceptions) {
            Issue.record("""
                stale field exception: \(field) now has a writer or no longer exists - \
                remove the exception
                """)
        }
        for heading in FieldWriterScanner.staleEntityExceptions(
            schemaText: schema, entityExceptions: Self.documentedEntityExceptions) {
            Issue.record("stale entity exception: \(heading) is no longer a SCHEMA heading")
        }
    }

    // MARK: - L1: the calibration pair

    /// The hit: with no exception list written, the decoder-only field is
    /// reported. Oracle: `Records+Extras.swift:247` is the decoder, and a decoder
    /// is not a writer.
    @Test func theDecoderOnlyFieldIsReportedWithNoExceptions() throws {
        let unwritten = FieldWriterScanner.unwrittenFields(
            schemaText: try Self.schemaDoc(), sources: try Self.productionSources())
        #expect(unwritten.contains("Preferences.notifications.anomalies"),
                "anomalies is decoded, never written - it must be reported. Got \(unwritten)")
    }

    /// The miss PJ.55 fixed: `Station.favorite` is NOT reported, because
    /// `StationSettingsView.swift:178` calls `setStationFavorite`. A guard that
    /// flags the field PJ.55 gave a writer is tuned wrong.
    @Test func theFavouriteFieldIsNotReported() throws {
        let unwritten = FieldWriterScanner.unwrittenFields(
            schemaText: try Self.schemaDoc(), sources: try Self.productionSources())
        #expect(!unwritten.contains("Station.favorite"),
                "PJ.55 gave favorite a writer - it must not be reported. Got \(unwritten)")
    }

    /// The full report with no exception list, pinned so a new unwritten field
    /// (or a writer that lands) forces this test to be read and updated. Each
    /// line's oracle: the field appears in the schema, its decoder, and nowhere
    /// that sets it.
    @Test func theRealSchemaFieldsReportTheirKnownGapsWithNoExceptions() throws {
        let unwritten = FieldWriterScanner.unwrittenFields(
            schemaText: try Self.schemaDoc(), sources: try Self.productionSources())
        #expect(unwritten == [
            "ChargeSession.chargeType",
            "ChargeSession.createdAt",
            "ChargeSession.durationMin",
            "ChargeSession.socEndPct",
            "ChargeSession.socStartPct",
            "ChargeSession.tariffId",
            "FillUp.fiscalIdentity",
            "Preferences.eagerMediaOnWiFi",
            "Preferences.notifications.anomalies",
            "Preferences.notifications.reminders",
            "Preferences.proFeedbackDiagnostics",
            "ServiceItem.lifetime.km",
            "ServiceItem.lifetime.months",
            "ServiceRecord.proposedReminderId",
            "Station.brand",
            "TireSet.purchaseExpenseId"
        ], "the field scan's report moved - read it before updating this list. Got \(unwritten)")
    }

    // MARK: - L1: the newly-visible entities (PJ.63)

    /// Every exception on the newly-visible fields names the row that will write
    /// it, so the exception is removable in that row's own change. The reported
    /// fields and their calibration live in `SchemaFieldWriterGuardNewEntityTests`.
    @Test func theNewExceptionsNameTheWritingRow() {
        let byField = Dictionary(
            uniqueKeysWithValues: Self.documentedExceptions.map { ($0.field, $0.reason) })
        #expect(byField["TireSet.purchaseExpenseId"]?.contains("PJ.26") == true,
                "the purchase-link exception must name PJ.26, its writer")
        #expect(byField["ServiceItem.lifetime.km"]?.contains("PJ.22") == true,
                "the lifetime exception must name PJ.22, its writer")
        #expect(byField["ServiceItem.lifetime.months"]?.contains("PJ.22") == true,
                "the lifetime exception must name PJ.22, its writer")
    }

    // MARK: - L1: the exclusions

    @Test func aFieldWrittenOnlyFromASeedIsStillReported() {
        let sources = Self.stationSources(extra: [.init(
            path: "App/Sources/Home/HomeTestSeed.swift",
            contents: "let station = Station(name: \"Shell\", favorite: true)")])
        let unwritten = FieldWriterScanner.unwrittenFields(schemaText: Self.stationSchema, sources: sources)
        #expect(unwritten.contains("Station.favorite"),
                "a test seed is not a writer - got \(unwritten)")
    }

    @Test func aFieldWrittenOnlyInsideDebugIsStillReported() {
        let sources = Self.stationSources(extra: [.init(
            path: "App/Sources/ConfirmManual/ManualFillUpStationRow.swift",
            contents: "#if DEBUG\nlet station = Station(name: \"Shell\", favorite: true)\n#endif")])
        let unwritten = FieldWriterScanner.unwrittenFields(schemaText: Self.stationSchema, sources: sources)
        #expect(unwritten.contains("Station.favorite"),
                "a #if DEBUG writer is not a production writer - got \(unwritten)")
    }

    /// The decoder restores what was stored - it cannot originate a value. Oracle:
    /// `Station(favorite: row["favorite"])` reads the stored column.
    @Test func theDecoderIsNotAWriter() {
        let sources = Self.stationSources(extra: [.init(
            path: "Sources/TankbookCore/Persistence/Records+Extras.swift",
            contents: "station = Station(name: row[\"name\"], favorite: row[\"favorite\"] as Bool)")])
        let unwritten = FieldWriterScanner.unwrittenFields(schemaText: Self.stationSchema, sources: sources)
        #expect(unwritten.contains("Station.favorite"),
                "the decoder is not a writer - got \(unwritten)")
    }

    /// The named mutation's shape: the repository function still exists, but no
    /// production call reaches it. This is PJ.55's exact state - the write API
    /// defined and nothing that invokes it.
    @Test func removingTheFavouriteCallReportsStationFavorite() {
        let sources = Self.stationSources(extra: [.init(
            path: "Sources/TankbookCore/Persistence/Repository+StationStamp.swift",
            contents: """
                public func setStationFavorite(id: UUID, _ favorite: Bool) throws -> Bool {
                    var live = try station(id: id)
                    live.favorite = favorite
                    return true
                }
                """)])
        let unwritten = FieldWriterScanner.unwrittenFields(schemaText: Self.stationSchema, sources: sources)
        #expect(unwritten.contains("Station.favorite"),
                "a defined-but-uncalled writer is not a writer - got \(unwritten)")
    }

    @Test func aReachableFavouriteCallIsAccepted() {
        let sources = Self.stationSources(extra: [
            .init(path: "Sources/TankbookCore/Persistence/Repository+StationStamp.swift",
                  contents: """
                      public func setStationFavorite(id: UUID, _ favorite: Bool) throws -> Bool {
                          var live = try station(id: id)
                          live.favorite = favorite
                          return true
                      }
                      """),
            .init(path: "App/Sources/StationSettings/StationSettingsView.swift",
                  contents: "try repository.setStationFavorite(id: station.id, favorite)")
        ])
        let unwritten = FieldWriterScanner.unwrittenFields(schemaText: Self.stationSchema, sources: sources)
        #expect(!unwritten.contains("Station.favorite"),
                "a production call to the field's write function is a writer - got \(unwritten)")
    }

    // MARK: - L1: the reasoned-exception self-check

    @Test func aReasonlessFieldExceptionFailsTheSelfCheck() {
        let bare = FieldWriterScanner.DocumentedException(field: "Station.favorite", reason: " \n ")
        #expect(FieldWriterScanner.reasonProblem(in: bare) != nil,
                "an exception with no reason must fail the self-check")
        let reasoned = FieldWriterScanner.DocumentedException(
            field: "Station.brand", reason: "no surface sets a brand; RV.115/RV.180 own it")
        #expect(FieldWriterScanner.reasonProblem(in: reasoned) == nil)
    }

    @Test func anExceptionForAFieldThatNowHasAWriterIsStale() {
        let sources = Self.stationSources(extra: [.init(
            path: "App/Sources/StationSettings/StationSettingsView.swift",
            contents: "station.favorite = favorite")])
        let stale = FieldWriterScanner.staleExceptions(
            schemaText: Self.stationSchema, sources: sources,
            exceptions: [.init(field: "Station.favorite", reason: "no longer true")])
        #expect(stale.contains("Station.favorite"),
                "an exception for a now-written field is stale - got \(stale)")
    }

    @Test func aFieldSpecForAHeadingTheDocNoLongerHasFails() {
        let stale = FieldWriterScanner.staleSpecHeadings(schemaText: "## Entities\n\n### Vehicle\n")
        #expect(stale.contains("Station"),
                "a field spec whose heading left the doc must be flagged stale - got \(stale)")
    }

    // MARK: - Fixtures

    private static let stationSchema = "## Entities\n\n### Station\n"

    private static func stationSources(
        extra: [FieldWriterScanner.SourceFile] = []) -> [FieldWriterScanner.SourceFile] {
        let domain = FieldWriterScanner.SourceFile(
            path: "Sources/TankbookCore/Domain/Entities.swift",
            contents: """
                public struct Station {
                    public var name: String
                    public var favorite: Bool
                }
                """)
        return [domain] + extra
    }
}
