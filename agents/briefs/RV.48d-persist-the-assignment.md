# RV.48 stage four: persist what the parse CONCLUDED, and show meaning instead of line soup

This is the half of RV.48 the product owner actually filed. Read the RV.48 row in `docs/TASKS.md`
before anything else (read it; do not edit that file).

> "there are all the data, but for a user and for the app important is only entry data. The data
> must be stripped, filtered and left only meaningful. That's the goal of the local OCR."

## Where you work

    /Users/sbelyaev/repos/fuel-counter-ios/.claude/worktrees/rv48   (branch rv48-local-extraction)

Write only inside it. **Never `cd` to the main checkout** - another session is live there.
**Run no `git` command.** Leave your work uncommitted; the orchestrator verifies and commits.

**Do not touch**: `docs/TASKS.md`, `agents/briefs/`, any `expected.csv`, any fixture image, and the
extraction internals under `ios/Sources/TankbookCore/Extraction/` **except** where you must read
`FuelExtraction` to copy values out of it. Three stages of accuracy work landed there today and are
verified; this task adds storage and presentation on top, and changes no parser behaviour. If the
corpus score moves at all, that is a bug in your change.

**Never `pgrep -f`** (your brief is your command line). Use `pgrep -x`. Never `pkill -f`.

## The defect, precisely

`Attachment` (`ios/Sources/TankbookCore/Domain/Entities.swift:495`) carries exactly
`ocrText: String?` and `extractedTimestamp: Date?` - the raw lines and a clock. There is no field
for what the parse concluded. So `AttachmentRecognisedView`
(`ios/App/Sources/EditEntry/AttachmentRecognisedView.swift`, 76 lines) renders `ocrText` because
raw text is **the only thing that exists**. It is not a presentation bug that a nicer view fixes.

The assignment IS computed - `FuelExtractor` decides that `51,71` is the total, `1,919 EUR/L` the
unit price and `26,94` the volume - flows into the Confirm form as a pre-fill, and is then thrown
away. The entry keeps the values; the attachment keeps no record of what was read as what.

## What already exists - do NOT design this from scratch

This is the most important paragraph in the brief. Three pieces are already in the tree:

1. **`ExtractionMeta`** (`Entities.swift:543`): `fields: [FieldRef: FieldExtraction]` plus
   `pipeline: String`. Already `Codable`, already persisted for other entities - `Migrations.swift`
   declares an `extraction` TEXT column holding JSON `ExtractionMeta?`, and `Records.swift` decodes
   it.
2. **`FieldExtraction`** (`Entities.swift:554`): `cropRect`, `confidence`, `userCorrected` - and
   **no value**. That is the gap: the app records where a field was found and how sure it was, but
   never what it read.
3. **`attachment.schema.json` already declares an `extractionMeta` property** (line 75) with the
   `fields`/`pipeline` shape - while the Swift `Attachment` struct has no such field. The slot was
   anticipated and never filled.

So the likely shape is: put `ExtractionMeta` on `Attachment` (the schema slot is waiting) and give
`FieldExtraction` the assigned **value**. Check that reading yourself and say if you disagree - but
if you invent a parallel structure instead, justify it against these three, because a second way to
say the same thing is a cost the sync layer pays forever.

Mind that `FieldExtraction` is shared with `FillUp`/`ServiceRecord` extraction meta, so any new
member must be optional and must not disturb existing decodes. `InvoiceSplitter` constructs it too.

## What to build

### 1. The stored assignment

Every field the parse assigned - total, unit price, volume, date, fuel kind, station, currency -
with its confidence. Two invariants from the RV.48 row, both testable:

- **A field the parse did not assign is ABSENT, never an empty string or a zero.**
- **A parse that assigned nothing stores no assignment at all**, rather than an empty container.

Values are money and volume, so honour `docs/SCHEMA.md`: money is a pair with its currency, a
`Decimal` never a `Double` (P2.2b - `FuelExtraction.unitPrice` and `.total` are already `Decimal`),
and the canonical field names are SCHEMA's, in every language.

### 2. The schema evolution

Hard rule 9: this is a **data change with a declarative transform**, never a backend deploy. Read
`docs/SYNC.md` -> the payload contract and the `payload_migrations` mechanism, whose ordered
operations are `rename`, `addDefault`, `wrap`, `removeDeprecated`. Adding an optional property is
the easy end of that mechanism - state which operation your change needs (quite possibly none) and
why an older client reading a newer payload, and the reverse, both stay safe.

Update `docs/SCHEMA.md` and `docs/SYNC.md` in the same change. The docs are the spec.

### 3. The decision the row leaves open: is the raw text trimmed?

The row is explicit that this is a decision to make and record, not an optimisation to slip in:

