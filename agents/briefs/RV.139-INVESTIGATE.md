# RV.139-INVESTIGATE - why no `/v1/rates/pack` request ever leaves the device

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**

## This is a READ-ONLY investigation. Do not change production code.

Your single deliverable is `diagnostics/RV.139-INVESTIGATE.md`. You may write **only** that file
and, if you need them, throwaway test files under `/private/tmp`. **Do not** edit anything under
`ios/App/Sources`, `ios/Sources`, `docs/`, or `HANDOVER.md`. **Do not commit.**
**Never move, rename or delete a file you did not create** - another session may be writing in this
checkout. If you find something in the way, report it and carry on.

**Do not run `swift test`, `xcodebuild`, or the UI suites.** Another agent is building in this same
checkout and the machine is memory-constrained. `swift build` once, if you genuinely need type
information, is the most you may spend. You are reading code and reasoning about it, not proving a
fix. If you want to *demonstrate* a hypothesis, write the test into your findings file as a code
block and say "not run".

## The symptom, and what the previous run already settled

Product owner, 2026-09-08: *"there are no requests to get exchange rates from the client."*
Across builds `1.0.0+841`, `+857` and `+864` the server logs `auth.refresh`, `sync.pull`,
`sync.push` and once `GET /v1/config/` - and **not one `/v1/rates/pack`**. The `GET /v1/config/ ->
499` line proves public unauthenticated GETs reach these logs, so a request that happened would
appear.

**Ruled out by the previous RV.139 run - do not re-derive these:**

- **The single-flight latch does not exist.** `await task.value` on a `Task<Void, Never>` never
  throws and always resumes; a cancelled creator still reaches the clear. It was probed directly
  (`cleared=true`) and nothing reproduced. The slot is now owned by the fetch task's own `defer`
  (`RateStore.swift:169-205`) and is structurally unable to latch.
- **Low Power Mode is not the cause.** `PowerState.swift:83-84` defers `.syncCycle` on exactly the
  same condition, and sync runs in every one of these sessions.
- **The URL shape is correct.** `RemoteRateFetcher.endpoint()` (`:69-71`) builds
  `director.baseURL()/v1/rates/pack`. This is **not** [RV.68]'s missing-`/v1` shape.
- **The wiring is correct.** `AppRates.store` is built with a real `RemoteRateFetcher`
  (`ManualFillUpCurrencySupport.swift:47-57`, `:288-292`), and `TabRoots.swift:532` awaits
  `AppRates.refresh()`.

So the call is made, the URL is right, and nothing latches. **Something between `refresh()` being
called and a socket opening is swallowing it, or the call is never reached.**

## The four candidates, pinned to lines. Rank them by EVIDENCE, not plausibility.

Every one of these produces exactly the observed signature - permanent silence, no error, no
server-side trace - so you cannot choose between them by symptom. Read the code and say which are
possible on a production device and which are structurally impossible, with the line that proves it.

**A. The pass never reaches the rate line because an earlier `await` does not return.**
`TabRoots.runAutomaticPass()` (`:514-541`) awaits **in this order**: `configService.refresh()`,
`notificationCoordinator.reconcileMonthlySummary()`, `sync.runOpportunisticSync()`, **then**
`AppRates.refresh()`, then `inbox.drainOutbox()`, then `FeedbackService.outbox.flush()`.
The logs show `sync.push` running and (before [RV.97]) hanging for 30 s at a time on this owner's
post-import data. **`AppRates.refresh()` is downstream of the exact call that [RV.97] proved could
livelock.** Determine: can `runOpportunisticSync()` fail to return, or return only after the process
is backgrounded and the pass suspended? Is there any timeout or cancellation that bounds it? Does a
suspended `@MainActor` pass resume on the next foreground, or is it dropped?

**B. The request is refused before any I/O and the refusal is silent.**
`TankbookHTTPClient` throws `hostNotAllowlisted` **before any I/O and before the token provider is
consulted**. `RemoteRateFetcher.send` maps that to `.transportUnavailable`, and
`RateStore.fetchAndMerge` (`:212-217`) swallows it with `try?`. A device whose
`director.baseURL()` returns a host the allowlist rejects - or a host that differs from the one sync
uses - would produce **exactly** this: sync works, rates are silent, and the server sees nothing.
Establish whether `AppConfigStore.shared.director.baseURL()` can differ from the base URL sync uses,
including any remote-config `apiBaseUrl` override and its auto-revert (`docs/CONFIG.md`), and what
the allowlist actually contains at runtime.

**C. `refresh()` returns before the fetcher is consulted.**
`RateStore.refresh` (`:159-168`) has two early returns: `guard let fetcher else { return false }`,
which emits **no log line at all**, and the Low Power deferral, which does.
`AppRates.refresh()` (`:284-296`) then interprets `false` as a deferral and registers deferred work -
its comment asserts *"the store always has a fetcher here"*. If that assertion can be false in any
production configuration, the app converts a missing fetcher into an eternal Low-Power deferral that
never drains. Say whether it can, and whether the nil-fetcher path is observable at all today (it is
not - that is itself a finding).

**D. The transport is the seeded/offline one in a production build.**
`AppRates.makeTransport()` (`:298+`) swaps in stubs for `-stubRates` / `-stubRatesEcho` and
"otherwise the transport is the app-wide seeded/real one (offline under a seeded launch, P6.21)".
Establish, by reading the code, that a **Release, non-seeded, no-launch-argument** process gets the
real transport - and whether any state other than a launch argument can select the offline one.

## What the deliverable must contain

`diagnostics/RV.139-INVESTIGATE.md`, structured as:

1. **Verdict**: which candidate is the cause, or "none of these - here is the fifth", or "cannot be
   decided from source, and here is the one log line that would decide it". **A negative result,
   reported honestly, is a successful run.** The previous run's value was exactly that.
2. **Per candidate**: possible / impossible, with the file and line that proves it. No candidate may
   be dismissed by reasoning alone where a line settles it.
3. **The discriminating observation**: if the cause cannot be pinned from source, name the single
   log line, breakpoint or field that separates the surviving candidates, and where it goes. The
   `rates.refresh` event (`outcome: attempted|joined|deferred`) already ships - say precisely what
   its presence, absence, or each value would prove, including what its **absence** means for
   candidate A versus candidate C.
4. **The test that would fail today**, written out as code but marked "not run", for whichever
   candidate you rank first.
5. **Anything you found on the way that is a defect but not this one**, listed separately. The
   nil-fetcher path emitting nothing is a live example.

## Docs to read (in order)

1. `docs/CONFIG.md` -> `apiBaseUrl` guardrails and auto-revert.
2. `docs/SECURITY.md` -> transport and the host allowlist.
3. `docs/LOGGING.md` - the authority on what may be logged; `CLAUDE.md` hard rule 12.
4. `docs/SYNC.md` -> the Low Power Mode table.

## This brief's diagnosis is a hypothesis, not a fact

The orchestrator has been wrong on this row once already (the latch), and wrong four times in the
last session; an agent caught every one. If all four candidates are impossible, **say so** - do not
pick the least impossible one to have an answer.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Your verdict in three sentences, the path of the findings file, and - explicitly - **which
candidates you ruled out with a line and which with reasoning**.
