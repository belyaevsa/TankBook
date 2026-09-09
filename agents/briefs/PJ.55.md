# PJ.55 - the station ranking's first rung reads a flag nothing can set

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The product decision is MADE - do not relitigate it

**Product owner, 2026-09-09: the rung stays, and `favorite` gets a writer on the Garage's station
settings screen.** The two alternatives - also adding a long-press on the entry's station row, and
deleting the rung - were both offered and **not** taken. Build the Garage toggle. If you find a
reason the Garage is the wrong home, **report it and build it there anyway**; the call is the
owner's, not yours.

## The defect, pinned to lines

[PJ.19]'s ladder ranks a **favourite within 300 m** first
(`StationSuggestion.swift:130`, `.filter({ $0.0.favorite })`), and **`Station.favorite` has no
production writer**:

| Site | What it does |
|---|---|
| `Migrations.swift:325` | the column defaults to `false` |
| `Records+Extras.swift:82` | the decoder reads it |
| `ImportStation.swift:43` | the only non-test writer, and it writes **`false`** |
| `HomeTestSeed.swift:436`, `RV166HomeTestSeed.swift:68`, and ~8 more | write `favorite: true` - **all test seeds** |

That last row is the point, and it is the trap [RV.163] names: **the field looks written because a
dozen seeds write it.** No production code ever sets it, there is no favourite control anywhere -
not on the entry's station row, not in the Garage - so **rung 1 can never fire** and the ladder
silently degrades to its lower rungs for every user.

`docs/SCHEMA.md:452` and `JOURNEYS.md` -> J4's *"filled by use"* both describe a flag the app cannot
fill.

**This is [RV.156]'s shape one level down**: RV.156 gave stations a creator; this is the same
orphan-state defect on a **field** of the thing it created - which is why the journeys walk found it
and RV.156's own brief did not.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. **Confirm `favorite` still has no production writer**
(`grep` for it outside tests and seeds) and that rung 1 is still first in the ladder. If something
now writes it, report that and stop.

## What to build

**A favourite control on `StationSettingsView`** (`ios/App/Sources/StationSettings/StationSettingsView.swift`),
the per-station screen [RV.150] built. It already has the shape you need: a `section(_:content:)`
helper wrapping a `SectionEyebrow`, and one `"Location"` section. Add the favourite beside it.

Requirements that are not negotiable:

- **Reversible.** Hard rule 13: a value the user set is theirs, and **un-favouriting must work** and
  must persist. A one-way toggle is the defect in a new costume.
- **It is a dirty write like any other field.** A `Station` is a synced entity (`docs/SCHEMA.md` ->
  Station, record-level LWW). Setting the flag marks the record dirty and it syncs; it must survive
  a round trip.
- **Never inferred.** Do not derive a favourite from visit count or `lastUsedAt` - that invents a
  fact the user never stated (hard rule 13). [RV.150]'s stamp already fills `lastUsedAt` and
  `defaults` by use; **favourite is the one field that cannot be inferred**, which is the whole
  reason it needs a control.
