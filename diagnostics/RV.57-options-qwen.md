# RV.57 – Options for raising on-device receipt recognition (qwen arm)

Research only. No code changed, nothing run. Score basis: `diagnostics/receipt-field-report.txt`
(173/210 cells, 28/46 receipts fully correct, 37 misses across 18 fixtures) read against
`diagnostics/receipt-ocr-lines.txt` (raw Vision dump of all 46 receipts) and the live parser in
`ios/Sources/TankbookCore/Extraction/`.

## 0. What I actually read

Read in full: both diagnostics files; `Spike/ReceiptSpike/fixtures/HIGH-WATER.md`; the complete
`_note` history in `high-water.json`; `Spike/ReceiptSpike/fixtures/receipts/README.md`;
`docs/EXTRACTION.md`; `CLAUDE.md` hard rules; the `.qr.txt` sidecars of every miss fixture that
has one (002, 007, 008, 012, 017, 018, 025, 027, 029); `expected.csv` conventions; and the code:
`FuelExtractor.swift`, `CrossCheck.swift`, `CurrencyDetection.swift`, `FuelKindNormalizer.swift`,
`ReceiptNoiseFilter.swift`, `FuelPriceBandProvider.swift`, `FuelPriceBands.seed.json`,
`VisionTextRecognizer.swift`, `ExtractionAssembler.swift`, `FiscalQR.swift` (incl.
`FiscalQRCrossCheck`, `FiscalQRAnchor`), `ConfirmPrefill.swift` (`ConfirmQRTotal`),
`AppFuelPriceBand.swift`, `CapturePipeline.swift` (language list, QR wiring).

I did not see the fixture images (no image input in this session): my claims about "what the
paper prints" are read from the OCR dump and the README's human-verified notes, and I say so where
that matters. I reverse-engineered three miss mechanisms from dump + code (sections 1.3, 1.4);
those are inferences from geometry, marked as such.

## 1. Anatomy of the 37 misses

The split that matters is not "OCR vs parser" but six distinct causal classes. Every one of the
37 misses is exactly one of them (24 + 4 + 3 + 3 + 1 + 2):

### 1.1 Band-ambiguous operand pairs – 24 cells, the dominant class

The operand line was read perfectly (conf 1.00 in every case) and the ladder abstained because
both operands fall inside the curated band, or a gate the band needs is nil:

| fixture | pair (as OCR'd) | why nil |
|---|---|---|
| 002, 018 | `450.00*43.820` | both in RUB petrol 2024+ band [40,500] |
| 007 | `43.61 Х 99.40` | both in band |
| 029 | `43.24 Х 58.51` | both in RUB 2018–2023 band [35,100] |
| 008 | `48.89 Х 48.80` | both in band; ratio 1.002, the corpus's honest-undecided case |
| 012 | `52.15 Х 23.99` | LPG band [15,60] contains BOTH by design (seed.json note) |
| 040 | `71.18 x 57.000` | both in band; ratio 1.25 |
| 025 | `43.38 Х 38.28` | multi-pair guard first (`OperandPair.single` refuses: the `69.28 X 1` service line precedes it), then both in the 2019 band [35,100] |
| 027 | `30 Х 70.05` | band blocked upstream: fuelKind nil (`АИ-96-К5` → `kind(forOctane: 96)` = nil), and `DefaultFuelPriceBandProvider.band` requires a kind (FuelPriceBandProvider.swift:77-79) |
| 035 | `70.44 X 39.000` | band blocked upstream: currency nil (fuel-card slip, no fiscal furniture), and band requires a currency |
| 041 | `68.44 X 54.000` | same as 035; and even with RUB the pair is both-in-band (ratio 1.27) |
| 043 | `40 Х 120.00` | band blocked upstream by the garbled fuelKind (1.2) – and moot, since 40 and 120 are both in [40,500] anyway |

These are the ladder working, not failing. `a x b == b x a` means nothing on the receipt can order
them; the abstentions are correct. The question is only what *outside* evidence (user history, QR,
car context) legitimately exists. Section 2 ranks those; section 3 names which pairs no outside
evidence in the product can reach either.

### 1.2 Garbled fuel-grade lines – 4 fuelKind cells

All four are recognition-layer damage, and all four were deliberately left nil:

- **027** `ЭКТО Plus (АИ-96-К5), л` – Vision misreads 95 as 96 at conf 1.00 (HIGH-WATER stage one,
  named). Not snapped to 95: resemblance.
- **042** `) BC` + `miles` on two lines – `D B0 miles` garbled AND line-split; `circleKLoyaltyGrade`
  needs `MILES` and `D B[0OÓ]` on one line (FuelKindNormalizer.swift:131-144).
- **043** `ДИ-95 (1 ТРК)/ *4 e1_news` – А→Д smear under the watermark badge, no -К5 on the line, so
  `corroboratedSmearedOctane` (which requires the suffix) does not fire.
- **044** `AM-95` – И→M smear, no -К5 (non-fiscal slip), abstains by the same rule.

### 1.3 The total-finder's modal tie, poisoned by stray label pairings – 3 nil totals

Reverse-engineered from the dump's geometry plus `grandTotal`/`pairedValue`/`modal`
(FuelExtractor.swift:304-373):

- **001**: the `Summa` header (y=0.731, x=0.616) pairs same-baseline to its right with the
  quantity `1` (y=0.721, x=0.675, Δy 0.010 < 0.012), not with `125,22` (Δy 0.018 – outside the
  pairing window). `KOKKU` pairs with `100,98` (the VAT-exclusive). Candidates {1, 100.98} tie,
  both primary-labelled, `modal` abstains on an unbreakable tie → nil. The true total `125,22`
  is printed three times and never pairs with any label.
- **038**: first `Summa` (y=0.751) pairs with `79,32` ✓, but the second `Summa` (y=0.730, x=0.453)
  pairs with the VAT amount `15,35` (same baseline, x=0.475). Candidates {79.32, 15.35} tie →
  abstain → nil. `KOKKU`/`KK MAKSE` find no same-baseline value.
- **041**: the total label itself is destroyed – OCR reads the ИТОГ row as `*O:` (y=0.438) – so no
  label classifies and `grandTotal` has zero candidates, while `=3695.76` is printed twice.

### 1.4 The two confident-wrong totals, and the third – 3 wrong values

- **017** got 961.80, want 961.00. Geometry: `ИТОГ:` (y=0.661, x=0.237) pairs same-baseline with
  `=961.80 РУБ` (y=0.661, x=0.623) – the pre-discount extension – while the charged `=961.00 РУБ`
  (y=0.642) is 0.019 below the label and outside the pairing window; it only pairs with
  `НАЛИЧНЫМИ:` (a payment label). `modal` then prefers the sole primary-labelled candidate:
  961.80. The receipt's own `СКИДКА =-0.80 РУБ` line is the evidence that separates the two, and
  the parser never uses it in the total finder. The QR sidecar agrees with the truth: `s=961.00`.
- **018** got 3555.89, want 19719.00. Same mechanism: `ИТОГ` (y=0.570) pairs with `-3555.89`
  (y=0.563) – which is the receipt's VAT amount (19719 × 22/122 = 3555.89) sitting in the value
  column – while `=19719.00` pairs only with `НАЛИЧНЫМИ`. Primary label wins → the VAT figure is
  returned as the total. (Inference: I could not reproduce every pairing distance from the dump
  alone, but the candidate set that produces the reported value is exactly this one.) The QR says
  `s=19719.00`.
- **025** got 1729.87, want 1660.59. Not a mispairing: 1729.87 IS the receipt's ИТОГ, correctly
  read. The miss is hard rule 4 – on this mixed receipt (service `69.28 X 1` + fuel) the fuel
  amount is the fuel line's own `#1660.59 РУb`, printed on the fuel pair's baseline (y=0.601 vs
  the pair's y=0.604). Reaching it requires the fuel line to be identified first, which the
  multi-pair guard currently refuses.

### 1.5 The zero-price shape – 1 cell

- **034** `30.61 Х 0.00` under "Цена определена договором": both operands outside the band
  (30.61 < 40, 0.00 < 40) → abstain. The volume is recoverable in principle (section 2, option 3).

### 1.6 No currency evidence on the document – 2 cells

- **035** and **041**, both fuel-card slips: no ₽/РУБ word, no fiscal furniture (ИНН/ККТ/ОФД/ФН),
  no QR. `CurrencyDetection` returns nil exactly as designed ("where the document does not say,
  nil"). These two are the residue the RUB evidence gate's own write-up predicted
  (CurrencyDetection.swift:28-31). Each nil currency also blocks the band for that slip's operand
  pair, which is how one missing cell cascades into three (041) – see 1.1.

Two cross-cutting facts the code inspection added:

- **The app already does better than the gate for returning users.** `CaptureView` injects
  `AppFuelPriceBand.provider(vehicleId:)`, which builds a `FillUpHistory` from the vehicle's own
  fill-ups (AppFuelPriceBand.swift:17-22). The corpus scorer injects the band pack only
  (high-water.json, stage two note). So 173/210 is a **first-launch number**; ladder step 3 is
  live code in the app and dead code in the measurement.
- **The QR-total fusion already exists in the app** (`ConfirmQRTotal.resolve`): on disagreement
  the QR total fills the field. It fixes 018 today (|19719.00 − 3555.89| → `.disagrees`), but it
  does NOT fix 017: `FiscalQRCrossCheck.tolerance` is 1 ₽ and |961.00 − 961.80| = 0.80 classifies
  `.agrees`, so the wrong OCR value stands. 025 is `.suggestsMixedReceipt` → `fuelLineStands(ocrTotal)`
  → 1729.87 stands (operands nil, so the computed fuel line falls back to the OCR total).

## 2. Ranked options

Ranked by expected gain per cost and risk. Gains are counted per fixture and per field from the
report; every number is traceable to section 1.

### Option 1 – Discount-aware, arithmetic-anchored total selection (parser)

(a) **What.** Extend `resolveTotal`/`grandTotal` (FuelExtractor.swift:276-315). When both operands
are resolved, compute the product P at exact Decimal. Then, before falling back to the modal
label pairing:

1. collect the document's discount lines (`ExtractionCrossCheck.discountLines` already exists and
   already handles СКИДКА/EXTRA SOODUS/ОКРУГЛЕНИЕ-adjacent values);
2. build targets, in precedence order: `P − d` for each printed discount d, then `P`;
3. scan BOTH the label-paired candidates and the bare value lines (noise-filtered) for values
   matching a target within the shared `ConfirmConfidenceGate.crossCheckTolerance`;
4. if the highest-precedence target with any match has matches, return the modal one; otherwise
   fall through to the existing modal label pairing unchanged. The mixed-receipt fuel-line branch
   (hard rule 4, `printedFuelLineAmount`) keeps its existing precedence over all of this.

The precedence of `P − d` over `P` is the 017/038 distinction stated once: where the receipt
prints a discount and a charged figure matching it (017: 961.80 − 0.80 = 961.00, printed twice),
the charged figure is the total; where the discount is printed but not subtracted (038: EXTRA
SOODUS −0,23 with KOKKU still 79,32 = P; README §receipt-038), no `P − d` candidate exists and
`P` wins. That is the residual-driven logic the cross-check already uses (EXTRACTION.md §5), moved
into the total finder.

(b) Layer: parser.
(c) **Gain, counted.** +3 deterministic: 001 total (bare `125,22` = 67.00 × 1.869), 038 total
(bare `79,32` = 45.22 × 1.754), and 017 total flipped from confident-wrong 961.80 to 961.00
(`=961.00 РУБ` printed at y=0.642/0.602 matches P − 0.80). It is also the enabling half of the
018/025/041 totals: each becomes recoverable the moment its operands are (their correct totals are
all printed: `=19719.00` ×4, `#1660.59 РУb`, `=3695.76` ×2).
(d) Cost: ~1 day including tests; the parts exist (discountLines, NumberScanner, tolerance). Zero
runtime cost beyond one pass over lines already in memory; nothing new on an iPhone 12.
(e) Wrong-answer risk: ≈ zero, and this is why it ranks first. A value wins only if it is printed
on the document AND equals the product of two ladder-resolved operands (or that product minus a
printed discount) within the shared tolerance. A coincidental match would require an unrelated
printed figure to equal liters × price to the cent. Abstains (falls to today's behaviour)
whenever operands are unresolved – it can never fire on the 24 nil-pair cells of class 1.1.
Regression check against current HITs with known operands: 003/004/005/006/009/011/013/014/016/
022/023/028/030/031/032/033/036/037/044/045/046 all have a printed candidate at P within the
shared tolerance – including the display-rounding cases 033 (prints 6000.00, P = 5999.67) and 045
(prints 51.71, P = 51.6997; the README's one-cent lesson), where `max(0.02, 0.5%)` absorbs the
gap and the rule selects the same value the document states. Where NO printed candidate matches P
the rule abstains to today's modal behaviour – additive only, never a replacement of a resolving
path.
(f) Generalises: yes – the mechanism it fixes (a label pairing with a stray same-baseline value,
modal tie, abstention or wrong primary) is a property of dense thermal headers, not of Circle K or
Татнефть. Any receipt where both operands resolve and the total is printed benefits; receipts
without a matching printed value keep today's behaviour.

### Option 2 – Make the QR total authoritative at extraction time (other evidence)

(a) **What.** Two concrete changes. First, pass the decoded QR anchor into the extractor's total
decision (today it is consumed only in `ConfirmQRTotal`, i.e. after the scored extraction): when a
QR anchor exists and the receipt is not mixed, the printed candidate matching the QR `s=` value is
the total; when no OCR candidate matches it, the QR value fills the field outright (it is the
fiscally registered charged amount). Second, fix the one-line semantics hole in
`FiscalQRCrossCheck`: `.agrees` within 1 ₽ currently lets 017's 961.80 stand against the QR's
961.00; the QR is exact by construction, so on agrees-with-difference the QR value should win (or
the tolerance should drop to 0 with whole-rouble rounding handled by option 1's discount target –
either fix is one line).
(b) Layer: other evidence (fiscal QR – already detected by `CaptureQRDetector`, already parsed by
`FiscalQRParser`; only the fusion point moves).
(c) **Gain, counted.** +1 deterministic on this corpus (018 total: the extractor itself returns
19719.00 instead of 3555.89; today only the app layer fixes it). 017 total also comes out right
at extraction time (overlaps option 1 – count once). Additionally converts every future
VAT-line/rounding-line total mispairing (the class that bit 002 in the 2026-08-25 README baseline)
from wrong to correct whenever the QR decodes. No operand gain: I verified all nine miss fixtures'
sidecars – the QR format on this corpus carries `t`, `s`, `fn`, `i`, `fp`, `n` only. No quantity,
no price, no item name. `FiscalQRAnchor` documents exactly this (liters/unitPrice/fuelKind are
nil "always"). The brief's "carries 2 of the 5 fields" is total + date, and date is not a scored
cell.
(d) Cost: ~half a day; the parser, detector and anchor exist. Runtime: none added (QR detection
already runs in the capture pipeline, CapturePipeline.swift:59).
(e) Wrong-answer risk: zero for the total – the QR is the fiscal register's exact figure, the
strongest evidence class on the document. One boundary: on mixed receipts the QR carries the GRAND
total (025's sidecar is `s=1729.87`, which is precisely NOT the fuel amount), so the hard-rule-4
fuel-line exemption must stay in front of the QR override – `ConfirmQRTotal` already does this and
the extractor fusion must copy that order.
(f) Generalises: to every Russian ФН-1.2 fiscal receipt whose QR decodes – measured presence is
9 of 16 fiscal receipts in the corpus, and absent by class on fuel-card slips (016/023/035/036/
040/041/044) and non-ФНС receipts (all EE, KZ). It cannot help where no QR is printed, which is
why it ranks below option 1 despite stronger evidence.

### Option 3 – The zero-operand guard and the contract-volume rule (parser)

(a) **What.** In `resolveOperands` (FuelExtractor.swift:185-213): when exactly one operand of the
pair is 0.00, treat the zero as the price (contract pricing – "a printed zero is not a value" is
already the code's own doctrine, FuelExtractor.swift:48-62) and resolve the non-zero operand as the
volume ONLY when the product line declares the unit – 034 prints `Plus (AИ-95-К5), л` (a unit
declaration stranded from the pair by the line layout) and the words "Цена определена договором".
Price stays nil; total stays nil (it is 0.00 → nil already). Additionally, add a zero-liters guard
mirror of the existing zero-total/zero-price guards: `extract()` currently nils a zero total and a
zero unit price but NOT zero liters – which matters because of the trap below.
(b) Layer: parser.
(c) **Gain, counted.** +1: 034 liters = 30.61. Its real value is the trap it closes: ladder step 3
(user history) is live in the app, and `resolveUnmarked` with a realistic median m ≈ 65 evaluates
034 as leftPlausible(|30.61 − 65| = 34.4 ≤ 39) vs rightPlausible(|0 − 65| = 65 > 39) → returns
**(liters 0.00, price 30.61)** – a confident wrong swap with a zero-liter fill, which no guard
currently catches. This option must land BEFORE any change that exposes history to the scorer, and
is cheap insurance regardless.
(d) Cost: hours, with tests.
(e) Wrong-answer risk: nil-output by construction unless the unit is declared on the product line;
the only asserted value (volume) is the non-zero operand of a pair whose other member is a printed
zero. The abstention alternative is today's behaviour.
(f) Generalises: fleet/contract card receipts are named in the README as "a whole class … common
across RU/KZ", not an anomaly. The zero-guard is universal.

### Option 4 – Measure and document the history step that already ships (other evidence)

(a) **What.** Not new code – the provider is wired (AppFuelPriceBand.swift). Two deliverables:
(1) a written per-fixture resolution condition for every class-1.1 pair, derived from
`resolveUnmarked`'s actual rule (exactly one operand inside [0.4m, 1.6m] of the user's median m in
that currency):

| fixture | resolves when | realistic? |
|---|---|---|
| 002, 018 (450/43.82) | m ∈ [281, 1125] | yes – for the Crimean АИ-100 regular (m ≈ 450) |
| 012 (23.99/52.15, LPG) | m ∈ [15, 32.6) | yes – LPG 2023 m ≈ 24 |
| 027 (70.05/30) | m ∈ (75, 175] | borderline – needs a m > 75 RUB/L driver |
| 007 (99.40/43.61) | m ∈ (109, 248] | no at typical АИ-100 prices (~90-105) |
| 008 (48.89/48.80) | m ∈ (122.0, 122.2] – a 0.22 ₽ window | never for a real user |
| 025 (43.38/38.28) | never via this path – the multi-pair guard fires first | never |
| 029 (58.51/43.24) | m ∈ (108, 146] | no |
| 040 (71.18/57.00), 041 (68.44/54.00) | m ∈ (142, 178] / m ∈ (135, 171] | no at 2026 prices |

(2) L1 unit tests of `resolveUnmarked` with synthetic histories (never added to the ratchet – a
synthetic history chosen to pass fixtures is fitted data; the ratchet stays the first-launch
number, and that reframing belongs in HIGH-WATER.md).
(b) Layer: other evidence (user's own data – ladder step 3, no network, hard rule 1 safe).
(c) **Gain, counted.** Conditional, per the table: +2 (012) for a returning LPG user; +4
(002 + 018 operands) for the Crimean АИ-100 user; +2 (027) for a high-median driver. On the
recorded corpus number: zero, by construction – the corpus has no user, and fabricating one to
raise the ratchet is the overfit this brief warns against. The honest statement: **the app's
returning-user accuracy on these fixtures is up to 8 cells above the gate, and the inequality
table above is exactly which users gain what.**
(d) Cost: an afternoon (docs + L1 tests). Runtime: none new.
(e) Wrong-answer risk: the rule's own – it can swap when the user's median sits pathologically
(catches both operands or neither → abstains; the asymmetric case is the swap). The ±60% window
means a swap needs the true price outside [0.4m, 1.6m] of the user's own median – unlikely for a
repeat customer of the same chain, which is precisely where it fires. Option 3's zero guard is a
prerequisite.
(f) Generalises: by construction it is the only evidence source here that is ABOUT the user rather
than the corpus – it cannot overfit to receipts it has not seen, it ignores them. Its failure mode
is a genuine price jump (new region, new grade), which the [0.4m, 1.6m] window absorbs or abstains
on.

### Option 5 – Grade vocabulary at the recognition layer: customWords, measured first (recognition)

(a) **What.** `VNRecognizeTextRequest.customWords` (iOS 15+, floor is 18) is the one untried knob
with non-zero expected gain. Add the real grade vocabulary – АИ-92/АИ-95/АИ-98/АИ-100, ДТ, the
-К5 suffix, `D B0 miles`, `95E0 miles` – and re-run the 46-receipt corpus through Vision
(the dump harness exists: `TANKBOOK_WRITE_CORPUS_FILES=1 TANKBOOK_DIAG_OUT=<dir> swift test
--filter ReceiptFieldDiagnostics`, per high-water.json stage one). Nothing ships until the dump
shows what Vision actually does with the bias, per fixture. The decision it forces, and why it is
a product call and not a parser tweak: a vocabulary bias makes Vision prefer catalog grades over
what the ink says. On 027 that recovers the truth (the paper says 95, Vision reads 96 at conf
1.00 – the README's human-verified reading). On a hypothetical receipt truly printing a
non-catalog grade (the ink of 027 said "96" until a human overruled it), the same bias fabricates
a 95. That is resolution-by-resemblance moved from the parser into the recognizer; HIGH-WATER.md's
verdict was about the move, not the layer. The parser's corroboration rules (-К5 suffix, loyalty
grade patterns) stay exactly as they are – customWords is allowed to improve what Vision reads,
never to relax what the normalizer accepts.
(b) Layer: recognition.
(c) **Gain, counted – upper bound, and unknown until measured.** If the bias flips the four
garbled reads: 027 fuelKind +1 AND its operands unlock (band [40,500]: 30 out, 70.05 in →
resolves) +2 = +3; 042 fuelKind +1; 044 fuelKind +1; 043 fuelKind +1 (its operands stay nil –
40 and 120 are both in band). Total ≤ +6, plausibly +1..+3 if Vision's conf-1.00 readings don't
move (conf-1.00 misreads resisting customWords is a documented Vision behaviour on this corpus's
pump class, and I cannot predict it from a text dump). **Measure in an afternoon** with the
existing harness; the gate is "no fixture that reads a real grade today changes its reading".
(d) Cost: ~1 day including the A/B dump and tests; runtime zero (same single Vision pass).
(e) Wrong-answer risk: the systemic one named above – catalog-biased readings of genuinely unusual
grades, at high confidence, surviving every downstream check. Mitigation is the unchanged
normalizer plus the A/B gate; residual risk is why this sits below the zero-risk options.
(f) Generalises: the vocabulary is country/chain-independent (it is the retail grade catalog);
the risk generalises too. It helps any receipt whose grade line is garbled, which is a recurring
thermal-print class (И-smears on 018/032/043/044 are four instances in 46 receipts).

### Option 6 – Second-pass re-recognition of a field region (preparation + recognition)

(a) **What.** Crop the image to a region of interest, upscale 2–4×, re-run the same recognizer,
and reconcile against the first pass. The geometry plumbing already exists: RV.48 persists
per-field crop rects (`ExtractionAssembler.cropRects`, Vision-normalised boxes of the source
lines). Two concrete uses: (i) unresolved grade lines (042's `) BC` row, 043's watermarked row,
044's `AM-95`, 027's `АИ-96`) get a targeted second pass – optionally with option 5's customWords;
(ii) a disagreement between passes on any value line downgrades that value to nil (an
anti-confidence use: more honest nils, never more guesses).
(b) Layer: preparation/recognition.
(c) **Gain: unknown for receipts, and I say so.** Every operand value in class 1.1 was read at
conf 1.00 at full resolution – a second pass over the same pixels has no measured deficit to
repair there, and I expect zero operand gain. The grade rows are the only candidates, and they
share option 5's uncertainty (a crop changes Vision's segmentation and context, which CAN flip a
reading, but the dump cannot tell me whether it will). Measurement: same afternoon harness as
option 5, cropping each unresolved grade line's box from the fixture original. Note the crop-rect
map currently only covers RESOLVED fields (ExtractionAssembler.swift:70-71) – unresolved-line
rects are one small addition, since `OperandPair`/product-line indices are known regardless.
(d) Cost: ~1 day. Runtime on an iPhone 12: one extra Vision pass per targeted crop, tens of ms at
crop size – acceptable gated to unresolved fields only; never a blanket double-pass.
(e) Wrong-answer risk: the disagreement variant reduces it (two independent reads disagree → nil).
The agreement variant inherits option 5's risk when combined with customWords.
(f) Generalises: the technique does; the gain is unproven. For the pump class (51/251, recognition-
bound) the same mechanism has a real measured deficit to attack – but that is behind its own flag
and outside this question's score.

### Option 7 – Structural fuel-line attribution on multi-pair receipts (parser)

(a) **What.** Replace `OperandPair.single`'s all-or-nothing guard with row attribution: a product
row that carries a detected fuel-grade token (025's `ТРК-2 АИ-95-К5`) owns the operand pair on the
following line(s) before any other pair is considered; the service row (`Услуга по регистрации
покупки / 69.28 X 1`) then cannot be read as the fill. Combine with same-baseline row-extension
reading (the fuel pair's own `#1660.59 РУb` at x=0.661 on its baseline) so option 1's fuel-line
precedence has a printed amount to take.
(b) Layer: parser.
(c) **Gain, counted: +1 (025 total) via options 1+7 together; the operands stay nil.** The fuel
amount 1660.59 is printed on the fuel pair's own baseline (`#1660.59 РУb` at y=0.601 vs the pair's
y=0.604), and the pair's product 43.38 × 38.28 = 1660.59 confirms it – commutative, so the
confirmation needs NO operand-order resolution. If row attribution names `ТРК-2 АИ-95-К5`'s row as
the fuel line, option 1's arithmetic anchor can take that printed amount as the fuel total. One
caveat: the existing `printedFuelLineAmount` (CrossCheck.swift:113) reads the line ABOVE the pair,
which here is the grade text, not the value – so this also needs a same-baseline row-extension
read. The 025 liters/unitPrice remain unreachable (both in the 2019 band, ratio 1.13 defeats any
realistic history median). Option 7's real value beyond the +1 is preventive: it removes the class
where a future band/history improvement is structurally unreachable, and it is the prerequisite if
item-level QR ever lands.
(d) Cost: ~1 day; geometry-heavy, needs the same-baseline machinery the total finder already has.
(e) Wrong-answer risk: moderate and must be stated – "the pair below a grade line is the fuel" is
document structure (receipts print name-then-amount), but a non-fuel item printed directly under a
fuel row would misattribute. Guard: fire only when exactly one grade-tagged row has an adjacent
pair, and keep the cross-check's mixed outcome in the loop.
(f) Generalises: multi-item receipts with a fuel row are common (009 and screenshot-008 are the
class, both resolved today by the `л` marker – this option covers the unmarked variant). Worth
building only together with option 1; ranked on honesty, not score.

### Option 8 – Car-context defaults for currency and fuel kind (product layer, not extraction)

(a) **What.** 035 and 041 are fuel-card slips with no fiscal furniture and no currency word –
CurrencyDetection correctly returns nil ("where the document does not say, nil"). The app, however,
knows the car: its home currency and its powertrain/fuel catalog. Rule 13 already blesses this as
a *default input*: pre-fill RUB from the car's country, pre-fill the car's fuel kind – each
editable at confirm time and afterwards. 042's diesel and 044's petrol95 are the same shape: the
document is silent, the car is not.
(b) Layer: other (product); deliberately NOT the parser – an extractor that emits car-context
values would score them as read facts, which they are not.
(c) **Gain, counted – as suggestions, not extractions.** 035: currency +1, then the band unlocks
(39.000 < 40 ≤ 70.44 ≤ 500 → exactly one in band) → liters +1, unitPrice +1 = +3. 041: currency +1
(operands remain abstained – both in band, ratio 1.27). 042/044 fuelKind: +2 as car defaults –
the SAME two cells option 5 targets from the recognition side, so count them once, not twice.
Whether these count toward the 210 is a scoring convention question the report should decide
explicitly (a suggested-and-confirmed value vs an extracted one); I count them separately here.
(d) Cost: small app-side change; no engine change.
(e) Wrong-answer risk: a RU-registered car filling abroad (KZ, BY) gets a wrong currency default;
a diesel car misfuelled petrol gets a wrong kind default. Both are editable suggestions at confirm
(rule 13), which is the designed containment – but this is exactly why it must stay out of the
extraction score.
(f) Generalises: completely – every no-evidence slip gets a coherent default instead of blanks,
for all slips everywhere. That is its point.

### Option 9 – The remaining recognition knobs, as an afternoon A/B (recognition)

(a) **What.** `VisionTextRecognizer` pins nothing: revision (latest), `recognitionLevel`
(.accurate – already max), `usesLanguageCorrection` (off, deliberate, documented), language list
(`["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]` – no `et-EE` despite six Estonian fixtures, no
Kazakh), `minimumTextHeight` (default), `customWords` (unused – option 5). The corpus verdict on
each: no miss in the dump is attributable to any of them. Every value the parser needed was read
at conf 1.00; the Estonian fixtures' misses are the modal tie (1.3) and the `) BC` garble (1.2),
not Estonian glyphs; receipt-033 (KZ) is 5/5 without a Kazakh language entry. The one real finding
is determinism, not accuracy: an unpinned revision means the ratchet can move when Apple ships a
new Vision – pin the revision and record it next to the high-water mark.
(b) Layer: recognition. (c) Gain: expected 0 on this corpus; unknown-by-measurement elsewhere –
re-run the 46-fixture dump with `et-EE` added and the revision pinned; half a day.
(d) Trivial. (e) Zero (language lists don't invent values; pinning removes variance).
(f) The pin generalises (reproducibility); the language addition is a no-op until a corpus miss
demands it.

### Option 10 – Image preparation (contrast, deskew, binarise, crop-to-paper) (preparation)

(a) **What.** Standard thermal-print pre-processing before recognition. (b) Layer: preparation.
(c) **Gain on receipts: none measured, and I checked the named cases.** receipt-018 – flagged in
the brief as low-contrast – reads every operand at conf 1.00 in the dump (`450.00*43.820`,
`=19719.00` ×4); its three misses are band ambiguity and the ИТОГ mispairing of section 1.4, which
no pre-processing touches. pump-058 is genuinely low-contrast, and genuinely in the pump class,
which scores 51/251 behind its own flag and is a different problem per EXTRACTION.md's split. No
receipt miss in the dump is attributable to contrast, skew or resolution.
(d) Non-trivial if built well (Core Image chain, per-image cost). (e) Low, but not zero:
aggressive binarisation can destroy faint thermal print. (f) Would generalise to bad photos –
which this corpus, by selection, under-represents. **Recommendation: not for receipts now;
revisit with the pump work, where the measured deficit lives.**

## 3. The ceiling

Start: 173/210 (82.4%), 28/46 receipts fully correct.

**Tier A – deterministic, zero wrong-answer risk (options 1 + 3): +4 → 177/210 (84.3%).**
001, 038, 017 totals (option 1); 034 liters (option 3). Receipts fully correct 28 → 31: 001, 038
and 017 become clean.

**Tier B – deterministic given evidence already on the document (options 2 + 7): +2 → 179
(85.2%).** 018 total from its fiscal QR (`s=19719.00`, option 2) and 025's fuel-line total 1660.59
from row attribution + the commutative product (option 7). Neither makes its receipt fully correct
– 018 and 025 still miss operands – so the clean-receipt count holds at 31.

**Tier C – realistic returning-user history (option 4): +6 → 185 (88.1%).** 012 liters+price for
the LPG user; 002 and 018 liters+price for the Crimean АИ-100 regular. Clean receipts → 34: 012
and 002 were only missing operands, and 018 now has its total (Tier B) plus operands, so all three
become clean for their users.

**Tier D – car-context defaults, counted as suggestions (option 8): +4 → 189 (90.0%).** 035
currency+liters+unitPrice (the band unlocks once the car supplies RUB); 041 currency. 035 becomes
clean → 35 (041 still misses liters/price/total).

**Tier E – the customWords / second-pass gamble (options 5–6), if the A/B gate passes and the
product accepts a recognition-layer vocabulary bias: +6 → 195 (92.9%).** 027 fuelKind + its two
operands (the kind fix unblocks the band: 30 out of [40,500], 70.05 in); 042, 043, 044 fuelKind.
Clean receipts → 38: 027, 042 and 044 each had only the fuelKind outstanding (027's operands come
with it); 043 still misses operands, so it does not.

**Named unreachable.** Two grades, because the distinction is the point:

- **Unreachable for any real user – 008 liters, unitPrice (2).** The operands differ by 0.2%
  (48.89 vs 48.80). The history rule CAN separate any distinct pair, but only with a median inside
  (2.5 × smaller, 2.5 × larger] – for 008 that is a window 0.22 ₽ wide at 2.5× the actual price
  (m ∈ (122.0, 122.2]), which is an oracle, not a user. No band, no document evidence, no QR
  (items not carried) can order them either. The corpus's own "honestly undecided" (README §1).
- **Unreachable in practice – 13 cells.** Separable only by a user median no real driver has
  (option 4's inequalities), with no QR items and the band unable to help: 007 liters+price (needs
  m > 109, above any typical АИ-100 price), 029 liters+price (m > 108), 025 liters+price (the
  multi-pair guard plus ratio 1.13; its TOTAL is Tier B, its operands are not), 040 liters+price
  (m > 142), 041 liters+price+total (m > 135 and a garbled ИТОГ; even currency recovery does not
  unlock the pair), 043 liters+price (volume 40 sits ON the band floor; needs m > 100 for 2026
  АИ-95; its fuelKind is Tier E).

That is 15 cells → **absolute ceiling 195/210 (92.9%)**, and it is only reachable if Tier E's
gamble pays off; without it the honest ceiling is 189 (90.0%). Tiers C–E are conditional on who
the user is and what the product allows, so the number to plan against is Tier A+B: **179 (85.2%)
at zero wrong-answer risk.** A claim above 195 on this corpus is fitted.

## 4. What I would not do

1. **Restore a decimal-count or operand-position tie-break.** HIGH-WATER.md exists precisely
   because this scored well by luck on one fixture while swapping 007 (99.40 L at 43.61, cross-check
   green). The corpus falsified it three more times since: 037 vs 040/041 (position reverses
   within one card's slips), 043 vs 037 (decimal count reverses). Options that sneak it back as a
   "feature heuristic" are the same move.
2. **Infer currency from magnitude** (035/041). 6000.00 ₸ and 6000.00 ₽ are the same digits;
   CurrencyDetection's header says it in so many words. Car-context default (option 8) is the
   legitimate path, as a suggestion.
3. **Snap 96→95, ДИ→АИ, AM→АИ in the parser.** The 027 trap: АИ-96 is not a retail grade, which
   is exactly what makes snapping look safe; two independently dispatched models already ruled on
   this. The customWords variant (option 5) relocates the same epistemic move into Vision and is
   acceptable only with the A/B gate and an explicit product decision – not as a quiet fix.
4. **Train or fine-tune anything on receipts.** EXTRACTION.md's data wall stands: 46 receipts is
   the test set, training on it makes the ratchet green by memorisation; every miss here has a
   name and a rule. The cloud arm's 84/96 came with five silent swaps and a decimal shift –
   accuracy bought that way is not the product's trade.
5. **Ship a second OCR engine on-device** (PaddleOCR measured worse on receipts, 29/96 vs 46/96,
   and the parser is coupled to Vision's line segmentation – P4.13).
6. **Use the receipt grand total as the fuel amount** on mixed receipts (025) – hard rule 4, and
   the QR carries the same grand total, so QR fusion must keep the fuel-line exemption.
7. **Gate values on Vision confidence.** Conf 1.00 on wrong digits is a named corpus fact
   (pump-004; 027's 96; 015's `=5380.0D`). Confidence thresholds buy nothing and hide the modal
   redundancy that does.
8. **Contrast/deskew pre-processing for receipts** (option 10's verdict): zero misses attributable,
   cost real. Save it for the pump class where the deficit is measured.
9. **Narrow the LPG band to force 012.** The overlap is deliberate (seed.json): LPG volumes
   40–80 L live inside any honest LPG price band, and a narrowed band swaps a 45 L fill whose
   price sits above the new ceiling. 012 belongs to the user's history (option 4), where it
   resolves for a real reason.
10. **Add a synthetic user history to the ratchet.** Any history chosen to move these fixtures is
    fitted data; the ratchet must stay the first-launch number (options 4 and 8 keep their gains
    where they live: the app, and the user's confirmation).

## 5. Findings nobody in this repo has written down (the ones I'd keep)

- The two Circle K total nils are **modal-tie poison**: label pairing grabs stray same-baseline
  values (the quantity `1`, the VAT `15,35`), and the unbreakable-tie abstention – correct as a
  doctrine – then discards a total that is printed three times. Arithmetic-anchored candidates
  (option 1) are the missing third source for the total finder.
- **The gate measures a first-launch user; the app runs a returning user.** Ladder step 3 is wired
  in AppFuelPriceBand and invisible to the ratchet. The ±60% history window has a structural
  consequence computable without running anything: resolving a pair needs the user's median inside
  (2.5 × smaller operand, 2.5 × larger] (or the mirror window at the low end), so narrow pairs
  demand narrow, high windows: 008's is 0.22 ₽ wide, and 025/029/040/041 need medians of 108–142+
  (025 never even reaches the rule – the multi-pair guard fires first). That family – five
  fixtures, nine cells – is permanently beyond history at realistic prices, and the band cannot
  separate them either. That, not parser quality, is the shape of the ceiling.
- **The QR path's 1 ₽ agrees-tolerance hides exactly one corpus error (017)** – a discount, not
  noise. One line of semantics separates them.
- **034 is a live trap for the history step**: with any realistic median, `resolveUnmarked`
  resolves it as liters 0.00 / price 30.61, and there is no zero-liters guard. Option 3 before
  option 4, always.
- The vision revision is unpinned: the high-water mark silently depends on Apple's OCR version.
