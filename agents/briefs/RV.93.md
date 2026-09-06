# RV.93 - take the whole My Fuel Manager export in one pass

## The defect

The owner's real export is **six files**: `fuel.csv` (513 rows), **`costs.csv` (260 rows)**,
`vehicles.csv` (5 cars), `trips.csv` (19), `incomes.csv` (1), `reminders.csv` (1). The parser already
handles fuel, costs, vehicles, incomes and reminders as separate `fileKind`s
(`backend/src/Tankbook.Api/Import/MfmParser.cs:130-140`, `KindByTitle` / `ColumnsByKind`), and the
wizard takes **one file per run**: `ImportWizardView.swift:60-62` and `:392-394` both open
`.fileImporter(... allowsMultipleSelection: false)` and use `urls.first`.

So a user importing their history runs the wizard **once per file** and, since [RV.86], **maps the
same five cars again on every run**. Get the mapping wrong on the second pass and the costs land on
a different car than the fuel. **And the odometer continuity that makes consumption work spans both
files**: a service at 106 722 km and a fill at 106 900 km are one timeline, so importing them
separately validates the second file against a car whose history it cannot see yet.

## The shape is DECIDED - build this one, do not re-open it

**Multi-select the files in the existing picker.** `allowsMultipleSelection: true`, and take every
URL rather than `urls.first`. Not a folder, not the ZIP:

- `fileImporter` already supports it behind one flag, and `ImportPickedFileStager` (RV.73) already
  stages a URL under its security scope - it just has to run per URL, in a loop.
- A folder picker is a different security-scope dance for no gain, and MFM's ZIP layout is not
  verified anywhere in this repo - building against an unverified container is how a brief invents a
  format.
- **One file must keep working exactly as it does today** (the row says so explicitly): a
  single-file pick is the same flow, with the same steps and no new questions.

**The server stays a per-file pure function. Do NOT add an endpoint that takes several files.**
`POST /import/parse` is hard rule 9's narrowest possible exception, and its bounding property is that
it parses one file and commits nothing. N files means **N calls to the existing endpoint** and the
grouping happens **on the device**. A multi-file server endpoint would widen the exception, which
needs its own product-owner decision and does not have one. If you find yourself editing
`backend/`, stop - that is the signal you have left this brief.

## What to build

1. **Pick and parse N files**, each through the existing `/import/parse` call, staging each URL under
   its own scope. A file that fails to parse must not kill the others: report it per file and let the
   user continue with the rest (hard rule 7 - the next step exists and the run survives).
2. **Ask the car mapping ONCE for the whole export.** The `Vehicle name` column is identical across
   every file - verified in [RV.86], do not re-verify it - so one mapping answers for all of them.
   The `.cars` step (`ImportFlowModel+Cars.swift`, `ImportCarsView`) already exists and already maps
   source names to destinations; it must now see the **union of names across every picked file**,
   not one file's names.
3. **Order the writes by what depends on what**: `vehicles.csv` creates or matches the cars first,
   then `fuel.csv` and `costs.csv` land against them, so the odometer validation sees **one
   timeline** per car. Entries from different files for the same car must interleave by date, using
   the ordering `EntryOrder` already defines (RV.87 - do not write a second comparator).
4. **It stays ONE write.** `confirmImport` -> `repository.commitImport` is the flow's single write
   (`ImportFlowModel.swift:6-11` says so); several files must not become several commits, or a
   half-imported export becomes a state nothing can undo (F6a: nothing is written until the user
   confirms).
5. **Say in the review what came from where** to the extent the existing review row allows - a user
   who picked six files needs to know the 260 cost rows are in there. Do not redesign the review
   list; if the honest answer is "the count is enough", say so.

## Explicitly out of scope

- `trips.csv` and any new `fileKind`. The parser's existing kinds are the scope.
- `RV.96` (where "Replacement parts" belongs). It lands in `MapCostsRow`; this row does not touch
  the mapping table.
- Any backend change at all.
- Making multi-file mandatory, or removing the single-file path.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L1**: the union-of-names grouping over several parsed files yields **one** mapping question per
  distinct source car, not one per file.
