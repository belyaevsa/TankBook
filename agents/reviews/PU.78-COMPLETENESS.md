# PU.78 completeness review - a last-digit misread is validated as agreement

Run 2026-09-24 01:11-01:40 EEST against the working tree at `c22d0217` + the uncommitted PU.78 diff.
Reviewer: reviewing agent, `agents/briefs/REVIEW-COMPLETE-PU.78.md`.

**What I ran** (read-only; I wrote nothing but this file): `git diff` / `git show` / `git log -S`,
`grep`, `sed`, file reads, `swiftlint lint` on the two touched Swift files (exit 0, warnings only),
`python3 scripts/tasks-index.py --check` (exit 0), `python3 scripts/scenario-index.py --check`
(exit 0, 528 rows), and a read-only Python diff of `windows.json` HEAD vs working tree to find the
corpus drift. **I did not run `swift run PumpReadTool` or any build** - the orchestrator's
`RELEASE=1 scripts/gate.sh` was running for most of this review and the machine was loaded, so every
number below is quoted from a log, not re-measured by me. Where a number is missing I say so.

---

## THE BLOCKER: the gate is red, and it is the corpus that moved, not the law

`/tmp/agentlogs/pu78-gate.log:10121` - **`[gate] tests exit 1 swift test`**. The gate stopped there,
so `xcodebuild test -only-testing:TankbookTests` (the app-target unit bundle) **never ran**.

Two issues out of 2282 tests in 293 suites (`pu78-gate.log:10004`); both are pinned constants
against a moved denominator, and neither is a reading defect:

| Failure | Log | Observed | Pinned |
|---|---|---|---|
| `PumpReaderPipelineTests.swift:281` `committed >= Self.committedFloor` | `pu78-gate.log:9951-9954` | annotated **116** committed, **116 correct, precision 1.000**, 40/67 photos, coverage 0.641 of **181** | `committedFloor = 118` (`PumpReaderPipelineTests.swift:30`) |
| `PumpReaderPipelineTests.swift:112` `measurement.numericTotal == PumpPhotoGate.readerNumericTotal` | `pu78-gate.log:9993-9997` | live **47 committed, 47 correct, 17 committing photos, 0 with a wrong cell**, coverage 0.260 of **181** | `readerNumericTotal = 183` (`PumpPhotoGate.swift:95`) |

**Cause, established.** The concurrent annotator session cleared `"reviewed": true` on
**`pump-275-wayne-neste-night-10337-5171l-board-ee.jpg`** - a heldout still - and hand-framed its
total box (`placedBy: "auto"` -> `"hand"`, new `zoom: 0.5105`, quad moved 0.2956/0.2172 ->
0.3017/0.2186) in `Spike/ReceiptSpike/fixtures/pump/windows.json` (uncommitted; mtime **00:40:20**).
`PumpReaderTestSupport.isHeldout` is `split == "heldout" && reviewed` (`PumpReaderTestSupport.swift:83`),
and `reviewed` is a `static let` read from `windows.json` **once per process**
(`PumpReaderTestSupport.swift:75-82`). So:

- the measurement run (`pu78-measure-2.log`, finished **01:07**) had cached the pre-drift set: 68
  stills, 183 asserted cells;
- the gate's `swift test` started at **01:12** (after the Release build finished 01:11:30) and read
  the post-drift file: **67 stills, 181 cells**.

I confirmed the drift by parsing both revisions: exactly one `reviewed` change, `pump-275` heldout
`True -> None`; heldout-reviewed **68 -> 67**.

**The law is clean on both corpora.** Drifted (gate): annotated 116/116 precision 1.000, zero WRONG
lines; live 47/47, "photos: 17 committing, 0 with a wrong cell". At HEAD (measure-2): annotated
118/118, live 47/47, same 17 committing photos, same 0 wrong. The reader's behaviour did not move
between the two runs - only the population it is scored on.

