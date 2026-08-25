# Task P3-UI-FIX – make the UI suite green after the entry-form reorder

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`** – the main checkout, on branch `main`.
**Work directly in it. Do not create a worktree. Do not commit, do not stash, do not
`git checkout`/`restore`/`reset` anything** – the tree holds a large body of **uncommitted** work
that is not yours and cannot be recovered if you discard it. If you think a file should be
reverted, say so in your report instead of doing it.

Do not read, write or `cd` into another checkout.

**Never `pgrep -f` / `pkill -f` for a build or test** – an agent's brief is part of its command
line, so that pattern matches sibling agents and killing the match destroys their work. Use
`pgrep -x xcodebuild`. **Your simulator is `iPhone 17`.**

## The problem, stated precisely

`xcodebuild ... test` currently reports **99 tests, 8 failures**. `swift test` is **510, exit 0**
and `swiftlint lint` is **exit 0**, so this is entirely in the app/UI target.

Your job is to make the UI suite green **or** to prove, failure by failure, that a remaining one
is pre-existing and unrelated. Both outcomes are acceptable. **A wrong green is not.**

## What changed just before these failures (the likely cause of most of them)

An entry-form reorder and some layout work, all uncommitted in your tree:

1. **Field order changed on BOTH entry screens** to `Date · Odometer · Station · Fuel · the
   three-number card · Currency` (`docs/DESIGN.md` -> "Entry forms follow one field order").
   `ManualFillUpView` and `EditEntryView`. The three-number card used to be **first**; it is now
   fifth. Tests that tap a number field may need the field scrolled into view.
2. **The currency section folds** while the entry is in the home currency
   (`manualFillUpCurrencyCollapsed` is the collapsed row) and **opens itself** when the currency
   needs attention - and then renders **above** the numbers card rather than below it. See
   `ManualFillUpCurrencySection.needsAttention(...)`.
3. `ConfirmableFormScreen` (new, in `ios/App/Sources/Sheets/`) pins a form's primary action and
   **hides the tab bar** while such a form is on screen. Adopted by `ReminderFormView`.
4. `AppTabBar.captureRise` is now **0** (the capture button aligns with the other slots) and the
   bar's bottom padding is computed from the safe area.
5. `StatTile` and the ServiceEntry date/odometer pair are now proper grids (equal cell heights).
6. `ManualFillUpSections.swift` was split; the currency section now lives in
   `ManualFillUpCurrencySupport.swift`.

## What NOT to do - each of these has burned this project

- **Do not add `sleep`/`wait` to paper over a failure.** `HANDOVER.md` says so explicitly about
  the `AddVehicle` pair. A timing fix that hides a real bug is worse than the red test.
- **Do not delete or `XCTSkip` a failing test** to reach green. If a test encodes a promise the
  new design deliberately changed, **update the test and say so in your report** - that is a
  spec change and must be visible, not silent.
- **Do not loosen an assertion** ("contains" instead of equality, removing an `isHittable` check)
  unless the assertion itself was wrong. Say which and why.
- **Do not "fix" by reverting the reorder.** The order is a product decision made today.
- **Do not touch `Spike/`, `docs/` beyond a genuine spec correction, or the two other branches.**

## Known-pre-existing failures - do NOT chase these

Documented in `HANDOVER.md` and re-confirmed by another agent on a branch that predates all of
the above:

- `AddVehicleUITests.testConfirmItIsRightIsOneTap`
- `AddVehicleUITests.testImplausibleOdometerWarnsButNeverBlocksSave`
- `ConfirmManualUITests.testReducedMotionLockStillLandsWithoutAnimation`

All three are the same shape: `typeText` after a successful `tap()`, with the field leaving the
accessibility tree. If they still fail, **report them as pre-existing and leave them alone**.

## A trap that cost the orchestrator three wrong fixes today - read this

The failures were first diagnosed as "the numbers card is below the fold". **That was wrong**, and
a screenshot proved it: with the new order everything still fits one screen on `iPhone 17`.

Two other things were confusing the picture, and you must control for both:

- **Machine load.** The failures were first measured while two other agents were building, at a
  load average of **272**. `waitForExistence(timeout: 5)` after an app launch does not survive
  that. The machine is idle now - keep it that way while you measure, and if a failure does not
  reproduce twice in a row on an idle machine, say so rather than "fixing" it.
- **`app.swipeUp()` does not reliably scroll a presented sheet.** Swipe the sheet's own scroll
  view (`app.scrollViews.firstMatch`), which also dismisses a keyboard left up by a previous
  field because the form uses `scrollDismissesKeyboard(.immediately)`.

A helper already exists for this - `focusField(_:_:)` in `ConfirmManualUITests` - and it may
itself be wrong. Fix it if so.

**Measure before you change anything.** Instrument an assertion (element `frame`, `isEnabled`,
`isHittable`, `app.scrollViews.count`) and read the numbers rather than inferring the cause from
the symptom. That single step is what finally identified the real situation today, after three
plausible-sounding fixes had failed.

## How to run

```
xcodegen generate ; echo "xcodegen: $?"
xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' test ; echo "xcodebuild test: $?"
cd ios && swift test ; echo "swift test: $?"          # must stay 0 / 510
swiftlint lint ; echo "swiftlint: $?"                  # must stay 0, from the REPO ROOT
```

Run a single suite while iterating - `-only-testing:TankbookUITests/<Suite>` - and the whole thing
before you report. Never run `simctl` while a test run is in progress; they fight over the device.

## Definition of done

`xcodebuild test` exit **0**, or every remaining failure named and shown to be pre-existing ·
`swift test` still 0 at 510 or higher · `swiftlint lint` 0 · no test deleted, skipped or slept ·
no source file reverted.

## Report back

- The **eight failures by name**, each classified: *caused by the reorder*, *pre-existing*, or
  *load artefact that does not reproduce*.
- For each one you changed: what you changed and **whether you changed the test or the code** -
  and if the test, what promise changed and why that is correct.
- The **captured exit code** of every command above.
- Anything you believe is wrong with the new design, stated plainly - you are allowed to disagree
  with the reorder, you are just not allowed to revert it silently.
- Do not claim a suite is green unless you ran it and read its exit code.
