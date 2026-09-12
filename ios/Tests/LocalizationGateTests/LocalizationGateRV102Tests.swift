import Foundation
import Testing
@testable import LocalizationGate

/// RV.102 (docs/TASKS.md) - the localization gate cannot see a key that never
/// reaches a view. `HomeEmptyStates.quickAction` took `_ title: String` and fed
/// it to `Label(title, systemImage:)`; `Label` has a `LocalizedStringKey` and a
/// `String` initialiser, and the `String` one renders the literal - so "Select
/// car" and "Type it" rendered in ENGLISH on a Russian device while their
/// translations sat in the catalogue, and the gate reported 0 violations
/// because the keys existed and were translated. This suite owns the L1 proof
/// that the new pass (RoutedLiteralScan) flags the shape at last: a literal
/// routed through a `String` type into a text renderer.
@Suite("Localization gate (RV.102)")
struct LocalizationGateRV102Tests {

    /// ios/Tests/LocalizationGateTests/<this file> -> ios/App/Sources
    private static var catalogueURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ios/Tests/LocalizationGateTests
            .deletingLastPathComponent() // ios/Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/Localizable.xcstrings")
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-rv102-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - The regression oracle: the exact quickAction shape

    /// The pre-fix `HomeEmptyStates.quickAction` shape, reconstructed: a local
    /// helper takes `_ title: String` and forwards it into `Label`, and the
    /// body calls it with raw literals. Both literals render English-in-RU, so
    /// the gate must flag both. This is the row's regression oracle - run it
    /// against the pre-fix shape, not the fixed code.
    @Test("the pre-fix quickAction shape is flagged at both call sites")
    func quickActionStringShapeIsFlagged() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("QuickActionsView.swift")

        try """
        import SwiftUI
        struct QuickActionsView: View {
            var body: some View {
                VStack {
                    quickAction("Select car", systemImage: "car") { }
                    quickAction("Type it", systemImage: "square.and.pencil") { }
                }
            }
            private func quickAction(_ title: String, systemImage: String,
                                     action: @escaping () -> Void) -> some View {
                Label(title, systemImage: systemImage)
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.count == 2, "both literals must be flagged; got \(violations)")
        #expect(violations.allSatisfy { $0.kind == .stringRoutedLiteral })
        #expect(violations.contains { $0.keyTemplate == "Select car" })
        #expect(violations.contains { $0.keyTemplate == "Type it" })
    }

    /// The FIXED shape (RV.100's change): the same helper takes
    /// `LocalizedStringKey`. The literals are then keys by construction and the
    /// gate must treat them like any `Text("…")` call - no violation while the
    /// catalogue holds the entries. A missing key must fail even here.
    @Test("the fixed LocalizedStringKey shape is clean, and a missing key still fails")
    func quickActionLocalizedStringKeyShapeIsClean() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("QuickActionsLSK.swift")

        try """
        import SwiftUI
        struct QuickActionsLSK: View {
            var body: some View {
                quickAction("Select car", systemImage: "car") { }
            }
            private func quickAction(_ title: LocalizedStringKey, systemImage: String,
                                     action: @escaping () -> Void) -> some View {
                Label(title, systemImage: systemImage)
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        #expect(try LocalizationGate.violations(sources: dir, catalogue: catalogue).isEmpty,
                "real keys on a LocalizedStringKey forward are clean")

        let marker = "N0T_A_RV102_KEY_\(UInt64.random(in: UInt64.min ... UInt64.max))"
        try """
        import SwiftUI
        struct QuickActionsBad: View {
            var body: some View {
                quickAction("\(marker)", systemImage: "car") { }
            }
            private func quickAction(_ title: LocalizedStringKey, systemImage: String,
                                     action: @escaping () -> Void) -> some View {
                Label(title, systemImage: systemImage)
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.count == 1, "got \(violations)")
        #expect(violations.first?.kind == .noEntry)
        #expect(violations.first?.keyTemplate == marker)
    }

    // MARK: - The String variable / LocalizedStringKey pair

    /// A `String` local bound to a literal and drawn by a text renderer renders
    /// the literal verbatim - flagged. The same view with a `LocalizedStringKey`
    /// local is clean: the value is a key and the existing pass checks it.
    @Test("a String-typed local bound to a literal is flagged; LocalizedStringKey is not")
    func stringLocalIsFlaggedAndLocalizedStringKeyIsNot() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("LocalCopies.swift")

        try """
        import SwiftUI
        func makeTitle() -> some View {
            let heading: String = "Select car"
            return Text(heading)
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.count == 1, "got \(violations)")
        #expect(violations.first?.kind == .stringRoutedLiteral)
        #expect(violations.first?.keyTemplate == "Select car")

        try """
        import SwiftUI
        func makeTitle() -> some View {
            let heading: LocalizedStringKey = "Select car"
            return Text(heading)
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let clean = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(clean.isEmpty, "a LocalizedStringKey local is a key, not a routed literal; got \(clean)")
    }

    // MARK: - False-positive guard: dynamic data must not be flagged

    /// The whole reason gates get deleted: a `String` holding genuinely dynamic
    /// user data - a car name from the model - MUST NOT be flagged, whether it
    /// reaches the renderer as a direct member access or through a local that
    /// copies the model value. Only copy bound to `String` is the defect.
    @Test("dynamic user data reaching a text renderer is not flagged")
    func dynamicUserDataIsNotFlagged() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("DynamicRow.swift")

        try """
        import SwiftUI
        struct DynamicRow: View {
            let car: Car
            var body: some View {
                VStack {
                    Text(car.name)
                    let name = car.name
                    Text(name)
                }
            }
        }
        struct Car {
            let name: String
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.isEmpty, "dynamic data must not trip the gate; got \(violations)")
    }

    /// A helper that takes a String and renders it is the localise-at-the-call
    /// site convention the app uses (reasonButton, hintText, StatTile...): every
    /// caller passes `L10n.localize(...)` or a dynamic value. Only a RAW literal
    /// at a call site is the defect - the convention itself must stay quiet.
    @Test("the localise-first helper convention is not flagged")
    func localiseFirstConventionIsQuiet() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("LocaliseFirst.swift")

        try """
        import SwiftUI
        struct LocaliseFirst: View {
            var body: some View {
                VStack {
                    reasonButton(title: L10n.localize("Other"), identifier: "a") { }
                    reasonButton(title: Self.label(for: selected), identifier: "b") { }
                }
            }
            private static func label(for kind: Int) -> String { kind == 0 ? "A" : "B" }
            private func reasonButton(title: String, identifier: String,
                                      action: @escaping () -> Void) -> some View {
                Button(action: action) { Text(title) }
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.isEmpty,
                "L10n-first and dynamic callers are correct; got \(violations)")
    }

    /// A String sink that is NOT a text renderer - a logger, a store - must not
    /// make its literal call sites user-facing copy. The gate only learns
    /// helpers whose body forwards into Label/Text/Button.
    @Test("a non-rendering String helper is not learned, so its literals stay quiet")
    func nonRenderingHelperIsNotLearned() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("DataSink.swift")

        try """
        import Foundation
        struct Recorder {
            func record(_ note: String) {
                UserDefaults.standard.set(note, forKey: "last")
            }
        }
        struct RecorderCaller {
            let recorder = Recorder()
            func capture() {
                recorder.record("Some internal marker string")
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.isEmpty, "a data sink is not copy; got \(violations)")
    }
}
