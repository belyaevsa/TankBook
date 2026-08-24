import Foundation
import Testing
@testable import LocalizationGate

/// P0.3 - the pseudo-localization gate (docs/TASKS.md): the app's user-facing
/// strings all resolve in the String Catalog for EN and RU, and the gate fails
/// on a deliberately hardcoded string while leaving non-user-facing literals
/// (accessibility identifiers, launch arguments, log messages, system images,
/// test code) alone.
@Suite("Localization gate (P0.3)")
struct LocalizationGateTests {

    /// ios/Tests/LocalizationGateTests/<this file> -> ios/App/Sources
    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ios/Tests/LocalizationGateTests
            .deletingLastPathComponent() // ios/Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources", isDirectory: true)
    }

    private static var catalogueURL: URL {
        appSources.appendingPathComponent("Localizable.xcstrings")
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - The gate on the current tree

    @Test("the current app tree has no unresolvable or untranslated strings")
    func cleanTreePasses() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let violations = try LocalizationGate.violations(sources: Self.appSources,
                                                         catalogue: catalogue)
        #expect(violations.isEmpty,
                "clean-tree gate must pass; violations: \(violations)")
    }

    @Test("every catalogue key carries a non-empty Russian value")
    func coverageIsComplete() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        #expect(catalogue.keysMissingRu.isEmpty,
                "keys missing Russian: \(catalogue.keysMissingRu)")
        // P0.3 adds the neutral keys (units, gauge marks, separators), so the
        // catalogue must be above the 220-key baseline from before this task.
        #expect(catalogue.keyCount >= 220, "key count: \(catalogue.keyCount)")
    }

    // MARK: - The deliberate-failure proof

    @Test("a deliberately hardcoded string fails the gate; the fixed version passes")
    func deliberateHardcodedStringFails() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("FakeView.swift")
        let marker = "T0T4LLY_HARDCODED_\(UInt64.random(in: UInt64.min ... UInt64.max))"
        let content = """
        import SwiftUI

        struct FakeView: View {
            var body: some View {
                Text("\(marker)")
            }
        }
        """
        try content.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir,
                                                         catalogue: catalogue)
        #expect(violations.count == 1)
        #expect(violations.first?.kind == .noEntry)
        #expect(violations.first?.keyTemplate == marker)

        // The same file with a real catalogue key is clean.
        let fixed = content.replacingOccurrences(of: marker, with: "Save fill-up")
        try fixed.write(to: file, atomically: true, encoding: .utf8)
        let clean = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(clean.isEmpty, "clean variant: \(clean)")
    }

    // MARK: - Termination (the defect that made the first build unusable)

    /// The scanner's tokenizer once failed to advance past a string literal,
    /// so the first `"` in any file span forever. Every other test in this
    /// suite hangs when that regresses rather than failing, which is exactly
    /// why this one is explicit: it bounds the work and names the cause.
    @Test("the scanner terminates on literals, comments and unterminated quotes")
    func scannerAlwaysTerminates() throws {
        let cases = [
            #"Text("a")"#,
            #"let s = "unterminated"#,
            #"// "quote in a comment"\#nText("Save fill-up")"#,
            #"/* "quote in a block" */ Text("Save fill-up")"#,
            #"Text("nested \(inner("deep")) tail")"#,
            "\"\"",
            "\""
        ]
        for source in cases {
            _ = SourceScanner.references(inFile: "T.swift", text: source)
        }
    }

    // MARK: - Coverage of the app's own catalogue lookup

    /// `L10n.localize` routes through `Text(_: String)`, which does not
    /// localise - so its literals are exactly the ones that render English in
    /// Russian while looking correct. They are keys by construction and the
    /// gate must check them.
    @Test("L10n.localize literals are checked, and a bad one fails")
    func l10nLocalizeCallSitesAreScanned() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("FakeView.swift")
        let marker = "L10N_UNKNOWN_\(UInt64.random(in: UInt64.min ... UInt64.max))"

        try """
        let good = L10n.localize("Save fill-up")
        let bad = L10n.localize("\(marker)")
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.count == 1)
        #expect(violations.first?.keyTemplate == marker)
    }

    /// A literal written with a real specifier must compare equal to the
    /// catalogue key it names: both sides normalise to the same `%@` template.
    @Test("a code-side literal written with %lld matches its catalogue key")
    func codeSideSpecifiersNormalise() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("FakeView.swift")

        try #"""
        let a = L10n.localize("%lld entries excluded")
        let b = L10n.localize("%d entries excluded")
        """#.write(to: file, atomically: true, encoding: .utf8)

        #expect(try LocalizationGate.violations(sources: dir, catalogue: catalogue).isEmpty)
    }

    // MARK: - False-positive guard (the reason gates get deleted)

    @Test("accessibility identifiers, launch args, logs and system images are not flagged")
    func nonUserFacingLiteralsAreIgnored() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("FakeView.swift")
        let nonKey = "H4RD_C0DED_LOOKING_\(UInt64.random(in: UInt64.min ... UInt64.max))"
        let content = """
        import SwiftUI
        import OSLog

        struct FakeView: View {
            private static let log = Logger(subsystem: "app.tankbook", category: "fake")

            var body: some View {
                Text("Save fill-up")
                    .accessibilityIdentifier("\(nonKey)")
                    .accessibilityLabel("Save fill-up")
                Image(systemName: "\(nonKey)")
                Label("Save fill-up", systemImage: "\(nonKey)")
                TextField("Full tank", text: .constant(""))
                Text("\\(count) days left")
            }

            func sideEffects() {
                Self.log.error("\(nonKey) failed: \\(error.localizedDescription, privacy: .public)")
                _ = ProcessInfo.processInfo.arguments.contains("-\(nonKey)")
                _ = Bundle.main.object(forInfoDictionaryKey: "\(nonKey)")
            }
        }

        struct FakeModel {
            var caption: LocalizedStringKey? = "last known · update after typing fuel"
        }
        """
        try content.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.isEmpty,
                "non-user-facing literals must not trip the gate; got \(violations)")
    }

    @Test("test code is excluded because the scan is rooted at the app target")
    func testCodeIsNotScanned() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // A deliberately bad literal under a Tests/ subtree.
        let testsDir = dir.appendingPathComponent("Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try """
        import SwiftUI
        struct FakeTest {
            let label = Text("T0T4LLY_NOT_A_KEY")
        }
        """.write(to: testsDir.appendingPathComponent("FakeTests.swift"),
                  atomically: true, encoding: .utf8)

        // Pointing the gate at the app target (which is what CI and the L1
        // wiring do) never sees the test file...
        let appDir = dir.appendingPathComponent("App", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try """
        import SwiftUI
        struct FakeView: View {
            var body: some View { Text("Save fill-up") }
        }
        """.write(to: appDir.appendingPathComponent("FakeView.swift"),
                  atomically: true, encoding: .utf8)

        #expect(try LocalizationGate.violations(sources: appDir, catalogue: catalogue).isEmpty)

        // ...whereas scanning the parent (Tests included) finds it. The gate
        // checks what it is told to check; the P0.3 wiring tells it App/Sources.
        let rooted = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(rooted.count == 1)
        #expect(rooted.first?.file.hasSuffix("FakeTests.swift") == true)
    }

    @Test("the localized string catalog holds the current RU coverage facts")
    func sampleKeysResolveInEnglishAndRussian() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)

        // Plain keys resolve in both languages.
        for key in ["Save fill-up", "Recently deleted", "Full tank", "Manual fill-up",
                    "Add car", "Delete everything here?"] {
            #expect(catalogue.value(for: key, language: "en")?.isEmpty == false, "en '\(key)'")
            #expect(catalogue.value(for: key, language: "ru")?.isEmpty == false, "ru '\(key)'")
        }

        // Composed key: the placeholder must survive translation. The RU pass
        // on P1.4 shipped word-order bugs exactly here ("%@ spend" became
        // "АВГУСТ РАСХОДЫ"), so assert the %@ is present, not just non-empty.
        let composedRU = catalogue.value(for: "%@ spend", language: "ru")
        #expect(composedRU == "Расходы за %@")
        #expect(composedRU?.contains("%@") == true)

        // Plural key: Russian has three forms plus a generic `other`; assert
        // they all resolve and that `one` differs from `many` (a real Russian
        // plural, not a copy of English's two-form split).
        let ruForms = catalogue.pluralForms(for: "%lld days left", language: "ru")
        for form in ["one", "few", "many", "other"] {
            #expect(ruForms[form]?.isEmpty == false, "ru \(form)")
        }
        #expect(ruForms["one"] != ruForms["many"])
        let enForms = catalogue.pluralForms(for: "%lld days left", language: "en")
        #expect(enForms["one"]?.isEmpty == false)
        #expect(enForms["other"]?.isEmpty == false)
    }

    // MARK: - Extraction behaviour

    @Test("interpolated literals resolve against plural catalogue entries")
    func interpolatedPluralsResolve() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("InterpView.swift")
        try """
        import SwiftUI
        struct InterpView: View {
            var body: some View {
                Text("\\(count) days left")
                Text("\\(count) entries excluded")
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        #expect(try LocalizationGate.violations(sources: dir, catalogue: catalogue).isEmpty)
    }

    @Test("LocalizedStringKey-typed stored and computed properties are checked")
    func localizedStringKeyPropertiesAreChecked() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("Props.swift")
        let bad = "N0T_A_KEY_\(UInt64.random(in: UInt64.min ... UInt64.max))"
        try """
        import SwiftUI
        struct Props {
            var title: LocalizedStringKey { "\(bad)" }
            var caption: LocalizedStringKey? = "ALSO_N0T_A_KEY"
            var good: LocalizedStringKey { "Save fill-up" }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.count == 2, "got \(violations)")
        #expect(violations.allSatisfy { $0.kind == .noEntry })
    }

    @Test("a dynamic Text argument is skipped, not flagged")
    func dynamicKeysAreSkipped() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("DynamicView.swift")
        try """
        import SwiftUI
        struct DynamicView: View {
            let key: String
            var body: some View { Text(key) }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        #expect(try LocalizationGate.violations(sources: dir, catalogue: catalogue).isEmpty)
    }
}
