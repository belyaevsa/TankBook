# RV.163 - no test asserts that anything can create an entity, and three features shipped on one nothing could

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect

`RV.156`: **`upsertStation` had zero non-seed callers.** So `PJ.19`'s ranking had nothing to rank,
`RV.150`'s stamping had nothing to stamp, and the Garage's stations list showed a list nothing could
add to. Three features built on an entity a hand-typing user could never create. **Green suite,
correct screenshot, permanently dead label.**

`PJ.55` is the same shape one level down and is **open right now**: `Station.favorite` has a reader
(`StationSuggestion.swift:130` ranks a favourite first), a column, a decoder - and **no production
writer**. Its only non-test writer is `ImportStation.swift:43`, which writes `false`. Rung 1 can
never fire.

**And here is the detail that matters most for your design:** about **ten test seeds** write
`favorite: true` (`HomeTestSeed.swift:436`, `RV166HomeTestSeed.swift:68`, `RV147HomeTestSeed.swift:58`
and more). The field looks thoroughly written. **A guard that counts seeds passes on both defects**,
which is why the row names that trap first.

## This brief's reading is a hypothesis - confirm it before you change anything

Confirm `Station.favorite` still has no production writer, and re-derive the writer inventory
yourself. **`PJ.55` may ship before or during your run** - it adds a favourite control on the Garage
station settings screen. If it has landed, that entity/field now has a writer and your guard must
still have a failing case; say what you used instead.

## What to build

**A test that asserts a production writer exists for every entity in `docs/SCHEMA.md`** - one that
is **neither a test seed nor the import path**.

`docs/SCHEMA.md`'s entities are `###` headings under `## Entities` (Vehicle, Entry, FillUp,
ChargeSession, ServiceRecord & Expense, Reminder, Attachment, Preferences, Station, ExchangeRate) -
read the doc, do not trust this list, and note that some headings cover two entities and one
(`ExchangeRate`) is explicitly *"local cache, deliberately NOT synced"*, which is exactly the kind of
honest exception the row asks you to record rather than silently pass.

Reuse the idiom this repo already has - **`MoneyHomeSideSumGuardTests` (RV.167, shipped today) is
the closest model**: a pure function over source text, a tree walk, and a reasoned allowlist with a
stale-entry check. Read it before you start. `SyncTriggerSourceGuardTests` (RV.157) is the other.

**The three exclusions are the whole design:**

1. **A test seed is not a writer.** Anything under a `*TestSeed.swift`, a `Tests` target, or inside
   `#if DEBUG` must not count. This is what hid `RV.156` and hides `PJ.55` today.
2. **The import path is not a writer.** `ImportStation.swift` writing a `Station` is precisely what
   made `RV.156` invisible: the entity *was* created, just never by anything a typing user could
   reach.
3. **Sync is not a writer either** - decide this and say so. A record arriving from another device
   was created *somewhere*, and if that somewhere is only ever another device, the entity is still
   uncreatable. State your rule.

**Record the honest exceptions with their reasons.** An entity that legitimately only ever arrives
by import or by sync is a **deliberate entry in a named list with its reason**, not a silent pass -
the list is the artefact that makes the next omission visible. A bare entry with no reason must fail
the guard's own self-check.

## Consider the field level, and say what you decided

`RV.156` was an **entity** with no writer; `PJ.55` is a **field** with no writer. The second is the
one still open, and it is the more common shape.

**Decide whether your guard covers fields, and argue it.** Covering every field of every entity is
likely too broad to be useful - but a field that a **ranking, a filter or a query reads** and nothing
writes is exactly the defect. If you scope to entities only, **say what the field-level version
would cost** and it becomes its own row. Do not silently do the easy half.

## Explicitly out of scope

- **[RV.162]** - the screen-reachability guard. Sibling row, same shape, its own dispatch.
- **[PJ.55]** - giving `favorite` its writer. **Do not fix it**; it is your failing case, and if it
  has already shipped you need another.
- **[RV.169]/[RV.170]/[RV.171]** - the re-homing, station-minting and receipt-persistence guards,
  all filed today. **Do not build them**; if your scanner generalises, say how.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> `## Entities` end to end. **The authority for what exists**; you are binding
   the code to it.
2. `docs/TESTING.md` -> where an architecture test sits; extend it in the same change to name this
   guard, as `RV.167` did.
3. `docs/DEFECT-PATTERNS.md` Part 2 - the "features built on an entity nothing creates" shape.
4. `CLAUDE.md` hard rule 13 and hard rule 14's `#if DEBUG` paragraph.

## Environment axes this crosses

**None at runtime** - test-only, no shipping code path differs. No screenshots, no locale, no
offline, no Release seam unless you touch a `#if DEBUG` region. Say if you disagree.

## Tests you must add

- **L1, and this is the teeth**: **delete the station creation path `RV.156` added and the guard
  fails.** The row names this explicitly. Do it, report the output, **revert it**.
- **L1**: every `SCHEMA.md` entity has a production writer outside seeds and import - the tree walk.
- **L1**: a documented exception passes, and **removing its reason fails**.
- **L1**: a **new** entity added to `SCHEMA.md` with no writer fails - supply the doc text to the
  scanner as a string so this is testable without editing the real doc.
- **L1**: a writer that exists **only** in a test seed does **not** count. Supply seed-shaped source
  text and assert it is not accepted. This is the trap that hid both defects, so it needs its own
  assertion, not a comment.

**Oracle for every expectation**: `docs/SCHEMA.md`'s entity headings are the list;
`TankbookRepository`'s `upsert*` functions are the writers; `RV.156`'s station creation is the
historical positive case and `ImportStation.swift` the historical false positive.

## The mutation you must run - I am naming it, do not choose your own

**Delete (or `#if DEBUG`-wrap) the production station-creation call `RV.156` added**, leaving the
import writer and every seed in place. The guard **must go red naming `Station`**. Then restore and
re-run. Report both outputs verbatim.

That is the mutation because it reconstructs `RV.156` exactly - the entity still has a table, a
decoder, an import writer and ten seeds, and a user still cannot make one.

## Vacuous traps, named

- **Counting a test seed or a `#if DEBUG` writer** - ten seeds write `Station.favorite` today.
- **Counting the import path**, which is what made `RV.156` invisible.
- An exception list with no reasons, which degrades to a skip list.
- A regex that matches `upsert` anywhere, including in a comment or a doc string - mask comments and
  strings, as `RV.167`'s scanner does.
- Passing because the walk found **zero** entities to check - assert the entity count is non-zero,
  or a doc-parsing bug reads as a green suite.
- Doing the entity level silently and never mentioning fields.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified tree, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

Re-measure the baseline yourself and report what you observe.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count. It must be **greater** than the
   baseline you measured.
4. No UI suite expected. If you touch one, name it and report an observed, **non-zero** count.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; **your decision on
field-level coverage and what the field version would cost**; your rule on whether sync counts as a
writer; the exceptions you recorded and their reasons; **every entity you found with no production
writer**; and **anything you found and did not fix**.
