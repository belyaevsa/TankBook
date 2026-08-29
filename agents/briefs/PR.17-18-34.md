# Task PR.17 + PR.18 + PR.34 - close the holes before the backend is public

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 3** (`docs/TASKS.md` -> "Blockers"). These three **must land before SH.1 puts the
backend on the public internet**: today `POST /import/parse` needs no auth and has no rate limit or
body cap, and a presigned PUT accepts **any bytes of any size**. That is fill-the-blob-store-at-line-
rate, from anywhere, for free.

**A concurrent agent is working the iOS lane right now.** Backend and iOS are the two tracks that
cannot collide - keep it that way.

## Where you may write

```
backend/src/Tankbook.Api/**
backend/tests/Tankbook.Api.Tests/**
docs/API.md
docs/SECURITY.md
```

**Do not touch `ios/` at all** - not one file. **Do not** touch `site/`, `deploy/`, `.github/`,
`Spike/`, `design/`, `project.yml`. **Do not commit. Do not tick `docs/TASKS.md`.**

## Write code first, explore second

Every claim below was verified in the source by the orchestrator before this brief was written.
The greps are reproduced so you do not re-derive them. Start editing.

## What NOT to explore

- **Do not redesign the blob pipeline, the sync protocol or the auth model.** They are built,
  tested and signed off (`docs/SYNC.md`, `docs/API.md`).
- **Do not add domain validation anywhere.** Hard rule 9: the server validates envelope, size and
  registered schema, never meaning. A size cap is structure; a "this looks like a weird fill-up"
  check is a rule violation.
- **Do not implement the iOS half of PR.17** ("client caps a push batch by bytes",
  `SyncEngine` splitting). Another agent holds that lane. Server-side only.

## The three defects, verified

```
$ grep -rn "RateLimiter\|AddRateLimiter" backend/src | wc -l
0                                    # PR.17: no rate limiting of any kind exists
$ grep -rn "MaxRequestBodySize\|Limits\." backend/src
(nothing)                            # PR.17: no explicit body cap; the Kestrel default 30 MB is
                                     # BELOW a maximal legal push batch (200 x 256 KB + envelope)
```

**PR.18** - `S3BlobStorage.CreateUploadUrl` (`Blobs/S3BlobStorage.cs:49`) builds a
`GetPreSignedUrlRequest` with `BucketName`, `Key`, `Verb` and `Expires` and **nothing else**: no
content type, no length. `SweepOrphansAsync` (`Blobs/BlobService.cs:190`) and
`DeleteStalePendingAsync` (`Blobs/BlobRepository.cs:292`) both exist and are **never scheduled** -
`Program.cs` registers only `MigrationHostedService`, `ImportPurgeHostedService`,
`AccountPurgeHostedService` and `RatesHostedService`.

**PR.34 is PARTLY BUILT, and the row does not say so.** `Program.cs:247-260` already has both
checks - for the `change-me` hash salt and for an unset JWT signing key - but each only calls
`app.Logger.LogWarning(...)`. **A warning is not a refusal**: the server starts anyway, in
Production, hashing account ids with a salt printed in this repo. Convert them to a refusal;
the detection is already written.

**One thing changed under you today, and the row predates it.** `appsettings.json` used to carry
`"Config:SigningKey": ""`. It now carries the **same non-empty dev placeholder** as
`appsettings.Development.json`:

```
IpsG7l75fgQtx1iYnwLA7ekrhHbkB8dy3sMjbo4OUKM=
```

so development is unblocked. That means **"empty signing key" is no longer the dangerous state -
"the committed placeholder" is.** A production server booting with that key signs config documents
with a keypair anyone who reads this repo can reproduce, and forge. Your guard must refuse on the
**placeholder value**, not merely on empty. Both remain refusals; add the placeholder case.

## What to build

### PR.17 - rate limits and body caps

