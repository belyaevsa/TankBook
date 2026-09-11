import Foundation
import Testing

// RV.171 - the source-scan guard that a scanned save binds its attachment,
// provenance and `purchaseGroupId` through the one canonical seam. Three rows
// in one family is the argument: `PJ.28` fixed the expense scan, its fence
// stopped there, `RV.149` had to be filed for the fill-up, and `RV.149` fenced
// out the grouped case, so `RV.173` had to be filed for the expense siblings.
// Each fix was correct and each left the next copy unprotected.
//
// **The canonical seam is `ScannedSavePlan.binding(_:)` + `expenses(from:)`** -
// decided by the investigation this row demanded and recorded in
// `ReceiptBindingScanner` and `docs/TESTING.md`. `binding(_:)` rebinds the plan
// to the id the photo write actually produced (`ReceiptWriteOutcome.sharedID`);
// `expenses(from:)` is the one place that stamps attachment + provenance +
// `purchaseGroupId` onto the group's rows. The investigation found exactly one
// production `.expenses(from:)` call site and it is bound; the single-expense
// scan is a distinct, non-group shape (one row, one write, id from the return).
//
// The scanner is `ReceiptBindingScanner` (same target). The strongest evidence
// here is against real history: the pre-fix `RV.149` and `RV.173` trees are read
// with `git show <sha>:<path>` and the scanner reports the unbound row builder.
// The oracle for every expectation is a source line, named at the call.
@Suite("Every scanned save binds through the canonical receipt seam (RV.171)")
struct ReceiptBindingGuardTests {

    /// Sites allowed to bind outside the seam, with the reason. Empty today: the
    /// seam is allowed structurally, the single-expense scan is not a group
    /// binding, and the typed-attach inits carry `.manual` provenance. A bare
    /// entry fails the self-check and a stale one fails the walk.
    private static let documentedExceptions: [ReceiptBindingScanner.DocumentedException] = []

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

