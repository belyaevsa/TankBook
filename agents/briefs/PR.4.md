# Task PR.4 - persist SyncPayloadMemory

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 18.** Small, and it is a **hard rule 13 bug**: a stale device can revert a user's edit.

## Where you may write

```
ios/Sources/TankbookCore/Sync/**
ios/Sources/TankbookCore/Persistence/**
ios/App/Sources/Settings/AppSync.swift
ios/Tests/TankbookCoreTests/**
docs/SCHEMA.md · docs/SYNC.md
```

**Do not** touch `Capture/**`, `ConfirmManual/**`, `Extraction/**`, `Config/**`, `Transport/**`,
`Logging/**`, `Auth/**`, `backend/`, `site/`, `Spike/`, `design/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## The defect, verified immediately before dispatch

```swift
// ios/App/Sources/Settings/AppSync.swift:35
payloadMemory: InMemorySyncPayloadMemory(),
```

The seam is two methods (`ios/Sources/TankbookCore/Sync/SyncTransport.swift:23`):

```swift
public protocol SyncPayloadMemory: Sendable {
    func lastSyncedPayload(for id: UUID) -> JSONValue?
    func recordSynced(id: UUID, payload: JSONValue)
}
```

**Why the in-memory double is a bug and not a shortcut.** S9's field-level merge decides *which
fields this device actually changed* by diffing against the last payload it synced. In memory, that
knowledge dies with the process - so after every relaunch the first sync claims **every field
changed**. A device that has been closed since yesterday then overwrites a field another device
edited in between. `docs/SYNC.md` S9 exists to prevent exactly that, and
`docs/PRACTICES.md` §7 A1 records it: "field-level Vehicle merge degrades to *every field changed*
after each relaunch".

The existing S9 test passes because it never relaunches - it holds one engine for the whole test.

## What to build

Persist the memory - a column or side table keyed by record id, whichever fits `docs/SCHEMA.md`
better; argue your choice in the report. **The migration is additive**: `docs/PRACTICES.md` A5 calls
device migrations "the scariest code in the app - they run once, on the user's data, with no
retry", so add, never rewrite, and leave existing rows valid.

Wire it in `AppSync.swift:35`. `InMemorySyncPayloadMemory` stays for tests.

## Explicitly out of scope

Retry/backoff (**PR.7** - a separate agent may run it right after you, so stay out of
`SyncCoordinator`'s scheduling) · migration backup safety (**PR.15**, deferred until a v1.1
migration exists) · anything in the transports · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 979 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1, the one that matters**: a **fresh `SyncEngine` over the same repository** between two syncs
  still merges only the changed field (S9). Build the second engine anew - if your test reuses the
  first, it cannot see this bug, which is exactly why the current S9 test passes.
- **L1**: migrate-from-existing leaves prior rows readable and syncable.

Name any UI suite you touch and **report its observed count**; a selector matching nothing prints
"0 tests ... passed" and exits 0. **Never `pgrep -f`** for a build - use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. Put `InMemorySyncPayloadMemory` back in `AppSync`. Your new test must fail. **This is the whole
   task** - if it still passes, the test is not crossing a process boundary.
2. Have `recordSynced` write nothing. The same test must fail.
3. Return a stale payload for the wrong record id. A test must fail, or the keying is unasserted.

A mutation that does not fail is a finding. One that does not **compile** proves nothing. Use a
**heredoc** for scripted edits.

## Report back

Every command with its **real exit code** and observed counts; all three mutation results **with the
suites you ran**; where you stored the payload and why; the files changed; and anything in this
brief that is wrong - nine agent pushbacks here have been correct.

En-dashes only, never em-dashes.

## Re-dispatch note (2026-08-29)

A first run of this brief completed correctly and the orchestrator then **destroyed it** with a
`git checkout` of the whole source directory while restoring a mutation - orchestrator error, not
yours. Nothing about the task changed.

**One finding from that run to settle this time.** Neutering `recordSynced` so it writes nothing
left all three new tests **green**. Either the tests do not pin the write path, or that experiment
was broken. Run that mutation yourself, report the result, and if the tests do not fail, fix them -
a persisted memory nobody asserts is written is the same class of gap as the in-memory double.
