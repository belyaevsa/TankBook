# RV.139-INVESTIGATE - why no `/v1/rates/pack` request ever leaves the device

Read-only investigation. No production code changed. Findings file only.

## 1. Verdict

**None of the four candidates can produce the observed permanent silence on a production
device.** B, C and D are each structurally impossible and are ruled out by a single line. A is
bounded by URLSession timeouts and finite loop bounds, so it can *delay* the rate refresh, never
silence it - and a suspended `@MainActor` pass resumes on foreground while every fresh foreground
spawns a second pass that skips a stuck sync and still reaches `AppRates.refresh()`. The one device
log already in hand (RV.132, build `841`) further proves the pass runs *past* the rate line: the
same session that pushed, pulled and refreshed tokens also POSTed feedback, and
`FeedbackService.outbox.flush()` is `runAutomaticPass` step 6, downstream of `AppRates.refresh()`
step 4. The cause is therefore **not in these four candidates**; the honest next step is the
`rates.refresh` event in a build that carries it (the symptom builds `841`/`857`/`864` do not).

## 2. Per candidate

### A. The pass never reaches the rate line - IMPOSSIBLE as a *permanent* silence

`runAutomaticPass` (`TabRoots.swift:514-541`) awaits, in order: `configService.refresh()`,
`reconcileMonthlySummary()`, `sync.runOpportunisticSync()` (`:528`), **then** `AppRates.refresh()`
(`:532`), then `inbox.drainOutbox()` (`:537`), then `FeedbackService.outbox.flush()` (`:540`). The
question is whether `runOpportunisticSync()` can fail to return and hold the pass before `:532`.

It cannot, for three reasons pinned to lines:

1. **Every request in the cycle has a hard timeout.** `URLSessionTransport.execute` always sets
   `urlRequest.timeoutInterval = request.timeoutInterval ?? configuration.timeoutIntervalForRequest`
   (`URLSessionTransport.swift:40`), and the session is built from `TransportTimeouts` with
   `timeoutIntervalForRequest = readJSON = 30` and `timeoutIntervalForResource = resource = 300`
   (`TransportTimeouts.swift:26,37,42-47`). After RV.97 the push path additionally asks for
   `TransportTimeouts.upload = 120` (`RemoteSyncTransport.swift:53-55`, `TransportTimeouts.swift:32`).
   A stuck request therefore fails at worst at the 300 s resource cap - it never blocks forever.
2. **The cycle's loop bounds are all finite.** Pull paginates on the server's `more` flag
   (`SyncEngine.swift:248-260`); push batches are bounded by both `batchLimit = 200` and
   `maxBatchBytes = 64 * 1024` (`SyncEngine.swift:398-412`); conflict resolution is bounded by
   `maxConflictRetries = 3` (`SyncEngine.swift:520,540`). `synchronize` returns.
3. **Even if it did hang, the next foreground reaches rates anyway.** `runSync` is gated by
   `guard !isSyncing, ... else { return }` (`AppSync.swift:499`). If the previous pass's sync is
   still in flight (its `isSyncing` is true), a *fresh* pass's `runOpportunisticSync()` ->
   `runSync()` returns immediately at that guard, and that fresh pass then proceeds to
   `AppRates.refresh()` (`TabRoots.swift:532`). A suspended `@MainActor` pass is also not dropped:
   the continuation is held by the runtime, so on foreground it resumes exactly where it awaited.

The decisive *observational* refutation: RV.132's own production log (build `841`, 2026-09-07)
records "the device pushes, pulls, refreshes its token **and posts feedback**" in one 20:24-20:30
window with no `/rates/pack` line. Feedback is posted only by `FeedbackService.outbox.flush()`, and
the only call site is `runAutomaticPass` step 6 (`TabRoots.swift:540`, pinned by
`FeedbackForegroundFlushTests.swift:26-28`). Reaching step 6 means the same pass already returned
from step 4 (`AppRates.refresh()`). So the pass *does* reach the rate line.

**Ruled out by:** lines (timeouts, loop bounds, `isSyncing` guard) plus the RV.132 log marker.

### B. Refused before I/O (`hostNotAllowlisted`) and silent - IMPOSSIBLE

`TankbookHTTPClient.send` throws `hostNotAllowlisted` before any I/O (`TankbookHTTPClient.swift:198-199`),
and `RemoteRateFetcher.send` maps any transport error to `.transportUnavailable`
(`RemoteRateFetcher.swift:60-66`), which `fetchAndMerge` swallows with `try?`
(`RateStore.swift:215`). So *if* the base URL were non-allowlisted, the signature would match exactly.

