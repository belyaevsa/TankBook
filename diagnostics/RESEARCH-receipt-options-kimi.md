# RV.57 – raising on-device receipt recognition: every option, ranked

Baseline: **173/210 cells, 28/46 receipts fully correct, 37 misses across 18 fixtures**
(`diagnostics/receipt-field-report.txt`), misses by field: liters=13, unitPrice=12, total=6,
fuelKind=4, currency=2. Three confident-wrong values remain, all totals: receipt-017 (961.80 vs
961.00), receipt-018 (3555.89 vs 19719.00), receipt-025 (1729.87 vs 1660.59).

## The one finding that shapes the whole answer

**Every missed numeric value is already in the OCR text.** I checked all 37 misses against
`diagnostics/receipt-ocr-lines.txt` line by line. The operand pairs of receipts 002, 007, 008, 012,
025, 027, 029, 034, 035, 040, 041, 043 are all present, at confidence 1.00. The six missing totals
are all present (001: `125,22` printed 3 times; 017: `=961.00 РУБ`; 018: `=19719.00` printed 3
times; 025: `#1660.59 РУБ`; 038: `79,32` printed 4 times; 041: `=3695.76` printed twice). What is
NOT in the text: four fuel-grade tokens garbled by Vision (`АИ-96-К5` for 95 on 027, `) BC` for
`D B0` on 042, `ДИ-95` for `АИ-95` on 043, `AM-95` for `АИ-95` on 044), one total label (`ИТОГО`
read as `*O:` on 041), and any currency evidence on the two fuel-card slips (035, 041). So the
losses live in **interpretation (25 operand abstentions + 6 totals)**, in **five token-level
recognition garbles**, and in **two honest absences of evidence** – and image preparation can only
address the middle five. receipt-018, named in the brief as a low-contrast suspect, OCRs cleanly
end to end; its three misses are all parser-level. Contrast is not where the receipt losses are.

## The miss map (the spine of every option below)

| fixture | misses | mechanism (traced in the dump) |
|---|---|---|
| 001 | total | `KOKKU` geometrically pairs the käibemaksuta amount `100,98` (baseline diff 0.006; the true `125,22` sits 0.014 away, outside the 0.012 window); `Käibemaks kokku` matches the `KOKKU` label by substring and pairs `24,24`; `KK MAKSE` pairs `125,22`. Three-way candidate set, primary tie -> nil. |
| 002 | liters, unitPrice | `450.00*43.820` unmarked; both operands inside the seeded 2024+ RUB band [40,500] -> abstains. |
| 007 | liters, unitPrice | `43.61 Х 99.40` unmarked, both 2 decimals, both in band -> abstains. The canonical swap fixture. |
| 008 | liters, unitPrice | `48.89 Х 48.80` – both plausible prices AND both plausible volumes. Undecidable in principle. |
| 012 | liters, unitPrice | `52.15 Х 23.99` LPG; the seeded LPG band [15,60] deliberately overlaps both operands -> abstains (a written decision in the seed note). |
| 017 | total | `ИТОГ:` prints the pre-discount `=961.80`, the charged `=961.00` sits on `НАЛИЧНЫМИ:`; primary label beats payment label in the tie-break -> confident wrong. QR says `s=961.00`. |
| 018 | liters, unitPrice, total | operands as 002. Total: the `=` of `=3555.89` (VAT row) OCR'd as `-3555.89`; the number parser drops the sign, the VAT value becomes the ИТОГ-paired candidate and beats `=19719.00` on primary-vs-payment. QR says `s=19719.00`. |
| 025 | liters, unitPrice, total | two unmarked pairs (`69.28 X 1` service, `43.38 Х 38.28` fuel) -> `OperandPair.single` abstains; with operands nil the total falls back to the grand total 1729.87 (hard-rule-4 violation, confident wrong). Fuel line `#1660.59 РУБ` sits on the fuel pair's own baseline. |
| 027 | liters, unitPrice, fuelKind | `ЭКТО Plus (АИ-96-К5)` – Vision misread 95 as 96; 96 is not a retail grade -> kind nil (deliberate: no resemblance snap). Kind nil -> kind-keyed band refuses -> `30 Х 70.05` abstains. |
| 029 | liters, unitPrice | `43.24 Х 58.51`, both 2 decimals, era band [35,100] contains both -> abstains. |
| 034 | liters | `30.61 Х 0.00` contract zero-price; the zero rule nils the price and the pair takes the volume down with it. |
| 035 | liters, unitPrice, currency | `70.44 X 39.000` unmarked -> abstains. Currency: the slip carries no fiscal furniture and no currency word -> honest nil. |
| 038 | total | rotated/steep-angle photo; geometry shattered (`KOKKU` at midY 0.339, its value `79,32` at 0.749). Two labelled candidates tie (`Summa`->79.32, `Summa`->15.35, both primary) -> nil. `79,32` appears 4 times in the document. |
| 040 | liters, unitPrice | `71.18 x 57.000` unmarked; both in band (57.000 >= 40) -> abstains. |
| 041 | liters, unitPrice, total, currency | `68.44 X 54.000` -> abstains. Total label `ИТОГО` OCR'd as `*O:` -> no labelled candidate -> nil, while `=3695.76` prints twice. Currency as 035. |
| 042 | fuelKind | `D B0` garbled to `) BC` (and the line is split); the loyalty-grade rule needs `D B[0OÓ]` + `MILES` and cannot fire. Deliberately left nil (no resemblance). |
| 043 | liters, unitPrice, fuelKind | watermark badge over the product line: `ДИ-95 (1 ТРК)` – no `Бензин` token, no `-К5` corroboration -> kind nil (deliberate) -> band refuses -> `40 Х 120.00` abstains. |
| 044 | fuelKind | `AM-95` with no `-К5` suffix; the smeared-octane rule requires the suffix -> nil (deliberate). |

