# RV.66 – with more than one car, the app says sync has a problem and then shows nothing

Reported by the product owner 2026-09-05: *"the state shows a problem with sync. User click and sees
nothing. Because the currently selected car has no sync problem, the problem appears only if a user
switched the current car."*

**REPRODUCE FIRST. This is a requirement, not a preference.** The scope mismatch below is verified in
code; **which control produces the dead end is NOT**, and a fix aimed at the wrong control will look
right and change nothing.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.**

**Use the `iPhone 17` simulator.**

## What is verified

**The indicators are ACCOUNT-WIDE.** `AppSync.flaggedCount` comes from
`repository.flaggedEntryCount()`, whose SQL has **no vehicle predicate**
(`Repository+FlaggedEntries.swift:12-17`). It drives both:

- the chip's warn dot (`SyncStateChip.swift:203-216`), and
- Settings' "N entries need a look" row (`SettingsView.swift:503`).

**The evidence a user can act on is CAR-SCOPED.** The conflict badge renders per entry in Home's Log
(`HomeSections.swift:472-481`, `entry.isConflicted`), and Home lists only the selected vehicle's
entries.

**So a conflict on car B leaves car A's Home looking clean while the account-wide dot insists
something is wrong.**

**`FlaggedEntriesView` is NOT the bug.** It iterates `liveVehicles()` and IS account-wide
(`FlaggedEntriesView.swift:90-95`), so the destination behind the warn dot would show the entry.

## What is NOT verified - establish it before changing anything

Two candidate paths produce "sees nothing", and **your reproduction must say which**:

**(a)** The user tapped the CHIP BODY. It is a `NavigationLink` to Settings whose `scrollTarget` is
nil for this state (`SyncStateChip.swift:193-199`), so they land on Settings with no scroll and
nothing highlighted.

**(b)** The user saw the indicator and looked at Home, which is car-scoped and clean.

Also worth knowing: the warn dot that DOES lead to the account-wide list is a **10 pt circle** with
a 24 pt hit area riding the chip's corner - easy to miss and easy to mis-tap.

**Set up two cars with the conflict on the NON-selected one, walk it, and report what you saw.**

## What to build

**The account-wide signal must lead to the account-wide list.** Options to weigh - choose, and say
why you rejected the others:

- make the chip BODY route to `flaggedEntries` when a flagged count exists (today only the 10 pt dot
  does);
- name the car on each row of `FlaggedEntriesView`, so the user learns WHERE the problem is;
- show the count per car in the switcher, so switching is an informed act rather than a hunt.

**Two fences:**

- **Do NOT make Home show other cars' entries.** That breaks the Log's whole contract.
- **Do NOT remove the account-wide signal.** Hiding the problem until the right car is selected is
  worse than a dead end - hard rule 8, nothing lost silently.

**Check the same mismatch for the INBOX badge** (`pendingInboxEntryIDs`, `HomeSections.swift:483`),
which looks car-scoped in the same way. Report whether it has the same defect; fix it only if it
does, and say so either way.

## Read before writing

1. **`CLAUDE.md`** – hard rule 8 (**conflicts surface as badges where the data lives, never modals
   at sync time**; nothing lost silently), rule 7, rule 10, rule 14.
2. `docs/SYNC.md` → S1-S8 and the conflict surfaces; `docs/ERRORS.md` → the flagged rows;
   `docs/SCREENMAP.md` → the chip's destinations.
3. `ios/App/Sources/Navigation/SyncStateChip.swift` (all of it - `scrollTarget`, `flaggedDot`),
   `ios/App/Sources/Settings/AppSync.swift` (`flaggedCount`),
   `ios/Sources/TankbookCore/Persistence/Repository+FlaggedEntries.swift`,
   `ios/App/Sources/Settings/FlaggedEntriesView.swift`, `ios/App/Sources/Home/HomeSections.swift`.

## Tests

**iOS unit 1426 today; must not fall.** UI suites: `SyncChipUITests`, `HomeUITests`, and whichever
drives flagged entries.

- **The headline L4, with TWO cars and the conflict on the NON-selected one: the indicator is
  visible AND following it reaches the conflicted entry WITHOUT the user switching cars first.**
  The assertion is **arriving at the entry**, not that a screen opened.
- **L1: `flaggedEntryCount` is account-wide while Home's rows are the selected vehicle's.** Pin the
  asymmetry deliberately, so a later change cannot silently make the count car-scoped and "fix" the
  symptom by hiding it.
- L4: with the conflict on the SELECTED car, today's behaviour is unchanged.

**Vacuous-assertion traps, named:**
- **Testing with one car.** The bug cannot appear - this is the trap that matters most here.
- Asserting the dot renders. It already renders; that is the complaint.
- Asserting Settings opened, rather than that the conflicted entry was reached.

**Mutation-check and report it**: revert your routing change and confirm the two-car test goes red.
Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"   # from repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
**Never `pgrep -f`/`pkill -f`.**

## Screenshots

**Required, EN and RU, dark, WITH TWO CARS and the conflict on the non-selected one** - a
single-car screenshot proves nothing. Save as `design/screenshots/RV.66-*.png` / `-ru.png`,
captured OUTSIDE a test run.
**Verify each EN/RU pair differs (`md5 -q a.png b.png`) before reporting them**: RV.58 shipped an
"RU" screenshot byte-identical to its EN one because the `-AppleLanguages "(ru)"` launch did not
take, and the agent could not tell. A `-` prefixed launch argument can PERSIST across relaunches;
reinstall between shots if a state flag sticks. `scripts/capture-screenshots.sh` is outside your
write area - name the capture lines in your report instead. You have no image input: say so.

## Report back

- Exit codes (captured, not piped), unit counts before/after, UI suites run, mutation result.
- **What your reproduction actually showed** - which control produced the dead end, (a), (b), or
  something else. If you could not reproduce it, say so plainly and say what you changed anyway.
- **Which routing option you chose**, and why you rejected the others.
- **A verdict on the inbox badge** - same mismatch or not.
- Confirmation Home still shows only the selected car's entries, and the account-wide signal
  survives.
- Anything you noticed that is not RV.66 - named separately.
