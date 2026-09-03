# RV.21 – Settings is reachable only from the Log tab

Reported by the product owner: the gear appears on Log and nowhere else, so from Trends or Garage a
user must switch tabs to reach Settings. The three are peer tab roots
(`docs/SCREENMAP.md` → "Tab roots (no back)"); there is no reason one of them owns the door.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**

## THE PART THAT MAKES THIS MORE THAN ADDING TWO BUTTONS

**The three roots do not share a header.** Verified 2026-09-03:

- `HomeView` draws a **custom** header — an `HStack` with a `.largeTitle.bold()` "Log" and the gear
  in a 44 pt circle (`HomeView.swift`, ~line 78, identifier `settingsButton`).
- `GarageView` uses **`.navigationTitle("Garage")`** — the system large-title bar.
- `TrendsView` has neither a gear nor a matching custom header.

Dropping a gear into each screen as-is would put it in a **visibly different place per tab**, which
is the opposite of what was asked ("put at the same places them"). So the task is:

> **give the three tab roots ONE header treatment**, with the gear in the same position on each.

Pick the treatment deliberately and say why in your report. The custom header is the one the artboards
draw and the one that already carries the gear; `.navigationTitle` is the one that gets iOS's
scroll-collapse behaviour for free. Whichever you choose, **all three must match** - a half-migration
is worse than what is there now, because it looks like a bug rather than a difference.

## What to build

1. One shared header component used by all three roots, carrying the title and the Settings gear.
2. The gear reaches Settings from each tab, by that tab's own navigation path - `TabRoots.swift`
   keeps a separate `NavigationStack` per tab (`logPath`, `trendsPath`, `garagePath`). Pushing
   Settings onto the wrong stack is the obvious way to break the back path.
3. `settingsButton` stays the accessibility identifier on all three, and each keeps its
   `accessibilityLabel("Settings")`.

## Explicitly out of scope

- The Settings screen itself.
- The tab bar (`AppTabBar`), and the `TabView`-less construction in `TabRoots.swift` - that file
  carries a long comment about three failed attempts to suppress the system bar. **Do not
  relitigate it.**
- Adding the sync-state chip. That is **RV.22**, it depends on this task landing first, and its
  design is settled in the RV.22 row - do not start it here.
- Any backend file.

## Read before writing

1. **`CLAUDE.md`** - hard rules 5 (palette tokens, no ad-hoc hex), 10 (String Catalogs), 14.
2. `docs/SCREENMAP.md` - **"Tab roots (no back)"** and the screen inventory. If the header changes,
   the doc moves in the same change.
3. `docs/DESIGN.md` - the layout and typography rules; the gear is `taillight` on `dash` today and
   `PaletteAccentGuardTests` governs that.
4. `ios/App/Sources/Navigation/TabRoots.swift`, `Home/HomeView.swift`, `Garage/GarageView.swift`,
   `Trends/TrendsView.swift`.

## Tests

- `cd ios && swift test` - **1154 today; must not fall.**
- L4: the settings button is **hittable on all three tab roots** and reaches Settings from each.
  **Assert the frames match across the three** - "a button exists on each" passes with the gear in
  three different places, which is exactly the reported complaint.

**Vacuous-assertion traps, named:**
- `app.buttons["settingsButton"].exists` on each tab. It existed on Log before this task, and
  existence says nothing about position.
- Asserting only that Settings opens. The bug is reachability *and* consistency; opening proves half.
- Testing Log first and assuming the others follow - Log is the tab that already worked.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed**, not by skimming. swiftlint from the repo root; zero **errors**.
`file_length` at 700 lines is an error - `HomeView.swift` and `TabRoots.swift` are both large, so if
your change pushes one past 700, split at a real seam rather than loosening the rule.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern - an agent's brief is part of its command line.

"Failed to load the test bundle … executable couldn't be located" is contention, not a red - zero
tests executed. Re-run once.

## Screenshots

`design/screenshots/RV.21-<tab>.png` and `-ru.png` for **each tab whose header your change alters**,
dark theme, outside any test run. RU matters: "Настройки", "Гараж" and "Тенденции" are longer than
their English counterparts and the header is where that shows.

Install the app you just built - newest `DerivedData/Tankbook-*` by `ls -dt`.

## Report back

- Exit codes for build, swiftlint, app build, `swift test`, each UI suite - numbers.
- **Which header treatment you chose and why**, and confirmation that all three now match.
- Unit-test count before/after; UI test names and observed count per suite; whether each RAN.
- Whether you saw the new frame assertion fail before the change.
- Files changed, doc sections extended, anything unfinished - named plainly.
