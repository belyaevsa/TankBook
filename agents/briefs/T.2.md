# T.2 – 23 taps that do not wait for what they tap

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and only these UI test files:

`CaptureUITests.swift`, `ImportUITests.swift`, `GarageUITests.swift`,
`AnomalyInsightUITests.swift`, `TireSetsUITests.swift`, `EditEntryUITests.swift`,
`ServiceEntryUITests.swift`, `SignInUITests.swift`, `CarSwitcherUITests.swift`,
`TankbookShellUITests.swift`, `VehicleDetailUITests.swift`.

Do **NOT** touch `ios/App/UITests/RemindersUITests.swift`, `ConfirmManualUITests.swift`,
`HomeUITests.swift`, `TankLevelUITests.swift`, `TrendsUITests.swift`, `DiscardGuardUITests.swift`
or any `*TestSeed.swift` – a sibling lane (T.1) owns those this run. Do **NOT** touch
`docs/TASKS.md` or any product source: **this row changes tests only.** If you believe a product
change is needed, stop and report.

Write code first, explore second.

## Use this simulator

`iPhone 17 Pro`. A sibling agent is on `iPhone 17`. **Never** `pgrep -f`/`pkill -f` for a build –
a brief is part of the process command line and that pattern once killed a sibling agent. Use
`pgrep -x xcodebuild`.

## The defect

23 sites tap an element with **no `waitForExistence` for that identifier in the preceding lines**.
A tap on an element that is not there yet does not fail at the tap - **it fails at the next
assertion, naming the wrong thing.** That is exactly how PJ.7d's shell walk presented ("Settings
nav bar never appeared" when the real fault was tapping too early) and how PJ.4b presents today.

Measured sites (verify them yourself - briefs here have carried wrong lists six times):

```
AnomalyInsightUITests 184, 218      homeAnomalyToggle
CaptureUITests 202, 295, 308, 323, 452, 640, 648, 657, 658
CarSwitcherUITests 116              carSwitcherAddCar
EditEntryUITests 204                editEntryDeleteButton
GarageUITests 109, 129              garageAddCar
ImportUITests 264, 281              importDateFormatOption-D/M/YYYY
ServiceEntryUITests 49              serviceEntryItemDelete
SignInUITests 230                   emptyRestoreStartFreshButton
TankbookShellUITests 200            carSwitcherButton
TireSetsUITests 102, 103            serviceEntryTireSetPicker, "Winter Nokian"
VehicleDetailUITests 225            carSwitcherButton
```

## What to build

Add the wait before the tap. Where a **pinned save bar** is involved, waiting is not enough:
`isHittable` **does not model occlusion**, so an element under the bar reports itself hittable and
the tap lands on the bar instead - that is PJ.7e, where a tap "on" the price field hit **Save** and
saved the entry. In those cases scroll by **geometry** (clear of the bar's top), following the
`focusField` / `scrollClearOfSaveBar` helpers that already exist in `ConfirmManualUITests` - read
them first and reuse the pattern rather than inventing a second one.

## Named vacuous traps

- **A blind `sleep` / `Thread.sleep` / a raised global timeout.** Explicitly forbidden for this
  family in this repo.
- A wait that cannot fail - e.g. `_ = element.waitForExistence(timeout:)` with the result discarded
  and no assertion. If the element never appears, the test must **fail there**, naming it.
- "Fixing" a site by deleting the interaction or the assertion after it.
- Changing what a test asserts. This row makes existing assertions reliable; it does not soften them.

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** – also `xcodebuild ... build` → `BUILD SUCCEEDED`.
- `swift test --package-path ios` – whole suite, never subsetted; it stood at **1121**.
- Every suite you touch, whole, on `iPhone 17 Pro`, then `scripts/check-ui-test-count.sh` on the
  log - a suite can print "passed" while some of its tests never ran.
  `AddVehicleUITests` is **not** in your list; if you run it and it fails, that is the sibling
  lane's known order-dependence, not yours.
- **Mutation, and this is the one that matters**: pick one site you fixed, break the app path so
  the element genuinely never appears, and confirm the test now fails **at your wait, naming that
  element** rather than further down. That is the whole point of the change. Restore by copying a
  backup back and verifying `md5` – **never** `git checkout`.

## Report back

Whether my list of 23 was right; which sites needed a geometric scroll rather than a wait, and why;
observed counts and exit codes per suite; the mutation result - what it said and where it failed;
the `md5` match. Say whether you **ran** the tests or only wrote them. Do not commit.