- **Keeping it** is what lets a bad parse be re-examined; `docs/EXTRACTION.md`'s four named failure
  modes are pinned to it.
- **Trimming it** is data minimisation: the dump carries the merchant's `Reg.kood`, `KMKR nr.`,
  `ИНН` and terminal ids into on-device storage and through sync, and the app has no use for any of
  it (`docs/SECURITY.md`, hard rule 12).

**There is now a third option that did not exist when the row was written**: `ReceiptNoiseFilter`
(stage one, `Extraction/ReceiptNoiseFilter.swift`) already classifies exactly those lines, and it
TAGS rather than deletes. So "keep everything", "keep only candidate lines" and "keep everything but
store the tags" are all available. Pick one, implement it, and write the reasoning into
`docs/SECURITY.md` (or SCHEMA, whichever owns it) - naming the cost of what you gave up. Deleting
evidence of a misread to save bytes is a real cost; so is syncing a stranger's VAT number.

### 4. The viewer shows MEANING

Rewrite `AttachmentRecognisedView` so the assigned fields are the headline: what the receipt said,
per field, with the values rendered per `docs/DESIGN.md` (DIN numerals, `tabular-nums`, money
amount-then-symbol with U+00A0, units typographically subordinate). **Demote the raw text behind a
disclosure** rather than deleting it from the view.

- An attachment whose parse assigned nothing **says so** instead of rendering an empty card
  (RV.48's L4 requirement).
- All strings through the String Catalogs, **EN and RU** (hard rule 10). No hardcoded text.
- Colours from `DESIGN.md` tokens only; no ad-hoc hex (hard rule 5).
- This view presents STORED data and must never re-run OCR - the existing doc comment explains why,
  and it still holds.

## Hard rule 13 is untouched, and say so in the code

Persisting what was read changes nothing about who decides. The stored assignment is a record of
what the scan concluded, **not** a fact and not a source that may overwrite a user's value. A field
the user has corrected stays corrected (`FieldExtraction.userCorrected` already exists for this).

## Tests

- `cd ios && swift test` is **1293 tests in 121 suites** today (higher if RV.48c has landed - check).
  It must still pass and the count must rise.
- **L1, from a real corpus fixture, not a hand-typed string.** The RV.48 row says so explicitly:
  `Spike/ReceiptSpike/fixtures` is the point of having them. Build an attachment from a fixture's
  extraction and assert the assigned fields carry the values the extractor produced; assert an
  unassigned field is ABSENT (not blank); assert a nothing-assigned parse stores no container.
- Round-trip the payload through encode/decode and through the persistence layer, and assert an
  older payload without the new property still decodes.
- **L4 UI**: the recognised page shows the assigned values, and a receipt with nothing assigned says
  so. Name the UI suite you extend and run **only** that one with `-only-testing:` - the full UI
  suite belongs to phase completion, not to this task. Report the observed test count; a `--filter`
  that matches nothing prints "0 tests passed", which is not a pass.
- **Mutation-check every load-bearing assertion**: state the mutation, the test that failed, and
  confirm the file was restored byte-identical. Vacuous traps here: asserting a field is non-nil
  when it already was; asserting the view "renders" without asserting a VALUE; a round-trip test
  that would pass with the payload empty.

## Screenshots (standing instruction)

One EN and one RU screenshot of the recognised page, dark theme, committed to `design/screenshots/`
as `RV.48-attachment-recognised.png` and `RV.48-attachment-recognised-ru.png`. Capture from a booted
simulator, **outside a test run** (`simctl` and `xcodebuild test` fight over the device):

    xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU

RU is not a formality: Russian runs 20-30% longer than English and short labels expand worst, which
is exactly what overflows a two-column field list. Check the seeds in
`scripts/capture-screenshots.sh` and pass `-homeResetDatabase` alongside any seed - the seeds are
idempotent and silently do nothing on a populated database.

## The baseline gate - judged by exit code

    cd ios && swift build            # 0
    swiftlint lint                   # from the REPO ROOT, 0
    cd ios && swift test             # 0, count risen
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build   # 0

Report all four, from `echo $?`, not from reading output.

## Out of scope

The parser and the corpus score, the pump class, RV.45's comparison card (this task is its
dependency, not its implementation), the gateway, and the backend.

## If you run short of budget

Land in this order, saving as you go: (1) the stored assignment plus its tests and the schema/doc
change, (2) the raw-text decision written down, (3) the viewer, (4) the screenshots. Stage 1 alone
is worth committing.

## Report back

The four exit codes and the test count; the shape you stored and why (against the three existing
pieces named above); your raw-text decision and its cost; the mutation checks; the UI suite name and
its observed count; the screenshot paths; and confirmation that the corpus score did not move.
