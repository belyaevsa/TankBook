import Foundation
import Testing

/// Share-to-Tankbook (docs/JOURNEYS.md J2, PJ.21) is declared in
/// `project.yml`: without the document types the share sheet never lists the
/// app and the `onOpenURL` door is unreachable. A source-scan over the spec,
/// the same shape as the other project guards - it fails when the keys are
/// dropped or the CSV type is removed.
@Suite("Share-to-Tankbook project declaration (PJ.21)")
struct ShareToTankbookProjectGuardTests {

    private static var projectYML: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("project.yml")
    }

    @Test("project.yml declares the CSV document type the share sheet needs")
    func projectDeclaresTheDocumentType() throws {
        let spec = try String(contentsOf: Self.projectYML, encoding: .utf8)
        #expect(spec.contains("CFBundleDocumentTypes:"))
        #expect(spec.contains("public.comma-separated-values-text"))
        #expect(spec.contains("LSHandlerRank: Alternate"),
                "Tankbook is an importer, never the system's CSV editor")
    }
}
