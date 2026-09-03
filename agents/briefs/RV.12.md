# RV.12 – saving a captured entry must not drop the user back in the camera

Reported by the product owner from a device walk on the TestFlight build: capture a
receipt, the Confirm sheet pre-fills, tap **Save** – and the capture window is on screen
again. A completed entry looks like a failed one, and a second tap starts a second entry.
Registered as RV.12 in `docs/TASKS.md`.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Write nothing outside it, including
no temp files elsewhere. **Do not run `git add` or `git commit`** – the orchestrator
verifies independently and commits.

## Write code first, explore second

The dominant failure mode in this repo's agent runs is a run that reads everything and
writes nothing. The diagnosis below is already done; you are not being asked to re-derive
it. Confirm it in the code, then write.

## The diagnosis (confirmed, do not re-derive)

Capture is a **modal presented over the current tab**, not a tab root:

- `ios/App/Sources/Navigation/TabRoots.swift` -> `openCapture()` sets `logModal = .capture`
  (or `trendsModal` / `garageModal`, whichever tab is on screen). The `.capture` case is in
  `ios/App/Sources/Navigation/Routes.swift`.
- Inside that modal, `CaptureView` presents the Confirm sheet with
  `.sheet(item: $activeSheet)`, case `.scanned(prefill)` -> `ScannedFillUpSheet` ->
  `ManualFillUpView`.
- `ManualFillUpView.save()` (around line 517, ending at line ~566) finishes with
  `dismiss()`. That dismisses **the Confirm sheet only**. The capture modal underneath was
  never dismissed, so it is what the user is looking at.

So this is not "the app navigates to capture after save". Nothing navigates. **The capture
modal was never torn down**, and the sheet dismissing merely uncovers it.

## What to build

On a **successful save of a captured entry**, the capture modal must be dismissed too, so
the user lands back on the tab they started from with the new entry visible.

Constraints that decide the shape:

1. **`ManualFillUpView` must not learn about tabs or capture.** It is also reached from
   the typed door and from Edit-entry-adjacent flows; a save there must keep behaving
   exactly as it does today. Whatever signal you add has to be **opt-in from the capture
   side** - the presenter tells the sheet what to do on save, the sheet does not reach up
   into the navigation graph. A closure passed down, or a callback on `ScannedFillUpSheet`,
   is the shape; a global or an environment singleton is not.
2. **Only on a successful save.** Cancelling the Confirm sheet, or a save that throws
   (`AppLog.error(operation: "confirmManual.save"...)` in the `catch`), must leave the
   capture modal exactly where it is - the user's photo and their typing are still there,
   and tearing the modal down under a failed save would destroy work. `hasUnsavedChanges`
   and `DiscardAwareSheet`'s existing behaviour are not yours to change.
3. **`toastCenter.noteEntryChanged()` must still fire**, and the notification reconcile
   `Task` must still be started. Do not reorder the save's tail so that dismissing the
   modal cancels either. This is a real risk: the reconcile runs in a `Task` whose lifetime
   is tied to the view.
4. The typed door through capture ("Type it" -> `.manualForm`) has the same shape and the
   same bug. Handle it, or state explicitly in your report that you did not and why.

**Where the user lands is not a new decision to invent.** They came from a tab; they go
back to it, and `toastCenter.noteEntryChanged()` already makes Home reload. Do not add a
tab switch, a navigation push, or a "view the entry you just saved" step - that is scope
this task does not have.

## Explicitly out of scope

- Do not touch `CaptureReviewView.swift` or the review step's own flow (RV.5, just landed
  and committed). You may read it.
- Do not touch `ManualFillUpGatewayBanner.swift` or `GatewayScanSession.swift` (RV.8).
- No change to what `save()` writes, to the fill-up it builds, or to the validation.
- No new screen, no post-save confirmation screen, no toast copy changes.

## What NOT to explore (closed questions)

