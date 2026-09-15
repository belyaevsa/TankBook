import Foundation
import TankbookCore
import UIKit
import XCTest
@testable import Tankbook

/// RV.181: the diagnostics share must hand the sheet a **file**, not the raw
/// preview `String`. A destination that accepts only short messages drops a
/// 12-15 KB text while every destination accepts a file URL; the device report
/// (AirDrop arrives, Telegram does not) is that shape.
///
/// The oracle is the preview on screen: the file's bytes are
/// `makePreviewText()`'s output, so "what the user read" and "what left the
/// device" are the same bytes. The protection assertion is the class
/// docs/SECURITY.md promises. The cleanup assertion is the cancel path: a share
/// the user abandons must not leave the bundle on disk.
@MainActor
final class RV181DiagnosticsFileShareTests: XCTestCase {

    /// The share item is one `.txt` file whose contents are the preview text,
    /// with the promised protection class. Red on the old shape, where the item
    /// was the `String` itself.
    func testTheShareItemIsASingleProtectedTxtFileMatchingThePreview() async throws {
        let text = await DiagnosticsService.makePreviewText()
        let directory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var captured: [Any] = []
        _ = DiagnosticsShare.present(text: text, directory: directory) { items, _ in
            captured = items
            return nil
        }

        XCTAssertEqual(captured.count, 1,
                       "the diagnostics share is one file, never a text-plus-file pair")
        let url = try XCTUnwrap(captured.first as? URL,
                                "the share item must be a file URL, not the raw string")
        XCTAssertEqual(url.pathExtension, "txt")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("tankbook-diagnostics-"),
                      "unexpected bundle name: \(url.lastPathComponent)")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text,
                       "the file IS the preview text, byte for byte")

        let protection = try url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
    }

    /// The seam that is discriminating on the simulator (PR.16b): the file is
    /// written through `FileProtection`, so a removed `protect` call fails here
    /// even though the simulator reports a constant for the attribute above.
    func testTheWrittenFileSeamAppliesThePromisedProtectionClass() throws {
        let recorder = ProtectionRecorder()
        let original = AppStore.fileProtectionApplier
        AppStore.fileProtectionApplier = { protectionClass, url in
            recorder.record(protectionClass.rawValue, url: url)
        }
        defer { AppStore.fileProtectionApplier = original }

        let directory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try DiagnosticsShare.write("diagnostics", directory: directory)

        let matching = recorder.snapshot().filter {
            $0.1.standardizedFileURL == url.standardizedFileURL
        }
        XCTAssertFalse(matching.isEmpty,
                       "no file-protection call recorded for \(url.lastPathComponent)")
        for entry in matching {
            XCTAssertEqual(entry.0, "completeUntilFirstUserAuthentication",
                           "the diagnostics bundle was applied class \(entry.0)")
        }
    }

    /// A cancel is still an outcome: the completion handler fires with
    /// `completed: false`, and the bundle must be gone - not left for the next
    /// preview to trip over.
    func testTheFileIsRemovedWhenTheShareOutcomeIsACancel() async throws {
        let text = await DiagnosticsService.makePreviewText()
        let directory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var completion: ((ShareOutcome) -> Void)?
        _ = DiagnosticsShare.present(text: text, directory: directory) { _, captured in
            completion = captured
            return nil
        }
        let file = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        completion?(ShareOutcome(activityType: nil, completed: false,
                                 errorDomain: nil, errorCode: nil))

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "a cancelled share must not leave the bundle on disk")
    }

    /// A share the user never finishes has no completion to remove it; the next
    /// write sweeps it, so at most one bundle exists at a time.
    func testANewWriteSweepsABundleAnUnfinishedShareLeftBehind() throws {
        let directory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = try DiagnosticsShare.write(
            "stale", now: Date(timeIntervalSince1970: 0), directory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale.path))

        _ = try DiagnosticsShare.write(
            "fresh", now: Date(timeIntervalSince1970: 60), directory: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path),
                       "at most one diagnostics bundle exists at a time")
    }

    private static func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RV181-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A lock-guarded recorder of `(classRawValue, url)` pairs, the PR.16b shape.
private final class ProtectionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(String, URL)] = []

    func record(_ classRawValue: String, url: URL) {
        lock.lock(); defer { lock.unlock() }
        entries.append((classRawValue, url))
    }

    func snapshot() -> [(String, URL)] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}
