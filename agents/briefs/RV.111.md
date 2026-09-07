# RV.111 - a row older than the rolling rate window is never re-asked

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The defect, pinned to four lines

An imported entry is written **rate-pending on purpose** - hard rule 3 says `rateDate` is the
ENTRY date, and a 2015 rate is not on the device at import time. Two things resolve such a row, and
**neither can reach a date older than 400 days**:

1. **The launch pass.** `TabRoots.swift:513` `runAutomaticPass()` -> `AppRates.refresh()` refreshes
   the **rolling pack only**: `RateStore.swift:185` asks `from = now - (packWindowDays - 1)` with
   `packWindowDays = 400` (`:142`). A 2015 date is not in it and never will be.
2. **The import drain.** `ManualFillUpCurrencySupport.swift:123` `drainAfterImport` does the right
   thing - `fetchSpan` over the span the imported rows actually cover (`:135`) - but it runs
   **exactly once**, scheduled off the commit (`:105`).

And the affordance that looks like the escape is not one. `HomeView.swift:264-270`,
`"Check for rates"`, runs `AppRates.refresh()` - **the rolling pack again**. RV.106 made the state
honest (the divider says why, the footnote counts the rows) but the button cannot fill a row whose
date the pack does not cover. **So a multi-year import committed while the server's rate archive is
still publishing leaves its oldest rows pending permanently**, and the only escape is a manual rate.

This is the case the product owner's own import did **not** hit: June to September is ~100 days,
inside the window, which is exactly why RV.106 saw pending rows resolve and concluded the mechanism
worked.

## Design questions ALREADY CLOSED - do not reopen

The row leaves the design open. I am closing it. Implement as written; if you think one of these is
wrong, say so and **stop there** rather than quietly choosing differently.

1. **"Check for rates" becomes demand-driven.** It asks for the spans the **pending rows actually
   cover**, not the rolling pack. This is the row's first honest option and it is the one that needs
   no new persisted state.
2. **The automatic launch pass is UNCHANGED.** `runAutomaticPass` keeps refreshing the rolling pack
   and nothing else. **This is the bound**, and it is the point: an unbounded re-demand of a decade
   of dates on every launch is its own defect, and the row says so. The expensive ask happens only
   when the user asks for it.
3. **The second bound is `fetchSpan`'s existing chunking.** It already splits a wide span under the
   server's 400-day cap (`RateStoreTests.swift:356` `fetchSpanChunksAWideSpanUnderTheServerCap`
   proves it). Do **not** write a second chunker. A decade is ~10 requests, and that number is what
   the L2 check asserts.
4. **A genuinely unavailable date is a dead end that names its next step** (hard rule 7). After a
   demand pass has covered a row's date and the row is *still* pending, the provider has no answer -
   the ECB archive legitimately does not serve some dates. The surface must then name the **manual
   rate** as the way out. It must NOT keep implying another check will help.
5. **Never convert at today's rate.** Hard rule 3, and it is [RV.88]'s defect. A pending row stays
   pending and stays **counted**; it is never zeroed and never silently valued.

## What already exists - build on it, do not duplicate

- `RateStore.fetchSpan(from:to:base:trigger:)` - demand fetch, already chunked.
- `MoneyBackfillService.backfill(_ repository:)` (`:42-55`) - walks every live vehicle's live
  entries, returns `Result(filledCount:stillPendingCount:)`. This walk is also how you enumerate
  the pending rows' dates; do not write a third traversal.
- `MoneyBackfillService.backfill(_:entries:)` (`:69`) - the scoped variant the import drain uses.
- `ManualFillUpCurrencySupport.drainAfterImport` (`:123`) - **the shape to mirror**: collect dates,
  `fetchSpan` over min...max, `persist`, then backfill.

## What to build

### A. A demand drain over the rows that are actually pending

Add to `ManualFillUpCurrencySupport` a sibling of `drainAfterImport`, e.g.
`drainPendingRows() async -> MoneyBackfillService.Result?`, which:

- reads the repository for every live entry whose money `isRatePending`;
- returns early when there are none (no request at all - an empty ask is a bug, not a no-op);
- computes `min`/`max` of their `rateDate`s and calls `store.fetchSpan(from:to:base:.eur,
  trigger:.userInitiated)`;
- `persist(store.allRates())`, then runs the backfill and bumps the revision through
  `onBackfilled` exactly as the existing paths do.