---

## Ranked options

### 1. The currency-convention decimal rule (parser) – **+14 cells**

**(a) What it is.** A new ladder step between the marker steps and the band: on an unmarked operand
pair, compare each operand's decimal-place count against the *currency's price-printing
convention* – RUB/KZT prices print 2 decimals (`70.44`, `99.40`, `450.00`), EUR prices print 3
(`1,754`, `1,869`). If exactly one operand matches the convention, it is the price. If both match
(equal counts), or neither does, abstain. Scoped to currencies with an observed convention; combine
with the band conservatively: if the band says the convention-priced operand is implausible AND the
swapped one is plausible, abstain rather than resolve.

Per fixture, from the dump: `450.00*43.820` (002, 018) -> 2dp side is the price; `70.44 X 39.000`
(035), `71.18 x 57.000` (040), `68.44 X 54.000` (041) -> same; `30 Х 70.05` (027), `40 Х 120.00`
(043) -> the 2dp side against a whole-litre operand. It abstains – correctly – on 007, 008, 012,
025, 029 (all both-2dp) and on 034 (zero-price, option 6's case).

**(b) Layer:** parser (`resolveUnmarked`, before the band).

**(c) Expected gain: +14 cells** – liters+unitPrice on 002, 018, 027, 035, 040, 041, 043. Verified
against every currently-hit fixture: every unmarked pair the band resolves today (003, 004, 005,
014, 015, 024, 026, 017, 028, 032, 033) has the 2dp side as the true price, so the rule agrees with
every existing HIT and fires nowhere else. This is not the decimal-ORDINAL heuristic the corpus
falsified twice ("more decimals = volume" dies on 037/043, "more decimals = price" dies on
002/033): it keys on the absolute count vs the currency's convention, and it abstains on ties.

**(d) Cost:** ~60 lines plus tests; zero runtime cost (string inspection).

**(e) Wrong-answer risk:** one shape – a RU/KZ receipt printing a 3-decimal price, or an EE receipt
a 2-decimal price with a 3-decimal volume. Zero occurrences in 46 fixtures; 2-decimal цена is the
fiscal print convention, not a chain quirk. A wrong fire is a swap the cross-check cannot see
(`a x b == b x a`), so the conservative combination rule (band disagreement -> abstain) is
mandatory, and the rule must live behind the marker steps so marked pairs never reach it.

**(f) Generalises:** yes – it encodes how fiscal printers format money, not anything about these 46
images. The corpus's own counter-examples to ordinal decimal rules (036/037 README) do not touch
this form because those pairs are marker-resolved upstream.

### 2. Score the pipeline the app runs: the fiscal QR anchor (other evidence) – **+2 cells, and retires 2 of the 3 confident-wrongs**

**(a) What it is.** The corpus scorer and the diagnostics harness run `FuelExtractor` alone. The
app does not: `CapturePipeline` runs `CaptureQRDetector` beside OCR, and
`ConfirmQRTotal.resolve` makes the QR's `s=` win the total on disagreement (`.qrAuthoritative`),
keep the fuel line on a mixed receipt (`.fuelLineStands`). Wire the committed `.qr.txt` sidecars
into the scored harness and apply the same resolution. On receipt-017 the QR says `s=961.00` where
the parser returned 961.80; on receipt-018 `s=19719.00` where it returned 3555.89. Both flip.

**(b) Layer:** other evidence (the document's own fiscal QR) + measurement alignment.

**(c) Expected gain: +2 cells** (017 total, 018 total), and the two worst remaining defects – confident
wrong totals – leave the measured surface. 22 of 46 fixtures carry a decodable QR. Note the
boundary, traceable per fixture: the QR carries **no** liters, unitPrice or fuelKind, so it can
never touch the 25 operand misses, and on receipt-025 `s=1729.87` is the *grand* total – the
fuel-line problem stays with option 5. Side effect worth more than the 2 cells: the measured number
becomes the pipeline the user actually experiences, so every future parser change is scored against
reality.

**(d) Cost:** ~30 lines in the harness plus a test; zero runtime cost (the app already pays it).

**(e) Wrong-answer risk:** none new – the resolution rule is already shipped behaviour with its own
tests; a QR/OCR conflict on a mixed receipt is exactly the `suggestsMixedReceipt` case, handled.

**(f) Generalises:** yes, for every fiscal receipt whose QR decodes. It does nothing for non-fiscal
slips (016, 023, 035, 036, 040, 041, 044) or Estonian receipts (no QR at all) – by design.

### 3. Redundancy-aware total resolution (parser) – **+3 to +5 cells**

**(a) What it is.** A fallback below the labelled-total ladder, fired only when that ladder yields
no winner (nil or an unbreakable tie), never as an override: scan the document's value lines, take
values that repeat, and resolve the total as the **largest repeated value**, with three guards that
the corpus itself dictates:
- *Sign-aware candidates.* `NumberScanner.value` drops a leading `-`, so receipt-018's `-3555.89`
  (a misread `=`) became a positive candidate. Reject non-positive total candidates. On 018 that
  leaves `{19719.00}` and resolves it **without** the QR (+1, overlapping option 2).
- *VAT-total label hygiene.* `Käibemaks kokku` (Estonian "VAT total") matches the `KOKKU` primary
  label by substring, injecting the bogus `24,24` primary candidate on 001. Add `KÄIBEMAKS` to the
  excluded-label vocabulary, mirroring the existing `НДС` exclusion.
- *Discount reconciliation.* When two candidates differ by exactly a printed `СКИДКА` /
  `ОКРУГЛЕНИЕ` line, the post-discount value wins. Receipt-017: `961.80 - 0.80 == 961.00` (+1,
  overlapping option 2). This is the `reconciled` cross-check outcome promoted from a flag to a
  field decision, and it generalises the three discount mechanisms the receipts README names.

The redundancy rule itself: on 001 `125,22` repeats 3x (largest repeated: 125.22 vs 24.24 x2) ->
125.22; on 038 `79,32` repeats 4x vs `15,35` x2 -> 79.32; on 041 `3695.76` repeats 2x, everything
else once -> 3695.76. Fires only where today is nil, so no current HIT can regress (receipt-019's
`3621.12` vs `3621.00` trap is handled by the discount guard; receipt-010's `48.54` x3 trap never
fires because its labelled total resolves).

**(b) Layer:** parser (`grandTotal`/`modal` fallback + `NumberScanner` sign handling + label
exclusion + the discount lines already collected in `CrossCheck`).

**(c) Expected gain: +3 cells** from redundancy alone (001, 038, 041); **+5** counting the two
guards' independent wins (018 via the sign guard, 017 via discount reconciliation) if option 2 is
not done.

**(d) Cost:** ~100 lines plus tests; trivial runtime.

**(e) Wrong-answer risk:** the fallback suggests a repeated value that is not the total on a
receipt whose labels all failed – the 010-shape (a per-litre price repeated 3x). Mitigations:
largest-among-repeated (not most-frequent), count >= 2, abstain on count ties (019-shape), the
discount guard, and never firing when a labelled result exists. Residual risk is a *suggestion* on
a nil-today field, shown on the Confirm screen next to the photo – not a stored fact.

**(f) Generalises:** yes – fiscal receipts print the charged total 2-4 times (item extension, ИТОГ,
payment row, card slip) by regulation, not by habit. The guards are language- and chain-specific
but additive: each new receipt shape can only add an exclusion, never loosen one.

### 4. Product-line-anchored fuel pair on multi-pair receipts (parser) – **+1 cell, and retires the last confident-wrong**

**(a) What it is.** When more than one unmarked operand pair exists, the ladder abstains *by
design* (`OperandPair.single`), and `resolveTotal` then falls back to the grand total – that is
receipt-025's confident wrong `1729.87`. The document already names the fuel pair: it is the pair
the fuel **product line** introduces. On 025, `ТРК-2 АИ-95-К5` is a product line and `43.38 Х
38.28` follows it; the service pair `69.28 X 1` follows `Услуга по регистрации покупки`, which is
not a product line. Rule: the pair nearest below a fuel product line is the fuel pair; its printed
extension (`#1660.59 РУБ`, same baseline, diff 0.003) is the fuel amount; operands still walk the
ordinary ladder (and still abstain on 025 – era band contains both, which is correct).

**(b) Layer:** parser (`resolveVolumeAndPrice` multi-pair branch + `resolveTotal`).

**(c) Expected gain: +1 cell** (025 total). This is the third and last confident-wrong value in the
corpus; with options 2/3 done, the class goes to zero.

**(d) Cost:** ~60 lines plus tests; trivial runtime.

**(e) Wrong-answer risk:** anchoring to the wrong pair. Guarded three ways: the anchor must be a
genuine fuel product line (`FuelKindNormalizer.isProductLine`), the extension must sit on the
pair's baseline, and it must agree with the pair's own product within the existing tolerance
(`43.38 x 38.28 == 1660.59` exactly). On receipt-009 the same anchor exists but never fires –
marked fuel line resolves upstream. When in doubt, nil: the grand-total fallback must also go –
a multi-pair document with no anchor should return *no* total rather than the grand total, which is
the hard-rule-4-safe default.

**(f) Generalises:** yes – "the fuel line is the one the fuel product names" is a document
structure, not a chain habit; it is the same anchor the `L`-marker path already uses when a marker
exists.

### 5. Era floor on the 2024+ RUB band (parser configuration) – **+2 cells beyond option 1**

**(a) What it is.** The seeded 2024+ RUB band is [40, 500]; receipt-007's `43.61 Х 99.40` has both
operands inside it. Raise the 2024+ floor to 50, with the seed note rewritten in the same style as
the existing ones: the corpus's own 2024+ minimum real price is 62.20 (2023-07 Yakutsk, era-2018
band anyway) / 62.89 (2024-08); no 2024+ retail price under 50 exists in the corpus, and АИ-92's
2024 lows (~52) stay inside. Then 007 resolves: 43.61 out, 99.40 in. The same floor independently
covers 002, 018, 035, 040, 041, 043 – so if option 1 is rejected, this is the fallback for most of
its gain, trading print-convention risk for magnitude risk.

**(b) Layer:** parser (`FuelPriceBands.seed.json` – two numbers and their notes).

**(c) Expected gain: +2 cells** (007 liters+unitPrice) on top of option 1.

**(d) Cost:** minutes to change; the cost is the curation judgement, not the code.

**(e) Wrong-answer risk:** a real 2024+ price in [40, 50) paired with a volume in [50, 500) swaps
where the old band abstained. No such fixture; early-2024 АИ-92 at ~50-52 is the nearest real case
and stays in band. The band still *ranks*, never vetoes – the Crimea outliers (205, 245, 269, 450)
are untouched because the high end does not move.

**(f) Generalises:** as well as any curated band does – it is an era statement about a national
price floor, and the seed format already carries the justification per row.

### 6. Zero-price contract volume (parser) – **+1 cell**

**(a) What it is.** When an operand pair has exactly one operand equal to `0.00`, the other is the
volume and the price stays nil. Receipt-034's `30.61 Х 0.00` currently returns nil-nil; the zero
rule already nils the price, but the volume – the one certain value on the document, and the only
cell the fixture asserts – goes down with it. Return (30.61, nil).

**(b) Layer:** parser (`resolveOperands`).

**(c) Expected gain: +1 cell** (034 liters). A zero-price fill remains a full consumption data
point, which is the entire design of the zero rule.

**(d) Cost:** ~10 lines plus tests.

**(e) Wrong-answer risk:** a `0.00 X 0.00` pair – abstain (both zero). A genuine zero *volume*
(void) prints `0,00L` marked (receipt-039) and never reaches this path. Near-zero risk; a printed
zero price is "not printed" by the app's own rule, so the other operand cannot be a price.

**(f) Generalises:** yes – B2B contract fuel cards are a document class across RU/KZ, not one
fixture.

### 7. The unmeasured recognition knobs (recognition) – **unknown; measurable in an afternoon, and the knob nobody has touched**

**(a) What it is.** `VisionTextRecognizer` is 92 lines and configures the request exactly one way:
`.accurate`, `usesLanguageCorrection = false`, language list `["en-US", "de-DE", "pl-PL", "cs-CZ",
"ru-RU"]`, no revision pin, no `minimumTextHeight`, no `customWords`. The diagnostics harness
(env-var gated, writes the field report and the line dump) makes each knob a one-line change with a
full 210-cell re-score and a line-level diff. The candidates, in the order I would measure them:
1. **Language order.** The corpus is 39/46 Cyrillic-primary documents and the list leads with
   English. All four remaining recognition garbles are Latin-bias artefacts: `АИ-95` -> `AM-95`
   (И->M, 044), `АИ-95` -> `ДИ-95` (А->Д, 043), `АИ-95` -> `АИ-96` (5->6, 027), `D B0` -> `) BC`
   (042). `ru-RU` first is the single most promising knob in the file. The Estonian receipts keep
   their Latin languages in the list, so the risk is bounded and visible in the diff.
2. **Revision pin.** `VNRecognizeTextRequest` has multiple revisions; the default is not a
   commitment. Pinning also makes results reproducible across iOS versions, which this project's
   snapshot discipline already cares about.
3. **`customWords`** with the fiscal vocabulary (ИТОГО, КОККУ/KOKKU, АИ-95, ДТ, СУГ, лит, руб).
   Targets 041's `ИТОГО` -> `*O:` directly, though option 3 already covers that cell for free.
4. `usesLanguageCorrection = true` – expected harmful on a document full of authorisation codes
   (the false setting is deliberate), but it is one run to confirm.
5. `minimumTextHeight` – expected harmful: receipt-038's *real* values (`79,32` at w=0.028) are
   among the smallest text in the corpus. Measure only to document the harm.

**(b) Layer:** recognition.

**(c) Expected gain:** unknown – at most +4 (the four garbled grade cells: 027, 042, 043, 044
fuelKind), possibly negative side effects on currently-hit lines. Measure: run the harness once per
knob, diff `receipt-ocr-lines.txt`, re-score; adopt only knobs that flip a miss with zero HIT
regressions.

**(d) Cost:** an afternoon for the matrix; adoption is one line per knob. iPhone 12 runtime: free
for order/revision/customWords; correction costs time; a second pass costs tens of ms.

**(e) Wrong-answer risk:** a knob that "recovers" a token wrongly (e.g. reads `АИ-96` into `АИ-98`)
creates a confident-wrong kind. That is exactly why adoption must require zero regressions *and*
the recovered token must still pass the text-layer rules (valid grade, corroboration where the
normaliser demands it) – the knobs change the input, the abstention discipline stays.

**(f) Generalises:** yes – language order and revision are document-set independent; `customWords`
is a vocabulary, additive like the noise-filter classes.

### 8. Era-keyed LPG band (parser configuration) – **+2 cells, against a written decision**

**(a) What it is.** The seeded LPG band [15, 60] overlaps LPG fill volumes *on purpose* – the seed
note says so: "an unmarked LPG pair has BOTH operands in band and abstains rather than swapping."
An era-keyed narrower row (2023: roughly [18, 35]) resolves receipt-012's `52.15 Х 23.99`:
23.99 in, 52.15 out.

**(b) Layer:** parser (seed pack).

**(c) Expected gain: +2 cells** (012 liters+unitPrice).

**(d) Cost:** one seed row – but it reverses a deliberate, documented abstention, so it needs the
same per-row justification the other rows carry, plus era rows for every period, not just 2023.

**(e) Wrong-answer risk:** an LPG price outside the narrowed band paired with a volume inside it
swaps (e.g. a 2026 LPG price of 36+ with a 30 L fill). The current row was written precisely to
make that impossible. The safer variant of the same gain: in the app, ladder step 3 (the user's own
price history) already resolves 012 – a user who buys LPG has a ~24 ₽/L median, 52.15 falls outside
the ±60% tolerance, 23.99 inside. **012 is resolved in the app today; only the corpus cannot see
it.**

**(f) Generalises:** only with per-era curation; the maintenance cost is real and the swap risk is
the documented reason the row is wide.

### 9. Fuel-family feed to the band when the grade is unreadable (parser) – **+0 unique cells**

**(a) What it is.** `BandContext` takes `FuelKind?`; a nil kind (027's `АИ-96`, 043's `ДИ-95`)
blocks the kind-keyed band entirely. A `detectFuelFamily` that reads only the family token
(`Бензин` -> petrol, `ДТ`/`Диз` -> diesel, `СУГ` -> lpg) would feed the band without committing to
a grade. On 027 (`Бензин автонобильный` prints cleanly) the petrol band resolves `30 Х 70.05`
today. fuelKind itself stays nil – honest.

**(b) Layer:** parser.

**(c) Expected gain: +0 beyond option 1** (which resolves 027 and 043 by decimals without any
band). Listed because if option 1 is rejected, this is the principled way to un-block 027 (+2)
while keeping the LPG protection that makes the kind key load-bearing.

**(d)-(f):** ~30 lines; risk is a family token misread (low – families are whole words, and
`matchesFuelToken` already guards abbreviations); generalises to any receipt whose product line
names the family in words.

### 10. Targeted re-recognition of a field region (recognition/retry) – **unknown, speculative, bounded**

**(a) What it is.** A second Vision pass over a small region at higher effective resolution
(upscaled 2-3x). The region for a *nil* field is derivable: the product line (the fuel-token line)
for fuelKind – exactly where all four remaining recognition losses live (027, 042, 043, 044).
Acceptance rule, because a re-read can also be wrong: accept only a result the text layer can
corroborate (a valid grade with `-К5` on the same line, or agreement between the two passes);
anything else stays nil.

**(b) Layer:** recognition.

**(c) Expected gain:** unknown, at most +4 (the four kind cells). Honest assessment: `) BC` (042)
may simply lack the pixels – the crop is the only way to know, and receipt-043's badge physically
covers the text. Cheap to test on four fixtures with the existing harness.

**(d) Cost:** ~150 lines (crop, upscale, re-recognise, acceptance) plus tens of ms of Vision time
on iPhone 12 – fine.

**(e) Wrong-answer risk:** an uncorroborated re-read creating a confident-wrong kind – the
acceptance rule exists precisely to keep that impossible.

**(f) Generalises:** yes as a mechanism (it is the same "re-read the crop" the confirm screen's
crop evidence already enables), but expectations should be low: it attacks 4 cells.

### 11. Image preparation (preparation) – **near-zero on this corpus, one real sub-case**

**(a) What it is.** Contrast stretch, binarisation, upscaling, deskew/perspective correction before
Vision.

**(b) Layer:** preparation.

**(c) Expected gain:** the evidence says ~nothing. Every numeric value in all 18 missing fixtures
is present in the OCR at confidence 1.00 (traced line by line, see the miss map) – preparation
fixes recognition losses this corpus's receipts do not have. receipt-018, the brief's low-contrast
suspect, is fully legible in the dump; its losses are options 1, 2 and 3. Two data points worth
recording: `CorpusCompressionTests` measures the 1600px/JPEG rendition at **174/210 – one cell
BETTER** than raw (the resize clears a smear; which fixture is not recorded – finding out is part
of any prep work), and receipt-038's scrambled geometry is the one place a deskew could matter –
but option 3 fixes 038 for free, without touching a pixel. If a prep matrix is run anyway, it is
the same harness afternoon as option 7, and the expected yield is 1-2 cells.

**(d)-(f):** CoreImage cost is fine on iPhone 12; risk is a prep step that *changes* a currently-
clean read (a global re-score catches it); generalises only if the matrix proves a gain.

### 12. Cross-capture resolution: the second photo of the same fill (other evidence) – **+0 corpus cells, real product gain**

**(a) What it is.** The corpus holds seven matched pairs/triples of one fill captured twice
(001/pump-001/screenshot-004, 038/pump-019, 040/pump-029, 042/pump-034, 044/pump-044,
045/pump-054, 046/pump-057). When a user photographs both the pump and the receipt, each capture's
blanks can be filled from the other – receipt-040's unmarked `71.18 x 57.000` is settled by
pump-029's display, receipt-042's missing kind is on no pump (rule: never infer kind from a pump)
but its pump-034 half corroborates the operands. The attach-merge seam (`ReceiptAttachMerge`,
blank-fields-only, typed values win silently) is the shape the rule already takes.

**(b) Layer:** other evidence – a second document.

**(c) Expected gain:** **zero on this scoreboard** – the corpus scores single documents. Listed
because it is the one avenue that turns the app's existing multi-photo surface into accuracy for
real users, and nobody has written it down. Guards: same-fill pairing needs timestamp + station +
amount agreement, conflicts stay user-visible (hard rules 8, 13), and a pump never names a kind.

**(d)-(f):** days of product work, not hours; risk is pairing two different fills, bounded by the
agreement checks; generalises to every user who shoots both.

---

## The ceiling

Sum the deterministic options: option 1 (+14), 2 (+2), 3 (+3, the 018/017 cells counted under 2),
4 (+1), 5 (+2), 6 (+1):

**196/210 (93.3%), 36/46 receipts fully correct** (newly full: 001, 002, 007, 017, 018, 034, 038,
040). Option 8 adds +2 -> **198/210 (94.3%)**, 37/46 full.

Above that, four kind cells (027, 042, 043, 044) are reachable only through the recognition layer
(options 7/10) – unproven until measured. If all four recover: **202/210 (96.2%)**.

**The hard floor – misses unreachable in principle, named:**

- **receipt-008's operands (2 cells).** `48.89 Х 48.80` – both plausible prices, both plausible
  volumes; they differ by 0.2%. No band, history or convention can split them, and the corpus
  README already calls this the honestly-undecided case. Abstention is the *correct* answer here.
- **receipt-025's and receipt-029's operands (4 cells).** Not reachable by the band (era rows
  deliberately contain both operands) and not by history as implemented: step 3's tolerance is
  ±60%, and 025's operands differ by 13%, 029's by 35% – both pairs sit inside any tolerance wide
  enough to survive a station or grade change (tighten to ±20% and a user switching АИ-92 to АИ-100
  swaps: 43 L inside [36.8, 55.2] around a 46 ₽ history). The two-tap manual fill is the design
  answer (hard rule 15), not a gap.
- **The two fuel-card currencies (035, 041 – 2 cells).** No currency evidence anywhere on the
  document. A script/address prior guesses RUB and is a confident-wrong on the Kazakh twin of the
  same slip (PetrolPlus operates in both countries; receipt-033 proves Cyrillic != RUB). Honest
  nil; the user picks a currency in one tap.

So: **absolute ceiling 202/210 (96.2%)**, honest deterministic ceiling **196-198/210**, and the
eight cells above are where "nil + two taps" is the right product answer, not a parser failure.

## What I would not do

1. **Restore any decimal-ordinal or position tie-break** ("more decimals = volume/price", "first
   operand is the price"). Falsified inside this corpus in both directions (037 vs 033; 043 vs
   002); HIGH-WATER.md records the 99.400 L at 43.610 swap it produced on receipt-007 with the
   cross-check green. Option 1 is not this rule: it keys on the currency's print convention and
   abstains on equal counts.
2. **Image preprocessing for receipts** (contrast, binarisation, upscaling as a default). The
   losses it targets do not exist in this corpus's receipts – every missed number is already
   recognised at confidence 1.00. It adds a global-mutation risk to currently-clean reads for zero
   measured gain.
3. **Any use of OCR confidence** to accept or reject a value. The corpus's two canonical
   counter-examples: pump-004's wrong digit at 1.00, receipt-015's `5380.0D` at 1.00. Confidence is
   not evidence about values.
4. **Resemblance snaps on garbled grades** (`АИ-96` -> 95, `ДИ-95` -> `АИ-95`, `AM-95` -> `АИ-95`
   without the `-К5` suffix). Rejected in writing twice (HIGH-WATER history; two independent agent
   verdicts in the RV.48 round). The `-К5` corroboration rule already captures the safe half.
5. **Currency from magnitude, script, or address.** A tenge total and a rouble total are the same
   digits; Kazakhstan prints in Russian; the two nil-currency slips stay nil on purpose.
6. **An on-device SLM, or PaddleOCR as a second reader.** Measured: the cloud LLM's gains come with
   silent swaps, decimal shifts, non-determinism and 12-36 s latency (P4.12); PaddleOCR scored
   *worse* than Vision+parser on receipts (P4.13) and proved the parser is coupled to Vision's
   segmentation, not that a different reader unlocks it. The corpus is the test set – a model
   trained on it cannot be honestly measured. Every remaining miss has a name; rules are still
   cheaper than the instrument that would replace them.
7. **Band veto, or narrow national bands.** The Crimea series (205, 245, 269, 450 ₽/L in one week
   of 2026) is real asserted ground truth; a vetoing band rejects real fills. Bands rank, never
   veto – and option 5 only moves a floor the seed notes can justify in writing.
8. **Modal-over-all-values as an override of the labelled total.** receipt-010 prints `48.54`
   three times against `3058.00` twice; receipt-019 prints `3621.12` twice against `3621.00` twice.
   As an override it regresses HITs; as a nil-only fallback with guards (option 3) it cannot.
9. **`minimumTextHeight` above zero.** receipt-038's real total `79,32` is among the smallest text
   in the corpus (w=0.028); a floor deletes it.
10. **Treating the QR as the general answer.** 24 of 46 fixtures have no decodable QR; non-fiscal
    fuel-card slips never carry one (016, 023, 036, 040, 041, 044) and Estonian receipts have none.
    It is a powerful anchor where it exists (option 2) and absent by design elsewhere.

## What this is built on (the evidence actually read)

Read end to end: `diagnostics/receipt-field-report.txt` (all 305 lines);
`diagnostics/receipt-ocr-lines.txt` (all 2184 lines – every claim above traces to it);
`docs/EXTRACTION.md`; `Spike/ReceiptSpike/fixtures/HIGH-WATER.md`;
`Spike/ReceiptSpike/fixtures/receipts/README.md` (817 lines); the `_note` history in
`Spike/ReceiptSpike/fixtures/high-water.json` (all three RV.48 stages); all 22 `.qr.txt` payloads
and `expected.csv`; the parser: `FuelExtractor.swift`, `FuelKindNormalizer.swift`,
`CurrencyDetection.swift`, `NumberScanner.swift`, `ReceiptNoiseFilter.swift`, `CrossCheck.swift`,
`FuelPriceBandPack.swift`, `FuelPriceBandProvider.swift`, `FuelPriceBands.seed.json`,
`VisionTextRecognizer.swift`, `ExtractionAssembler.swift`, `ReceiptAttachMerge.swift`,
`FuelExtraction.swift`, the `ConfirmQRTotal` half of `ConfirmPrefill.swift`; the app wiring:
`CapturePipeline.swift`, `AppFuelPriceBand.swift`; the harness: `ReceiptFieldDiagnosticsTests.swift`,
`CorpusCompressionTests.swift`; and for what was already proposed, `diagnostics/RV.48-analysis-
orchestrator.md` and `diagnostics/RV.48-proposal-qwen.md`. Not read: the pump fixture READMEs in
depth (pump is a different scoreboard), the Spike's own reference parser, the gateway code. Nothing
was executed – every mechanism is traced from the dump against the parser source, not re-run.
