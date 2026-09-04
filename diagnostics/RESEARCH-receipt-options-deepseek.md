# RV.57 — how to raise on-device receipt recognition from here

Research only. No code changed. Everything below is traced to a fixture line in
`diagnostics/receipt-ocr-lines.txt` (conf values cited) or to
`diagnostics/receipt-field-report.txt`.

## The headline the evidence forces

The recognition layer is **not** the receipt bottleneck. I read every line of the
OCR dump, and every operand, label and marker the parser currently fails to use is
already read by Vision at **confidence 1.00**:

| miss | line in the dump | text | conf |
|---|---|---|---|
| receipt-002 | `450.00*43.820` | 86 | 1.00 |
| receipt-007 | `43.61 Х 99.40` | 271 | 1.00 |
| receipt-008 | `48.89 Х 48.80` | 312 | 1.00 |
| receipt-012 | `52.15 Х 23.99` | 535 | 1.00 |
| receipt-018 | `450.00*43.820` | 769 | 1.00 |
| receipt-025 | `43.38 Х 38.28` | 1123 | 1.00 |
| receipt-027 | `30 Х 70.05` | 1213 | 1.00 |
| receipt-029 | `43.24 Х 58.51` | 1279 | 1.00 |
| receipt-034 | `30.61 Х 0.00` | 1517 | 1.00 |
| receipt-035 | `70.44 X 39.000` | 1566 | 1.00 |
| receipt-040 | `71.18 x 57.000` | 1833 | 1.00 |
| receipt-041 | `68.44 X 54.000` | 1884 | 1.00 |
| receipt-043 | `40 Х 120.00` | 1998 | 1.00 |

Even the smeared grades the parser abstains on are read at confidence 1.00 —
`АИ-96-К5` (027, line 1212), `ДИ-95` (043, line 1997), `AM-95` (044, line 2040),
`) BC` (042, line 1921). These are thermal-print defects or confident misreads,
not low-confidence reads. A confidence threshold cannot touch them, and neither
can any recognition knob. The 37 remaining misses are **23 parser misses with a
name, 2 QR-closable, 8 deliberate swap abstentions, and 4 resemblance-prohibited
fuelKind abstentions** — not recognition failures.

---

## The options, ranked

### 1. The three-decimal operand is the volume — but only in the unmarked fallback, with a magnitude guard

**(a) What it is.** `OperandPair` already carries each operand's *text*
(`leftText`/`rightText`), and `resolveUnmarked` is the last-resort path that runs
only when no unit marker (`л`/`L`), no `руб`, no labelled column and no
`loneMarkers` named the volume. Add one rule there: **when exactly one operand has
exactly three decimal digits, and that operand is between 5 and 250, it is the
volume; the other is the price.** Never fire this anywhere else in the ladder —
specifically not on the marker path, and not as a general decimal-count tie-break.

The two guards are both load-bearing:
- **Three decimals, not "more"**: `receipt-027` (`30 Х 70.05`) shows "more
  decimals = volume" is false (70.05 is the price). But it has no three-decimal
  operand, so a *three-decimal* rule does not fire there.
- **The magnitude floor**: a Western unit price reads `1,754` (three decimals,
  value 1.754). Read as a volume that is under 5 L, so the guard rejects it and
  the pair abstains. It costs the rule nothing on the corpus (no unmarked pair has
  a three-decimal operand under 5), and it makes the rule currency-independent.

**(b) Layer.** Parser (`resolveUnmarked` in `FuelExtractor.swift`).

**(c) Expected gain, counted.** The three-decimal convention (litres to the
millilitre, price to the kopeck) is a CIS-print convention, and it holds on every
unmarked pair in the corpus:

| fixture | pair | three-decimal operand | correct? | gain |
|---|---|---|---|---|
| receipt-002 | `450.00*43.820` | 43.820 | volume ✓ | +2 |
| receipt-018 | `450.00*43.820` | 43.820 | volume ✓ | +2 |
| receipt-033 | `24.690 Х 243.00` | 24.690 | volume ✓ | already HIT |
| receipt-035 | `70.44 X 39.000` | 39.000 | volume ✓ | +2 |
| receipt-040 | `71.18 x 57.000` | 57.000 | volume ✓ | +2 |
| receipt-041 | `68.44 X 54.000` | 54.000 | volume ✓ | +2 |

**+10 cells, 5 fixtures** (002/018/035/040/041), taking 173 → 183. It costs
nothing to keep 033 (already correct), and it fires on **no** wrong case in the
corpus. This is the single largest deterministic lever.

