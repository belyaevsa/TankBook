# RV.139b - make the next production log decisive, and settle candidate A without a device

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## Read this first

`diagnostics/RV.139-INVESTIGATE.md` is the read-only investigation that precedes this task,
**including the orchestrator's correction at the bottom** - read that correction, it invalidates one
of the findings' own arguments. Do not re-derive what is settled there.

## The symptom, and what is already settled

Product owner, 2026-09-08: *"there are no requests to get exchange rates from the client."* Across
builds `1.0.0+841`, `+857` and `+864` the server logs `auth.refresh`, `sync.pull`, `sync.push` and
once `GET /v1/config/` - and **not one `/v1/rates/pack`**. That config line proves public
unauthenticated GETs reach these logs.

Four candidates were investigated. **Three are dead on a line each** and you must not spend the run
on them:

- **B, allowlist refusal**: rates and sync resolve from the same `AppConfigStore.shared.director`
  (`AppSync.swift:14`, `ManualFillUpCurrencySupport.swift:288`), and `ConfigStore.swift:432/191/591`
  guarantee the resolved base URL is always allowlisted.
- **C, nil fetcher**: `makeFetcher()` returns a non-optional (`ManualFillUpCurrencySupport.swift:287-291`).
- **D, offline transport in Release**: the stub selection is entirely `#if DEBUG`; the `#else` is an
  unconditional `appTransport(URLSessionTransport())` (`:317-320`).

**Candidate A - the automatic pass never reaches the rate line - is the survivor**, and it is ruled
out only by *reasoning* (timeouts bound every request; loop bounds are finite; a fresh foreground
pass skips a stuck sync at `guard !isSyncing`, `AppSync.swift:499`). The investigation also offered
an *observational* refutation - that a feedback POST proves the pass reached step 6 - and **that
argument is wrong**: `FeedbackModel.send()` calls `outbox.submit()` directly
(`FeedbackModel.swift:57,71`) through the same memoized outbox, so a user pressing Send in About
POSTs feedback with the pass never having run.

## This task is NOT "find the bug by guessing". It has two concrete jobs.

**The honest state is: the question needs one device log, and no build has ever carried the event
that would answer it** - `rates.refresh` ships in the current tree but not in `841`/`857`/`864`. So
job one is to make sure the *next* build's log is decisive whichever way it falls, and job two is to
settle candidate A in a test rather than waiting for a device.

### Job 1 - close the two gaps that would leave the next log ambiguous

**1a. `rates.refresh` is not emitted on every branch.** `RateStore.refresh` (`RateStore.swift:159-207`)
emits for `deferred`, `joined` and `attempted`, but the **nil-fetcher guard at `:160` emits nothing**
and returns `false`. `AppRates.refresh()` then reads that `false` as a Low-Power deferral and
registers deferred work (`ManualFillUpCurrencySupport.swift:95-106`), so a missing fetcher would read
in the log as *a deferral that never drains*. It is unreachable today, which is exactly why it is
cheap to close - and while it is open, **"`rates.refresh` absent" means "A or C" and cannot separate
them**. Give that branch an outcome (a fourth case, or move the emit above the guard - choose and
say why). After this change, absence of the line must mean **one** thing: `refresh()` was never
called.

**1b. An allowlist refusal is reported as a transport failure - and that is a live defect on its
own.** `RemoteRateFetcher.send` (`:60-66`) maps every non-HTTP error, including
`TankbookHTTPClientError.hostNotAllowlisted`, to `director.report(.transportFailure)`. That counter
feeds the config auto-revert (`ConfigStore.swift:365-377`), so a **security refusal masquerades as
"the host is down" and can trigger an auto-revert it does not deserve**. Separate the two: a refusal
is not evidence the host is unreachable. Check whether the other `TankbookHTTPClient` owners have the
same mapping and report what you find; fix it here only for the rate fetcher unless the change is
genuinely the same line.

**1c. Make the pass itself observable, so absence of `rates.refresh` names its own branch.**
`TabRoots.runAutomaticPass()` (`:514-541`) awaits six steps in order. Today nothing records that it
started, which step it is on, or that it finished - so if it stalls at step 3 the log looks identical
to "it never ran". Emit **shape only** (`docs/LOGGING.md`, hard rule 12: step names, counts,
durations and outcomes are loggable; amounts, currencies, stations and payloads are not) so one
session's log says which step the pass reached. Keep it cheap and quiet - this runs on every
foreground. Add the event to `docs/LOGGING.md` in the same change.

