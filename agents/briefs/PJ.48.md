# PJ.48 [v1.1] – add a receipt to an entry that was typed

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Expected:

- `ios/App/Sources/EditEntry/` (the receipt card gains the affordance)
- `ios/App/Sources/ConfirmManual/` (the quiet "Attach receipt" row on the typed path)
- `ios/Sources/TankbookCore/` for the **rule** – see "Where the logic goes"
- `ios/App/UITests/EditEntryUITests.swift`, `ios/App/UITests/ConfirmManualUITests.swift`
- `ios/Tests/` for the L1 tests
- `ios/App/Sources/Localizable.xcstrings` – you own it this run. It is **not line-mergeable**: add
  keys, never restructure.

Do **NOT** touch `docs/TASKS.md` (the orchestrator ticks it at merge). Do **NOT** touch
`ios/App/Sources/ConfirmManual/ManualFillUpFuelCard.swift` or
`ios/Sources/TankbookCore/Domain/Enums.swift`'s fuel-kind rules – that is P2.3c's freshly landed
work; leave it exactly as it is.

Write code first, explore second.

## Use this simulator

`iPhone 17` – `-destination 'platform=iOS Simulator,name=iPhone 17'`. **Never** `pgrep -f` /
`pkill -f` for a build (a brief is part of the process command line; that pattern once killed a
sibling agent 48 minutes in). Use `pgrep -x xcodebuild`.

## Everything this builds on already exists – do not redesign it

Verified by the orchestrator before dispatch:

- **PJ.1** (capture pipeline) and **PJ.2** (keep the photo) are done and merged.
- `EditEntryRows.receiptCard(attachments:entry:pendingBlobIDs:)` already renders the receipt strip,
  **including the empty state** (a `doc.text` placeholder when `attachments.first` is nil). That
  empty state is where "Add receipt" belongs.
- `Attachment` (`Entities.swift:495`) carries `kind`, `file: LocalFileRef`, `ocrText`,
  `extractedTimestamp` and the inline `thumbnailBase64` that makes list chips cost zero blob
  fetches.
- The photo write the scan path uses is app-side (`VehiclePhotoStore` / `InvoiceAttachmentFiles`,
  referenced from `ScannedSavePlan.swift:13`). **Find the exact seam PJ.2 uses and reuse it** – do
  not write a second photo-writing path.

**My file references have been wrong four times in this project** (a 5-file list that was 11, a
16-field count that was 18, two files that did not exist). Verify each one before relying on it,
and say in your report where I was wrong.

## The rule this task exists for

The typed door currently produces a **lesser entry** – it cannot carry the receipt. Hard rule 15
says typing and scanning are peers, so a typed entry must be able to hold the paper too.

The whole difficulty is what happens **after** the photo is attached, and `docs/ERRORS.md:125-126`
(already written – this is the authority, quote it, do not paraphrase) plus `JOURNEYS.md:105` fix it:

1. **OCR may offer pre-fills for BLANK fields only.** A typed value is **never** overwritten. Each
   suggestion is **dimmed until tapped** – hard rule 13: a suggestion is a default input, never a
   fact.
2. **No cross-check amber is raised against a typed value.** `ERRORS.md:126`: *"Typed values win
   silently; only blank fields are offered a pre-fill... The photo is kept either way."* An OCR
   reading that disagrees with what the user typed produces **no amber, no dialog** – nothing.
3. **A failed photo write leaves the entry completely unchanged**, with the `warn` line from
   `ERRORS.md:125`, quoted verbatim: `"Couldn't save the photo – the entry is unchanged."` with
   next steps *Try again · free up space*.
4. `provenance` stays `.manual`. `extraction` records the attach.

## Where the logic goes

**The blank-fields-only merge is a pure function in `TankbookCore`**, unit-tested at L1; the views
only call it. This repo has a scar exactly here: `AppTabBar`'s arithmetic lived in the app target,
which package tests cannot import, so a defect survived two whole phases "verified by looking at one
device". A function taking (typed entry, OCR result) and returning (suggestions for blank fields
only) is trivially testable, and it is the guarantee the whole row is about.

## Explicitly out of scope

- Changing the scan path's own behaviour, or PJ.1's pipeline.
- Any new cross-check, and any change to the existing amber on the scanned path.
- Multiple attachments per entry, re-running OCR on demand, or removing an attachment.
- `docs/TASKS.md`.

## Named vacuous traps for this task

- **A test that attaches to an entry with blank fields only.** The load-bearing case is a
  **fully typed** entry meeting an OCR result that disagrees: assert every typed field is
  **byte-identical** afterwards and that **no amber exists**. A test that never creates a
  disagreement cannot see the defect.
- Asserting a suggestion "exists" without asserting it is **dimmed and not applied** until tapped.
  A pre-fill that silently lands in the field is the hard-rule-13 violation this row prevents.
- Testing the failed-write path by asserting the write threw, rather than asserting **the entry is
  unchanged** and the warn line renders with its next step.
- Adding "Add receipt" where an attachment already exists (`ERRORS.md`/the row: it shows **only**
  when there is none).

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** – also run
  `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination
  'platform=iOS Simulator,name=iPhone 17' build` and report `BUILD SUCCEEDED`.
  Keep every file under **700 lines** – `file_length` is a SwiftLint **error** here, and hard rule
  14 says fix the code, never loosen the rule.
- `swift test --package-path ios` – whole suite, never subsetted. It stood at **1084**; report the
  observed count and your delta.
- `xcodebuild ... -only-testing:TankbookUITests/EditEntryUITests
  -only-testing:TankbookUITests/ConfirmManualUITests test` – whole suites. Report the **observed
  count**; a filter matching nothing prints "0 tests ... passed" and exits **0**. Then run
  `scripts/check-ui-test-count.sh` against your log – a suite can print "passed" while some of its
  tests never ran, which happened here on 2026-08-30.
- **Screenshots, EN + RU, dark**, to `design/screenshots/`: the Edit-entry receipt card with "Add
  receipt" (`PJ.48-edit-add-receipt{,-ru}.png`) and the attached state showing a dimmed suggestion
  on a blank field (`PJ.48-edit-suggestion{,-ru}.png`). `-homeResetDatabase` alongside the seed;
  never drive the simulator while `xcodebuild test` runs. The orchestrator opens these personally –
  RU runs 20-30% longer and short labels overflow worst.
- **Mutation-check the load-bearing rule**: let the OCR result overwrite a **typed** field, and
  confirm a test fails naming that field. Then restore, by copying back a backup you made first and
  verifying with `md5` – **never** `git checkout`.

## Report back

Observed counts and exit codes for every command (including the `xcodebuild build`); where my file
references were wrong; the pure function's signature and where it lives; whether the mutation
produced a failure and what it said; the `md5` match after restore; the screenshot filenames; any
string keys you added. Say whether you **ran** the tests or only wrote them. Do not commit.
