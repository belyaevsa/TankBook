# Task PJ.10 + PJ.9 - the import preview asks, and commits what it showed

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 6.** Import is MVP. Today an ambiguous date file **silently imports every row as
M/D** - the stats-poisoning misread `docs/JOURNEYS.md` J2 warns about - and every non-fuel row the
server found is shown to the user and then **dropped at commit**.

**PJ.11** (`TimelineValidator` on every write) is the third row of this Tier-1 entry and is
**out of scope here**: it touches the same import commit path and would collide. It follows.

## Where you may write

```
ios/App/Sources/Import/**
ios/Sources/TankbookCore/Import/**
ios/App/Sources/Localization/L10n.swift
ios/App/Sources/Localizable.xcstrings
ios/Tests/TankbookCoreTests/**
ios/Tests/LocalizationGateTests/**
ios/App/UITests/ImportUITests.swift
docs/JOURNEYS.md · docs/ERRORS.md · docs/LOCALIZATION.md
```

**Do not** touch `ios/App/Sources/Capture/**`, `ConfirmManual/**`, `ServiceEntry/**`,
`TankbookCore/Extraction/**`, `TankbookCore/Config/**`, `TankbookCore/Sync/**`, `backend/`,
`site/`, `deploy/`, `.github/`, `Spike/`, `design/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`** - a concurrent session edits it.

## Write code first, explore second

Verified by the orchestrator immediately before dispatch. **Both halves are client-side only** -
the server already does its part, so you need no backend change.

## PJ.10 - the date-format question

The server **already asks**. `backend/src/Tankbook.Api/Import/MfmParser.cs:159-164` counts
ambiguous dates and emits a `"dateFormat"` question when the count is above zero. The client type
exists too - `ios/Sources/TankbookCore/Import/ImportModels.swift:131`:

> An F6 once-per-file question, returned instead of guessed

**Nothing in `ios/App/Sources/Import` reads it.** So the parser's M/D guess stands, silently, on a
file that may well be D/M. The MFM corpus is real data: `Spike/ImportFixtures/mfm/` has 513 fuel
rows over 13 years with dates that are **genuinely ambiguous** - read its README before assuming.

Build: the preview **asks** `dateFormat` (and surfaces `outOfScope`) when the server reports it;
**confirm is disabled until it is answered**; answering **re-dates the candidates**. Ask **once per
file**, not per row.

## PJ.9 - non-fuel rows commit as what they are

`ImportConversion.swift:105,143` already classifies a `.noFuel` row with `fill: nil`, and the
server already emits `serviceRecord` candidates (`MfmParser.cs:372-394`). The preview shows them.
Then `ImportFlowModel.swift:310` commits only

```swift
!isSkipped(sourceRow: row.sourceRow) && row.fill != nil
```

so **every one of them is silently dropped** - shown, then discarded. That is hard rule 8 (nothing
lost silently) and F6b ("offered as what it is").

Build: `.noFuel` rows get an **"Import as service / expense"** action, and the commit accepts mixed
records with `provenance = .import`, writing a `ServiceRecord` where the candidate is one. The
commit path takes `[FillUp]` only today - widen it.

## Russian

New strings go through the String Catalog, EN **and** RU. `docs/LOCALIZATION.md` is the authority.
Two rules that have each shipped a bug here:

- **If a `%@`/`%lld` receives runtime data, the surrounding phrase must not govern its case.**
  «с вашего %1$@» rendered "с вашего телефон Android".
- **Never compose a sentence by concatenation** - a full localised phrase per language.
- Any **count** you render is a plural: RU needs one/few/many, and the edges are **11 and 21**.
  Note 1 and 21 both take `one`, so a few/many error is invisible at 21 - assert 1, 2, 5, 11, 21.

## Explicitly out of scope

`TimelineValidator` on the import commit or anywhere else (**PJ.11**) · any parser change ·
any backend change · the capture pipeline · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 943 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1 (PJ.10)**: a parse result carrying a `dateFormat` question **blocks confirm** until
  answered, and the answer **flips the candidate dates**. Assert the dates, not just the flag.
- **L1 (PJ.9)**: a `serviceRecord` candidate commits as a `ServiceRecord` with
  `provenance = .import`. **`ImportTests:387` asserts that a commit happened, not what KIND it
  wrote** - that is exactly the hole this row exists to close, so do not lean on it.
- **L4 `ImportUITests`**: a stubbed parse with a `dateFormat` ambiguity shows the question **once**;
  the non-fuel action exists and the Log then shows the service entry. EN **and** RU.

Run only `-only-testing:TankbookUITests/ImportUITests` and **report the observed count**; a
selector matching nothing prints "Executed 0 tests" and reads exactly like success. **Do not run
the full UI suite.** **Never `pgrep -f`** for a build - your brief is part of your command line,
and that killed a sibling agent 48 minutes in. Use `pgrep -x xcodebuild`; never `pkill -f`.

## Mutations you must run and report

1. Let confirm proceed with the question unanswered. The L1 must fail.
2. Answer the question but **do not re-date** the candidates. A test must fail - if none does, the
   test is asserting the flag rather than the dates, which is the whole defect.
3. Commit a `serviceRecord` candidate as a `FillUp` instead. A test must fail.
4. Restore `row.fill != nil` to the commit filter. The PJ.9 test must fail.

A mutation that does not fail is a finding - report it, and say **which suites you ran**: a
mutation can also "pass" because the guarantee lives in a tier you did not run. One that does not
**compile** proves nothing and must be redone. Use a **heredoc** for scripted edits.

## Screenshots

EN **and** RU, dark: the import preview showing the date-format question, and the review list
showing a non-fuel row with its action. Capture **outside** a test run - `simctl` and
`xcodebuild test` fight over the device. Name them `PJ.10-import-date-question{,-ru}.png` and
`PJ.9-import-nonfuel-row{,-ru}.png`, and register them in `scripts/capture-screenshots.sh` so they
are re-capturable.

**Check the feature is actually in frame before you finish.** Four confirm screenshots were
deleted rather than committed in P5.2b because the subject sat below the fold, and two more this
week because they were captured from a seed instead of the real path. A capture that does not show
its feature is evidence for the wrong code. You cannot see them; the orchestrator opens every one.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results; the files
changed; and anything in this brief that is wrong - seven agent pushbacks in this project have been
correct, two of them on my stale file paths.

En-dashes only, never em-dashes.
