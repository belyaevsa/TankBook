# PJ.20a – `POST /feedback` is specified and does not exist

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- `backend/src/Tankbook.Api/` (the endpoint, handler, storage, migration)
- `backend/tests/Tankbook.Api.Tests/`
- `docs/API.md` only if the contract text needs correcting (it should not - build to it)

Do **NOT** touch anything under `ios/` - a sibling lane (PJ.7g) owns the iOS seed harness and is
running now. Do **NOT** touch `docs/TASKS.md`.

Write code first, explore second.

## The gap

`docs/API.md` → Feedback gives the whole contract, and the backend has **no Feedback endpoint,
handler or route**:

```
POST /feedback  - public (bearer optional)
{ category: "feature" | "problem" | "other", text,
  appVersion, deviceModel?, replyTo? }        // deviceModel only with the user's toggle
-> 202
```
> Account id attached when a bearer token is present; rate-limited per device/IP; `text` <= 4 KB.
> **No log content, ever.**

**The iOS half already exists** - `FeedbackClient`, `FeedbackModels`, `FeedbackQueue`,
`FeedbackOutbox`, `FeedbackConsentStore`, `FeedbackLogEvents` are all built against this contract
with a stub transport, which is how every client row here is built. So PJ.20's About screen,
P6.10's "send us this case" and the import wizard's "send us the file" currently post to a URL that
does not exist. **Read the client's model types first and build the server to what they send** - if
the client and `API.md` disagree, say so rather than picking one silently.

## What to build

1. `POST /feedback`, public with an **optional** bearer. Account id attached when a token is
   present; absent is not an error - feedback must work for a user with no account.
2. **202**, not 200 - the contract says so, and it means "accepted", which is what an outbox client
   expects.
3. `text` <= 4 KB. An oversize body is refused by **PR.17's existing cap** with `problem+json`
   carrying its `traceId` - reuse `BodySizeLimits`, do not invent a second mechanism.
4. Rate-limited per device/IP through the **existing** `AddTankbookRateLimiting` / `RateLimitOptions`
   (PR.17), not a new limiter.
5. Store the row. `202` with nothing persisted is the vacuous version of this task.

## Hard rules that bound this

- **Rule 12, and it is the sharp one here: NOTHING but shape is logged. Never the feedback text**,
  never `replyTo`, never `deviceModel`. Category, sizes, counts, ids, durations only. Pin it with a
  `RedactionTests` case - that suite sweeps rendered log output, and there is a
  `WithoutMachineFields()` helper for the free-running numeric fields that can spell a needle by
  accident.
- **Rule 9: the server validates structure, never domain meaning.** Envelope, size and shape - the
  server does not interpret what the feedback *says*. This endpoint is not a new exception and must
  not become one.
- `replyTo` is user-supplied contact data. Treat it as the most sensitive field in the row.

## Named vacuous traps

- **Asserting 202 without asserting the row was stored.** Named in the task row itself.
- A redaction test that greps the log for the literal you happened to send. Send text that *would*
  appear if logging leaked - and assert the sweep over rendered output, the way `RedactionTests`
  already does, rather than eyeballing.
- Testing only the bearer-present path. The endpoint is **public**; the no-account path is the one
  that must not 401.
- Re-implementing the body cap or the rate limiter locally so the test passes without exercising
  PR.17's real machinery.

## Checks

- `cd backend && dotnet build` exit 0, `dotnet test` exit 0, `dotnet format --verify-no-changes`
  exit 0 - **all three judged by exit code**. Backend stood at **274 tests**; report the observed
  count and your delta.
- The endpoint's own L2 tests: a valid body returns **202** *and the row exists*; an oversize body
  is refused with `problem+json` carrying its `traceId`; the rate limiter engages; a bearer attaches
  the account id and its absence does not 401.
- **Mutations, two**: (a) make the handler return 202 without storing, and confirm a test fails on
  the missing row; (b) log the feedback `text`, and confirm the redaction sweep fails naming it.
  Restore by copying backups back and verifying `md5` - **never** `git checkout`.
- Postgres for local dev now runs on **port 5434** (changed 2026-08-31); `backend/scripts/dev-up.sh`
  starts it and `appsettings.Development.json` points at it.

## Report back

Whether the client's models and `API.md` agreed; the storage shape and its migration; observed
counts and exit codes for all three backend commands; both mutation results and what they said; the
`md5` matches. Say whether you **ran** the tests or only wrote them. Do not commit.
