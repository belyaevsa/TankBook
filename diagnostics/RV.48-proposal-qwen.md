# RV.48 research - qwen3.8-max's analysis, salvaged from its transcript

**Provenance, stated plainly.** The agent `RV.48-research-qwen`
(`alibaba-token-plan/qwen3.8-max`) read both evidence dumps end to end, the whole of
`ios/Sources/TankbookCore/Extraction/`, `docs/EXTRACTION.md`, both fixture READMEs and
`HIGH-WATER.md`, reached its conclusions, printed *"Writing the report now"* - and was killed by
SIGTERM one step before it wrote the file. **This file was reconstructed by the orchestrator from
its 236 KB transcript**, not written by the agent. The findings are its work; the arrangement is
mine, and every claim marked VERIFIED below I checked against the source myself rather than taking
on trust.

## The headline: four confident-wrong values, each traced to a mechanism

The report showed four fixtures where the parser returned a **wrong** volume rather than
abstaining. Qwen traced every one to its exact cause:

| fixture | got | the line that caused it | mechanism |
|---|---|---|---|
| receipt-023 | `32986034.000` | `wNLL32986034/90` (confidence **0.30**) | `loneMarkers` volume path |
| receipt-046 | `10180925.000` | `Reg.kood 10180925, KMKR nr• EE1003L` | `loneMarkers` volume path |
| receipt-041 | `5.000` (want 54) | `2X5LT6` - a card **authorisation code** | `OperandPair` reads it as `2 X 5L`, and `5L` carries a volume marker, so the fuel-line path prefers it |
| receipt-044 | `1.000` (want 25) | `1 ед.=1 литр для нефтепродуктов/суг` | `loneMarkers`, and the same line also produces the wrong `lpg` fuel kind |

`2X5LT6` is the sharpest of the four: an auth code that happens to contain a digit, an `X` and an
`L` parses as a complete operand pair with a unit marker. No cleaning stage means every id on the
paper is a candidate operand.

## VERIFIED: `hasVolumeMarker` is case-sensitive, and it costs four cells

    var hasVolumeMarker: Bool {
        firstMatch(of: /\d\s*[лL]/) != nil || firstMatch(of: /[лL]\s*\d/) != nil
    }

The character class is Cyrillic **lowercase** `л` (U+043B) and Latin **uppercase** `L`. It does not
contain Cyrillic uppercase `Л` (U+041B) or Latin lowercase `l`. I checked the source: this is
exactly what `FuelExtractor.swift:454` says.

Consequence, traced through the ladder on `receipt-031`: the fuel line `69.98 Х 30 Л` is not
recognised as carrying a volume marker, so `OperandPair.fuelLine` skips it and the code falls back
to `OperandPair.first`, which picks the **`БЕЗ СКИДКИ 30.000 Х 71.05`** list-price line instead -
and that one has no markers either, so the ladder abstains. `receipt-037` (`99.99 Х 25 Л`) dies the
same way. A one-character fix, `[лЛL]`, worth **+4 cells**.

## VERIFIED: `СУММА` in Cyrillic is not a total label

`TotalLabel.primary` is `["ИТОГ", "ВСЕГО", "К ОПЛАТЕ", "TOTAL", "KOKKU", "SUMMA", "AMOUNT"]`
(`FuelExtractor.swift:488`). `SUMMA` there is **Latin**; `receipt-036` prints Cyrillic `СУММА:`
against `2499.75 РУБ` on the same baseline, matches nothing, and its total comes back nil. One
vocabulary entry, **+1 cell**.

## The ranked changes

### C1. RUB document-evidence gate (+28 cells)

Mirror the existing KZT gate (P2.10). Qwen checked `ИНН` on all 46 fixtures one by one: present on
26 RUB receipts, absent from every EUR and from the Kazakh `receipt-033`. Two RUB fixtures
(`receipt-035`, `receipt-041`) need secondary tokens (`ОСТАТОК ЛИМИТА`, `ТОПЛИВНАЯ КАРТА`), and it
confirmed neither token appears on any Estonian or Kazakh fixture. Precedence unchanged: explicit
marker, then Kazakhstan, then Russia.

