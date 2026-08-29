# Task PR.7 - client retry policy

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 20.** The app **already tells the user it will retry** and then never does.

## Where you may write

```
ios/Sources/TankbookCore/Sync/SyncCoordinator.swift
ios/Sources/TankbookCore/Sync/Retry/**            (new, if the policy wants its own home)
ios/Sources/TankbookCore/Extraction/Gateway/**    (the ONE /extract retry only)
ios/App/Sources/Settings/AppSync.swift
ios/Tests/TankbookCoreTests/**
docs/SYNC.md · docs/API.md · docs/ERRORS.md
```

**Do not** touch `Capture/**`, `ConfirmManual/**`, the extraction parsers, `Config/**`,
`Transport/**` (PR.6's timeouts are closed), `Persistence/**` (PR.4 just landed there), `Auth/**`,
`backend/`, `site/`, `Spike/`, `design/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## The defect, verified immediately before dispatch

`Retry-After` is decoded and **displayed** - `SyncServerNotice.swift:29,42-43,61` renders
"Retrying in N minutes" from `retryAfterSeconds` - and **nothing schedules the retry**. There is no
backoff anywhere in `SyncCoordinator`. So the notice makes a promise the app does not keep, which
is hard rule 7 inverted: the next step is named and then not taken.

`docs/API.md:316` also specifies **one** silent retry for `/extract`, and it is not implemented.

## What to build

1. **Jittered exponential backoff, capped ~5 min**, in `SyncCoordinator`, for the **unavailable
   class only** - offline and 5xx. Honour `Retry-After` when the server sent one: the server's
   number wins over your curve.
2. **Retry only idempotent calls.** Push is idempotent by id + `baseScn` (`docs/SYNC.md`), so it
   qualifies; anything that is not must not be retried without a key (`Idempotency-Key` is PR.25,
   deferred).
3. **The one silent `/extract` retry** from `API.md:316`, then surface.
4. **Never retry the refusal classes.** A 401 is `authExpired` and PR.1's refresher owns it; 402,
   410, 426 and 429-with-quota are refusals, not transient faults. Retrying them is a loop that
   burns battery and never succeeds.

**Jitter is not decoration.** Synchronised retries from a fleet after an outage are a self-inflicted
second outage (`docs/PRACTICES.md` U7). The jitter must be **bounded and testable** - a test that
cannot pin the schedule is not a test of a backoff.

## Explicitly out of scope

Transport timeouts (**PR.6**, closed) · `Idempotency-Key` (**PR.25**) · trace headers (**PR.8**) ·
debounced sync after writes (**PR.20**) · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 984 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

**Drive every schedule assertion with a FAKE CLOCK, never a real sleep.** This repo spent a day
fixing four wall-clock races in `GatewayBudgetTests` where a real-time assertion raced the scheduler
under load; the corpus suites peg every core for ~29 s. Do not add a fifth.

- **L1**: a 429 carrying `Retry-After: 120` schedules **one** cycle at +120 s, **none earlier**, and
  the jitter stays inside its stated bound.
- **L1**: a 5xx sequence backs off 1-2-4-8, capped.
- **L1**: `/extract` retries **once**, then surfaces.
- **L1**: 401, 402, 410 and 426 are **never** retried.

Name any UI suite you touch and **report its observed count**; a selector matching nothing prints
"0 tests ... passed" and exits 0 - that caught the orchestrator three times this session, so read
the count. **Never `pgrep -f`** for a build; use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. Ignore `Retry-After` and use your own curve. The +120 s test must fail.
2. Remove the cap. The backoff test must fail.
3. Remove the jitter entirely. A test must fail - if none does, the jitter is unasserted and the
   fleet-synchronisation risk is unguarded.
4. Retry a 426. That test must fail.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc** for scripted edits.

## Screenshots

None expected. If the Settings notice copy changes at all, capture EN **and** RU.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results **with the
suites you ran**; the curve, cap and jitter bound you chose and **why each**; the files changed; and
anything in this brief that is wrong - ten agent pushbacks here have been correct.

En-dashes only, never em-dashes.
