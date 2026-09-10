# RV.116 - an import must say what it is NOT bringing in

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

**This row spans BOTH tiers** - the C# backend and the iOS client. Budget for both; the backend half
is where the data lives and the client half is only rendering.

## The defect

Product owner, 2026-09-07: *"worth to say for this program, what data we don't support (as a
notification), such as driver and other fields"*.

**Measured on the Drivvo export**: of 29 refuelling columns, Tankbook has no home for `Водитель`
(driver - the fleet feature that is Drivvo's whole positioning), `Метод оплаты` (payment method),
`Тип расхода`, `Скидка` (discount), the second- and third-fuel blocks, and the EV columns when the
row is a liquid fill. The `##Service` and `##Expense` sections carry `Заголовок` and
`Название сервиса` with no destination either. MFM has the same shape with different names.

**The parser reads what it understands and the rest evaporates, silently.** A fleet user importing a
driver-per-row history discovers only later that the column they cared about is gone.

**This is NOT hard rule 8.** Nothing is deleted - the source file is untouched and the rows the app
keeps are complete. That is exactly why it needs its own rule: it is a **completeness promise**, and
an import that quietly narrows the data is a migration a user cannot trust.

## The contract split - the row's wording could mislead you, so read this

The row says *"each `format` in `GET /import/formats` declares its unsupported fields"*. That is
half of it, and the other half **cannot** live there:

| What | Where | Why |
|---|---|---|
| the unsupported column **names**, per format | `GET /import/formats` | static per parser, ETag'd reference data, **data not code** |
| **how many rows carried a value** in each | `POST /import/parse` response | per *file*; the server cannot know it until it reads the user's CSV |

A count in `/import/formats` is impossible; copy hardcoded in the client is the thing that rots. Get
this split right and the rest is mechanical.

**Both endpoints are already the licensed hard-rule-9 exception** (`CLAUDE.md` rule 9, amended
2026-08-27): `/import/parse` is the one endpoint that reads what a field means. Counting non-empty
cells in a column you are already parsing is **inside** that exception. Do not let it spread further.

## Where things are, confirmed on the tree

- `backend/src/Tankbook.Api/Import/ImportFormats.cs` - `ImportFormatInfo(Id, DisplayName, FileKinds,
  HelpUrl, AddedInPackVersion)` and the static registry with `mfm` and `drivvo`.
- `backend/src/Tankbook.Api/Import/ImportModels.cs:102` - `ImportParseResponse`.
- `backend/src/Tankbook.Api/Import/ImportService.cs:215` - `BuildResponse`.
- `backend/src/Tankbook.Api/Import/DrivvoParser.cs`, and the MFM parser beside it.
- `ios/Sources/TankbookCore/Import/ImportModels.swift:12` - the client `ImportFormat`, which mirrors
  the wire record field for field.
- `docs/API.md:409` - the `/import/formats` contract; `docs/API.md:430` - the parse response shape.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. **Verify the parsers actually discard these columns
silently** before you build the notice - if any already surfaces something, say so and build on it.

## What to build

**Say what is not coming in, BEFORE the commit, at the review gate** - the F6a moment where the user
has written nothing yet. Name the unsupported columns **and how many rows carried a value in each**,
so the number tells the user whether it matters to them:

> "Driver, payment method and discount are not imported (250 rows carry a driver)."

**Say it once, calmly.** A notice at the gate, never a blocking dialog and never an error. Continue
is never disabled by it. Hard rule 7 still applies: it names what to do instead, which is *the file
stays on your phone if you need those columns*.

**Decide whether a column that is empty in every row is mentioned at all.** My preference is **no** -
a notice about nothing is noise, and listing every unsupported column buries the one that matters.
**Whichever you choose, assert the decision** and write it in `docs/API.md`.

**`docs/API.md` changes here, and `CLAUDE.md` calls that a breaking-change review.** Both endpoints
gain a field. State in your report whether an **older client** ignoring the new fields still works
(it must) and whether an **older server** omitting them leaves the client sane (it must - no notice,
not a crash).

## Explicitly out of scope

- New importers. `mfm` and `drivvo` are the two that exist.
- The parsers' mapping decisions - which columns are supported is settled; you are declaring the
  complement, not changing it.
- [PJ.9] (the review row cannot change what a row became) and [RV.113]. Cite if you touch their area.

## Docs to read before writing (in order)

1. `docs/API.md` -> **Import parsing**, both endpoints. **The authority for the wire contract**; you
   are extending it, in the same change.
2. `docs/SCHEMA.md` -> **Import mapping (launch importers)** - the column tables that say what IS
   supported. The unsupported list is its complement; derive it there rather than inventing a list.
3. `docs/ERRORS.md` -> **Import**, the review gate's existing copy - the notice must sit beside it
   without becoming an error.
4. `CLAUDE.md` hard rules 7, 9 (the import exception and its five bounding properties), 10, 12.

## Environment axes this crosses

**Locale** - the notice is user-facing copy, EN and RU, gate at 100%. RU is where a comma-separated
column list plus a count runs longest. **Offline** is unchanged (parsing already needs the network -
rule 1's bounded exception). **Screenshots: EN and RU of the review gate carrying the notice.**
Backend changes need `dotnet build` **and** `dotnet format --verify-no-changes`.

## If this adds a failure path, what makes it visible in production?

The parse already logs shape only - format name, row counts, error counts (hard rule 9's *"nothing
is logged but shape"*). **A column name is shape; a cell's value is not.** If you log the
unsupported-column counts, log the **count and the column name**, never a driver's name or any cell
content (hard rule 12). Say what you added.

## Tests you must add

- **L1 (backend), and it FAILS TODAY**: the parse result declares the unsupported columns for its
  format **with the count of rows carrying a value in each**. **Oracle**: a fixture CSV you control -
  N rows with a driver, M without - so the expected count is arithmetic, not a guess.
- **L1 (backend)**: a column empty in **every** row follows your decision - asserted either way.
- **L1 (backend)**: `GET /import/formats` declares the column names per format, and the two formats
  declare **different** lists (they have different column names - a shared list would be the bug).
- **L4 (iOS)**: the review gate shows the notice **with the counts**, and **Continue is never
  blocked** - assert the button is enabled with the notice present.
- **L1 (iOS)**: the client renders whatever the server declared - feed it a format with an
  unsupported list the app has never heard of and it still renders. This is the anti-hardcoding
  assertion.

Report the observed, **non-zero** count for every suite, and **run any app-target iOS suite
separately** - a combined `xcodebuild` invocation silently dropped a `TankbookTests` filter on
2026-09-10 ([PJ.56]).

## The mutation you must run - I am naming it, do not choose your own

**Return the unsupported-column list with all counts forced to zero** (leave the names). The L4 test
**must go red on the COUNT**, not on the notice's presence. Then restore and re-run. Report both
outputs verbatim.

That is the mutation because the count is the whole value of the notice: *"driver is not imported"*
is trivia, *"250 rows carry a driver"* is a decision. A test that passes on a notice with no numbers
is testing the sentence, not the feature.

## Vacuous traps, named

- **Hardcoding the copy in the client per format** - the thing that rots, and the row names it first.
- **Listing every unsupported column including the empty ones**, which buries the one that matters.
- **Asserting the notice exists without asserting the count** - the count is what makes it
  actionable.
- Blocking or disabling Continue on it.
- Putting the counts in `/import/formats`, which cannot know them.
- A single shared unsupported list for both formats - their columns differ.

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

Re-measure the baseline yourself and report what you observe. As left, `main` is **1857 tests / 219
suites**, **826** localization keys at 100% RU, backend **445** tests.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. **`cd backend && dotnet build`** and **`dotnet test`** - exit 0, report the count.
5. **`cd backend && dotnet format --verify-no-changes`** - exit 0. This is half the backend gate and
   is the one that gets forgotten.
6. **`xcodebuild ... build` for the app target.** `swift build` compiles only the SwiftPM package;
   anything under `ios/App/Sources` is invisible to it ([RV.174], 2026-09-10).
7. `xcodegen generate`, then the UI suite you touched by name with an observed, **non-zero** count.
8. Localization gate - exit 0; report keys and RU percentage.
9. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; your decision on
all-empty columns and where you wrote it down; **the old-client / old-server compatibility answer**;
what you added for observability; and **anything you found and did not fix**.
