import Foundation
import Testing

// PJ.63 - the RV.196 field guard could not see `TireSet` or `ServiceItem`,
// because neither was bound to a SCHEMA heading the scanner reads: `TireSet`
// had no `###` section at all and `ServiceItem` was documented only in prose
// under `ServiceRecord & Expense`. This suite is the calibration for the two
// newly-visible types. It lives in its own file so the original guard suite
// stays under the lint type-body ceiling.
@Suite("PJ.63: the newly-visible entities have a field guard")
struct SchemaFieldWriterGuardNewEntityTests {

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

    // MARK: - L1: the fields the headings exposed

    /// PJ.26 gave `purchaseExpenseId` a production writer
    /// (`TireSetPurchase.makeSet`, `TireSetPurchase.swift`), so the guard must
    /// stop reporting it. Oracle: the `.parts` expense path constructs a
    /// `TireSet` with `purchaseExpenseId: expense.id`. Before PJ.26 this same
    /// assertion failed - the guard reported the field.
    @Test func theTireSetPurchaseLinkIsNoLongerReported() throws {
        let unwritten = FieldWriterScanner.unwrittenFields(
            schemaText: try Self.schemaDoc(), sources: try Self.productionSources())
        #expect(!unwritten.contains("TireSet.purchaseExpenseId"),
                "the purchase link now has a production writer - it must not be reported. Got \(unwritten)")
    }

    /// Oracle: `TireSetDraft.build` passes `name`, and the item editor /
    /// `ServiceItem.make` pass `title`. A guard that flags every field of a
    /// newly-visible entity is mis-tuned; this pair proves it discriminates.
    @Test func theNewEntityCalibrationFieldsAreNotReported() throws {
        let unwritten = FieldWriterScanner.unwrittenFields(
            schemaText: try Self.schemaDoc(), sources: try Self.productionSources())
        #expect(!unwritten.contains("TireSet.name"),
                "TireSetDraft.build writes name - it must not be reported. Got \(unwritten)")
        #expect(!unwritten.contains("ServiceItem.title"),
                "the item editor writes title - it must not be reported. Got \(unwritten)")
    }

    /// Oracle: `ServiceItem.Lifetime` is constructed only by the decoder and the
    /// test seeds; no editor sets `km` or `months`, so both leaves report.
    @Test func theServiceItemLifetimeLeavesAreReportedBeforeAnyException() throws {
        let unwritten = FieldWriterScanner.unwrittenFields(
            schemaText: try Self.schemaDoc(), sources: try Self.productionSources())
        #expect(unwritten.contains("ServiceItem.lifetime.km"),
                "the lifetime editor is unbuilt (PJ.22) - km must be reported. Got \(unwritten)")
        #expect(unwritten.contains("ServiceItem.lifetime.months"),
                "the lifetime editor is unbuilt (PJ.22) - months must be reported. Got \(unwritten)")
    }

    // MARK: - L1: the stale-exception check on the new entries

    /// Give `purchaseExpenseId` a production writer and its exception must be
    /// flagged, so the list cannot rot once PJ.26 lands.
    @Test func theTireSetPurchaseExceptionGoesStaleWhenAWriterLands() {
        let sources = Self.tireSetSources(extra: [.init(
            path: "App/Sources/TireSets/TireSetFormView.swift",
            contents: "set.purchaseExpenseId = expense.id")])
        let stale = FieldWriterScanner.staleExceptions(
            schemaText: Self.tireSetSchema, sources: sources,
            exceptions: [.init(field: "TireSet.purchaseExpenseId", reason: "PJ.26 owns it")])
        #expect(stale.contains("TireSet.purchaseExpenseId"),
                "a writer must make the exception stale - got \(stale)")
    }

    /// Same for the lifetime leaves: a `Lifetime(km:)` construction in a
    /// production host makes `ServiceItem.lifetime.km`'s exception stale.
    @Test func theLifetimeExceptionGoesStaleWhenAnEditorLands() {
        let sources = Self.serviceItemSources(extra: [.init(
            path: "App/Sources/ServiceEntry/LifetimeEditor.swift",
            contents: "item.lifetime = ServiceItem.Lifetime(km: 15_000, months: nil)")])
        let stale = FieldWriterScanner.staleExceptions(
            schemaText: Self.serviceItemSchema, sources: sources,
            exceptions: [.init(field: "ServiceItem.lifetime.km", reason: "PJ.22 owns it")])
        #expect(stale.contains("ServiceItem.lifetime.km"),
                "a writer must make the exception stale - got \(stale)")
    }

    // MARK: - Fixtures

    private static let tireSetSchema = "## Entities\n\n### TireSet\n"

    private static func tireSetSources(
        extra: [FieldWriterScanner.SourceFile] = []) -> [FieldWriterScanner.SourceFile] {
        let domain = FieldWriterScanner.SourceFile(
            path: "Sources/TankbookCore/Domain/Entities.swift",
            contents: """
                public struct TireSet {
                    public var id: UUID
                    public var name: String
                    public var purchaseExpenseId: UUID?
                }
                """)
        return [domain] + extra
    }

    private static let serviceItemSchema = "## Entities\n\n### ServiceRecord & Expense\n"

    private static func serviceItemSources(
        extra: [FieldWriterScanner.SourceFile] = []) -> [FieldWriterScanner.SourceFile] {
        let domain = FieldWriterScanner.SourceFile(
            path: "Sources/TankbookCore/Domain/ServiceItem.swift",
            contents: """
                public struct ServiceItem {
                    public var title: String
                    public var partNumber: String?
                    public var lifetime: Lifetime?
                    public struct Lifetime {
                        public var km: Int?
                        public var months: Int?
                    }
                }
                """)
        return [domain] + extra
    }
}
