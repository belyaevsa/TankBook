# Task PJ.33 - the per-source export guide

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 22.** J2's Export names an "illustrated guide per source app" and F6 promises "here's
where the CSV export lives". With only one importer shipping, **the guide is what tells a switcher
what actually works**.

## Where you may write

```
backend/src/Tankbook.Api/Import/ImportFormats.cs
backend/tests/Tankbook.Api.Tests/**
ios/App/Sources/Import/**
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
ios/Tests/TankbookCoreTests/**
ios/App/UITests/ImportUITests.swift
site/content/**            (the guide page, EN and RU)
scripts/capture-screenshots.sh
docs/API.md · docs/JOURNEYS.md · docs/SITE.md
```

**Do not** touch `Capture/**`, `ConfirmManual/**`, `ServiceEntry/**`, `Settings/**`, `SignIn/**`,
`Welcome/**`, `Home/**`, `Reminders/**`, `Sync/**`, `Config/**`, `Auth/**`, `site/layouts/**`,
`deploy/`, `.github/`, `Spike/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch

The wire already carries the field end to end - `ImportFormatInfo` -> `FormatResponse` ->
`ImportModels.helpUrl`. What is missing is a value and a place to point it:

```
backend/.../Import/ImportFormats.cs:16
new("mfm", "My Fuel Manager", ["csv"], HelpUrl: null, AddedInPackVersion: 1)
```

**And there is no guide page on the site.** `site/content/` holds `_index`, `delete-account`,
`press`, `privacy`, `roadmap`, `support`, `terms` - each with a `.ru.md` twin. Nothing about
exporting.

## What to build

1. **The guide page**, EN **and** RU, following the existing `site/content/` conventions exactly
   (front matter, the `.ru.md` twin, the tone of `support.md`). It tells a My Fuel Manager user
   where that app's CSV export lives and what Tankbook does with it.
2. **`HelpUrl` populated for `mfm`** pointing at that page.
3. **"How to export" rendered** on the format row **and inside the 422 / not-listed messages** -
   the two places a user is stuck and needs it.

**A link that 404s is worse than no link** (hard rule 7: every error names a next step that
*exists*). The page must ship in the same change as the URL that points at it.

**Say only what is true.** `W1`'s site gate forbids `zero typing|just snap|scans any|reads
perfectly`, and three rows are open for copy that over-promises (**PJ.3b**, **PJ.12b**, W6). The
guide describes what the importer does: one format, server-side parse, review before anything is
written.

## Russian

The RU page is a **translation with the same content**, not a stub. `docs/LOCALIZATION.md` is the
authority; W9 records six RU defects found by reading rendered pages, so read yours. Site copy is
the one artefact where an error reaches a customer directly.

## Explicitly out of scope

Other importers (**P5.4b**, deferred - do not imply they exist) · the import wizard's parse or
review · site layout or nav chrome · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build && swift test   ; echo "ios: $?"      # 1052 today. MUST rise if you add core logic.
swiftlint lint                        ; echo "lint: $?"     # from the REPO ROOT, must be 0
cd backend && dotnet build && dotnet test && dotnet format --verify-no-changes ; echo "backend: $?"   # 268 today
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L2**: `/import/formats` carries a non-null `helpUrl` for `mfm`.
- **L4 `ImportUITests`**: the format row shows the link, and the **422** message names it.
- If `site/` has a check script (`scripts/check-site.sh`), run it and report the exit code.

Report the observed count for each suite. **A selector matching nothing prints "0 tests ... passed"
and exits 0.** **Never `pgrep -f`** for a build; use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. Set `HelpUrl` back to `null`. The L2 **and** the L4 must fail - if only one does, the other tier
   is unasserted.
2. Render the link on the row but **not** in the 422 message. A test must fail; that message is
   where a stuck user actually needs it.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, anchor on the **code line** not a comment, and confirm the build before
believing any result - five mutations misapplied that way this session.

## Screenshots

EN **and** RU, dark: the import format row showing "How to export". Name them
`PJ.33-import-guide{,-ru}.png`, register them in `scripts/capture-screenshots.sh`, capture
**outside** a test run.

**Check the link is in frame.** Twelve captures have been deleted rather than committed here,
four of them this week - one showed a spinner where a Cancel belonged, two a caption scrolled off,
two a toggle in the opposite state to the invariant. If the subject needs scrolling, say so rather
than committing the image.

## Report back

Every command with its **real exit code** and observed counts; both mutation results; the URL you
chose and the page you wrote; anything in the RU page you were unsure of; the files changed; and
anything in this brief that is wrong.

En-dashes only, never em-dashes.
