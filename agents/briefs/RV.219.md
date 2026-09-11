# RV.219 - the QR date is parsed, tested, and never applied

**Scenarios: J5 · the RU/KZ receipt (the fiscal QR as an anchor) and F5 · the QR decodes and nothing
more is fetched.** This is the ONE row holding both scenarios open. When it lands, both are re-walked
for their `Status: implemented` lines - so the fix must satisfy the journey text, not just the row.

## The defect, found twice independently

`REVIEW-SCENARIO-J5-2026-09-11` and `REVIEW-SCENARIO-F5-2026-09-11` landed on the same line without
seeing each other, and the orchestrator confirmed it in the tree:

- `ExtractionAssembler.assemble` calls `FuelExtractor(...).extract(lines:source:)` **without** the
  anchor, parses the QR **afterwards**, and only carries it on `CaptureAssembly`
  (`ios/Sources/TankbookCore/Extraction/ExtractionAssembler.swift:54-60`).
- The **total** is rescued downstream: `ConfirmQRTotal.resolve(extraction:qrAnchor:)`
  (`ConfirmPrefill.swift:166`) makes the QR total outrank OCR at the confirm step.
- The **date** has no such rescue. `FuelExtractor.composeQR` (`FuelExtractorTotalFinder.swift:18-31`)
  would apply it - and `qrAnchor:` is passed to `extract` **only from tests**
  (`grep -rn "qrAnchor:" ios/Sources` shows no production caller). `ManualFillUpView.apply` sets
  `form.date` from the OCR date alone (`ManualFillUpView.swift:402-404`).

J5 promises *"total and date land exact from the QR"*. Today that is true of the total only. A RU/KZ
receipt whose OCR date is garbled, absent or in the wrong zone keeps the wrong or empty date even
though the QR carries the exact timestamp. **Tested but not shipped** - `RV.129`'s shape.

## What to build - one path, not a second override

**Parse the QR first and pass the anchor into `extract`**, so `composeQR` runs in production and the
extraction's date comes from the QR when the QR has one. Do NOT add a second date override in
`ManualFillUpView.apply` - that would be two places deciding the same field, which `RV.169`-`RV.171`
exist to prevent. Read `docs/SCHEMA.md` -> FISCAL QR for the precedence rule (the QR outranks an
absent or garbled OCR date) and `docs/EXTRACTION.md` for the cross-check outcomes, and make sure a
QR date does not silently win over a **confident, agreeing** OCR date in a way that changes an
existing fixture's result.

**Check what else `composeQR` does when it runs.** It may also resolve the total - which the
downstream `ConfirmQRTotal.resolve` already does. If both now apply, decide which is the one place
and say so; if they agree byte-for-byte, the downstream one may stay as the confirm-step guard. Do
not leave two silent writers of the same value.

## Corpus gate

The accuracy ratchet (`AccuracyRatchetTests`, `CorpusCompressionTests`) already exercises
`qrAnchor:` from tests. **Run the full package suite and report the corpus scores.** If applying the
QR date in the assembler moves a score, report which fixture and why - a QR date correcting a
misread OCR date is the point; a QR date overriding a correct one is a regression.

## Tests you must add

- **L1, and it FAILS TODAY**: assembling a receipt whose OCR date is garbled and whose QR payload
  carries a timestamp yields `extraction.date` from the QR. Oracle: `SCHEMA.md` FISCAL QR.
- **L1**: the same receipt with a confident OCR date that AGREES leaves the date unchanged and the
  source unchanged.
- **L1**: `RV56ExtractionTests.swift:233` still passes - it is the case that already covered the
  test-only path.
- **L4 `CaptureUITests` EN + RU**: on a QR-carrying fixture with a garbled printed date, the Confirm
  form's date field shows the QR date. Capture lines added; both frames shot.

## The mutation you must run - named, do not choose your own

Remove the anchor argument from the assembler's `extract` call again and show the new "date from the
QR" L1 goes red. Restore byte-identical, re-run, report both outputs verbatim.

## Vacuous traps

- Setting `form.date` from `qrAnchor.date` in the view - a second path.
- A test that asserts the anchor is *present* on the assembly rather than that the date *landed*.
- Making the corpus green by loosening the ratchet.

## Docs

`docs/JOURNEYS.md` J5 and F5 already promise this; **do not edit them** unless the behaviour you ship
differs from the text - then change the text to match, in the same change, and say why.
