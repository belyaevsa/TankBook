# PJ.28 - Expense capture photographs the receipt and discards it

**[v1.x]**, product-owner priority (2026-08-31).

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## Read this first: half of this row is already done, and the row's summary elsewhere is stale

[RV.62] (2026-09-04) delivered the pre-fill half. The Expense-mode shutter is **no longer
decorative**: a scan's total, currency and date reach the form through `ExpenseSession.pendingPrefill`
and are applied at `ExpenseEntryView.swift:302-310`, after the category preset so a scan never
overwrites one, as default input the user edits (hard rule 13). That is **L1 and L4 tested and passes
today**.

**The whole remaining row is the photo.** `ExpenseEntryView.swift:189` still writes
`attachments: []`, and `ExpensePrefill` deliberately carries no attachment reference - RV.62's agent
flagged it as out of its scope rather than folding it in. So the user photographs a receipt, the app
reads it, and then **throws the image away silently**. It is the only row in the v1.1 queue that
loses data (hard rule 8: nothing lost silently).

**Do not re-deliver the pre-fill.** Asserting it is this row's named vacuous trap - it already
passes.

## What already exists - reuse it, do not invent a second path

The fill-up capture path already persists a receipt exactly the way this one must:
`ManualFillUpReceiptSave.writeReceiptAttachment` (`ios/App/Sources/ConfirmManual/ManualFillUpReceiptSave.swift:151-174`)
encodes the source image to JPEG, writes it through `VehiclePhotoStore.save`, builds a thumbnail via
`AttachmentRendition.thumbnailBase64`, carries the OCR text and the receipt's own
`extractedTimestamp`, stores `extractionMeta` as `assignmentOnly` (a parse that assigned nothing
stores no container at all - [RV.48]), and calls `repository.upsertAttachment`.

**That is the shape.** Either call into it or extract the shared piece - your choice, say which and
why - but there must not be a second, subtly different way to persist a receipt.

Note `ExpensePrefill` currently carries no image reference, so getting the photo from the capture to
the form is part of the task: extend the prefill (or the session) to carry what the save needs. The
prefill is **consumed** when applied (`:309`), so a second open of the form must not re-attach a
stale photo - the same discipline the values already follow.

## What to build

- A scanned Expense saves with its receipt **attached**, and the attachment is openable from the
  saved entry the way a fill-up's receipt is.
- The `extractedTimestamp` matters here for the same reason it does on a fill-up: the receipt's own
  printed date is ground truth for the timeline priority rule (`docs/SCHEMA.md` -> PRIORITY). Carry
  it if the extraction read one.
- **A manual expense with no scan still saves, with no attachment and no error.** The scan is a head
  start, never a requirement (hard rule 15, two doors).
- **A failed write must not lose the entry.** If the image cannot be encoded or stored, the expense
  still saves and the user is told what happened and what to do next (hard rule 7, hard rule 8) -
  never a silent drop, which is the defect this row exists to remove, and never a blocked save.

## Explicitly out of scope

- The pre-fill values ([RV.62], done).
- The Service-entry invoice path (`ServiceInvoiceSession`), unless the shared extraction genuinely
  covers it - if it does, say so.
- Attachment sync and the blob pipeline. The local write is this row; `docs/SYNC.md`'s blob upload
  follows the ordinary path and needs no change here.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Attachment, and PRIORITY (the receipt-date rule).
2. `docs/JOURNEYS.md` -> J7b Purchase.
3. `docs/ERRORS.md` -> the expense/capture surfaces - **extend it** with the write-failure message.
4. `CLAUDE.md` hard rules 7, 8, 13, 15.

## UI suites to run

`TankbookUITests/ExpenseCaptureUITests` (exists, from RV.62) and
`TankbookUITests/AttachmentViewerUITests`.

## Tests you must add

- **L4, the row's whole point** (extend `ExpenseCaptureUITests`): the scanned photo is attached to
  the saved expense **and openable from it**.
- **L1**: the saved `Expense.attachments` carries the id, and the `Attachment` row exists with its
  file reference - assert both, since either alone can pass while the receipt is unreachable.
- **L1**: a manual expense with no scan saves with no attachment and no error.
- **L1**: the prefill is consumed - a second open of the form attaches nothing.
- **L1**: `extractedTimestamp` is carried when the extraction read a date.
- **L1**: a failed image write still saves the expense and surfaces the named next step.

## Vacuous traps, named

- **Asserting the pre-fill** - RV.62 already delivers it and it passes today. The attachment is the
  whole remaining row.
- Asserting `attachments` is non-empty without asserting the `Attachment` row and its file exist.
- Writing a second receipt-persistence path instead of reusing the fill-up's.
- Making the save depend on the image succeeding, or on the network (hard rule 1).
- Re-attaching a stale photo on a second open of the form.

## Screenshots

`design/screenshots/PJ.28-expense.png` and `PJ.28-expense-ru.png`: a saved scanned expense showing
its attached receipt.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; whether you reused `writeReceiptAttachment` or extracted a shared piece, and why;
how the image reaches the form from the capture; what happens on a write failure; and anything you
found and did not fix.

## Never stash, move or `git checkout` to get a "clean baseline"

To show a test fails before the fix: **write the test, run it against the unmodified code, then make
the change.** If the change is already written, prove the test's teeth with a **mutation** - revert
the one line the test is about, run it, restore the line.

**Do not** `git stash`, `git checkout`, or move files out of the tree to get a clean baseline. On
2026-09-08 an agent did exactly that and a bad `mv` loop destroyed three of its own new files; the
same loop would have taken a concurrent session's uncommitted work. Assume you are not alone in this
checkout.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

Re-measure the baseline yourself and report what you observe; do not copy numbers from this brief.
As left, `main` was **1702 tests / 190 suites**, **777** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. Run it from the root, **not** from `ios/`: the
   `excluded:` paths are root-relative and from `ios/` it reports thousands of phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suites named above **by name**, each with its **observed,
   non-zero** count. A filter matching nothing prints "0 tests ... passed" and still exits 0, and
   several RV suites here are `extension HomeUITests`, so a class-name filter for them matches
   nothing.
5. Localization gate - exit 0; report the key count and RU percentage. **Every new user-facing
   string is EN and RU** (hard rule 10).
6. Release build only if you touch a `#if DEBUG` seam (a test seed is one). Say which applies.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

**Screenshots**: every UI task ships EN **and** RU, **dark** theme, captured **outside** any running
test (`simctl` and `xcodebuild test` fight over the device). Pass `-homeResetDatabase` alongside any
seed - seeds are idempotent and silently do nothing on a populated database. RU:
`xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
RU strings run 20-30% longer and short ones expand worst. **You cannot see your own screenshots** -
the orchestrator opens every one. State what you captured and how; do not assert they look right.
