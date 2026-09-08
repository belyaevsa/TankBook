# RV.142 - the Log row says "Diesel" twice and drops the station

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## What the owner sees

Every row reads `Diesel` / `53.0 L · Diesel · 375 963 km · 11 Jul 20` - the fuel kind twice, no
station, no price, no consumption. Product owner, 2026-09-08, asked for: the station name as the
title where it exists, the odometer promoted, and a second line carrying station and this fill's
consumption.

## Three findings. Two are bugs; the third is already computed.

### 1. The station title EXISTS and is starved of data

`HomeSections.swift:527-534` already returns the station name and falls back to the fuel kind only
when `stationId` does not resolve. It never resolves for imported rows, and the chain is broken in
**two** places:

- `ImportConversion.swift:59` hardcodes `stationId: nil`.
- **`ImportCandidate` has no station field at all** - the iOS wire model
  (`ImportModels.swift:95-101`) carries `entityType, date, odometer, volumeL, unitPrice, money,
  fuelKind, ...` and nothing for a station.

Meanwhile `DrivvoParser.cs:521,579` lists `station` in its **header-mapping table** (`Азс` /
`Gas station`). **That is the sharp part**: the column is *recognised*, so [RV.116]'s
unsupported-column notice will not list it either. The data is read, looks supported, and is thrown
away without ever telling the user.

### 2. The duplicate is a rule that never looks at the title

`showsFuelKind` (`LogStream.swift:158-162`) asks only whether the kind earns its place **against the
vehicle** - multi-fuel, or different from the car's usual. It never asks whether the title is
already that kind. When the title falls back to the fuel kind, the subtitle repeats it.

### 3. Per-fill consumption already exists

`Segment` carries `per100` and `closingFillID` (`Segment.swift:14-19`). The figure for a given fill
is computed today and simply never reaches the row. **Read the engine's value; do not recompute in
the view** (hard rule 2: the view does no arithmetic).

## Design questions ALREADY CLOSED

1. **Fix the two bugs before the layout.** A station-titled row and a non-repeating subtitle are
   most of what was asked, and they need no design decision.
2. **Per-fill consumption is ABSENT, never zero**, for a fill that closes no segment - a non-full
   tank, the first fill, a gap in the history. The absent case is the design, exactly as [RV.120]
   states, and a `0.0 L/100km` is a wrong claim about the car.
3. **Do not fix the duplicate by deleting the fuel kind.** It earns its place on a genuinely
   multi-fuel car, which is what the rule exists for. Make the rule title-aware instead.
4. **Do not fork [RV.115].** That row owns the station BRAND list, and its decision is that brands
   are reference data ordered on the device. Creating station records on import must not invent a
   second, competing notion of what a station is - if matching an imported name to an existing
   station is not obvious, create the record and say so, leaving brand normalisation to [RV.115].

## The one question I want DECIDED, not assumed

The owner asked for the **odometer as the primary information**. Look at the real data first:
consecutive odometers read `375 963`, `375 261`, `374 755`, `373 915` - they differ only in the last
three digits and scan as one repeated number, whereas the station is what tells rows apart at a
glance. **Build it, look at it against the artboard in `design/screens/`, and say which reads
better.** If the odometer wins, `docs/DESIGN.md` gains the rule and the artboard is updated in the
same change. If it does not, say so and keep the station as the title - the owner asked for an
improvement, not for a specific layout.

## What to build

- The station chain: candidate field -> conversion -> a `Station` record (`Repository.upsertStation`
  exists, `Repository.swift:290`) -> `stationId` on the entry. Backend and iOS both move.
- `showsFuelKind` made title-aware.
- Per-fill consumption on the row, from `Segment.per100` keyed by `closingFillID`.
- **Worth doing while you are here, and the owner asked "what else"**: `unitPrice` (price per litre)
  says more about a fill than its total. Add it if it fits the row without crowding; say so either
  way. The total's absence is [RV.140]'s subject, not yours.
- Update `docs/SCHEMA.md` -> import mappings for the station, and `docs/DESIGN.md` if the layout
  rule changes.

## Explicitly out of scope

- **[RV.140] edits the SAME file (`HomeSections.swift`) - it lands before you.** `git log` before
  you start and build on what is there. Do not touch the money rendering.
- [RV.115]'s brand list, [RV.116]'s unsupported-column notice.
- The Trends screen.

## Docs to read before writing (in order)

1. `CLAUDE.md` - hard rules 2, 6, 10, 13.
2. `docs/DESIGN.md` -> the log row, type rules, `tabular-nums` for aligned digits.
3. `docs/SCHEMA.md` -> import mappings and the consumption model.
4. `design/screens/` - the Home artboard for this row.

## Checks

