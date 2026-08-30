# Task PJ.3b - the first screen promises what the corpus says we cannot do

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

Filed from opening PJ.3's screenshot. **Small, and it is the first sentence a user ever reads.**

## Where you may write

```
design/screens/Welcome.dc.html · design/screens/LightWelcome.dc.html
ios/App/Sources/Welcome/**
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
ios/App/UITests/WelcomeUITests.swift
ios/Tests/LocalizationGateTests/**
scripts/capture-screenshots.sh
docs/DESIGN.md · docs/VISION.md
```

**Do not** touch anything else - `Capture/**`, `ConfirmManual/**`, `Import/**`, `Settings/**`,
`Home/**`, `TankbookCore/**` beyond a gate if you add one, `backend/`, `site/`, `Spike/`,
`project.yml`. **PJ.47 is running and holds `docs/JOURNEYS.md` and `docs/ERRORS.md` - stay out of
both.** **Do not commit. Do not tick `docs/TASKS.md`.**

## The defect, verified

```
design/screens/Welcome.dc.html:31       "Point. Scan. Done."
design/screens/LightWelcome.dc.html:31  "Point. Scan. Done."
ios/App/Sources/Welcome/WelcomeView.swift:63   Text("Point. Scan. Done.")
Localizable.xcstrings  ru -> «Наведи. Сканируй. Готово.»
```

**The artboard is the source, and the app copies it faithfully** - which is why fixing only the
Swift string would leave the next agent to re-introduce it from the artboard. Both `.dc.html` files
and the string must change together.

**Why it is a defect and not a taste question.** Hard rule 15 was written **after** these artboards,
with corpus evidence: receipts extract at **38.3%**, pump displays at **0%**, Vision misreads a digit
at **confidence 1.00**, and a fiscal QR is on only **9 of 16** real receipts carrying 2 of 5 fields.
"Point. Scan. Done." promises the scan finishes the job. It does not, and this sentence is the first
thing a new user reads. `W1`'s site gate already forbids the same family
(`zero typing|just snap|scans any|reads.{0,20}perfectly`), and **W6** removed the identical claim
from `VISION.md` §2 - this is the app-side twin of that fix.

## What to build

1. **A tagline that is true**, in both artboards and the app string, EN and RU. Hard rule 15's own
   words are the target: capture is a **head start, not an answer**, and typing is a **peer path**.
   The live site already has language that passed review - `site/content/_index.md` says *"A head
   start, not an answer"* - so match that register rather than inventing a new claim.
2. **The RU is a fresh translation of the new line**, not a patch of the old one. And fix the
   register while you are there: the current RU tagline is **ты-form** («Наведи. Сканируй.») while
   the bullet directly beneath it is **вы-form** («Сканируйте чеки…»). One screen, two registers.
   The app is вы throughout - match it.
3. **A gate so it cannot come back.** Follow `W1`'s shape: a test that greps the **app strings and
   both artboards** for the over-promise family and fails. Say plainly in the test what a text scan
   cannot see.

**Do not touch any other Russian copy.** The product owner has asked that texts stay as they are
(P6.17, W9); a new string for a changed English line is unavoidable, a general RU edit pass is not.

## Explicitly out of scope

The capture caption's pump promise (**PJ.12b** - same family, its own row) · `VISION.md` §2 (**W6**,
done) · any other screen · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1057 today (verified). MUST rise if you add the gate.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: the over-promise gate - **including the artboards**, which is the half that matters.
- **L4 `WelcomeUITests`**: the screen still shows its three paths and the new tagline; nothing else
  about PJ.3 regresses.

Run only `-only-testing:TankbookUITests/WelcomeUITests` and **report the observed count**.
**A selector matching nothing prints "0 tests ... passed" and exits 0.** **Never `pgrep -f`** for a
build; use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. Put "Point. Scan. Done." back in the **app string** only. The gate must fail.
2. Put it back in **`Welcome.dc.html`** only, leaving the app correct. **The gate must still fail** -
   if it does not, it scans the code and not the source of truth, and the next agent told to match
   the artboard will reintroduce the claim.

A mutation that does not fail is a finding. One that does not **compile** proves nothing. Use a
**heredoc**, anchor on the code line rather than a phrase that also appears in a comment, and
confirm `BUILD: 0` before believing any result - six mutations were misapplied that way this session.

## Screenshots

EN **and** RU, **dark and light** (this screen has a light artboard). Name them
`PJ.3b-welcome{,-ru}{,-light}.png`, register them in `scripts/capture-screenshots.sh`, replacing
PJ.3's if the names collide, and capture **outside** a test run.

**The tagline must be legible in the frame** - it is the entire subject. Twelve captures have been
deleted rather than committed on this project for not showing theirs.

## Report back

Every command with its **real exit code** and the observed `WelcomeUITests` count; both mutation
results; the EN and RU lines you chose and why; whether the gate covers the artboards; the files
changed; and anything in this brief that is wrong.

En-dashes only, never em-dashes.
