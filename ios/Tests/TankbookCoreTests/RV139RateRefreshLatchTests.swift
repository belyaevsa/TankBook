import Foundation
import os
import Testing
@testable import TankbookCore

// RV.139 - the client never asks for exchange rates. Production shows sync and
// config traffic but not one `/v1/rates/pack` across three builds. This suite
// pins the single-flight slot in `RateStore.refresh` (RV.59) against the one
// failure the row names: the creator of the in-flight fetch task being cancelled
// or abandoned between claiming the slot and clearing it, leaving the slot set
// forever so every later `refresh()` joins a finished task and returns `true`
// WITHOUT issuing a request.
//
// The traps named in the row, avoided here by construction:
//   - asserting `refresh()` returned true (it does on the join path - the bug);
//     every assertion is a REQUEST COUNT on the fetcher double,
//   - testing with a fresh store (the latch cannot have formed), and
//   - concluding Low Power Mode without checking that sync deferred too.

// MARK: - Test doubles

/// Holds a fetch open until `open()` - "a pack fetch is on the wire" becomes an
/// observable, deterministic state rather than a timing accident.
private actor FetchGate {
    private var hasStarted = false
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signalStarted() { hasStarted = true }
    var started: Bool { hasStarted }
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Counts `/rates/pack` fetches, optionally stalling them on a gate.
private final class GatedCountingFetcher: RateFetcher, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    private let gate: FetchGate?

    init(gate: FetchGate? = nil) { self.gate = gate }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> RatePack {
        lock.withLock { $0 += 1 }
        await gate?.signalStarted()
        await gate?.wait()
        return RatePack(rates: [])
    }

    var fetchCount: Int { lock.withLock { $0 } }
}

// MARK: - The latch: an interrupted creator must not silence every later refresh

/// The row's whole point, run as the hypothesis states it: the creator of the
/// in-flight fetch is CANCELLED while the fetch is on the wire. If the single-
/// flight slot can be left set, the later `refresh()` joins the finished task
/// and no second request is ever issued. The assertion is the REQUEST COUNT,
/// never the return value - `refresh()` returns `true` on the join path.
@Test func anInterruptedCreatorDoesNotLatchTheSingleFlightSlot() async throws {
    let gate = FetchGate()
    let fetcher = GatedCountingFetcher(gate: gate)
    let store = RateStore(seed: [], fetcher: fetcher)

    // Creator A claims the slot and its fetch is now on the wire.
    let creator = Task { await store.refresh() }
    while await !gate.started { try await Task.sleep(for: .milliseconds(1)) }
    #expect(fetcher.fetchCount == 1, "the first refresh must issue exactly one request")

    // A second trigger WHILE the fetch is in flight joins it: single-flight
    // (RV.59) must still hold - one request, not two.
    let joiner = Task { await store.refresh() }
    try? await Task.sleep(for: .milliseconds(20))

    // The view-shaped interruption: the creator is cancelled mid-await.
    creator.cancel()

    // The fetch completes; the creator's cancellation must not stop the slot
    // from clearing.
    await gate.open()
    _ = await creator.value
    _ = await joiner.value

    // A LATER refresh must fetch again. If the slot is still set (the latch),
    // this joins the finished task and the count stays at 1.
    await store.refresh()
    #expect(fetcher.fetchCount == 2,
            "an interrupted creator must not leave the slot set - a later refresh must fetch")
}

/// The abandoned-creator shape: the task that claimed the slot is dropped
/// without being awaited (and cancelled), so nothing in the caller's world will
/// ever observe its result. Only the store's own clear can release the slot.
@Test func anAbandonedCreatorDoesNotLatchTheSingleFlightSlot() async throws {
    let gate = FetchGate()
    let fetcher = GatedCountingFetcher(gate: gate)
    let store = RateStore(seed: [], fetcher: fetcher)

    let creator = Task { await store.refresh() }
    while await !gate.started { try await Task.sleep(for: .milliseconds(1)) }
    #expect(fetcher.fetchCount == 1)

    creator.cancel()
    // Never awaited: the creator handle is dropped while its fetch is on the
    // wire. This is the "abandoned caller" shape.
    await gate.open()
    // Give the runtime a beat to run whatever the cancelled creator has left.
    try? await Task.sleep(for: .milliseconds(100))

    await store.refresh()
    #expect(fetcher.fetchCount == 2,
            "an abandoned creator must not leave the slot set - a later refresh must fetch")
}

// MARK: - Observability: every branch records itself (RV.139)

/// Builds a `TankbookLog` over an `InMemorySink` so tests assert on the real
/// emitted output.
private func makeLog() -> (TankbookLog, InMemorySink) {
    let sink = InMemorySink()
    let log = TankbookLog(sink: sink,
                          context: { LogContext(deviceId: nil, appVersion: "test", platform: "ios") })
    return (log, sink)
}

/// A real fetch records `attempted` - the line that, in production, must be
/// followed by the fetch's own `net.request`. A refresh that never even logs
/// `attempted` never reached the fetch, which is the RV.139 question answered.
@Test func aRefreshThatFetchesEmitsAnAttemptedEvent() async {
    let fetcher = GatedCountingFetcher()
    let (log, sink) = makeLog()
    let store = RateStore(seed: [], fetcher: fetcher, log: log)

    await store.refresh()

    let events = sink.all().map(\.event)
    #expect(events.contains("rates.refresh"), "a refresh must record itself")
    #expect(sink.rendered().contains { $0.contains("outcome=attempted") },
            "the fetch branch must log outcome=attempted")
    #expect(sink.rendered().contains { $0.contains("trigger=background") },
            "the trigger must be on the line (hard rule 12: shape only)")
}

