import Foundation

// RV.73 - the local half of picking an import file. A URL from the system
// file picker (Files, iCloud Drive) is SECURITY-SCOPED: the app can read it
// only while `startAccessingSecurityScopedResource()` is active, and the scope
// is released when the picker's completion handler returns. The wizard reads
// the file later than that handler - the parse upload, the "send us the file"
// share and any resume all consume the bytes after the scope is gone - so the
// bytes are COPIED into the app's own container at pick time, under the scope,
// and every later reader works from that copy. Without the copy the read is
// refused outside the container, `try?` swallowed the error, and every real
// pick rendered "We couldn't read that file" while no request ever left the
// device (the production log had no `/v1/import/parse` line).
//
// This seam lives in core so the scope discipline and the copy lifecycle are
// L1-testable on macOS (`swift test`), where the OS does not enforce scoped
// access: the scope/copy/remove operations are injectable closures, production
// defaults call the real Foundation APIs, and the tests substitute recorders
// and throwing copies. A `false` from `startAccessingSecurityScopedResource`
// is NOT a failure on its own - a URL already inside the container needs no
// scope - so staging never turns it into one; the copy is attempted either way
// and the copy decides.
//
// The lifecycle decision (docs/ERRORS.md -> Import wizard): the staged copy is
// deleted once its single consumer has read it - immediately after the parse
// path reads the bytes into `Data`, and when the consent/share flow settles on
// the send-us-the-file path. It never outlives the wizard step that needed it
// (it holds user data), and the staging directory is the app's Caches, which
// the OS may additionally purge. The file protection class SECURITY.md
// promises for stored user data is applied to the copy on write.

/// Stages (copies) a user-picked, security-scoped import file into the app's
/// own container so the wizard can read it after the scope is released.
public struct ImportPickedFile: Sendable {
    /// The outcome of copying a picked file into the container.
    public enum Outcome: Sendable, Equatable {
        /// The container copy is at `url`, named after the original pick.
        case staged(URL)
        /// The bytes could not be copied (permission refused, the iCloud file
        /// is not downloaded, ...). The failure's type and code were logged by
        /// `stage` - nothing else is carried (hard rule 12).
        case readFailed
    }

    /// The directory the container copies are written to. The app decides it
    /// (Caches/TankbookImport); tests supply a temporary directory.
    public let stagingDirectory: URL

    // The injectable seams. Production defaults call the real Foundation APIs;
    // tests substitute recorders and throwing doubles (the RV.73 tests drive
    // the scope discipline and the copy lifecycle without a real scoped URL).
    public var startScope: @Sendable (URL) -> Bool
    public var stopScope: @Sendable (URL) -> Void
    public var copyItem: @Sendable (URL, URL) throws -> Void
    public var removeItem: @Sendable (URL) throws -> Void

    public init(stagingDirectory: URL,
                startScope: @escaping @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
                stopScope: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
                copyItem: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default
                    .copyItem(at: $0, to: $1) },
                removeItem: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.stagingDirectory = stagingDirectory
        self.startScope = startScope
        self.stopScope = stopScope
        self.copyItem = copyItem
        self.removeItem = removeItem
    }

    /// The destination for one pick: a fresh per-pick subdirectory (so two
    /// picks of the same file cannot collide) holding the copy under the
    /// ORIGINAL name, because that name is what the wizard shows and uploads.
    public func destination(for picked: URL) -> URL {
        let subdirectory = stagingDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return subdirectory.appendingPathComponent(picked.lastPathComponent)
    }

    /// Copies the picked file into the container under the security scope and
    /// releases the scope on every path. A read failure yields `.readFailed`
    /// and logs the error's type and code (never the path, never the file
    /// name - hard rule 12) so the failure is reconstructible from the log.
    public func stage(_ picked: URL, log: TankbookLog? = nil) -> Outcome {
        let scoped = startScope(picked)
        defer {
            if scoped { stopScope(picked) }
        }
        do {
            let destination = destination(for: picked)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try copyItem(picked, destination)
            FileProtection.protect(destination)
            return .staged(destination)
        } catch {
            log?.emit(ImportReadFailure(error: error))
            return .readFailed
        }
    }

    /// Deletes a staged copy (and its per-pick subdirectory) once the consumer
    /// is done. Idempotent - safe to call twice. A URL that is not a staged
    /// copy (one the caller created elsewhere) is removed by file only, never
    /// by directory, so this can never delete an arbitrary directory.
    public func dispose(_ staged: URL) {
        let parent = staged.deletingLastPathComponent()
        let isStaged = parent.standardizedFileURL.path
            .hasPrefix(stagingDirectory.standardizedFileURL.path + "/")
        if isStaged {
            try? removeItem(parent)
        } else {
            try? removeItem(staged)
        }
    }
}
