# The extraction plan: receipts, pumps, and the plumbing between them

*The newest section is first ("2026-09-26"); everything from "Where it stands tonight" down is the
plan of 2026-09-04 and is history.*

## 2026-09-26 - the pump reader: where it stands, what the owner does, what gets built

### Where it stands

| Measure (68 frozen heldout stills, 183 cells, the corpus scorer) | Now | Gate |
|---|---|---|
| Committed / correct | **119 / 118** | - |
| Precision | **0.992** | >= 0.99 |
| Coverage | **0.65** | >= 0.60 |
| Non-pumps routed as a pump / committing a number | 6 of 117 / **0** | 0 committing |

The build clears the pump-mode gate. The mode itself is the remote `pumpPhoto` flag, **off** - until
it is on, a pump reading reaches Confirm marked alpha. The pipeline and every threshold are described
stage by stage in the Russian explainer (artifact "Как Tankbook читает колонку") and in
`docs/EXTRACTION.md` -> "The pump reader".

**What still reads nothing** (`agents/research/PU.90.md`): dark LCDs with pale segments behind
reflective glass, and TFT screens. Both fail at the locator; the read and the law already handle them
when the rows are found. Nothing wrong is committed on either - the law refuses.

### What the owner does (the parts no agent can)

1. **Decide - now:**
   - turn on `pumpPhoto` (the build clears the gate), or keep the alpha framing a while longer;
   - upload a new beta (`release.sh --upload --beta`): the phone's build still commits the old
     tenfold-price and swapped-field readings that `HEAD` refuses;
   - the cautioned no-price tier on unfamiliar heads (PU.95): keep it, keep it but never on a family
     the locator was not trained on, or drop it.