**(d) Cost.** ~15 lines in `resolveUnmarked` plus a unit test per fixture above.
Zero runtime cost (pure function). No iPhone 12 impact.

**(e) Wrong-answer risk.** A three-decimal *price* on a genuinely unmarked pair.
The corpus contains none (Estonian three-decimal prices are all `EUR/L`-marked and
never reach this path). The magnitude guard makes a stray `1,754` price abstain
rather than swap. Residual risk: a hypothetical receipt printing volume to three
decimals *and* price to three decimals — the rule requires *exactly one*, so it
abstains. Honest abstention, not a guess.

**(f) Generalises?** Yes, and here is why it is the one heuristic the docs
mis-scoped. `receipts/README.md` and `high-water.json` record that a
"three decimals means volume" reading was **falsified** by `receipt-037`
(`99.99 X 25 Л`). But 037 carries a `Л` marker — it is resolved by the *marker*
path and never reaches `resolveUnmarked`. The falsification was against decimal
count as a **general** operand rule; it says nothing about decimal count as the
**unmarked-fallback** rule, which is the only place I propose it. No corpus
document has made that distinction. It should hold for any CIS thermal receipt
(three-decimal litres is the printing convention) and correctly abstain on Western
receipts.

---

### 2. Repair the total-finder's three named bugs (net-vs-gross, leading minus, discount)

**(a) What it is.** Three independent defects in `resolveTotal` / `grandTotal`,
each with a fixture:

1. **Net-vs-gross on the Estonian layout** (receipt-001, receipt-038). On
   receipt-001 the gross `125,22` is the item-column value at y=0.713, while the
   `KOKKU` label at y=0.636 sits on the same baseline as `100,98` (the
   `KAIBEMAKSUTA` net). `pairedValue`'s same-baseline rule takes `100,98` as the
   total; the gross `125,22` is one baseline up and just outside the `0.012`
   midY window, so the finder returns nil. receipt-038 (`79,32` vs net `63,97`)
   is the same shape. Fix: when a `KOKKU`/`SUMMA` label's same-baseline value
   equals the `KAIBEMAKSUTA` figure, prefer the modal value across the
   `Summa`-column rows instead — the gross appears 4+ times at conf 1.00.
2. **The leading minus is not a disambiguator** (receipt-018). `ИТОГ` at y=0.570
   pairs with `-3555.89` (the `СУММА НДС 22%` amount, one line lower on the same
   baseline) because `NumberScanner.value` silently drops the leading `-`. The
   real total `=19719.00` is *above* the label (value-before-label reading
   order). Fix: a value line beginning with `-` (or `_`) is a subtraction line,
   never a total candidate.
3. **A `СКИДКА` discount between the line extension and the total** (receipt-017).
   The finder returns the item extension `961.80`, ignoring the `СКИДКА =-0.80`
   line and the discounted `=961.00`. Fix: when a discount line is present, prefer
   the discounted total — or, better, let the QR settle it (option 3).

**(b) Layer.** Parser (`resolveTotal`, `pairedValue`, `NumberScanner`).

**(c) Gain.** receipt-001 +1, receipt-038 +1, receipt-018 +1 = **+3 cells**, and
removes one of the three confident-wrong values (018).

**(d) Cost.** Small, isolated; `NumberScanner` change is two lines. Zero runtime.

**(e) Wrong-answer risk.** Low and strictly better than today: these three now
return nil (or 961.80, which is *wrong*, not abstaining). Fixing to the printed
gross/discounted total cannot be worse than a confident-wrong value. The one care
point: the net-vs-gross fix must still let a genuinely no-discount receipt lock
its gross; keep the residual cross-check so a mismatch stays visible.

**(f) Generalises?** Yes — net/gross and value-before-label are printing
conventions, not corpus quirks. The minus-sign fix is universal: a `-`-prefixed
value is a subtraction line in any language that prints VAT/discounts.

---

### 3. Wire the fiscal QR into the scored extraction (it is already built, just not in the score)

**(a) What it is.** `CaptureQRDetector` already decodes the QR at capture time
(`CapturePipeline.swift`), `FiscalQRParser` already parses it, and
`ConfirmQRTotal.resolve` already decides OCR-vs-QR for the total. But the corpus
scorer measures `FuelExtractor` on OCR alone, so the QR's contribution is
invisible to the 173/210 number. Wire the QR anchor into the scored path: where a
QR is present, its `s` (grand total) and `t` (date) override or confirm the OCR
total, and classify mixed receipts by `s` vs the fuel line.

