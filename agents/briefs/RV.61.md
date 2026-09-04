# RV.61 – Service and Expense have no manual door

Reported by the product owner 2026-09-04: *"if I want to enter expenses or service there is no way
to make it manually - I can choose a type only in capture moment"*. **Confirmed in code before
filing** – do not re-derive it, but do confirm it still holds before changing anything.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.

**A sibling agent (RV.63) is working in `backend/`** – ignore it. **Never move, rename or delete a
file you did not create.** There is a git worktree at `.claude/worktrees/rv48` belonging to another
session; it is not yours and it is not your gate.

**Use the `iPhone 17` simulator.**

## The diagnosis, verified – confirm, do not re-derive

**This is a hard rule 15 violation, and the rule names this exact shape**: the two doors must stand
*"side by side at every entry point"*, never "scan, and type only if scanning failed". For Service
and Expense there is no typing door at all outside the camera.

**The forms are not missing – they are unreachable.** `ServiceEntryView` and `ExpenseEntryView`
exist and are wired at `Destinations.swift:80/82`.

Every rule-15 "Type it" affordance routes to `.confirmManual`, the **fill-up** form:
`HomeView.swift:150`, `:202`, `:220`, `:324`; `HomeEmptyStates.swift:96`; `TrendsView.swift:103`.

The only routes to the other two forms are:
1. the capture screen – `CaptureMode.manualEntryForm` -> `CaptureEntryForm.sheetRoute`
   (`ScannedFillUpSheet.swift:86-88`);
2. `ReminderCompleteSheet.swift:255-256`;
3. `.expenseEntry` nested INSIDE `ServiceEntryView:213`.

**The three `sheet = .serviceEntry` sites in `TabRoots.swift:505/543/563` look like three doors but
are one** – all three are the capture modal's `ModalDestinationView` completion handler. Check this
yourself; it is the detail most likely to mislead you.

So typing a service record with no photo means: open the camera, change mode to Service, press
"Type it". A camera-first path to a form that needs no camera.

## What to build

**Give Service and Expense a manual door of equal standing, at the entry points that already offer
one for fill-ups.** Home's "Type it" is today a single hardwired button
(`HomeView.swift:323-335`).

**The design constraint that makes this non-trivial, and the thing to get right: the type chooser
must not become a gate.** Putting a "what kind?" step in front of every manual entry would make the
COMMONEST entry (a fill-up) slower, which is its own rule-15 problem – manual entry must not become
harder to reach than it is today. A menu whose primary action is still fill-up, a long-press, a
segmented control on the form itself: all are defensible. **Pick one, say why, and state what it
costs the fill-up path in taps** (the answer must be "nothing").

**`docs/SCREENMAP.md` is the authority on the navigation graph** and lists the planned-not-drawn
screens. If it already specifies this door, build what it says. If it does not, extend it in the
same change. `docs/JOURNEYS.md` J7 is the service journey and should name the manual path.

## Read before writing

1. **`CLAUDE.md`** – hard rule 15 (both doors, peer standing), 13, 7, 10 (String Catalogs, EN+RU,
   whole phrases never concatenated), 14.
2. `docs/SCREENMAP.md`, `docs/JOURNEYS.md` J7, `docs/DESIGN.md` for any new control.
3. `ios/App/Sources/Home/HomeView.swift`, `HomeEmptyStates.swift`, `ios/App/Sources/Trends/TrendsView.swift`,
   `ios/App/Sources/Navigation/{Routes,Destinations,TabRoots}.swift`,
   `ios/Sources/TankbookCore/Domain/CaptureMode.swift`.

## Tests

**iOS unit 1322 today; must not fall.** Name the UI suites you run with `-only-testing:`.

- **L4 `HomeUITests`: from Home, with no camera involved, reach a SAVED Service record and a SAVED
  Expense record.** The assertion is a saved entry of each type visible afterwards – **not** that a
  sheet appeared.
- **L4: the fill-up "Type it" path costs no additional taps.** Assert the existing fill-up manual
  flow still reaches the form in the same number of interactions – this is the guard against fixing
  the bug by slowing the common path.
- **L1: every `CaptureEntryForm` case has a reachable manual route**, table-driven or
  compile-checked, so a fourth entry type added later cannot silently lack a door.
- `ServiceEntryUITests` must stay green (you are changing how it is reached).

**Vacuous-assertion traps, named:**
- Asserting `.serviceEntry` *can* be presented. It always could – nothing user-facing presents it.
- Asserting a menu contains three labels, without saving an entry through each.
- Asserting the sheet opened rather than that a record exists afterwards.

**Mutation-check and report it**: remove the new route for Expense and confirm the "save an expense
from Home" test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
Match the process NAME (`pgrep -x xcodebuild`); **never `pgrep -f`/`pkill -f`**.

## Screenshots

**Required, EN and RU, dark theme** – this adds a user-visible control. Capture from a booted
simulator OUTSIDE a test run and save to `design/screenshots/` as `RV.61-<screen>.png` and
`RV.61-<screen>-ru.png`. RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
**RU runs 20-30% longer and short strings expand worst** ("Log" -> "Журнал" is 2x) – a truncated
label on a new chooser is exactly the failure this catches. You have no image input: say so, and
say what you could not check.

## Report back

- Exit codes (captured, not piped), unit-test counts before/after, the UI suites you ran.
- **Which shape you chose for the chooser and what it costs the fill-up path in taps.**
- The mutation result.
- What you changed in `SCREENMAP.md` / `JOURNEYS.md`.
- Anything you noticed that is not RV.61 – named separately, not folded in.
