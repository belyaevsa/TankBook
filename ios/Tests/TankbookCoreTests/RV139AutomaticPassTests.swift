import Foundation
import os
import Testing
@testable import TankbookCore

// RV.139b - job 1c and job 2. Three families:
//
//  1. The automatic foreground pass is OBSERVABLE: `AutomaticPassRunner` marks
//     each step in the log BEFORE awaiting its work, so a session's log says
//     which step the pass reached and that it finished, and a hang at step N
//     keeps the marks for every step up to and including N (the L1 behavioural
//     half is the runner, driven here with a gated/hanging step).
//  2. The pass is REACHED in the two shapes production takes: a scene already
//     `.active` when the view attaches (the `.task` fallback) and an `.active`
//     transition after a resign (`didRunAutomaticPass` gates the dedupe). Both
//     are pinned against the source, because `runAutomaticPass` is a private
//     method of a SwiftUI root view that only launching the app constructs - the
//     same structural-pin pattern as `FeedbackForegroundFlushTests`.
//  3. A slow/hanging sync cannot stop a LATER foreground pass from reaching
//     `AppRates.refresh()`: the pass awaits sync before rates (so its own sync
//     must return first), and `AppSync.runSync` begins with `guard !isSyncing`,
//     which is what makes a fresh pass's sync return immediately while an
//     earlier one is still in flight. Both halves are pinned against the source.

// MARK: - Test doubles + helpers

/// A continuation gate: `wait()` suspends until `open()` resumes it. Resumption
/// happens on this actor, so a `@MainActor` runner suspended at `wait()` does
/// not deadlock the `@MainActor` test that opens it.
private actor PassGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private func makeLog() -> (TankbookLog, InMemorySink) {
    let sink = InMemorySink()
    let log = TankbookLog(sink: sink,
                          context: { LogContext(deviceId: nil, appVersion: "test", platform: "ios") })
    return (log, sink)
}

