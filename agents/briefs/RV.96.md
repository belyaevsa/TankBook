# RV.96 - "Replacement parts" is 107 of 260 cost rows and lands as a plain expense

## The defect, and the decision it needs

`MapCostsRow` (`backend/src/Tankbook.Api/Import/MfmParser.cs:400-451`) maps the owner's finance
categories like this today:

| MFM category | Today | Rows in the owner's file |
|---|---|---|
| `WORK` | ServiceRecord, `repair` | |
| `Diagnostic` | ServiceRecord, `inspection` | |
| `Oil` | ServiceRecord, `oil` | |
| `Washing` | ServiceRecord, `wash` | |
| **`Replacement parts`** | **Expense, `parts`** | **107 of 260 - the second-largest category** |
| `Parking` | Expense, `parking` | |
| anything else | `RowParseException(ReasonUnknownFinanceCategory)` -> the review list | |

The notes on those 107 rows are unmistakably **parts fitted to the car** - «Замена колес зима ->
лето», `AdBlue 5 литров`, `Топливный фильтр VAG 8t0127401A`. As an Expense they carry money and no
service meaning: they cannot feed the parts shelf, a reminder's completion, or "what did this car
cost me in parts".

## The decision is MADE - implement it, do not re-open it

**`Replacement parts` maps to a ServiceRecord with `ServiceCategory.parts`.** The schema already has
the case - `ServiceCategory.parts` (`ios/Sources/TankbookCore/Domain/Enums.swift:82`), beside `oil`,
`brakes`, `tires`, `filters`, `inspection`, `repair`, `wash` - so this is filling in a mapping the
domain already models, not inventing a shape. `ServiceRecordCandidate` (`MfmParser.cs:453+`) already
puts the note in the item's `title` and the money in both `money` and the item's `cost`; the mapping
is a one-line change plus its test.

**`Parking` stays an Expense with `parking`.** It is money not tied to work on the car - that is
exactly what `Expense` is for, and the current mapping is right.

**Do NOT fabricate parts-shelf rows.** `ServiceRecord.usedParts` is `[UUID]`
(`ios/Sources/TankbookCore/Domain/Entities.swift:269`) - it references real `Part` entities. Turning
`Топливный фильтр VAG 8t0127401A` into a structured part with a number and a quantity is **parsing
free text into entities**, which is a different row and a different decision. The note survives as
the service item's title, which is what makes the history searchable and correctable; that is the
scope here.

**And the category must stay editable on the review row** (hard rule 13 - the app suggests, the user
decides). The owner's own file has a **fuel filter filed under `Parking`**, which is the proof that
no mapping table can be right about every row. Verify the review row lets the user change what a row
became, and **if it does not, say so as a finding** - do not build a new editor inside this row
without saying you did.

**The unknown-category behaviour is correct and must survive.** An unrecognised category throws
`ReasonUnknownFinanceCategory` and lands on the review list rather than being silently retyped
(hard rule 8). Do not "improve" this into a guess.

## Explicitly out of scope

- `RV.93` (taking the whole export in one pass). Different row, different files.
- Parsing part numbers, quantities or units out of the note.
- Adding categories to `ServiceCategory` or `ExpenseCategory` - the cases needed already exist.
- Re-typing a row by reading its note ("this says filter, so file it as filters"). The owner's
  mis-filed fuel filter is the reason: content-sniffing would overwrite a value the user can see and
  fix, and hard rule 13 makes that the user's call.

## Tests

This row is **backend-first**: `cd backend && dotnet build && dotnet test`, and report the count
before -> after (it was 407). If the client half needs nothing, say so rather than inventing a change.

- **L1**: a `Replacement parts` row maps to a **ServiceRecord with category `parts`**, and **its note
  survives** in the item title.
- **L1**: the `Parking`-filed fuel filter still lands as **parking** and editable - asserted as "not
  re-typed by content", which is the claim.
- **L1**: an unknown category **still reaches the review list** (the `RowParseException` path).
- **L1**: the money is unchanged by the remap - same amount, same currency, both on the record and
  on the item.

### Vacuous traps, named

- **Asserting the mapping table without asserting the note survives.** The note is the entire value
  of these 107 rows.
- **Testing only the categories that already map** (`WORK`, `Oil`) - they pass today.
- **Asserting a category COUNT** rather than what a row **becomes**.
- Asserting the row is "a service record" without asserting its **category** is `parts` - `repair`
  would pass that.
- A fixture with one costs row, where "107 of 260" cannot be observed at all. Use the committed
  `Spike/ImportFixtures/mfm/` costs fixture if there is one; if there is not, say so and add one from
  the owner's shapes (categories and notes only - it is already a committed fixture family).

### Mutations (run each, report, restore byte-for-byte)

1. Map `Replacement parts` back to `ExpenseCandidate` -> the mapping test must fail.
2. Drop the note when building the service item -> the note test must fail.
3. Make the unknown category fall through to a default expense instead of throwing -> the review-list
   test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Docs to reconcile

`docs/SCHEMA.md` (the MFM import mapping table - it is the authority for import mappings and must
name where `Replacement parts` goes and why), `docs/API.md` only if the parse response shape changes
(it should not).

## Hard rules that decide things in this area

**8** (an unknown category lands on the review list, never silently retyped) · **9** (the import
parse is the narrowest exception - it interprets a foreign file and commits nothing; do not add
domain reasoning anywhere else in the backend) · **12** (nothing but shape is logged - format name,
row counts, error counts; never a note, an amount or a category value) · **13** (the mapping is a
default input the user edits) · **14** (it builds and it lints - for this row that is
`dotnet build` + `dotnet format --verify-no-changes`).

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