**(b) Layer.** Other evidence (the fiscal QR), composed in `ExtractionAssembler`.

**(c) Gain, counted from the 22 `.qr.txt` files present.** The QR carries exactly
`s` and `t` (plus fiscal ids) — **no litres, no unit price, no fuel kind, no
currency** (`FiscalQR.swift`), so it closes only totals and dates:

| fixture | OCR total today | QR `s` | gain |
|---|---|---|---|
| receipt-017 | 961.80 (wrong) | 961.00 | +1 |
| receipt-018 | 3555.89 (wrong) | 19719.00 | +1 |
| receipt-025 | 1729.87 (grand, mixed) | 1729.87 | 0 (mixed, fuel line needs operands) |

**+2 cells**, and it removes the other two confident-wrong totals. Separately it
fixes four garbled dates for free (010 `11.24`, 019, 031, 008 `08-12.22`) and is
the authoritative tiebreak for `receipt-031`'s list-vs-charged price and the
`receipt-009`/`-025` mixed classification — value the score does not count.

**(d) Cost.** Already implemented; the work is a scorer-side wiring plus a
`FuelExtractor`/assembler hook. Zero runtime (the QR is already decoded). No
iPhone 12 impact.

**(e) Wrong-answer risk.** Essentially none — the QR is a signed fiscal field.
The one subtlety is `receipt-031` (loyalty): the QR total is the *charged* total,
which is exactly the number the product wants, and `ConfirmQRTotal` already
handles it.

**(f) Generalises?** Yes, and it is already the agreed design
(`docs/EXTRACTION.md` → P4.12, `ConfirmQRTotal`). The only reason it does not show
in the score is that the score measures OCR alone.

---

### 4. A zero operand names the volume (receipt-034)

**(a) What it is.** When one operand of an unmarked pair is `0.00`, the other
operand is the volume and the price is nil — the B2B "price determined by
contract" shape (`receipt-034`, `30.61 Х 0.00`, "Цена определена договором",
line 1517 at conf 1.00). `resolveOperands`/`resolveUnmarked` should return
`(liters: 30.61, price: nil)` instead of abstaining. The zero→nil mapping for
`total`/`unitPrice` already exists (extract, lines 61–62); only the volume side
is left dangling.

**(b) Layer.** Parser.

**(c) Gain.** receipt-034 **+1** (liters). This is a real, honest cell — the
volume is printed and unambiguous; only the price is contract-hidden.

**(d) Cost.** ~5 lines. Zero runtime.

**(e) Wrong-answer risk.** None — a printed `0.00` operand is unambiguous, and
the volume is the only other number on the line.

**(f) Generalises?** Yes — contract-priced fleet fills are common across RU/KZ,
and this is exactly the "printed zero is not a value" class
`docs/EXTRACTION.md` already rules on.

---

### 5. Narrow the RU LPG band (receipt-012)

**(a) What it is.** `FuelPriceBands.seed.json` gives RU LPG a 15–60 band, and its
`note` says that overlap is **deliberate** — it lets `52.15 Х 23.99` have both
operands in band so it abstains rather than swap. That is a choice, not a fact:
LPG in the corpus era never prices above ~35 ₽/L, so narrowing to 15–35 would put
23.99 in band and 52.15 out, resolving `52.15 L at 23.99` for a real reason.

**(b) Layer.** Reference data (the band pack), not parser code.

**(c) Gain.** receipt-012 **+2**.

**(d) Cost.** One seed row. Zero runtime.

**(e) Wrong-answer risk.** A hypothetical LPG price above 35 ₽/L — which does not
exist in the corpus's span and would require a real market shift. The
currently-documented concern ("LPG fill volumes are 40–80 L, keep them in band")
is backwards: 52.15 read as a *volume* is correct; the band's job is to reject it
as a *price*, and it already can at no risk.

**(f) Generalises?** Yes within reason, but note the product wrote the wide band
deliberately; this re-opens a signed-off decision and belongs in P5 with the band
pack, not as a parser patch.

---

### 6. Resolve the two currency abstentions (035, 041) — the gate that blocks everything else