- **L1 (the row's real point)**: fuel and costs rows for one car **interleave into a single
  timeline**, and a service between two fills **does not flag either**. Build the fixture from the
  committed `Spike/ImportFixtures/mfm/` files - `fuel.csv` is already there; add or reuse the costs
  fixture rather than inventing numbers.
- **L1**: the write order is vehicles -> entries, asserted by the commit's effect (the entries land
  on the mapped cars), not by spying on call order.
- **L4 `ImportUITests`**: choosing two files maps the cars **once** and lands **both kinds**.
- Suites: `ImportUITests`. Report the observed count - a filter matching nothing prints "0 tests ...
  passed".

### Vacuous traps, named

- **Asserting each file parses.** They already do - that is not this row.
- **Testing two files that share no car**, where the ordering and the single-mapping claim can never
  fail.
- **Asserting a count of records** rather than the merged per-car **odometer order** - the count is
  the same whether the timeline is right or wrong.
- Asserting the picker's flag changed rather than that two picked files produce one mapping step.
- A fixture where every row has no odometer, which is where the continuity claim lives.

### Mutations (run each, report, restore byte-for-byte)

1. Ask the mapping per file instead of once -> the single-mapping test must fail.
2. Write entries before vehicles -> the timeline/mapping test must fail.
3. Sort the merged entries by file, then date, instead of by date across files -> the interleave test
   must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Docs to reconcile

`docs/API.md` if anything about `/import/parse`'s use changes (it should NOT - say so if it did not),
`docs/JOURNEYS.md` F6 (the import journey now takes an export, not a file), `docs/ERRORS.md` (what a
per-file failure says and its next step), `docs/SCREENMAP.md` if the wizard's steps change.

## Hard rules that decide things in this area

**1** (local-first: the parse is the ONE network exception and everything else - review, edit, commit
- is local) · **7** (a file that fails names its next step and the run survives) · **8** (nothing
lost silently - one commit, never a half-import) · **9** (the server stays a per-file pure function;
this exception does not spread) · **10** (EN + RU, full localised phrases) · **13** (the mapping is
the user's decision, editable) · **14** (it builds and it lints before anything else counts).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`,
`backend/src/**`, `backend/tests/**`, `Spike/ImportFixtures/**`, `design/screens/**`,
`design/screenshots/**`, and the docs named in this brief. **If your row's "out of scope" says not to
touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above and is confirmed - do not spend the run re-deriving it. Where this brief leaves a
genuinely open choice, **take the smallest correct option and keep going**, then say in the report
which you took and what you rejected. Do not stop and wait on it. (`RV.74`'s first dispatch ran two
hours and wrote nothing, stuck on a question its brief left open.)

If a fence in this brief turns out to be wrong, **report it as a Residual rather than obeying
quietly** - a fence can be wrong the same way a diagnosis can. Two of my diagnoses have been wrong
this month and the agent was right both times.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported (before -> after). Never subset it.
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- `swift run --package-path ios localization-gate` from the root -> 0.
- **If you touched `backend/`**: `cd backend && dotnet build` -> 0 and `dotnet test` -> 0 (count
  before -> after), plus `dotnet format --verify-no-changes` -> 0.
- **If you touched `ios/App/`**: `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  `swift build` does NOT compile `ios/App`; only `xcodebuild` does. Run `xcodegen generate` first if
  you added a file. **Check the observed count is non-zero.** Do NOT run the whole UI suite - that
  belongs to phase completion (2026-08-29 rule).
- **`$?` after a pipe is the pipe's exit code.** `dotnet test | tail` once reported 0 while the run
  aborted and "66 passed" of ~396 nearly read as green. Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.
- **Simulator contention produces false reds** with a *different* failing set each run, and a suite
  reporting "Executed 0 tests" beside its failures is kills, not assertions. Shut the simulators down
  and re-run once on a quiet machine before believing a red.

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. Each mutation: what you broke, which named test failed, and that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on. Four passed on 2026-09-06
   and each meant the test did not cover the claim its row was written for.
3. Screenshot paths and md5s, if this brief asked for screenshots.
4. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
5. Anything in this brief that was wrong, as a Residual.
6. Whether the tests were actually **run**, not only written.
