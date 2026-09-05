import Foundation
import os
import Testing
@testable import TankbookCore

// RV.73 - the local half of picking an import file (docs/TASKS.md RV.73). A
// file-picker URL is security-scoped; neither `.fileImporter` handler took the
// scope, `try?` swallowed the read error, and every real pick rendered the
// generic "couldn't read that file" card while no request ever reached the
// server. The fix lives in `ImportPickedFile` (the scope discipline + the
// container copy) and in the logged `ImportReadFailure` event. These tests run
// in a plain `swift test` process where scoped access is not enforced, so the
// scope/copy/remove seams are injected and the tests drive the discipline that
// production enforces - a real scoped URL cannot be simulated here, which is
// exactly why the seam exists.

// MARK: - Doubles

private final class ScopeRecorder: @unchecked Sendable {
    /// The ORDER of the seam calls, not just how many. Counting starts and
    /// stops cannot tell "the scope framed the copy" from "the scope was taken
    /// and dropped before the copy ran" - and the second is exactly the
    /// production bug RV.73 fixes, so the sequence is what the test asserts.
    enum Event: Equatable { case start, copy, stop }

    private let lock = OSAllocatedUnfairLock(initialState: [Event]())
    func recordStart() { lock.withLock { $0.append(.start) } }
    func recordCopy() { lock.withLock { $0.append(.copy) } }
    func recordStop() { lock.withLock { $0.append(.stop) } }
    func events() -> [Event] { lock.withLock { $0 } }
    func counts() -> (starts: Int, stops: Int) {
        let events = self.events()
        return (events.filter { $0 == .start }.count, events.filter { $0 == .stop }.count)
    }
}

/// Builds a stager over a shared `ScopeRecorder` so one test can drive several
/// attempts and then assert the scope discipline across all of them.
private func seamedStager(directory: URL,
                          recorder: ScopeRecorder,
                          copyItem: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default
                              .copyItem(at: $0, to: $1) }) -> ImportPickedFile {
    ImportPickedFile(
        stagingDirectory: directory,
        startScope: { _ in recorder.recordStart(); return true },
        stopScope: { _ in recorder.recordStop() },
        copyItem: { source, destination in
            recorder.recordCopy()
            try copyItem(source, destination)
        })
}

private func tempDir(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("rv73-\(name)-\(UUID().uuidString)")
}

/// Writes a real import-looking CSV at `directory/MyFuelManager_export.csv` and
/// returns its URL.
private func makePickFile(in directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("MyFuelManager_export.csv")
    try Data("Date;Odometer;Volume\n1/1/2024;120000;42.5".utf8).write(to: url)
    return url
}

private func makeLog(sink: InMemorySink) -> TankbookLog {
    TankbookLog.makeDefault(sink: sink, deviceId: nil, breadcrumbs: nil)
}

// MARK: - The suite

@Suite("Import picked-file staging (RV.73)")
struct ImportPickedFileStagingTests {

    /// The security scope must frame the copy attempt and be released on EVERY
    /// path - success and failure alike (the `defer` the defect's fix adds).
    /// The mutations this catches: deleting the `startScope` call, and losing
    /// the `defer` release on the failure path.
    @Test func theScopeFramesTheCopyAndIsReleasedOnEveryPath() throws {
        let root = tempDir("scope")
        defer { try? FileManager.default.removeItem(at: root) }
        let pick = try makePickFile(in: root)
        let recorder = ScopeRecorder()

        let success = seamedStager(directory: root, recorder: recorder)
            .stage(pick, log: nil)
        #expect(success.isStaged, "the copy succeeds under scope")

        let failed = seamedStager(directory: root, recorder: recorder) { _, _ in
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadNoPermission.rawValue)
        }.stage(pick, log: nil)
        #expect(failed == .readFailed, "a permission-shaped copy failure is a read failure")