**Offline is a non-event** (hard rule 1): a failed fetch must not throw, and the backfill still
fills whatever the cache already holds. `fetchSpanFailureIsSilent` (`RateStoreTests.swift:411`) is
the existing precedent.

### B. Wire it to the affordance, and only to it

`HomeView.swift:264-270` calls `drainPendingRows()` instead of `AppRates.refresh()`. Update the
comment there - it currently claims the button runs "the refresh + S8 backfill the next launch would
run", which will no longer be true, and `CLAUDE.md` -> "Code comments: current truth only" requires
the stale claim to go in the same change.

### C. The dead end names the manual rate

When a demand pass ran, covered the pending rows' dates, and rows are **still** pending, the footnote
must stop promising another check and name the manual rate instead. Decide the smallest honest
surface for this and say what you chose. Constraints:

- **One full localised phrase per language**, EN + RU in `Localizable.xcstrings`, never
  concatenation. The scar: `"%@ spend"` composed in RU as `"%@ расходы"` rendered "АВГУСТ РАСХОДЫ".
- The count keeps its **RU plural variations** (три formы: строка/строки/строк) - the existing
  `entries pending rates` key at `L10n.swift:146-154` already does this; match it.
- It is a **footnote**, not an error, not a dialog, and it never blocks (`docs/ERRORS.md` severity
  vocabulary).

## Explicitly out of scope

- **[RV.112]** - the vitals tile and Trends treating a rate-pending row as zero. Different row, and
  do not "fix" it in passing.
- Changing `packWindowDays`, the automatic launch pass, or `fetchSpan`'s chunk size.
- Persisting an unresolved-span record (the row's second option - decision 1 chose the first).
- Anything about the import wizard or the commit path.

## Docs to read before writing (in order)

1. `CLAUDE.md` - hard rules 1, 3, 7, 10, 12, 13.
2. `docs/SCHEMA.md` -> Money (**the authority**: `rateDate` = entry date, snapshots immutable,
   backfill is fill-blanks-only).
3. `docs/SYNC.md` -> S8.
4. `docs/ERRORS.md` -> the Home surface and the severity vocabulary.

## Checks

Baseline on the tree you are handed: **iOS 1625 tests / 181 suites**, `swift build` 0, `swiftlint`
0 errors **from the repo ROOT**, localization gate 0 (770 keys, 100% RU).

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. Root-relative `excluded:` paths; running it
   from `ios/` gives a wrong answer.
3. `cd ios && swift test` - full suite, **never subsetted**, **>= 1625**, report the number.
4. `xcodegen generate`, then the UI suites you touched **by name** (`-only-testing:`). Report the
   observed count and **check it is non-zero** - a filter matching nothing prints "0 tests ...
   passed".
5. Localization gate - 0, 100% RU, report the key count.
6. Release build - required only if you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L1 - the row's whole point**: a pending row whose `rateDate` is **outside** the 400-day window
  is included in what the retry asks for, and **fills when the answer arrives**. Use a date years
  back, not months.
- **L1**: a date the provider cannot serve leaves the row **pending and counted** - assert the
  count, and assert the money was **not** written at today's rate.
- **L2 - the bound**: a decade-long pending span asks a **specific number** of chunks. Assert the
  number, not "more than one".
- **L1**: no pending rows means **no request at all**.
- **L1**: offline - the fetch fails, nothing throws, and the backfill still fills from cache.

### Vacuous traps, named

- **Testing with a date inside the 400-day window** - that already works and is exactly what RV.106
  proved. A test that passes against today's code proves nothing here.
- **Asserting the request was made** rather than that the row **filled**.
- **An unbounded retry** that passes the test and hammers the provider on every launch.
- Converting at today's rate to make a row "resolve".
- Asserting a localization key exists rather than what it renders.

## Screenshots

Only if the dead-end copy changes what the user sees. If it does: the Home footnote in that state,
dark theme, EN and RU, as `design/screenshots/RV.111-home-rates.png` and `-ru.png`.

- Pass the reset flag alongside the seed - seeds are idempotent and silently do nothing on a
  populated database.
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- Take them **outside** a test run - `simctl` and `xcodebuild test` fight over the device.
- **OCR your own capture and read the text back.** A committed screenshot has twice shown the
  opposite of its row's claim because it was taken before the screen settled.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **you**. Use
`pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, and whether each test was **run or only written**.
Name any closed decision you think is wrong and stop there rather than absorbing it - four of the
orchestrator's diagnoses have been wrong and every one was caught by an agent pushing back.