**What is needed** (the orchestrator's and the owner's call, not mine - the standing fence forbids
touching the annotator's working-tree changes):

1. Resolve pump-275's re-annotation the way PU.79 resolved pump-014's (`docs/TASKS.md:1070`: "the
   row closes when `gateMirror` reads 112 on that commit") - the owner marks it reviewed and the
   corpus commits, or the row is measured and committed against a tree where it is.
2. Re-set on that corpus: `PumpPhotoGate.readerNumericTotal` (`:95`), and `committedFloor`
   (`PumpReaderPipelineTests.swift:30`) with its history comment (`:24-29`, which currently ends
   "112 -> 118 committed, all correct, 35 -> 41 photos").
3. Re-state the same numbers in the PU.78 row's result cell (`docs/TASKS.md:1068`) and in the
   `docs/EXTRACTION.md:1096-1107` paragraph ("heldout **45 -> 47**, annotated **112 -> 118, all
   correct** (35 -> 41 photos fully right)").
4. Re-run `RELEASE=1 scripts/gate.sh` to **exit 0 including the app-target unit bundle**. Hard rule
   14 and RV.250: package-green is not app-green, and a gate that stops at `swift test` has not
   gated the row.

**Consequence the owner should see, and it is not about the constants.** pump-275 leaving the
reviewed heldout set removes from the gate the one still that PU.81 exists to fix and that PU.67's
reopen condition names. PU.81's Checks (`docs/TASKS.md:1069`) are "heldout (annotated and live) zero
wrong ... PU.67 re-measured on it" - neither can be evaluated for pump-275 while it is unreviewed.
If the hand re-frame is what makes pump-275 readable, that is good news and should be measured and
said; if it is mid-edit, PU.81 is blocked on it.

---

## Item 1 - Fidelity to the published method: **MET**, with one recording gap (M3) that makes it PARTIAL under items 6/7

Everything shipped is on the note's list. I found **no unlisted departure**.

| Note | Code | Verdict |
|---|---|---|
| **M1**, §3-M1 / A5: close set `{round2, floor2}`, `closingSlack` retired | `PumpReadingLaw.swift:411-429` - `rounds = abs(product - t.value) < 0.0005`, `closes = rounds \|\| abs(floored - t.value) < 0.0005`; `closingSlack` deleted (was `:27` at HEAD) | MET. A5's two-value set rather than Luhn's single equation, justified in the note by the per-head-unknown rounding mode; still zero-tolerance |
| **A14**: preset keeps the half-volume-step term, loses the additive term | `PumpReadingLaw.swift:421-423` - `presetSlack ? abs(product - t.value) <= 0.005 * p.value : ...` | MET, exactly as prescribed |
| `exactClosing` becomes the round-branch; keeping it is the implementer's call | `:429` `exactClosing: rounds`; doc rewritten at `:345-348` | MET (the note explicitly leaves this to the implementer) |
| **M2 step 1**: exact agreement replaces the 0.5 % band; band-filter the shown list (note §7 finding 3) | `:296-300` - `let bandShown = shownPrices.filter { band.contains($0) }` then `closesExactly`; `pairAgreementTolerance` deleted (was `:267`) | MET |
| **M2 step 2**: unique single-confusion repair | **not shipped** | Held as PU.81 - judged below |
| **M2 step 3**: 5 % band fallback unchanged, behind steps 1-2 (A7) | `:301-307`, `pairValidationTolerance = 0.05` at `:263` | MET |
| **M3**: SR + SGR risk-coverage instrument | **absent** - `grep -rn "SGR\|kappa\|riskCoverage\|selectiveRisk\|pMax" ios/` returns nothing | Not shipped and **not recorded anywhere** - judged below |

**One implementation detail the note does not list**, and I judged it not a method departure:
`cents(floorOf:)`'s `1e-7` nudge (`PumpReadingLaw.swift:310-314`). Luhn is exact integer arithmetic;
the nudge is binary-representation hygiene so a product that is a whole number of cents does not
floor a cent low. It cannot widen the close set: `floor(x*100 + 1e-7) <= round(x*100 + 0.5)`, so
`floored` is still in `{product, product - 0.01}`, and the whole predicate stays inside the retired
0.011 interval. It is commented with the reason.

**Also verified, because the note's A5 made it a pre-ship condition** ("every train/heldout close
with miss in (0.0005, 0.011] today is listed and each is floor-or-round explainable, or named to the
owner") and falsifier #4 makes a lost heldout close a stop-the-ship: no separate enumeration artifact
is in the evidence, but the outcome it predicts is measured directly on all three arms and is
stronger - heldout live **rose** 45 -> 47, heldout annotated **rose** 112 -> 118, train committed
**rose** 124 -> 126 with correct 117 -> 120. Nothing rode the slack. Falsifier #4 did not fire.
Falsifier #1 (any heldout cell lost or newly wrong) did not fire: both heldout arms are precision
1.000 with zero WRONG lines.

### Judgement: holding M2 step 2 is legitimate - and the row's own gate required it

- **It removes behaviour the note proposed and adds none.** Item 1's MISSING case is code doing
  something the paper does not do. Nothing shipped here that the note did not list, so there is no
  fidelity hole to name a paper section against.
- **The A/B is clean and on the same corpus.** `pu78-measure.log` (WITH the repair step): annotated
  **118 committed, 117 correct**, `WRONG pump-014 liters got 3.8200000000000003 want 3.92`.
  `pu78-measure-2.log` (without): **118/118**. Same 183 cells, same 68 photos, same build, minutes
  apart. The row's gate is "zero wrong on heldout", so shipping the step would have **failed the
  row**. Holding it is not a judgement call against the note, it is the note's own gate binding.
- **The note pre-authorised this response.** Falsifier #5: "M2's repair firing non-uniquely or
  uniquely-WRONGLY on any heldout or train photo (a repaired commit that the scorer marks wrong is a
  new wrong cell - gate 1 catches it; the uniqueness rule is the designed defence)." The repair fired
  **uniquely and wrongly** - pump-014's 3.82 x 1.834 = 7.006 -> 7.01 is the only single-confusion
  exact close against its four boards (`docs/TASKS.md:1069`). The designed defence failed, and the
  note's remedy is that gate 1 catches it. Holding is the note working, not the note being overruled.
  What changed since the note was written is the data: the owner re-framed pump-014 (`b42f38da`), and
  the note's enumeration of pump-014 ("EMPTY ... partners of 7 are {1}, of 2 are {}", §3-M2) was
  measured against the old box.
- **It is carried, not dropped.** `docs/TASKS.md:1069` (PU.81) records the mechanism, the pump-014
  arithmetic, the three candidate guards, the owner's decision (**A, the beam guard**, top
  `beamWidth` = 3) and the owner's fallback ("if it does not [exclude pump-014], fall back to no
  repair (pump-275 commits under the caution) rather than invent a threshold"), plus the Checks cell
  and the J4/F2 scenario link. `docs/EXTRACTION.md:1105-1107` records it in the doc too. That is the
  "a gap the row cannot close becomes a new row, drafted here, never silently dropped" shape, done
  correctly.

**The consequence that must be said out loud, because a note falsifier is triggered:** pump-275
still commits **103.31** in the deskew-`.onRefusal` arm - now under `.shownPriceDiffers` rather than
bare agreement. That is the note's falsifier #2 ("pump-275 still committing 103.31 in the deskew-on
arm (neither corrected nor refused)"). It is **not** a clause of the ROW: the app ships `.off`, the
heldout gate runs `.off`, and at `.off` pump-275 commits nothing (`nothingClosed`), so "zero wrong on
heldout" holds. PU.67 therefore stays blocked and PU.81 says it is the reopen path. Two loose ends
for whoever takes PU.81:
- PU.67's row (`docs/TASKS.md:1067`) still says "Reopen once the pump-275 misread is refused (a law
  or read change, its own row)" and does not point forward to PU.81. The link exists only in the
  PU.81 -> PU.67 direction.
- The deskew-`.onRefusal` arm was **not re-measured** after PU.78. `docs/EXTRACTION.md:1113-1114`
  still quotes "52 committed, 51 correct (0.981)" for it. The committed/correct counts probably did
  not move (pump-275 commits either way; only its caution did), but that is my inference, not a
  measurement, and PU.81's Checks promise "PU.67 re-measured on it".

### Judgement: M3's absence leaves no promise of the ROW unmet - but it is recorded nowhere, and that is a gap

- **M3 cannot change a verdict, by the note's own text.** §6: "M3 ships no runtime code unless a
  theta passes the gate (then: one comparison per cell at commit)." §3-M3's ship rule: "theta ships
  only if the heldout gate passes at it - and §0.2's overlap predicts it will not." §0.2 measured the
  overlap that predicts it: the six wrong photos span minimum margins 0.012-0.790 nats, and correct
  heldout photos reach down to pump-139's 0.200. So M3 fixes none of the eight traced cells, and the
  row's gate (zero wrong on heldout, train wrong falls, heldout commits do not fall, oracle ratchet
  and fragility hold) is met without it. The ROW's Checks cell never names M3; it names "the
  published method from the note implemented at that seam", and the seam the row names is the tier
  that admitted each wrong cell - M1 and M2 are at that seam, M3 is not.
