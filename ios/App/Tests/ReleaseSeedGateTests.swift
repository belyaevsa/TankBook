import XCTest

/// PJ.7g: the RELEASE build must not contain, and must not reference, any seed
/// harness symbol. The seed types, the stub session, the seeded transports and
/// the config seed are each compiled under `#if DEBUG`; this test scans the app
/// SOURCE for the invariant that no seed symbol appears on a line the compiler
/// would emit in a RELEASE build.
///
/// Why a source scan and not a runtime assertion: the guarantee is about the
/// configuration the test does NOT run in. This bundle builds DEBUG (like every
/// test), so a runtime check would only ever prove the DEBUG behaviour - which
/// is exactly the vacuous trap. A RELEASE build that fails to compile is the
/// compile-time half of the proof (any reference to a gated seed type outside
/// `#if DEBUG` is a "cannot find type in scope" error); this scan is the other
/// half: it catches a seed type left COMPILED INTO a release (gated off its call
/// sites but still present in the binary), which compiles fine and ships the
/// Keychain-planting machinery anyway.
///
/// The scan is `#if`-aware, not a grep: it tracks `#if DEBUG` / `#else` /
/// `#endif` nesting and flags a seed symbol only when the enclosing region is
/// active in RELEASE. The symbol list is the enumerated harness, so adding a
/// new seed without a guard is a failure here. If the source tree is absent the
/// test FAILS - a guard that silently skips would be worth nothing.
final class ReleaseSeedGateTests: XCTestCase {

    /// The enumerated seed harness. Each name must never appear in release-
    /// active source: seed types, seed entry points, the stub transports, the
    /// stub session writer and the test-only repository wipe.
    private static let seedSymbols = [
        "HomeTestSeed", "AnomalyTestSeed", "ManualFillUpTestSeed", "RecentlyDeletedTestSeed",
        "SettingsTestSeed", "SeededLaunch", "SeededLaunchTransport", "AuthExpiredTransport",
        "ServerDownTransport", "SignInSyncStubTransport", "FlaggedBatchSyncStubTransport",
        "CarSwitcherTestSeed", "EditEntryTestSeed", "PhotoSyncingTestSeed", "ImportTestSeed",
        "ReminderTestSeed", "ReminderFormPrefillSeed", "PartsShelfTestSeed",
        "ServiceEntryPrefillSeed", "ServiceEntryTestSeed", "SignInTestSeed", "TireSetTestSeed",
        "TrendsTestSeed", "GarageTestSeed", "TankLevelTestSeed", "VehicleDetailTestSeed",
        "AppConfigTestSeed", "DebugLaunch", "NotificationResponseReplay", "ConfirmPrefillSeed",
        "RateBackfillDebugHook", "ImportStubTransport", "FailingImportTransport",
        "AccountStubTransport", "FailingAccountTransport", "RateStubTransport",
        "FailingFeedbackTransport", "RateLimitedFeedbackTransport",
        "stubSession", "seedSessionAtLaunchIfRequested", "resetForTestsOncePerLaunch",
        "resetForTestsIfRequested", "seedAttachSuggestionIfRequested",
        "StubIDTokenProvider", "StubAuthService", "StubRestoreProvider",
    ]

    func testNoSeedSymbolIsReleaseActive() throws {
        let sources = try Self.sourcesDirectory()
        let files = try Self.swiftFiles(under: sources)
        XCTAssertFalse(files.isEmpty, "no source files found under \(sources.path)")

        var violations: [String] = []
        for file in files {
            violations.append(contentsOf: Self.releaseActiveSeedSymbols(in: file))
        }

        XCTAssertTrue(
            violations.isEmpty,
            "seed harness reachable in a RELEASE build:\n" + violations.joined(separator: "\n"))
    }

    // MARK: - Scanning

    /// Returns `file:line: symbol` for every seed symbol that appears on a line
    /// the compiler emits in a RELEASE build.
    private static func releaseActiveSeedSymbols(in file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var violations: [String] = []
        // true when the enclosing `#if DEBUG` block is in its DEBUG (true) branch.
        // A line is release-active iff no enclosing block is in its DEBUG branch.
        var debugBranches: [Bool] = []

        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if") {
                debugBranches.append(trimmed.contains("DEBUG"))
                continue
            }
            if trimmed == "#else" || trimmed.hasPrefix("#elseif") {
                // In a DEBUG/!DEBUG conditional, the else branch is release-active.
                if !debugBranches.isEmpty { debugBranches[debugBranches.count - 1] = false }
                continue
            }
            if trimmed == "#endif" {
                if !debugBranches.isEmpty { debugBranches.removeLast() }
                continue
            }

            let releaseActive = !debugBranches.contains(true)
            guard releaseActive else { continue }

            let code = line.components(separatedBy: "//").first ?? ""
            for symbol in seedSymbols where Self.contains(symbol, in: code) {
                violations.append("\(file.lastPathComponent):\(offset + 1): \(symbol)")
            }
        }
        return violations
    }

    /// True when `symbol` appears in `line` as a standalone identifier (not a
    /// substring of a longer name). Word-boundary checked by hand so the scan
    /// never depends on regex-engine lookbehind support.
    private static func contains(_ symbol: String, in line: String) -> Bool {
        var searchStart = line.startIndex
        while let range = line.range(of: symbol, range: searchStart..<line.endIndex) {
            let beforeOK: Bool
            if range.lowerBound == line.startIndex {
                beforeOK = true
            } else {
                let before = line[line.index(before: range.lowerBound)]
                beforeOK = !before.isLetter && !before.isNumber && before != "_"
            }
            let afterOK: Bool
            if range.upperBound == line.endIndex {
                afterOK = true
            } else {
                let after = line[range.upperBound]
                afterOK = !after.isLetter && !after.isNumber && after != "_"
            }
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }

    // MARK: - Source tree

    /// The app source directory, resolved from the compile-time path of this
    /// test file (`ios/App/Tests/ReleaseSeedGateTests.swift` -> repo root).
    private static func sourcesDirectory() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        var candidate = thisFile.deletingLastPathComponent() // ios/App/Tests
        for _ in 0..<3 { candidate = candidate.deletingLastPathComponent() } // -> repo root
        let sources = candidate.appendingPathComponent("ios/App/Sources", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw NSError(
                domain: "ReleaseSeedGateTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "app source tree not found at \(sources.path) - the seed gate cannot run"])
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