It cannot be. Three lines prove the base URL is always allowlisted and identical to sync's:

- The allowlist is the whole `*.tankbook.live` tree: `allowedDomain = "tankbook.live"`
  (`HostAllowlist.swift:42`), matched over a label boundary, HTTPS required
  (`HostAllowlist.swift:62-69`).
- **Rates and sync resolve the same URL from the same object.** `AppRates.makeFetcher()` passes
  `director: AppConfigStore.shared.director` (`ManualFillUpCurrencySupport.swift:288`); sync does the
  same (`AppSync.swift:14`). `director.baseURL()` reads `store.current.apiBaseURL` at request time
  (`AppConfigService.swift:236-249`), so the two can only ever differ if the resolved config changes
  *between* the sync call and the rate call - and any value it can change to is still allowlisted.
- The config layer guarantees the resolved `apiBaseURL` is allowlisted: a remote document's
  non-allowlisted `apiBaseUrl` candidate is rejected at the key level (`ConfigStore.swift:432`), a
  cached `activeBaseURL` is adopted only if `isAllowlistedBaseURL` (`ConfigStore.swift:191`), and
  `resolve` always falls back to the bundled default (`ConfigStore.swift:591`).

Since `sync.pull`/`sync.push` reach the server in every session, the base URL is reachable *and*
allowlisted; the rate URL built from it (`RemoteRateFetcher.swift:69-71`) passes the same check.

**Ruled out by:** `HostAllowlist.swift:42`, `AppSync.swift:14` + `ManualFillUpCurrencySupport.swift:288`
(same director), `ConfigStore.swift:432/191/591` (base URL always allowlisted).

### C. `refresh()` returns before the fetcher is consulted - IMPOSSIBLE (and the nil path is silent)

`RateStore.refresh` has `guard let fetcher else { return false }` with **no log line**
(`RateStore.swift:160`), and `AppRates.refresh()` interprets `false` as a Low-Power deferral and
registers deferred work (`ManualFillUpCurrencySupport.swift:95-106`). If `fetcher` were ever nil in
the app, the result would be exactly the observed silence, converted into an eternal deferral.

It is never nil. `AppRates.store` is built with `fetcher: makeFetcher()` (`:51`), and `makeFetcher()`
returns a non-optional `RemoteRateFetcher` (`:287-291`). `RateStore.fetcher` is optional only so the
core type can be constructed without one in tests; there is no production path that constructs it
without a fetcher.

Defect (separate, see §5): the nil-fetcher branch emits nothing, so if the invariant ever broke it
would be indistinguishable from candidate A in the log - the `rates.refresh` event should also cover
that branch.

**Ruled out by:** `ManualFillUpCurrencySupport.swift:51,287-291` (store always built with a fetcher).

### D. The transport is the seeded/offline one in release - IMPOSSIBLE

`AppRates.makeTransport()` swaps in `-stubRates` / `-stubRatesEcho` etc. **only under `#if DEBUG`**;
the `#else` branch is unconditional: `return appTransport(URLSessionTransport())`
(`ManualFillUpCurrencySupport.swift:300-321`, specifically `:317-320`). `SeededLaunch` and every stub
transport are themselves `#if DEBUG` (`SeededLaunchTransport.swift:1,168-207`), so in a Release build
the selection state that chooses the offline transport does not exist. `appTransport` is the real
URLSession transport wrapped in the `LoggingHTTPTransport` observability decorator
(`AppSync.swift:605-620`). No state other than a DEBUG launch argument can select the offline one.

**Ruled out by:** `ManualFillUpCurrencySupport.swift:317-320` (`#else return appTransport(URLSessionTransport())`).

## 3. The discriminating observation

The `rates.refresh` event (`RatePackRefresh`, `RatePackRefreshLogEvent.swift:14-37`) ships in the
current tree but **not** in the symptom builds `841`/`857`/`864`. One device log from a build that
carries it, plus the existing `net.request`/`net.response` lines (`LoggingHTTPTransport.swift:56,74`),
separates every surviving case. Read it as follows:

- **`rates.refresh` absent entirely.** `RateStore.refresh` emits on every branch *except* the
  nil-fetcher guard (`RateStore.swift:160`). Absence therefore means either the pass never reached
  `AppRates.refresh()` (candidate A) or the nil-fetcher guard was hit (candidate C). The two are
  indistinguishable by this line alone - which is exactly why the nil-fetcher branch not emitting is
  a defect (§5). But C is ruled out structurally (`:51,287-291`), so **absence ⇒ candidate A**.
