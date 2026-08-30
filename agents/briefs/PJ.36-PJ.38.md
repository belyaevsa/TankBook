# Task PJ.36 + PJ.38 - "Export everything" actually exports

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 17.** `VISION.md:42` promises "one-tap CSV/JSON export - always free" and the row is
**dead**: a bare `HStack` with a chevron whose own comment says "the export body is a later task".
The promise is on screen; the feature is not.

## ANOTHER AGENT IS RUNNING RIGHT NOW

PJ.33 holds `ios/App/Sources/Import/**`, `backend/`, and `site/`. **Do not touch any of them.**

**Use `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'` for every `xcodebuild`** so you do
not fight it for the device. Two known **device-specific** families fail on some simulators and pass
on others - the `AddVehicle` pair and the `ConfirmManual` pair (`HANDOVER.md`). Neither is in your
suites; if you see them, they are not yours. **Name the simulator in every result you report.**

## Where you may write

```
ios/App/Sources/Settings/SettingsView.swift   (the export row's action only)
ios/App/Sources/Garage/**                     (the per-car export row)
ios/App/Sources/Export/**                     (new, if the share plumbing wants a home)
ios/Sources/TankbookCore/Backup/**
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
ios/Tests/TankbookCoreTests/**
ios/App/UITests/SettingsUITests.swift · VehicleDetailUITests.swift
scripts/capture-screenshots.sh
docs/ERRORS.md · docs/SCHEMA.md · docs/JOURNEYS.md
```

**Do not** touch `Import/**`, `site/`, `backend/`, `Capture/**`, `ConfirmManual/**`,
`ServiceEntry/**`, `SignIn/**`, `Welcome/**`, `Reminders/**`, `Sync/**`, `Config/**`, `Auth/**`,
`Spike/`, `project.yml`. **Do not commit. Do not tick `docs/TASKS.md`.**

## What already exists - build on it, do not reinvent

P5.5a shipped the archive: `BackupFormat.swift` with `ArchiveScope`, and `VehicleArchiveReader`.
The scope guard is real and tested - a `scope: "vehicle"` archive must not pass an account restore.

## What to build

**PJ.36 - the row does something.** It builds the **whole-account** archive and hands it to the
share sheet. The **disk-full** row from `ERRORS.md:163` is a real state, not a crash: it names its
next step and the app stays usable (hard rule 7).

**PJ.38 - CSV per car.** Fill-ups, charges, service and expenses as flat rows using **`SCHEMA.md`'s
exact field names**, the **original + home money pair** (hard rule 3 - money is a pair, never one
number), and **ISO dates**. It ships **inside the archive and as its own share item**.

**Tombstones count.** The row's own check says row count equals **live + tombstoned** entries by
type. An export that silently drops deleted-but-undoable rows loses data the user still owns
(hard rule 8, 30-day undo).

**Export is always free** - no gate, no upsell, no Pro check anywhere near this path
(`VISION.md`, and hard rule 7 forbids monetisation on error surfaces).

## Explicitly out of scope

The PDF dossier (**PJ.37**, deferred) · import (**PJ.33**, another agent) · sync or blob upload ·
`docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1052 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build ; echo "app build: $?"
```

- **L1**: the whole-account archive **round-trips through `VehicleArchiveReader` hash-equal**.
- **L1**: CSV row count equals **live + tombstoned** entries **by type** - assert per type, not a
  total, or one type dropping to zero hides inside the sum.
- **L1**: a **golden fixture diff** for the CSV - pin the bytes, so a column rename or a date format
  change is visible.
- **L1**: the money pair survives - assert **both** amounts and the currency, not just one.
- **L4 `SettingsUITests`**: tap -> share sheet. **L4 `VehicleDetailUITests`**: the share sheet
  carries the CSV.

Report the observed count per suite **and the simulator**. **A selector matching nothing prints
"0 tests ... passed" and exits 0.** **Never `pgrep -f`** for a build - it matches other agents'
briefs and has killed one; use `pgrep -x xcodebuild`, never `pkill -f`.

## Mutations you must run and report

1. Export **live rows only**, dropping tombstoned ones. The per-type count test must fail.
2. Write **only the home amount**, dropping the original currency. A test must fail - money is a
   pair (hard rule 3).
3. Change one CSV column name. The golden fixture must fail; if it does not, the fixture is not
   pinning bytes.
4. Make the disk-full path throw instead of surfacing its message. A test must fail.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, anchor on the **code line** not a comment, and confirm the build first -
five mutations were misapplied that way this session.

## Screenshots

EN **and** RU, dark: Settings with the export share sheet open, and the car's export row. Name them
`PJ.36-export-share{,-ru}.png` and `PJ.38-car-export{,-ru}.png`, register them in
`scripts/capture-screenshots.sh`, capture **outside** a test run.

**Check the subject is in frame.** Twelve captures have been deleted rather than committed here,
four this week - a spinner where a Cancel belonged, a caption scrolled off, a toggle showing the
opposite of the invariant it illustrated. A share sheet that has not appeared yet is the same trap.

## Report back

Every command with its **real exit code**, observed counts **and the simulator**; all four mutation
results; the CSV columns you chose and where `SCHEMA.md` named them; the files changed; and anything
in this brief that is wrong.

En-dashes only, never em-dashes.
