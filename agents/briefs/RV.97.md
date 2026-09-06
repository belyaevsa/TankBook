# RV.97 - sync push must ask for the upload budget, and its batch must be bounded by BYTES

## The defect, measured, and it is two independent defects

Production, device `787c4f6f`, build `1.0.0+788`, 2026-09-06 20:05-20:22. Every
`POST /v1/sync/push` is **145-151 KB** and ends **499** (client gone) after 31.8 / 31.1 / 13.5 /
31.9 / 4.1 s, while every `GET /v1/sync/pull` in the same minutes returns in **490-750 ms**. The
clustering at ~30 s is the tell and our own constants name it.

**Defect 1 - the budget.** `TransportTimeouts.readJSON = 30`
(`ios/Sources/TankbookCore/Transport/TransportTimeouts.swift:26`) is the idle/read budget for
"ordinary JSON calls (sign-in, **sync**, rates, gateway, catalog, config)". `TransportTimeouts.upload
= 120` exists because "blob PUT and import multipart carry megabytes over a mobile uplink", and the
two long paths ask for it explicitly per request:
`RemoteBlobTransport.swift:42` and `ImportClient.swift:98` both pass
`timeoutInterval: TransportTimeouts.upload`.
**`RemoteSyncTransport.push` does not** - `ios/Sources/TankbookCore/Sync/RemoteSyncTransport.swift:45-49`
builds `TankbookHTTPRequest(url:method:body:)` with no `timeoutInterval`, so
`URLSessionTransport.execute` (`ios/Sources/TankbookCore/Auth/URLSessionTransport.swift:39`) falls
back to the session's 30 s. After an import the push body is megabyte-class too, and it runs out of
read budget mid-flight while **the server does the work anyway** (~31 s of it) and then finds nobody
to answer - that is exactly what `499` means.

**Defect 2 - the batch.** `SyncEngine.batchLimit` is `Int = 200`
(`ios/Sources/TankbookCore/Sync/SyncEngine.swift:96`) and the slice at
`SyncEngine.swift:349` counts **records, never bytes**, so the same oversized batch is rebuilt
identically every cycle.

**The loop is measured, not hypothesised** (the second log, seventeen minutes). The server write is
`INSERT`-or-`UPDATE` keyed on `(account_id, id)` (`backend/src/Tankbook.Api/Sync/SyncRepository.cs:51-65`),
so a retry does **not** duplicate rows - but it **assigns a new SCN every time**, and that closes the
cycle:

1. push 150 KB; the server does ~31 s of real work and commits;
2. the client abandons at its 30 s budget and never learns the outcome, so **the rows stay dirty**;
3. the pull hands the device its OWN just-written rows back, fifty at a time (`SinceScn`
   492 -> 546 -> 596 on a **single-device** account, where nothing else can be writing);
4. still dirty -> the identical 150 KB goes again, forever, on the user's battery and data.

**Fix both halves and say in your report which fixed what.** Raising only the timeout converts a
30 s failure into a 120 s one on the next, larger import; bounding only the batch leaves a slow
uplink failing at 30 s on a legitimate body.

## What to build

**1. The push request asks for the upload budget.**
In `RemoteSyncTransport.push`, set `timeoutInterval: TransportTimeouts.upload` on the request, the
same way `RemoteBlobTransport` and `ImportClient` already do. Do **not** raise `readJSON`: it is the
budget every failing GET is bounded by, and raising it would make a half-connected radio freeze a
button for two minutes. Do **not** add a new global default. `pull` keeps the JSON budget - it is a
query string, and the log shows it returning in under a second.

**2. The batch is bounded by encoded size as well as by count.**
In `SyncEngine.pushAll`, replace the count-only slice with an accumulation that closes a batch when
**either** bound is reached:

