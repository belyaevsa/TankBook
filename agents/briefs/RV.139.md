# RV.139 - the client never asks for exchange rates

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The symptom, from production

Product owner, 2026-09-08: *"there are no requests to get exchange rates from the client."*
Across builds `1.0.0+841`, `+857` and `+864` the server logs `auth.refresh`, `sync.pull`,
`sync.push` and once `GET /v1/config/` - and **not one `/v1/rates/pack`**. That config line proves
public unauthenticated GETs do reach these logs, so a request that happened would appear.

## What is already ruled out - do not spend the run re-checking these

- **The wiring is correct.** `AppRates.store` is built with a real `RemoteRateFetcher`
  (`ManualFillUpCurrencySupport.swift:51`, `:286-289`).
- **The URL is correct.** `endpoint()` builds `baseURL/v1/rates/pack` on the **same host** as sync
  (`RemoteRateFetcher.swift:69-71`). This is **not** [RV.68]'s missing-`/v1` shape.
- **It is called.** `TabRoots.swift:532` awaits `AppRates.refresh()` inside `runAutomaticPass`.
- **Low Power Mode is NOT the cause**, and the logs are what rule it out. `RateStore.refresh`
  returns early with no HTTP when `LowPowerPolicy.defers(work:.ratePackRefresh, trigger:.background,
  lowPowerMode:)` is true - but `PowerState.swift:83-84` defers `.syncCycle` on **exactly the same
  condition**, and sync runs in every one of these sessions. If the mode were on, sync would be
  silent too.

## My hypothesis, pinned to lines - VERIFY it before building on it

`RateStore.swift:161-177`:

```swift
if let existing = lock.withLock({ $0.inFlightRefresh }) {
    await existing.value
    return true                     // joins - and issues NO request
}
let task = Task { await self.fetchAndMerge(fetcher: fetcher) }
lock.withLock { $0.inFlightRefresh = task }
await task.value
lock.withLock { $0.inFlightRefresh = nil }   // <-- only if the creator REACHES this line
return true
```

**The clear is not on a `defer`.** If the caller that created the task is cancelled or abandoned
before reaching that final line - `runAutomaticPass` runs inside a SwiftUI `.task`, which is
cancelled when the view goes away, and the `.onChange(of: scenePhase)` handler spawns its own
`Task` - then `inFlightRefresh` stays set **forever**. Every later `refresh()` takes the join
branch, awaits an already-finished task, and returns `true` **without issuing a request**.

That matches the symptom exactly: permanent silence, no error, and a return value that looks
healthy. The comment above the clear even asserts the invariant that fails - *"a newer refresh
cannot be created while `inFlightRefresh` is still set"* - which is the latch, not a guarantee.

**Four of the orchestrator's diagnoses have been wrong and every one was caught by an agent that
checked.** Reproduce the latch in a test before you change anything, and report what you found even
if it contradicts the above.

## What to build

- Make the in-flight slot **impossible to leave set**, whatever the caller does. The obvious shapes
  are clearing inside the `Task` itself, or a `defer` around the await - **choose one, say why, and
  make sure the choice still satisfies [RV.59]'s original point**: two racing triggers must open one
  `/rates/pack` request, not two.
- Keep the deferral and the single-flight semantics otherwise unchanged.
- **Add the shape-only observability this cost three builds to notice.** `docs/LOGGING.md` permits
  shape: a line recording that a pack fetch was **attempted, deferred, or joined an in-flight task**
  would have answered this in one session. Field names, counts and outcomes only - never a rate, an
  amount or a currency pair beyond its code (hard rule 12). Put it where the branch is taken, and
  add the row to `docs/LOGGING.md` in the same change.

## Explicitly out of scope

- [RV.135]'s historical EUR feed (already shipped) and the backend generally.
- [RV.136] (the vehicle push loop), though you will see it in the same logs.
- Changing `packWindowDays`, the deferral policy, or the automatic pass's ordering.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Reference data -> Exchange rates.
2. `docs/SYNC.md` -> the Low Power Mode table.
3. `docs/LOGGING.md` (**the authority for what you may log**), and `CLAUDE.md` hard rule 12.
4. `CLAUDE.md` hard rule 1 - a miss is a non-event; this must not become an error surface.

## Checks

Baseline: `main` is green at **1651 tests / 184 suites**, **777** localization keys, `swift build` 0,
`swiftlint` 0 errors **from the repo ROOT**. **Re-measure yourself** and report what you observe.

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0.
3. `cd ios && swift test` - full, never subsetted; report the number.
4. `xcodegen generate` + any UI suite you touch **by name**; report a **non-zero** count - a filter
   matching nothing prints "0 tests ... passed" and still exits 0.
5. Localization gate - 0, report the key count.
6. Release build - required only if you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L1, the row's whole point**: a **second** `refresh()` after the first has completed issues a
  **second** request. Assert the stub transport's **request count**, not the return value -
  `refresh()` returns `true` on the join path, so a test that checks the return passes today.
- **L1**: reproduce the latch against the CURRENT code first and show it fails, then show your fix
  makes it pass. Report both outcomes; a fix whose test passes before the change proves nothing.
- **L1**: [RV.59]'s guarantee still holds - two concurrent triggers issue exactly **one** request.
- **L1**: the deferral path is taken only when Low Power Mode is actually on, and issues no request.

### Vacuous traps, named

- Asserting `refresh()` returned `true` - it does on the join path, which is the bug.
- Testing with a **fresh** store, where the latch cannot have formed.
- Removing the single-flight entirely to make requests happen - that reintroduces [RV.59].
- Logging a rate, an amount, or anything beyond shape.
- Concluding "Low Power Mode" without checking that sync deferred too.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Whether the latch reproduced, with the failing-then-passing test output; every check with the
**exit code you observed**; whether each test was **run or only written**; and which clearing shape
you chose and why. If my hypothesis is wrong, say so and report what you actually found rather than
making the code match my guess.