- **M3's only downstream consumer is gone.** PU.81's option C was "a fitted selective threshold
  (PU.78 M3, Geifman & El-Yaniv)". The owner chose **A**, the beam guard. Nothing open depends on M3.
- **What is missing is the record, and item 7 exists for exactly this.** Neither the PU.78 row
  (`docs/TASKS.md:1068`) nor `docs/EXTRACTION.md:1096-1107` mentions M3 at all. A reader of the docs
  cannot tell that one of the note's three nominated mechanisms was not built. Worse, the EXTRACTION
  paragraph says "**The note's third step**, repairing one confusable cell of a pair against a shown
  price" (`:1105`) - the repair is **M2's step 2**; the note's third mechanism is M3. The sentence
  mislabels the thing it is describing and simultaneously hides the thing that is actually absent.
- **Fix (docs only, no code):** in the row's result cell and in `docs/EXTRACTION.md:1105`, rename
  "the note's third step" to "M2's repair step", and add one clause: M3 (the SR + SGR risk-coverage
  instrument) was not built - it changes no verdict, the note's own §0.2 margin overlap predicts no
  theta passes the heldout floor, and PU.81's owner-chosen beam guard removed its only consumer; if
  the owner wants the risk-coverage price list, that is its own row. That last part matters: the note
  called the curve "what turns 'the bands feel too loose' into an owner-visible price list", and it
  is a reasonable thing to want later. It should be droppable only in writing.

---

## Item 2 - Wired into the app path, Release as well as Debug: **MET**

The chain, read end to end:

- `CapturePipeline.process` (`ios/App/Sources/Capture/CapturePipeline.swift:44-63`) ->
  `readPumpDisplay` (`:60`, `:126`) -> `PumpDisplayCapture.classify`
  (`PumpDisplayCapture.swift:302` public, `:317-342` body) -> `readDecision` ->
  `PumpReader.read` -> **`PumpReadingLaw.resolve`** (`PumpReader.swift:557`).
- The reader the app uses is built once at `CapturePipeline.swift:28` from the bundled
  `PumpSegments.mlmodelc` / `DigitRows.mlmodelc`, and also feeds the live preview analyzer
  (`ios/App/Sources/Capture/CameraCapture.swift:153`) and the lab (`CaptureLabRunner.swift:173`).
- The law's other two call sites are `PumpFrameFusion.swift:74` (the Live-Photo frame path) and
  `PumpReadTool` (`main.swift:253`, `:330`) - the tool is not the only door.
- **No `#if DEBUG` anywhere in the chain**: `grep -n "#if DEBUG\|#else\|#endif"` over
  `PumpReadingLaw.swift`, `PumpDisplayCapture.swift`, `PumpReader.swift` returns nothing, and
  `CapturePipeline.swift` has no `#if` at all. The Release build compiled it:
  `pu78-gate.log:4717` **`[gate] release exit 0`**.
- **The measurement is on the app's entry point, not the harness's**: `livePath` builds the reader
  through `PumpDisplayCapture.makeReader` and the report line reads "PU.63 live path (the app's
  classify)" (`PumpReaderPipelineTests.swift:84-101`). `trainSplitRiskBound` does the same
  (`:129-133`). This is not the "docs naming behaviour with no call site" shape.

One caveat, and it belongs to the blocker above: because the gate stopped at `swift test`, the
app-target unit bundle never ran, so `CapturePipelineCompositionTests` (which asserts the caution
channel PJ.500 built, and which PU.78 changes the frequency of) is **unverified in this run**.
Nothing under `ios/App` changed, so I suspect nothing is broken - but suspicion is not the gate.

---

## Item 3 - Measured on the app path, on the named population: **PARTIAL**

The measurements exist, are on the app path, cover every population the row named, and carry PU.68's
intervals beside every point estimate. The two pinned constants no longer match the tree.

