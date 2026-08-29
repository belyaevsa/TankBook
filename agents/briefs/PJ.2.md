# Task PJ.2 - a scanned save keeps the photo

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 1**, the half PJ.1 did not deliver (PJ.1 landed in `520ea0c`). An image now becomes
a prefill - and then **the photo is thrown away at save**. That breaks cross-journey principle 3
("photos are never discarded"), J1's payoff, J3's "keep the photo", F1's "photo attached", and the
mixed-receipt promise that the fuel row and its accepted expenses share **one** receipt image.

## Where you may write

```
ios/App/Sources/ConfirmManual/**
ios/App/Sources/Persistence/**
ios/App/Sources/EditEntry/**
ios/Sources/TankbookCore/Domain/**        (only if a type genuinely lacks a field - argue it)
ios/Tests/TankbookCoreTests/**
ios/App/UITests/EditEntryUITests.swift
docs/JOURNEYS.md · docs/SCHEMA.md
```

**Do not** touch `ios/App/Sources/Capture/**` (PJ.1 is done - consume its `ConfirmPrefill`, do not
rework it), `ServiceEntry/**`, `Import/**`, `Settings/**`, `SignIn/**`,
`TankbookCore/Config/**`, `TankbookCore/Sync/**`, `TankbookCore/Auth/**`, `backend/`, `site/`,
`Spike/`, `design/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## The defect, verified immediately before dispatch

```swift
// ios/App/Sources/ConfirmManual/ManualFillUpView.swift:565,571
money: money, note: nil, attachments: [], provenance: .manual,
...
crossCheck: derived.crossCheck, extraction: nil)
```

Hardcoded on **every** save, including one that arrived through the scan door with
`prefill.sourceImage` in hand. `ConfirmPrefill` already carries `sourceImage`, `crops`, `ocrLines`
and `qrAnchor`; `prefill` is reachable at the save site (`ManualFillUpView.swift:213`).

## What already exists - do not rebuild it

| Piece | Where |
|---|---|
| Attachment entity | `TankbookCore.Attachment` (`Entities.swift:495`) |
| Extraction record | `ExtractionMeta { fields: [FieldRef: FieldExtraction], pipeline }`; `FieldExtraction { cropRect, confidence, userCorrected }` |
| Provenance cases | `.receiptScan`, `.pumpPhoto`, `.fiscalQR`, `.screenshot`, `.manual`, `.import(source:)` |
| Where attachment bytes go | `VehiclePhotoStore.attachmentsDirectory()`, used by `InvoiceAttachmentFiles` - **follow that pattern** |

## What to build

1. **One `Attachment` per save, shared.** A scanned save writes the receipt once and references it
   from the `FillUp` **and from each accepted mixed-receipt `Expense`** - the same id, not a copy
   per row. It is one photograph of one receipt.
2. **`provenance` reflects how it arrived**: `.receiptScan` / `.pumpPhoto` / `.fiscalQR` as
   appropriate, never `.manual` when a prefill was applied.
3. **`extraction: ExtractionMeta`** when a prefill was applied, carrying each resolved field's crop
   rect and confidence, and **`userCorrected` set for a field the user changed** from what the scan
   proposed. That flag is not decoration: `docs/EXTRACTION.md` uses "pre-fill overwritten by the
   user" as its accuracy feed, and nothing produces it today.
4. **A typed save writes no attachment and stays `.manual`.** Typing is a peer path, not a lesser
   one (hard rule 15) - it must not acquire an empty attachment or a scan provenance.

**File protection**: attachments live under `completeUntilFirstUserAuthentication` (hard rule 11,
`docs/SECURITY.md`). PR.16 is the row that sets it explicitly everywhere - **do not** implement
that here, but do not write the receipt somewhere PR.16 would not find it. Use the existing
directory.

## Explicitly out of scope

Reworking the capture pipeline (**PJ.1**, done) · blob upload or sync of the attachment (P4.6,
built) · explicit file-protection attributes (**PR.16**) · the gateway (**P6.3**) · new UI beyond
what is needed to render an existing receipt card · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 957 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: a save with a prefill writes **one** `Attachment`, referenced by the `FillUp` **and by
  each accepted Expense** - assert the **same id**, not merely that each has one.
- **L1**: `provenance != .manual` and `extraction != nil` on a scanned save.
- **L1**: `userCorrected` is true for a field the user edited and false for one left as proposed.
- **L1**: a save with **no** prefill writes **no** attachment and stays `.manual`.
- **L4 `EditEntryUITests`**: the receipt card renders after a seeded scanned save.

Run only `-only-testing:TankbookUITests/EditEntryUITests` and **report the observed count**; a
selector matching nothing prints "Executed 0 tests" and reads exactly like success - that caught the
orchestrator today. **Do not run the full UI suite.**

**A guarantee in `ios/App/Sources` pins only at L4** - there is no app unit-test target, so say
which suites you ran with each mutation result.

**Never `pgrep -f`** for a build - your brief is part of your command line, and that killed a
sibling agent 48 minutes in. Use `pgrep -x xcodebuild`; never `pkill -f`.

## Mutations you must run and report

1. Write a **separate** `Attachment` per accepted Expense. The shared-id test must fail - if it
   passes, it asserts "each has one" rather than "they share one".
2. Keep `provenance = .manual` on a scanned save. A test must fail.
3. Write an attachment even when there is no prefill. The typed-path test must fail.
4. Never set `userCorrected`. A test must fail, or that field is unasserted and the accuracy feed
   is decoration.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc** for scripted edits.

## Screenshots

EN **and** RU, dark: the Edit-entry screen of a **scanned** fill-up showing its receipt card.
Capture **outside** a test run, name them `PJ.2-edit-entry-receipt{,-ru}.png`, and register them in
`scripts/capture-screenshots.sh`.

**Check the feature is in frame.** Six captures have been deleted rather than committed on this
project for showing a screen without their subject - four below the fold, two taken from a seed
instead of the real path. You cannot see them; the orchestrator opens every one.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results **with the
suites you ran**; the files changed; and anything in this brief that is wrong - eight agent
pushbacks here have been correct, several on stale details in these rows.

En-dashes only, never em-dashes.