- **`outcome: attempted` with no following `net.request endpoint=/v1/rates/pack`.** The fetch claimed
  the slot and ran `fetchAndMerge` -> `RemoteRateFetcher.fetchPack`, but died before
  `transport.execute`. The only silent pre-transport exits are a `components?.url == nil` (a URL the
  brief already verified is correct) and `TankbookHTTPClient`'s `hostNotAllowlisted`
  (`TankbookHTTPClient.swift:198-199`), i.e. **candidate B**. B is ruled out by the allowlist (§2B),
  so this value would point at a URL/allowlist regression, not a current defect.
- **`outcome: attempted` *and* a following `net.request` for `/v1/rates/pack`.** The request reached
  the transport and was dispatched. If the server still logs nothing, the loss is between the
  device's socket and the origin - not client code. (Given `GET /v1/config/` reaches the origin, this
  is the least likely outcome.)
- **`outcome: deferred`.** Low Power Mode deferred rates. But sync defers on the same injected power
  state and the same `.background` trigger (`PowerState.swift:83-84`; both wired to `power.powerState`
  at `AppRootView` init via `AppRates.configure` and `AppSync`), and sync runs in these sessions -
  so `deferred` would contradict observation and indicate a wiring regression where rates got a
  different power state than sync.
- **`outcome: joined` only (never `attempted`).** The single-flight latch the previous run ruled out.
  Structurally impossible now (the slot is cleared by the fetch task's own `defer`,
  `RateStore.swift:191-192`); `joined`-only would indicate a regression in that clear.

The single most valuable line is therefore **whether `rates.refresh` appears at all**, and if it
does, **whether `net.request endpoint=/v1/rates/pack` follows it**.

## 4. The test that would fail today (candidate A, ranked first) - not run

Candidate A is the only one not killed by a single line, so this is the test for it. It is the
source-order gate that would fail the day someone moves `AppRates.refresh()` below a livelock-prone
await, or drops it from the pass. Mirrors the existing `FeedbackForegroundFlushTests` pattern
(`ios/App/Tests/FeedbackForegroundFlushTests.swift`). **Expected to PASS today** - the order in
`TabRoots.swift:514-541` is correct, which is itself the negative result.

```swift
import XCTest

/// RV.139-INVESTIGATE - candidate A gate: the rate refresh must be awaited in
/// runAutomaticPass AFTER the opportunistic sync (so a slow sync can never stop
/// it from being *reached* downstream) and BEFORE the outbox drains (so the
/// RV.132 feedback marker stays a valid proof that the pass ran past the rate
/// line). Not run in this investigation; asserted as a structural invariant the
/// same way FeedbackForegroundFlushTests pins the flush call site.
final class RateRefreshOrderGateTests: XCTestCase {
    func testAutomaticPassAwaitsRateRefreshAfterSync() throws {
        let source = try Self.appSourceFile("Navigation/TabRoots.swift")
        let region = try Self.body(ofFunction: "runAutomaticPass", in: source)
        let syncIndex = try XCTUnwrap(region.range(of: "await sync.runOpportunisticSync()"))
        let ratesIndex = try XCTUnwrap(region.range(of: "await AppRates.refresh()"))
        let outboxIndex = try XCTUnwrap(region.range(of: "await inbox.drainOutbox()"))
        XCTAssertLessThan(syncIndex.lowerBound, ratesIndex.lowerBound,
                          "rates must be reached AFTER sync returns, never before")
        XCTAssertLessThan(ratesIndex.lowerBound, outboxIndex.lowerBound,
                          "the RV.132 feedback marker must stay downstream of rates")
    }

    private static func appSourceFile(_ relativePath: String) throws -> String {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        var candidate = thisFile.deletingLastPathComponent()
        for _ in 0..<3 { candidate = candidate.deletingLastPathComponent() }
        let file = candidate.appendingPathComponent("ios/App/Sources")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func body(ofFunction name: String, in source: String) throws -> String {
        guard let start = source.range(of: "func \(name)") else { throw NSError(domain: "gate", code: 1) }
        guard let bodyStart = source[start.upperBound...].range(of: "{") else { throw NSError(domain: "gate", code: 2) }
        let bodyOpen = source.index(bodyStart.lowerBound, offsetBy: 1)
        guard let close = source[bodyOpen...].range(of: "\n    }\n") else { throw NSError(domain: "gate", code: 3) }
        return String(source[bodyOpen..<close.lowerBound])
    }
}
```