Baseline: `main` green at **1657 tests / 184 suites**, backend **436**, **777** localization keys.
**Re-measure yourself** - [RV.140] lands first and will have moved these.

1. `cd backend && dotnet build` / `dotnet test` / `dotnet format --verify-no-changes` - 0 each,
   report the count.
2. `cd ios && swift build` - 0.
3. `swiftlint lint` from the **repo ROOT** - 0.
4. `cd ios && swift test` - full, never subsetted; report the number.
5. `xcodegen generate` + the UI suites you touched **by name**; report a **non-zero** count.
6. Localization gate - 0, report the key count.
7. Release build - required if you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L1 backend**: a Drivvo row's station name reaches the candidate.
- **L1 iOS**: an imported row with a station name arrives with a **resolvable `stationId`**; one
  without a station keeps `nil` and the row falls back to the fuel kind - **that fallback is the
  path that regressed, so it needs its own fixture**.
- **L4**: a row titled with the station shows the fuel kind only when it earns its place; a row
  titled with the fuel kind **never repeats it**.
- **L1**: per-fill consumption equals the `Segment.per100` whose `closingFillID` is that fill, and
  is **absent** for a fill closing no segment.
- **L4 RU**: the row does not truncate in Russian.

### Vacuous traps, named

- Asserting the title is the station without a fixture where the station is **absent**.
- Showing `0.0 L/100km` for a fill with no segment.
- Recomputing consumption in the view instead of reading the engine's value.
- Removing the fuel kind entirely to kill the duplicate.
- Asserting the candidate has a station field without asserting a `Station` record exists after
  commit.

## Screenshots

The Log with station-titled rows and per-fill consumption, dark, EN and RU:
`design/screenshots/RV.142-log-row.png` and `-ru.png`. Include at least one row **without** a
station so the fallback is visible in the same frame. Take them **outside** a test run, pass the
reset flag with the seed, and **OCR your own capture** before reporting it.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild` / `pgrep -x dotnet`. Never
`pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**, your
answer on odometer-as-title with what you saw, and whether you added the unit price. Name any closed
decision you think is wrong and stop there rather than absorbing it.

---

## RESUMING 2026-09-08 - a previous run was killed by MEMORY PRESSURE, not by a fault

It got a long way and **the tree compiles** (`swift build` exit 0). Judge the inherited code on its
merits - a resumed run that rubber-stamps what it finds is the failure this note exists to prevent -
but do not redo what is already right. What exists:

- **The station chain, end to end**: `ImportStation.swift` (new), plus edits to `DrivvoParser.cs`,
  `ImportModels.swift`, `ImportConversion.swift`, `ImportLanes.swift` and
  `ImportFlowModel+Wizard.swift`. Verify the candidate carries the station and that a `Station`
  record exists after commit.
- **Row rendering**: `HomeSections.swift`, `HomeSections+LogStream.swift`, `LogStream.swift`.
- **Tests**: `RV142StationAndConsumptionTests.swift` (L1), `RV142LogRowUITests.swift` (L4),
  `RV142HomeTestSeed.swift`, and `DrivvoParserTests.cs`.
- It was killed **mid-edit of `RV142HomeTestSeed.swift`**, replacing a hardcoded `.diesel` with a
  per-row `fillKind`. Check that file first - it is the most likely place to find something
  half-written.

**What remains, and it is the half the row is judged on:**

1. **Run every gate and report the exit codes.** None were run.
2. **The screenshots**, EN and RU, with at least one row lacking a station so the fallback is
   visible in the same frame.
3. **Your answer on odometer-as-title**, with what you actually saw against the artboard.
4. **Whether you added the unit price**, either way.

**Baselines have moved**: `main` is green at **1664 tests / 185 suites**, backend **436**, **777**
localization keys. [RV.140] landed in `HomeSections.swift` before you - it renders a pending row's
original amount, e.g. `110.00 USD`, dimmed. **Do not disturb the money rendering**; your row is the
title, the station, the fuel-kind duplicate and the consumption.

---

## RESUME 2 - 2026-09-08: killed by memory pressure again. One regression left, cause known.

The previous run was killed a **second** time by the machine running low on memory - not a fault in
the work. I then ran every gate myself. Here is exactly where it stands, measured:

| Gate | Result |
|---|---|
| `swift build` | **0** |
| `swiftlint lint` (repo ROOT) | **0 errors** |
| `swift test` | **0** - **1671 tests / 186 suites**, zero failures |
| `dotnet build` / `format` / `test` | **0 / 0 / 0** - **437 backend tests** |
| Localization gate | **0** - 777 keys, 100% RU |
| Your three new L4 tests | **all pass** |

