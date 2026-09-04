# RV.57 – after a capture, open the entry view pre-filled from the LOCAL parse

**This is a product-owner REQUIREMENT, not a bug fix** (2026-09-04): *"we have a recognition on the
flight – let's open after capture the next view with the recognized data with a comment that a user
can proceed and the more reliable data will come later, but for now we recommend proceeding (if the
data are not recognized correctly). It can have the same view as for attachment view."*

**DO NOT DISPATCH ALONGSIDE RV.61 OR RV.62** – all three touch the capture and entry-form area.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.**

**Use the `iPhone 17` simulator.**

## Why this exists – the number settles it

The RV.51 decision accepted the inbox as the primary path because the cloud answer effectively never
arrives inside the 3 s budget. **Production, 2026-09-04: one `llm.extract` took 18 748 ms,
`Outcome=ok`, on `deepseek-v4-flash-vision-exp`** – worse than the 12 s RV.51 recorded as the
FASTEST observed. So the cloud answer is never present while the user stands at a pump, and a flow
that waits for it is a flow that always waits.

The local parse, by contrast, is immediate and is no longer weak: RV.48 took the receipt class to
**180/220 cells**, and the corpus's newest Russian slip (`receipt-048`) sweeps 5 of 5 with a locked
cross-check.

## What to build

**Capture -> the entry view opens AT ONCE, pre-filled from the local parse**, reusing the attachment
view's presentation – RV.48's "meaning instead of line soup" (`AttachmentViewerView`,
`ReceiptCardView`) – and carrying a **non-blocking note** that a more reliable reading may still
arrive and that proceeding now is recommended.

**The four fences, and they are what make this correct rather than merely built:**

1. **Every pre-filled value is a default input the user edits, never a fact** (hard rule 13) –
   editable at the moment it is offered and again afterwards.
2. **The note is NOT an error and must not behave like one** (hard rule 7): it names its next step,
   survives being ignored, and blocks nothing. **No spinner that implies waiting is required** – the
   whole point is that the user need not wait.
3. **Do NOT async-overwrite the open editor.** The product owner already ruled on this the same day:
   *"if a user keeps the edit entry open (they fill up odometer) and recognition has arrived – there
   is no need to async update"*. A late answer lands in the **inbox** (RV.45's per-field
   yours-vs-receipt card), never as a value that moves under the user's cursor.
4. **Typing stays a peer door** (hard rule 15): this screen is reached identically whether the user
   typed or scanned, and nothing here may frame manual entry as the failure branch.

**Copy through String Catalogs, EN + RU, whole localised phrases and never concatenation** (hard rule
10 – the composed-string bug that produced "АВГУСТ РАСХОДЫ" is exactly this shape).

## Read before writing

1. **`CLAUDE.md`** – hard rules 13, 7, 15, 10, 1, 14.
2. `docs/JOURNEYS.md` (J3, the capture journey), `docs/ERRORS.md` (the note is not an error – but
   check what IS defined for a partial extraction), `docs/DESIGN.md` for the note's treatment
   (**amber is attention only; this is informational, so amber is probably WRONG here** – justify
   whatever token you pick), `docs/EXTRACTION.md` for what the local parse resolves.
3. `ios/App/Sources/Capture/{CaptureView,CapturePipeline,ScannedFillUpSheet}.swift`,
   `ios/App/Sources/ConfirmManual/{ConfirmPrefill,ManualFillUpView}.swift`,
   `ios/App/Sources/EditEntry/{AttachmentViewerView,ReceiptCardView}.swift`,
   `ios/App/Sources/Inbox/`.

## Tests

**iOS unit 1322 today; must not fall.** Name the UI suites you run; expect `CaptureUITests`,
`ConfirmManualUITests`, `InboxUITests`.

- **L4: capture with a stubbed LOCAL parse opens the entry view pre-filled, the note present and
  dismissable, and Save reachable WITHOUT the cloud ever answering.** Assert the field values and a
  saved entry.
- **L4, the one that pins the product owner's ruling: with a late answer injected WHILE the editor is
  open, the on-screen values do NOT change and the inbox gains one item.** The assertion is that the
  field values are **UNCHANGED** – not merely that nothing crashed.
- **L1: the note's presence is derived from there being an in-flight request**, and is absent when
  the parse was local-only.
- L1: a parse resolving nothing opens the empty form with no error (rule 7).

**Vacuous-assertion traps, named:**
- Asserting the view appears without asserting the fields are pre-filled.
- Asserting the inbox count grew without asserting the editor's values held – the second is the
  actual requirement.
- Asserting the note's string exists rather than that it blocks nothing (Save must be reachable with
  the note on screen).

**Mutation-check and report it**: make the late answer write into the open editor and confirm the
values-unchanged test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe.** Never `pgrep -f`/`pkill -f`.

## Screenshots

**Required, EN and RU, dark** – this is a new user-facing surface, and the note is a sentence, which
is the worst case for RU expansion (20-30% longer, short strings worst). Save as
`design/screenshots/RV.57-capture-prefill.png` and `-ru.png`, OUTSIDE a test run. Compare against the
`design/screens/*.dc.html` artboards before you finish. You have no image input – say so, and say
what you could not check.

## Report back

- Exit codes (captured, not piped), counts before/after, UI suites run, mutation result.
- **What the note says, in EN and RU**, and which colour token you chose and why.
- **Proof the late answer does not touch an open editor** – name the test.
- Whether Save is reachable with the note on screen.
- Anything you noticed that is not RV.57 – named separately.
