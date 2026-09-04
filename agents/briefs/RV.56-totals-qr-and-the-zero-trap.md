# RV.56: the three unanimous fixes - the zero trap, the QR the score ignores, and the total finder

Design and implement. Code first, exploration second.

Three independent research agents (`diagnostics/RV.57-options-{qwen,kimi,deepseek}.md`) analysed
this corpus from scratch. **These three items are the ones all three agreed on**, and they carry no
wrong-answer risk. The one they disagreed about - a decimal-format rule for unmarked operand pairs -
is **deliberately not in this brief** and must not be implemented: it is a product decision that has
not been taken. If you find yourself inferring which operand is the price from how many decimal
places it has, stop; that is out of scope.

## Where you work

    /Users/sbelyaev/repos/fuel-counter-ios/.claude/worktrees/rv48   (branch rv48-local-extraction)

Write only inside it. **Never `cd` to the main checkout** - another session is live there and
commits to `main` regularly. **Run no `git` command at all**; leave the work uncommitted for the
orchestrator to verify and commit. Do not touch `docs/TASKS.md`, `agents/briefs/`, any
`expected.csv`, or any fixture image.

**Never `pgrep -f`** - your brief is your command line, so it matches you. Use `pgrep -x`.

## Where the corpus stands right now

**Receipts 180/220 cells.** Misses: `liters=14 unitPrice=13 total=7 fuelKind=4 currency=2`. Two
fixtures (receipt-047, receipt-048) arrived from trunk an hour ago, so the numbers differ from the
research reports, which were written against 173/210 - the fixture-level findings below still hold,
but **re-measure before and after rather than trusting any number in this brief**:

    cd ios && TANKBOOK_WRITE_CORPUS_FILES=1 TANKBOOK_DIAG_OUT=/tmp/rv56 \
      swift test --filter ReceiptFieldDiagnostics

`/tmp/rv56/receipt-field-report.txt` is per fixture and per field; `receipt-ocr-lines.txt` is the
raw Vision output with bounding boxes, confidences, and `[FILTERED …]` markers.

---

## 1. The zero-operand guard - do this one FIRST, it is a live trap

`receipt-034` is a B2B contract fuel card: it prints `30.61 Х 0.00` with "Цена определена
договором". The volume is printed and unambiguous; only the price is contract-hidden. Today the
ladder abstains on both, which costs one cell.

