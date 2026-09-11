import Foundation
import Testing

// RV.164 - the source-scan guard behind `docs/ERRORS.md`'s fourth audit
// question: does the next step an error names EXIST? The three original
// questions (what happened, the preselected next step, what if ignored) never
// ask it, which is how `RV.98` shipped an alert promising a deleted car "moves
// to Recently deleted" while `RecentlyDeletedView` never queried deleted
// vehicles.
//
// The guard reads the REAL `docs/ERRORS.md` copy and checks every route it names
// after the doc's own `→` convention against the screens `docs/SCREENMAP.md`
// carries. It does NOT check that the named route behaves as promised - that is
// the stated residue, pinned by the RV.98 tests below and handled by the
// journey walk, never by this scan.
@Suite("Every route an error names exists in SCREENMAP (RV.164)")
struct ErrorRouteGuardTests {

    // MARK: - Source location

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
    }

    private static func doc(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// A `→`-introduced phrase that is deliberately not a SCREENMAP screen. One
    /// entry, with its reason: the Log is the Home tab root's entry stream, not a
    /// separate screen.
    private static let nonRoutes: [ErrorRouteScanner.NonRoute] = [
        .init(phrase: "Log filtered to flagged entries",
              reason: "the Log is the Home tab root's entry stream (SCREENMAP: Home), "
                  + "not a separate screen - a destination phrase, not a screen name")
    ]

    /// The screen vocabulary: every per-screen index row plus every screen the
    /// doc's machine-readable no-route marker carries (Paywall is the only one).
    private static func knownScreens(in screenMap: String) -> Set<String> {
        Set(ScreenRouteScanner.screenNames(in: screenMap))
            .union(ScreenRouteScanner.markedScreens(in: screenMap).map(\.screen))
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
            throw NSError(domain: "ErrorRouteGuardTests",
                          code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "git show \(spec) failed"])
        }
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw NSError(domain: "ErrorRouteGuardTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "git show \(spec) was not UTF-8"])
        }
        return text
    }

    /// The alert as `RV.98` found it, read from history - the exact sentence the
    /// guard's teeth are proven against, never a paraphrase.
    private static func preRV98DeleteAlert() throws -> String {
        try gitShow("dbd93bd8^:ios/App/Sources/VehicleDetail/VehicleDetailView.swift")
    }

    // MARK: - L1: the real doc

    /// Every route the real error catalog names after a `→` is a screen
    /// SCREENMAP carries, or a reasoned non-route. The non-vacuity checks beside
    /// it prove the scan parsed the doc and saw arrows - an empty result from a
    /// scanner that looked at nothing is not a pass.
    @Test func everyRouteNamedByErrorCopyExistsInScreenMap() throws {
        let screenMap = try Self.doc("docs/SCREENMAP.md")
        let errors = try Self.doc("docs/ERRORS.md")

        let screens = ScreenRouteScanner.screenNames(in: screenMap)
        #expect(screens.count >= 30,
                "the SCREENMAP parse found only \(screens.count) screens - a parse bug must not read as green")
        let known = Self.knownScreens(in: screenMap)
        #expect(known.contains("Recently deleted"),
                "the vocabulary must carry RV.98's promised route")

        let candidates = ErrorRouteScanner.routeCandidates(in: errors)
        #expect(candidates.contains("Welcome") && candidates.contains("Reminders"),
                "the arrow parse found \(candidates.count) phrases - a parse bug must not read as green")

        for nonRoute in Self.nonRoutes {
            if let problem = ErrorRouteScanner.reasonProblem(in: nonRoute) {
                Issue.record("non-route self-check: \(problem)")
            }
        }
        for phrase in ErrorRouteScanner.staleNonRoutes(Self.nonRoutes, candidates: candidates) {
            Issue.record("""
                stale non-route: "\(phrase)" no longer follows an arrow in docs/ERRORS.md - \
                remove it, or the entry hides the next unknown route.
                """)
        }

        for finding in ErrorRouteScanner.unknownRoutes(in: errors, knownScreens: known,
                                                       nonRoutes: Self.nonRoutes) {
            Issue.record("""
                docs/ERRORS.md:\(finding.line) names the next step "\(finding.route)", which is not a \
                screen docs/SCREENMAP.md carries and is not a reasoned non-route. RV.98 shipped this \
                shape: an alert promised "moves to Recently deleted" while no screen could deliver it. \
                Name a real route, or record the non-route in the scanner's reasoned list.
                """)
        }
    }

    // MARK: - L1: the teeth, against RV.98's real copy

    /// The scanner reads the route out of the REAL historical sentence - so the
    /// teeth are not a synthetic fixture. Oracle: `git show dbd93bd8^` ->
    /// `VehicleDetailView.swift` -> the delete alert.
    @Test func theScannerReadsTheRouteRV98Promised() throws {
        let alert = try Self.preRV98DeleteAlert()
        let known = Self.knownScreens(in: try Self.doc("docs/SCREENMAP.md"))
        #expect(ErrorRouteScanner.namedScreens(in: alert, knownScreens: known)
            .contains("Recently deleted"),
                "the scanner must read RV.98's promised route out of the historical alert")
    }

    /// The residue, pinned rather than overclaimed: RV.98's copy named a route
    /// that EXISTED, so the route scan passes it. What was missing was the car
    /// row inside the screen, which no route scan can see - the journey walk's
    /// manual check (REVIEW-SCENARIO question 5).
    @Test func theRouteCheckCannotSeeRV98sBehaviourGap() throws {
        let alert = try Self.preRV98DeleteAlert()
        let known = Self.knownScreens(in: try Self.doc("docs/SCREENMAP.md"))
        #expect(ErrorRouteScanner.unknownRoutes(in: alert, knownScreens: known).isEmpty,
                "RV.98's route existed; the guard must not claim it catches the behaviour gap")
    }

    /// The same real sentence with its destination renamed to a screen SCREENMAP
    /// does not carry IS reported - the teeth, shown on the historical copy's
    /// own words rather than a fabricated one.
    @Test func theSamePromiseWithAnUnknownRouteIsReported() throws {
        let alert = try Self.preRV98DeleteAlert()
            .replacingOccurrences(of: "Recently deleted", with: "Recently archived")
        let known = Self.knownScreens(in: try Self.doc("docs/SCREENMAP.md"))
        let findings = ErrorRouteScanner.unknownRoutes(in: alert, knownScreens: known)
        #expect(findings.count == 1, "one renamed route must yield one finding - got \(findings)")
        #expect(findings.first?.route.hasPrefix("Recently archived") == true,
                "the reported route must be the renamed destination - got \(findings)")
    }

    // MARK: - L1: the shape, not the one sentence

    /// The named mutation: a fake route name added to an error string is
    /// reported. This is the live-doc mutation the task runs and reports.
    @Test func aFakeRouteNameIsReported() {
        let copy = "Reminder due | Amber banner | View → Reminders · Check → Fake screen"
        let findings = ErrorRouteScanner.unknownRoutes(in: copy, knownScreens: ["Reminders"])
        #expect(findings.map(\.route) == ["Fake screen"],
                "an unknown route name must be reported - got \(findings)")
    }

    /// A known screen after the arrow passes, and a longer known name is not
    /// satisfied by a shorter one.
    @Test func knownScreensPassAndPrefixesDoNot() {
        #expect(ErrorRouteScanner.unknownRoutes(in: "tap → Edit entry",
                                                knownScreens: ["Edit entry"]).isEmpty)
        let findings = ErrorRouteScanner.unknownRoutes(in: "tap → Edit entryway",
                                                       knownScreens: ["Edit entry"])
        #expect(findings.map(\.route) == ["Edit entryway"],
                "a longer name must not be satisfied by a shorter known screen - got \(findings)")
    }

    /// Non-route shapes: a lowercase destination, a numeric arrow and a `.md`
    /// cross-reference are not routes.
    @Test func nonRouteShapesAreNotFlagged() {
        let copy = """
            Filled rows → a toast naming the count
            Consumption updated: 6.9 → 6.8 L/100km
            See docs/SCHEMA.md → Currency offer
            """
        #expect(ErrorRouteScanner.unknownRoutes(in: copy, knownScreens: []).isEmpty,
                "lowercase destinations, numbers and doc cross-references are not routes")
    }

    // MARK: - L1: the reasoned non-route self-check

    @Test func aReasonlessNonRouteFailsTheSelfCheck() {
        let bare = ErrorRouteScanner.NonRoute(phrase: "Log filtered to flagged entries", reason: " \n ")
        #expect(ErrorRouteScanner.reasonProblem(in: bare) != nil,
                "a non-route with no reason must fail the self-check")
    }

    @Test func aNonRouteThatLeftTheCopyIsStale() {
        let stale = ErrorRouteScanner.staleNonRoutes(
            [.init(phrase: "Log filtered to flagged entries", reason: "a destination phrase")],
            candidates: ["Welcome", "Reminders"])
        #expect(stale == ["Log filtered to flagged entries"],
                "a non-route no longer in the copy is stale - got \(stale)")
    }
}
