# The extraction plan: receipts, pumps, and the plumbing between them

Written 2026-09-04 from the day's measurements and seven independent agent analyses
(`diagnostics/RESEARCH-receipt-options-{qwen,kimi,deepseek}.md` and
`diagnostics/RESEARCH-pump-{vision,kimi,pro,qwen}.md`).

## Where it stands tonight

| class | this morning | now | note |
|---|---|---|---|
| receipts | 101/210 (48%) | **180/220 (82%)** | 4 commits; 61% of receipts fully correct |
| fiscal | 2/5 | 5/5 | |
| screenshots | 27/40 | 34/40 | |
| pump | 51/251 (20%) | 53/261 (20%) | **and the 20% is not the real number - see B0** |

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

**B3. Then measure the crop experiment.** The two analysts who opened the photographs disagree
about whether cropping the LCD window and upscaling recovers the decimal point - same fixture,
opposite conclusions. It is an afternoon: crop `pump-005`'s total window, upscale, re-run Vision,
see whether the dot returns. **Measure; do not arbitrate by argument.** Worth ~+20 cells if it
works, nothing if it does not.

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

**D2. Hard rule 15 quotes stale numbers.** `CLAUDE.md` still says *"receipts extract at 38.3%, pump
displays at 0%"*. Receipts are 82% and pump's honest figure is 2.2% on numeric fields. The rule's
*conclusion* is unchanged - typing stays a peer path - but a hard rule citing numbers that are two
and a half times off invites someone to relitigate it on stale evidence.

**D3. `docs/EXTRACTION.md` measured-reality section** needs the 180/220 figure and the pump
re-scoping.

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
