# RV.56 – the receipt total is the last field that still returns a WRONG number

Filed 2026-09-04 out of RV.48's measurement. **A wrong total is worse than a missing one** – it lands
in the entry as money, and hard rule 13 makes an abstention the correct answer whenever the document
does not settle the value.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/`, `Spike/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a fixture or any file you did not create** – the corpus is evidence.

## The current marks – use THESE, not the ones in older notes

The corpus grew on 2026-09-04. **Receipts are 180/220**, compression **181/220**, pump 53/261,
fiscal 5/5, screenshots 34/40. `Spike/ReceiptSpike/fixtures/high-water.json` is authoritative; read
its `_note` before you touch anything, it is the change log.

## The cases, each with a stated cause

**Confident-WRONG totals – these are the point of the row:**

- `receipt-017`: returns `961.80` against a printed `961.00`. A `СКИДКА` line reconciles the two.
- `receipt-018`: returns `3555.89`, which is the **VAT amount** – the value sits ABOVE its `ИТОГ`
  label and the pairing reads downward.
- `receipt-025`: returns `1729.87` on a **mixed** receipt where the fuel line is not the grand total
  (hard rule 4: fuel amount is not the receipt grand total).

**Returning nil:**

- `receipt-001`: label and value are 0.018 apart against a 0.012 same-baseline window.
- `receipt-041`: the label itself is destroyed – **honestly unresolvable, and it should stay nil.**
- `receipt-047` (added 2026-09-04): prints `=3765.65` TWICE with a leading `=` and no `ИТОГ` label,
  so the finder has no labelled anchor. Its sibling `receipt-040` hits its total; compare them.

**A lead from the RV.48 research:** `receipt-038`'s total is taken from a VAT row whose column header
is ALSO `Summa`. The two are separable by the sibling tokens on the header's baseline – `Määr`,
`Kood`, `Kirjeldus`, `Kogus`.

## What to build

**Fix the total finder, or abstain.** Take the three wrong values first: **each has a stated cause,
so each is a rule with a reason, not a tolerance to widen.**

**Do NOT widen the 0.012 same-baseline window to catch `receipt-001` without showing what else it
mispairs** – that bound is what keeps a neighbouring row from being read as the total. If you widen
it, report every fixture whose total changed, in both directions.

**Do not resolve by resemblance.** This file's own history forbids it: `receipt-027`'s `АИ-96` was
left unsnapped deliberately. An abstention is a correct answer.

**Reuse the RV.48 diagnostics harness** – it reports per fixture and per field:

    TANKBOOK_WRITE_CORPUS_FILES=1 TANKBOOK_DIAG_OUT=<dir> swift test --filter ReceiptFieldDiagnostics

## Read before writing

1. **`CLAUDE.md`** – hard rule 4 (fuel amount is not the grand total), 13 (the app suggests), 14.
2. `Spike/ReceiptSpike/fixtures/high-water.json` `_note`, and `fixtures/receipts/README.md`.
3. `docs/EXTRACTION.md` – the pipeline, the cross-check outcomes and the named failure modes.
4. `ios/Sources/TankbookCore/Extraction/` – the total finder, `ReceiptNoiseFilter`, `FuelExtractor`.

## Tests

**iOS unit 1322 today; must not fall.**

- **L1 per fixture, from the committed OCR lines**, for each case you change – so a regression names
  the receipt.
- **The headline: ZERO confident-wrong totals in the receipts class.** Assert it as a property over
  the whole class (every fixture either matches its expected total or returns nil), not as three
  individual expectations – that way a NEW wrong total added later fails too.
- The corpus mark and `CorpusCompressionTests` move together; `PumpPhotoGate` should not move.
- Expected direction: receipts 180/220 -> ~186. **Report the measured number, do not assume it.**

**Vacuous-assertion traps, named:**
- Asserting a total equals itself, or asserting only the three fixtures you fixed.
- Buying the number by making the finder abstain everywhere – abstention is correct only where the
  document does not settle it. **Report how many totals are RESOLVED before and after**, not just
  how many are wrong.
- Re-baselining `high-water.json` upward without re-measuring all four classes live in the same run.

**Mutation-check and report it**: revert one of the three rules and confirm that fixture's L1 goes
red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT

**Echo the exit code from the COMMAND, never through a pipe.** Never `pgrep -f`/`pkill -f`.

## Screenshots

None applies – extraction only, no UI change. Say so rather than fabricating one.

## Report back

- Exit codes (captured, not piped), test counts before/after, mutation result.
- **The four class marks re-measured LIVE in the same run** (receipts, pump, fiscal, screenshots),
  and the compression mark – never carried forward from this brief.
- **Totals resolved before and after, and totals WRONG before and after** – both numbers.
- Every fixture whose total changed, in both directions, including any you made abstain.
- Confirmation `receipt-041` still returns nil.
- Anything you noticed that is not RV.56 – named separately.
