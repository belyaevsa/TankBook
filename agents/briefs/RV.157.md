# RV.157 - a local write schedules a sync

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.**

## The defect

`docs/SYNC.md:151` says the cycle is *"triggered on app foreground, **after every local write
(debounced)**, and by push notification nudge."* **The write-triggered half was never built.**
`runOpportunisticSync()` has exactly one caller (`TabRoots.swift:518`, the foreground pass) and
`syncNow()` is the Settings button. Backgrounding does nothing - `case .inactive, .background:`
(`TabRoots.swift:355`) only resets a flag.

Nothing is lost: a save writes `.dirty` and pushes on the next foreground. It is a **latency**
defect - an edit sits until the app is backgrounded and reopened, and a second device is stale for
exactly that long. Production evidence, 2026-09-09: `sync.queue dirtyCount=1
oldestDirtyAgeSeconds=54` with no cycle coming.

`SYNC.md` has been burned by this exact class before and says so a few lines below - it corrects
*"the same fiction the 'launch, foreground and timer cycles' phrasing once hid"* and pins
wired-vs-policy-only rules with a source-scan guard. **Line 151 sits outside that guard.**

## The decision, made 2026-09-09 by the product owner - implement, do not re-open

**Implement the debounced write trigger.** Battery was offered as the argument against and explicitly
waived (*"we don't care about a battery... the case has a minor affect"*). A third option - syncing on
backgrounding instead - was offered and **not** taken.

**The rule the owner stated, and it governs the implementation:**

> **save locally first, send to the cloud asynchronously**

So the save **writes and returns**. The cycle is **scheduled, never awaited**, and can never fail or
delay the save. That is hard rule 1 at the call site and it is the acceptance this row is judged on.

## What to build

- **A debounced scheduler that a local write pokes.** A burst must coalesce into **one** cycle: an
  import commit writes hundreds of rows and a push batch is ~90, so "one cycle per write" is
  pathological. Choose the window and say why.
- **Pick the seam and justify it.** The repository is core and must not know about sync. The app
  already has a change signal - `toastCenter.noteEntryChanged()` is called from the write paths
  (`HomeView.swift:316,334,353`, `FlaggedEntriesView.swift:225,264`) - so either that, or a signal
  the repository posts that the app observes, or the save call sites. **Whichever you choose, it must
  cover every local write, not just the ones you happened to find** - a trigger that covers three
  screens out of six is the same fiction in a new form. Say how you established the coverage.
- **Reuse `syncNow`/`runSync`, never a second door** (hard rule 1). Respect Low Power Mode exactly as
  the foreground pass does: `SYNC.md:490` puts opportunistic cycles in the *defers* column and **the
  save itself in *never defers*** - the save stays immediate and local whatever the sync does.
- **Extend the source-scan guard** so a trigger named in `SYNC.md` with no call site fails a test.
  That guard is the only reason the previous fiction stayed dead, and this row exists because line
  151 was outside it. **This is not optional** - without it the doc can drift again tomorrow.
- A guest (signed out) has nothing to sync: the trigger must be a cheap no-op, not a cycle that
  starts and finds nothing.

## Explicitly out of scope

- Push notification nudges (the third trigger `SYNC.md:151` names) - `NOTIFICATIONS.md` puts them at
  v1.x. **Do not implement them, and do not delete that clause either** - report what you find.
- [RV.154] (backend push cost) and [RV.155] (the pull cursor). **Another agent is on RV.154 right
  now**; do not touch `backend/`.

## Docs to read before writing (in order)

1. `docs/SYNC.md` - the trigger sentence at :151, the Low Power table at :490, and the wired-vs-policy
   section that follows. **Reconcile the doc with what you build, in the same change.**
2. `CLAUDE.md` hard rule 1.

## Tests you must add

- **L3**: one local write schedules exactly **one** cycle, and N writes inside the window still
  schedule **one**. Assert the cycle count.
- **L3**: the trigger defers under Low Power Mode and drains through `LowPowerResumer` when it ends.
- **L1**: the save **never awaits** the scheduled work and never fails because of it - assert the
  save completes with the transport unavailable/erroring.
- **L1**: the source-scan guard fails when `SYNC.md` names a trigger with no call site. **Prove its
  teeth**: it must fail if you delete your own trigger.
- **L1**: a signed-out write schedules no cycle.

## Vacuous traps, named

- Making the save await the push - that is the local-first design inverted, and the owner's rule
  forbids it in words.
- A trigger on some write paths and not others.
- Asserting a sync happened rather than that exactly **one** happened for a burst.
- Implementing it as a repeating timer - `SYNC.md` already retired that fiction by name.
- Wiring the trigger and leaving line 151 unverified by any test.

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1800 tests / 207
suites, all green**, **811** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then any UI suite you touch by name with an observed, non-zero count.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; which seam you chose and **how you established it covers every local write**; the
debounce window and why; the source-scan guard's failing-then-passing output; and anything you found
and did not fix.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change - or mutate one line to
prove the test's teeth. **Do not** `git stash`, `git checkout`, or move files out of the tree: an
agent did that on 2026-09-08 and a bad `mv` loop destroyed three of its own new files. **Another
agent is working in this checkout right now on the BACKEND** - expect files you did not touch to
change under you, never move or revert them, and report anything odd rather than acting on it.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**