| The row's claim (`docs/TASKS.md:1068`) | Evidence | Verdict |
|---|---|---|
| heldout live 45 -> **47/47** | baseline `pu79-on-b42f38da.log:16` 45/45, 15/68 photos -> `pu78-measure-2.log` 47/47, 17/68, Wilson 95 % [0.9244, 1.0000], one-sided Wilson 0.9456, Clopper-Pearson 0.9382, photo-level one-sided 0.8627 | MET |
| annotated 112 -> **118/118** (41/68 photos) | baseline `pu79-on-b42f38da.log:10` 112/112, 35/68 -> `pu78-measure-2.log` 118/118, 41/68, Wilson [0.9685, 1.0000], one-sided 0.9776, CP 0.9749 | MET at HEAD; **the tree now measures 116/116, 40/67** (`pu78-gate.log:9946`) |
| train in-sample 124/117 -> **126/120** | baseline PU.68's row (`docs/TASKS.md:1067`) 124/117 -> `pu78-measure-2.log` 126/120, 47 committing photos, 4 with a wrong cell, Wilson [0.9000, 0.9780], photo wrong-commit UCB 0.1843 at delta 0.05 / 0.1629 at delta 0.10, HB p 1.0000 | MET |
| **zero wrong on heldout** | live "photos: 17 committing, **0 with a wrong cell**"; annotated precision 1.000 with no `WRONG` line, on both corpora | MET |
| **the train wrong count falls** | 7 cells / 5 photos -> **6 cells / 4 photos**; the WRONG list loses pump-251 and keeps 099 total, 137 liters, 137 total, 264 total, 266 liters, 266 total - exactly the note's prediction (§5, "Train wrong cells 7 -> 6 (pump-251's 75.36 refused); 137 x2, 099, 264, 266 x2 remain, owned M5/M6") | MET |
| **heldout commits do not fall** | live 45 -> 47, annotated 112 -> 118 | MET |
| `PumpPhotoGate` reader constants **47/47/183** | `PumpPhotoGate.swift:86,91,95` = 47/47/183. The run says 47 committed, 47 correct - **and 181 asserted cells** | **PARTIAL**: 47/47 match, **183 is stale** |
| `committedFloor` **118** | `PumpReaderPipelineTests.swift:30` = 118. The run says **116** | **PARTIAL**: stale |
| intervals beside the point estimate (PU.68 landed) | printed for live, annotated and train, two-sided and one-sided Wilson plus Clopper-Pearson, plus the in-sample UCB and HB p-value | MET |

---

## Item 4 - No regression elsewhere: **PARTIAL** (latency), the rest MET

**Receipt leak - MET, on an argument plus one printed number, not a fresh leak run.**
Routing is decided by `PumpDisplayCapture.decide` (rows / text lines / widest row); this diff touches
no file under `ios/Sources` except `PumpReadingLaw.swift` and `PumpPhotoGate.swift` (`git status`), so
the routing count cannot move. The gate's classification run prints
`PU.38 heldout classification: 5/6 pumps (5 fast), **0/8 receipts leaked**` (`pu78-gate.log:9973`),
unchanged. And every predicate the diff touches is **strictly narrower**, so a leaked fixture can
commit strictly less than before:
- `rounds` (`|product - t| < 0.0005`) is a subset of the retired `miss <= 0.011`;
- `floored` is in `{product, product - 0.01}`, so `|floored - t| < 0.0005` implies
  `|product - t| < 0.0105 <= 0.011`;
- preset `<= 0.005 * p` is a subset of `<= 0.011 + 0.005 * p`;
- for the pair: if a band-filtered shown price closes exactly then `implied = total / liters` is
  within half a cent over litres of it, so `nearest` (`:301`) is at most that far - the exact
  agreement branch cannot fire on a pair the old 5 %-gated branch would have refused.
`PumpLeakConsequenceTests` (`PUMP_LEAK=1`) was **not** re-run - it is opt-in, the row does not
promise it, and PU.68's finding was "6 of 116 routed, **0 commit a field**". If the orchestrator
wants the number rather than the argument, `PUMP_LEAK=1` is cheap.

**Oracle ratchet - MET, it rose.** `pu78-gate.log:7073` (on the final tree, after the test-file
split): **774 committed, 773 correct, precision 0.99871**, coverage 0.871 of 889, the sole wrong
being the declared artefact `pump-031`. Pre-row: **771 / 770, 0.99870** (`pu68-swifttest.log`, same
889 denominator). Floors `committedFloor = 294`, `precisionFloor = 0.996`
(`PumpReadingLawTests.swift:16-17`) untouched by the diff. Note the direction: the M1 mutation
(restoring the interval) reads **780** (`pu78-mutation-M1.log`), i.e. exactness costs 6 oracle cells
and buys a precision that was already 0.9987 - the ratchet's floor is not what protects this row,
the heldout arms are.

**Fragility - MET against its ceiling, but not a clean A/B.** `pu78-gate.log:8102`: **995 committed,
41 wrong = 0.0412**, ceiling 0.10 (`PumpReadingLawTests.swift:474`). The M1 mutation reads 1035/53 =
0.0512, so exactness **lowers** the fragility wrong rate by a point. The nearest pre-row number I can
find is 987/36 = 0.0365 (`pu68-swifttest.log`, 2026-09-23 19:53) - measured on the corpus **before**
`b42f38da`, so it is not the same population, and no pre-PU.78 fragility run exists on the current
corpus. The movement is inside the ceiling and inside the spread the test's own comment documents
("seeds 1/2/3/21 read 6.8 / 6.5 / 8.5 / 9.1 %"). I am not calling this a fall; I am saying the row's
"fragility 0.041 (<= 0.10)" is honest and that no like-for-like baseline was taken.

