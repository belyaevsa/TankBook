import XCTest

/// RV.127 - the feedback outbox promises an automatic retry that nothing
/// triggered. The retry behaviour is pinned at L1 (`FeedbackTests`: a persisted
/// queued case is sent by a flush from a cold start, no connectivity keeps it
/// queued, a flush racing a manual retry posts once). What was MISSING was the
/// trigger: `FeedbackOutbox.flush()` had zero call sites.
///
/// This is the trigger test. It cannot invoke `runAutomaticPass` - it is a
/// private method of the SwiftUI root view, constructed only by launching the
/// app - and a SUCCESSFUL flush is deliberately silent (a 202 removes the case;
/// the user sees nothing either way), so no L4 black-box test can distinguish
/// "the pass flushed it" from "the pass never called flush" - which is exactly
/// the defect. So the wiring is pinned structurally, the same way
/// `ReleaseSeedGateTests` pins its invariant: deleting the flush from the
/// automatic pass makes this test fail on HEAD - the dead code the row is about
/// comes back.
final class FeedbackForegroundFlushTests: XCTestCase {

    func testTheAutomaticPassInvokesTheFeedbackFlush() throws {
        let source = try Self.appSourceFile("Navigation/TabRoots.swift")

        // The call must live in runAutomaticPass's body, not anywhere else in
        // the file - "flush is called somewhere" would pass while the automatic
        // pass stays dead.
        let region = try Self.body(ofFunction: "runAutomaticPass", in: source)
        XCTAssertTrue(region.contains("await FeedbackService.outbox.flush()"),
                      "runAutomaticPass must drain the feedback outbox:\n" + region)
    }

    func testThePassAndTheAboutComposerShareOneOutbox() throws {
        // A second FeedbackOutbox over the same queue file is the double-post
        // bug: the About composer must submit through the SAME memoized outbox
        // the automatic pass flushes, never one it builds itself.
        let service = try Self.appSourceFile("Settings/FeedbackService.swift")
        XCTAssertTrue(service.contains("static var outbox: FeedbackOutbox"),
                      "FeedbackService must expose the one app-wide outbox")
        XCTAssertTrue(service.contains("if let cachedOutbox { return cachedOutbox }"),
                      "the one outbox must be memoized, never rebuilt per caller")
        XCTAssertTrue(service.contains("return FeedbackModel(outbox: outbox,"),
                      "makeModel must build the composer over the shared outbox")
    }

    // MARK: - Source resolution and slicing

    /// Reads an app source file, resolved from this test file's own path
    /// (`ios/App/Tests/...` -> repo root -> `ios/App/Sources/<rel>`).
    private static func appSourceFile(_ relativePath: String) throws -> String {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        var candidate = thisFile.deletingLastPathComponent() // ios/App/Tests
        for _ in 0..<3 { candidate = candidate.deletingLastPathComponent() } // -> repo root
        let file = candidate.appendingPathComponent("ios/App/Sources")
            .appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw NSError(domain: "FeedbackForegroundFlushTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "app source not found at \(file.path) - the trigger gate cannot run"])
        }
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// Returns the text of `func <name>` up to its closing brace (the first
    /// `}` at the method's own 4-space indentation - bodies nest deeper).
    private static func body(ofFunction name: String, in source: String) throws -> String {
        guard let start = source.range(of: "func \(name)") else {
            throw NSError(domain: "FeedbackForegroundFlushTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey:
                            "func \(name) not found - the automatic pass moved?"])
        }
        guard let bodyStart = source[start.upperBound...].range(of: "{") else {
            throw NSError(domain: "FeedbackForegroundFlushTests", code: 3,
                          userInfo: [NSLocalizedDescriptionKey:
                            "func \(name) has no body"])
        }
        let bodyOpen = source.index(bodyStart.lowerBound, offsetBy: 1)
        guard let close = source[bodyOpen...].range(of: "\n    }\n") else {
            throw NSError(domain: "FeedbackForegroundFlushTests", code: 4,
                          userInfo: [NSLocalizedDescriptionKey:
                            "could not find the end of func \(name)"])
        }
        return String(source[bodyOpen..<close.lowerBound])
    }
}
