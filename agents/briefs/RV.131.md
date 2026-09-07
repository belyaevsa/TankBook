# RV.131 - the duplicate card hides the two entries it asks about

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The defect, in the product owner's words (2026-09-07)

> "there is a detection of duplicate records, but it doesn't show what are the records exactly.
> Just suggest merge them or keep separately."

## Measured, pinned to lines

`ios/App/Sources/Home/HomeSections.swift:401-431` renders **one sentence** and two buttons:

```swift
Text(String(format: L10n.localize("Possible duplicate – %@, %@ logged twice"), title, volume))
Button("Merge") { onMerge(group) }
Button("Keep both") { onKeepBoth(group) }
```

Both `%@` come from **`group.counted` only**: `duplicateTitle` (`:435`) is the counted entry's
station-or-fuel-kind, `duplicateVolume` (`:441`) its volume.

- **`group.excluded` is never rendered anywhere in the app.** It appears only inside the two
  resolution handlers, `HomeView.swift:325` and `:345`.
- **The card has no `NavigationLink`**, so neither member can be opened. Ordinary rows have one
  (`:450`).
- Its own comment says it is "a single card where the pair would otherwise appear as two rows" - so
  while the card stands, **both entries are removed from the Log and unreachable**.

**The detector makes this decidable only by looking.** `DuplicateDetector.swift:104-107`: same
vehicle, dates within **30 minutes**, volumes within **5%**, and its own header comment says "no
extra signals (station, ...)". Two genuine fills half an hour apart at one forecourt - a tank then a
jerrycan - match that rule exactly. The fields that separate them are odometer, total, unit price,
station and attachment: **precisely what the card omits.** The detector pairs on sameness and then
shows the user only the sameness.

Hard rule 13 says the app suggests and the **user decides**. Hard rule 7 is met in letter - both
next steps are named - but a next step the user cannot evaluate is not a resolution.

## You need NO new data. This is presentation only.

`LogStream.LogEntry` (`ios/Sources/TankbookCore/Consumption/LogStream.swift:145-170`) already
carries everything: `date`, `odometer`, `money`, `quantity`, `vendor`/`provider`, `entryTitle`,
`hasAttachment`, `isConflicted`. `DuplicateGroup` (`:96-105`) hands you **both** members as full
`LogEntry` values. Do not add a fetch, a view model, or a repository call.

## Design questions ALREADY CLOSED

1. **S2's single-count invariant does not change.** Until the user decides, exactly one member feeds
   every figure (`docs/SYNC.md` S2). `AnomalyInsight.swift`'s own comment documents a dependency on
   this - "an unresolved duplicate pair's excluded member never reaches the engine, so the anomaly
   can never disagree with the headline". **This row changes what is DISPLAYED, never what is
   counted.** A change that touches counting is out of scope and breaks two things at once.
2. **Both members must be reachable** via `Route.editEntry`. Opening the entry is the real escape
   when a summary cannot settle it, and the pair must never be *less* reachable than the two
   ordinary rows it replaced.
3. **Show what DIFFERS.** Sameness is what the detector already established; difference is the only
   information the user lacks. At minimum the time-of-day (the 30-minute window is the whole reason
   they were paired), odometer, and total - and **which one has an attachment**, because
   `docs/SYNC.md` makes that the merge survivor, so it explains *why* Merge keeps the one it keeps.
4. **It stays inline and non-blocking.** Not a modal - `docs/SYNC.md` S1-S8: conflicts surface as
   badges where the data lives, never modals at sync time.

## What to build

Decide between an expanded card showing both members and a card that reveals the pair, and **say
which you chose and why**. Constraints either way:

- Amber is attention, and this is attention (hard rule 5). No new colour, no ad-hoc hex.
- Copy is **one full localised phrase per language**, EN + RU in `Localizable.xcstrings`, never
  concatenation. Russian runs 20-30% longer and short strings expand worst; a two-column layout of
  two entries is where that bites.
- Numbers in DIN with `tabular-nums` where they align (hard rule 6) - two odometers or two totals
  side by side must be comparable at a glance, which is the entire point.

## Explicitly out of scope

- `DuplicateDetector`'s criteria. Widening or narrowing the 30-minute / 5% rule is a different row.
- The merge and keep-both handlers' behaviour (`HomeView.swift:325`, `:345`).
- The Garage, Trends or Recently-deleted surfaces.

## Docs to read before writing (in order)

1. `docs/SYNC.md` -> S2 (**the authority**: the single-count rule and the attachment-wins survivor).
2. `CLAUDE.md` - hard rules 5, 6, 7, 8, 10, 13.
3. `docs/ERRORS.md` -> the Home surface and the severity vocabulary.
4. `docs/DESIGN.md` -> the palette tokens and type rules.
5. The Home artboard in `design/screens/` - match it, do not reinvent.

## Checks

Baseline: **iOS 1631 tests / 181 suites with ONE known failure** (`RV.125`'s confident-wrong total
in the Vision-gated `RV.56` suite - **not yours, do not fix it**), `swift build` 0, `swiftlint` 0
errors **from the repo ROOT**, localization gate 0 (771 keys, 100% RU). Other rows are landing;
**re-measure the baseline yourself** and report what you found.

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0. Root-relative `excluded:` paths.
3. `cd ios && swift test` - full, never subsetted; report the number and the only-permitted failure.
4. `xcodegen generate` + the Home UI suites you touched **by name**; report a non-zero observed
   count - a filter matching nothing prints "0 tests ... passed".
5. Localization gate - 0, 100% RU, report the key count.
6. Release build - required only for a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L4**: the card names **both** entries and shows the fields that differ. Use a pair differing in
  **odometer and total** and assert **both** values are present - a test whose pair is identical
  cannot see this defect.
- **L4**: each member opens its editor from the card.
- **L1**: the single-count invariant is unchanged - an unresolved pair contributes exactly one
  member to the headline, the month total and the anomaly engine. Assert this **after** your change.
- **L4 RU**: both entries render without truncation in Russian.

### Vacuous traps, named

- Showing the excluded entry's **id** or a count instead of its distinguishing **fields**.
- Asserting the card renders, rather than that both entries are **identifiable and reachable**.
- **Changing what is counted while changing what is shown** - that breaks S2 and the anomaly
  engine's documented dependency on it.
- Testing a pair whose members are identical, where the defect is invisible.
- A layout that fits EN and truncates RU.

## Screenshots

The Log with an unresolved duplicate pair, dark, EN and RU:
`design/screenshots/RV.131-home-duplicate.png` and `-ru.png`. **Both entries and both actions must
be visible in the frame** - if they fall below the fold the screenshot does not show the fix.

- Pass the reset flag alongside the seed; seeds are idempotent and silently do nothing on a
  populated database.
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- Take them **outside** a test run - `simctl` and `xcodebuild test` fight over the device.
- **OCR your own capture and read the text back.** A committed screenshot has twice shown the
  opposite of its row's claim because it was taken before the screen settled.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**, and
which layout you chose with the reason. Name any closed decision you think is wrong and stop there
rather than absorbing it.