**Latency - PARTIAL. There is no Release number.** The law is on the capture hot path; the gate's own
Debug timing is `PU.38 pump decision ms: median 1287 max 23936; classify+read ms: median 34160 max
39057` (`pu78-gate.log:9975`), and `grep Release /tmp/agentlogs/pu78-measure*.log` returns nothing.
The note §6 both argues the cost is nothing ("one interval comparison with two equality comparisons";
"dozens of floating-point multiplies, microseconds") and states the obligation ("**the Release number
is owed by the implementation** (the row's gate; for scale, PU.75's row records today's Release
decision 13-73 ms and read 112-164 ms on a Mac)"). The row's Checks cell does not promise it, so
this is the review template's item, not a dropped row promise - but the template asks and the answer
is absent. Either take the Release number (`pump-read --timings` on a Release build) or write the
immateriality argument into the row so the next reviewer does not re-ask.

---

## Item 5 - Tests that would fail: **MET**, with one traceability note

Both mutations are in the evidence and both went red on the right tests.

**M1 revert (restore the 0.011 interval) - 2 tests red**, `pu78-mutation-M1.log`:
- "a total one cent off the product does not close: the check is exact" - both assertions fail,
  `reading.total.value` comes back **75.36** instead of the beam's 6 -> 5 runner-up closing 75.35.
  That is pump-251's exact shape, green-wrong again, which is what the note §6 asked this mutation to
  demonstrate.
- "a pair near a shown price but not exact is a difference, not agreement" - `committedCount == 2`
  fails with **3**, and the caution goes missing: with the slack back, `cleanBoardClose` closes
  10.00 x 2.008 = 20.08 against a shown 20.01 and the board tier commits the price too.
- The same log shows the oracle ratchet moving 774 -> 780 and fragility 0.0412 -> 0.0512, i.e. the
  mutation is visible in the corpus instruments as well as in the unit tests.
- The build warning in that log (`initialization of immutable value 'floored' was never used`,
  `PumpReadingLaw.swift:412`) is the fingerprint of the mutation itself, which is useful: it confirms
  the revert replaced the predicate rather than deleting the mechanism.

**M2 revert (restore `pairAgreementTolerance`) - 3 tests red**, `pu78-mutation-M2.log`: the near-miss
pair, "a pair a cent off an exact close against the board is cautioned, not agreed", and "PJ.500: a
shown price the pair closes exactly against carries no caution; 0.4 % off does" - all three on
`expected shownPriceDiffers`. Oracle and fragility are unchanged under this mutation (774 / 995-41),
which is itself informative: M2 changes **cautions**, not committed cells, so only these tests see it.
That is the correct coverage shape - without them the mutation would have been invisible.

**Traceability note (not a defect, but fix it in the row).** Both logs cite
`PumpReadingLawTests.swift:224`, `:243`, `:254-255`, `:440`. Those three tests now live in
`PumpReadingLawExactTests.swift:14`, `:31`, `:45` (file mtime **01:09:50**, after the mutation runs
at **01:08**), and the PJ.500 test's `Issue.record` is now at `PumpReadingLawTests.swift:397`. The
test **names** and the failing assertion **texts** match the tree one-to-one, so the evidence is
sound - but the line numbers are not addressable, and a later reader could conclude the mutations
were run against different tests. One clause in the row ("run before the three tests moved to
`PumpReadingLawExactTests.swift`") closes it.

**Coverage of the two branches nobody mutated:**
- The **floor** half of the close is load-bearing in two green tests that would go red without it:
  `ambiguityWindowIsLoadBearing` (`PumpReadingLawTests.swift:481-502`) and
  `partialReadCarriesFieldReason` (`:198-213`) were both rewritten to 7.00 x 2.001 = 14.007, which
  rounds to 14.01 and floors to 14.00, and the first asserts `closed.count >= 2` ("the beam must
  offer a second closing triple for this test to mean anything"). Dropping the floor branch takes
  that count to 1 and turns it red. Both also assert the round-exact total wins, which is what
  `exactClosing`'s new meaning is for.
- The **preset** narrowing (A14) is covered by `readWindowIsLoadBearing`
  (`PumpReadingLawTests.swift:505-518`: 1000.00 / 13.17 / 75.95, product 1000.26 against a 0.380
  bound) plus `PumpExtractorTests.swift:90` and `DigitRepairTests.swift:117`, all green in the gate.
  No test distinguishes `0.005p` from `0.011 + 0.005p`; for a narrowing that is acceptable, and the
  note's A14 asked only that pump-010 be re-measured by name, which those three do.
- The new suite ran in the gate and passed: `pu78-gate.log:4771` (started), `:7620` (the one-cent
  test), **`:9531` `Suite "Pump reading law - exact closes" passed`**; it was linted at `:1132`.

---

## Item 6 - Docs reconciled: **PARTIAL** - five things, one of them introduced by this diff

**What is reconciled, and it is the bulk of the work:**
- Decision 11's "Wired" paragraph carries the amendment in place, dated, with the reason and the
  measured example: `docs/EXTRACTION.md:1019-1022`.
- The new narrative paragraph `docs/EXTRACTION.md:1096-1107` names the paradigm (check-digit, zero
  tolerance), the retired constant, the preset exception, all three measured movements, what stays
  wrong and which row owns each (099/264/266 -> PU.73, 137 -> PU.74), and what was held (PU.81).
- `docs/ERRORS.md` needs **no change**, and I checked rather than assumed: `:315` already words the
  trigger as "the displayed unit price is **near but not equal to** total / litres (a loyalty
  discount, or a misread digit)". That is now literally the code's rule - PU.78 made the copy true
  rather than approximately true. No new string, no new surface, no next step changed, so hard rule 7
  is untouched and there is nothing to screenshot (no file under `ios/App` changed).
- `docs/JOURNEYS.md` needs **no change**, and this one is worth saying: J4 has read "when the shown
  price differs from the implied one by **more than rounding**, an amber notice names both as a
  discount or a misread" since PJ.500 (`git log -S` -> `bdca96a9`). The journey was already
  specifying exact agreement; the code was behind it. F2's "residue" row ("if all three numbers are
  wrong *consistently* (rare), the cross-check passes falsely") is narrowed by this change and states
  no threshold, so it needs no edit either.
- `scripts/tasks-index.py --check` exit 0 (the index at `docs/TASKS.md:167-168` carries both the
  PU.78 tick and the new PU.81 row); `scripts/scenario-index.py --check` exit 0, 528 rows, PU.81
  attached to J4/F2.

**What is not:**

1. **A typo this diff introduced.** `docs/EXTRACTION.md:1017-1018` reads "the law marks a shown price
   that differs from the implied one **by / by** more than rounding". The HEAD line ended in "by" and
   the replacement text began with "by". One word to delete.
2. **`docs/EXTRACTION.md:1113-1114` contradicts the paragraph above it.** "so the app's reader stays
   `.off` (**45/45**)" sits two paragraphs below "heldout **45 -> 47**". It is inside a dated
   PU.65/PU.67 measurement paragraph, but it states the app's current floor, and CLAUDE.md's conflict
   rule says the more specific doc wins and the stale one gets fixed in the same change.
3. **`docs/EXTRACTION.md:900`** quotes the bound this row moved: "45/45 committed-correct bounds
   precision at only ~0.92 (Wilson two-sided 95 %; the one-sided 95 % lower bound is 0.943)". At 47/47
   the run prints [0.9244, 1.0000] and one-sided 0.9456. Dated owner amendment, so the softest of
   these - but it is the number PU.68's whole row exists to keep honest.
4. **`docs/TASKS.md:1062` (PJ.500, `[x]`) names two symbols this diff deleted**: "the law now
   separates agreement (within 0.5 %, **`pairAgreementTolerance`** - no caution)" and
   "Checks: **`pairWithAgreeingShownPriceIsNotCautioned`**". The constant is gone and the test is now
   `pairAgreementIsExact` (`PumpReadingLawTests.swift:378`). PU.79 exists as a row precisely because a
   closed row's stale number went unowned; this is the same shape at smaller scale, and it is a
   one-clause fix ("retired by PU.78; the test is now `pairAgreementIsExact`").
5. **`agents/research/PU.78.md` is untracked** (`??` in `git status`) while **three pointers cite it
   by path**: `PumpReadingLaw.swift:14` ("the check-digit paradigm, agents/research/PU.78.md §2.1"),
   `PumpReadingLaw.swift:267` ("agents/research/PU.78.md, M2") and `docs/EXTRACTION.md:1096`.
   `agents/briefs/RESEARCH-PU.78.md` and `agents/briefs/REVIEW-COMPLETE-PU.78.md` are untracked too.
   If the commit does not include them, two code comments and one doc paragraph dangle. (`HEAD`
   `c22d0217` is the commit that made research notes the artifact for a row that changes a method, so
   the note belongs in the row's commit.)

**The comment audit the brief asked for.** `closingSlack` and `pairAgreementTolerance` are **gone
from every line of code and every code comment**: `grep -rn` over `ios/Sources`, `ios/App` and
`ios/Tests` returns zero hits. What remains, and whether it matters:

| Where | Text | Verdict |
|---|---|---|
| `PumpReadingLaw.swift:455-460` | "**STALE - fix.** `commit()`'s contender comment still narrates the retired slack: 'a competing triple that reaches the SAME total inside **the truncation slack** is a false close of an operand: its price or volume is **a cent off** and the exact operand is the read.'" | There is no truncation slack in the two-decimal branch any more, and `exactClosing` now means *rounds, not floors* - its own doc at `:345-348` was correctly rewritten to say so, and this one was not. What the filter actually drops now is a competitor that reaches the same displayed total **only by flooring** (product in `[T, T + 0.01)`). CLAUDE.md: "When behavior changes, audit every comment in each touched file... search comments for renamed symbols and replaced literal values." This is the one comment in the file that does not describe the exact close |
| `PumpReadingLaw.swift:9-15` | header: "closes the arithmetic exactly: the shown total is the product rounded or floored to the cent, never a value near it" | Correct, present tense, and the `never` is enforced by `PumpReadingLawExactTests.swift:14`. Cites the authority rather than restating a rule, as CLAUDE.md asks |
| `PumpReadingLaw.swift:108-115` | repair tier: "the arithmetic still has to close to the cent (no tolerance widening)" | Now literally true, as the note §3-M1 predicted. The repair tier calls `closingTriples` unchanged (`:135-136`) and inherits exactness |
| `PumpReadingLaw.swift:265-274` | `pairOutcome` doc, steps 1 and 2 | Correct, and correctly does **not** describe a repair step that is not shipped. No planned-feature narration |
| `PumpReadingLaw.swift:310-311`, `:316-317`, `:414-419` | the nudge, `closesExactly`, the inline close comment | All current truth, all explain a non-obvious invariant (binary noise; the per-head rounding mode; the preset bound being resolution-derived rather than a tolerance) |
| `PumpReadingLaw.swift:262` | **pre-existing, and in a file this row touched**: "The band alone is not a sufficient guard on the heldout live path (**measured: 6 of 8 pair commits** land inside the coarse currency band and are wrong)" | A mutable accuracy score in a comment, which CLAUDE.md forbids, describing the tier this row changed, and now sitting beside a heldout live path that measures **0 wrong**. The claim is a counterfactual about the band *alone*, so it is not strictly contradicted - but the fix is cheap: keep the justification, drop or source the count |
| `docs/TASKS.md:1068`, `:1069`; `agents/research/*.md`; `agents/briefs/*`; `agents/reviews/PUMP-REVIEW-2026-09-23-qwen.md:86` | name both retired constants | Correct: these are records, and the PU.78 row's whole point is to say they were retired |
| `ml/pump-reader/REPORT.md:592` | "`closingSlack` is 0.011 so a head that floors its product still closes..." | A dated entry in the engineering log (its last three commits are PU.53/PU.54/PU.55; PU.65-PU.80 did not append), describing the PU.34 finding that created the very contender filter whose comment is now stale. History, not current truth - no change owed, but it is where a reader will land if they grep the constant |
| `agents/research/PU.72.md:98`, `agents/research/PU.74.md:148,297`, `agents/briefs/RESEARCH-PU.72.md:19` | name `closingSlack` with line numbers as a constant those rows would touch or leave alone | **Found, not fixed - owned by PU.72 and PU.74, both open.** Those notes will be handed to implementers, and `closingSlack (:27)` no longer exists. A note is a record of a run at a commit, so this is defensible; a one-line "retired by PU.78" at each site is cheaper than an implementer rediscovering it |
| `ml/pump-reader/.out/review-why/tree/...` | a full stale copy of `PumpReadingLaw.swift:27` | Gitignored (`.gitignore:8`, `ml/pump-reader/.out/`). Not a doc, no action |

---

## Item 7 - Everything the row promised, sentence by sentence

The Checks cell of `docs/TASKS.md:1068`:

| Sentence | Verdict |
|---|---|
| "Each of the seven wrong cells traced to the law tier and the rule that admitted it (pump-read tool, app path)" | **MET, and exceeded.** The note §0 traces **eight** (the seven train cells in five photos plus heldout pump-275), through `pump-read --trace-serve` -> `PumpDisplayCapture.classify` (`TraceServe.swift:78-80`), i.e. the app's entry point as the sentence asks, and then replicates the law's arithmetic in Python from the traced posteriors, reproducing all six fixtures' verdicts **to the nat** (e.g. pump-137 `-12.234401` vs observed `-12.234401477523217`). §0.1's table gives tier + rule + `file:line` per cell. It also **refutes the row's own working inference** for three of the eight: 251 and 137 are the main triple tier's slack, not the pair bands. That is the trace doing its job |
| "the published method from the note implemented at that seam" | **PARTIAL.** M1 and M2 steps 1 and 3 are implemented at exactly the seams the trace named. M2 step 2 is held as PU.81 - legitimate and gate-required, judged above. M3 is absent and **unrecorded** - no ROW promise unmet, judged above, but the docs must say so |
| "train split (in-sample, `PUMP_CERTIFY=1`) and heldout app path both reported with PU.68's intervals" | **MET.** `pu78-measure-2.log` ran with `PUMP_CERTIFY=1` (the train test is `.enabled(if:)`-gated at `PumpReaderPipelineTests.swift:128` and it executed, 1879 s). Both arms print two-sided and one-sided Wilson plus Clopper-Pearson, the train arm adds the photo wrong-commit UCB at delta 0.05 and 0.10 and the HB p-value, and every print is labelled in-sample |
| "zero wrong on heldout" | **MET** on both heldout arms and on both corpora (118/118 and 116/116 annotated; 47/47 live, "0 with a wrong cell") |
| "the train wrong count falls without heldout commits falling" | **MET.** 7 -> 6 wrong cells, 5 -> 4 wrong photos, pump-251 gone; heldout live 45 -> 47 and annotated 112 -> 118, both up |
| "oracle ratchet and fragility hold" | **MET.** 771 -> 774 at 0.99871 against floors 294 / 0.996; fragility 0.0412 against a 0.10 ceiling (and 0.0512 under the M1 mutation, so exactness improves it) |
| "completeness review COMPLETE" | **NOT MET - this review is INCOMPLETE** |

Result cell claims I checked and found accurate: the EIGHT-cell trace, M1/M2 as described,
`closingSlack` and `pairAgreementTolerance` retired, the preset tier keeping its half-volume-step
bound, "M2's repair step held as PU.81 (it corrupted pump-014)", the 45 -> 47 / 112 -> 118 /
124-117 -> 126-120 movements, the 41/68 photos, the ownership of what stays wrong (099/264/266 ->
PU.73 read quality, 137 -> PU.74), oracle 774 at 0.9987, fragility 0.041, and both mutation logs.
The two claims that are **not** accurate against the tree are the pinned constants: "`PumpPhotoGate`
reader constants 47/47/**183**" and "`committedFloor` **118**".

---

## Found and not fixed

1. **The blocker** - red gate, two stale corpus constants, app-target bundle never run. Owned by this
   row; the orchestrator and the owner (pump-275's re-annotation) close it.
2. **`PumpReadingLaw.swift:455-460`** - `commit()`'s contender comment still narrates the retired
   truncation slack. Owned by this row (CLAUDE.md's same-change audit rule).
3. **`docs/EXTRACTION.md:1017` "by by"**, **`:1113` "(45/45)"**, **`:900` the 45/45 bound**,
   **`:1105` "the note's third step"**, **M3 unrecorded**. Owned by this row.
4. **`docs/TASKS.md:1062` (PJ.500)** names `pairAgreementTolerance` and
   `pairWithAgreeingShownPriceIsNotCautioned`, both deleted here. Owned by this row (it deleted them).
5. **`agents/research/PU.78.md`, `agents/briefs/RESEARCH-PU.78.md`,
   `agents/briefs/REVIEW-COMPLETE-PU.78.md` are untracked** while cited by path from two code
   comments and one doc paragraph. Owned by this row's commit.
6. **No Release latency number** for a change on the capture hot path. Owned by this row (the note §6
   assigns it there); cheap either way.
7. **The deskew-`.onRefusal` arm was not re-measured after PU.78**, and
   `docs/EXTRACTION.md:1113-1114` still quotes 52/51 (0.981) for it. **Owned by PU.67 / PU.81**
   ("PU.67 re-measured on it"), not by this row - the app ships `.off`.
8. **PU.67's row does not point forward to PU.81**, though PU.81 points back at it and is now its
   only reopen path. **Owned by PU.67/PU.81**; one clause.
9. **`agents/research/PU.72.md:98`, `PU.74.md:148,297`, `agents/briefs/RESEARCH-PU.72.md:19`** name
   `closingSlack` with line numbers as a live constant. **Owned by PU.72 and PU.74**, both open, both
   about to be dispatched to implementers.
10. **`PumpReadingLaw.swift:262`** carries a mutable measured count ("6 of 8 pair commits") in a
    comment, in a file this row touched, about the tier this row changed. Pre-existing; CLAUDE.md
    forbids the shape. Cheapest to fix while the file is open.
11. **The mutation logs' line numbers do not address the tree** (the three tests moved to
    `PumpReadingLawExactTests.swift` after the runs). Names and assertion texts match one-to-one, so
    the evidence stands; the row should say so.
12. **No sibling fix is owed, and I checked rather than assumed.** The nearest siblings are the
    receipt cross-check's `ConfirmConfidenceGate.crossCheckTolerance` (`CrossCheck.swift:93`) and the
    rules arm's `PumpExtractor.exactTolerance = 0.005` (`PumpExtractor.swift:418`). Neither is this
    defect: a receipt's total is printed by a different device than its line items, so a 0.5 %
    tolerance there is a consistency signal and its own comment says so ("anything looser is a
    consistency signal, never a pin"), while a pump head's total is the *same head's own product* of
    the operands it shows - which is what makes zero tolerance correct there and wrong here.
    `PumpExtractor.exactTolerance` is already half a cent, i.e. already exact. `DigitRepair`
    (`DigitRepair.swift:17-23`) is already exact and is the rule M2 step 2 would have extended.

---

## Verdict

# INCOMPLETE

The method is right, the measurements are right, and the two things the row chose **not** to ship
were chosen correctly and carried forward properly. What blocks the commit is not the law.

**Must fix before the orchestrator commits:**

1. **The gate must exit 0** (`pu78-gate.log:10121` is `exit 1`), **including the app-target unit
   bundle**, which never ran. Resolve pump-275's re-annotation (owner marks it reviewed, corpus
   commits - PU.79's precedent), then re-set `PumpPhotoGate.readerNumericTotal` (`:95`),
   `committedFloor` (`PumpReaderPipelineTests.swift:30`) and its history comment (`:24-29`) on that
   corpus, and re-state the numbers in `docs/TASKS.md:1068` and `docs/EXTRACTION.md:1101-1102`.
   If the owner intends pump-275 to stay out of the reviewed heldout set, say so in the row - it
   unmeasures the still PU.81 and PU.67 both turn on.
2. **Record M3's absence and fix its mislabel.** `docs/EXTRACTION.md:1105` "the note's third step"
   -> "M2's repair step"; add one clause, in the row and in the doc, that M3 (SR + SGR
   risk-coverage) was not built because it ships no verdict, the note's §0.2 margin overlap predicts
   no theta passes the heldout floor, and PU.81's owner-chosen beam guard removed its only consumer -
   and that the risk-coverage price list, if the owner ever wants it, is its own row.
3. **Rewrite the stale comment** at `PumpReadingLaw.swift:455-460` so it describes the exact close
   (a competitor dropped is one that reaches the same total **only by flooring**, not one "a cent off
   inside the truncation slack").
4. **Docs, four small edits:** delete the duplicated "by" at `docs/EXTRACTION.md:1017`; reconcile
   "the app's reader stays `.off` (45/45)" at `:1113` with the 47 the row measured; update or date
   the 45/45 precision bound at `:900`; add "(retired by PU.78; the test is now
   `pairAgreementIsExact`)" to the PJ.500 row at `docs/TASKS.md:1062`.
5. **Include the untracked artifacts in the commit**: `agents/research/PU.78.md`,
   `agents/briefs/RESEARCH-PU.78.md`, `agents/briefs/REVIEW-COMPLETE-PU.78.md`, and this review -
   two code comments and one doc paragraph cite the note by path.
6. **A Release latency number, or the immateriality argument written into the row** (note §6 owes it;
   PU.75's row is the precedent for the format).
7. **One clause in the row** noting the mutations were run before the three tests moved to
   `PumpReadingLawExactTests.swift`, so their log line numbers do not address the tree.

Items 1, 2 and 4 of the brief's list are PARTIAL and item 3 is PARTIAL; items 5 and 6 are MET apart
from the comment and doc fixes above; item 7 is PARTIAL only through the sentences listed here. No
gap in this list needs a new row except the ones already filed: **PU.81** (the repair and its beam
guard) and, if the owner wants it, a row for **M3's risk-coverage curve**, which item 2 above should
name explicitly rather than leave to memory.

Re-dispatch a fresh copy of `REVIEW-COMPLETE-PU.78.md` once 1-7 are in the tree. The law change
itself needs no further work that I can see.
