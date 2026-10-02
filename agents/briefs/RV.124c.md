# RV.124c - rules per country: the sourced winter-tyre law table

Journey: J7b (tires - the seasonal advisory). Read the RV.124c row in `docs/TASKS.md` (search
`RV.124c`) and the RV.124 row above it - the owner decided the shape on 2026-10-02: WeatherKit
on the phone, the car's home city on its profile, a city dictionary, and **rules per country as a
sourced data table, not code**. The legal research you start from is
`agents/briefs/RV.124-design.report.md` section 3 - re-check every row against its primary
source; do not copy it on trust.

## Where you may write

Only these: `ios/Sources/TankbookCore/Tires/` (the data file `TireLaws.seed.json` already exists
as an empty placeholder and is already registered in `ios/Package.swift` - **do not edit
Package.swift**), `ios/Tests/TankbookCoreTests/TireLaw*Tests.swift`, and a new `### Tyre laws`
section in `docs/SCHEMA.md` (add it after the `### AdBlue` section; touch nothing else in that
file). Nothing else - other files are being changed by another worker right now (Vehicle,
TireSet, payloads, sync, backend). git is read-only for you.

## What to build

1. **The data file** `TireLaws.seed.json`: `{ "version": 1, "rows": [...] }`. Each row: `country`
   (ISO 3166-1 alpha-2), optional `jurisdiction`, `vehicleClass` (e.g. `M1`, `N1`, or `upTo3500kg`),
   `kind` (`dated` - winter tyres required between fixed dates; `conditional` - required between
   dates only in winter road conditions; `none` - no national date rule), `from` and `to` as
   `MM-DD` (inclusive; a window may wrap the new year), `criteria` (free text: what counts as a
   winter tyre there, e.g. the M+S / 3PMSF marking), `seasonGate` (`autumnFrom`, `autumnTo`,
   `springFrom`, `springTo` as `MM-DD` - the months a forecast-based advisory may fire in that
   country), `sourceURL`, `checked` (ISO date you checked it), `status` (`verified` / `reviewDue`
   / `withdrawn`), `note`. Rows: EE, LV, LT, RU, KZ (expected `dated`), FI, SE, AT, DE (expected
   `conditional`), NO (`none` nationally; say why in `note`), BY only if you find and cite a
   current primary source, otherwise omit it and say so. Plus PL, CZ, UA and the other countries
   the receipt corpus comes from if their rule is clear and sourced. **Mark `verified` only when
   you read the primary legal or government source yourself**; otherwise `reviewDue`.
2. **The core model** in `Tires/TireLaw.swift`: `TireLawTable` (decode the bundled file through
   `Bundle.module`, like `FuelPriceBandPack` does for its seed; tolerant of unknown keys and of
   unknown `kind`/`status` values - an unknown one is skipped, never a crash) and a pure query:
   `func law(country: String, on date: Date, calendar: Calendar) -> TireLawVerdict` returning one
   of: `.required(from: Date, to: Date, source: URL)` (a verified dated row whose window contains
   or is about to contain the date - define "about to" as within 30 days before `from`, a named
   constant), `.conditional(from:to:)`, `.noDatedRule`, `.unknown` (no row, or only
   unverified/withdrawn rows). And `func seasonGate(country:) -> SeasonGate?`. **Only a
   `verified` `dated` row may produce `.required`** - that is the promise the notification copy
   relies on.
3. **Tests** (Swift Testing, `TireLawTests.swift`): a dated verified row yields `.required` with
   the right dates inside and just before the window, and nothing after it; a window wrapping the
   new year (Dec-Mar) works on both sides of 1 January; a conditional row never yields
   `.required`; a `reviewDue` and a `withdrawn` dated row yield `.unknown`; an unknown country
   yields `.unknown`; an unknown `kind` value in the JSON is skipped, not a decode failure; the
   bundled file decodes and every row has a source URL and a checked date. **Mutation:** make
   `reviewDue` count as verified - the reviewDue test must go red; restore.
4. **The doc section** `### Tyre laws` in `docs/SCHEMA.md`: the row fields, the `kind` and
   `status` meanings, the rule "only verified dated rows may say required", and how the table is
   maintained (a data file reviewed before each autumn and spring; a correction is a new
   `version`; it will also be refreshable as reference data - the endpoint is a separate task).

## Checks (exit codes; report each)

`cd ios && swift build --scratch-path /private/tmp/claude-501/spm-rv124c` and `swift test
--scratch-path /private/tmp/claude-501/spm-rv124c --filter TireLaw` (report the count - non-zero);
`swiftlint lint` from the repo root, exit 0. Do not run xcodebuild or UI tests.

## Standing fences

En-dashes only, never em-dashes. Code comments: present tense, no task ids, no dates except data.
Never `pgrep -f`/`pkill -f`. Never move, rename or revert a file you did not create.

## Report back

Exit codes and counts; the mutation's red-then-green; the table of rows you shipped with status
and source; every country you left out or marked `reviewDue` and why; anything you could not
verify.
