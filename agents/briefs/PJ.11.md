# Task PJ.11 - TimelineValidator on every write, not just capture

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 6**, last of three (PJ.10 and PJ.9 landed in `ae97057`). `docs/JOURNEYS.md` F9a
says the timeline is checked **on every write, not just capture**. Today only the fill-up paths
check. A service odometer typo, or the MFM `9` row, lands **unflagged** and silently skews odometer
spans and cost/km for the life of the log.

## Where you may write

```
ios/App/Sources/ServiceEntry/**
ios/App/Sources/EditEntry/**
ios/App/Sources/Import/**
ios/Sources/TankbookCore/Import/**
ios/Sources/TankbookCore/Validation/**
ios/Tests/TankbookCoreTests/**
ios/App/UITests/ServiceEntryUITests.swift
ios/App/UITests/ImportUITests.swift
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
docs/JOURNEYS.md · docs/ERRORS.md
```

**Do not** touch `Capture/**`, `ConfirmManual/**`, `TankbookCore/Extraction/**`,
`TankbookCore/Config/**`, `TankbookCore/Sync/**`, `TankbookCore/Auth/**`, `backend/`, `site/`,
`Spike/` (the MFM fixture is **read-only** - its defect is deliberate), `project.yml`, `design/`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## The row's file paths are STALE - corrected here

`ServiceEntryDraft.swift` and `Expenses/ExpenseEntryView.swift` **do not exist**. The real write
sites, verified immediately before dispatch:

```
ios/App/Sources/ServiceEntry/ServiceEntryView.swift:358   repository.upsertServiceRecord(service, linkedParts:)
ios/App/Sources/ServiceEntry/ExpenseEntryView.swift:182   Expense(... conflict: .none ...)
ios/App/Sources/EditEntry/EditEntryView.swift:345,348,351 upsertChargeSession / upsertServiceRecord / upsertExpense
ios/Sources/TankbookCore/Import/ImportConversion.swift:57 conflict: .none on the import commit
```

**Enumerate the class, not the four lines above.** A guard written to cover exactly the defect in
front of you is how the contrast guard was too narrow twice in one day (`HANDOVER.md`). Find every
path that writes an entity carrying `conflict` and decide, for each, whether it must validate -
then **pin that list with a source-scan test** so a fifth write path cannot appear unflagged. Follow
the pattern in `LowPowerModeTests.productionCallSitesMatchTheWiredAndUnwiredSplit` (`#filePath`
enumeration), and **say plainly in the test what a text scan cannot see**.

## The pattern to copy, already in the tree

`ManualFillUpView.swift:572` is the shape - do not invent a second one:

```swift
let validations = TimelineValidator.validate(entries: existingEntries + [candidate],
                                             vehicle: vehicle)
candidate.conflict = validations.first { $0.entryID == candidate.id }?.conflict ?? .none
```

## What to build

1. **Service, expense and charge-session saves stamp `conflict`** from `TimelineValidator`, on
   create and on edit.
2. **The import commit stamps it too**, and the import classifier gains an **order/pace row kind**
   so the review list can show it before anything is written.
3. **The flagged row names its next step** (hard rule 7) and **never blocks the save** (hard rule
   13 - the app suggests, the user decides; an implausible value is a warning, never a refusal).
   Amber only - `warn` is attention, and red is for system dialogs alone (hard rule 5).

## The acceptance case is real data - do not clean it

`Spike/ImportFixtures/mfm/README.md` records a **deliberately preserved** defect: a Volvo row dated
`4/14/2025` with `odometer 9`. The README says keep it, and `docs/TASKS.md` P5.4 records that a
"plausibility repair" nulling odometers below 100 **fails 2 of 16** tests. So: the `9` row must
**commit flagged and be excluded from spans** - not dropped, not repaired, not silently fixed.
Nothing lost silently (hard rule 8).

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 951 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: a service record dated below its neighbour saves `.flagged`, and a plausible one saves
  `.none`. Both halves.
- **L1**: the MFM `9` row commits **flagged and excluded from the span**, and the other 15 rows are
  untouched.
- **L1**: the source-scan guard over the write paths.
- **L4 `ServiceEntryUITests`**: the amber row and its **Fix** affordance; save still succeeds.
- **L4 `ImportUITests`**: the flagged-order row appears in the review list.

Run only those two suites with `-only-testing:` and **report the observed count for each**
(`ImportUITests` is 13 today); a selector matching nothing prints "Executed 0 tests" and reads
exactly like success. **Do not run the full UI suite.**

**A guarantee in `ios/App/Sources` can only be pinned at L4** - there is no app unit-test target,
so a core-only run will not see it. Say which suites you ran with each mutation result; that trap
made two of the orchestrator's own mutations appear to pass today.

**Never `pgrep -f`** for a build - your brief is part of your command line, and that killed a
sibling agent 48 minutes in. Use `pgrep -x xcodebuild`; never `pkill -f`.

## Mutations you must run and report

1. Stamp `.none` unconditionally on the service path. The L1 must fail.
2. Make the flagged state **block the save**. A test must fail - hard rule 13 says it must not.
3. Repair the MFM `9` row instead of flagging it. The fixture test must fail.
4. Add a new write path that skips validation. The source-scan guard must fail - if it does not,
   the guard covers the four call sites you changed rather than the class.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc** for scripted edits.

## Screenshots

EN **and** RU, dark: the flagged service row with its amber warning and Fix, and the import review
list showing a flagged-order row. Capture **outside** a test run, name them
`PJ.11-service-flagged{,-ru}.png` and `PJ.11-import-flagged-row{,-ru}.png`, and register them in
`scripts/capture-screenshots.sh`.

**Check the feature is in frame before finishing** - captures have been deleted rather than
committed here for showing a screen without their subject. You cannot see them; the orchestrator
opens every one and reads the Russian for grammar, not only for overflow.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results **with the
suites you ran**; the full list of write paths you found and which you decided must validate; the
files changed; and anything in this brief that is wrong - eight agent pushbacks in this project have
been correct, two of them on stale paths in these very rows.

En-dashes only, never em-dashes.