- ASP.NET `RateLimiter` **per IP** on `/auth/session`, `/auth/refresh`, `/import/parse`,
  `/catalog/publish`; **per device** (`X-Device-Id`) on `/extract`, `/sync/push`, `/blobs/begin`.
- **`Retry-After` on every 429**, including the existing quota 429s, which carry none today. A 429
  without it is an error with no next step (hard rule 7), and the client already decodes and
  displays that header.
- Explicit **`MaxRequestBodySize` per endpoint**, written into `docs/API.md`: push =
  200 x 256 KB + envelope, extract 6 MB, import 8 MB, everything else 64 KB. An oversize body must
  be a **413 `problem+json` carrying its `traceId`**, never a bare connection reset.
- Pick limits that a real user cannot hit and say in a comment why each is what it is.

### PR.18 - bind the presign, schedule the sweep

- `CreateUploadUrl` binds the **declared content type and length** from the `begin` request, so the
  URL cannot be used to upload something else. Mirror it in `RecordingBlobStorage` or the test
  double proves nothing.
- Schedule `SweepOrphansAsync` + `DeleteStalePendingAsync` **hourly across all accounts**. Copy the
  shape of `ImportPurgeHostedService` / `AccountPurgeHostedService`, including how they are kept
  **out of test hosts** - registering a timer in every integration test is its own bug.

### PR.34 - refuse, do not warn

Outside Development, **fail startup** on: the `change-me` hash salt (or empty), the committed
placeholder config signing key (or empty), and an unset `Auth:JwtSigningKeyBase64`. The message
must name the setting and how to supply it (hard rule 7 applies to operators too).

## Tests

```
cd backend && dotnet build                     ; echo "build: $?"
cd backend && dotnet test                      ; echo "test: $?"    # 253 today, MUST rise
cd backend && dotnet format --verify-no-changes ; echo "format: $?"
```

Integration tests need Postgres + MinIO: `bash backend/scripts/dev-up.sh` (plain `docker run`,
**never docker-compose**). **Do not run `swift build`, `swift test`, `xcodebuild` or `swiftlint`** -
you changed no iOS file, and the iOS agent needs the machine.

Required cases (`docs/TESTING.md` vocabulary):

- L2: N+1 requests inside the window -> **429 with `Retry-After`**; a body one byte over the cap ->
  **413 problem+json with a traceId**; a **maximal legal push batch -> 200** (the cap must not
  break a legitimate client).
- L2: the recorded upload URL carries constraints equal to the `begin` body.
- L2: a pending row and an unreferenced blob older than `OrphanGraceDays` both vanish in one pass,
  and a **referenced** blob survives; the sweep is **not** registered in a test host.
- L2: a host built with Production environment and the default salt **throws at startup**; same for
  the placeholder signing key.

## Mutations you must run and report

Break it, confirm the named test fails, restore **byte-for-byte**.

1. Raise one endpoint's rate limit far above the test's N. The 429 test must fail.
2. Drop `Retry-After` from the 429 response. A test must fail - if none does, the header is
   asserted nowhere and that is a finding.
3. Remove the content-type binding from the presign. The PR.18 test must fail.
4. Make the sweep skip rows **older** than the cutoff instead of newer (an inverted comparison, not
   a deletion - the subtle form). A test must fail.
5. Turn one PR.34 refusal back into a `LogWarning`. A test must fail. **This is the mutation that
   matters most**: warning-instead-of-refusing was the shipping state, and nothing failed.

A mutation that does not fail is a finding, not a pass. A mutation that does not **compile** proves
nothing and must be redone. Use a **heredoc** for scripted edits, never an inline `python3 -c` with
a glob-able path in it.

## Report back

Every command with its **real exit code** and the observed test count before and after; all five
mutation results; the limits you chose and why; the exact files changed; and anything in this brief
you found to be **wrong**. Agents have refused a bad brief and been right five times in this
project - saying so is worth more than working around it.

En-dashes only, never em-dashes.