### Job 2 - settle candidate A with a test, not a device

Write the tests that would fail if the pass could fail to reach `AppRates.refresh()`:

- A slow or hanging sync step does not prevent a **later** foreground pass from reaching the rate
  refresh (`guard !isSyncing`, `AppSync.swift:499`, is what should make this true).
- The pass is reached in the shapes production actually takes: a scene already `.active` when the
  view attaches (the `.task` fallback, `TabRoots.swift:333-336`) **and** an `.active` transition
  after a resign - `didRunAutomaticPass` gates the first, and the row has always asked whether a warm
  foreground reaches the pass at all.

If a test shows the pass genuinely cannot be reached in one of those shapes, **that is the bug and
the run has found it** - fix it and say so. If they all pass, report that plainly: it means candidate
A survives on reasoning only and the device log is still required. **A negative reported honestly is
a successful run.**

## Explicitly out of scope

- Changing the single-flight, the deferral policy, `packWindowDays`, or the pass's ordering.
- [RV.135]'s historical feed and the backend generally.
- [RV.136] (the vehicle push loop), though it is in the same logs and has its own brief.
- **Inventing a fix for a cause you have not demonstrated.** Three candidates are dead; do not
  "harden" them.

## Docs to read before writing (in order)

1. `diagnostics/RV.139-INVESTIGATE.md`, including the orchestrator's correction.
2. `docs/LOGGING.md` - **the authority for what you may log** - and `CLAUDE.md` hard rule 12.
3. `docs/CONFIG.md` -> `apiBaseUrl` guardrails and auto-revert (for 1b).
4. `docs/SYNC.md` -> the Low Power Mode table; `CLAUDE.md` hard rule 1 - a rate miss is a non-event
   and must never become an error surface.

## Checks

Baseline on `main` as left: **1675 tests / 187 suites**, **777** localization keys at 100% RU,
`swift build` 0, `swiftlint lint` 0 errors **from the repo ROOT**. **Re-measure yourself and report
what you observe** - do not copy these numbers into your report.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then any UI suite you touch **by name**, with its **observed count** - check
   it is non-zero; a filter matching nothing prints "0 tests ... passed" and still exits 0. Several
   RV suites here are `extension HomeUITests`, so a class-name filter for them matches nothing.
5. Localization gate - exit 0; report the key count. No new user-facing strings are expected: a log
   line is not user-facing.
6. **Release build required if you touch a `#if DEBUG` seam** - say which applies and run it if so.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

### Tests you must add

- **L1**: every branch of `RateStore.refresh` emits exactly one `rates.refresh`, the nil-fetcher
  branch included. Assert the emitted **outcome**, and assert the branch count is total - a new
  branch added later must not be able to slip through silently.
- **L1**: a `hostNotAllowlisted` refusal does **not** increment the transport-failure counter that
  feeds auto-revert, and a genuine transport error still does.
- **L1**: the automatic pass records the step it reached, and a step that throws or hangs does not
  erase the record of the steps before it.
- **L1/L3, job 2**: the two reachability tests above.
- **L1**: nothing added logs a rate, an amount, a currency pair beyond its code, or a URL with a
  query string (hard rule 12).

### Vacuous traps, named

- Asserting `refresh()` returned `true` - it does on the join path.
- Asserting a log line "was emitted" without asserting **which outcome**, which is the whole point of
  the event.
- Testing with a fresh store, where the interesting states cannot have formed.
- "Fixing" B, C or D, which are dead - a diff there is a diff against a line that already proves the
  case impossible.
- Logging anything beyond shape, or making a rate miss visible to the user as an error (hard rule 1).
- Adding a log line on a hot path without bounding how often it fires.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; whether either reachability test **failed** (that would be the bug, and is the
best outcome this run can have); what you chose for the nil-fetcher branch and why; what you found
about the allowlist/transport mapping in the other `TankbookHTTPClient` owners; and - in one
sentence - **what the next production log will now be able to prove that today's cannot**.
