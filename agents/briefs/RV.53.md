# RV.53 – a storage outage destroys a recognition the user already paid for

Asked for by the product owner as *"a queue, so unavailable LLM or storage does not lose data"*.
Checking it found a **live critical-path defect**, which is the first thing to fix. Read the whole
brief before starting: **the two outages are different problems and must not get the same fix.**

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` — **`backend/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `ios/` file.

**A sibling agent may be working in `backend/src/Tankbook.Api/Rates/` (RV.50).** Stay out of
`Rates/`. If a `Rates` test is red and you did not touch it, **report it and carry on**.

**Never move, rename or delete a file you did not create.** There is a git worktree at
`.claude/worktrees/rv48` belonging to another session — ignore it entirely; it is not your gate.

## The defect, verified — confirm it before changing anything

`backend/src/Tankbook.Api/Llm/LlmService.cs`, in `ExtractAsync`:

1. the provider call succeeds;
2. `IncrementUsageAsync` **meters** it (`:189`) — the user's quota is now spent;
3. `RecordCallAsync` (`:190`) calls `_storage.PutObjectAsync` (`:265`) — **with no try/catch
   anywhere on that path**.

So if S3/MinIO is unavailable the write throws, the exception escapes `ExtractAsync`, and **the user
gets nothing back from a call that already ran, already cost money, and already consumed a quota
unit.** An *audit* write is sitting on the critical path of the user's answer.

**This is a regression RV.33 introduced.** Before the ledger existed, an S3 outage could not affect
`/extract` at all. Say in your report whether you confirmed that reading.

**Second, narrower defect on the same page.** The provider-failure `catch` (`:178-183`) also calls
`RecordCallAsync`. If storage is down *too*, the audit write throws **inside the catch block** and
masks the original provider error — the operator sees a storage stack trace for what was really an
LLM outage.

## The design point: the two outages are NOT the same problem

**(a) Storage down — the answer EXISTS.** Only the audit artefact failed. Failing the user here is
indefensible, and **this is where a queue genuinely belongs**: retry the ledger row / blob write
later, and if it can never land, **degrade to a row WITHOUT its rendition rather than no row and no
answer**.

**(b) LLM provider down — there is nothing to queue.** The image is not the server's to keep. The
product owner's own framing is the correct one: *"with photos we can get them later from a device
with a sync if required"*. The device still holds the photo, so the honest shape is a **clean
failure that does not burn quota** (the current `catch` already declines to meter — that part is
right) plus a client retry.

**Do not build a server-side image queue for retry.** It would mean storing user images for a
purpose hard rule 9's amendments deliberately bounded — they name three content stores and say a
fourth needs its own written decision. If you conclude one is genuinely needed, **stop and say so**
rather than building it.

## What to build

**Fix the critical path first. It is small and it is the actual bug.**

An audit write must never fail a user's request: make the ledger write best-effort (catch, log,
continue), or write the **row** synchronously and the **blob** asynchronously. Either is defensible
— pick one and say why.

**But a silently-dropped ledger row defeats what RV.33 exists for**, so a failed audit write must be
**visible**: its own log event (shape-only — hard rule 12: ids, counts, outcome codes, never a
payload or an image), and if you queue the retry, a bound on how long it retries and a defined
outcome when it gives up.

**Fix the masking catch** so a provider outage still reports as a provider outage.

**Then decide the queue's scope explicitly and write it down** in `docs/API.md` / `docs/SECURITY.md`:

- **what it holds** — ledger rows and blob keys, **not images**;
- **where it lives** — in-memory is lost on the blue-green deploy that happens on every release; a
  Postgres table survives, and `delivery_outbox` (RV.44, migration 016) is a working precedent
  sitting right there;
- **how long it retries, and what happens when it stops.**

## Read before writing

1. **`CLAUDE.md`** — hard rule 9 and **both** its amendments (the LLM call ledger and the delivery
   outbox: they name the content stores and bound them), rule 12, rule 14.
2. `docs/SECURITY.md` → the LLM call ledger and delivery outbox sections; `docs/API.md` → the LLM
   gateway.
3. `backend/src/Tankbook.Api/Llm/LlmService.cs` (`ExtractAsync`, `RecordCallAsync`),
   `LlmCallRepository.cs`, `Outbox/` (the RV.44 precedent — read it before inventing a new shape),
   `backend/tests/Tankbook.Api.Tests/Llm/LlmCallLedgerTests.cs` for the existing L2 shape.

## Tests

**Backend 370 today; must not fall.**

- **The headline L2: with the blob store failing, `/extract` still returns 200 with the extraction.**
  Assert the **response body** carries the extracted fields, not just the status code.
- **Quota is metered exactly once** in that scenario — assert the value, since today the user is
  charged for an answer they never receive.
- **A ledger row exists**, with or without its rendition — **assert which**, so the degradation is
  pinned rather than assumed.
- **Both down**: with the provider AND storage failing, the response and the log both say
  **provider**, not storage. This is the masking fix, and it needs its own test.
- If you add a retry queue: a queued write that later succeeds lands the row; one that exhausts its
  bound has a defined, asserted outcome.

**Vacuous-assertion traps, named:**
- Asserting the status is 200 without asserting the body — an empty 200 would pass.
- Asserting "no exception was thrown". That is the mechanism, not the outcome.
- Testing only the storage-down case. The both-down case is what proves the masking fix.

**Mutation-check and report it**: restore the unguarded `PutObjectAsync` and confirm the
storage-outage test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd backend && dotnet build ; echo "BUILD=$?"
    cd backend && dotnet format --verify-no-changes ; echo "FORMAT=$?"
    cd backend && dotnet test ; echo "TEST=$?"

**Echo the exit code from the COMMAND, never through a pipe** (`cmd | tail -2 ; echo $?` reports
`tail`'s status); redirect to a file instead. `backend/scripts/dev-up.sh` starts Postgres + MinIO
(plain `docker run`, no compose). Match the process NAME (`pgrep -x ...`); **never `pgrep -f`**.

## Report back

- Exit codes (captured, not piped), test counts before/after, the mutation result.
- **Confirmation of the diagnosis** — including whether an S3 outage really could not touch
  `/extract` before RV.33.
- **Which shape you chose** for the audit write (best-effort, or row-sync/blob-async) and why.
- **How a failed audit write becomes visible**, and the retry bound if you added one.
- **The queue's scope as you wrote it down**, and confirmation it holds no images.
- Confirmation the LLM-down path still declines to meter quota.
- Anything you noticed that is not RV.53 — named separately, not folded in.
