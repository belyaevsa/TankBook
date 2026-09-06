# RV.83 - the Garage attention strip is a tap target that does not look like one

## The defect, measured in both the code and the artboard

[RV.79] made the per-car "N needs attention" strip navigate to the merged reminders list. The pixels
never got the message.

- **The code**: `attentionLink` (`ios/App/Sources/Garage/GarageView.swift:185-203`) is a
  `NavigationLink(value: Route.remindersAll)` whose row is `bell + text + Spacer(minLength: 0)` -
  **no chevron**, full-width `contentShape(Rectangle())`.
- **The car row directly above it**: `vehicleDetailLink` (`:139-175`) is the same kind of
  `NavigationLink` and **ends in `chevron`** (`:168`). Two doors on one card, one marked and one not.
- **The artboard**: `design/screens/GarageReminderCounts.dc.html:46-49` draws the strip as a
  **statement** - bell, amber text, no chevron, no button affordance.
- **The screenshot** shows it: `design/screenshots/RV.79-garage-counts.png`.

A full-width target with no affordance is either an invisible feature or an accidental tap, depending
on the user.

## The decision is MADE - implement (b), the doorway

**It is a doorway: keep the navigation and give it the affordance the rest of the app uses for one -
the chevron the car row itself carries** (`:168`, `chevron`). Reasons, so you do not re-open it:

- Removing the tap would delete a shipped feature ([RV.79] chose the destination deliberately: the
  merged list is "what needs doing", and a create action there would compete with the count for
  meaning - the comment at `:179-184` says so).
- The count is genuinely a door - it is the one place in the Garage that answers "what needs doing on
  this car".
- The app already has exactly one affordance for "this row leads somewhere", and it is on the same
  card, 30pt above.

**Update `design/screens/GarageReminderCounts.dc.html` in the same change** so the mock stops
disagreeing with the build. That is half the point of the row - a change to only one side leaves the
same defect pointing the other way. Match the chevron the car row draws in the artboard (read how the
car row's chevron is drawn there and reuse it - do not invent a second chevron glyph).

**The accessibility label must keep naming the car and the count** (`attentionAccessibilityLabel`,
`:206-208`, from [RV.79], hard rule 5 - the count is never colour alone). Do not let a chevron become
part of the spoken label.

## Explicitly out of scope

- Changing where the strip navigates to.
- Changing the car row, the archived row, or the count's arithmetic (`RemindersAllRows` /
  `ReminderListGroups.attentionCount` - [RV.79] owns that and it is correct).
- Adding a create action to the strip.
- Re-seeding the canvas. Edit the `.dc.html` artboard; the canvas re-seed is the orchestrator's.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L4 `GarageUITests`**: tapping the strip reaches the **merged reminders list** (the behaviour is
  now marked, so assert it still holds), and the strip remains its **own** accessibility element
  whose label names **the car and the count**.
- If any pure formatting piece changes, L1 it. If nothing pure changes, say so rather than inventing
  a seam.
- Suites: `GarageUITests`. Report the observed count - a filter matching nothing prints "0 tests ...
  passed".

### Vacuous traps, named

- **Asserting the strip exists.** It does, and it did before the row.
- **Changing the artboard without changing the code, or the reverse** - the point of the row is that
  they agree. Report both diffs.
- Asserting the chevron's SF Symbol name in a test - that is testing the implementation, not the
  affordance. The visual claim is the screenshot's job.
- Asserting navigation without asserting the accessibility label survived.

### Mutations (run each, report, restore byte-for-byte)

1. Remove the strip's `NavigationLink` destination -> the navigation test must fail.
2. Fold the strip's accessibility element into the card's -> the label test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Screenshots - the visual IS the row

EN **and** RU, **dark**, into `design/screenshots/`, as `RV.83-garage-attention.png` and `-ru.png`,
showing a car card **with** the attention strip and its new affordance.
- Compare the shot against `design/screens/GarageReminderCounts.dc.html` **after** you have updated
  the artboard - they must now agree.
- Capture **outside** a test run; `-homeResetDatabase` alongside any seed.
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
  RU matters here: "1 needs attention" -> "1 требует внимания" is much longer, and the strip now has
  a chevron competing for the same width. Check it does not truncate.
- **Verify the pair differs with `md5 -q`** and report both hashes.
- **You cannot see your own screenshots.** The orchestrator opens every one.

## Docs to reconcile

`docs/DESIGN.md` if this establishes the rule explicitly (a tappable row carries the chevron), and
the artboard itself. `docs/SCREENMAP.md` already records the destination - check it does and fix it
if not.

## Hard rules that decide things in this area

**5** (amber is attention, and the count is never colour alone - the words and the label carry it) ·
**6** (numbers in DIN, units subordinate - the count is a number in a UI string; follow what
`ReminderAttentionFormat` already does) · **7** (an affordance that does not look like one is a next
step the user cannot find) · **10** (EN + RU) · **14** (it builds and it lints).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`,
`backend/src/**`, `backend/tests/**`, `Spike/ImportFixtures/**`, `design/screens/**`,
`design/screenshots/**`, and the docs named in this brief. **If your row's "out of scope" says not to
touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above and is confirmed - do not spend the run re-deriving it. Where this brief leaves a
genuinely open choice, **take the smallest correct option and keep going**, then say in the report
which you took and what you rejected. Do not stop and wait on it. (`RV.74`'s first dispatch ran two
hours and wrote nothing, stuck on a question its brief left open.)

If a fence in this brief turns out to be wrong, **report it as a Residual rather than obeying
quietly** - a fence can be wrong the same way a diagnosis can. Two of my diagnoses have been wrong
this month and the agent was right both times.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported (before -> after). Never subset it.
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- `swift run --package-path ios localization-gate` from the root -> 0.
- **If you touched `backend/`**: `cd backend && dotnet build` -> 0 and `dotnet test` -> 0 (count
  before -> after), plus `dotnet format --verify-no-changes` -> 0.
- **If you touched `ios/App/`**: `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  `swift build` does NOT compile `ios/App`; only `xcodebuild` does. Run `xcodegen generate` first if
  you added a file. **Check the observed count is non-zero.** Do NOT run the whole UI suite - that
  belongs to phase completion (2026-08-29 rule).
- **`$?` after a pipe is the pipe's exit code.** `dotnet test | tail` once reported 0 while the run
  aborted and "66 passed" of ~396 nearly read as green. Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.
- **Simulator contention produces false reds** with a *different* failing set each run, and a suite
  reporting "Executed 0 tests" beside its failures is kills, not assertions. Shut the simulators down
  and re-run once on a quiet machine before believing a red.

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. Each mutation: what you broke, which named test failed, and that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on. Four passed on 2026-09-06
   and each meant the test did not cover the claim its row was written for.
3. Screenshot paths and md5s, if this brief asked for screenshots.
4. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
5. Anything in this brief that was wrong, as a Residual.
6. Whether the tests were actually **run**, not only written.
