# RV.141 - "8 entries excluded" names no entries and no reason

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## What was asked

Product owner, 2026-09-08, looking at the Home footnote: *"there is a label - 8 entries excluded.
But what entries? How can I find them? What are the reasons?"* All three are unanswerable from that
screen.

## Measured

- `ExcludedEntriesFootnote.swift` takes an optional `destination`, and its own comment records the
  split: *"On Trends the footnote is the route to the flagged entry... on Home it stays the passive
  caption it has always been."* **Home passes none**, so the count is inert text.
- **`docs/ERRORS.md` contradicts the code twice.** Row 56 (Home, timeline conflict) and row 257
  (Trends) both give the next step as **"Tap -> the flagged entry"**. Hard rule 7 requires a warning
  to name its next step; on Home this one names nothing while the doc says it does.
- Where the route does exist it is **singular** - `destination: Route?` opens ONE entry, so 8
  excluded entries reach one and seven are unreachable.
- **No reason is surfaced anywhere.** "Excluded" covers two different problems with two different
  fixes.

## The complication that decides the design - I measured it, do not re-derive it

`HomeStats.swift:70-74`: `excludedEntryCount` is **conflict-flagged entries PLUS the excluded
members of unresolved S2 duplicate pairs**.

`FlaggedEntriesView.reload()` (`:276-292`) collects entries where **`entry.conflict != .none`** and
nothing else.

**So "Needs a look" is a strict subset of what the footnote counts.** Routing the footnote straight
there would show fewer rows than the number promised - the "says 8, shows 6" defect, which is the
same class as the one this row exists to fix. Whatever you build, **the destination must account for
both classes**.

## Design questions ALREADY CLOSED

1. **The count and its destination must agree.** A footnote saying 8 that lands on 6 rows is not an
   improvement. Assert the equality in a test.
2. **Each row states its reason**, because the fixes differ: a timeline conflict is resolved by
   editing the odometer or the date; a duplicate by Merge or Keep both. "Excluded" is the word the
   user already told us they cannot act on.
3. **Reconcile `docs/ERRORS.md` in the same change.** Rows 56 and 257 currently describe behaviour
   Home does not have. Whichever way this lands, the doc and the code must agree - decide explicitly
   whether Home gains the tap or the doc drops the promise, and do not leave them contradicting.
4. **Do not re-implement duplicate resolution.** [RV.131] rebuilt the duplicate card on Home with
   both members, their differences and the attachment marker. If a duplicate member is listed here,
   its resolution belongs where that card is - route to it rather than growing a second Merge.

## What to build

Decide between widening "Needs a look" to cover both classes, and giving the footnote a destination
that lists exactly what it counted. **Say which you chose and why.** "Needs a look" already exists,
already has swipe actions ([RV.133]) and is the surface a user would expect - but it is currently
conflict-only, so widening it is a real change to what that screen means, and its `Row`
(`FlaggedEntriesView.swift:37-44`) carries no flag kind to render a reason from.

## Explicitly out of scope

- The exclusion RULES themselves - what makes an entry conflicted or a pair duplicate.
- The duplicate card's own behaviour ([RV.131], shipped).
- [RV.140] and [RV.142] both edited `HomeSections.swift` before you. `git log` first and build on
  what is there.

## Docs to read before writing (in order)

1. `docs/ERRORS.md` -> rows 56 and 257 (**the authority, and currently wrong**).
2. `CLAUDE.md` - hard rule 7.
3. `docs/SYNC.md` -> S2 and S3, for what each exclusion means.
4. `docs/SCREENMAP.md` -> where "Needs a look" sits and its back path.

## Checks

Baseline: `main` green at **1664 tests / 185 suites**, **777** localization keys. **Re-measure
yourself** - two rows land before you.

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0.
3. `cd ios && swift test` - full, never subsetted; report the number.
4. `xcodegen generate` + the UI suites you touched **by name**; report a **non-zero** count - a
   filter matching nothing prints "0 tests ... passed" and still exits 0.
5. Localization gate - 0, report the key count.
6. Release build - required if you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L1, the trap**: the destination lists **exactly** `excludedEntryCount` entries, on a fixture
  containing **both** a conflicted entry and an unresolved duplicate pair. A fixture with only
  conflicts cannot catch the subset bug.
- **L4**: the Home footnote is reachable and lands on that list.
- **L4**: a conflicted row and a duplicate row **read differently** - each states its own reason.
- **L4**: at zero excluded the footnote is absent, as now.

### Vacuous traps, named

- Routing to a single entry when N>1 - the current shape on Trends.
- Asserting the footnote is tappable without asserting **where it lands**.
- Showing "excluded" as the reason - the word the owner already cannot act on.
- Testing with conflicts only, where the count and the list agree by accident.
- Fixing Home and leaving `docs/ERRORS.md` describing the old behaviour.

## Screenshots

The footnote's destination showing both a conflict and a duplicate with their reasons, dark, EN and
RU: `design/screenshots/RV.141-excluded-list.png` and `-ru.png`. Take them **outside** a test run,
pass the reset flag with the seed, and **OCR your own capture** before reporting it.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**,
which destination you chose and why, and how you reconciled `docs/ERRORS.md`. Name any closed
decision you think is wrong and stop there rather than absorbing it.