- **Reconcile the docs in the same change**: `docs/SCHEMA.md` (the field's description) and
  `docs/JOURNEYS.md` -> J4 (*"filled by use"* is wrong for this field - it is filled by the user).
  Today both describe behaviour the code cannot produce.

**Check the reachability of the screen you are adding to.** `StationSettingsView` takes a
`stationID` and its doc comment says `nil` is a debug pose. **Confirm a user can reach a real
station's settings from the Garage without a debug flag** - that is `PJ.4`'s failure shape, and if
the route is DEBUG-only your toggle is unreachable and the row is not done. Report what you found.

## Check the sibling while you are there - report, do not fix

**`Station.brand` is likewise only ever written by the import path.** [RV.161] plans to extract it
from receipts. **Say whether it has the same gap** - a reader with no writer - rather than leaving
it for a third walk. Do not build it.

## Explicitly out of scope

- **[RV.115]** station normalisation and merging - two devices naming the same forecourt is its
  problem, not yours. Do not auto-merge on name.
- **[RV.161]** brand extraction.
- The ranking ladder's other rungs, and `PJ.19`'s ordering rules.
- A long-press affordance on the entry's station row - **explicitly not taken by the owner**.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> **Station**, its fields and the LWW rule. **The authority for the field's
   meaning**; extend it in the same change.
2. `docs/JOURNEYS.md` -> **J4**, the station-suggestion journey and what it promises about how the
   ranking learns.
3. `docs/SYNC.md` -> Reference data and hard rule 13's "once a user changes one, that value is
   theirs permanently" - **no sync merge or later curation may overwrite a user-set favourite**.
4. `docs/DESIGN.md` -> control treatment on a settings screen; `CLAUDE.md` hard rules 5, 10, 13.

## Environment axes this crosses

**Locale** - a new label and its section header, EN and RU, gate at 100%. **Sync** - the round trip
is part of the acceptance. **Screenshots: EN and RU required** (`-seedStationSettings` and
`-presentScreen stationSettings` exist; check the exact argument names in `DebugLaunch.swift`). No
offline-specific path, no signed-out difference (a guest has stations too - **confirm that** and say
so). Release build only if you add a `#if DEBUG` seam.

## If this adds a failure path, what makes it visible in production?

A write that silently fails to persist would be invisible. If the toggle's write can fail, add the
shape-only event that answers "did the favourite write land?" (`docs/LOGGING.md`, hard rule 12 - the
station id is loggable, its **name is not**). Say whether you added one and why.

## Tests you must add

- **L1, and it FAILS TODAY**: setting a station favourite persists **and rung 1 then outranks a
  nearer non-favourite**. **Oracle**: `StationSuggestion`'s ladder - a favourite within 300 m beats
  a closer non-favourite; construct both and assert the **resulting order**. **Assert the ranking
  reordered, not that the flag flipped** - the field is the mechanism, the order is the feature.
- **L1**: the flag survives a sync round trip like any other field, and **a pull does not overwrite
  a user-set favourite** (hard rule 13 + `docs/SYNC.md` -> Reference data).
- **L4**: the affordance is reachable and **reversible** - turn it on, turn it off, and the off
  state persists across a relaunch.
- **L4**: EN and RU.
- **L1**: nothing infers a favourite - a station used many times is still not favourite unless the
  user said so.

Name the UI suite you extend and report its observed, **non-zero** test count.

## The mutation you must run - I am naming it, do not choose your own

**Make the toggle's write a no-op** (drop the persist call, keep the UI state) while leaving the
control on screen. **The ranking test must go red** - not the "the toggle exists" test. Then restore
and re-run. Report both outputs verbatim.

That mutation is chosen because the row's failure mode is precisely a control that looks like it
works: `favorite` has had a reader, a column, a decoder and a dozen seeds for months, and none of
that made rung 1 fire.

## Vacuous traps, named

- **Asserting the field changed without asserting the RANKING reordered** - the field is the
  mechanism, the order is the feature, and the field already changes fine in seeds.
- **Inferring a favourite from visit count** - invents a fact the user never stated (hard rule 13).
- A one-way toggle, or one whose off state does not persist.
- Counting a **test seed** as proof the writer exists - that is exactly what hid this defect.
- Adding the control to a screen a user cannot reach without a debug flag (`PJ.4`'s shape).
- Leaving `SCHEMA.md`/J4 describing a flag "filled by use".

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Check
what is behind your subject** - `RV.149`'s first capture put a correct toast over an empty garage, a
state no user can reach, and it looked like a successful capture.

## Standing checks

Re-measure the baseline yourself and report what you observe.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suite you touched by name with an observed, **non-zero** count.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; **whether a user can
reach a real station's settings screen with no debug flag, and by what route**; your verdict on
`Station.brand`'s sibling gap; and **anything you found and did not fix**.