**The trap is worse than the missing cell.** Ladder step 3 (the user's own price history) is wired
in the app through `AppFuelPriceBand` and is invisible to the corpus scorer. With a realistic
median - say 65 - `resolveUnmarked` evaluates this pair as
`leftPlausible(|30.61 - 65| = 34.4 <= 39)` against `rightPlausible(|0 - 65| = 65 > 39)` and returns
**`(liters: 0.00, price: 30.61)`**: a zero-litre fill at a price that is really a volume. Nothing
catches it. `extract()` already maps a zero total and a zero unit price to nil (lines 48-62, and
the comment there is the doctrine: "a printed ZERO is *the price is not on this receipt*, never
*the fuel was free*") - but **there is no zero-litres guard**.

Two changes:

- **A zero operand names the price, not the volume**: when exactly one operand is `0.00`, resolve
  the other as the volume and leave the price nil. The research disagreed on whether to require the
  product line to declare the unit (`receipt-034` prints `Plus (AИ-95-К5), л`, stranded from the
  pair by the layout); decide, and say why.
- **A zero-litres guard in `extract()`**, mirroring the existing zero-total and zero-price ones.

Gain: +1 cell. Its real value is closing the trap before anything exposes history to more inputs.

## 2. Wire the fiscal QR into the scored path

`CaptureQRDetector` decodes the QR at capture time, `FiscalQRParser` parses it, and
`ConfirmQRTotal.resolve` already decides OCR-versus-QR for the total - **in the app**. The corpus
scorer measures `FuelExtractor` on OCR alone, so none of that is in the 180/220 number, and the app
is therefore better than its own gate says.

The QR carries `s` (grand total) and `t` (date) and **nothing else** - no litres, no unit price, no
fuel kind, no currency - so it closes totals and dates only. `22` `.qr.txt` files sit beside the
fixtures.

- Compose the QR into the scored extraction where one is present.
- Keep **hard rule 4**: on a mixed receipt the fuel amount is the fuel line, never the grand total,
  and the QR carries the grand total. `receipt-025` is the case; the QR must not override it.
- One research finding to check rather than assume: the QR agreement tolerance is said to be about
  1 rouble, which would swallow `receipt-017`'s 0.80 discount - *"a discount, not noise"*. Look at
  `ConfirmQRTotal` and decide whether that tolerance is right for the scored path.

Expected: 2 wrong totals retired (017, 018), plus four garbled dates fixed for free (010, 019, 031,
008). Dates are not scored, so the cell gain is small and the correctness gain is not.

## 3. The total finder's three named bugs

Each has a fixture and a diagnosis. Verify each against the dump before fixing it.

1. **Net versus gross on the Estonian layout** (`receipt-001`, `receipt-038`). On `receipt-001` the
   gross `125,22` is the item-column value at y=0.713, while the `KOKKU` label at y=0.636 shares a
   baseline with `100,98`, the `KÄIBEMAKSUTA` **net**. `pairedValue` takes the net; the gross is one
   baseline up, just outside the 0.012 midY window, so the finder returns nil. `receipt-038` is the
   same shape (`79,32` gross against `63,97` net). The gross appears four or more times at
   confidence 1.00, so the modal value across the `Summa` column is the better source. **Do not
   simply widen the 0.012 window** - it is what stops a neighbouring row being read as the total;
   if you widen it, prove with the report that nothing else mispairs.
2. **A leading minus is not a disambiguator** (`receipt-018`). `ИТОГ` pairs with `-3555.89` - the
   `СУММА НДС 22%` amount one line lower - because `NumberScanner.value` silently drops the leading
   `-`. The real total `=19719.00` sits *above* the label. A value line beginning with `-` is a
   subtraction line and never a total candidate.
3. **A `СКИДКА` line between the extension and the total** (`receipt-017`). The finder returns the
   item extension `961.80` and ignores both the `СКИДКА =-0.80` line and the discounted `=961.00`.
   Prefer the discounted total - or let the QR settle it, if item 2 lands first.

Expected: +3 cells, and it removes two of the three confident-wrong values in the class. **After
this and item 2, the receipt class should contain no confident-wrong value except `receipt-025`'s
mixed-receipt total** - state in your report whether that held.

---

## What must not change

- **Hard rule 13.** Every path either resolves for a stated reason or returns nil. The class
  currently has three wrong values and everything else is an honest abstention; that ratio must
  improve, never worsen.
- **No decimal-format or operand-position rule** (see the top of this brief).
- **No confidence thresholds.** Vision reads wrong digits at confidence 1.00 - a named corpus fact.
- The parser must stay a pure function over `[OCRLine]` plus injected providers: no Vision, no
  network, no image access in `TankbookCore/Extraction`.

## Tests

- `cd ios && swift test` is **1321 tests in 126 suites** as of the last trunk merge - check the
  current number yourself, trunk moves. It must still pass and the count must rise.
- A test per fixture named above, driven by `extract(textLines:)` with lines quoted exactly as the
  dump shows them, misreads included.
- **Mutation-check every load-bearing change** and report each: the mutation, the test that failed,
  and confirmation the file was restored byte-identical. Vacuous traps here: asserting a total is
  non-nil rather than asserting its VALUE; a minus-sign test whose line would parse the same
  without the fix; a QR test that passes with the QR absent.
- If a recorded mark moves, update it: `Spike/ReceiptSpike/fixtures/high-water.json` (numbers and a
  `_note` entry in the existing style), `CorpusCompressionTests.recordedReceipts`, and
  `PumpPhotoGate` if the pump class moves.

## The baseline gate - judged by exit code

    cd ios && swift build      # 0
    swiftlint lint             # from the REPO ROOT, 0 errors
    cd ios && swift test       # 0, count risen

Report all three from `echo $?`.

## Out of scope

The decimal rule, the pump class, image preparation and recognition knobs (all three agents
measured them as no-ops for receipts), the cloud gateway, the backend, and any fixture change.

## If you run short of budget

Land item 1, then 3, then 2, saving as you go. Item 1 alone is worth committing - it closes a trap
that is live in the app today.

## Report back

The three exit codes and the test count; corpus before and after, per class; which fixtures moved;
whether any confident-wrong value remains and which; every mutation check; and anything you chose
not to do and why.
