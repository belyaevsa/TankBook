# RV.141 - "8 entries excluded" names no entries, no reason, and on Home is not tappable

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect

Product owner, 2026-09-08: *"there is a label - 8 entries excluded. But what entries? How can I find
them? What are the reasons?"* All three questions are unanswered.

- **On Home it is inert text.** `ExcludedEntriesFootnote` takes an optional `destination`;
  `HomeSections.swift:393` passes **none**. `TrendsView.swift:91` passes one. The type's own comment
  records the split as deliberate.
- **The route is singular even where it exists.** `destination: Route?` opens **one** entry, so with
  8 excluded, seven are unreachable.
- **No reason is shown anywhere.** "Excluded" covers a timeline conflict (F9a/S3) and an unresolved
  duplicate (S2). The fixes differ - edit the odometer or the date, versus Merge or Keep both - and
  the user cannot tell which they have.
- **Hard rule 7**: every warning names its next step. On Home this one names nothing.

## What I checked before writing this - do not re-derive it

**Siblings.** The footnote has exactly two call sites (`HomeSections.swift:393`,
`TrendsView.swift:91`). There is also a **shape sibling**: `PendingRatesFootnote`, whose own comment
says *"Same shape as `ExcludedEntriesFootnote`, without…"*. It appears to name its next step
already ("Check for rates", [RV.111]/[RV.132]) - **verify that and report**; if it has the same
defect, say so and file it rather than widening this row.

**The destination exists.** `Route.flaggedEntries` is the "Needs a look" screen
(`Routes.swift:82,108`), and [RV.133] recently gave it swipe actions. So a route into it is cheaper
than a new screen.

**The doc disagrees with the code, twice.** `docs/ERRORS.md:308` states the next step as
**"Tap → the flagged entry"** - singular, and Home does not do it at all. There is a matching Home
row earlier in the same doc. **Both must be reconciled in this change.**

## The trap that makes this more than a routing fix - read this twice

**`excludedEntryCount` and "Needs a look" do not count the same thing.** The footnote's count
includes **unresolved duplicate members**; the flagged-entries screen filters on **conflicts only**.
So the obvious implementation - route the footnote to that screen - produces a screen showing
**fewer rows than the number the user just tapped**, which is a worse lie than the silent label.

**Establish the two populations before you build**, and make them agree: either the destination shows
everything the count counts, or the count counts only what the destination shows. **Say which you
chose and why.** A count and its destination that disagree is the defect this row is about, one layer
down.

## What to build

- **The count reaches its entries from BOTH surfaces.** Home gets a destination; the route for N>1
  goes to a **list**, not a single entry.
- **Each row states its reason**, because the fix differs per reason.
- **Reconcile `docs/ERRORS.md`** (the Home row and row 308) with what you build, in the same change.
- Zero excluded entries shows no footnote at all - check that is already true and keep it.

## Explicitly out of scope

- [RV.133]'s swipe actions and the flagged screen's own behaviour beyond the filter question above.
- The duplicate-resolution and conflict-resolution flows themselves.
- `PendingRatesFootnote` - report on it, do not change it.

## Docs to read before writing (in order)

1. `docs/ERRORS.md` - Home and Trends rows for excluded entries. **The authority, and extend it.**
2. `docs/SCREENMAP.md` if you add or change a route.
3. `docs/SYNC.md` -> S2 and S3, for what "excluded" actually covers.
4. `CLAUDE.md` hard rules 5, 6, 7, 10.

## UI suites to run

`TankbookUITests/HomeUITests`, `TankbookUITests/TrendsUITests`,
`TankbookUITests/FlaggedEntriesUITests`. Report each observed, **non-zero** count - a filter matching
nothing prints "0 tests … passed" and still exits 0, and several RV suites here are
`extension HomeUITests`, so a class-name filter for them matches nothing.

## Tests you must add

- **L4, and it fails today**: the Home footnote is tappable and reaches the excluded entries.
- **L4**: with N>1 excluded, the destination lists **all N** - assert the count on the destination
  matches the count in the footnote. This is the test that catches the population mismatch.
- **L4**: each listed row states its reason, and a conflict and a duplicate read differently.
- **L4**: Trends keeps working - the regression guard.
- **L1**: zero excluded shows no footnote.
- **L4**: EN and RU at the largest text size. RU is where a reason label beside a count overflows.

## Vacuous traps, named

- **Routing to a screen that shows fewer rows than the count promised** - the trap above.
- Asserting the footnote `isHittable` rather than that tapping it **arrives somewhere with the
  entries** - `isHittable` returned true for an element 86% clipped (`RV.84`). Assert the frame
  against the window.
- Fixing Home and leaving Trends' singular route opening one of eight.
- Showing a reason that does not distinguish a conflict from a duplicate.
- Leaving `ERRORS.md` saying "Tap → the flagged entry".

## Screenshots

**EN and RU**, **dark**, outside any running test: the Home footnote and the destination it reaches.
Commit as `design/screenshots/RV.141-home.png`, `-ru.png`, `RV.141-excluded-list.png`, `-ru.png`.
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
**`simctl launch` on an already-running app silently ignores new arguments** - `terminate` first and
wait for the relaunch, or the "RU" shot is the EN one with a different clock. **You cannot see your
own screenshots**; state what you captured and do not assert it looks right.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change - or mutate one line to
prove the test's teeth. **Do not** `git stash`, `git checkout`, or move files out of the tree: an
agent did that on 2026-09-08 and a bad `mv` loop destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. Four of the orchestrator's diagnoses were wrong in one
recent session and an agent caught every one. If the population mismatch turns out not to exist,
**report that with evidence** rather than building around it.

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1808 tests / 209
suites, all green**, **811** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with thousands of phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suites above by name with observed, non-zero counts.
5. Localization gate - exit 0; report keys and RU percentage. Every new string is EN **and** RU.
6. Release build if you touch a `#if DEBUG` seam (a test seed is one). Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; the failing-then-passing output for the headline test; **which population you made
authoritative and why**; what you found about `PendingRatesFootnote`; and **anything you found and
did not fix**.
