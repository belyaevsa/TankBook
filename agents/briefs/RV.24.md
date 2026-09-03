# RV.24 – make the Language row work

The product owner: *"Language switch doesn't work in Settings. Default language must be taken from
the system at first launch. If a user changed it in Settings, Settings is a priority."*

**Option B was chosen (2026-09-03): an in-app picker, and a restart prompt is acceptable.**

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**

## Do not touch `docs/TASKS.md`

The orchestrator marks the row after verifying. Editing it from an agent silently un-ticks other
tasks when the conflict is resolved by side (`HANDOVER.md`).

## What is there today (verified — do not re-derive)

`SettingsView.preferencesCard` renders:

```swift
valueRow("Language", value: "English", identifier: "settingsLanguageRow")
```

`valueRow`'s own doc comment says *"A static value row (its destination screen is another task)"*.
It is **not broken — it was never built**, and Appearance and Notifications are the same placeholder.
There is **no `AppleLanguages` write, no stored preference, and no language plumbing anywhere** in
`ios/`; `L10n.localize` reads `Bundle.main.localizedString`, so the app simply follows the system.

## What to build

A real picker on that row, writing the choice so it applies on the next launch.

- The offered list comes from **`Bundle.main.localizations`** (today `en`, `ru`), never a hardcoded
  pair — a third language must need no code change here.
- The row shows the **current** language, not the literal `"English"`.
- Choosing a language writes `AppleLanguages` into `UserDefaults` and shows the prompt below.
- Offer a way back to "follow the system" — a user who overrode by accident must be able to undo it,
  and that is a distinct state from "the system language happens to be English".

### Four things this decision pulls in — all four are requirements

**(a) The prompt is an error-class surface (hard rule 7): it must name its next step.**
"Language changes the next time you open Tankbook", not a bare "restart required". EN + RU, full
phrases per language.

**(b) Never call `exit(0)` or any programmatic restart.** An app that kills itself to apply a
setting is an App Store rejection risk and reads to the user as a crash. They reopen it.

**(c) Do NOT half-apply the change to the running session.** Routing `L10n.localize` (153 call
sites) at a new bundle while the 268 `Text(LocalizedStringKey)` sites keep the old one would leave
the app **in two languages at once** — visibly worse than one clean restart. All-or-nothing.

**(d) Write nothing at first launch.** *No stored preference* is the representation of "follow the
system", so a user who later changes their phone's language sees the app follow. Storing the system
value at first launch would silently freeze the app against the phone. The product owner's wording
was "default from the system setting of the first launch"; this reading satisfies it and keeps the
app in step. **If you conclude it must literally freeze at first launch, say so in your report
rather than implementing it** — it is a product decision, not yours or mine.

## Explicitly out of scope

- The Appearance and Notifications rows. They are the same placeholder and they are **not** this
  task; do not "while I'm here" them.
- Re-localising any existing string, or touching `Localizable.xcstrings` beyond the few keys this
  screen needs.
- Any change to `L10n`'s bundle resolution — see (c).
- Any backend file.

## Read before writing

1. **`CLAUDE.md`** — hard rules 7 (every error names its next step), 10 (String Catalogs, EN + RU),
   13 (the app suggests, the user decides — a language the user chose is theirs permanently), 14.
2. `docs/LOCALIZATION.md` — how strings reach the screen, and the `Text(String)` trap that has
   produced four live bugs. Your new copy must not add a fifth.
3. `docs/ERRORS.md` → **Settings**. The restart prompt is a row there, in the same
   Condition / Shows / Next step shape as its neighbours.
4. `docs/SCREENMAP.md` — Settings' destinations; the row gains one.
5. `ios/App/Sources/Settings/SettingsView.swift`, `ios/App/Sources/Localization/L10n.swift`.

## Tests

- `cd ios && swift test` — **1154 today; must not fall.**
- **L1 in core** for the decision itself — *no stored preference → follow the system; a stored one
  wins* — with its own tests. It is a pure rule and does not belong inline in a view.
- L4: the row is **hittable** (it is inert today, so an existence check passes against the bug), it
  opens the picker, the picker lists the app's real localizations, and choosing one shows the
  prompt.

**Vacuous-assertion traps, named:**
- `app.buttons["settingsLanguageRow"].exists` — the row exists today and does nothing. Assert
  **hittable**, and assert the picker appears.
- Asserting the value label reads "English". It is hardcoded to that string right now, so the
  assertion passes against the defect.
- A test that only checks `UserDefaults` was written. That tests `UserDefaults`. Assert the row's
  displayed value changes, and that the L1 rule resolves as specified.
- Testing only EN. The whole feature is about the other language.

**Mutation-check** the L1 rule and report whether you saw it go red.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed**, not by skimming. Zero lint **errors**; `file_length` at 700
is an error and `SettingsView.swift` is already large — split at a real seam if you approach it.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern — an agent's brief is part of its command line.

"Failed to load the test bundle … executable couldn't be located" is contention, not a red — zero
tests executed. Re-run once.

## Screenshots

`design/screenshots/RV.24-language.png` and `-ru.png` (the picker), plus the restart prompt in both
languages — dark theme, outside any test run. RU is where the prompt copy overflows.

Install the app you just built — newest `DerivedData/Tankbook-*` by `ls -dt`.

## Report back

- Exit codes for build, swiftlint, app build, `swift test`, each UI suite — numbers, not prose.
- Test counts before/after; suites RUN; whether the L1 mutation went red.
- The final EN and RU copy for the prompt and the row, verbatim.
- Confirmation that nothing is written to `UserDefaults` at first launch, and how you proved it.
- Files changed, doc sections extended, anything unfinished — named plainly.