**(a) What it is.** `receipt-035` and `receipt-041` are Russian corporate
fuel-card slips with **no fiscal furniture** — no ККТ/ИНН/ОФД, no ₽, no QR — so
`CurrencyDetection`'s document-evidence gate returns nil, which in turn blocks the
band (keyed on currency) and the three-decimal rule (if you gate it on currency).
Their litre/price pairs (`70.44 X 39.000`, `68.44 X 54.000`) are otherwise
trivially resolvable by option 1. The only honest signal left is the Russian
text (`АЗС`, `ТРК`, `Бензин G-Drive 95`) and price magnitude — both of which the
gate was built to *not* use.

**(b) Layer.** Parser (currency), but it unblocks the parser's band/option-1.

**(c) Gain.** +2 currency, and it unblocks +4 litres/price (035, 041). Total **+6
conditional**.

**(d) Cost.** Small, but it is a *policy* change, not a lookup.

**(e) Wrong-answer risk.** Real. "Language + magnitude ⇒ currency" is exactly the
"currency from magnitude" heuristic the product declined, and it would mislabel a
hypothetical KZ or a Ruble-denominated non-RU slip. **Prefer option 1's
currency-independent magnitude guard**, which recovers 035/041 litres/price
without ever touching currency — leaving currency nil is the honest answer for
these two.

**(f) Generalises?** No — this is the one proposal I would not ship as written.

---

### 7. Recognition knobs (customWords, revision, minimumTextHeight, language list) — measure, but expect ~0

**(a) What it is.** `VisionTextRecognizer` sets `.accurate`, `usesLanguageCorrection
= false`, and a language list, and leaves `revision`, `minimumTextHeight` and
`customWords` unset. The language list `["en-US","de-DE","pl-PL","cs-CZ","ru-RU"]`
omits Estonian and Kazakh; `automaticallyDetectsLanguage` is left at its default
`true`, which **overrides** `recognitionLanguages`, so the list may be moot today.
Each is a one-line experiment against the corpus via the existing Spike A/B
harness.

**(b) Layer.** Recognition.

**(c) Gain.** Unknown, and here is how to measure it in an afternoon: run the
corpus once per knob (customWords = {ИТОГ, НДС, СКИДКА, ОКРУГЛЕНИЕ, АИ-*, К5, РУБ,
EUR/L, miles, 95E0, D B0}; `minimumTextHeight` = 0.01; `revision` = the current
major; `automaticallyDetectsLanguage` = false with an explicit `et-EE`/`kk-KZ`
added). **Expected ≈ 0 on receipts**, because the table at the top of this file
shows every relevant glyph is already read at confidence 1.00. `customWords` is
the only one with a plausible receipt gain — the smeared grades — and those are
print defects a dictionary bias will not unsmear.

**(d) Cost.** Cheap to try, no iPhone 12 risk (Vision runs fine on the 12).

**(e) Wrong-answer risk.** Low (these only bias reading, never fabricate values),
but "no gain" is the most likely outcome, so it is last.

**(f) Generalises?** The measurement is the answer; do not ship any knob whose
corpus gain is zero.

---

### 8. Image preparation (contrast, deskew, binarise, crop, upscale) — not for receipts

**(a)-(b) Layer.** Preparation. **(c) Gain.** ~0 for receipts: the OCR dump shows
no receipt operand read below confidence 1.00, and `docs/EXTRACTION.md` already
records the split — receipts fail on *interpretation*, pumps on *recognition*.
`pump-058` (grey-on-grey) is the real low-contrast case and it is pump mode,
outside this question. **(d) Cost.** a few hundred ms on an iPhone 12 per image,
for nothing. **(e)/(f)** Skip for receipts.

### 9. Second-pass region re-recognition — not for receipts

Same verdict as 8. The nil litre/price cells are abstentions over correctly-read
operand lines, not OCR failures, so re-OCR of a crop adds a Vision pass and
recovers nothing. The only regions worth re-reading are the smeared grades
(`) BC`, `ДИ-95`, `AM-95`, `АИ-96`) and those are thermal-print defects — the
same smear reads back at the same confidence on a re-pass. Cheap to build on top
of RV.48's persisted crop rects, but the expected receipt gain is zero; file it
for pump mode if anything.

---

## The ceiling

With options 1–4 (deterministic rules + QR, no guessing):

| source | cells | running total |
|---|---|---|
| today | 173 | 173 |
| three-decimal volume rule (002/018/035/040/041) | +10 | 183 |
| zero-operand volume (034) | +1 | 184 |
| total-finder fixes (001/038/018) | +3 | 187 |
| QR total (017; 018 already counted in the finder fix) | +1 | 188 |

Add the conditional option 5 (LPG band, +2) and you reach **190/210 (90.5%)**. I
would call **188/210 (89.5%)** the honest on-device ceiling for this corpus, and
190 if the product re-opens the LPG band.

