# Task PJ.8 - a rate that arrives must actually fill the blanks

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 14.** F9 promises "the rate arrives later, the conversion fills in". P5.2 is ticked
and **the only caller of the backfill is a DEBUG screenshot hook**, so a rate-pending entry stays
pending forever unless the user types a manual rate.

## Where you may write

```
ios/App/Sources/ConfirmManual/ManualFillUpCurrencySupport.swift   (AppRates)
ios/App/Sources/Home/**                                          (foreground trigger + the hook)
ios/App/Sources/Navigation/**
ios/Sources/TankbookCore/Rates/**
ios/Tests/TankbookCoreTests/**
ios/App/UITests/HomeUITests.swift
docs/SYNC.md · docs/SCHEMA.md
```

**Do not** touch `Capture/**`, `Import/**`, `Settings/**`, `SignIn/**`, `Welcome/**`,
`Reminders/**`, `ServiceEntry/**`, `TankbookCore/Sync/**`, `Config/**`, `Transport/**`, `backend/`,
`site/`, `Spike/`, `project.yml`. **Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch

`MoneyBackfillService` has exactly **one** caller in the whole app:

```
ios/App/Sources/Home/RateBackfillDebugHook.swift:26   -runRateBackfill (DEBUG screenshots)
```

`AppRates.refresh()` fetches and merges rates and **never runs the backfill**. So an entry saved in
a foreign currency with no rate for its date is converted only if the user opens it and types a rate
by hand.

## What to build

Run `MoneyBackfillService` **after every successful `AppRates.refresh()`** and **on foreground**.
Keep `-runRateBackfill` working - it is the screenshot hook.

**Three invariants this must not break. They are hard rules, not preferences:**

1. **Fill-blanks-only** (hard rule 3). The backfill may only populate a **missing** home amount. It
   must never overwrite an existing snapshot, and never touch one whose source is a **manual** rate
   the user typed - once a user sets a value it is theirs permanently (hard rule 13). A relaxed
   guard here is exactly the P5.2a mutation that **left all 661 tests green**, so assume the guard
   is easy to weaken without anything noticing.
2. **`rateDate` is the entry's date, never today** (hard rule 3). A backfill running in September
   must convert an August entry at August's rate.
3. **Silence** (S8, `docs/SYNC.md:330`). The backfill bumps the revision so the UI re-reads, and
   posts **no toast, no banner, no badge**. P5.2b's mutation - making the backfill post a toast -
   fails the S8 silence test, and it must keep failing.

## Explicitly out of scope

The rates transport (P5.1, shipped) · manual-rate entry (P5.2b, shipped) · sync (S8's cross-device
half is built) · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1016 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: a pending entry plus a stub fetcher is **filled after `refresh()`**, with **no launch
  flag**.
- **L1**: an entry whose snapshot came from a **manual** rate is left alone.
- **L1**: the filled amount uses the **entry's date**, not today's - seed two different rates and
  assert the value, not merely that it is non-nil.
- **L1**: the backfill posts nothing (S8).
- **L4 `HomeUITests`**: pending -> filled through a stub rate transport, **without**
  `-runRateBackfill`.

Run only `-only-testing:TankbookUITests/HomeUITests` and **report the observed count** (19 at last
measurement). **A selector matching nothing prints "0 tests ... passed" and exits 0.**
**Never `pgrep -f`** for a build; use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. **Relax the fill-blanks guard** so it also overwrites a manual snapshot. A test must fail. This
   is the load-bearing one: the equivalent relaxation in P5.2a left **all 661 tests green**, so if
   nothing fails here, the guard is unpinned and that is the finding.
2. Use **today's** rate instead of the entry's `rateDate`. A test must fail.
3. Make the backfill post a toast. The S8 silence test must fail.
4. Remove the `refresh()` trigger, leaving only the DEBUG hook. The L4 test must fail.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, anchor on the **code line** rather than a phrase that also appears in a
comment, and confirm `BUILD: 0` before believing any result - three mutations misapplied that way
today.

## Screenshots

EN **and** RU, dark: a Home entry that was rate-pending and is now converted. Name them
`PJ.8-backfilled{,-ru}.png`, register them in `scripts/capture-screenshots.sh`, capture **outside**
a test run, and **check the converted amount is actually in frame** - four captures of this exact
feature were deleted in P5.2b because the conversion card sat below the fold (P6.9).

## Report back

Every command with its **real exit code** and observed counts; all four mutation results **with the
suites you ran**; how you guaranteed fill-blanks-only and date correctness; the files changed; and
anything in this brief that is wrong - eleven agent pushbacks here have been correct.

En-dashes only, never em-dashes.
