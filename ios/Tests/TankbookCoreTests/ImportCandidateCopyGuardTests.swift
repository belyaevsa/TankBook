import Foundation
import Testing

// RV.170 (Half B) - the source-scan guard that every `ImportCandidate` copy
// helper round-trips every field. `RV.189` was the live case: the product
// owner's imported fills showed `92` instead of the station the file named,
// because `ImportBatchMerge.remappingSourceRow` rebuilt the candidate without
// `station` between the wire and the conversion. Every documented link held -
// the parser read the column, the wire carried it, the conversion stamped it,
// the commit materialised the row - and the value was dropped in between.
//
// A compiler cannot catch it because `ImportCandidate.init` DEFAULTS `station`
// to nil, so omitting it is legal. The four sibling helpers happened to pass
// it; the fifth did not. This guard is deliberately not keyed on `station`:
// it compares the init's own parameter list against what each construction
// passes, so the next field a helper drops is caught the same way.
//
// The oracle for every expectation is a source line, named at the call. The
// pre-RV.189 case is read from `git show e7a7a6c^` - the file as it was
// broken - not a synthetic fixture.
@Suite("Every ImportCandidate copy helper round-trips every field (RV.170)")
struct ImportCandidateCopyGuardTests {

    /// Helpers allowed to omit a field, with the reason. Empty today - the four
    /// siblings and the batch merge all pass every field - but the mechanism
    /// keeps a future deliberate omission a recorded decision. A bare entry
    /// fails the self-check and a stale one fails the walk.
    private static let documentedExceptions: [ImportCandidateCopyScanner.DocumentedException] = []

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
    private static func productionSources() throws -> [ImportCandidateCopyScanner.SourceFile] {
        var files: [ImportCandidateCopyScanner.SourceFile] = []
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

    private static func importCandidateInitFields() throws -> [String] {
        try ImportCandidateCopyScanner.initFields(
            in: source(under: "Sources/TankbookCore/", path: "Import/ImportModels.swift"))
    }

    /// The file as `RV.189` found it, read from history with `git show`.
    private static func preRV189BatchMerge() throws -> String {
        try gitShow("e7a7a6c^:ios/Sources/TankbookCore/Import/ImportBatchMerge.swift")
    }

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
            throw NSError(domain: "ImportCandidateCopyGuardTests",
                          code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "git show \(spec) failed"])
        }
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw NSError(domain: "ImportCandidateCopyGuardTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "git show \(spec) was not UTF-8"])
        }
        return text
    }

    // MARK: - L1: the real tree

    /// No production copy helper drops a field. The non-vacuity check beside it
    /// proves the scan parsed the init and saw a construction - an empty result
    /// from a scanner that looked at nothing is not a pass.
    @Test func everyProductionCopyHelperRoundTripsEveryField() throws {
        let fields = try Self.importCandidateInitFields()
        #expect(fields.contains("station"),
                "the init parse must expose station - a parse bug must not read as green")
        #expect(fields.count >= 15, "the init parse found only \(fields.count) fields")

        let merge = try Self.source(under: "Sources/TankbookCore/",
                                    path: "Import/ImportBatchMerge.swift")
        let sites = ImportCandidateCopyScanner.constructionSites(
            in: Array(EntityWriterScanner.masked(merge)))
        #expect(!sites.isEmpty, "the batch merge must construct a candidate, or this scan is vacuous")

        let findings = ImportCandidateCopyScanner.findings(
            in: try Self.productionSources(), initFields: fields,
            exceptions: Self.documentedExceptions)
        for exception in Self.documentedExceptions {
            if let problem = ImportCandidateCopyScanner.reasonProblem(in: exception) {
                Issue.record("exception self-check: \(problem)")
            }
        }
        for name in ImportCandidateCopyScanner.staleExceptions(
            findings: findings, exceptions: Self.documentedExceptions) {
            Issue.record("stale exception: \(name) no longer drops a field - remove the exception")
        }
        for finding in findings {
            let missing = finding.missing.joined(separator: ", ")
            Issue.record("""
                \(finding.path):\(finding.line) \(finding.helper) omits \(missing) from its \
                ImportCandidate copy. A copy helper must round-trip every field of the memberwise \
                init - RV.189 dropped `station` this way and the Log titled imported fills `92`. \
                Pass the missing field(s) through.
                """)
        }
    }

    // MARK: - L1: the calibration pair

    /// The miss: today's four sibling helpers all pass `station` and are not
    /// reported. Oracle: `applyingOdometer`, `applyingTotal`, `applyingCurrency`
    /// and `reDatingToDMY` in `ImportModels.swift`.
    @Test func todaySiblingHelpersAreNotReported() throws {
        let source = try Self.source(under: "Sources/TankbookCore/",
                                     path: "Import/ImportModels.swift")
        let findings = ImportCandidateCopyScanner.findings(
            in: [.init(path: "Sources/TankbookCore/Import/ImportModels.swift", contents: source)],
            initFields: try Self.importCandidateInitFields())
        #expect(findings.isEmpty,
                "the four sibling helpers all pass station - they must not be reported; got \(findings)")
    }

    /// The hit, against the REAL defect: the pre-RV.189 batch merge omitted
    /// `station`. Oracle: `git show e7a7a6c^` -> `ImportBatchMerge.swift` ->
    /// `remappingSourceRow`, the file as it was broken.
    @Test func thePreRV189BatchMergeIsReported() throws {
        let broken = try Self.preRV189BatchMerge()
        let findings = ImportCandidateCopyScanner.findings(
            in: [.init(path: "Sources/TankbookCore/Import/ImportBatchMerge.swift",
                       contents: broken)],
            initFields: try Self.importCandidateInitFields())
        let hit = findings.first { $0.helper == "remappingSourceRow" }
        #expect(hit != nil,
                "the pre-RV.189 remappingSourceRow must be reported - got \(findings)")
        #expect(hit?.missing == ["station"],
                "the reported field must be station - got \(String(describing: hit?.missing))")
    }

    /// The guard generalises beyond `station`: a helper that drops a different
    /// field is reported too. Oracle: the fixture omits `category`.
    @Test func aCopyHelperThatDropsANonStationFieldIsReported() throws {
        let fixture = """
            extension ImportCandidate {
                func applyingNote(_ note: String?) -> ImportCandidate {
                    ImportCandidate(entityType: entityType, date: date, odometer: odometer,
                                    volumeL: volumeL, unitPrice: unitPrice, money: money,
                                    fuelKind: fuelKind, isFull: isFull,
                                    tankLevelAfterPct: tankLevelAfterPct, note: note,
                                    vehicleName: vehicleName, provenance: provenance,
                                    sourceRow: sourceRow, station: station, items: items,
                                    title: title)
                }
            }
            """
        let findings = ImportCandidateCopyScanner.findings(
            in: [.init(path: "Sources/TankbookCore/Import/ImportModels.swift", contents: fixture)],
            initFields: try Self.importCandidateInitFields())
        #expect(findings.count == 1, "one omission must yield one finding - got \(findings)")
        #expect(findings.first?.missing == ["category"],
                "the omitted field is category, not station - got \(findings)")
    }

    /// A test seed that builds a candidate from scratch is not a copy host, so
    /// it is not reported: the guard must not teach everyone to allowlist seeds.
    @Test func aSeedConstructingACandidateIsNotReported() throws {
        let fixture = "let candidate = ImportCandidate(entityType: \"fillUp\", sourceRow: 1)"
        let findings = ImportCandidateCopyScanner.findings(
            in: [.init(path: "App/Sources/Import/ImportFlowModel+Seeds.swift", contents: fixture)],
            initFields: try Self.importCandidateInitFields())
        #expect(findings.isEmpty, "a seed is not a production copy host - got \(findings)")
    }

    // MARK: - L1: the reasoned-exception self-check

    @Test func aReasonlessExceptionFailsTheSelfCheck() {
        let bare = ImportCandidateCopyScanner.DocumentedException(
            helper: "applyingNote", field: "station", reason: " \n ")
        #expect(ImportCandidateCopyScanner.reasonProblem(in: bare) != nil,
                "an exception with no reason must fail the self-check")
        let reasoned = ImportCandidateCopyScanner.DocumentedException(
            helper: "applyingNote", field: "station",
            reason: "the note copy deliberately does not carry a station")
        #expect(ImportCandidateCopyScanner.reasonProblem(in: reasoned) == nil)
    }

    @Test func anExceptionForAFieldThatIsPassedAgainIsStale() {
        let findings = [ImportCandidateCopyScanner.Finding(
            path: "Sources/TankbookCore/Import/ImportModels.swift", line: 1,
            helper: "applyingOdometer", missing: ["category"])]
        let stale = ImportCandidateCopyScanner.staleExceptions(
            findings: findings,
            exceptions: [.init(helper: "applyingOdometer", field: "station",
                               reason: "used to be dropped")])
        #expect(stale == ["applyingOdometer.station"],
                "an exception for a field that is passed again is stale - got \(stale)")
    }
}