    private static func source(under prefix: String, path: String) throws -> String {
        let root = try #require(scannedRoots.first { prefix.hasPrefix($0.prefix) }?.url,
                                "no scanned root for \(prefix)")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every Swift file under both source roots, tagged the way the scanner's
    /// host rules read the path.
    private static func productionSources() throws -> [ReceiptBindingScanner.SourceFile] {
        var files: [ReceiptBindingScanner.SourceFile] = []
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

    /// The file as a named commit left it, read from history with `git show`.
    private static func gitShow(_ spec: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "show", spec]
        process.currentDirectoryURL = repoRoot
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ReceiptBindingGuardTests",
                          code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "git show \(spec) failed"])
        }
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw NSError(domain: "ReceiptBindingGuardTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "git show \(spec) was not UTF-8"])
        }
        return text
    }

    // MARK: - L1: the real tree

    /// No production binding bypasses the seam. The non-vacuity check beside it
    /// proves the scan actually saw the canonical bound row builder - an empty
    /// result from a scanner that looked at nothing is not a pass.
    @Test func everyProductionReceiptBindingFlowsThroughTheSeam() throws {
        let sources = try Self.productionSources()
        let findings = ReceiptBindingScanner.findings(in: sources,
                                                      exceptions: Self.documentedExceptions)

        let save = try Self.source(under: "App/Sources/",
                                   path: "ConfirmManual/ManualFillUpView.swift")
        let rowBuilders = ReceiptBindingScanner.memberCallOpenParens(
            named: ReceiptBindingScanner.rowBuilderFunction,
            in: Array(EntityWriterScanner.masked(save)))
        #expect(!rowBuilders.isEmpty,
                "the grouped save must build rows, or this scan is vacuous")

        for exception in Self.documentedExceptions {
            if let problem = ReceiptBindingScanner.reasonProblem(in: exception) {
                Issue.record("exception self-check: \(problem)")
            }
        }
        for name in ReceiptBindingScanner.staleExceptions(
            in: sources, exceptions: Self.documentedExceptions) {
            Issue.record("""
                stale exception: \(name) no longer bypasses the seam - remove the exception
                """)
        }
        for finding in findings {
            Issue.record("""
                \(finding.path):\(finding.line) \(finding.function) binds a receipt outside the \
                canonical seam (\(finding.kind.rawValue)). Every scanned save must bind its rows \
                through ScannedSavePlan.binding(receiptWrite.sharedID).expenses(from:), so the \
                attachment id, the provenance and the purchaseGroupId travel together - RV.173 \
                left an unbound copy and the group kept a dangling id. Route the binding through \
                the seam, or record a reasoned exception above.
                """)
        }
    }

    // MARK: - L1: the calibration pair

    /// The miss: today's grouped save is bound, so it is not reported. Oracle:
    /// `ManualFillUpView.swift` -> `save()` -> `let bound = scanned.binding(...)`
    /// and `bound.expenses(from:)`.
    @Test func todayGroupedSaveIsNotReported() throws {
        let source = try Self.source(under: "App/Sources/",
                                     path: "ConfirmManual/ManualFillUpView.swift")
        let findings = ReceiptBindingScanner.findings(
            in: [.init(path: "App/Sources/ConfirmManual/ManualFillUpView.swift",
                       contents: source)])
        #expect(findings.isEmpty,
                "the bound grouped save is canonical and must not be reported; got \(findings)")
    }

    /// The hit, against REAL history: the pre-RV.173 grouped save built its rows
    /// from the plan's intended id, so a lost photo left the expenses dangling.
    /// Oracle: `git show c6df797^` -> `ManualFillUpView.swift` -> `save()`, the
    /// file as it was broken.
    @Test func thePreRV173GroupedSaveIsReported() throws {
        let broken = try Self.gitShow(
            "c6df797^:ios/App/Sources/ConfirmManual/ManualFillUpView.swift")
        let findings = ReceiptBindingScanner.findings(
            in: [.init(path: "App/Sources/ConfirmManual/ManualFillUpView.swift",
                       contents: broken)])
        let hit = findings.first { $0.kind == .unboundRowBuilder && $0.function == "save" }
        #expect(hit != nil,
                "the pre-RV.173 unbound row builder must be reported - got \(findings)")
        #expect(hit?.path == "App/Sources/ConfirmManual/ManualFillUpView.swift")
    }

    /// The hit, against REAL history: the same unbound builder was live when
    /// RV.149 shipped - its fix fenced out the grouped case, which is why
    /// RV.173 had to be filed. Oracle: `git show 0044e04^` -> `ManualFillUpView.swift`.
    @Test func thePreRV149GroupedSaveIsReported() throws {
        let broken = try Self.gitShow(
            "0044e04^:ios/App/Sources/ConfirmManual/ManualFillUpView.swift")
        let findings = ReceiptBindingScanner.findings(
            in: [.init(path: "App/Sources/ConfirmManual/ManualFillUpView.swift",
                       contents: broken)])
        #expect(findings.contains { $0.kind == .unboundRowBuilder && $0.function == "save" },
                "the grouped builder was unbound when RV.149 shipped - got \(findings)")
    }

    /// The pre-PJ.28 expense scan is a DIFFERENT shape and is recorded as a
    /// coverage limit rather than papered over. That defect was
    /// `attachments: []` on a path that never built a `ScannedSavePlan` at all -
    /// one row, one write, no group - so there is no binding seam here to bind
    /// through. It is a runtime degrade decision (report the loss and keep the
    /// entry), not a binding site, and it was fixed by PJ.28/RV.149. The guard
    /// covers the GROUPED binding seam RV.173 settled. Oracle:
    /// `git show 8005181^` -> `ExpenseEntryView.swift` -> `save()`.
    @Test func thePrePJ28ExpenseScanIsADifferentShapeNotCoveredHere() throws {
        let broken = try Self.gitShow(
            "8005181^:ios/App/Sources/ServiceEntry/ExpenseEntryView.swift")
        let findings = ReceiptBindingScanner.findings(
            in: [.init(path: "App/Sources/ServiceEntry/ExpenseEntryView.swift",
                       contents: broken)])
        #expect(findings.isEmpty,
                "the single-expense scan is not a group binding; this guard does not cover it - \(findings)")
    }

    /// The guard is not fooled by the mere presence of `.binding(`: binding the
    /// plan to its OWN intended id is RV.173's defect restored, and it is
    /// reported. Oracle: the fixture binds `scanned.attachmentID`, not the write
    /// outcome's `sharedID`.
    @Test func bindingToThePlansOwnIDIsNotTheSeam() {
        let fixture = """
            func save() {
                let bound = scanned.binding(scanned.attachmentID)
                let rows = bound.expenses(from: plan, vehicleId: vehicle.id, date: now,
                                          createdAt: now) { amount in money(amount) }
                for row in rows { try repository.upsertExpense(row) }
            }
            """
        let findings = ReceiptBindingScanner.findings(
            in: [.init(path: "App/Sources/ConfirmManual/ManualFillUpView.swift",
                       contents: fixture)])
        #expect(findings.contains { $0.kind == .unboundRowBuilder && $0.function == "save" },
                "binding to the plan's own id must be reported - got \(findings)")
    }

    /// A second binding site - a hand-rolled plan that carries a scan provenance
    /// outside the factory/rebind - is reported. Oracle: the fixture's direct
    /// `ScannedSavePlan(provenance: .receiptScan)`.
    @Test func aSecondScanBindingSiteIsReported() {
        let fixture = """
            func saveScanned() {
                let plan = ScannedSavePlan(attachmentID: id, provenance: .receiptScan,
                                           extraction: meta)
                let row = Expense(attachments: plan.sharedAttachmentIDs,
                                  provenance: .receiptScan)
            }
            """
        let findings = ReceiptBindingScanner.findings(
            in: [.init(path: "App/Sources/ConfirmManual/NewScannedSave.swift",
                       contents: fixture)])
        #expect(findings.contains { $0.kind == .secondBindingSite && $0.function == "saveScanned" },
                "a second scan binding site must be reported - got \(findings)")
    }

    /// A typed attach binds `.manual` provenance and is not a scanned save, so
    /// its direct construction is not reported. Oracle: the shape in
    /// `EditEntryView+NonFillSave.swift:113`.
    @Test func aTypedAttachIsNotReported() {
        let fixture = """
            func writeNonFillWithHeldReceipt() {
                let plan = ScannedSavePlan(attachmentID: UUID.v7(), provenance: .manual,
                                           extraction: assignment)
            }
            """
        let findings = ReceiptBindingScanner.findings(
            in: [.init(path: "App/Sources/EditEntry/EditEntryView+NonFillSave.swift",
                       contents: fixture)])
        #expect(findings.isEmpty,
                "a typed attach is not a scanned save and must not be reported - got \(findings)")
    }

    /// A test seed that builds a binding is not a host, so it is not reported:
    /// the guard must not teach everyone to allowlist seeds.
    @Test func aSeedConstructingABindingIsNotReported() {
        let fixture = """
            func seed() {
                let rows = scanned.expenses(from: plan, vehicleId: id, date: now,
                                            createdAt: now) { money($0) }
                let plan = ScannedSavePlan(attachmentID: id, provenance: .receiptScan,
                                           extraction: nil)
            }
            """
        let findings = ReceiptBindingScanner.findings(
            in: [.init(path: "App/Sources/ConfirmManual/ManualFillUpTestSeed.swift",
                       contents: fixture)])
        #expect(findings.isEmpty, "a seed is not a production host - got \(findings)")
    }

    /// A binding that exists only under `#if DEBUG` is masked before the scan,
    /// so it cannot satisfy - or violate - the guard.
    @Test func aDebugOnlyBindingIsNotReported() {
        let fixture = """
            func save() {
                #if DEBUG
                let rows = scanned.expenses(from: plan, vehicleId: id, date: now,
                                            createdAt: now) { money($0) }
                #endif
            }
            """
        let findings = ReceiptBindingScanner.findings(
            in: [.init(path: "App/Sources/ConfirmManual/ManualFillUpView.swift",
                       contents: fixture)])
        #expect(findings.isEmpty, "a DEBUG-only binding is not production code - got \(findings)")
    }

    // MARK: - L1: the reasoned-exception self-check

    @Test func aReasonlessExceptionFailsTheSelfCheck() {
        let bare = ReceiptBindingScanner.DocumentedException(
            path: "App/Sources/ConfirmManual/NewSave.swift", function: "save",
            reason: " \n ")
        #expect(ReceiptBindingScanner.reasonProblem(in: bare) != nil,
                "an exception with no reason must fail the self-check")
        let reasoned = ReceiptBindingScanner.DocumentedException(
            path: "App/Sources/ConfirmManual/NewSave.swift", function: "save",
            reason: "a documented second binding site with its own reason")
        #expect(ReceiptBindingScanner.reasonProblem(in: reasoned) == nil)
    }

    @Test func anExceptionThatNoLongerBindsIsStale() {
        let sources = [ReceiptBindingScanner.SourceFile(
            path: "App/Sources/ConfirmManual/NewSave.swift",
            contents: "func save() { let x = 1 }")]
        let stale = ReceiptBindingScanner.staleExceptions(
            in: sources,
            exceptions: [.init(path: "App/Sources/ConfirmManual/NewSave.swift", function: "save",
                               reason: "used to bind a plan by hand")])
        #expect(stale == ["App/Sources/ConfirmManual/NewSave.swift:save"],
                "an exception whose site no longer bypasses the seam is stale - got \(stale)")
    }
}
