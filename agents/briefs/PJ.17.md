# Task PJ.17 - the empty-but-alive Confirm

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 13.** `ERRORS.md:82` and F1's Verdict: when a scan resolves nothing, **the failure
state IS the manual form** - not an error screen, not a dead end.

## Where you may write

```
ios/App/Sources/ConfirmManual/**
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
ios/Tests/TankbookCoreTests/**
ios/App/UITests/ConfirmManualUITests.swift
scripts/capture-screenshots.sh
docs/ERRORS.md · docs/SCREENMAP.md · docs/JOURNEYS.md
```

**Do not** touch `Capture/**` (PJ.1 is closed - consume its prefill), `ServiceEntry/**`,
`Import/**`, `Settings/**`, `SignIn/**`, `Welcome/**`, `Home/**`, `Reminders/**`, `Rates/**`,
`Sync/**`, `Config/**`, `backend/`, `site/`, `Spike/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## What to build

An **all-nil prefill that carries a photo**:

1. **Focuses Total on appear** - the one field the user can always read off a receipt.
2. Shows a quiet caption in `inkSoft`: **"Couldn't read this one - type it, the photo stays
   attached."** Quote it exactly; a paraphrased error ships as a paraphrased error.
3. **A caption, never a banner, and never amber.** This is not an error state - hard rule 15 says a
   scan that resolved nothing degrades to the ordinary form, and hard rule 5 reserves amber for
   attention. A user who typed by choice must see **no caption at all**.
4. **Reconcile the P2.3 row and `SCREENMAP.md`'s wording** with what you ship, in the same change -
   the docs are the spec, and a stale sentence in one is more expensive than a bug (`HANDOVER.md`).

**"the photo stays attached" must be true, not just said.** PJ.2 made a scanned save persist its
receipt; this caption promises that for a scan that resolved nothing. Verify the attachment is
written on that path - a promise in copy the code does not keep is worse than no copy.

## Explicitly out of scope

The capture pipeline (PJ.1) · attachment plumbing beyond confirming it holds (PJ.2) · the
cross-check or lock behaviour · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1035 today (verified). MUST rise if you add core logic.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L4 `ConfirmManualUITests`**: an empty prefill **with a photo** focuses Total, shows the caption,
  and is **never amber**; the **typed** path shows **no** caption.
- **L1** (if you put the "should the caption show" decision in core, which is recommended - there is
  no app unit-test target): empty-prefill-with-photo yes, empty-prefill-without-photo and
  typed-path no.

**`ConfirmManualUITests` currently reports 24 with 2 pre-existing failures** -
`testCrossCheckMismatchShowsAmberRefusesLockButSaveAnywayWorks` and
`testReducedMotionLockStillLandsWithoutAnimation`. I verified those **fail at baseline on
`iPhone 17`** by stashing the previous task and re-running, so they are **not yours**. Report the
count and confirm the failures are still exactly those two - if a third appears, it is yours.

**A selector matching nothing prints "0 tests ... passed" and exits 0.** **Never `pgrep -f`** for a
build; use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. Show the caption on the **typed** path too. A test must fail - typing is a peer door, not a
   degraded one (hard rule 15), and a caption there frames it as the failure branch.
2. Render the caption in **amber** instead of `inkSoft`. A test must fail, or the "never amber"
   half is unasserted and this becomes an error state.
3. Do not focus Total on appear. A test must fail.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, anchor on the **code line** not a comment, and confirm `BUILD: 0` before
believing any result - four mutations misapplied that way this session.

## Screenshots

EN **and** RU, dark: the Confirm sheet in the empty-but-alive state, caption visible, Total focused.
Name them `PJ.17-confirm-empty{,-ru}.png`, register them in `scripts/capture-screenshots.sh`,
capture **outside** a test run.

**This sheet is the one with the worst capture history on the project**: four of its screenshots
were deleted in P5.2b because the subject sat below the fold (P6.9), and two more this week for
showing a seeded state rather than the real path. Nine deletions total. **Check the caption is
actually in the frame you commit.**

## Report back

Every command with its **real exit code** and the observed `ConfirmManualUITests` count **and which
tests failed**; all three mutation results; whether the photo is genuinely attached on that path;
which doc wordings you reconciled; the files changed; and anything in this brief that is wrong.

En-dashes only, never em-dashes.
