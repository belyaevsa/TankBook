import Foundation
import Testing

// RV.170 (Half A) - the source-scan guard that every production `Station(...)`
// construction flows through the one minting seam. `RV.156` was the shape from
// the other side: `upsertStation` was defined and called only by the import
// path and seeds, so PJ.19's ranking, RV.150's stamping and the Garage list all
// stood on a set no hand-typing user could populate. The fix gave the typed
// path a door, and RV.150 made a save stamp `lastUsedAt`/`defaults` on the row.
// A second construction path that skipped the seam would mint a station the
// ranking cannot rank - the same hole, freshly dug.
//
// The canonical seam, decided by the investigation this row demanded, is
// `ImportStationResolver.station(for:existing:now:)` in `ImportStation.swift`.
// `TankbookRepository.createStation` is a caller that routes through it, and
// `missingStations` (the import commit) calls it too; neither constructs a
// `Station`. The persistence decoder is not a creation path - it restores what
// was stored, the discrimination RV.196's field guard had to make.
//
// The scanner is `StationMintingScanner` (same target). The oracle for every
// expectation is a source line, named at the call.
@Suite("Every production Station is minted through the canonical seam (RV.170)")
struct StationMintingGuardTests {

    /// Paths allowed to construct a `Station`, with the reason. Empty today:
    /// the seam is allowed structurally (its own function) and the decoder is
    /// not a host. A future second legitimate site is recorded here, never
    /// silently allowed; a bare entry fails the self-check and a stale one
    /// fails the walk.
    private static let documentedExceptions: [StationMintingScanner.DocumentedException] = []

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
    private static func productionSources() throws -> [StationMintingScanner.SourceFile] {
        var files: [StationMintingScanner.SourceFile] = []
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

    // MARK: - L1: the real tree

    /// No production `Station(...)` construction sits outside the seam. The
    /// non-vacuity check beside it proves the scan actually saw the seam's own
    /// construction - an empty result from a scanner that looked at nothing is
    /// not a pass.
    @Test func everyStationConstructionIsInsideTheCanonicalSeam() throws {
        let sources = try Self.productionSources()
        let findings = StationMintingScanner.unmintedStations(
            in: sources, exceptions: Self.documentedExceptions)

        let seam = try Self.source(under: "Sources/TankbookCore/",
                                   path: "Import/ImportStation.swift")
        let seamHits = StationMintingScanner.stationConstructions(
            in: Array(EntityWriterScanner.masked(seam)))
        #expect(!seamHits.isEmpty,
                "the seam must construct a Station, or this scan is vacuous")

        for exception in Self.documentedExceptions {
            if let problem = StationMintingScanner.reasonProblem(in: exception) {
                Issue.record("exception self-check: \(problem)")
            }
        }
        for path in StationMintingScanner.staleExceptions(
            in: sources, exceptions: Self.documentedExceptions) {
            Issue.record("""
                stale exception: \(path) no longer constructs a Station outside the seam - \
                remove the exception
                """)
        }
        for finding in findings {
            Issue.record("""
                \(finding.path):\(finding.line) mints a Station outside the canonical seam. \
                Every station must flow through ImportStationResolver.station(for:existing:now:) \
                in ImportStation.swift, or the suggestion ranking cannot rank it (RV.156/RV.150). \
                Route the name through the resolver, or record a reasoned exception above.
                """)
        }
    }

    // MARK: - L1: the calibration pair

