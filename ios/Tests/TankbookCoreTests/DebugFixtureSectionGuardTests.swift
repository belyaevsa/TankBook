import Foundation
import Testing

// PJ.59 - the source-scan guard that no production view renders a section whose
// only data is a DEBUG launch-argument fixture. `RecentlyDeletedView`'s
// "Overwritten by sync" section was exactly that: it read
// `RecentlyDeletedFixtures.fromLaunchArguments()`, so it appeared under
// `-forceSyncOverwritten` in every UI test and in no Release build.
// `ScreenRouteScanner` (RV.162) binds screens to routes and cannot see a section
// inside a live screen; this is that stated blind spot for the one source shape
// it can see. The scanner is a pure function (`DebugFixtureSectionScanner`), so
// a hand-written fixture can be fed to it the way RV.162/RV.165 do.
@Suite("No production section is a DEBUG launch-argument fixture (PJ.59)")
struct DebugFixtureSectionGuardTests {

    // MARK: - Source location

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
    }

    /// Every Swift file under the app target's production sources.
    private static func appSources() throws -> [DebugFixtureSectionScanner.SourceFile] {
        let root = repoRoot.appendingPathComponent("ios/App/Sources")
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else {
            Issue.record("cannot enumerate \(root.path)")
            return []
        }
        var files: [DebugFixtureSectionScanner.SourceFile] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append(.init(path: "App/Sources/\(relative)",
                               contents: try String(contentsOf: url, encoding: .utf8)))
        }
        return files
    }

    // MARK: - L1: the tree walk (the calibration)

    /// The real tree passes: no production view renders a section from a
    /// launch-argument fixture collection. This is the guard's calibration - it
    /// was RED on `RecentlyDeletedView.swift` before PJ.59 wired the section to
    /// the real `syncOverwrite` log.
    @Test func theRealAppTreeHasNoFixtureBackedSection() throws {
        let sources = try Self.appSources()
        #expect(!sources.isEmpty, "no app source was found - a parse bug must not read as green")
        #expect(sources.contains { $0.path.contains("RecentlyDeletedView.swift") },
                "the scan must see the view this row is about")

        for section in DebugFixtureSectionScanner.gatedSections(in: sources) {
            Issue.record("""
                \(section.path):\(section.line): \(section.member) renders a section whose only \
                data is a DEBUG launch-argument fixture. Give the section a real data source \
                (read the repository) or remove it - a section that exists only behind a flag \
                exists for no Release user. PJ.4/PJ.59's shape.
                """)
        }
    }

    // MARK: - L1: the historical shape is reported

    /// Reconstructs the exact pre-fix code: the section is gated on and rendered
    /// from `RecentlyDeletedFixtures.fromLaunchArguments()`. A guard that only
    /// looked for a `#if DEBUG` wrapper would walk past this.
    @Test func theHistoricalFixtureSectionIsReported() {
        let source = #"""
            struct RecentlyDeletedView: View {
                @State private var fixtures = RecentlyDeletedFixtures.fromLaunchArguments()

                var body: some View {
                    if !fixtures.syncOverwritten.isEmpty {
                        syncOverwrittenSection
                    }
                }

                private var syncOverwrittenSection: some View {
                    ForEach(fixtures.syncOverwritten) { row in
                        syncOverwrittenRow(row)
                    }
                }
            }
            """#
        let sections = DebugFixtureSectionScanner.gatedSections(
            in: [.init(path: "App/Sources/RecentlyDeleted/RecentlyDeletedView.swift", contents: source)])
        #expect(sections.map(\.member) == ["fixtures.syncOverwritten"],
                "the historical fixture section must be reported - got \(sections)")
    }

    // MARK: - L1: the fixed shape is not reported

    /// The real data source (a state array, not a fixture) is not a fixture
    /// binding at all, so the same `ForEach`/`.isEmpty` shape passes.
    @Test func theFixedRealDataSectionIsNotReported() {
        let source = #"""
            struct RecentlyDeletedView: View {
                @State private var syncOverwritten: [SyncOverwrittenRow] = []

                var body: some View {
                    if !syncOverwritten.isEmpty {
                        syncOverwrittenSection
                    }
                }

                private var syncOverwrittenSection: some View {
                    ForEach(syncOverwritten) { row in
                        syncOverwrittenRow(row)
                    }
                }
            }
            """#
        let sections = DebugFixtureSectionScanner.gatedSections(
            in: [.init(path: "App/Sources/RecentlyDeleted/RecentlyDeletedView.swift", contents: source)])
        #expect(sections.isEmpty, "a real-data section must pass - got \(sections)")
    }

    // MARK: - L1: a fixture boolean banner is not this shape

    /// A fixture boolean hiding a card of static copy (the S5 archived-returned
    /// banner, PJ.40) is a different decision, tracked separately. The scanner's
    /// narrowness is deliberate and pinned here rather than left implicit.
    @Test func aFixtureBooleanBannerIsNotASection() {
        let source = #"""
            struct HomeBanners: View {
                let presentables: HomePresentables

                var body: some View {
                    if presentables.archivedReturned {
                        archivedReturnedCard
                    }
                }
            }
            """#
        // No `fromLaunchArguments()` binding in this file, so nothing is scanned
        // as a fixture even before the boolean rule is reached.
        let sections = DebugFixtureSectionScanner.gatedSections(
            in: [.init(path: "App/Sources/Home/HomeBanners.swift", contents: source)])
        #expect(sections.isEmpty, "a fixture boolean banner is not a fixture-backed section - got \(sections)")
    }

    /// A fixture boolean gate in the same file as a fixture binding is still not
    /// reported: the signal is a rendered collection, not any fixture read.
    @Test func aFixtureBooleanGateIsNotACollectionSection() {
        let source = #"""
            struct HomeView: View {
                @State private var presentables = HomePresentables.fromLaunchArguments()

                var body: some View {
                    if presentables.syncToast {
                        HomeSyncToast()
                    }
                }
            }
            """#
        let sections = DebugFixtureSectionScanner.gatedSections(
            in: [.init(path: "App/Sources/Home/HomeView.swift", contents: source)])
        #expect(sections.isEmpty, "a boolean gate is not a collection section - got \(sections)")
    }

    // MARK: - L1: prose and strings are not call sites

    @Test func commentsAndStringsAreMasked() {
        let source = #"""
            // the old view used ForEach(fixtures.syncOverwritten)
            /* let fixtures = RecentlyDeletedFixtures.fromLaunchArguments() */
            let flag = "-forceSyncOverwritten"
            """#
        let sections = DebugFixtureSectionScanner.gatedSections(
            in: [.init(path: "App/Sources/RecentlyDeleted/RecentlyDeletedView.swift", contents: source)])
        #expect(sections.isEmpty, "commented/string prose must not fail the guard - got \(sections)")
    }

    // MARK: - L1: the binding reader

    @Test func fixtureBindingsReadOnlyFromLaunchArgumentAssignments() {
        let source = #"""
            @State private var fixtures = RecentlyDeletedFixtures.fromLaunchArguments()
            @State private var presentables = HomePresentables.fromLaunchArguments()
            @State private var realRows: [Row] = []
            """#
        let names = DebugFixtureSectionScanner.fixtureBindings(
            in: DebugFixtureSectionScanner.maskCommentsAndStrings(source))
        #expect(names == ["fixtures", "presentables"],
                "only the launch-argument bindings are fixtures - got \(names)")
    }
}