2. **Verify frames in the annotator** (PU.91's data): 30-60 frames per record, spread over the fill,
   from `video-050` and `live-6402`, `6404`, `6405`, `6424`, `6425`; check the reference quads of
   `video-050` and `video-051` (placed by the orchestrator, unreviewed). A tracker's box is not
   training data until a human has looked at it.
3. **Capture:**
   - **dark-LCD fills, 10-20, from three or more chains**, each with its Live record - two heads
     today is not a family;
   - **TFT screens, 5-10, from other chains or countries** - one still today;
   - the **first fill of each kind goes to `heldout2` whole** (each family has one member there now, an
     idle display);
   - **Capture Lab runs** for SH.9 with the next beta: a night pump, a display in glare, a long or
     faded receipt.

### What gets built, in order

| # | Row | What | Waits on |
|---|---|---|---|
| 1 | **PU.93** | Measure the unguarded path: does the receipt parser's fallback (PU.62) commit a TFT or dark-LCD value with no family check? If yes, gate it before anything else ships | nothing |
| 2 | **PU.91** | Retrain RowSeg with the dark-LCD stills and verified frames; judged on the rotated gate, the heldout floors, and the dark-LCD stills and frames | the owner's frame verification |
| 3 | **PU.92** | TFT route: display-family statistics -> on-device Vision OCR -> the unchanged law; advert suppression in the same change; labels as a cross-check. Vision never reads a segment display | PU.93; more TFT photos to judge generality |
| 4 | **PU.94** | Live-frame fusion at the locator (glare moves, digits do not) | only if PU.91 leaves glare as the limit |
| 5 | **PU.95** | The cautioned pair tier on unfamiliar heads: measure its precision per family, apply the owner's ruling | the owner's decision |
| - | **SH.10** | Store the 2048 px copy of a capture, not the full photo (reads as well, ~3x smaller) | nothing |
| - | **SH.9** | Production capture preset (stays `default` until the lab shows a difference) | the owner's lab runs |

### What not to do

- No path where Vision's raw digits pre-fill a field without the law's exact close - the advert's
  digits and the dropped decimal point are both real, measured outputs.
- No loosening of the classification floors to let these families through: on `pump-339`/`340` they are
  the only thing between the user and a price-board cell committed as the total.
- No tuning against `heldout2` - it is measured when a change is judged, never while one is fitted.
- No renderer work for the dark-LCD family first: the locator that fails trains on real images only.

---

*The plan of 2026-09-04 follows. Written from the day's measurements and seven independent agent
analyses (`diagnostics/RESEARCH-receipt-options-{qwen,kimi,deepseek}.md` and
`diagnostics/RESEARCH-pump-{vision,kimi,pro,qwen}.md`).*

## Where it stands tonight

| class | this morning | now | note |
|---|---|---|---|
| receipts | 101/210 (48%) | **188/220 (85%)** | 33 of 48 fixtures entirely correct; the total column misses nothing |
| fiscal | 2/5 | 5/5 | |
| screenshots | 27/40 | 35/40 | |
| pump | 51/251 (20%) | **24/178 numeric, 100% precision** | the gate was re-scoped (B1); the old 20% mixed three unlike things - see B0 |

Receipts have three confident-wrong values left, all totals, and `RV.56` is in flight against
them. Everything else in the receipt class is an honest abstention.

---

## Track A - receipts: finish the job

**A1. `RV.56`, in flight.** The zero-operand guard (a live trap: with a real user's price history
the ladder currently returns *0.00 litres at 30.61* on a contract fuel card), the fiscal QR wired
into the scored path, and the total finder's three named bugs. Expected ~+6 cells and **no
confident-wrong value left except the mixed-receipt total**.

**A2. The decimal-format decision - yours, not mine.** Two of three analysts propose resolving an
unmarked operand pair by decimal format (deepseek: exactly three decimals plus a magnitude window,
+10; kimi: decimal count against the currency's price convention, +14). Qwen refuses the whole
family as the tie-break `HIGH-WATER.md` removed after it swapped `receipt-007` with every check
green. I verified both proposals abstain on 007, 008, 012, 025 and 029, so they are narrower than
the banned rule - but they still infer role from format, and a swap is the one error class nothing
downstream can catch. **Decide explicitly; do not let it arrive by implementation.**

**A3. Prove ladder step 3.** The user's price history is implemented, injected in the app, and
**unprovable by the corpus** - a fixture has no prior fill-ups. Eight of the remaining misses
(receipts 025, 029, 040, 041) are correct abstentions that history exists to resolve. An L1 test
injecting a median and asserting those pairs resolve closes the gap between "shipped" and "known to
work". Qwen's structural finding belongs here: resolving a pair needs the median inside
`(2.5 x smaller, 2.5 x larger]`, which for `receipt-008` is a window 0.22 roubles wide - an oracle,
not a user. Five fixtures are permanently beyond history, and that is the shape of the ceiling.

**A4. A secondary currency tier.** `receipt-035` and `-041` carry no fiscal furniture;
`Топливная карта` / `ОСТАТОК ЛИМИТА` appear on no Estonian or Kazakh fixture. +2 cells, and
currency unlocks the band, so `-035`'s pair may follow.

**Receipt ceiling: ~188-190/220 deterministically.** The rest are abstentions by design.

---

## Track B - pumps: fix the instrument before the algorithm

**B0. The number everyone quotes is wrong.** Of the 261 scored cells, currency (66) is read from a
printed `€`/`РУБЛИ` marker and is nearly free, and `fuelKind` (17) is a column
`docs/EXTRACTION.md` says a pump parser must **never** fill - yet the parser emits grade guesses
and is scored on them. On the three numbers the mode exists to read the score is **4/178 (2.2%)**
and the arithmetic cross-check passes **0/66**.

**B1. Re-scope the gate. This comes first and is cheap.** Score the 178 numeric cells; stop scoring
`fuelKind`; and re-base `PumpPhotoGate` from **recall** to **precision on committed fields plus a
coverage floor**. The reason is not presentation: recall scores a correct `nil` as a miss and a
confident-wrong as a hit, which inverts hard rule 13 - and the two idle pumps' ground-truth zeros
mean recall actively rewards logging a zero-litre fill, the exact bug hard rule 15 forbids. All
four analysts reached this independently.

**B2. The tokenizer, then a pump-shaped ladder. This is the free win.**
`NumberScanner.decimals(in:)` requires a `[.,]` separator, so `12522` is not merely mis-scaled -
it is **discarded**, and the digits Vision read at confidence 1.00 never reach the parser. Verified
in the source. Beyond it, the pump path is the *receipt* parser with two switches: it wants an `×`
operator, an `L` marker and an `ИТОГ` label, and a pump prints three bare numbers under three
labels. The ladder: separator-liberal tokens, decimal-scale search pinned by the price band and
tank capacity, label and make anchors (the make logo and field labels survive in nearly every dump
- the cheapest accuracy available), then the existing cross-check and digit repair, then
abstention. Kimi's estimate: **~4/178 → ~110/178 on the OCR text that already exists.**

**B3. MEASURED AND CLOSED, 2026-09-05** (`diagnostics/RESEARCH-pump-B3-crop-experiment.md`). Run
over all 66 fixtures: of 148 separator-less digit runs, a crop recovers a separator on 19 and the
CORRECT value on only 7, while producing ten wrong ones - several off by a factor of ten, which is
the error class the cross-check cannot see. Upscaling is strictly worse (7 correct at 1x, 5 at 2x,
4 outright regressions): interpolating a seven-segment glyph invents edges that were never
photographed. Both analysts were half right - the separator IS in the pixels, and it is recovered
by ISOLATION at 1x rather than by resolution. **Do not build it as a recogniser.** A 1x crop is
usable only as a candidate generator for B2's scale search, where the arithmetic validates the
reading instead of the reading being believed, and only after the ladder is finished.

**B4. Refusal behaviours, which earn no cells and matter anyway.** An idle pump, a display still
holding the previous customer's transaction, and a factor-of-ten tie must be **refused**, not
logged. This is what makes a precision gate meaningful.

**B5. Then, and only then, re-ask whether the mode ships.** A perfect reader tops out at ~96.6%
(three fixtures' ground truth was read off the pump, not off the photo) and ~91% once the product's
own correct abstentions are counted as misses. Kimi: *"A mode that pre-fills four fills out of five
and never writes a wrong digit is worth shipping; calling that 95% was never what the 95% was for.
Do not lower the bar to open it."*

---

## Track C - plumbing, so the gains reach a user

**C1. `RV.57` (filed by the other session): after a capture, go straight to the entry view
pre-filled with what local recognition got.** This is the consumer of everything in Track A. An 82%
parser that the user never sees the output of is worth what a 38% one was.

**C2. `RV.62`: expense capture runs the fill-up recogniser and throws the result away.**

**C3. Check the corpus harness's image orientation.** `VisionTextRecognizer.recognizeText(in: url:)`
passes no orientation, while the in-memory path beside it takes one explicitly, citing RV.49. One
analyst reports `pump-001` arriving rotated and losing two decimal points. If the harness is
feeding Vision rotated images, today's baselines measured a handicapped reader.

**C4. Pin the Vision revision.** `VNRecognizeTextRequest` is unpinned, so every recorded high-water
mark silently depends on Apple's OCR version and can move under a system update.

---

## Track D - hygiene

**D1. An id collision, mine - resolved.** I used `RV.57` and `RV.58` for research briefs while the
other session filed real rows under those ids on trunk (RV.57 is the capture-to-entry-view
requirement, RV.58 a corrected data-leak filing). The research artefacts are now named
`RESEARCH-receipt-options-*` and `RESEARCH-pump-*` - **out of the RV id space entirely**, because
research is not a task and should never have claimed a backlog id. Task rows for the work below get
fresh ids when they are filed.

**D2. DONE 2026-09-05.** The stale corpus numbers are refreshed everywhere they are a LIVE claim:
hard rule 15 in `CLAUDE.md`, `docs/JOURNEYS.md` (J3b's "why this is a journey"), `docs/VISION.md`
and `docs/SITE.md`. Each keeps the old figures visible as the "before", because the interesting
fact is that the rule survived a 37-point improvement: the argument is no longer "scanning mostly
fails" but "scanning is usually a good head start and is never the whole entry". `SITE.md` also
gains the new temptation in writing - 85% is a good number to boast with and is not a promise that
a scan finishes the job. Historical task rows are deliberately NOT rewritten: they record what was
known when the decision was taken.

**D3. DONE 2026-09-05.** `docs/EXTRACTION.md`'s measured-reality section now carries the per-class
table, the pump gate's re-scoping, and the two things measured and closed so they are not
re-proposed (recognition knobs for receipts, and B3).

---

## Sequencing

1. **A1** lands and is verified (in flight).
2. **D1** rename, then commit the seven analyses - they are the evidence base for everything above.
3. **B1** re-scope the pump gate. Cheap, and it stops the next measurement lying.
4. **B2** the tokenizer and the pump ladder - the single largest gain available anywhere, ~+106
   numeric cells, no new technology.
5. **A3** and **C3** in parallel: both are checks on things believed to work.
6. **B3** the crop experiment, then **B4**, then **B5** the ship decision.
7. **A2** whenever you decide it; **A4**, **C4**, **D2**, **D3** as they fit.

**What not to do**, on which all seven analyses agree: no trained model on 46 receipts (the corpus
is the test set), no second on-device OCR engine (PaddleOCR measured worse), no confidence
thresholds (Vision misreads at confidence 1.00), no image preprocessing for *receipts* (every glyph
already arrives at confidence 1.00), and no chasing the corpus number by loosening a tolerance or
snapping a misread grade.
