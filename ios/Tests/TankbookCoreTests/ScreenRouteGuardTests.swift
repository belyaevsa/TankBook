import Foundation
import Testing

// RV.162 - the source-scan guard that every screen docs/SCREENMAP.md lists has
// a non-DEBUG production door. `PJ.4` shipped the Reminders screen whose only
// route was gated on a DEBUG flag, so no Release user could open it, while the
// UI suite stayed green - it navigates through `-presentScreen`, a DEBUG launch
// argument, so every screen is reachable TO A TEST whether or not it is
// reachable to a user. `PJ.25` (the shelf reachable only mid-service) and
// `PJ.20` (copy routing to a screen that did not exist) are the same shape.
//
// The guard is a pure function over the doc and source text
// (`ScreenRouteScanner`), so a test can feed it a hand-written doc string the
// way RV.167's scanner takes source text. The per-screen index is the list; a
// screen -> door-witness binding table (each entry annotated) plus the doc's
// machine-readable no-route marker are the routes. A DEBUG-wrapped door removes
// its witness because `#if DEBUG` regions and `DebugLaunch.swift` are masked.
//
// THE REACHABILITY DEPTH THIS ACTUALLY CHECKS, stated so it is not overclaimed:
// it proves a non-DEBUG production door names the screen. It does NOT walk the
// view graph, so a door on a screen that is itself unreachable from a tab root
// would still pass, and a door guarded by a runtime condition that can never be
// true would pass too. That is strictly stronger than "referenced somewhere"
// (the door must be a real NavigationLink/presentation in production code) and
// strictly weaker than "a user can reach it by tapping". `PJ.25`'s original
// shape - reachable only from inside a service entry - is caught here only
// because the pushed Vehicle-detail door is the one the binding names.
@Suite("Every SCREENMAP screen has a non-DEBUG production route (RV.162)")
struct ScreenRouteGuardTests {

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