**The misses that are unreachable in principle by rules, and their reasons:**

- **receipt-007** (2 cells): the canonical swap, `43.61 Х 99.40`, both operands
  in the 40–500 band, both two decimals. Only the user's own price history
  (ladder step 3) can settle it — and that is what it exists for.
- **receipt-008** (2 cells): `48.89 Х 48.80`, 0.2% apart. Even history is a coin
  flip here; leaving nil is correct.
- **receipt-025** (3 cells): mixed receipt, service line ahead of the fuel line,
  and the hardest swap (`43.38 Х 38.28`, Moscow 2019 ≈ 43.4). Only a
  region+era price prior resolves it, and `receipts/README.md` §5b already
  demonstrated a national band cannot (Yakutsk vs Moscow). User history.
- **receipt-029** (2 cells): `43.24 Х 58.51`, both in band. 58.51 is the 2021
  АИ-100 price; only history resolves.
- **receipt-027** (3 cells: litres+price+fuelKind): the fuelKind is `АИ-96` — a
  confident Vision misread of 95 — and snapping it is the resolve-by-resemblance
  move the history forbids. Its litres/price are collateral.
- **receipt-042** (1 cell fuelKind), **receipt-043** (3 cells), **receipt-044**
  (1 cell): garbled/smeared grades (`) BC`, `ДИ-95`, `AM-95`). Resemblance
  forbidden; recognition reads them at confidence 1.00 so no knob fixes them.
- **receipt-041** total (1) + currency (1): garbled total label (`ИтогО:` →
  `*O:`) and no fiscal furniture.
- **receipt-035** currency (1): no fiscal furniture.

That is roughly 20 cells, of which ~7 are scorable *only* by a real user's price
history in production — so the corpus ceiling understates what an active user
actually sees.

## What I would not do

- **Trained model / SLM for receipts.** `docs/EXTRACTION.md` already decided this:
  the corpus *is* the test set, so a model trained on it cannot be scored by it,
  and the misses are still nameable rules. The three-decimal rule above is the
  proof of the point — one of the largest remaining blocks falls to ~15 lines of
  deterministic code.
- **Cloud LLM for these misses.** Rule 1 (local-first) and the P4.12 latency
  measurement (12–36 s against a 3 s budget) both say no; the gateway already
  exists as a separate, late-answer path.
- **Restoring a decimal-*digit-count* tie-break.** This is the exact trap
  `HIGH-WATER.md` documents: `25,52 X 70.92` won by iteration order and the same
  code swapped `receipt-007`. Option 1 is a *three-decimal* rule with a magnitude
  guard and a marker-path exclusion — deliberately not the removed tie-break.
- **Relaxing the resemblance prohibition to snap grades.** Snapping `АИ-96`→95,
  `ДИ-95`→`АИ-95`, `AM-95`→`АИ-95`, `) BC`→`D B0` would score +4 fuelKind plus
  downstream, but it is the confident-wrong-value failure the whole design avoids,
  and `high-water.json` records that two independently-dispatched models reached
  that verdict. Not for a score.
- **"Integer operand = volume".** Would gain zero corpus cells today (027/043 are
  blocked by fuelKind, not by the shape), and carries a real swap risk on a
  whole-rouble price. Not worth it.
- **Currency from magnitude/language** (option 6). The product already declined it;
  option 1 recovers 035/041 litres/price without it.
- **Image preparation and region re-OCR for receipts.** Measured no-op: the glyphs
  are already read at confidence 1.00. They are pump-mode tools.

---

## What I actually read

`receipt-field-report.txt` in full; `receipt-ocr-lines.txt` in full (all 2184
lines, so every claim above carries a conf value, not a fixture name alone);
`HIGH-WATER.md`; `high-water.json` including the truncated `_note` (extracted
whole with `python3 -c`); `receipts/README.md` in full; `docs/EXTRACTION.md` in
full; `VisionTextRecognizer.swift`; `VisionRequestGate.swift`; `OCRLine.swift`;
`FuelExtractor.swift` (entry point, volume/price ladder, `resolveUnmarked`, the
total-finder, `TotalLabel`, `OperandPair`, `NumberScanner`);
`FuelPriceBands.seed.json`; `CapturePipeline.swift` (including `CaptureQRDetector`
and the language list); `ExtractionAssembler.swift`; `FiscalQR.swift`; and all 22
`.qr.txt` payload files.
