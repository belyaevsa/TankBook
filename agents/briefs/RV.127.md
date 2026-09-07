# RV.127 - the feedback outbox promises a retry that nothing triggers

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The defect, pinned

`ios/Sources/TankbookCore/Feedback/FeedbackOutbox.swift:53` declares:

```swift
public func flush() async { ... }
```

Its comment says it runs "when connectivity returns or on a later foreground". **It has zero call
sites in the entire repository** - measured 2026-09-07 across app, core, tools and every test
target. So a feedback send that fails is queued, the UI tells the user it is queued, and nothing
ever sends it. Hard rule 7 requires an error to name its next step and to **survive being ignored**;
this one names a next step that never arrives.

## The seam already exists - I found it, do not go looking for another

`TabRoots.runAutomaticPass()` (`ios/App/Sources/Navigation/TabRoots.swift:513`) **is** the
established launch-and-foreground pass. Its callers are the `.task` fallback and the
`scenePhase == .active` transition (`:332` and `:337-353`), with `didRunAutomaticPass` preventing a
double run at launch. It already drains three queues in exactly this shape:

```swift
await sync.runOpportunisticSync()   // P6.8
await AppRates.refresh()            // PJ.8 - rate pack + S8 backfill
await inbox.drainOutbox()           // RV.44 - the delivery outbox
```

**`inbox.drainOutbox()` is the precedent to copy**, and its own comment states the contract you
want: *"best-effort: a guest has no outbox and a failure just retries next launch."* The feedback
outbox is the same shape - a queue drained on foreground, best-effort, retried next time.

**So the answer to "where should it be called" is: one more line in `runAutomaticPass`, beside
`drainOutbox()`.** Do not add a second `scenePhase` observer, do not add an `NWPathMonitor`
subscription, and do not introduce a new lifecycle owner. `AppPathMonitor` exists
(`ios/App/Sources/Network/AppPathMonitor.swift`) but is a **logging** monitor - it is not a
connectivity-returned event bus, and turning it into one is a bigger change than this row needs.
A foreground pass is the trigger; "when connectivity returns" becomes "the next foreground", and
the comment must be corrected to say so.

## Design questions ALREADY CLOSED

1. **Retry is kept, not deleted.** The UI already promises it and the queue already persists;
   deleting is the larger user-facing change and needs its own product decision.
2. **The trigger is `runAutomaticPass`**, per above.
3. **It is best-effort and never blocks.** A failure leaves the item queued for the next pass. It
   must not throw, must not surface an error, and must not gate anything else in the pass -
   `drainOutbox()`'s placement last in the pass is deliberate; put the flush beside it.
4. **Correct the comment in the same change** (`CLAUDE.md` -> comments carry current truth). The
   current wording promises a connectivity trigger that will not exist.

## What to build

- One call in `runAutomaticPass`, wired the way `drainOutbox()` is.
- Whatever plumbing the app needs to reach the outbox instance from there - **reuse the existing
  ownership pattern**, do not construct a second `FeedbackOutbox`. A second instance over the same
  persisted queue is the bug this row would otherwise create.
- **Idempotency**: a flush that races the user's own retry tap must not double-post. Check what the
  outbox already guarantees and say what you found; add the guard only if it is missing.

## Explicitly out of scope

- Changing the feedback API, the endpoint, or `POST /feedback`'s contract.
- Reworking `AppPathMonitor` into a connectivity event source.
- [RV.129]'s other detached declarations, and [RV.130]'s mechanical sweep.
- Any new user-facing string. If you think one is needed, stop and say so.

## Docs to read before writing

1. `CLAUDE.md` - hard rules 1, 7, 12, and the code-comment rule.
2. `docs/API.md` -> `POST /feedback`.
3. `docs/ERRORS.md` -> the feedback surface and its next step (**the authority for what the user
   was promised**).
4. `docs/LOGGING.md` - the flush logs shape only: counts and outcomes, never a feedback body
   (hard rule 12).

## Checks

Baseline: **iOS 1631 tests / 181 suites** (one pre-existing failure, `RV.125`'s confident-wrong
total in the Vision-gated `RV.56` suite - **not yours**), `swift build` 0, `swiftlint` 0 errors
**from the repo ROOT**, localization gate 0 (771 keys, 100% RU).

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0.
3. `cd ios && swift test` - full, never subsetted, **>= 1631**; the only permitted failure is the
   `RV.56` one named above. Report the number.
4. `xcodegen generate` + the UI suites you touched **by name**; report a non-zero observed count.
5. Localization gate - 0; the key count should be **unchanged at 771**.
6. Release build - required if you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L1**: an item queued and persisted is sent on the next pass **starting from a cold state** -
  construct the outbox from persisted data rather than from an in-memory leftover, because "it is
  still in the array from earlier in the test" proves nothing about a real launch.
- **L1**: no connectivity leaves the item **queued**, not dropped.
- **L1/L2**: the send is idempotent - a flush racing a manual retry does not double-post.
- **The trigger is what is missing, so test the trigger.** A test that calls `flush()` directly
  asserts the half that already worked. Prove the pass invokes it.

### Vacuous traps, named

- **Calling `flush()` once at launch and calling that a lifecycle.**
- **Testing `flush()` directly** rather than the trigger - that is the entire defect.
- Leaving the comment's connectivity promise in place after wiring a foreground trigger.
- Constructing a second `FeedbackOutbox` so the flush drains a different queue than the one the UI
  filled - this passes a naive test and fixes nothing.
- Logging a feedback body (hard rule 12).

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**, what
the outbox already guarantees about idempotency, and how you reached the outbox instance from
`runAutomaticPass`. Name any closed decision you think is wrong and stop there rather than absorbing
it.