### C2. The line/token noise classifier (+0 direct, removes 5 wrong values, enables the rest)

Two layers, and Qwen's argument is that **both** are needed:

1. **Line classification** by witnessed patterns, in six classes: N1 Russian fiscal ids
   (`\bИНН\b`, `(ЗН|РН)\s*ККТ`, `ФН`, `ФД`, `ФП`, bare `^\d{14,16}$` value lines), N2 Estonian
   registration and payment (`REG\.\s*KOOD`, `KMKR`, `STAATUS`, `KAUPMEES`, `ATC`, `AID`,
   `^A[0-9A-F]{10,}`), N3 terminal and card block (`RRN`, `TID`, `ТЕРМИНАЛ`, `КОД АВТОРИЗАЦИИ`,
   `ОДОБРЕНО`, masked PANs, `^\d{17,}$`), N4 unit-convention lines (`1\s*ЕД\.?\s*=`),
   N5 addresses, phones and URLs, N6 the Estonian VAT table.
2. **Token-level marker hygiene**: the volume marker must be a standalone token, i.e.
   `(?<!\p{L})[лЛL](?!\p{L})`. This is what kills `2X5LT6` (the `L` is followed by `T`) and
   `wNLL32986034` (the `L` is preceded by `L`).

Neither layer alone is sufficient: `EE1003L` on receipt-046 ends in a token-final `L` and passes the
hygiene rule, so it needs the `Reg.kood` line class; `2X5LT6` sits on an unlabelled line, so it needs
the token rule.

**Crucially, the classifier tags rather than deletes.** Since Q5 keeps the raw text, nothing is lost -
noise lines are excluded from *candidate* generation only.

