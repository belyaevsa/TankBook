# PJ.25 - the parts shelf is unreachable from the Garage

**[v1.x]**, product-owner priority (2026-08-31). Journey gap: `docs/JOURNEYS.md` J7b Shelf says the
shelf is *"visible under Garage"*.

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## The defect, confirmed in code

The shelf **works**. `PartsShelfView` exists (`ios/App/Sources/ServiceEntry/PartsShelfView.swift`),
its list is derived (`PartsShelf.onShelf`, never stored), the route exists
(`Routes.swift:116`, `Destinations.swift:86`), and it has a seed (`PartsShelfTestSeed`).

**It has exactly one entry point, and it is nested inside a service entry**:
`ServiceEntryView.swift:122`, `onViewShelf: { nestedSheet = .partsShelf }`. Nothing in the Garage or
`VehicleDetail` reaches it. So a user who wants to see what parts they have on the shelf must first
begin logging a service they may not be logging.

This is a **navigation** row, not a feature row: the screen is built and tested; it needs a door.

## What to build

- A route to the parts shelf from the Garage / `VehicleDetail`. `VehicleDetailView` already has the
  shared chevroned `NavigationLink` card helper (`VehicleDetailView.swift:172-180`) that its other
  rows use - **use it**, so the new row is indistinguishable from its neighbours.
- **Decide the scope and say why**: `.partsShelf` today is opened nested from a service entry for one
  car. A Garage row could be per-car (from `VehicleDetail`) or all-cars. Read `docs/SCREENMAP.md` and
  `docs/JOURNEYS.md` J7b and follow what they say; if they do not settle it, pick per-car (it matches
  where the row lives) and record the decision in `docs/SCREENMAP.md`.
- **Mind the back path.** `Routes.swift:125` currently lists `.partsShelf` among the
  `.discardSilently` destinations - that classification was made for a nested sheet inside a form.
  Check whether it is still right for a pushed Garage destination and say what you concluded;
  `docs/SCREENMAP.md` owns back-path conventions.
- The empty state must be a real one: a car with no parts on the shelf shows what that means and what
  to do next, never a blank screen (hard rule 7). If `PartsShelfView` already has one, reuse it; if
  it does not, this row adds it.

## Explicitly out of scope

- Changing what the shelf shows or how `PartsShelf.onShelf` derives it.
- The service-entry nested entry point - it stays exactly as it is; this row **adds** a door, it does
  not move one.
- Parts editing, installation flow, or anything in [PJ.28]'s expense territory.

## Docs to read before writing (in order)

1. `docs/SCREENMAP.md` - **the authority**: the navigation graph and back-path conventions. **Extend
   it** with the new route in the same change.
2. `docs/JOURNEYS.md` -> J7b Shelf.
3. `docs/DESIGN.md` -> the Garage / VehicleDetail row patterns.
4. `docs/ERRORS.md` -> empty states, if you add one.

## UI suites to run

`TankbookUITests/VehicleDetailUITests` and `TankbookUITests/PartsShelfUITests` (both named by the
row). If either does not exist under that name, **report the real name you ran** rather than
silently running nothing - a filter matching nothing still exits 0.

## Tests you must add

- **L4, the row's whole point**: the shelf opens from the Garage/VehicleDetail **without** going
  through a service entry, and shows the seeded parts.
- **L4**: the back path returns to where it was opened from, per whatever `docs/SCREENMAP.md` says.
- **L4**: a car with an empty shelf shows the empty state, not a blank list.
- **L4**: the existing service-entry nested route still works - the regression guard.

## Vacuous traps, named

- Asserting the row **exists** in the Garage rather than that tapping it **opens the shelf**.
- Adding the row and leaving `.discardSilently` unexamined, so the back gesture behaves like a
  form-dismiss on a pushed screen.
- A test that passes because the shelf was already on screen from the service-entry path.
- Duplicating `PartsShelfView` for the new entry point instead of routing to it.

## Screenshots

`design/screenshots/PJ.25-parts-shelf.png` and `-ru.png`: the shelf reached from the Garage. If the
empty state is new, a second pair for it is worth having.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; which scope you chose (per-car or all-cars) and what decided it; what you
concluded about `.discardSilently`; the real names of the UI suites you ran; and anything you found
and did not fix.

## Never stash, move or `git checkout` to get a "clean baseline"

To show a test fails before the fix: **write the test, run it against the unmodified code, then make
the change.** If the change is already written, prove the test's teeth with a **mutation** - revert
the one line the test is about, run it, restore the line. **Do not** `git stash`, `git checkout`, or
move files out of the tree: on 2026-09-08 an agent did that and a bad `mv` loop destroyed three of
its own new files. Assume you are not alone in this checkout.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1702 tests / 190
suites**, **777** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it reports thousands of phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suites named above **by name**, each with its **observed,
   non-zero** count. A filter matching nothing prints "0 tests ... passed" and still exits 0.
5. Localization gate - exit 0; report the key count and RU percentage. **Every new user-facing
   string is EN and RU** (hard rule 10).
6. Release build only if you touch a `#if DEBUG` seam (a test seed is one). Say which applies.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

**Screenshots**: EN **and** RU, **dark** theme, captured **outside** any running test (`simctl` and
`xcodebuild test` fight over the device). Pass `-homeResetDatabase` alongside any seed. RU:
`xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
RU runs 20-30% longer and short strings expand worst. **You cannot see your own screenshots** - the
orchestrator opens every one. State what you captured; do not assert it looks right.
