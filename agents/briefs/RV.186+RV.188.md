# RV.186 + RV.188 - a timeline conflict that is not one, and a panel that cannot explain it

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Two rows, one dispatch, and the order matters**: `RV.188`'s panel is **how you diagnose**
`RV.186`. Fixing the validator without the panel leaves nobody able to confirm it - which is exactly
where the product owner and the orchestrator both ended up.

## RV.186 - the defect

Product owner, 2026-09-10, after a Drivvo import: *"services expenses are at the same day as fillups
with the same odo with other expenses. It's not a problem."* The Excluded-entries screen shows two
Services at **396 930 km / 5 Sep 21** and an Expense sharing **377 733 km / 22 Mar 21** with the
fill-up of that reading.

**Cause pinned.** `TimelineValidator` treats every entry kind identically:

- `invariantHolds` (`:70-73`) requires the odometer to **strictly** increase across ALL entries.
- CHECK 1 (`:140`) flags when `odo <= previous.odometer`.

Two entries at one reading therefore always conflict. **But the same reading is exactly what a
service at the pump looks like**: you fill up and have the work done without moving. The odometer
measures **travel**, and only fill-ups measure travel against fuel; a service or expense is an
annotation at a point, not a second journey.

**The consequence is data loss in the stats**: these entries sit on the Excluded page, so an imported
history silently loses spend and service records for a reason that is not a defect in the data.

### The owner's SECOND case, which you must explain

Two **fill-ups** on 20 Sep 2020 with **different, rising** odometers - **360 200 → 360 519** - are
also flagged. The orchestrator checked both rules against those numbers:

- CHECK 1: `360519 <= 360200` is **false**.
- CHECK 2 (pace): guarded on `days > 0`, so a same-day pair contributes **no** pace bound.

**Neither rule explains that flag**, so the culprit is an entry the panel does not show. **Reproduce
it with the real Drivvo fixture and say what it was.** If it is a same-odometer sibling, this row
covers it. **If it is not, it is a THIRD rule and needs its own row** - report it, do not widen this
one to swallow it.

## What to build for RV.186

**Make the strict-increase rule apply between entries that MEASURE travel, and let an annotation
share a reading.** Decide precisely which kinds are which and record it in `docs/SCHEMA.md` beside
the invariant. The obvious line: `FillUp` and `ChargeSession` must strictly increase; `ServiceRecord`
and `Expense` may equal a neighbour but never go backwards.

**A falling odometer stays a conflict for every kind** - that half is right and must not regress.

**Check every consumer of `invariantHolds` and CHECK 1 before changing them** - the import's F6a
gate, the review list and the sync flag all lean on this. A rule that changes shape must change in
one place, or the page and the badge will disagree.

## RV.188 - the panel cannot explain itself

The neighbourhood panel lists **`Previous entry`** and **`This entry`** and stops. In the owner's
screenshot both are consistent - 377 702 → 377 733, same day, rising - while the message reads *"The
entries around this one can't all be right - no odometer or date fits between them"*
(`TimelineNeighbourhood.swift:218`, the `inconsistentNeighbourhood` case, which fires when the valid
range collapses on **both** sides). The entry actually responsible is the **third, unlabelled point**
on the chart.

So the user is shown two numbers that agree, told they are impossible, and given no route to the one
that disagrees. **Hard rule 7 fails in substance**: the next step is *"check it"*, and the thing to
check is not on screen.

**Reported twice** - the same panel, a different entry (20 Sep 2020), the same dead end.

### What to build for RV.188

- **Show the NEXT entry** beside Previous and This, with its odometer and date - the panel already
  prints exactly that for the two it lists.
- **Label the chart's points** with odometer and date. The chart currently plots the culprit as an
  anonymous dot.
- **Make the message name the offending PAIR** rather than gesturing at "the entries around this
  one". It knows which comparison failed; saying so turns a dead end into an instruction.
