# RV.69 – the catalog's tank capacity is litres, shown AND SAVED as the user's unit

Found 2026-09-05 by the orchestrator while opening RV.67's screenshot: a Lada suggestion rendered
**"50 gal"**, which is ~190 L and impossible. **Pre-existing, not RV.67's doing. Verified end to
end - confirm it still holds, do not re-derive it.**

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.**

**Use the `iPhone 17` simulator.**

## Part 1 – the units bug. This is the serious half

The chain, each link checked:

1. The catalog field is **`tankCapacityL`** - litres, by name (`CatalogSuggestions.swift:23`,
   `VehicleCatalog.swift:23`).
2. **`AddVehicleSupport.capacityText`** (`AddVehicleForm.swift:179-184`) does **no conversion** - it
   only formats the `Double`.
3. The suggestion row prints that number beside **`L10n.volumeUnit(units.volume)`** - the USER's
   unit (`AddVehicleSections.swift:87`).
4. **And it is not display-only**: `apply()` writes
   `form.capacity = AddVehicleSupport.capacityText(tank)` (`AddVehicleView.swift:121-123`), so the
   litre number is stored verbatim into a field read in the user's unit.

**So a US-units user who accepts the suggestion gets a car whose tank is wrong by 3.785x**, and tank
capacity feeds tank-level and range features.

**This inverts hard rule 13.** The app's suggestion is meant to be a default the user can judge and
correct. Here it is a WRONG FACT the user cannot spot, because the label agrees with their own
settings. The RU screenshot proves the shape: under litres it correctly reads **"50 л"**. **The bug
is invisible in metric.**

## Part 2 – the year separator. Cosmetic, same rows

`Text("\(suggestion.entry.yearsStart)–")` (`AddVehicleSections.swift:81-84`) interpolates an `Int`
into a SwiftUI `Text`, which applies locale grouping: **"2,011–"** in EN, **"2 011–"** in RU. A year
is not a quantity and must not carry a thousands separator.

## What to build

**Convert at the boundary, once.** The catalog stores litres; the UI shows and the form stores the
user's unit. Convert on the way OUT of the catalog and on the way INTO `form.capacity`. **Say where
you put the single conversion** - if it ends up in two places, say why.

**Check the battery path too** (`batteryCapacityKWh`, `AddVehicleSections.swift:89-90` and the
`else` branch of `apply`). kWh is unit-invariant so it is probably already correct - **confirm it,
and make sure your fix does not accidentally convert it.**

**Then audit every other place a catalog litre value reaches the UI or the form**, and report what
you found. This is a class, not one call site.

**For the year**: render it verbatim (`Text(verbatim:)` or `String(...)`) and **grep for the same
`Int`-into-`Text` shape elsewhere** - odometer, plate year, counts, any id. Report every instance
you find, and fix the ones that are genuinely wrong. A count like "5 entries" SHOULD group at
1,000+; a year, an id or a version must not. **Say which you judged to be which.**

**Do not "fix" the units by relabelling the row to always say litres** - the user's unit setting is
theirs (hard rule 13), and showing metric to a gallons user is the same class of bug pointed the
other way.

## Read before writing

1. **`CLAUDE.md`** – hard rule 13 (**the app suggests, the user decides** - and a suggestion the
   user cannot judge is not a suggestion), rule 6 (numbers in DIN, units subordinate), rule 14.
2. `docs/SCHEMA.md` → Vehicle, the catalog, and how units are stored vs displayed - **the storage
   unit is the authority here**; `docs/DESIGN.md` → number formatting.
3. `ios/Sources/TankbookCore/Catalog/CatalogSuggestions.swift`, `VehicleCatalog.swift`,
   `ios/App/Sources/AddVehicle/AddVehicleSections.swift` (the row), `AddVehicleView.swift`
   (`apply`), `AddVehicleForm.swift` (`capacityText`), and wherever `Vehicle.Units` conversion
   already lives - **reuse it, do not write a second converter.**

## Tests

**iOS unit 1421 today; must not fall.** UI suite: `AddVehicleUITests` (and
`RV67SuggestionScrollUITests`, which drives the same rows).

- **The headline L1: a catalog entry with `tankCapacityL: 50` yields 50 for a litres user and
  ~13.2 for a gallons user, in BOTH the row text AND the applied `form.capacity`.** Assert both -
  **fixing only the label leaves the saved value wrong and looks fixed.**
- **L1: the saved vehicle's capacity round-trips to the same PHYSICAL volume under either unit
  setting.** That is the assertion that catches a half-conversion.
- L1: a year renders "2011" with no separator, under a locale that groups.
- L1: the battery value is unchanged by the fix.
- L4: accepting a suggestion under gallons shows a plausible tank in the form, and it stays
  editable (rule 13's second half).

**Vacuous-assertion traps, named:**
- **Testing only under litres.** The bug is invisible there - that is why it survived.
- Asserting the row shows a number, or that the label string is correct.
- Asserting `form.capacity` is non-empty rather than its VALUE.
- Asserting the year string without a grouping locale active.

**Mutation-check and report it**: remove the conversion and confirm the gallons test goes red.
Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"   # from repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
**Never `pgrep -f`/`pkill -f`.**

## Screenshots

**Required, EN and RU, dark, WITH US/GALLON UNITS SELECTED** - that is the only setting where the
bug is visible, so a metric screenshot proves nothing. Save as
`design/screenshots/RV.69-addcar-units.png` / `-ru.png`, captured OUTSIDE a test run.
**Verify the two files differ (`md5 -q a.png b.png`) before reporting them** - RV.58 shipped an "RU"
screenshot byte-identical to its EN one because the `-AppleLanguages "(ru)"` launch did not take.
A `-` prefixed launch argument can PERSIST across relaunches; reinstall between shots if a state
flag sticks. **`scripts/capture-screenshots.sh` is OUTSIDE your write area** - name the capture
lines in your report instead. You have no image input: say so.

## Report back

- Exit codes (captured, not piped), unit counts before/after, UI suites run, mutation result.
- **Where the single conversion lives**, and whether you reused an existing converter.
- **The gallons value for a 50 L tank**, in the row and in `form.capacity`.
- **Every other place a catalog litre value reaches the UI or the form** - the class audit.
- **Every `Int`-into-`Text` instance you found**, and which you judged should group and which should
  not.
- Confirmation the battery path is unchanged.
- Anything you noticed that is not RV.69 - named separately.