- the existing record count (`batchLimit`, 200 - the server's own cap, `SyncService.MaxChangesPerBatch`),
- **or** a new encoded-size cap. **The cap is decided: `maxBatchBytes = 64 * 1024` (64 KB).**
  Reasons to write into the doc and the code comment: the observed livelock body was ~150 KB, so
  64 KB splits the owner's real import into three requests that each finish inside the budget; the
  server's own `/sync/push` body cap is ~52 MB (`docs/API.md` -> Request body caps) and is therefore
  **not** the binding constraint - the mobile uplink is; and it is a client transport constant, so it
  belongs with the other compiled operational numbers, not in remote config
  (`docs/PRACTICES.md` -> constants placement: transport tunables are compiled).

**Measure the size of what actually goes on the wire**, not a proxy. The per-change encoded size is
the `payload` JSON plus the envelope `RemoteSyncTransport.encodePush` writes around it
(`id`, `entityType`, `schemaVersion`, `baseScn`, `clientUpdatedAt`, `deleted`). Compute it from
`change.payload` (a `JSONValue`; `jsonData().count` gives its bytes) plus a fixed per-change
envelope allowance, and state in a comment which allowance you used and why. If you prefer to expose
an encoded-size helper on the change or the transport rather than estimate, that is fine and better -
but the assertion must be about **bytes on the wire**, not about `batchLimit`.

**A single record larger than the cap still ships, alone.** A record that cannot be pushed is a
record lost silently (hard rule 8), and the server accepts a payload up to 256 KB
(`PayloadValidator.MaxPayloadBytes`). So: never emit an empty batch, and never skip a row for being
big - a batch always carries at least one change.

**3. Say what this does to the livelock, in `docs/SYNC.md`.** The protocol section is the authority.
Write the two bounds (records AND bytes), the number and its reason, and that push carries the upload
budget while pull carries the JSON one. If the S1-S8 scenarios need a line about a push whose outcome
the client never learned, add it - do not leave the mechanism recorded only in a commit message.

## Explicitly out of scope

- The car-deletion cluster (`RV.98`, `RV.99`, `RV.100`).
- Any server change. The backend is correct here: it commits the work it was given. Do not touch
  `backend/`.
- Resumable or delta push, a push cursor, or making the client learn the outcome of an abandoned
  request. That is a protocol change and is a different row; this one makes the request fit in its
  budget so the outcome is learned normally.
- Changing `readJSON`, `resource`, or `pullPageLimit`.

## Tests

Read the current `swift test` count yourself before you start and report before -> after; other rows
land in parallel, so any number quoted in a brief is stale.

- **L1 (the budget, assert the REQUEST):** a `RemoteSyncTransport.push` through a recording transport
  carries `timeoutInterval == TransportTimeouts.upload`. `TransportTimeoutsTests.swift` already has
  exactly this shape for blob PUT (`:188`) and import multipart (`:206`) with a
  `RecordingRequestTransport` - add the sync-push sibling there. **Assert the request, never the
  constant.**
- **L1 (the bytes):** a dirty set whose encoded size exceeds the cap splits into **several** push
  requests, **each one under the cap**, and **every record lands exactly once** across them - assert
  both the per-request size and the union of ids. Build the fixture with payloads large enough that
  the SIZE bound binds while the 200-record bound does not, and a second case where the count bound
  binds first, so both are live.
- **L1 (the single oversize record):** one record larger than the cap is still pushed, in a batch of
  one, and is not dropped or deferred forever.
- **L2 if you can reach it:** a push of the owner's import volume against the real endpoint
  completes. If the environment cannot reach a real server, say so plainly rather than faking it -
  that is an honest Residual, not a failure.

Suites: this is `swift test` (TankbookCore) only. **No UI suite and no screenshots** - nothing on
screen changes. If you believe a UI suite is touched, say why rather than running the whole thing.

### Vacuous traps, named

- **Testing with a handful of small records**, where neither bound binds - the test then passes on
  the unfixed code. Every new test must FAIL on `main`'s behaviour.
- **Asserting `batchLimit` changed**, or asserting a new constant's value, rather than the encoded
  SIZE of what goes on the wire.
- **Asserting `TransportTimeouts.upload == 120`.** `TransportTimeoutsTests:118` already does that and
  it is not this defect; the defect is the request that never asks for it.
- **Raising the timeout and calling it fixed.** The next import is bigger.
- Asserting a batch COUNT of requests without asserting each one's size - a count is not a bound.
- A fixture whose payloads are all identical trivial objects: if the fixture omits the state the rule
  is about, it cannot test the rule (the shape behind four passing mutations on 2026-09-06).

### Mutations (run each, report, restore byte-for-byte)

1. Remove `timeoutInterval: TransportTimeouts.upload` from the push request -> the budget test must
   fail.
2. Make the size bound never bind (cap it at `Int.max`, or drop the size check) -> the split test
   must fail.
3. Skip a record that exceeds the cap instead of shipping it alone -> the single-oversize test must
   fail.

**A mutation that PASSES is a finding** - report it as one and grow the test until it fails, rather
than moving on. Four mutations passed on 2026-09-06 and each meant the test did not cover the claim
its row was written for.

## Hard rules that decide things in this area

**1** (local-first: no screen is ever sync-gated; a push that cannot fit must still make progress) ·
**8** (nothing lost silently - which is why an oversize single record ships rather than being
skipped) · **12** (never log a domain value: bytes, counts, record counts and durations are
loggable; a station, an amount or a payload is not - if you add a log line for the split, log the
SHAPE) · **14** (it builds and it lints before anything else counts).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/Tests/**`, and `docs/SYNC.md`.

**Never move, rename or delete a file you did not create.** Another session may work in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The cause is pinned to lines above and is confirmed. Do not spend the run re-deriving it. The
questions that are CLOSED and must not be re-investigated:

- Whether the server duplicates rows on retry - it does not (`SyncRepository.cs:51-65`, INSERT-or-UPDATE).
- Whether the server's body cap is the constraint - it is not (~52 MB).
- Whether `pull` is implicated - it is not; it returns in under a second throughout the log.
- Whether `readJSON` should be raised - decided: no.
- What the byte cap should be - decided: 64 KB.

The one genuinely open question is **how** to measure the encoded size cleanly given that the encoder
lives in `RemoteSyncTransport` and the batching lives in `SyncEngine`. Take the smallest correct
option and keep going; say in the report which you took and what you rejected. Do not stop and wait
on it.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported (before -> after).
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- the localization gate **from the repo root** -> 0.
- No `xcodebuild` run is required: this brief names no UI suite and touches no app-layer file. If you
  end up touching `ios/App/**`, stop and say so - that is outside the write fence.
- **`$?` after a pipe is the pipe's exit code.** Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.

## Report back

1. Exit code of every gate, and observed test counts (before -> after).
2. **Which fix addressed which half** of the defect, in one sentence each.
3. Each mutation: what you broke, which named test failed, that you restored it byte-for-byte. A
   mutation that PASSES is a finding - say so.
4. The per-change envelope allowance you used and how you arrived at it.
5. What the user can now do that they could not before - specifically, what happens on the owner's
   next sync cycle after an import.
6. Anything in this brief that was wrong. A fence can be wrong the same way a diagnosis can: report
   it as a Residual rather than obeying quietly.
7. Whether the tests were actually **run**, not only written.
