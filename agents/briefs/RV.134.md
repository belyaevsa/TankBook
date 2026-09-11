# RV.134 - five more places bake a unit into the sentence

**Scenario: J3b · type it (the peer path, every locale).** The only v1 row holding J3b open.

## The defect

Found 2026-09-08, two of the five by opening `RV.126`'s own RU screenshot. On a miles/gallons car the
Confirm screen renders the odometer in `миль` and the volume in `гал`, then labels the price row
**`Цена / л`** (`ManualFillUpSections.swift:147`, key `"Price / L"`) and captions it
**`считается из суммы ÷ литров`** (`:150`, `"fills in from total ÷ liters"`). One screen states the
user's units correctly in two rows and contradicts itself in two others. Three more:
`ManualFillUpSections.swift:389` hardcodes `"+\(delta.km) km since last"` for **every** car;
`ServiceEntryFormState.swift:184` and `ImportReviewRowFields.swift:53` hardcode the km key the
same way. Hard rule 10 and 13 together: a value the user set is stated back to them wrong.

**Line numbers are from 2026-09-08 - re-find each by its key, not its line.**

## What to build

**One full localised sentence per unit, exactly as `RV.126` did it** -
`OdometerConflict.quote(day:odometer:distanceUnit:)` is the pattern. The reason is the one that
matters: RU declines units differently (`км` indeclinable, `миль` genitive plural, `л`/`гал`
abbreviations), so a composed `"\(n) \(unit)"` is wrong in RU even when EN reads fine. A key per
(sentence, unit), never a unit token dropped into a sentence.

**Then audit the seam, not the file.** `RV.126` scoped its audit to one file and missed two on the
same screen. Grep every `L10n` key containing `km`, `L`, `/ L`, `liters`, `litres`, `mi`, `gal` and
every string interpolation adjacent to `.km`, `.mi`, `.l`, `.gal`; list every hit and say which
are correct (already per-unit) and which you fixed. **The list is a deliverable.**

## Tests

- **L1**: each fixed sentence, for a metric and an imperial vehicle, in EN and RU - asserting the
  full phrase, not the presence of a unit token.
- **L4 `CaptureUITests` RU on an imperial car**: the Confirm screen's price label and caption read
  `гал`, not `л`. EN + RU frames of that screen on an imperial seed; capture lines added.

## Mutation - named

Restore the `"Price / L"` key on the imperial path; the RU imperial L1 goes red. Byte-identical
restore; outputs verbatim.

## Vacuous traps

- A `unitSymbol` interpolated into one sentence - that is the bug with a new name.
- Fixing the five and stopping; the audit list is the point.
