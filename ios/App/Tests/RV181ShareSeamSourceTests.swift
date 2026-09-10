import XCTest

/// RV.181 source oracle: every share surface must go through the one seam,
/// `Shared/ActivityView.swift`. A call site that builds its own
/// `UIActivityViewController` gets neither the presentation latch nor the
/// outcome record, so a failed share there is again indistinguishable from a
/// cancel - the state that left the device report undiagnosable.
///
/// **Its blind spot**: the scan is textual. It sees a construction site and a
/// reference; it cannot see whether the outcome is acted on, and it says
/// nothing about whether a share reaches its destination.
final class RV181ShareSeamSourceTests: XCTestCase {

    func testActivityViewIsTheOnlyActivityControllerConstructionSite() throws {
        let sources = try Self.sourcesDirectory()
        let files = try Self.swiftFiles(under: sources)
        XCTAssertFalse(files.isEmpty, "no source files found under \(sources.path)")

        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if text.contains("UIActivityViewController("),
               file.lastPathComponent != "ActivityView.swift" {
                offenders.append(file.path)
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "UIActivityViewController must be constructed only in Shared/ActivityView.swift; "
            + "offenders: \(offenders)")
    }

    /// The surfaces the seam serves: diagnostics text, the receipt photo/PDF,
    /// the account and per-car exports (both via `ExportFlow`), and "send us the
    /// file". Each must reference `ActivityView(`.
    func testEveryShareSurfaceReferencesTheSeam() throws {
        let sources = try Self.sourcesDirectory()
        let expected = [
            "Settings/DiagnosticsPreviewView.swift",
            "EditEntry/AttachmentViewerView.swift",
            "Export/ExportFlow.swift",
            "Import/ImportWizardView.swift"
        ]
        for relative in expected {
            let url = sources.appendingPathComponent(relative)
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.contains("ActivityView("),
                          "\(relative) must share through ActivityView, not its own sheet")
        }
    }

    // MARK: - Source tree (mirrors ReleaseSeedGateTests)

    private static func sourcesDirectory() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        var candidate = thisFile.deletingLastPathComponent() // ios/App/Tests
        for _ in 0..<3 { candidate = candidate.deletingLastPathComponent() } // -> repo root
        let sources = candidate.appendingPathComponent("ios/App/Sources", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw NSError(
                domain: "RV181ShareSeamSourceTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "app source tree not found at \(sources.path) - the seam gate cannot run"])
        }
        return sources
    }

    private static func swiftFiles(under directory: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }
}