**What must never be tagged noise** (Qwen's list, and the more valuable half of the answer):
product lines, operand lines, `ИТОГ`/`KOKKU`/`SUMMA`/`ЖИЫНЫ` totals, dates, currency carriers,
discount lines, stranded marker lines (`л =5380.00`), and **bare short-decimal value lines** - a bare
`5380.00` *is* the total, so no digit-count rule may touch short decimals. It also flags that the
`Справочная информация` / `Цена за ед.` block is **data**, being the only source of receipt-023's and
receipt-044's unit price. (Kimi reached the same two conclusions independently.)

### C3. `hasVolumeMarker` case fix (+4) - see VERIFIED above

### C4. Estonian `/L` self-reading (+5)

`1,744 EUR/L`-style lines carry the label and the value on the same line; the current
price-per-unit path only looks *below* a bare label. Fixes 038, 039, 042, 045, 046.

### C5. Labelled-column vocabulary and partial columns (+6)

Three separate gaps: `ЕДИНИЦ` missing from the quantity-header vocabulary; `ЦЕНА ЗА ЕД` missing from
the price-per-unit labels; and structurally, `labelledColumn` **returns nil unless both headers are
found**, so a receipt with a quantity column and a price stated elsewhere resolves neither. The fix
is to let step 1 contribute partially and let later steps fill the rest. Fixes 023, 030, 044.

### C6. Multi-operator line (+1) - `Аи-98 х25.00 лит х99.99 РУБ` on receipt-036

### C7. Fuel-kind vocabulary (+9 or +10, and kills the one wrong value)

`D B0 miles` / `95E0 miles` (Estonian loyalty grades), `АИ` misread as `AM`/`АЙ` (Latin homoglyphs),
and receipt-044's `lpg` which the C2 cleaning removes at the source. Qwen's own caution:
**`receipt-027`'s `АИ-96` must not be snapped to 95.** `АИ-96` is not a retail grade, so it looks
fixable, but that is resolution-by-resemblance and `HIGH-WATER.md` forbids it. (GLM reached the same
verdict independently, which is the strongest signal in this whole exercise.)

### C8. Zero-operand rule (+1) and zero-litres to nil

`30.61 Х 0.00` on receipt-034 is a contract fuel card: the volume is certain, the price is not.
Separately, `receipt-039`'s `Kogus 0,00L` should map to nil like price and total already do -
a zero volume is "no purchase", not a measurement.

### C9. The price band (step 4) - +22 firm, up to +38

Qwen worked the band case fixture by fixture and reached the same conclusion my own simulation did:
**it must be keyed by fuel kind and era, not currency alone.** Its per-fixture verdicts:

- resolves cleanly: 003, 004, 005, 014, 015, 024, 026, 032 (a RUB band with a floor around 40),
  plus 012 (LPG band 15-45), 017 (diesel 2020, 30-80), 027, 028, 033 (KZT), 035.
- **band-width dependent**: 043 (`40 Х 120.00` - both operands fall outside a 50-110 band, so it
  abstains unless the band reaches 150), 007 (the receipt-007 swap fixture - resolves only if the
  petrol-100 band excludes 43.61), 002/018 (Crimean 450 RUB/L needs a regional band).
- **cannot be resolved by any band**: 025, 029, 040, 041 (both operands plausible - these need
  step 3, the user's own history) and 008 (`48.89 X 48.80`, honestly undecidable).

### C10. Storage (Q5)

Store the concluded assignment on `Attachment` as a field map with per-field confidence; a field the
parse did not assign is **absent**, never an empty string, and a parse that assigned nothing stores
no map at all. **Keep the raw OCR text** - it is what lets a bad parse be re-examined and what
`docs/EXTRACTION.md`'s failure modes depend on - and rely on the classifier's tags rather than
deletion for the privacy concern. Schema evolution per hard rule 9: registry plus declarative
transform, no backend deploy.

## What Qwen would NOT do

1. Restore the decimal-count tie-break in any clothing. `receipt-033` supports "3 decimals means
   volume"; `receipt-037` (`25 Л`, zero decimals) and `receipt-043` (`40 Х 120.00`, volume has
   fewer decimals) each refute it.
2. Add an operand-**position** rule. True on the Crimean `PRICE*QTY` slips, false on receipt-031's
   `БЕЗ СКИДКИ` line and on receipt-037.
3. Infer currency from magnitude (the existing charter).
4. Key fuel kind on any octane digit anywhere in the document - `АЗС-98`, `ТРК №3` are not grades.
5. Promote a `БЕЗ СКИДКИ` list price to the unit price (receipts 010, 031): the price paid, only.
6. Treat a VAT rate as a fixed per-country constant (16% on 033, 22% on 037, 24% on 045).
7. Resolve an unmarked pair by the product against the total - symmetric, so it proves nothing.
8. Use an OCR **confidence threshold** to accept or reject a value. Even the noise classifier keys
   on shape, never on confidence: `pump-004` misreads at confidence 1.00, and the 0.30-confidence
   `wNLL32986034/90` line is killed by its id shape instead.

## The arithmetic

    baseline                                            101/210
    C1 RUB gate                                            +28
    C3 volume-marker case                                   +4
    C4 Estonian /L                                          +5
    C5 columns and ЦЕНА ЗА ЕД                               +6
    C6 multi-operator line                                  +1
    C7 fuel kind                                          +9/10
    C8 zero operand                                         +1
    C2 cleaning                    removes 5 wrong values, +1 total
    ------------------------------------------------------------
    deterministic subtotal                        ~157/210 (75%)
    C9 band, firm                                          +22
    C9 band, conditional                                   +12
    ------------------------------------------------------------
    with the band pack                            ~191/210 (91%)

Remaining after all of it: receipt-008 (honestly undecidable), the four history-dependent pairs, and
a handful of total-finder corner cases (001, 017, 018, 025) that none of the five questions covered.
