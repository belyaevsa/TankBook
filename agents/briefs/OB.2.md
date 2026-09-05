# OB.2 (was PR.10) – emit the defined events and the async edges

**The device currently says almost nothing about what it did.** Every production bug this week -
RV.58, RV.59, RV.60, RV.65, RV.66 - was diagnosed from SERVER logs, and two needed someone to read
client source and guess. One of those guesses was **wrong and had to be retracted**. This row is the
foundation of the OB cluster: nothing can be exported (OB.4) or persisted (OB.3) that was never
emitted.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**A sibling agent may be working in `backend/`** – ignore it. **Never move, rename or delete a file
you did not create.**

**Use the `iPhone 17` simulator.**

## What to emit

`docs/LOGGING.md` is the authority and already DEFINES these - the gap is that they are not emitted.
**Read it first and implement what it specifies**; where it is silent, say so rather than inventing
a shape.

- **`DataMutationLogger`** around repository create / update / delete / restore, including the merge
  source.
- **Sync cycle**: `SyncCycleBegin` / `SyncCycleEnd`, `SyncMerge`, `SyncQueue`.
- **Network**: `NetRequest` / `NetResponse`. **These two are the highest value in the row** - they
  are what would have shown RV.59's duplicate config fetch and RV.65's doubled 53 KB upload from the
  device side. Include a byte count and the endpoint, never the body.
- **`CapturePipeline(userCorrected:)`** emitted from the confirm commit - true when a pre-filled
  value was edited before saving.
- **`app.lifecycle`** on scene phase.
- **`beginBackgroundTask` + its expiry event** around push and upload.
- **`NWPathMonitor` path-change event** aborting an in-flight blob upload.
- **`sync.clock.skew`** client-side, and the `clamped` count on the server push line.

## The rule that governs every line of this

**Hard rule 12 is the whole risk here, and this row touches more surfaces than any other.** Ids,
counts, codes, durations, byte counts and field NAMES are loggable. **Amounts, stations, notes,
coordinates, payloads, tokens and images are not - at any level, in any build.** A `DataMutationLogger`
sitting on repository writes is one careless interpolation away from logging a fill-up's station and
price, so every event needs its fields chosen deliberately.

**Write the privacy argument for each event in its own doc comment**, not just in `LOGGING.md` -
the next person adding a field to an existing event needs to see the constraint at the call site.

## Read before writing

1. **`CLAUDE.md`** – hard rule 12 above all, plus 1, 14.
2. **`docs/LOGGING.md`** – what each tier logs, the three privacy classes, trace correlation, the
   event table. This row implements it; extend the doc where you add something it does not name.
3. `ios/Sources/TankbookCore/Logging/` (whatever exists today), `ios/App/Sources/AppLog.swift`,
   `ios/Sources/TankbookCore/Sync/SyncEngine.swift`,
   `ios/Sources/TankbookCore/Config/TankbookHTTPClient.swift` (the natural `NetRequest/Response`
   seam - **note RV.65 may be editing `send()` concurrently; if it has landed, build on it**),
   `ios/App/Sources/Capture/CapturePipeline.swift`, the repository write paths.

## Tests

**iOS unit 1378 today; must not fall.** Name the UI suites you run.

- **L1: a real write on a temp DB emits `begin` then exactly one `ok`**; a failing write emits `fail`
  with `rolledBack`.
- **L1: a 500-record merge emits ONE `sync.merge` line**, not 500.
- **L1: confirm emits `userCorrected=true` when a pre-fill was edited, and false when it was not.**
  Both directions - a flag that is always true measures nothing.
- L1: an injected background-task expiry handler emits its event.
- L1: a far-future `clientUpdatedAt` emits `sync.clock.skew`.
- **THE PRIVACY TEST, and it is the one that matters most: a seeded entry with a distinctive station
  name, note and amount produces log output containing NONE of those strings.** Assert against the
  captured log text, over every event this row adds - not per-event, so a future event cannot slip
  through. This is the `AboutUITests` pattern from PR.11's row applied at L1.

**Vacuous-assertion traps, named:**
- Asserting a logger was CALLED. The defect class is what it carries, not that it fired.
- Asserting one event's fields by hand while the privacy test covers only that event - sweep all of
  them.
- Emitting `NetRequest` without a byte count, which is exactly the field RV.65 needed.
- Asserting `userCorrected` in one direction only.

**Mutation-check and report it**: interpolate a station name into one event and confirm the privacy
test goes red. **Restore byte-for-byte** and confirm green - and say plainly that you removed it.

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

None applies – no user-visible surface changes (the export UI is OB.4). Say so rather than
fabricating one.

## Report back

- Exit codes (captured, not piped), unit counts before/after, mutation result.
- **The full list of events you now emit, each with its exact field list** - so the privacy class of
  every field is reviewable in one place.
- **Confirmation that `NetRequest`/`NetResponse` carry a byte count and an endpoint**, and what they
  do NOT carry.
- Whether RV.65 had already landed in `TankbookHTTPClient.send`, and how you composed with it.
- Anything `docs/LOGGING.md` defines that you did NOT emit, and why.
- Anything you noticed that is not OB.2 – named separately.