/// A refresh that joins an in-flight fetch records `joined` and issues no
/// request of its own. In production, a session full of `joined` with no
/// `attempted` is the single-flight slot never being released.
@Test func aRefreshThatJoinsEmitsAJoinedEventAndIssuesNoSecondRequest() async throws {
    let gate = FetchGate()
    let fetcher = GatedCountingFetcher(gate: gate)
    let (log, sink) = makeLog()
    let store = RateStore(seed: [], fetcher: fetcher, log: log)

    let first = Task { await store.refresh() }
    while await !gate.started { try await Task.sleep(for: .milliseconds(1)) }
    let second = Task { await store.refresh() }
    try? await Task.sleep(for: .milliseconds(20))
    await gate.open()
    _ = await first.value
    _ = await second.value

    #expect(fetcher.fetchCount == 1, "RV.59: two racing triggers issue ONE request")
    let text = sink.rendered()
    #expect(text.contains { $0.contains("outcome=attempted") },
            "the creator branch must log outcome=attempted")
    #expect(text.contains { $0.contains("outcome=joined") },
            "the join branch must log outcome=joined")
}

/// The deferral branch is taken ONLY when Low Power Mode is on, records
/// `deferred`, and issues no request.
@Test func aDeferredRefreshEmitsADeferredEventAndIssuesNoRequest() async {
    let power = MutablePowerState(lowPower: true)
    let fetcher = GatedCountingFetcher()
    let (log, sink) = makeLog()
    let store = RateStore(seed: [], fetcher: fetcher, powerState: power, log: log)

    #expect(!(await store.refresh()), "the refresh defers while the mode is on")
    #expect(fetcher.fetchCount == 0, "a deferred refresh must not hit the network")
    #expect(sink.rendered().contains { $0.contains("outcome=deferred") },
            "the deferral must record itself as outcome=deferred")

    // The mode ends: the same refresh runs and records attempted.
    power.isLowPowerModeEnabled = false
    await store.refresh()
    #expect(fetcher.fetchCount == 1)
    #expect(sink.rendered().contains { $0.contains("outcome=attempted") },
            "the same refresh must run - and record attempted - once the mode is off")
}

/// The event carries shape only: outcome and trigger codes, never a rate, an
/// amount or a date (hard rule 12). This is the privacy sweep for the new line.
@Test func theRateRefreshEventCarriesShapeOnly() async {
    let fetcher = GatedCountingFetcher()
    let (log, sink) = makeLog()
    let store = RateStore(seed: [], fetcher: fetcher, log: log)

    await store.refresh()

    let line = sink.rendered().first { $0.contains("event=rates.refresh") }
    guard let line else {
        Issue.record("expected a rates.refresh line")
        return
    }
    #expect(line.contains("outcome=attempted"))
    #expect(line.contains("trigger="))
    #expect(!line.contains("PLN") && !line.contains("EUR"),
            "no currency code may reach the line (hard rule 12)")
}

// MARK: - RV.139b: every branch records itself, the no-fetcher branch included

/// Drives every decision `RateStore.refresh` can take and counts the
/// `rates.refresh` lines. The row's requirement (RV.139-INVESTIGATE §5.1): the
/// nil-fetcher guard must NOT stay silent, or a missing fetcher would read in
/// the log as a Low Power deferral that never drains - indistinguishable from a
/// pass that never reached the refresh. After this, absence of the line means
/// one thing: `refresh()` was never called.
@Test func everyRefreshBranchEmitsExactlyOneRatesRefreshEvent() async {
    let (log, sink) = makeLog()

    // Branch 1 - no fetcher: the store is built without one (a core-test-only
    // shape; the app always supplies a fetcher). Must record `noFetcher`.
    let noFetcherStore = RateStore(seed: [], fetcher: nil, log: log)
    #expect(!(await noFetcherStore.refresh()),
            "a store with no fetcher cannot refresh")

    // Branch 2 - deferred: Low Power Mode postpones the background refresh.
    let power = MutablePowerState(lowPower: true)
    let deferredStore = RateStore(seed: [], fetcher: GatedCountingFetcher(),
                                  powerState: power, log: log)
    #expect(!(await deferredStore.refresh()),
            "a background refresh defers while the mode is on")

    // Branches 3 + 4 - attempted and joined: the creator claims the slot and
    // fetches (`attempted`), a racing second refresh rides it (`joined`,
    // RV.59). One shared store, one in-flight fetch.
    let gate = FetchGate()
    let store = RateStore(seed: [], fetcher: GatedCountingFetcher(gate: gate), log: log)
    let creator = Task { await store.refresh() }
    while await !gate.started { try? await Task.sleep(for: .milliseconds(1)) }
    let joiner = Task { await store.refresh() }
    try? await Task.sleep(for: .milliseconds(20))
    await gate.open()
    #expect(await creator.value, "the creator refresh is not deferred")
    #expect(await joiner.value)

    // One line per decision, every decision covered exactly once - comparing
    // against `allCases` (not a hard-coded list) is what forces a future branch
    // or outcome to be driven here: the test and the outcome vocabulary cannot
    // drift apart, and a new branch cannot slip through without emitting.
    let refreshLines = sink.rendered().filter { $0.contains("event=rates.refresh") }
    #expect(refreshLines.count == RatePackRefresh.Outcome.allCases.count,
            "each refresh decision must emit exactly one line, got \(refreshLines.count): \(refreshLines)")
    let outcomes = Set(refreshLines.compactMap { line -> String? in
        guard let outcome = line.components(separatedBy: "outcome=").dropFirst().first?
            .components(separatedBy: " ").first else { return nil }
        return outcome
    })
    let expected = Set(RatePackRefresh.Outcome.allCases.map(\.rawValue))
    #expect(outcomes == expected,
            "the driven branches must cover every outcome: got \(outcomes.sorted()), expected \(expected.sorted())")
}
