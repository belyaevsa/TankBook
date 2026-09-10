# RV.196 - the writer guard is entity-level, and the field-level instances are live

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

## The defect

[RV.163]'s `EntityWriterScanner` proves every `###` entity in `docs/SCHEMA.md` has a production
writer. **[PJ.55] is the instance it could not see**: `Station` HAD a writer while
`Station.favorite` had none - a column, a decoder, ten test seeds, a reader in the ranking ladder
(*"a favourite within 300 m is proposed first"*), and **nothing anywhere that could set it**. Rung
one of the ranking could never fire, and the ranking silently degraded for every user. Three
features shipped onto that flag.

RV.163's row states this blind spot in its own text. **A scan on 2026-09-10 found live instances**,
so this is not a hypothetical widening:

| Field | What exists | What is missing |
|---|---|---|
| `Settings.anomalies` | column, decoder (`Records+Extras.swift:247`) | any surface that sets it |
| `Settings.eagerMediaOnWiFi` | column, decoder (`Records+Extras.swift:249`) | any surface that sets it |
| `Station.brand` | decoder, and a READER in `StationSettingsView.swift:61` | written only as `nil` by `ImportStation.swift:42` |

**Confirm each of these yourself before building anything** - the orchestrator's scan was crude and
three of its diagnoses have been wrong this week. If one of them turns out to have a writer, say so
and use it as a calibration case instead.

## What to build

Extend the scanner from entities to their **fields**: for each field `docs/SCHEMA.md` names, is
there a production path that gives it a non-default value?

**The hard half is the initializer**, and it is why a naive `grep "\.field ="` scan is useless: the
normal construction path passes the value as a memberwise-init **argument**, not an assignment. A
field is written when either
- it is assigned outside its own type's declaration, **or**
- it is passed as an init argument whose value is **not** a literal default (`nil`, `false`, `[]`,
  `0`, or the same default the declaration carries).

Reuse what already works in `EntityWriterScanner`: a **pure function over source text**, masking
comments, strings and `#if DEBUG` regions before it looks; and the **reasoned-exception list**,
where a bare entry fails the guard's own self-check exactly as it does at entity level.

## This brief's reading is a hypothesis - confirm it before you change anything

Beyond re-checking the three fields above: **decide what the scanner's unit of truth is.** SCHEMA.md
names fields in prose and tables, not in a fixed grammar, so extracting "the fields of entity X" may
be the hardest part of the row. If SCHEMA.md's shape will not support it reliably, **say so and
propose reading the field list from the Swift type instead** - and say what that trades away
(a field the docs promise but the type lacks would then be invisible). Record the shape you chose
and why.

## Explicitly out of scope

- **Fixing the fields this reports.** Each one is a DECISION for the product owner - give it a
  writer, or record why it has none - exactly as `PJ.55` was. Report them; do not build UI.
- `ChargeSession`'s fields. It is already a documented, reasoned exception at entity level (see
  `SchemaEntityWriterGuardTests.swift:144`) because the EV entry path is `[v1.x]` and unbuilt, so
  every field inside it inherits that reason. **Do not re-report them one by one.**
- `RV.115`/`RV.180` (station brand normalisation) - `Station.brand`'s missing writer is theirs to
  answer, not this row's.

## Docs to read before writing (in order)

1. `ios/Tests/TankbookCoreTests/SchemaEntityWriterGuardTests.swift` **end to end** - especially the
   three exclusions and `reasonProblem`. You are extending this idea, not replacing it.
2. `docs/SCHEMA.md` - the authority on which fields exist and what each means.
3. `docs/DEFECT-PATTERNS.md` -> Part 2, the product-reachability shapes.
4. `docs/TESTING.md` - where a guard is declared. Extend it to name this one.

## Environment axes this crosses

**None at runtime** - this is a test-target source scan; no shipping code path differs. Say so.
**No screenshots** (a scanner is not a screen), and say that rather than shipping one.

## If this adds a failure path, what makes it visible in production?

None - it runs in CI and on a developer's machine, never in the app. Say so.

## Tests you must add

- **L1 that FAILS TODAY on a real field**: `Settings.anomalies` is reported as having no production
  writer, before any exception list is written. Report the full list the scanner produces.
- **The calibration, and it is the important one**: `Station.favorite` is **NOT** reported, because
  [PJ.55] gave it a writer in `StationSettingsView`. A guard that flags the field PJ.55 fixed is
  tuned wrong, and that pair - one live miss, one live hit - is what proves it discriminates.
- **L1**: a field written only from a `TestSeed` or inside `#if DEBUG` is still reported. **The
  decoder is not a writer either** - it restores what was stored, and it is the exact shape that hid
  PJ.55.
- **L1**: an exception with a blank reason fails the guard's own self-check.

Each expectation names its ORACLE - which line you read to know the field is or is not written.
Report each suite's observed, **non-zero** count, filtered **by suite name, not the file's**.

## The mutation you must run - I am naming it, do not choose your own

**Delete `Station.favorite`'s production writer** in `StationSettingsView` (the toggle's assignment)
and show the guard goes red naming `Station.favorite` - reconstructing PJ.55's exact state. Then
restore it byte-identical and re-run. Report both outputs verbatim.

That is the mutation because it recreates the defect as it actually occurred, rather than a
synthetic one.

## Vacuous traps, named

- **Counting the persistence decoder as a writer.** It reads a stored row back; it cannot originate
  a value. This is the single trap that would make the whole row worthless, because it is exactly
  what hid `PJ.55`.
- Counting a literal default in an init (`favorite: false`) as a write.
- **Allowlisting every finding until the guard is green** - that converts a defect list into a
  config file. An exception needs a reason a human wrote, and the row expects the list to be SHORT.
- A guard that reports so many fields nobody reads it. If the list is long, say so and propose a
  narrowing (booleans and ids first, say) rather than shipping noise.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

As left, `main` is **1879 tests / 225 suites**, **831** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count.
4. **`xcodebuild ... build` for the app target** ([RV.174]).

Verify by **exit code** (`echo $?`).

## Report back

Every check with the **exit code observed** and the counts; **the full list of fields the scanner
reports**, which are real and which you excluded with what reason; **the mutation's red-then-green
output verbatim**; the shape you chose for reading the field list and why; and **anything you found
and did not fix**.
