# RV.23 – first launch must say what an account is for (Option A)

The product owner: *"it's not obvious why a user has to or has to at all to sign in."*
**Option A was chosen**: keep Welcome as ONE screen and fix what it says. Do **not** add a screen -
`docs/JOURNEYS.md` J1 records *"⚠ Every extra onboarding screen loses users → one screen,
skippable"*, and PJ.3 built Welcome as exactly that.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**

## Write code first, explore second

The diagnosis is done and the file is small (172 lines). Read it, read the five docs named below,
then write.

## What is wrong today (verified 2026-09-03, do not re-derive)

`ios/App/Sources/Welcome/WelcomeView.swift`:

1. **The screen argues AGAINST an account.** Its third feature row reads
   `"No account needed – your data stays yours"`. That is true and it pre-empts the decision before
   the user knows what it costs them.
2. **The only sign-in door speaks to returning users.** `"Already use Tankbook? Sign in – your
   garage follows you."` is J11 copy (reinstall / Android migrant). A brand-new user is addressed by
   none of it.
3. **It is a 13 pt centred text link** under two full-width buttons - so even a user who wants it
   has to hunt for it.
4. **It is built by string concatenation** - `Text("Already use Tankbook? ") + Text("Sign in").bold()
   + Text(" – your garage follows you.")`. This is the **P1.4 bug**, on the first screen of the app:
   RU currently renders *"Уже пользуетесь Tankbook? **Вход** – гараж поедет за вами."*, where `Вход`
   is a noun standing where a verb belongs. Hard rule 10 - **a full localised phrase per language,
   never concatenation.** Fix this as part of the task.

## What an account actually buys (all four are free - RV.4)

Use these, and no others. Every one is checkable in the code; do not invent benefits or imply cost.

- **Cloud receipt reading.** `/extract` is bearer-only (`GatewayScanStarter.makeTransport` returns
  nil without a session), so **a guest never gets it**. This is the strongest and most concrete:
  on-device Vision resolves **38.3%** of receipts, the cloud model **84/96** (P4.12).
- **Sync across devices** and **restore after loss or reinstall** (`docs/SYNC.md`).
- **Photo backup** - attachment blobs reach the server only with a session.

## What to build

The same one screen, re-argued:

1. **Replace the "No account needed" row** with something honest and two-sided - the app works
   fully offline AND an account adds something. Do not simply delete the local-first promise: it is
   true, it is hard rule 1, and it is a real reason people choose this app.
2. **Say what signing in gives**, in the user's terms, near the decision. Cloud receipt reading is
   the one to lead with, because it changes what the app can do rather than where data lives.
3. **Raise sign-in to a peer door** - a real button beside the other two, not a 13 pt link.
4. **The skip stays a peer.** "Add your car" continues straight through with no account and must not
   read as the lesser choice: no grey small-print, no "continue without an account" beneath a filled
   primary. **A user who never signs in has chosen correctly** (hard rule 1). This is the single
   easiest way to ship this task wrongly.

Copy EN + RU in `ios/App/Sources/Localizable.xcstrings`, full phrases per language.

## THE TRAP - read this twice

Welcome's sign-in currently opens `SignInFlowHost(arrivedViaRestore: true)`. That flag drives
**J11a's honest wrong-provider question**: when the signed-in account is empty, the app asks
*"Nothing is stored under this Apple ID. Last time, did you sign in with Google?"*

That question is correct for a **returning** user and **wrong for a new one** - a new user's account
is empty because it is new, and being asked about a previous sign-in they never made is confusing
and faintly alarming.

So the moment sign-in becomes a general-purpose door, `arrivedViaRestore: true` is no longer safe as
a constant. **Preserve the distinction**, by whatever means you judge best - the returning-user
intent must still reach `SignInFlowHost`, and the wrong-provider question must not fire for someone
who never claimed to be returning. Whatever you choose, **say in your report what signal now carries
the restore intent**. Do not delete the J11a path to make the screen tidier: it exists because v1
ships no account linking, and it is the only thing standing between an Android migrant and an empty
garage that looks like data loss.