**One regression, and I know precisely why**:
`HomeUITests.testEntryRowSubtitleWrapsToTwoLinesAtXL` (`HomeUITests.swift:597-616`) now fails -
odometer and date land on the SAME line (both y=768.03) where the test requires the subtitle to wrap
at `UICTContentSizeCategoryXXXL`.

**Your change caused it, correctly.** That test seeds `-seedHomeFullHistory`, whose fills have no
station, so the title falls back to the fuel kind - and your title-aware `showsFuelKind` now removes
the kind from the subtitle it used to duplicate. The line got shorter and no longer wraps. The
test's own comment still describes the old subtitle: `"42.0 L · 95 · 123 600 km · Aug 17"`.

**The test's intent is "a long subtitle WRAPS rather than truncating at XXXL"** - that intent is
still worth protecting; only its fixture is stale. **I tried repointing it at `-seedHomeRV142Log`
and it still failed, so do not simply repeat that** - measure what that seed's subtitle actually
renders at XXXL before choosing. I reverted my attempt; `HomeUITests.swift` is untouched in the tree.

Fix the regression, keep the assertion honest (do not weaken the 8pt threshold to make it pass), and
**re-run the whole `HomeUITests` suite** - it is 44 tests and only the full run shows this one.

**Still owed from the last resume**, none of it done:

1. The **screenshots**, EN and RU, with at least one station-less row in frame so the fallback is
   visible.
2. Your answer on **odometer-as-title**, with what you actually saw against the artboard.
3. Whether you added the **unit price**, either way.

Everything else is verified and staying. Do not re-verify what the table above already reports, and
do not touch the money rendering - [RV.140]'s `110.00 USD` is in the same file.

---

## RESUME 3 - 2026-09-08: ONE regression left. Four fixes already ruled out by measurement.

Everything else in this row is done and **verified by the orchestrator**, not by an agent report:

| Gate | Result |
|---|---|
| `swift build` | **0** |
| `swiftlint lint` (repo ROOT) | **0 errors** |
| `swift test` | **1671 tests / 186 suites** |
| `dotnet build` / `format` / `test` | 0 / 0 / **437** |
| Localization gate | **0** - 777 keys, 100% RU |
| Your three new L4 tests | **all pass** |

**Do not re-verify the above and do not redo the feature work.** Your job is one failing test, plus
the three deliverables at the bottom.

### The failing test

`HomeUITests.testEntryRowSubtitleWrapsToTwoLinesAtXL` (`HomeUITests.swift:597-616`). It requires the
subtitle to wrap at `UICTContentSizeCategoryXXXL`; the odometer and date now land on the SAME line.

**The cause is certain and is your own change, working correctly.** That test seeds
`-seedHomeFullHistory`, whose fills carry no station, so the row title falls back to the fuel kind -
and your title-aware `showsFuelKind` correctly stops the subtitle repeating it. One segment shorter,
it no longer overflows. **The assertion did not become false; it became unprovable.** The test's own
comment still describes the old subtitle, `"42.0 L · 95 · 123 600 km · Aug 17"`.

`SubtitleFlow` (`HomeSections.swift:479`) genuinely wraps, so the behaviour is fine - the fixture is
stale.

### Four things I tried. All FAILED. Do not repeat them.

1. Repointing the test at `-seedHomeRV142Log` - still one line.
2. Raising the size to `UICTContentSizeCategoryAccessibilityLarge` - still one line.
3. Running the test in **Russian** (the trick the sibling test at `:562` uses, and its comment says
   EN fits on one line even at XXXL) - **still one line**.
4. Any of the above combined with editing the comment - two of my attempts also broke
   `swiftlint`: `HomeUITests.swift` is at **~697 of its 700-line cap**, so more than a couple of
   added lines is a lint ERROR. Budget for that.

**Every failure reported the identical geometry - odometer and date both at y=768.0269368489581.**
That number not moving across three different seeds, two type sizes and two languages is the most
informative fact available: the subtitle is not marginally short, it is comfortably short, and
something is capping it that none of those inputs changes.

### Do this first, before choosing a fix

**Dump what is actually rendered.** I inferred the subtitle four times and was wrong four times.
Print the row's real `staticTexts` - identifiers, labels and frames - at the size under test, and
look at how many segments exist and how wide they are. One look at the real string beats another
guess, and skipping it is exactly what cost these four attempts.

Then fix it so the test proves what it is named for - **a long subtitle wraps rather than
truncating**. Constraints: do **not** weaken the 8pt threshold, do **not** delete the test, and keep
`swiftlint` at 0 errors including the file-length cap.

### Still owed

1. **Screenshots**, EN and RU, with at least one station-less row in frame so the fallback is visible.
2. Your answer on **odometer-as-title**, with what you saw against the artboard.
3. Whether you added the **unit price**, either way.

Do not touch the money rendering - [RV.140]'s `110.00 USD` lives in the same file.
