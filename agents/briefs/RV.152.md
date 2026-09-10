# RV.152 - changing a car's home currency asks what to do with the log it already has

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect

Product owner, 2026-09-09. Changing a car's home currency is **silent about the history it already
has**. Today:

- [RV.140]'s re-home runs and touches **only rate-pending entries** - they carry no snapshot, so
  nothing is restated. `MoneyBackfillService.rehome` (`:232-248`) skips anything where
  `money.isRatePending` is false.
- **Every snapshotted entry keeps its old home currency.** That is correct - hard rule 3 makes a
  snapshot immutable - and it is **never explained**.

The result is a **mixed history the user did not ask for and was not told about**. It is legible
only because [RV.145] shipped: the surfaces now render per-currency subtotals (`91 € · 8 $`) instead
of one wrong number. **This row is offerable precisely because of that** - before RV.145, "keep them
as they are" produced a screen that lied.

## The seam, pinned to a line

`ios/App/Sources/VehicleDetail/VehicleDetailView.swift:313-328`:

```swift
try repository.upsertVehicle(updated)                 // ← the write
...
if vehicle.homeCurrency != updated.homeCurrency {     // ← RV.140's re-home, AFTER the write
    _ = try MoneyBackfillService(store: AppRates.store)
        .rehome(repository, vehicleID: updated.id, to: updated.homeCurrency)
}
```

**The row says ask BEFORE the write.** Today the currency change is committed and then reconciled,
so you will have to restructure the save: detect the change, ask, and only then write. Say how you
did it.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left, and **`PJ.55` shipped into the station half of this area
today**. Re-read the save path. If the ordering already differs, build on what you find and say what
moved.

## The product decisions are MADE - do not relitigate them

Product owner, 2026-09-09:

1. **Two answers**, both plainly worded: **Convert the log** and **Keep the entries as they are**.
2. **Rows go pending rather than blocking**, and **the prompt says so upfront, with the count** -
   verbatim: *"row goes pending, prompt says so upfront"*.
3. **No undo.** The warning carries that, **and says the original receipt amounts are never
   touched** - which is what makes the warning fair rather than frightening.

## What to build

**Ask at the vehicle save, and only when the question is real**: the currency actually changed
**and** the car has entries. An empty log needs no question; re-picking the same currency needs no
question.

**Answer (1) - Convert the log.** Each entry's **derived half** is recomputed from its **immutable
receipt** (`Money.amount` + `Money.currency`) at **that entry's OWN date** - hard rule 3, never
today's rate. The receipt is untouched; only the derived home figure changes. This is **not** the
silent snapshot rewrite RV.140 forbade, because the user asked for it.

`MoneyBackfillService.outcome(for:in:)` (`:252-264`) is the shape to follow - it looks up
`store.snapshot(original:home:on: entry.date)` and converts - but it **guards on
`money.isRatePending`**, so it will not touch the snapshotted entries this answer must convert. You
need a sibling operation, in the same service, sharing the same date-scoped lookup so the two can
never disagree about what a date's rate is.

**Rows whose date has no rate become rate-pending and counted** - the ordinary F9 state - and the
prompt states that count **before** the user commits. Conversion quality depends on [RV.151] and
[RV.139]; until those land most rows may go pending, **and the prompt must not pretend otherwise**.

**Answer (2) - Keep the entries as they are.** Existing entries keep their home currency, new ones
use the new one, and **the copy explains what that means for the stats**: totals show per-currency
subtotals rather than one figure, because there is no honest way to add two currencies (hard rule 2).

**Either way [RV.140]'s pending-row re-home still runs** - a pending entry has no snapshot to
protect.

## Explicitly out of scope

- **[RV.143]** - a home-currency change arriving by SYNC re-homes nothing on the receiving device.
  Related and deliberately separate; this row is the local, user-initiated change. **If your work
  makes RV.143 easier or harder, say so.**
- [RV.151] / [RV.139] - rate coverage. You depend on them; you do not fix them.
- The Add-car path. This is the *change* case, on a car that already has a log.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> **Money**, the snapshot rules, and **Recalculation on edit**. Hard rule 3
   lives here and it governs everything this row does.