/// Polls until `condition` holds, so a `@MainActor` test can wait for the
/// (also `@MainActor`) runner to reach a mark. The sleep yields the main actor.
private func waitUntil(timeoutNanoseconds: UInt64 = 2_000_000_000,
                       _ condition: @escaping @Sendable () async -> Bool) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !(await condition()) {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("timed out waiting for the condition")
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - Source resolution (core tests may read the app sources - see
// `LowPowerModeTests`, `ConfigBaseURLGrepGateTests`)

private let iosRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // TankbookCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // ios

private func appSource(_ relativePath: String) throws -> String {
    let url = iosRoot.appendingPathComponent("App/Sources")
        .appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw NSError(domain: "RV139AutomaticPassTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey:
                        "app source not found at \(url.path) - the gate cannot run"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// Slices one `func`'s body: from after the opening `{` to the first `\n    }\n`
/// (the method's own 4-space-indented close). Mirrors `FeedbackForegroundFlushTests`.
private func body(ofFunction name: String, in source: String) throws -> String {
    guard let start = source.range(of: "func \(name)") else {
        throw NSError(domain: "RV139AutomaticPassTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "func \(name) not found"])
    }
    guard let bodyStart = source[start.upperBound...].range(of: "{") else {
        throw NSError(domain: "RV139AutomaticPassTests", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "func \(name) has no body"])
    }
    let bodyOpen = source.index(bodyStart.lowerBound, offsetBy: 1)
    guard let close = source[bodyOpen...].range(of: "\n    }\n") else {
        throw NSError(domain: "RV139AutomaticPassTests", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "could not find the end of func \(name)"])
    }
    return String(source[bodyOpen..<close.lowerBound])
}

private extension InMemorySink {
    /// The ordered `automatic.pass` step marks in this sink's rendered output.
    func automaticPassMarks() -> [AutomaticPassMark] {
        rendered().compactMap { line in
            guard line.contains("event=automatic.pass"),
                  let stepRaw = line.components(separatedBy: "step=").dropFirst().first?
                    .components(separatedBy: " ").first,
                  let mark = AutomaticPassMark(rawValue: stepRaw) else { return nil }
            return mark
        }
    }
}

// MARK: - The runner: the pass records the step it reached (L1, behavioural)

@Suite("Automatic foreground pass observability (RV.139b)")
struct RV139AutomaticPassTests {

    /// A full pass marks every step exactly once, in order, and finishes: the
    /// `automatic.pass` line vocabulary IS the whole ordered step set, so the
    /// mark list of a healthy pass equals the enum's cases and nothing more -
    /// a step added to the runner without a mark, or marked out of order, shows
    /// up here.
    @MainActor
    @Test func aFullPassMarksEveryStepInOrderAndFinishes() async {
        let (log, sink) = makeLog()

        await AutomaticPassRunner.run(steps: [
            AutomaticPassRunner.Step(code: .config) {},
            AutomaticPassRunner.Step(code: .summary) {},
            AutomaticPassRunner.Step(code: .sync) {},
            AutomaticPassRunner.Step(code: .rates) {},
            AutomaticPassRunner.Step(code: .delivery) {},
            AutomaticPassRunner.Step(code: .feedback) {},
        ], log: log)

        #expect(sink.automaticPassMarks() == AutomaticPassMark.allCases,
                "a full pass marks started, each step, then finished - in order, once each")
        #expect(sink.rendered().filter { $0.contains("event=automatic.pass") }.count
                == AutomaticPassMark.allCases.count,
                "exactly one line per mark - the pass runs on every foreground, so it stays cheap")
    }

    /// The row's core L1 question: a step that HANGS must not erase the record
    /// of the steps before it. Because the runner writes each mark before the
    /// await it names, a pass stalled at sync still shows started/config/summary/
    /// sync and nothing after - which is exactly what separates "the pass never
    /// reached rates" from "the pass reached sync and died there" in one log.
    @MainActor
    @Test func aHangingStepKeepsTheRecordOfTheStepsBeforeIt() async throws {
        let gate = PassGate()
        let (log, sink) = makeLog()

        let pass = Task { @MainActor in
            await AutomaticPassRunner.run(steps: [
                AutomaticPassRunner.Step(code: .config) {},
                AutomaticPassRunner.Step(code: .summary) {},
                AutomaticPassRunner.Step(code: .sync) { await gate.wait() },
                AutomaticPassRunner.Step(code: .rates) {},
            ], log: log)
        }

        // Wait until the pass is stuck at the sync step.
        await waitUntil { sink.rendered().contains { $0.contains("step=sync") } }
        #expect(sink.automaticPassMarks() == [.started, .config, .summary, .sync],
                "the pass must record every step it reached before the stall, got \(sink.automaticPassMarks())")
        #expect(!sink.rendered().contains { $0.contains("step=rates") },
                "a step after the stall must not be marked")

        // The stall clears: the SAME pass resumes and finishes, its prior marks
        // intact (nothing was erased by the wait).
        await gate.open()
        await pass.value
        #expect(sink.automaticPassMarks() == [.started, .config, .summary, .sync, .rates, .finished],
                "releasing the stall lets the pass finish without losing the record")
    }

    /// The event is shape only (hard rule 12): a step code and nothing else.
    /// This sweep covers the new line exactly as `theRateRefreshEventCarriesShapeOnly`
    /// covers `rates.refresh`.
    @Test func theAutomaticPassEventCarriesShapeOnly() {
        let (log, sink) = makeLog()
        log.emit(AutomaticPass(step: .started))
        log.emit(AutomaticPass(step: .rates))
        log.emit(AutomaticPass(step: .finished))

        let text = sink.rendered()
        #expect(text.count == 3)
        for line in text {
            #expect(line.contains("event=automatic.pass"))
            #expect(!line.contains("PLN") && !line.contains("EUR") && !line.contains("USD"),
                    "no currency code may reach the line (hard rule 12)")
            #expect(!line.contains("https://"),
                    "no URL may reach the line (hard rule 12)")
        }
        #expect(text[0].contains("step=started"))
        #expect(text[1].contains("step=rates"))
        #expect(text[2].contains("step=finished"))
    }
}

// MARK: - The pass is reached in production's two shapes (job 2, source-pinned)

@Suite("Automatic pass reachability (RV.139b)")
struct RV139AutomaticPassReachabilityTests {

