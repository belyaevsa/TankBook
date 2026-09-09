import Foundation
import Testing

// RV.157 - the source-scan guard for docs/SYNC.md's trigger list. Line 151 once
// promised a cycle "after every local write (debounced)" that no code performed;
// the row exists because that sentence sat OUTSIDE the wired-vs-policy-only
// guard (`LowPowerModeTests.productionCallSitesMatchTheWiredAndUnwiredSplit`),
// which only scans `defers(work:)` call sites. This guard closes the gap it
// left: every WIRED trigger the doc names must have a real call site in the
// sources. Delete a trigger's call site (or drop the trigger from the doc) and
// this test fails - the teeth are demonstrated by mutating one line and running.
//
// The unwired trigger - the push-notification nudge - is marked "[v1.x], NOT
// wired" in the doc (NOTIFICATIONS.md plans it for v1.x), so the guard does NOT
// require a call site for it. Deleting that clause would break the "the doc
// still names it as unwired" assertion below, which is the deliberate inverse:
// the nudge must stay documented as planned-but-unwired, never relisted as if it
// were wired.
@Suite("Sync trigger source-scan guard (RV.157)")
struct SyncTriggerSourceGuardTests {

    /// The wired triggers docs/SYNC.md must name, mapped to the source symbol
    /// that must have a call site. One entry per trigger in the doc's "- Sync
    /// cycle:" bullet; adding a wired trigger means adding it here AND in the
    /// doc, never one alone.
    private struct WiredTrigger {
        let docMarker: String
        let callSite: String
        let requiredIn: String
    }

    private static let wiredTriggers: [WiredTrigger] = [
        WiredTrigger(docMarker: "**App foreground**",
                     callSite: "runOpportunisticSync()",
                     requiredIn: "Navigation/TabRoots.swift"),
        WiredTrigger(docMarker: "**After every local write (debounced)**",
                     callSite: "noteLocalWrite()",
                     requiredIn: "Settings/AppSync.swift")
    ]

    @Test func everyWiredTriggerNamedInTheDocHasACallSite() throws {
        let syncDoc = try syncDoc()
        let triggerBullet = try triggerBullet(in: syncDoc)

        for trigger in Self.wiredTriggers {
            let marker = trigger.docMarker.replacingOccurrences(of: "**", with: "")
            #expect(triggerBullet.contains(marker),
                    "the Sync cycle bullet must name the \(marker) trigger:\n\(triggerBullet)")
            let source = try appSource(trigger.requiredIn)
            #expect(source.contains(trigger.callSite),
                    "\(trigger.callSite) must exist in \(trigger.requiredIn) (doc names it wired)")
        }
    }

    /// The write trigger must actually route a local write into the ONE sync
    /// door (`runSync(.background)`) - pinning the wiring, not just the symbol.
    /// Without this, `noteLocalWrite` could exist yet be dead, which is the
    /// same fiction in a new form.
    @Test func theWriteTriggerRoutesThroughTheSingleSyncDoor() throws {
        let source = try appSource("Settings/AppSync.swift")

        // The poke seam: the app observes the repository write signal.
        #expect(source.contains("ensureWriteTriggerArmed"),
                "AppSync must arm the repository write signal")
        #expect(source.contains("writeSignal.observer"),
                "the armed observer must register on the database write signal")
        #expect(source.contains("noteLocalWrite()"),
                "the observer must poke noteLocalWrite on a local write")

        // The one door: the debounced cycle runs the SAME background trigger the
        // foreground pass uses - never a second SyncEngine.
        #expect(source.contains("runSync(trigger: .background)"),
                "the write-triggered cycle must run through runSync(.background)")
        #expect(source.contains("SyncWriteScheduler"),
                "the debounce must live in SyncWriteScheduler (core)")
    }

    /// The nudge stays documented as unwired. This is the deliberate inverse of
    /// the wired checks: deleting the clause (or silently relisting the nudge as
    /// wired without a call site) fails here.
    @Test func thePushNudgeStaysDocumentedAsUnwired() throws {
        let bullet = try triggerBullet(in: syncDoc())
        #expect(bullet.contains("Push notification nudge"),
                "the nudge trigger must stay documented (NOTIFICATIONS.md plans it for v1.x)")
        #expect(bullet.contains("NOT wired"),
                "the doc must mark the nudge as not wired - the guard requires call sites only for wired triggers")
        #expect(bullet.contains("[v1.x]"),
                "the nudge must be marked v1.x - it is planned, not built")
    }

    // MARK: - Source/doc resolution

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TankbookCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()  // repo root

    private func syncDoc() throws -> String {
        let url = Self.repoRoot.appendingPathComponent("docs/SYNC.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func appSource(_ relativePath: String) throws -> String {
        let url = Self.repoRoot.appendingPathComponent("ios/App/Sources")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The "- Sync cycle:" bullet, from its start to the next bullet at the same
    /// indentation. The trigger list lives inside it.
    private func triggerBullet(in doc: String) throws -> String {
        guard let start = doc.range(of: "- Sync cycle:") else {
            throw NSError(domain: "SyncTriggerSourceGuardTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "- Sync cycle: bullet not found in docs/SYNC.md"])
        }
        let remainder = doc[start.upperBound...]
        // The bullet's continuation lines are indented; the next top-level
        // bullet is a newline followed by "- " at column 0.
        if let next = remainder.range(of: "\n- ", options: []) {
            return String(remainder[..<next.lowerBound])
        }
        return String(remainder)
    }
}
