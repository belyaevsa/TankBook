import Foundation
import Observation
import SwiftUI
import TankbookCore

/// A file another app handed to Tankbook (the share sheet / "Open in", J2:
/// "shares the file to Tankbook"). The root stages the copy here and opens the
/// import wizard, which takes the file at its source step in place of the
/// picker - the user still declares which app it came from; the app never
/// sniffs the file (hard rule 13).
@MainActor
@Observable
final class ImportShareInbox {
    struct SharedFile: Equatable {
        /// The staged copy inside the app container (the incoming URL's scope
        /// is gone by the time the wizard reads it - RV.73's rule).
        let url: URL
        let name: String
    }

    private(set) var sharedFile: SharedFile?

    /// Stages `url` for the wizard. Returns false when the bytes could not be
    /// copied - the caller then has nothing to open.
    func receive(_ url: URL) -> Bool {
        let stager = ImportService.makePickedFileStager()
        switch stager.stage(url, log: AppLog.shared) {
        case .staged(let copy):
            if let previous = sharedFile { stager.dispose(previous.url) }
            sharedFile = SharedFile(url: copy, name: url.lastPathComponent)
            return true
        case .readFailed:
            return false
        }
    }

    /// The wizard takes the file; a second wizard opening finds none.
    func take() -> SharedFile? {
        defer { sharedFile = nil }
        return sharedFile
    }
}

/// The share-to-Tankbook door on the root (docs/JOURNEYS.md J2): a file
/// opened into the app is staged and the Log tab lands on the import wizard
/// at its source step. A file that cannot be read opens nothing - the wizard
/// would only show its read-failure card with no file to name.
private struct SharedFileOpener: ViewModifier {
    @State private var inbox = ImportShareInbox()
    @Binding var tab: AppTab
    @Binding var logPath: [Route]

    func body(content: Content) -> some View {
        content
            .environment(inbox)
            .onOpenURL { url in open(url) }
            #if DEBUG
            .task { openLaunchFixtureIfRequested() }
            #endif
    }

    private func open(_ url: URL) {
        guard inbox.receive(url) else { return }
        tab = .log
        logPath = [.importWizard]
    }

    #if DEBUG
    /// `-openFile <name>`: a UI test's stand-in for the share sheet - a CSV
    /// under that name is written to the temporary directory and opened the
    /// way the system would open a shared file.
    private func openLaunchFixtureIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-openFile"),
              arguments.indices.contains(index + 1) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(arguments[index + 1])
        try? Data("Date;Volume;Price\n01/09/2026;42.1;1.679\n".utf8).write(to: url)
        open(url)
    }
    #endif
}

extension View {
    /// Owns the `ImportShareInbox` the wizard reads from the environment.
    func sharedFileOpener(tab: Binding<AppTab>, logPath: Binding<[Route]>) -> some View {
        modifier(SharedFileOpener(tab: tab, logPath: logPath))
    }
}

extension L10n {
    /// "Read receipts.csv" - the source step's primary action when another
    /// app shared the file. One phrase per language; the name is data.
    static func readSharedFile(fileName: String) -> String {
        String(format: localize("Read %1$@"), fileName)
    }
}
