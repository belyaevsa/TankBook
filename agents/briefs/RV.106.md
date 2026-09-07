# RV.106 - a month whose rates have not arrived must not report "0 €"

## The certain half, pinned to one line

`LogStream.section` sums the month's rows with
`entry.money?.homeAmount ?? Decimal.zero`
(`ios/Sources/TankbookCore/Consumption/LogStream.swift:319-331`), so a **rate-pending** row - the
amount is known, its home-currency value is not resolved yet - contributes **zero**, and the month
divider renders that sum as a fact.

The product owner's screenshot (2026-09-07, their imported history): August rows carry amounts
(107.25 €, 101.71 €, 112.06 €); **July and June show no amount on any row and a month total of
`0 €`**. The app states a spend the user did not have. Stats are derived (hard rule 2), which is
exactly why a derived figure must not assert what the data cannot support - `0 €` beside rows with
no amount is not a missing number, it is a **wrong** one.

`PendingRatesFootnote` exists and counts the pending rows
(`ios/App/Sources/Shared/PendingRatesFootnote.swift:22`) but it is a **bare `Text`**: it names no
next step and offers no action (hard rule 7).

## What to build

1. **A month containing rate-pending rows must not print a bare total.** Show the partial with its
   pending count, or omit the figure and say why - **decide and write it down, but `0 €` is not an
   option.** Also decide what the divider shows when **every** row in the month is pending, which is
   the owner's actual case.
2. **Give the pending footnote a next step** (hard rule 7). It states a count and stops; the user has
   no way to ask for a retry and no idea whether waiting will help.
3. **Do NOT convert at today's rate to make a number appear.** `rateDate` is the entry's own date and
   snapshots are immutable (hard rule 3). That is the defect [RV.88] was filed for and reintroducing
   it to tidy a total would be worse than the blank.

## The second half is an OPEN QUESTION - establish it before building any retry

What I measured, so you do not repeat it:

- The import drain (`ManualFillUpCurrencySupport.drainAfterImport`, [RV.88]) runs **once**, off the
  commit: one `fetchSpan` over the imported span, one scoped backfill, **no retry and no resume**
  (`ios/App/Sources/ConfirmManual/ManualFillUpCurrencySupport.swift:104-157`).
- The **account-wide** backfill DOES re-run at every launch - `AppRates.refresh()` -> `runBackfill()`
  (`:75-97`), via the app root's automatic pass - but it can only fill from rates the store holds.
- The owner's **server** log shows the rate archive being published incrementally:
  `rates.backfill Processed=50 Published=100` at 05:15 and 05:20, while the import ran 05:10-05:17.
  So the server plausibly did not yet have June and July when the client asked its one time.

**Determine, on the owner's real data or a faithful reproduction: do these rows resolve on a later
launch once the server has published those dates?**

- **If yes**, the fix is the honest total plus a truthful "waiting for rates" surface, and no retry
  machinery is needed. Say so - that is a good outcome, not a small one.
- **If no**, there is a second defect: a one-shot drain that misses is permanent, because nothing
  scoped to the imported rows ever runs again. Find it and report it before building.

**Do not guess this.** Write what you measured, with the observation that produced it.

## Explicitly out of scope

- The rate provider, the feed, or the server's publishing schedule.
- Changing `MoneyBackfillService`'s fill-blanks-only semantics or hard rule 3.
- The Trends totals, unless they share the same summing code - if they do, say so and fix both.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L1 (the certain half)**: a month whose rows are rate-pending does **not** report `0 €` - assert
  what the divider actually renders. Cover **three** fixtures: all-pending, **mixed** (some
  converted, some pending - the figure must be marked partial rather than silently short), and
  fully-converted (unchanged, to the cent).
- **L1**: the purchase-group and duplicate arms of that same `reduce` behave consistently - they use
  the same `?? .zero` shape and must not disagree with the entry arm.
- **L4**: the pending footnote offers its next step and the action does something observable.
- Suites: `HomeUITests`, plus `TrendsUITests` if Trends shares the code.

### Vacuous traps, named

- **Asserting the total is not zero without asserting what it IS** - a wrong non-zero number is no
  better than a wrong zero.
- **Testing a month where every row converted**, which passes today.
- **Filling with today's rate** to make an assertion pass - that is [RV.88] all over again.
- Asserting the footnote's **count** rather than that it now names a next step.
- A fixture with one pending row in a month of ten, where "0 €" would never have appeared anyway.

### Mutations (run each, report, restore byte-for-byte)

1. Restore `?? Decimal.zero` in the entry arm -> the all-pending test must fail.
2. Report the partial total as if complete (drop the pending marking) -> the mixed test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Screenshots

EN **and** RU, **dark**, `design/screenshots/RV.106-log-pending-month.png` and `-ru.png`, showing a
month whose rows are pending beside one that converted - the owner's actual shape.
- Capture outside a test run; `-homeResetDatabase` with any seed.
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- **Verify the pair differs with `md5 -q`** and report both hashes.
- You cannot see your own screenshots; the orchestrator opens every one.

## Docs to reconcile

`docs/ERRORS.md` (the pending-rates surface and its next step - the 3-question audit applies),
`docs/SCHEMA.md` if the money-pair rules need the "a pending row is not zero" sentence stated,
`docs/SYNC.md` S8 if the silent-fill behaviour changes.

## Hard rules that decide things in this area

**2** (derived figures - and a derived figure that states a falsehood is the defect) · **3** (money
is a pair; `rateDate` is the entry date, never today) · **7** (the pending state names its next
step) · **10** (EN + RU, full localised phrase) · **14**.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`, `backend/src/**`,
`backend/tests/**`, `design/screenshots/**`, and the docs named in this brief. **If your row's "out
of scope" says not to touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above. Where this brief leaves a genuinely open choice, **take the smallest correct option and
keep going**, then say which you took and what you rejected. Do not stop and wait on it.

**My diagnosis can be wrong** - it has been several times this month, and the agent was right every
time. If what you measure does not match what this brief claims, **say so and report the
measurement**; that beats a fix built on a wrong premise.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0; `cd ios && swift test` -> 0, count reported (before -> after). Never
  subset it.
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- `swift run --package-path ios localization-gate` from the root -> 0.
- **If you touched `backend/`**: `dotnet build` -> 0, `dotnet test` -> 0 (count before -> after),
  `dotnet format --verify-no-changes` -> 0.
- **If you touched `ios/App/`**: `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  Run `xcodegen generate` first if you added a file. **Check the observed count is non-zero.**
- **A change touching a `#if DEBUG` seam also builds RELEASE**
  (`xcodebuild -configuration Release ... build`).
- **`$?` after a pipe is the pipe's exit code.** Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.
- **Watch the file-length ceiling**: several files sit at 699-700 lines and the lint error is a hard
  700. If your change pushes one over, split it the way the codebase already does (`+Wizard`,
  `+Cars`, `L10n+…`), never by deleting comments.

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. The measurement this row asked for, in numbers.
3. Each mutation: what you broke, which named test failed, that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on.
4. Screenshot paths and md5s, if this brief asked for screenshots.
5. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
6. Anything in this brief that was wrong, as a Residual.
7. Whether the tests were actually **run**, not only written.