    /// The hit: a construction outside the seam is reported with `file:line`.
    /// Oracle: `App/Sources/Garage/QuickAddStation.swift:2`, a function that
    /// builds the row itself instead of resolving the name.
    @Test func aStationMintedOutsideTheSeamIsFlagged() {
        let sources = [StationMintingScanner.SourceFile(
            path: "App/Sources/Garage/QuickAddStation.swift",
            contents: """
                func quickAdd(name: String, now: Date) -> Station {
                    Station(id: UUID(), createdAt: now, name: name)
                }
                """)]
        let findings = StationMintingScanner.unmintedStations(in: sources)
        #expect(findings == [.init(path: "App/Sources/Garage/QuickAddStation.swift", line: 2)],
                "a Station built outside the seam must be reported with file:line - got \(findings)")
    }

    /// The miss: the seam's own construction is not reported. Oracle:
    /// `ImportStation.swift` -> `func station(...) -> Station { return Station(...) }`.
    @Test func theSeamItselfIsNotFlagged() {
        let sources = [StationMintingScanner.SourceFile(
            path: StationMintingScanner.seamPath,
            contents: """
                public static func station(for name: String, existing: [Station]) -> Station {
                    return Station(id: UUID(), name: name)
                }
                """)]
        let findings = StationMintingScanner.unmintedStations(in: sources)
        #expect(findings.isEmpty, "the canonical seam must not be flagged - got \(findings)")
    }

    /// The decoder and the repository's create door are not creation paths.
    /// Oracle: the decoder at `Records+Extras.swift:73` restores a stored row;
    /// `Repository+StationCreate.swift` only CALLS the resolver.
    @Test func theDecoderAndTheCreateDoorAreNotFlagged() throws {
        let decoder = try Self.source(under: "Sources/TankbookCore/",
                                      path: "Persistence/Records+Extras.swift")
        let createDoor = try Self.source(under: "Sources/TankbookCore/",
                                         path: "Persistence/Repository+StationCreate.swift")
        let findings = StationMintingScanner.unmintedStations(in: [
            .init(path: "Sources/TankbookCore/Persistence/Records+Extras.swift",
                  contents: decoder),
            .init(path: "Sources/TankbookCore/Persistence/Repository+StationCreate.swift",
                  contents: createDoor)
        ])
        #expect(findings.isEmpty,
                "the decoder restores and the create door routes through the resolver; got \(findings)")
    }

    /// The seam is a function, not a file: a second construction in the same
    /// file but a different function is still a second path.
    @Test func aSecondConstructionInTheSeamFileIsFlagged() {
        let sources = [StationMintingScanner.SourceFile(
            path: StationMintingScanner.seamPath,
            contents: """
                public static func station(for name: String) -> Station {
                    return Station(id: UUID(), name: name)
                }

                static func sneaky(name: String) -> Station {
                    return Station(id: UUID(), name: name)
                }
                """)]
        let findings = StationMintingScanner.unmintedStations(in: sources)
        #expect(findings == [.init(path: StationMintingScanner.seamPath, line: 6)],
                "only the seam function may construct - got \(findings)")
    }

    /// A test seed that constructs a `Station` is not a host, so it is not
    /// reported: the guard must not teach everyone to allowlist seeds.
    @Test func aSeedConstructingAStationIsNotFlagged() {
        let sources = [StationMintingScanner.SourceFile(
            path: "App/Sources/Home/HomeTestSeed.swift",
            contents: "let station = Station(name: \"Shell\")")]
        #expect(StationMintingScanner.unmintedStations(in: sources).isEmpty,
                "a test seed is not a production host and must not be flagged")
    }

    // MARK: - L1: the reasoned-exception self-check

    @Test func aReasonlessExceptionFailsTheSelfCheck() {
        let bare = StationMintingScanner.DocumentedException(
            path: "App/Sources/Garage/QuickAddStation.swift", reason: " \n ")
        #expect(StationMintingScanner.reasonProblem(in: bare) != nil,
                "an exception with no reason must fail the self-check")
        let reasoned = StationMintingScanner.DocumentedException(
            path: "App/Sources/Garage/QuickAddStation.swift",
            reason: "a documented second minting site with its own reason")
        #expect(StationMintingScanner.reasonProblem(in: reasoned) == nil)
    }

    @Test func anExceptionThatNoLongerMintsIsStale() {
        let sources = [StationMintingScanner.SourceFile(
            path: "App/Sources/Garage/QuickAddStation.swift",
            contents: "func quickAdd() { print(\"nothing\") }")]
        let stale = StationMintingScanner.staleExceptions(
            in: sources,
            exceptions: [.init(path: "App/Sources/Garage/QuickAddStation.swift",
                               reason: "used to mint a station")])
        #expect(stale == ["App/Sources/Garage/QuickAddStation.swift"],
                "an exception whose site no longer mints is stale - got \(stale)")
    }
}