2. `docs/ERRORS.md` -> **F9** (rate-pending) and the Vehicle-detail rows - the authority for what the
   prompt and its outcome say. **Extend it in the same change** with both answers and their copy.
3. `docs/JOURNEYS.md` -> the money/rates journey, if the prompt changes what it promises.
4. `CLAUDE.md` hard rules 2, 3, 8, 13.

## Environment axes this crosses

**Locale** - new prompt copy, EN and RU, gate at 100%; **RU is where a two-sentence warning with a
count runs longest**. **Offline** - conversion depends on the rate cache; an offline convert is the
"most rows go pending" case and the prompt must be honest about it. **Screenshots: EN and RU
required** for the prompt, and the RU one is the real check. No signed-out difference. Release build
if you add a `#if DEBUG` seed - you probably will.

## If this adds a failure path, what makes it visible in production?

**It does**: a convert that partially succeeds. Add the shape-only event that lets one device log
answer *"how many converted, how many went pending?"* - counts only, never an amount, a currency
pair's values, a station or a date (hard rule 12; the currency **codes** and the **counts** are
shape, the money is not). Say what you added.

## Tests you must add

- **L4, and it FAILS TODAY**: changing the currency on a car **with** entries presents the prompt;
  on an **empty** car it does not; re-picking the **same** currency does not.
- **L4**: the prompt states the **pending count before the user commits**. **Oracle**: the number of
  entries whose date has no rate in the pack, computed by the same lookup the convert will use -
  never a second count written in the test.
- **L1, convert**: recomputes from the receipt at the entry's **own date** - assert the resulting
  `homeAmount` **and** `rate`, and that `amount` and `currency` are **byte-identical**. **Oracle**:
  the seeded pack's rate for that entry's date, not today's.
- **L1, convert**: a date with **no** rate leaves that entry rate-pending **and counted**, and the
  rest still convert. A partial convert is the expected case, not an error.
- **L1, keep**: every snapshotted entry is **byte-identical** afterwards, and only the pending ones
  are re-homed - [RV.140]'s behaviour, unchanged.
- **L1**: **neither answer ever converts at today's rate.** The negative claim that keeps hard rule 3
  intact.

Name the UI suite you extend and report its observed, **non-zero** count. **Run any app-target suite
separately** - a combined `xcodebuild` invocation silently dropped a `TankbookTests` filter on
2026-09-10 and reported a green subset ([PJ.56]).

## The mutation you must run - I am naming it, do not choose your own

**Make convert use today's rate instead of the entry's own date** (`Date()` in place of
`entry.date` in the lookup). The L1 convert test **must go red on the resulting `homeAmount`/`rate`**,
not on a count. Then restore and re-run. Report both outputs verbatim.

That is the mutation because "converted at today's rate" is the one outcome that looks completely
correct on screen - every figure populated, nothing pending - and is silently wrong forever. Hard
rule 3 exists for it.

## Vacuous traps, named

- **Converting home-to-home at today's rate**, which destroys history the receipt still holds.
- **Asserting the prompt appeared rather than what each answer DID** - the prompt is the cheap half.
- **A fixture with no snapshotted entries**, where the two answers are indistinguishable and both
  pass.
- Promising an undo the row does not have.
- A prompt on a car with an empty log, or on re-picking the same currency.
- Asserting a count the test computed itself rather than through the shared lookup.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Check
what is BEHIND your subject** - on 2026-09-10 a correct toast was photographed over a screen no user
can reach, and it looked like a successful capture.

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` is **1852 tests / 217
suites**, **816** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. **`xcodebuild ... build` for the app target.** `swift build` compiles only the SwiftPM package;
   anything under `ios/App/Sources` is invisible to it, and on 2026-09-10 a change was green on
   build + lint + 1826 tests and did not compile into the app ([RV.174]).
5. `xcodegen generate`, then the UI suite you touched by name with an observed, **non-zero** count.
6. Localization gate - exit 0; report keys and RU percentage.
7. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; how you restructured the
save so the question precedes the write; the copy both answers carry; what you added for
observability; whether your work helps or hinders [RV.143]; and **anything you found and did not
fix**.
