# RV.62 – Expense capture runs the FILL-UP recogniser, then throws the result away

Reported by the product owner 2026-09-04 in the same breath as RV.61: *"if I checked it on a capture
moment, it's not adjusted, and recognition logic must be also applied to a recognition view"*.
**Confirmed in code, and only ONE of the two types is broken** – read the diagnosis before assuming
Service is affected. It is not.

**DO NOT DISPATCH THIS ALONGSIDE RV.61 OR RV.57** – all three touch the capture and entry-form area.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.** The `.claude/worktrees/rv48` worktree is
another session's and is not your gate.

**Use the `iPhone 17` simulator.**

## The diagnosis, verified – confirm, do not re-derive

**Service is FINE. Do not "fix" it.** `CaptureView.swift:610` branches
`let isService = mode == .service`; the shutter opens the document camera;
`ServiceInvoiceScanner.process(images:)` runs; the pre-fill reaches `ServiceEntryView` through the
shared `ServiceInvoiceSession` (`CaptureView.swift:600-605`). That is the pattern to copy.

**Expense falls through that `else`**:

1. it calls `captureFrame()`, which runs `CapturePipeline` – the FILL-UP OCR, extracting liters,
   unit price and fuel kind;
2. `ScannedFillUpSheet.swift:88` routes `.expense` -> `.expenseEntry`;
3. **`ExpenseEntryView` has no channel to receive anything.** `ExpenseEntrySession` carries exactly
   one field, `pendingPreset: ExpenseCategory?` (`ExpenseEntrySession.swift:11-13`), written only by
   `ServiceEntryView:212` for the nested add-an-expense case, never by capture.
   `SheetRoute.expenseEntry` carries no associated value either.

So the user photographs a receipt, a recognition genuinely runs, and a **blank** expense form opens.
The work is done and discarded – and on the gateway path that spends real money and a quota unit.

## What to build

**Wire a prefill channel for Expense, and recognise the right fields – do NOT pipe the fill-up
prefill across.** A shop receipt is not a fuel receipt: liters and fuel kind are meaningless on it.

**The product owner's decision, already taken: recognise total + currency + date.** That is the
honest minimum and `ExtractionAssembler` already resolves all three. Anything beyond it (merchant,
category) is a NEW extraction problem – if you think one is needed, say so in your report rather
than building it.

**Give `ExpenseEntrySession` a `pendingPrefill` mirroring `ServiceInvoiceSession`** – that pattern is
already this codebase's answer to exactly this problem, and matching it is worth more than a new one.

**Every prefilled value stays a default input the user edits** (hard rule 13), editable at the moment
it is offered and again afterwards. **An extraction that resolves nothing lands the EMPTY form and
never an error** (hard rule 7) – the same contract the fill-up path already honours.

## Read before writing

1. **`CLAUDE.md`** – hard rules 13, 7, 15, 10, 12 (log field names and codes, never values), 14.
2. `docs/EXTRACTION.md` – the pipeline and what the assembler resolves; `docs/JOURNEYS.md` for the
   expense flow; `docs/ERRORS.md` for the empty-extraction row.
3. `ios/App/Sources/Capture/CaptureView.swift` (the `isService` branch and `scanServiceInvoice`),
   `ScannedFillUpSheet.swift`, `ios/App/Sources/ServiceEntry/{ExpenseEntrySession,ExpenseEntryView}.swift`,
   `ios/App/Sources/ServiceEntry/ServiceInvoiceSession.swift` (the pattern to mirror),
   `ios/Sources/TankbookCore/Extraction/ExtractionAssembler.swift`.

## Tests

**iOS unit 1322 today; must not fall.** Name the UI suites you run with `-only-testing:`.
Expect `CaptureUITests` and `ServiceEntryUITests`; add an expense case where it belongs.

- **L1: the expense prefill carries total, currency and date and NEVER liters or fuelKind.** Assert
  the absent fields explicitly – this is the assertion that stops someone piping the fill-up prefill
  across later.
- **L4: capture in Expense mode with a stubbed extraction opens the expense form with the total
  PRE-FILLED and editable.** Assert the FIELD VALUE. "The form appeared" passes against the bug today.
- **L1: an extraction that resolves nothing yields an empty form and no error.**
- L4: Service capture is UNCHANGED – its existing prefill still arrives. You are editing the branch
  it lives in.

**Vacuous-assertion traps, named:**
- Asserting the pipeline ran. It already runs; the defect is that nothing receives it.
- Asserting `pendingPrefill != nil` rather than the value the user sees in the field.
- Asserting the expense form opens. It already opens – empty.

**Mutation-check and report it**: clear the prefill before the form reads it and confirm the
field-value test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
**Never `pgrep -f`/`pkill -f`.**

## Screenshots

**Required, EN and RU, dark** – the pre-filled expense form is a user-visible change. Save as
`design/screenshots/RV.62-expense-prefill.png` and `-ru.png`, captured OUTSIDE a test run. You have
no image input; say so and say what you could not check.

## Report back

- Exit codes (captured, not piped), unit counts before/after, UI suites run, mutation result.
- **Which fields the expense extraction resolves**, and confirmation liters/fuelKind are never among
  them.
- Confirmation the Service path is untouched and still receives its prefill.
- Whether any OCR work is still performed whose result is discarded – if so, name it.
- Anything you noticed that is not RV.62 – named separately.
