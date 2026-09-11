# RV.171 - a second receipt-persistence path could be written and nothing would fail

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Scenario: `no-scenario: a source-scan guard over the receipt-persistence seam`.**

**This row was held back until its seam was settled.** [RV.173] ships first and decides what a
grouped save does with its attachment ids when the photo write fails; **this guard is written
against that settled seam, never against a hypothetical.** That sequencing has now worked three
times - `RV.163` after `PJ.55`, `RV.170` after `RV.189` - and each mutation reconstructed the
original defect exactly.

## The defect this guards

Named by the [RV.167] agent. It is the shape that produced **[PJ.28]** and **[RV.149]** and
**[RV.173]**: a scanned save threw its photograph away on one surface while another kept it, because
the binding of an entry to its **attachment**, its **provenance** and its **`purchaseGroupId`** is a
convention rather than a checked one.

Three rows in the same family is the argument. `PJ.28` fixed the expense scan; its fence stopped
there, so `RV.149` had to be filed for the fill-up; `RV.149` fenced out the grouped case, so
`RV.173` had to be filed for the expense siblings. **Each fix was correct and each left the next
copy unprotected.**

## What to build - after reading what RV.173 actually did

**`RV.173` may have changed the seam.** Read its shipped code first and build the guard against what
is there, not against this brief's description of it.

A source-scan guard: **every production path that persists a scanned entry flows through the one
receipt-persistence seam.** The three facts that travel together - attachment id, provenance, and
`purchaseGroupId` for a grouped save - must be bound in one place, and a second binding site must
fail the build.

**Establish what the canonical seam IS before writing the guard.** If there are legitimately two
today, **the row is to decide which is canonical and record that decision** - the guard comes
second. This is exactly what `RV.170` found: the orchestrator's "two creation paths" hypothesis was
wrong and the agent corrected it.

## Build on what exists

Four shipped guards share one anatomy - `RV.162`, `RV.163`, `RV.196`, and `RV.170`'s pair. **A pure
function over source text**, masking comments, strings and `#if DEBUG` before it looks, plus a
**reasoned exception list** where a blank reason **and** a stale unused entry both fail the guard's
own self-check. **Reuse it.** Read `ImportCandidateCopyScanner` and `StationMintingScanner`
(`RV.170`, `fb00eba`) - they are the newest and the closest in shape.

## The strongest test available, and the brief requires it

**Test the guard against real history, not a synthetic fixture.** `git show <sha>:<path>` reads a
file as it was at a commit and writes nothing. The defects are on record:

- `PJ.28`'s pre-fix state - the expense scan that discarded its photo,
- `RV.149`'s pre-fix state - `receiptAttachmentIDs` logging and returning `[]`,
- `RV.173`'s pre-fix state - the dangling expense ids.

**Find their commits** (`git log --oneline --grep`) and run your scanner over those files. A guard
that would have caught three defects that actually shipped is worth more than any fixture you could
invent. `RV.170` did exactly this and it is the strongest evidence in that row.

## Explicitly out of scope

- Fixing anything the guard reports beyond what `RV.173` already fixed. **A finding is a row.**
- `RV.169` (the re-homing guard) - still waiting for its own seam.
- `RV.204` - the block-vs-degrade asymmetry; a decision, not a scan.

## Docs to read before writing (in order)

1. `RV.173`'s shipped commit - **the seam you are guarding**.
2. `ios/Tests/TankbookCoreTests/ImportCandidateCopyScanner.swift` + its guard tests - the pattern.
3. `docs/SCHEMA.md` -> **Attachment**, `provenance`, `purchaseGroupId`.
4. `docs/DEFECT-PATTERNS.md` -> the sibling-defect shape, which this family is the worked example of.
5. `docs/TESTING.md` - where a guard is declared. **Extend it to name this one.**

## Environment axes this crosses

**None at runtime** - a test-target source scan; no shipping code path differs. Say so. **No
screenshots** (a scanner is not a screen), and say that rather than shipping one.

## If this adds a failure path, what makes it visible in production?

None - CI and a developer's machine, never the app. Say so.

## Tests you must add

- **L1, and it must FAIL on real history**: your scanner reports the pre-fix `PJ.28` (or `RV.149`, or
  `RV.173`) source. Cite the commit you read. **At least one, and say which ones you tried.**
- **L1, the calibration**: today's tree is **clean** - the canonical seam is not reported. A guard
  that flags the legitimate path is mis-tuned, and this pair is what proves it discriminates.
- **L1**: a test seed and a `#if DEBUG` block are **not** hosts.
- **L1**: an exception with a blank reason fails the self-check, and a stale unused exception fails.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count, filtered
**by suite name, not the file's**.

## The mutation you must run - I am naming it, do not choose your own

**Re-break `RV.173`** at the seam it settled - restore the behaviour its own mutation restores - and
show your guard reports it. Then restore byte-identical and re-run. Report both outputs verbatim.

If `RV.173`'s fix turns out not to be source-scannable (a runtime decision rather than a binding
site), **say so plainly and say what your guard checks instead** - that is a finding, not a failure.

## Vacuous traps, named

- **Flagging test seeds**, which teaches everyone to allowlist and turns the exception list into a
  skip list.
- **Writing the guard before deciding which path is canonical** - `RV.170`'s row says this in its own
  text and it was the right warning.
- A guard that only matches the exact spelling `RV.173` used, so the next copy - written differently
  - walks past it. The `RV.170` field guard is the model: it caught a non-`station` omission too.
- An exception list longer than a handful. If it is long, the guard is mis-tuned; say so.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08. **Reading
history with `git show <sha>:<path>` is fine and is what the tests above want** - it writes nothing.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## Concurrent work in this checkout

Another `opencode` run has been growing the receipts corpus since 2026-09-10 19:57 and holds
uncommitted changes in `Spike/ReceiptSpike/fixtures/`,
`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` and `ios/Tests/TankbookCoreTests/Corpus*`.
**Do not touch, revert or `git checkout` any of them.** Also pre-existing and **not yours**: four
`ReminderNotificationActionTests` failures, and `SyncWriteTriggerTests` ([RV.203]).

## Standing checks

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0.
3. `cd ios && swift test` - full; report the count. **Run it alone.**
4. **`xcodebuild ... build` for the app target** ([RV.174]).

Verify by **exit code** (`echo $?`).

## Report back

**Which historical commits your guard catches**, with their shas; what the canonical seam turned out
to be and whether there was more than one; every check with its **exit code observed** and counts;
**the mutation's red-then-green output verbatim**; the full list of anything the guard reports; and
**anything you found and did not fix**.
