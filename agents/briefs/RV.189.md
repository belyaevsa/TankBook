# RV.189 - imported fill-ups do not show the station the file names

**This is an INVESTIGATION first and a fix second.** The cause is **not established**, and the
orchestrator's first diagnosis was **wrong**. Do not skip to a fix.

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

## The symptom

Product owner, 2026-09-10: *"drivvo import has gas station names, but they are ignored during the
import."* The Log screenshots show imported fills titled **`92`** - the fuel kind - where [RV.142]
promises the station name.

## What the orchestrator got WRONG, recorded so you do not repeat it

The first diagnosis was *"the commit never persists the Station row"*, based on `grep upsertStation`
finding no caller in the import path. **That is false.**
`ImportFlowModel+Wizard.swift:373-383` (`materializedStationRecords`) appends the Station rows to the
**same `commitImport` call**, explicitly so *"a fill never references a station that did not land"*.
They travel as `ArchiveImportRecord` values, which is why the grep missed them.

## What IS verified, end to end

| Link | Evidence |
|---|---|
| The parser reads the column | `DrivvoParser.cs:260,287`, header `Азс` / `Gas station` |
| The owner's file carries values | `Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv:3-5` → `Газпром` |
| The wire carries it | `ImportCandidate.station` (`ImportModels.swift:127-130`) |
| The conversion resolves and stamps it | `ImportConversion.swift:53-66`, deterministic id, RV.142 |
| The commit materialises the rows | `ImportFlowModel+Wizard.swift:373-383`, one transaction |

**Every link holds on inspection. So the break is somewhere none of this covers, and finding it is
the row.**

## Your first deliverable: which link is actually broken

Import `Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv` and inspect, **in this order**, stopping
at the first failure:

1. Does the parsed candidate carry `station`?
2. Does the committed `FillUp` carry a `stationId`?
3. Does a `Station` row with that id exist **after** the commit?
4. Does the Log row **ask** for it - and does [RV.142]'s title rule prefer it over the fuel kind?

**Report the answer to all four before changing anything.** The candidates, in order of cheapness:
the Log row's title function does not prefer the station for imported rows; the resolver matched an
existing station whose name renders differently; the header did not match in the owner's **real**
file (a different Drivvo locale or export version than the fixture); or the rows the owner sees were
imported **before** [RV.142] shipped.

**If every link holds against the fixture**, the fixture is not reproducing the owner's case: say so
plainly and say what would be needed (most likely their actual export file). **Do not invent a fix
for a break you could not observe.**

## Then, and only then, fix the link that is broken

**Do not add a second station-creation path.** The resolver is shared with [RV.156]'s
`createStation` and [RV.161]'s scanned name, so a typed, scanned and imported name converge on one
id. A second minting rule manufactures exactly the duplicates [RV.115] exists to clean up.

## Explicitly out of scope

- [RV.115]'s normalisation and merging.
- [RV.185]/[RV.187]'s import work (a separate dispatch, same parser - **re-read the file before
  editing**, it may have landed first).
- [RV.170], the station-minting guard: it is **sequenced after this row**, because it needs the seam
  this row settles.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` → **Station**, and **Import mapping (launch importers)** - what the parse knows.
2. `docs/API.md` → the `/import/parse` candidate shape.
3. `docs/ERRORS.md` → the Log-row and import rows.
4. `CLAUDE.md` hard rules 12, 13.

## Environment axes this crosses

**Locale** - the owner's file is Russian; the header map has `Азс`, and a different export locale is
one of the candidates, so **say which header your fixture actually carries**. No new copy expected.
**Screenshots**: only if a user-visible surface changes; a Log row showing a station name would be
worth EN and RU, **with capture lines added** ([RV.176]).

## If this adds a failure path, what makes it visible in production?

A station that silently fails to resolve is exactly what produced this report. If your fix has a
branch where the name is dropped, add the shape-only event that answers *"did the import resolve a
station?"* - **counts only**: hard rule 12 makes a station **name** a domain value that is never
logged, at any level, in any build.

## Tests you must add

- **L1, and it should FAIL TODAY once you know which link breaks**: after committing the fixture,
  every imported fill's `stationId` resolves to a **live Station row**. This is the assertion that
  would have settled the wrong diagnosis in one run - write it regardless of where the break turns
  out to be.
- **L4**: an imported fill-up shows **`Газпром`** in the Log, not `92` - [RV.142]'s promise, and the
  owner's actual complaint.
- **L1**: two rows naming one station produce **ONE** Station, not two.
- **L1**: a row with an empty station column stamps no id and writes no Station.

Report each suite's observed, **non-zero** count, and **filter by suite name, not the file's** - on
2026-09-10 a class-name filter matched nothing and printed `TEST SUCCEEDED` on zero tests.

## The mutation you must run - I am naming it, do not choose your own

**Once you have found and fixed the broken link, break that same link again** and show the L4 goes
red naming the fuel kind where the station belongs. Then restore and re-run. Report both outputs
verbatim, **and name which link you broke** - that sentence is the row's finding.

## Vacuous traps, named

- **Fixing a link without first showing which one is broken** - the orchestrator already did that
  once here and was wrong.
- Asserting `stationId` is non-nil: it already is, on the broken code.
- A second minting rule beside `ImportStationResolver`.
- Testing with a hand-written fixture instead of the owner's file, which is the only artefact known
  to reproduce it.
- Concluding "works on my machine" without saying what would reproduce it.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Standing checks

As left, `main` is **1864 tests / 222 suites**, **829** localization keys at 100% RU, backend **451**.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count.
4. `cd backend && dotnet build`, `dotnet test`, **`dotnet format --verify-no-changes`** - only if you
   touch the parser; all three, and the format check is the half that gets forgotten.
5. **`xcodebuild ... build` for the app target** ([RV.174]).
6. `xcodegen generate`, then each UI suite touched **by suite name**, non-zero count.
7. Localization gate - exit 0; report keys and RU percentage.

Verify by **exit code** (`echo $?`).

## Report back

**The four-step trace and its answers, first** - that is the deliverable even if no fix follows.
Then: every check with the **exit code observed** and the counts; run or only written; **the
mutation's red-then-green output and which link you broke**; whether the fixture reproduced the
owner's case at all; and **anything you found and did not fix**.