## 5. Defects found on the way that are NOT this one

1. **The nil-fetcher branch of `RateStore.refresh` emits no `rates.refresh` line**
   (`RateStore.swift:160`). `AppRates.refresh()` then converts the silent `false` into an
   "eternal Low-Power deferral" (`ManualFillUpCurrencySupport.swift:101-103`) - a missing fetcher
   would read in the log as a deferral that never drains, and be indistinguishable from candidate A.
   Unreachable today (`:51,287-291` always supply a fetcher), but it is the one branch the new event
   does not cover. The `rates.refresh` event should emit `outcome` for it too (a fourth outcome such
   as `noFetcher`, or move the emit above the guard).
2. **`RemoteRateFetcher` reports `.transportFailure` for a `hostNotAllowlisted` refusal**
   (`RemoteRateFetcher.swift:60-66`). If the allowlist were ever tightened or the base URL ever
   drifted off-allowlist, five such silent misses would also feed the config auto-revert counter via
   `director.report(.transportFailure)` (`ConfigStore.swift:365-377`) - a security refusal would
   masquerade as "the host is down" and could trigger an auto-revert it does not deserve. Distinct
   from this row, but the same silence that hid this bug.
3. **Stale line references in the brief.** `AppRates.refresh()` is at
   `ManualFillUpCurrencySupport.swift:95-106`, `makeTransport()` at `:300-321`, `makeFetcher()` at
   `:287-291` - the brief's `:284-296` / `:298+` point at an earlier revision of the file. Cited
   current numbers throughout this file.

## Report back

Verdict in three sentences: none of the four candidates can explain the permanent silence on a
production device - B, C and D are each ruled out by a single line, and A is bounded by URLSession
timeouts and finite loop bounds so it can only delay rates, while the RV.132 production log (feedback
POSTed in the same session as sync, feedback being `runAutomaticPass` step 6, downstream of rates at
step 4) proves the pass runs past the rate line. The cause is not in these four; the next step is one
device log from a build carrying the `rates.refresh` event, read against the table in §3. Findings
file: `diagnostics/RV.139-INVESTIGATE.md`.

Ruled out with a line: **B** (`HostAllowlist.swift:42` + `AppSync.swift:14`/`ManualFillUpCurrencySupport.swift:288`
same director + `ConfigStore.swift:432/191/591`), **C** (`ManualFillUpCurrencySupport.swift:51,287-291`),
**D** (`ManualFillUpCurrencySupport.swift:317-320` `#else`). Ruled out with reasoning (plus lines):
**A** (timeouts `TransportTimeouts.swift:26/32/37`, finite loops `SyncEngine.swift:248/398/520`,
`isSyncing` guard `AppSync.swift:499`, and the RV.132 feedback marker).

---

## Orchestrator's correction, 2026-09-08: the RV.132 feedback marker does NOT hold

Verified against source after the run. §1, §2A and §4 all lean on "a feedback POST proves
`runAutomaticPass` reached step 6, therefore it returned from step 4 (rates)". **That inference is
unsound.** `FeedbackService.outbox.flush()` is indeed the only *flush* call site
(`TabRoots.swift:540`), but it is not the only thing that POSTs feedback: `FeedbackModel.send()`
calls `outbox.submit(payload)` directly (`FeedbackModel.swift:57,71`), through the **same** memoized
outbox by design (`FeedbackService.swift:11-15`). A user pressing Send in About therefore produces a
feedback POST with the automatic pass never having run at all - which is the likelier reading of
RV.132's log, since that row exists *because* the owner submitted feedback.

**What survives:** candidate A's line-pinned refutation - every request bounded by
`TransportTimeouts` (`URLSessionTransport.swift:40`, `TransportTimeouts.swift:26/32/37/42-47`),
finite loop bounds (`SyncEngine.swift:248/398/520`), and a fresh foreground pass skipping a stuck
sync at `guard !isSyncing` (`AppSync.swift:499`) and still reaching `AppRates.refresh()`.

**What does not:** the observational proof. **Candidate A is ruled out by reasoning alone, not by
observation**, and it remains the strongest of the four. The §4 gate test's second assertion, whose
stated purpose is to keep the feedback marker valid, is asserting an invariant that was never
load-bearing; the first assertion (rates after sync) still is.

The verdict's practical conclusion is unchanged and correct: **get one device log from a build
carrying `rates.refresh` and read it against §3.**
