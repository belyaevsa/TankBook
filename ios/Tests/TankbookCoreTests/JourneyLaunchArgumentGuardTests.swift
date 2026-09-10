import Foundation
import Testing

// RV.165 - the source-scan guard that the cold-launch journey suite walks the
// view graph instead of teleporting into it. The rest of the UI suite passes
// `-presentScreen`/`-openFirst*`/`-select*Tab`/seeds, so a test that STARTS
// inside a screen can never discover that the screen is unreachable - the exact
// blind spot that let PJ.4 ship a Reminders screen whose only route was
// `#if DEBUG`. The journeys are only worth their cost while they keep tapping.
//
// The guard is a pure function over source text (`JourneyLaunchArgumentScanner`)
// so a fixture can be fed to it the way RV.162/RV.163's scanners take text. It
// masks comments, extracts string literals, and fails on any navigation seed
// (`-presentScreen`, any other `-present*` except the fresh-install
// `-presentWelcome`, `-openFirst*`, `-select*Tab`) or any flag not on the
// reasoned allowlist. A bare allowlist entry fails the guard's own self-check,
// and an entry the suite no longer uses is stale and fails too.
@Suite("Journey launch arguments are never navigation seeds (RV.165)")
struct JourneyLaunchArgumentGuardTests {

    // MARK: - Source location

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
    }

    /// Every journey suite file under `ios/App/UITests`. A new journey file is
    /// covered the moment it is named `*Journey*`.
    private static func journeySources() throws -> [JourneyLaunchArgumentScanner.SourceFile] {
        let directory = repoRoot.appendingPathComponent("ios/App/UITests")
        let manager = FileManager.default
        let names = try manager.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") && $0.contains("Journey") }
            .sorted()
        return try names.map { name in
            let url = directory.appendingPathComponent(name)
            return .init(path: "App/UITests/\(name)",
                         contents: try String(contentsOf: url, encoding: .utf8))
        }
    }

    // MARK: - L1: the tree walk

    /// The real suite passes: every flag it passes is either allowlisted or
    /// absent, and no navigation seed is present. The failure names the file
    /// and line, so the person who sees it knows which tap to restore.
    @Test func theRealJourneySuitePassesTheGuard() throws {
        let sources = try Self.journeySources()
        #expect(!sources.isEmpty,
                "no journey suite file was found - a parse bug must not read as green")
        #expect(sources.contains { $0.path.contains("ColdLaunchJourneyUITests") },
                "the scan must see the cold-launch journey suite")

        for allowed in JourneyLaunchArgumentScanner.allowedFlags {
            if let problem = JourneyLaunchArgumentScanner.reasonProblem(in: allowed) {
                Issue.record("allowlist self-check: \(problem)")
            }
        }
        for stale in JourneyLaunchArgumentScanner.staleAllowlistEntries(
            in: JourneyLaunchArgumentScanner.allowedFlags,
            usedArguments: JourneyLaunchArgumentScanner.usedArguments(in: sources)) {
            Issue.record("""
                stale allowlist entry: \(stale) is permitted but no journey passes it - remove it, \
                or a future journey inherits a hole.
                """)
        }

        for violation in JourneyLaunchArgumentScanner.violations(in: sources) {
            Issue.record("""
                \(violation.path):\(violation.line): \(violation.argument) is a navigation seed, \
                not a journey step. \(violation.reason). Walk the screen by tapping, or record a \
                reasoned data/environment entry in the allowlist.
                """)
        }
    }

    // MARK: - L1: the named mutation's shape

    /// A planted `-presentScreen` in a journey test must fail the guard - a
    /// guard that only scanned for `-openFirst*`, say, would walk past it.
    @Test func aPlantedPresentScreenFails() {
        let violations = JourneyLaunchArgumentScanner.violations(in: [
            .init(path: "App/UITests/SomeJourneyUITests.swift",
                  contents: #"app.launchArguments = ["-presentScreen", "editEntry"]"#)
        ])
        #expect(violations.map(\.argument) == ["-presentScreen"],
                "a planted -presentScreen must fail - got \(violations)")
        #expect(violations.first?.line == 1)
    }

    /// Every named navigation pattern fails, not just `-presentScreen`.
    @Test func everyNavigationSeedPatternFails() {
        let cases: [(String, String)] = [
            (#"app.launchArguments = ["-openFirstFlaggedEdit"]"#, "-openFirstFlaggedEdit"),
            (#"app.launchArguments = ["-selectTrendsTab"]"#, "-selectTrendsTab"),
            (#"app.launchArguments = ["-presentScreen", "about"]"#, "-presentScreen"),
            (#"app.launchArguments = ["-presentExportShare"]"#, "-presentExportShare")
        ]
        for (source, expected) in cases {
            let violations = JourneyLaunchArgumentScanner.violations(
                in: [.init(path: "App/UITests/SomeJourneyUITests.swift", contents: source)])
            #expect(violations.map(\.argument) == [expected],
                    "\(expected) must fail - got \(violations)")
        }
    }

    /// A `-seed*` flag the allowlist does not carry fails; the same shape with
    /// a reasoned allowlist entry passes.
    @Test func anUnallowlistedSeedFailsAndAnAllowlistedOnePasses() {
        let source = #"app.launchArguments = ["-seedHomeFullHistory"]"#
        let violations = JourneyLaunchArgumentScanner.violations(
            in: [.init(path: "App/UITests/SomeJourneyUITests.swift", contents: source)])
        #expect(violations.map(\.argument) == ["-seedHomeFullHistory"],
                "an unallowlisted seed must fail - got \(violations)")

        let allowed = [JourneyLaunchArgumentScanner.AllowedFlag(
            flag: "-seedHomeFullHistory", reason: "500 fill-ups cannot be typed", isDataVolume: true)]
        let clean = JourneyLaunchArgumentScanner.violations(
            in: [.init(path: "App/UITests/SomeJourneyUITests.swift", contents: source)],
            allowed: allowed)
        #expect(clean.isEmpty, "an allowlisted data-volume seed must pass - got \(clean)")
    }

    /// An allowlist entry with no reason fails the guard's own self-check: a
    /// list without reasons degrades into a skip list.
    @Test func aBlankReasonFailsTheSelfCheck() {
        let bare = JourneyLaunchArgumentScanner.AllowedFlag(
            flag: "-seedSomething", reason: " \n ", isDataVolume: true)
        #expect(JourneyLaunchArgumentScanner.reasonProblem(in: bare) != nil,
                "a blank reason must fail the self-check")
    }

    /// A commented-out forbidden flag is prose, not a call site: masking
    /// comments is what keeps the guard from failing on its own documentation.
    @Test func aCommentedNavigationSeedIsNotACallSite() {
        let source = """
            // the old suite used -presentScreen editEntry
            /* app.launchArguments = ["-selectGarageTab"] */
            app.launchArguments = ["-homeResetDatabase"]
            """
        let violations = JourneyLaunchArgumentScanner.violations(
            in: [.init(path: "App/UITests/SomeJourneyUITests.swift", contents: source)])
        #expect(violations.isEmpty, "commented prose must not fail the guard - got \(violations)")
    }

    /// The allowlist's own hygiene: an entry no journey uses is stale.
    @Test func anUnusedAllowlistEntryIsStale() {
        let allowed = [JourneyLaunchArgumentScanner.AllowedFlag(
            flag: "-seedUnused", reason: "no journey passes it", isDataVolume: true)]
        let stale = JourneyLaunchArgumentScanner.staleAllowlistEntries(
            in: allowed, usedArguments: ["-homeResetDatabase"])
        #expect(stale == ["-seedUnused"], "an unused entry must be reported stale - got \(stale)")
    }

    /// A value argument (`(ru)`, a fixture path) is not a flag and never fails.
    @Test func valueArgumentsAreNotFlags() {
        let source = #"app.launchArguments = ["-unknownFlag", "(ru)", "/tmp/x.png"]"#
        let violations = JourneyLaunchArgumentScanner.violations(
            in: [.init(path: "App/UITests/SomeJourneyUITests.swift", contents: source)])
        #expect(violations.map(\.argument) == ["-unknownFlag"],
                "only the flag should be considered - got \(violations)")
    }
}
