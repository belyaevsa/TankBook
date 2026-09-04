# RV.42 – the language restart notice must survive being ignored

The product owner, 2026-09-03: *"after I changed the language in the setting, I wasn't asked /
prompted / notified to re-launch the app to apply the settings."*

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.** Touch no `backend/` file.

**Use the `iPhone 17 Pro Max` simulator for every xcodebuild/xcrun step.** Other work is running in
this checkout on `iPhone 17` and `iPhone 17 Pro`, and `simctl`/`xcodebuild` fight over a device.

**A concurrent agent owns `ios/App/Sources/Inbox/` and `ios/Sources/TankbookCore/Inbox/` (RV.45).**
Do not touch those. See "Shared files" below - it is the part of this brief most likely to cost you.

## The notice EXISTS. It is unmissable in exactly the wrong way

RV.24 shipped `L10n.languageRestartPrompt` - *"Language changes the next time you open Tankbook"* /
*"Язык изменится при следующем открытии Tankbook"*. The bug is not missing copy, it is **where the
copy lives and how long it lives**:

- It renders **only inside the picker sheet** (`LanguagePickerView.swift:99-100`), below the option
  list, as a `.footnote` in `inkSoft` - the quietest text style on the screen.
- It is gated on `@State private var pendingChange` (`:72`, set at `:152`/`:159`), and **`@State`
  dies with the sheet**. Tapping a language moves the checkmark, and the natural next action is
  `Done` in the navigation bar - which dismisses the sheet and destroys the only notice.
- Back in Settings the Language row shows the **new** value with nothing indicating the app is still
  running in the **old** language.

So the user is left with a setting that visibly took effect and an app that visibly did not change,
which reads as a **broken switch** rather than a pending one.

**This is hard rule 7, not a copy tweak**: *"every error names its next step **and survives being
ignored**"*. This notice is defined by not surviving being ignored.

## The constraint that makes a notice necessary - do not trade it away

iOS applies `AppleLanguages` **at launch**, and a programmatic exit to apply a setting reads as a
crash and risks App Store rejection (`docs/ERRORS.md`, RV.24). **Do not add a relaunch button, and
do not call `exit()`.** The answer is a notice that persists, never a relaunch the app performs
itself.

## What to build

**The pending state is DERIVED, never stored.** The app is pending a relaunch exactly while the
stored preference differs from the language actually running:

    LanguagePreferenceStore.storedLanguage  vs  Bundle.main.preferredLocalizations.first

That is a **pure comparison** and belongs in core beside `LanguagePreference.resolve`, with its own
L1 tests - not a flag in a view. It **self-clears on the next launch** with nothing to reset, which
is the property that makes it correct: no bookkeeping can drift out of sync with reality.

Surface it **on the Settings Language row itself** - the row the user just changed, and where they
end up after dismissing the picker.

**Decide explicitly whether the moment of choice also deserves a confirmation** rather than a
caption. The product owner's words were *"asked / prompted / notified"*, and a `.footnote` in
`inkSoft` is none of those. Say what you chose and why.

## Shared files - the coordination that matters today

Three files are touched by the concurrent RV.45 agent as well. **Keep your edits minimal and
additive in each**, so a merge is a merge and not a rewrite:

- **`ios/App/Sources/Localizable.xcstrings`** - the dangerous one. It is a single large JSON
  document, so a wholesale rewrite silently drops the other agent's new keys. **Add only your keys;
  do not reformat, re-sort or re-serialise the file.** If your tooling wants to rewrite the whole
  document, hand-add the entries instead.
- **`docs/ERRORS.md`** - extend the existing RV.24 Settings row; do not restructure the section.
- **`scripts/capture-screenshots.sh`** - append your capture lines; do not reorder existing ones.

## Read before writing

1. **`CLAUDE.md`** - hard rules 7 (survives being ignored), 2 (derived, never stored - the same
   instinct applies here), 10 (whole localised phrases, never concatenation), 13, 14.
2. `docs/ERRORS.md` → the Settings section and RV.24's "Language changed" row.
3. `ios/Sources/TankbookCore/Localization/LanguagePreference.swift` (`resolve`,
   `LanguagePreferenceStore`), `ios/App/Sources/Settings/LanguagePickerView.swift`,
   `ios/App/Sources/Settings/SettingsView.swift` (`languageRow`, `languageValue`),
   `ios/Tests/TankbookCoreTests/LanguagePreferenceTests.swift` (the L1 model to follow).

## Tests

- `cd ios && swift build ; swift test` - **1233 today; must not fall.**
- **L1 for the pending rule** (this is the core of the task):
  - preference set to a language the bundle is **not** currently rendering → **pending**;
  - preference matching the running language → **not** pending;
  - **no preference at all (follow-system) → not pending** - a user who never overrode is not
    waiting for anything.
- **L4, and this single assertion IS the bug**: choose a language, **dismiss the picker**, and
  assert the pending notice is **still visible in Settings**. A test that only checks the notice
  inside the sheet passes against today's code and proves nothing.
  Assert the notice's **text**, not that some element exists.

**Vacuous-assertion traps, named:**
- Asserting the prompt exists while the picker is still open. That is the current, broken behaviour.
- Asserting the Language row's value changed - it always did; that is not the bug.
- A pending-state test that never exercises the follow-system case, which must NOT be pending.

**Mutation-check and report it**: scope the pending state back to the picker's `@State` and confirm
the L4 "still visible after dismiss" assertion goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe** - `cmd | tail -2 ; echo $?` reports
`tail`'s status, not the command's. Redirect to a file instead. Run swiftlint from the **repo
root**; from `ios/` its root-relative `excluded:` paths report thousands of phantom violations.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern - an agent's brief is part of its command line, and that pattern killed a sibling agent on
2026-08-24. Sibling agents ARE running today, so this matters.

**Never move, rename or delete a file you did not create.** On 2026-09-04 an agent moved another
session's uncommitted migration out of the repo to get a clean baseline; it was recovered, but it
was 56 KB of someone's unsaved work. If something in the tree breaks your gate and is not yours,
**report it and carry on** - do not tidy it away.

## Screenshots

`design/screenshots/RV.42-settings-pending.png` and `-ru.png`, dark, **outside** any test run,
capture lines appended to `scripts/capture-screenshots.sh`: **Settings showing the pending notice
after the picker was dismissed** - that is the whole point, so a shot of the picker itself does not
demonstrate the fix.

RU runs longer and this sits on a row that already carries a value and a chevron - that is where it
overflows. You have no image input; say so plainly. The orchestrator opens every screenshot
personally.

## Report back

- Exit codes (captured, not piped), test counts before/after, suites RUN, the mutation result.
- **Whether you added a confirmation at the moment of choice**, or kept a caption, and why.
- Quote the pending-state rule and confirm it self-clears on next launch with nothing to reset.
- Confirmation you added no relaunch button and no `exit()` call.
- Confirmation your `Localizable.xcstrings` edit was additive and did not re-serialise the file.
- Files changed, docs extended, anything unfinished.
