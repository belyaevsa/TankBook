# RV.18 – measure how often sync actually fires, before changing anything

Raised by the product owner while reading RV.14. **This is a measurement task first and a fix
second**, and a brief that produced a "fix" without numbers would have failed it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**

## The premise that was already checked, so you do not repeat it

**Sync is NOT timer-driven.** Verified 2026-09-03: there is no `Timer`, no `BGTaskScheduler`, no
periodic loop anywhere in `ios/`. The triggers are exactly:

- launch — `TabRoots.swift` `.task` → `sync.runOpportunisticSync()`
- foreground — `.onChange(of: scenePhase)` where `phase == .active` → the same
- the Settings "Sync now" button → `sync.syncNow()`
- the failure retry backoff → `SyncCoordinator` `.background`
- the Low Power resumer drain

So the ~90-second cadence seen in production was **activity**, not a clock.

## The open question

`scenePhase == .active` fires on **every** return to active, which includes:

- dismissing a system permission alert
- returning from the out-of-process Photos picker
- a Control Centre pull-down
- an app-switcher peek
- a notification banner

None of those is a moment when data changed. That alone could explain several of the six cycles in
seven minutes production showed.

## What to do, in order

1. **Instrument the trigger.** `runSync(trigger:)` already carries `PowerWorkTrigger`; make the
   cycle count observable per trigger (a debug counter, a log line at shape only - **hard rule 12,
   counts and trigger names are loggable, domain values are not**).
2. **Drive a scripted session and report the counts**: launch · save an entry · pick a photo from
   the library · dismiss a permission alert · peek the app switcher · background and foreground.
   Report cycles per trigger for that script.
3. **Only then**, if the numbers justify it, propose and implement a fix. Two candidates:
   a minimum interval between *opportunistic* cycles, or a "something changed" precondition
   (`dirtyCount > 0 || lastPull is stale`).

**If the numbers do not justify a fix, say so and stop.** A measurement that closes the question is a
complete result, and RV.18 exists precisely because nobody had counted.

## The danger, stated plainly

Hard rule 1 means **no screen is ever sync-gated**, so a missed cycle costs freshness and never
function. That makes over-suppression **easy to ship and hard to notice** - nothing breaks, data just
quietly gets staler. Any suppression you add must be defensible from your own numbers, and the user
must still be able to force a cycle from Settings at any moment.

## Explicitly out of scope

- **RV.14, the sync echo loop.** A vehicle is pushed on every cycle because
  `RecordMerge.mergeVehicle` always reports `.fieldMerge` and `SyncEngine.applyPull` marks that dirty
  unconditionally. **That is being fixed separately - do not touch `RecordMerge` or `applyPull`.**
  Note that it inflates whatever you measure: every cycle carries a spurious record.
- The retry backoff schedule and the Low Power deferral - both are deliberate.
- Any backend file.

## Read before writing

1. **`CLAUDE.md`** - hard rules 1 and 12, and rule 14.
2. `docs/SYNC.md` → Low Power Mode and the sync cycle; `docs/LOGGING.md` for what a log line may carry.
3. `ios/App/Sources/Settings/AppSync.swift`, `ios/App/Sources/Navigation/TabRoots.swift`,
   `ios/Sources/TankbookCore/Sync/SyncCoordinator.swift`.

## Tests

- `cd ios && swift test` - **1154 today; must not fall.**
- If you add a suppression rule, it is a **pure decision** and belongs in core with L1 tests, like
  `SyncSurface` - not inline in a view.
- L4 only if behaviour changed: a navigation cycle that used to trigger N cycles now triggers M.

**Vacuous-assertion traps:**
- Asserting a counter increments. That tests the counter.
- Measuring on the simulator and reporting it as production behaviour - the simulator does not
  produce Control Centre or real permission alerts. **Say which triggers you could and could not
  exercise.**

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed.** Match the process NAME (`pgrep -x xcodebuild`); **never
`pgrep -f` or `pkill -f`**.

## No screenshots unless a surface changed

Say none applies rather than fabricating one.

## Report back

- **The counts, per trigger, for the scripted session** - this is the deliverable.
- Which triggers you could not exercise, and why.
- Whether the numbers justify a fix; if you made one, what it is and how a user can still force a
  cycle.
- Exit codes, test counts, suites RUN.
- Files changed, anything unfinished.
