import XCTest
@testable import Tankbook

/// PR.16: docs/SECURITY.md promises `completeUntilFirstUserAuthentication` on
/// the database triple and on attachment files, and nothing set it - the class
/// rode the platform default. These are executed assertions against real files
/// on disk in the app's own container (L2), so they must live in the app-target
/// test bundle: the SwiftPM core tests run on macOS, where the app's
/// Application Support path does not exist and the protection attribute does
/// nothing. The `-wal` and `-shm` files carry the most recent rows; asserting
/// only `.sqlite` would prove nothing about them.
///
/// Simulator caveat: the iOS Simulator does not emulate data protection, so
/// `resourceValues` reports the class as a constant on the simulator while a
/// real device reflects what the code set. The mutation run (PR.16 report)
/// proves the assertion discriminates: a file whose protection reads anything
/// but `.completeUntilFirstUserAuthentication` - including nil - fails the
/// assert naming the file.
@MainActor
final class FileProtectionTests: XCTestCase {

    func testDatabaseTripleCarriesCompleteUntilFirstUserAuthentication() throws {
        _ = try AppStore.repository()
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("Tankbook", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("tankbook.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            try assertCompleteProtection(URL(fileURLWithPath: databaseURL.path + suffix))
        }
    }

    func testWrittenAttachmentCarriesCompleteUntilFirstUserAuthentication() throws {
        let id = UUID()
        let (_, relativePath) = try VehiclePhotoStore.save(Data("PR.16 test attachment".utf8), id: id)
        let url = try VehiclePhotoStore.attachmentsDirectory().appendingPathComponent(relativePath)
        defer { try? FileManager.default.removeItem(at: url) }
        try assertCompleteProtection(url)
    }

    private func assertCompleteProtection(_ url: URL,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) throws {
        let values = try url.resourceValues(forKeys: [.fileProtectionKey])
        let actual = values.fileProtection
        let message = "\(url.lastPathComponent): file protection = \(actual?.rawValue ?? "nil")"
        XCTAssertEqual(actual, .completeUntilFirstUserAuthentication, message, file: file, line: line)
    }
}