    /// The pass must run its six steps THROUGH the runner (so every step is
    /// marked), in the order config -> summary -> sync -> rates -> delivery ->
    /// feedback. Deleting the runner call, dropping a step, or reordering steps
    /// past the rate refresh breaks this gate.
    @Test func thePassRunsEveryStepThroughTheRunnerInOrder() throws {
        let source = try appSource("Navigation/TabRoots.swift")
        let region = try body(ofFunction: "runAutomaticPass", in: source)

        #expect(region.contains("AutomaticPassRunner.run"),
                "the pass must route through AutomaticPassRunner so every step is marked")
        let expectedOrder = ["config", "summary", "sync", "rates", "delivery", "feedback"]
        var last: String.Index = region.startIndex
        for step in expectedOrder {
            guard let found = region.range(of: "AutomaticPassRunner.Step(code: .\(step))") else {
                Issue.record("runAutomaticPass must include the .\(step) step")
                return
            }
            #expect(found.lowerBound >= last,
                    "step .\(step) must not move before an earlier step in the pass")
            last = found.upperBound
        }

        // Each step is wired to the awaited work the docs name for it - the
        // ordering is only load-bearing if the steps are the real ones.
        #expect(region.contains("await configService.refresh()"))
        #expect(region.contains("reconcileMonthlySummary()"))
        #expect(region.contains("runOpportunisticSync()"))
        #expect(region.contains("await AppRates.refresh()"))
        #expect(region.contains("await inbox.drainOutbox()"))
        #expect(region.contains("await FeedbackService.outbox.flush()"))
    }

    /// Candidate A's line-pinned refutation, stated as a gate: rates must be
    /// reached AFTER the opportunistic sync (a slow sync can only delay the
    /// CURRENT pass, and `guard !isSyncing` skips a stuck sync on the NEXT
    /// one) and BEFORE the two outbox drains - so the RV.132 feedback marker
    /// stays downstream of rates for the sessions that run the pass.
    @Test func ratesIsReachedAfterSyncAndBeforeTheOutboxDrains() throws {
        let source = try appSource("Navigation/TabRoots.swift")
        let region = try body(ofFunction: "runAutomaticPass", in: source)

        let sync = try #require(region.range(of: "Step(code: .sync)"))
        let rates = try #require(region.range(of: "Step(code: .rates)"))
        let delivery = try #require(region.range(of: "Step(code: .delivery)"))
        let feedback = try #require(region.range(of: "Step(code: .feedback)"))
        #expect(sync.lowerBound < rates.lowerBound,
                "rates must be reached AFTER sync, never before")
        #expect(rates.lowerBound < delivery.lowerBound,
                "the rate refresh must precede the delivery-outbox drain")
        #expect(rates.lowerBound < feedback.lowerBound,
                "the rate refresh must precede the feedback flush")
    }

    /// The mechanism that lets a LATER foreground pass reach rates while an
    /// EARLIER one is still in sync: `AppSync.runSync` must return immediately
    /// when a sync is already running (`guard !isSyncing`), and the pass's sync
    /// step must go through `runOpportunisticSync` (which calls `runSync`).
    /// Removing that guard makes a fresh foreground pass join the stuck cycle
    /// instead of skipping it - the candidate-A failure the device log cannot
    /// wait for.
    @Test func aSecondPassSkipsASyncAlreadyInFlight() throws {
        let syncSource = try appSource("Settings/AppSync.swift")

        let runSyncRegion = try body(ofFunction: "runSync", in: syncSource)
        #expect(runSyncRegion.contains("guard !isSyncing"),
                "runSync must bail when a sync is already running, so a later pass's sync cannot hang on it")
        #expect(runSyncRegion.contains("guard !isSyncing, configService.allowsServerBacked"),
                "the isSyncing gate must sit at the top of runSync, before any coordinator work")

        #expect(syncSource.contains("func runOpportunisticSync()"),
                "the pass's sync door must exist")
        #expect(syncSource.contains("await runSync(trigger: .background)"),
                "runOpportunisticSync must run the same single-flight runSync the gate protects")
    }

    /// Shape 1 - a scene already `.active` when the view attaches: the `.task`
    /// fallback runs the pass, gated on `didRunAutomaticPass` so the launch
    /// `.active` transition (when it does arrive) cannot double it.
    @Test func anAlreadyActiveSceneRunsThePassFromTheTaskFallback() throws {
        let source = try appSource("Navigation/TabRoots.swift")

        #expect(source.contains("if scenePhase == .active, !didRunAutomaticPass {"),
                "the .task fallback must run the pass when the scene is already active and nothing has claimed it")
        guard let fallback = source.range(of: "if scenePhase == .active, !didRunAutomaticPass {") else {
            return
        }
        let tail = source[fallback.lowerBound...]
        #expect(tail.contains("didRunAutomaticPass = true"),
                "the fallback must claim the pass before running it")
        #expect(tail.contains("await runAutomaticPass()"),
                "the fallback must actually run the pass")
    }

    /// Shape 2 - an `.active` transition after a resign (a warm foreground):
    /// the handler claims the pass (`didRunAutomaticPass`), runs it, and the
    /// resign arms the next foreground by resetting the flag. This is the shape
    /// the row has always asked about - "does a warm foreground reach the pass
    /// at all" - and deleting the `Task { await runAutomaticPass() }` arm, or
    /// never resetting the flag on resign, is what would answer it "no".
    @Test func anActiveTransitionAfterAResignRunsThePassAndResignArmsTheNext() throws {
        let source = try appSource("Navigation/TabRoots.swift")

        #expect(source.contains("case .active:"),
                "the scenePhase handler must have an .active arm")
        #expect(source.contains("guard !didRunAutomaticPass else { return }"),
                "one .active = one pass: a burst of active transitions must not start a second pass")
        #expect(source.contains("Task { await runAutomaticPass() }"),
                "the .active transition must run the pass")
        #expect(source.contains("case .inactive, .background:"),
                "the scenePhase handler must reset on resign")
        #expect(source.contains("didRunAutomaticPass = false"),
                "a resign must re-arm the pass so the next real foreground runs it again")
    }
}
