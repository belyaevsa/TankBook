import Foundation

#if !os(macOS)
/// iOS has no subprocesses. The package's test target also runs in the iOS
/// simulator, where the Vision accuracy suites are measured
/// (`docs/TESTING.md` -> "The OCR accuracy suites are runtime-specific"); the
/// host-tooling tests that shell out to `python3`, `git` or `sqlite3` compile
/// there against this stand-in, whose `run()` throws, and are not run there.
final class Process {
    struct Unavailable: Error {}

    var executableURL: URL?
    var arguments: [String]?
    var currentDirectoryURL: URL?
    var environment: [String: String]?
    var standardError: Any?
    var standardOutput: Any?
    private(set) var terminationStatus: Int32 = -1

    func run() throws { throw Unavailable() }
    func waitUntilExit() {}
}
#endif