    private static func screenMapDoc() throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent("docs/SCREENMAP.md"), encoding: .utf8)
    }

    /// Every Swift file under both source roots, tagged the way the scanner's
    /// host rules read the path.
    private static func productionSources() throws -> [ScreenRouteScanner.SourceFile] {
        var files: [ScreenRouteScanner.SourceFile] = []
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

    /// Every screen in the real per-screen index has a non-DEBUG production
    /// door, or is recorded in the doc's machine-readable no-route marker. The
    /// failure names the screen, so the person who sees it knows which door is
    /// missing rather than just that the map drifted.
    @Test func everyScreenMapScreenHasANonDebugProductionDoor() throws {
        let doc = try Self.screenMapDoc()
        let sources = try Self.productionSources()

        let screens = ScreenRouteScanner.screenNames(in: doc)
        #expect(screens.count >= 30,
                "the doc parse found only \(screens.count) screens - a parse bug must not read as green")
        #expect(screens.contains("Reminders"),
                "the parse must see the historical positive case (PJ.4's Reminders)")

        for binding in ScreenRouteScanner.bindings {
            if let problem = ScreenRouteScanner.noteProblem(in: binding) {
                Issue.record("binding self-check: \(problem)")
            }
        }
        for marker in ScreenRouteScanner.markedScreens(in: doc) {
            if let problem = ScreenRouteScanner.reasonProblem(in: marker) {
                Issue.record("marker self-check: \(problem)")
            }
        }
        for screen in ScreenRouteScanner.staleBindings(in: doc) {
            Issue.record("""
                stale binding: \(screen) is bound to a door but is no longer a row of the \
                per-screen index - the screen was renamed or removed. Update the table deliberately.
                """)
        }
        for screen in ScreenRouteScanner.staleMarkers(in: doc) {
            Issue.record("""
                stale marker: \(screen) is marked as having no route but the doc no longer names it \
                anywhere else - the screen left the map.
                """)
        }

        for screen in ScreenRouteScanner.unreachableScreens(doc: doc, sources: sources) {
            Issue.record("""
                \(screen) has no non-DEBUG production door. A route inside #if DEBUG, in \
                DebugLaunch.swift or in a test seed does not count - PJ.4's Reminders was reachable \
                to every UI test and to no Release user. Give the screen a real NavigationLink / \
                presentation in production code, or record it in the doc's "Screens with no \
                production route" marker with its reason.
                """)
        }
    }

    // MARK: - L1: the shape, not the one line (the named mutation)

    /// Reconstructs PJ.4: the Reminders route exists and compiles, but its only
    /// door is wrapped in `#if DEBUG`. The scanner must report `Reminders` - a
    /// scanner that counted the DEBUG route would pass on the exact defect this
    /// row exists for. The live-tree mutation is run and reported separately.
    @Test func aDebugWrappedDoorDoesNotCount() {
        let sources = [
            ScreenRouteScanner.SourceFile(
                path: "App/Sources/Home/HomeBanners.swift",
                contents: """
                    #if DEBUG
                    NavigationLink(value: Route.reminders) { Text("Reminders") }
                    #endif
                    """)
        ]
        let unreachable = ScreenRouteScanner.unreachableScreens(doc: Self.remindersOnlyDoc, sources: sources)
        #expect(unreachable == ["Reminders"],
                "a #if DEBUG door is not a production route - got \(unreachable)")
    }

    /// The same door outside the DEBUG region is a production route and passes.
    @Test func aProductionDoorCounts() {
        let sources = [
            ScreenRouteScanner.SourceFile(
                path: "App/Sources/Home/HomeBanners.swift",
                contents: "NavigationLink(value: Route.reminders) { Text(\"Reminders\") }")
        ]
        let unreachable = ScreenRouteScanner.unreachableScreens(doc: Self.remindersOnlyDoc, sources: sources)
        #expect(unreachable.isEmpty, "a production door must pass - got \(unreachable)")
    }

    /// `Route.reminders` must not be satisfied by `Route.remindersAll` - a
    /// substring match would let the merged list's door stand in for the
    /// per-car one.
    @Test func aSuffixMatchIsNotTheDoor() {
        let sources = [
            ScreenRouteScanner.SourceFile(
                path: "App/Sources/Home/HomeBanners.swift",
                contents: "NavigationLink(value: Route.remindersAll) { Text(\"Reminders\") }")
        ]
        let unreachable = ScreenRouteScanner.unreachableScreens(doc: Self.remindersOnlyDoc, sources: sources)
        #expect(unreachable == ["Reminders"],
                "Route.remindersAll must not stand in for Route.reminders - got \(unreachable)")
    }

    // MARK: - L1: the marker is the recorded exception

    /// A screen the doc marks as having no production route does not fail, and
    /// the reason is carried, not discarded.
    @Test func aMarkedScreenDoesNotFail() {
        let unreachable = ScreenRouteScanner.unreachableScreens(
            doc: Self.markedDoc, sources: [])
        #expect(unreachable.isEmpty, "a marked screen must pass - got \(unreachable)")
        #expect(ScreenRouteScanner.markedScreens(in: Self.markedDoc).first?.reason.isEmpty == false)
    }

    /// A marker entry with no reason fails the guard's own self-check: a list
    /// without reasons degrades into a skip list.
    @Test func aReasonlessMarkerFailsTheSelfCheck() {
        let marker = ScreenRouteScanner.MarkedScreen(screen: "Paywall", reason: " \n ")
        #expect(ScreenRouteScanner.reasonProblem(in: marker) != nil,
                "a marker with no reason must fail the self-check")
    }

    // MARK: - L1: a new screen with no route fails

    /// Adding a screen to the per-screen index without a door and without a
    /// marker is the `PJ.20` shape; the scanner must report it. The doc is fed
    /// as a string, so this is testable without editing the real map.
    @Test func aNewScreenWithNoRouteFails() {
        let unreachable = ScreenRouteScanner.unreachableScreens(
            doc: Self.newScreenDoc, sources: [])
        #expect(unreachable == ["Warp Drive"],
                "a new indexed screen with no door and no marker must fail - got \(unreachable)")
    }

    // MARK: - Fixtures

    /// A minimal per-screen index carrying only Reminders.
    private static let remindersOnlyDoc = """
        ## Per-screen index

        | Screen | Reached from | Forward exits | Back path |
        |---|---|---|---|
        | Reminders | Home banner, VehicleDetail | complete → ReminderComplete | back → opener |

        ## Next
        """

    /// The same index, plus a machine-readable no-route marker.
    private static let markedDoc = """
        ## Per-screen index

        | Screen | Reached from | Forward exits | Back path |
        |---|---|---|---|
        | Warp Drive | nowhere yet | none | none |

        ### Screens with no production route

        | Screen | Reason |
        |---|---|
        | Warp Drive | a planned [v2] screen with no v1 door by design |

        ## Next
        """

    /// A new indexed screen with no binding and no marker.
    private static let newScreenDoc = """
        ## Per-screen index

        | Screen | Reached from | Forward exits | Back path |
        |---|---|---|---|
        | Warp Drive | nowhere yet | none | none |

        ## Next
        """
}
