# RV.170 - a second station-minting path, and a copy helper that drops a field

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**This row was deliberately held back until its seam was settled.** `RV.189` shipped tonight and did
two things for it: it settled the import station path, and it **filed the live failing case** this
guard needs. A guard built against a hypothetical is the one thing this queue's sequencing rule
forbids; this one has a case with a commit hash.

## Half A - the row as filed: a second station-minting path

`Station` minting is `RV.156`'s shape from the other side. `upsertStation` had zero non-seed callers
for months and three features were built on an entity nothing created; `RV.150` then made a save
stamp `lastUsedAt` and `defaults` on it. **So there is now a stamping seam, and a second creation
path that skipped it would produce stations the ranking cannot rank** - the same silent hole,
freshly dug.

**Establish what the canonical seam IS before writing anything.** The orchestrator's grep found
production constructions at `Records+Extras.swift:73` (the persistence decoder), and creation at
`Repository+StationCreate.swift:30` (`createStation`) - plus the import resolver in
`ImportStation.swift`. **That looks like TWO creation paths.** If it is, **the row is to decide
which is canonical and record the decision** - the guard comes second. Say what you found; do not
assume the orchestrator's grep was complete.

**The decoder is not a creation path** and must not be flagged: it restores what was already stored,
the same discrimination `RV.196`'s field guard had to make.

## Half B - the case `RV.189` filed, and it may be a SECOND guard

`RV.189` (`e7a7a6c`): the product owner's imported fills showed `92` instead of the station the file
named. Every documented link held - the parser read the column, the wire carried it, the conversion
stamped it, the commit materialised the row. **The value was dropped between them**, in
`ImportBatchMerge.remappingSourceRow`, a copy helper that rebuilt the `ImportCandidate` without
`station`.

**The reason a compiler could not catch it**: `ImportCandidate.init` **defaults `station` to nil**
(`ImportModels.swift:146`), so omitting it is legal. The four sibling helpers happen to pass it; the
fifth did not, and nothing failed.

**Decide whether this is the same guard or a second one, and say which.** They share a theme - a
value that silently goes missing - but Half A scans for a CONSTRUCTION outside a seam and Half B
scans for a FIELD dropped by a copy. **Two guards with two names is a perfectly good answer**, and
better than one guard bent to cover both. Whatever you choose, say why.

A shape worth considering for Half B: a copy helper on `ImportCandidate` must round-trip **every**
field. That is checkable by comparing the init's parameter list against what each helper passes -
and it generalises beyond `station`, which is the point, because `station` was only the field that
happened to break.

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one - and
on `RV.189` the wrong one was about this very area. Re-run both greps yourself and report what they
actually return.

## Build on what exists

`RV.162`, `RV.163` and `RV.196` are three shipped source-scan guards with the same anatomy: a **pure
function over source text**, masking comments, strings and `#if DEBUG` before it looks, plus a
**reasoned exception list** where a blank reason and a stale unused entry both fail the guard's own
self-check. **Reuse that anatomy.** Read `SchemaFieldWriterGuardTests` first - it is the newest and
closest.

## Explicitly out of scope

- `RV.115`/`RV.180` (station brand normalisation).
- `RV.171` (the receipt-persistence guard) - sequenced after `RV.173` for the same reason this row
  was sequenced after `RV.189`.
- Fixing anything the guard reports beyond what `RV.189` already fixed. A finding is a row, not a
  side effect.

## Docs to read before writing (in order)

1. `ios/Tests/TankbookCoreTests/SchemaFieldWriterGuardTests.swift` and its scanner - the pattern.
2. `docs/SCHEMA.md` -> **Station**, and `docs/JOURNEYS.md` -> J4's ranking ladder, which is what a
   badly-minted station breaks.
3. `docs/DEFECT-PATTERNS.md` -> Part 2.
4. `docs/TESTING.md` - where a guard is declared. **Extend it to name this one.**

## Environment axes this crosses

**None at runtime** - a test-target source scan; no shipping code path differs. Say so. **No
screenshots** (a scanner is not a screen), and say that rather than shipping one.

## If this adds a failure path, what makes it visible in production?

None - it runs in CI and on a developer's machine, never in the app. Say so.

## Tests you must add

- **Half A, L1**: a fixture minting a `Station` outside the canonical seam is flagged, with
  `file:line`.
- **Half A, L1, the calibration**: the seam itself, the decoder and the import resolver are **not**
  flagged. A guard that flags the legitimate paths is tuned wrong, and that pair is what proves it
  discriminates.
- **Half B, L1, and it FAILS on the pre-`RV.189` source**: a copy helper that omits `station` is
  reported. Prove it against the real defect, not a synthetic one - `git show e7a7a6c^:ios/Sources/TankbookCore/Import/ImportBatchMerge.swift`
  is the file as it was broken, and running your scanner over that text is the strongest evidence
  available.
- **Half B, L1**: today's four sibling helpers are **not** reported.
- **L1**: an exception with a blank reason fails the guard's own self-check.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count, filtered
**by suite name, not the file's**.

## The mutation you must run - I am naming it, do not choose your own

**Re-break `RV.189`**: remove `station: station` from `ImportBatchMerge.remappingSourceRow` and show
your Half-B guard reports it. Then restore byte-identical and re-run. Report both outputs verbatim.

That is the mutation because it recreates a defect that actually shipped and cost the product owner
a report, rather than one invented to be caught.

## Vacuous traps, named

- **Flagging test seeds**, which teaches everyone to allowlist and turns the exception list into a
  skip list.
- **Writing the guard before deciding which path is canonical** - the row says this in its own text.
- Counting the persistence decoder as a creation path.
- A Half-B guard that hardcodes `station` - then the next field to go missing walks past it.
- An exception list longer than a handful. If it is long, the guard is mis-tuned; say so.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08. **Reading a
historical file with `git show <sha>:<path>` is fine and is what the Half-B test wants** - that
writes nothing.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## Concurrent work in this checkout, 2026-09-10

Another `opencode` run has been growing the receipts corpus since 19:57 and holds uncommitted
changes in `Spike/ReceiptSpike/fixtures/`, `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` and
`ios/Tests/TankbookCoreTests/Corpus*`. **Do not touch, revert or `git checkout` any of them.** If
`swift test` shows a corpus failure, say so and say it is not yours - do not "fix" it.

## Standing checks

As left, `main` is **1911 tests / 230 suites**, **835** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone** - on 2026-09-10 four
   `SyncWriteTriggerTests` failed purely from contention with a parallel build.
4. **`xcodebuild ... build` for the app target** ([RV.174]).

Verify by **exit code** (`echo $?`).

## Report back

**What the greps actually returned** and which path you made canonical; **whether Half A and Half B
are one guard or two, and why**; every check with its **exit code observed** and counts; **the
mutation's red-then-green output verbatim**; whether your Half-B scanner catches the pre-`RV.189`
source; the full list of anything either guard reports; and **anything you found and did not fix**.