- Whether capture is a modal or a tab - it is a modal; the code is named above.
- Whether `TabView` should be reinstated. `TabRoots.swift` carries a long comment about
  three failed attempts to suppress its bar. Do not relitigate it.
- The palette. Anything visual uses `Theme.Palette` tokens; no ad-hoc hex (hard rule 5).

## Read before writing, in this order

1. **`CLAUDE.md`** – the hard rules. Rule 14 (it builds and it lints) and rule 8 (nothing
   lost silently) bind here; rule 8 is why a failed save must not tear the modal down.
2. `docs/SCREENMAP.md` – the navigation graph and the **back-path conventions**. If the
   post-save path is described there and your change alters it, the doc moves in the same
   change. RV.5 added a "The capture review step" section; read it for the current shape.
3. `docs/JOURNEYS.md` – J1 and J3, whose last step is exactly this.

Extend the docs in the same change if the flow they describe is now different. A behaviour
change that no doc records is an unfinished task.

## Tests

- `cd ios && swift test` – **1154 unit tests today; the number must not fall.**
- L4 in `ios/App/UITests/`. The capture suites are `CaptureUITests`,
  `CapturePipelineUITests` and `CaptureReviewUITests`; put the new test where it fits and
  **name in your report which suites you ran**. `-captureFixtureImage <path>` drives the
  pipeline from a host image (the simulator has no camera); `-captureAutoReview` exists
  from RV.5. Use those, do not invent a second mechanism.
- The test that pins this: capture -> review -> Use this -> Confirm -> **Save**, then
  assert the camera surface is **NOT** on screen and the tab the user started from is.

**Vacuous-assertion traps for this task, named:**
- Asserting the Confirm sheet is gone after Save. It always was - that is `dismiss()`,
  which worked before this task and proves nothing about the bug.
- Asserting `app.buttons["captureShutter"].exists == false` without first asserting it was
  **true** before the save. An identifier that never existed is absent for free.
- A test that never actually saves, because `Save fill-up` is disabled until total and
  litres are filled. Check the button is enabled before tapping it; a tap on a disabled
  button silently does nothing and the rest of the test then passes for the wrong reason.
- Asserting only on the typed door, which may not reproduce it, and calling the scan door
  covered.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed, not by skimming output** - `LINT=0` printed after a
pipe is the pipe's exit code, not swiftlint's. Run swiftlint from the repo root (its
`excluded:` paths are root-relative). Zero lint **errors** is the standard; `file_length`
at 700 lines is an error, not a warning, and `CaptureView.swift` is at 594 and creeping -
if your change pushes a file past 700, split it at a real seam rather than loosening a rule.

If you check whether the simulator is free, match the process NAME (`pgrep -x xcodebuild`).
**Never `pgrep -f` or `pkill -f`** on a build/test pattern: an agent's brief is part of its
command line, and on 2026-08-24 exactly that killed another agent 48 minutes into its task.

## Screenshots

Only if this task changes what a screen looks like. It probably does not - it changes what
is on screen after a dismissal, which a screenshot cannot show. **Do not fabricate a
screenshot to satisfy the convention**; say in your report that none applies, and why.

## Report back

- The exit codes you observed for `swift build`, `swiftlint`, the app build, `swift test`,
  and each UI suite - the numbers, not a summary.
- The unit-test count before and after.
- The UI test names, the suites, and the observed count per suite. A `-only-testing:` that
  matches nothing prints "0 tests ... passed", which is not a pass - check the count.
- **Whether each test was actually RUN, not only written**, and whether you saw the new
  test FAIL before the fix (mutation evidence: revert the fix, watch it go red, restore).
  A test for this bug that passes with the fix reverted is not a test for this bug.
- Every file you created or modified, and any doc section you extended.
- Whether you covered the "Type it" door as well as the scan door.
- Anything you could not finish, named plainly. An honest gap is worth more than a green
  report that does not hold.