## Explicitly out of scope

- **No new screen.** That is Option B and it was not chosen.
- No change to `SignInFlowHost`, the providers, or `AuthService`.
- No change to Import or AddVehicle.
- No paywall or monetization copy - all four benefits are free, and hard rule 7 keeps monetization
  off every surface but the car-limit sheet.
- Do not touch `WelcomeRootView.reevaluate()`'s data-driven finish.

## Read before writing, in this order

1. **`CLAUDE.md`** - hard rules 1 (local-first), 7, 10 (String Catalogs), 15 (peer doors), 14.
2. `docs/JOURNEYS.md` - **J1** (the "one screen, skippable" row) and **J11 / J11a** (the restore path
   and the wrong-provider trap). Your change touches what both promise; move them in the same change.
3. `docs/SCREENMAP.md` - the **Welcome** node and its screen-inventory row (lines ~135, ~141).
4. `docs/DESIGN.md` - palette tokens and the accessibility floor. `PaletteAccentGuardTests` requires
   4.5:1 on every accent fill in both themes; note the existing comment explaining why the primary
   CTA's text is `midnight` and not white.
5. `design/screens/Welcome.dc.html` and `LightWelcome.dc.html` - the artboards. If your change
   departs from them, say so in your report; do not silently diverge.

## Tests

- `cd ios && swift test` - **1154 today; must not fall.**
- `ios/App/UITests/WelcomeUITests.swift` exists - extend it. Name the suites you ran and the
  observed count.
- The checks that matter: all three doors are hittable; **sign-in and the add-car door are of
  comparable prominence** - assert their FRAMES, not merely that both exist; the add-car path still
  reaches AddVehicle with no session; sign-in still reaches `SignInFlowHost`.

**Vacuous-assertion traps, named:**
- Asserting each button `exists`. All three existed before this task; existence proves nothing about
  the thing being fixed.
- Asserting the copy contains the word "sync" or "account". A string check passes against copy that
  is still buried in 13 pt at the bottom.
- Testing only English. The concatenation bug is a **RU** bug - it renders acceptably in EN and
  badly in RU, which is exactly how it shipped.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed**, not by skimming output. Run swiftlint from the repo root.
Zero lint **errors**; `file_length` at 700 is an error, not a warning.

Match the process NAME if you check for a running build (`pgrep -x xcodebuild`). **Never `pgrep -f`
or `pkill -f`** on a build/test pattern - an agent's brief is part of its command line, and on
2026-08-24 exactly that killed another agent 48 minutes into its task.

If a UI run fails with "Failed to load the test bundle … executable couldn't be located", that is
contention, not a red - zero tests executed. Re-run once before reporting a failure.

## Screenshots

`design/screenshots/RV.23-welcome.png` and `-ru.png`, **dark** theme, captured from a booted
simulator **outside any test run**. RU is not a formality here - it is where the fixed copy has to
prove itself, and Russian runs 20-30% longer.

    xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU

Welcome shows only with **no vehicle AND no session**, so reset the app's data before capturing.
**Install the app you just built** - take the newest `DerivedData/Tankbook-*` (`ls -dt`), or you will
shoot a stale build and believe nothing changed.

## Report back

- Exit codes for build, swiftlint, app build, `swift test`, and each UI suite - numbers, not prose.
- Unit-test count before and after; UI test names and observed count per suite.
- Whether each test was actually RUN, and whether you saw the new ones fail before the change.
- **What signal now carries the restore intent**, and how you satisfied yourself the J11a
  wrong-provider question cannot fire for a genuinely new user.
- The final EN and RU copy, verbatim, for every string you added or changed.
- Files changed, doc sections extended, and anything you could not finish, named plainly.
