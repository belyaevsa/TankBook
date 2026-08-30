# Task PJ.20 - About & feedback, with consent that means something

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 21.** `ERRORS.md` About & feedback; P6.10 and the import wizard both route "send us
this case" to a screen that cannot send anything.

## Where you may write

```
ios/App/Sources/Settings/**            (AboutView and the feedback row)
ios/App/Sources/Import/ImportWizardView.swift   (the "send us the file" consent line only)
ios/Sources/TankbookCore/Feedback/**   (new)
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
ios/Tests/TankbookCoreTests/**
ios/App/UITests/AboutUITests.swift (new) · ImportUITests.swift
scripts/capture-screenshots.sh
docs/ERRORS.md · docs/LOGGING.md · docs/SECURITY.md
```

**Do not** touch `Capture/**`, `ConfirmManual/**`, `ServiceEntry/**`, `Welcome/**`, `Home/**`,
`Reminders/**`, `Rates/**`, `Sync/**`, `Config/**`, `Auth/**`, `backend/`, `site/`, `Spike/`,
`project.yml`. **Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch

`POST /feedback` is specified in `docs/API.md:201-205` and **the server does not implement it** -
there is no Feedback endpoint, handler or route. Build the client **against the documented
contract**, exactly as every other client row here is built against a stub transport. The missing
server half is filed separately as PJ.20a and is **not yours**.

```
{ category: "feature" | "problem" | "other", text,
  appVersion, deviceModel?, replyTo? }        // deviceModel only with the user's toggle
-> 202
```

## What to build

1. **A send-feedback row on About** that posts to `POST /feedback`, with **queued-offline** and
   **429** states. Every state names its next step (hard rule 7) and survives being ignored.
2. **The once-asked opt-in**: "help improve scanning - attach this case". **Default OFF, persisted,
   and changeable afterwards** (hard rule 13 - a value the user set is theirs).
3. **The import "send us the file" attaches the actual file** with an explicit consent line. Today
   `ImportWizardView.swift:305` shares a *sentence* through `ActivityView` and no file.
4. **Nothing but shape is logged** - hard rule 12. Format name, counts, error codes, durations,
   field *names*. Never the feedback text, never a station, amount, note or coordinate, never the
   file's contents.

**The consent is the load-bearing part.** A case or a file is queued **only** with consent, and the
default is off. `deviceModel` rides only with the toggle, per the contract above.

## Explicitly out of scope

The server endpoint (**PJ.20a**) · the diagnostics bundle (**PR.11**, deferred to v1.0.x - this row
shares its future `AboutUITests` suite, nothing more) · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1042 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: consent **defaults off** and **persists** across a fresh instance - build the second one
  anew, or the test cannot see a persistence bug (that is exactly how PR.4's first attempt passed
  while writing nothing).
- **L1**: a case or file is queued **only** with consent - assert the queue is empty without it.
- **L1 payload sweep**: a fully populated feedback payload through the log path leaks **no** domain
  value. Use `WithoutMachineFields()` if you sweep rendered output: `timestamp` renders `SS.mmm` so
  `...:42.317Z` contains `"42.3"`, and a 9.87 s duration renders `9876.5432` - free-running numbers
  that spell a needle, which fires about **one run in 600**. Fix the sweep, never the needle.
- **L4 new `AboutUITests`**: the feedback row, and the offline copy.
- **L4 `ImportUITests`**: the share sheet lists the **file name**.

Report the observed count for each suite. **A selector matching nothing prints "0 tests ... passed"
and exits 0.** **Never `pgrep -f`** for a build; use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. Default the consent to **on**. A test must fail.
2. Queue the case **without** consent. A test must fail - this is the one that matters; if it
   passes, consent is decorative.
3. Put the feedback **text** into a log line. The payload sweep must fail.
4. Drop persistence so consent resets each launch. A test must fail, **or your test is not building
   a fresh instance**.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, anchor on the **code line** not a comment, and confirm `BUILD: 0` first -
four mutations misapplied that way this session.

## Screenshots

EN **and** RU, dark: About with the feedback row, and the import share step showing the file name.
Name them `PJ.20-about{,-ru}.png` and `PJ.20-import-sendfile{,-ru}.png`, register them in
`scripts/capture-screenshots.sh`, capture **outside** a test run.

**Check the subject is in frame.** Eleven captures have been deleted rather than committed on this
project, three of them this week - one showed a spinner where a Cancel should be, two showed a
focused field with the caption scrolled off. If your feature needs scrolling to see, say so instead
of committing the image.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results **with the
suites you ran**; how consent is persisted and what happens on a fresh install; the files changed;
and anything in this brief that is wrong.

En-dashes only, never em-dashes.