- **Decide what an empty range shows when there is more than one culprit**, and record it rather
  than picking the first.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. **Reproduce both rows against the owner's fixture
(`Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv`) before changing anything.** The
orchestrator's diagnoses have been wrong four times in this session and an agent caught every one -
including, on `RV.189`, a confident cause that the code disproved.

## Explicitly out of scope

- The pace limit's value, and `paceLimitKmPerDay` as a per-car setting.
- [RV.187]'s titles (a separate dispatch, though it touches the same Excluded-entries list - **do not
  edit the row's title rendering here**).
- The import's F6a gate copy.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` → the odometer invariant and **Validation (runs on every write)**. **The
   authority**; the kind distinction is recorded there in the same change.
2. `docs/ERRORS.md` → **F9a**, the conflict copy and its next step.
3. `docs/JOURNEYS.md` → F6a/F9a.
4. `CLAUDE.md` hard rules 7, 8.

## Environment axes this crosses

**Locale** - the panel's new rows and any reworded message, EN and RU; **RU is where a date plus a
six-figure odometer beside a chart point is tightest**. **Screenshots: EN and RU** of the panel
showing three entries with labelled points. No offline path, no Release seam expected.

**Add capture lines to `scripts/capture-screenshots.sh` for any screenshot you commit** - three rows
shipped out-of-band screenshots in the last day ([RV.176]).

## Tests you must add

- **L1, RV.186, and it FAILS TODAY**: a service at the SAME odometer as a same-day fill-up is not
  flagged, and is **not excluded from the stats** - assert both.
- **L1**: two services at one reading are not flagged (the owner's 396 930 pair).
- **L1**: an entry whose odometer goes BACKWARDS is still flagged, for every kind.
- **L1**: two **fill-ups** at the same reading are still flagged - they claim travel that did not
  happen.
- **L1, the owner's second case**: two fill-ups on one day at 360 200 and 360 519 are not flagged.
  **If your fix does not make this pass, say what does** - it may be the third rule.
- **L4, RV.188**: the panel lists the next entry when one exists, the chart's points carry odometer
  and date, and the message names the failing pair.
- **L4**: a neighbourhood with no next entry still renders, with no blank row.

Report each suite's observed, **non-zero** count. **Check the COUNT, not the exit code** - on
2026-09-10 a filter matched nothing three times and printed `TEST SUCCEEDED` with exit 0 on zero
tests; filter by the **suite** name, not the file's.

## The mutation you must run - I am naming it, do not choose your own

**Restore the strict `odo <= previous.odometer` comparison for every kind.** The same-odometer L1s
**must go red**, and the falling-odometer and two-fill-ups L1s must stay **green**. Then restore and
re-run. Report both outputs verbatim.

That split is the evidence: it shows the fix narrowed the rule rather than removing it.

## Vacuous traps, named

- **Relaxing the rule for every kind**, which lets two fill-ups at one reading through.
- Asserting the flag is gone **without** asserting the entry is back IN the stats.
- Changing `invariantHolds` and leaving CHECK 1, or the reverse - they must agree.
- **Widening RV.186 to swallow the second case** without showing it is the same rule.
- Labelling the chart's axes but not its points, which still leaves "which entry is that".
- A message that names a pair it did not actually test.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. An agent's `git stash` +
`mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source** - it reuses the previous binary, and on 2026-09-10
that photographed a mutated build and presented it as proof of a fix.

## Standing checks

As left, `main` is **1864 tests / 222 suites**, **829** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full, never subsetted; report the count.
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then each UI suite you touched **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. Release build if you touch a `#if DEBUG` seam.

Verify by **exit code** (`echo $?`).

## Report back

Every check with the **exit code observed** and the counts; run or only written; **the mutation's
red-then-green output, verbatim**; **what the culprit was in the owner's second case, and whether it
is this rule or a third**; which consumers of `invariantHolds`/CHECK 1 you found; and **anything you
found and did not fix**.