        let counts = recorder.counts()
        #expect(counts.starts == 2, "the scope was taken for both attempts, got \(counts)")
        #expect(counts.stops == 2, "the scope was released on BOTH paths - success and failure, got \(counts)")
        // The ordering is the real claim, and counting cannot make it: a stager
        // that takes the scope and releases it BEFORE copying passes on counts
        // alone while reproducing the production bug (the read runs unscoped).
        #expect(recorder.events() == [.start, .copy, .stop, .start, .copy, .stop],
                "each copy must run INSIDE its own scope - start, copy, stop - got \(recorder.events())")
    }

    /// A permission-shaped read failure (a Cocoa 257 - what a scoped pick
    /// outside the container throws when the scope is not taken) lands on the
    /// read-failure outcome, never on a staged copy.
    @Test func aPermissionShapedFailureIsTheReadFailureOutcome() throws {
        let root = tempDir("permission")
        defer { try? FileManager.default.removeItem(at: root) }
        let pick = try makePickFile(in: root)
        let stager = ImportPickedFile(stagingDirectory: root,
                                      copyItem: { _, _ in
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadNoPermission.rawValue)
        })

        let outcome = stager.stage(pick, log: nil)
        #expect(outcome == .readFailed,
                "a permission-shaped copy failure must surface the read-failure state, got \(outcome)")
    }

    /// A scope-start that returns false (a URL already inside the app
    /// container needs no scope) is NOT a failure: the copy is attempted and
    /// decides. The defect's fix must never turn a `false` into an error.
    @Test func aRefusedScopeStartIsNotTreatedAsAFailure() throws {
        let root = tempDir("refused-scope")
        defer { try? FileManager.default.removeItem(at: root) }
        let pick = try makePickFile(in: root)
        let stager = ImportPickedFile(stagingDirectory: root,
                                      startScope: { _ in false })

        let outcome = stager.stage(pick, log: nil)
        #expect(outcome.isStaged, "a false scope-start must not fail the read - the copy decides, got \(outcome)")
    }

    /// The read failure is LOGGED with the error's type and code - and never
    /// the path, never the file name (hard rule 12). A Cocoa file error names
    /// the file it could not open, so its rendered description must have no
    /// route into the line.
    @Test func theReadFailureLogsTypeAndCodeButNoPathOrName() throws {
        let sink = InMemorySink()
        let log = makeLog(sink: sink)
        let root = tempDir("log")
        defer { try? FileManager.default.removeItem(at: root) }
        let pickDir = root.appendingPathComponent("picks")
        let pick = try makePickFile(in: pickDir)
        let stager = ImportPickedFile(stagingDirectory: root,
                                      copyItem: { _, _ in
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadNoPermission.rawValue)
        })

        let outcome = stager.stage(pick, log: log)
        #expect(outcome == .readFailed)

        let lines = sink.rendered()
        #expect(lines.count == 1, "exactly one event is logged for a staged read failure")
        let line = lines.first ?? ""
        #expect(line.contains("event=import.read.fail"), "line was: \(line)")
        #expect(line.contains("errorType=NSError"), "line was: \(line)")
        #expect(line.contains("errorCode=257"),
                "the Cocoa code (257 = read no permission) must be logged, line was: \(line)")
        #expect(!line.contains("MyFuelManager_export.csv"), "the file name must never be logged, line was: \(line)")
        #expect(!line.contains(pick.path), "the picked path must never be logged, line was: \(line)")
        #expect(!line.contains(root.path), "the staging path must never be logged, line was: \(line)")
    }

    /// A successful copy lands where the decision says (a per-pick subdirectory
    /// under the staging directory) and keeps the ORIGINAL name - the wizard
    /// shows and uploads that name.
    @Test func theStagedCopyIsWrittenWhereDecidedAndNamedAfterThePick() throws {
        let root = tempDir("write")
        defer { try? FileManager.default.removeItem(at: root) }
        let pick = try makePickFile(in: root)
        let stager = ImportPickedFile(stagingDirectory: root)

        guard case .staged(let staged) = stager.stage(pick, log: nil) else {
            Issue.record("expected the copy to succeed"); return
        }
        #expect(staged.lastPathComponent == "MyFuelManager_export.csv",
                "the staged copy keeps the original name for display and upload")
        let parent = staged.deletingLastPathComponent()
        #expect(parent.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"),
                "the copy is staged under the decided directory")
        #expect(FileManager.default.fileExists(atPath: staged.path),
                "the staged copy exists on disk")
    }

    /// The staged copy is deleted when the consumer is done (`dispose`) - the
    /// copy holds user data and must not outlive its use.
    @Test func disposeDeletesTheStagedCopy() throws {
        let root = tempDir("dispose")
        defer { try? FileManager.default.removeItem(at: root) }
        let pick = try makePickFile(in: root)
        let stager = ImportPickedFile(stagingDirectory: root)

        guard case .staged(let staged) = stager.stage(pick, log: nil) else {
            Issue.record("expected the copy to succeed"); return
        }
        stager.dispose(staged)
        #expect(!FileManager.default.fileExists(atPath: staged.path),
                "dispose must delete the staged copy")
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path),
                "dispose must delete the empty per-pick subdirectory too")
    }
}

extension ImportPickedFile.Outcome {
    /// Convenience for the tests: whether a staged URL was produced.
    var isStaged: Bool {
        if case .staged = self { return true }
        return false
    }
}
