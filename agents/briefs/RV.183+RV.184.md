# RV.183 + RV.184 - the attachment viewer's "What was read" page

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Two rows, one dispatch**: both edit `ios/App/Sources/EditEntry/AttachmentRecognisedView.swift`.

## RV.183 - "Scanned 9 Sep at 00:00"

Product owner, 2026-09-10, with a screenshot: *"capture time is not accounted on the photos."*

**Cause pinned - three faults in one line.** `AttachmentRecognisedView.swift:30-33` renders
`extractedTimestamp` under the word **"Scanned"**, and `scannedLine` (`:147-148`) formats it
`.hour().minute()`. But `docs/SCHEMA.md:335` defines that field as *"printed date on receipt / QR
timestamp"* - **the date the RECEIPT carries**, which is date-only, so it renders midnight.

1. The label says *scanned*; the value is the receipt's own date.
2. The formatter asserts a minute precision the value does not have.
3. **The real capture time is on the same record and unused** - `Attachment.createdAt`, set to
   `Date()` in `ManualFillUpReceiptSave.writeReceiptAttachment`.

A user reading `00:00` cannot tell whether the app lost the time or the receipt never had one.

### What to build

**Show the capture time from `createdAt`, and let the receipt's printed date be what it is** - the
field table already has a `Date` row carrying it, so the caption should be the capture and say so.

**Never format a date-only value with a time.** If a value has no time component, render the date
alone. **Decide whether that rule belongs in `docs/DESIGN.md`** beside the DIN/units rules, and
record the decision either way.

Note `AttachmentRecognisedView` currently receives only `extractionMeta`, `ocrText` and
`extractedTimestamp` (`AttachmentViewerView.swift:190-192`); `createdAt` is available at the call
site and will need passing in.

## RV.184 - the station is extracted and never shown

Product owner, 2026-09-10: *"on the scanned receipt, worth to show what was the station name
extracted."*

**The page is already ready.** `AttachmentRecognisedView.swift:206` has
`case .station: return L10n.localize("Station")`, so `FieldRef.station` exists and the row would
render.

**The gap is upstream.** `ScannedSavePlan.assignment(from:)`
(`ios/Sources/TankbookCore/Domain/ScannedSavePlan.swift:139-169`) builds the stored `ExtractionMeta`
from total, volume, unitPrice, date, currency and fuelKind - and **never writes `.station`**, so
nothing reaches the viewer. [RV.161] added `FuelExtraction.stationName` and wired it to the Confirm
pre-fill; that was its fence, and this is the half outside it.

### What to build

**Add the station to the assignment**, beside the six fields already there, so the stored record says
what the scan concluded about the station exactly as it does for the others.

This is **presentation of a STORED conclusion**, not a fact and not a source: hard rule 13 is
untouched, nothing feeds back into the entry, and `FieldExtraction.userCorrected` already marks a
field the user changed.

**Check the viewer renders a plain string correctly** - the existing rows are money, number, date,
currency and fuelKind, so a text value may be a case the formatter has not met.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. **Confirm the caption really reads `extractedTimestamp`**
and that no station reaches the assignment, before changing either. The orchestrator's diagnoses have
been wrong four times this session and an agent caught every one.

## Explicitly out of scope

- Re-running OCR in the viewer. The page is presentation of stored data; a fresh read could
  contradict values the user already confirmed (hard rule 13), and the file's own header says so.
- [RV.161]'s extractor and the Confirm pre-fill.
- [RV.179]'s corpus measurement of station accuracy.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` → **Attachment & extraction provenance** - `createdAt`, `extractedTimestamp` and
   what each means. **The authority for RV.183's whole argument.**
2. `docs/EXTRACTION.md` → the per-field assignment and the station role ([RV.161] extended it today).
3. `docs/ERRORS.md` → the attachment-viewer rows.
4. `CLAUDE.md` hard rules 12, 13.

## Environment axes this crosses

**Locale** - a reworded caption and the Station row's label, EN and RU, gate at 100%. **Screenshots:
EN and RU** of the recognised page showing the Station row and the corrected caption. No offline
path. Release build if you touch a `#if DEBUG` seam.

**Add capture lines to `scripts/capture-screenshots.sh` for any screenshot you commit** - three rows
shipped out-of-band screenshots in the last day ([RV.176]). `-openAttachmentViewerRecognised` already
exists (`RV.48`).

## Tests you must add

- **L1, RV.183, and it FAILS TODAY**: the caption reads from `createdAt`, **not**
  `extractedTimestamp` - assert the **SOURCE**. Both are `Date`, so a test asserting "a date renders"
  passes on the defect.
- **L1**: a date-only value never renders a time component.
- **L4, RV.183**: a receipt whose **printed date differs from the capture day** shows BOTH,
  distinctly. **The fixture must have them differ**, or the two fields are indistinguishable and the
  test proves nothing.
- **L1, RV.184**: a scan that resolved a station stores it in the assignment - assert the **VALUE**.
- **L1**: a scan that resolved none stores **no** station field, never an empty one ([RV.48]'s rule:
  a field the parse did not assign is absent, never a blank row).
- **L4, RV.184**: the page shows the Station row with the extracted name, EN and RU.

Report each suite's observed, **non-zero** count, and **filter by the suite name, not the file's** -
on 2026-09-10 a class-name filter matched nothing and printed `TEST SUCCEEDED` on zero tests.

## The mutation you must run - I am naming it, do not choose your own

**Point the caption back at `extractedTimestamp`.** The RV.183 L1 **must go red on the SOURCE**, and
the RV.184 station tests must stay **green**. Then restore and re-run. Report both outputs verbatim.

That split matters because both fields are `Date`s: the test has to fail on *which field*, not on
*a date being present*.

## Vacuous traps, named

- **A fixture where the scan day and the receipt's printed date are the same** - passes either way,
  and it is RV.183's headline trap.
- Asserting the caption string contains a date.
- Fixing the label and leaving the `.hour().minute()` formatter on a date-only field.
- Asserting a station row **appears** without asserting **which** station.
- Writing an empty station field for a scan that found nothing.
- Feeding the stored assignment back into the entry, which would overwrite a station the user chose.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. An agent's `git stash` +
`mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source** - it reuses the previous binary, and on 2026-09-10
that photographed a mutated build and presented it as proof of a fix.

## Standing checks

As left, `main` is **1864 tests / 222 suites**, **829** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full, never subsetted; report the count.
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then each UI suite you touched **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. Release build if you touch a `#if DEBUG` seam.

Verify by **exit code** (`echo $?`).

## Report back

Every check with the **exit code observed** and the counts; run or only written; **the mutation's
red-then-green output, verbatim**; whether the viewer needed a new value case for a plain string;
your decision on the date-only formatting rule and where you recorded it; and **anything you found
and did not fix**.
