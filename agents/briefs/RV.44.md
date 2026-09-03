# RV.44 – the backend's one role in notifications: delivering an answer the device never got

The product owner asked, 2026-09-04: *"should backend process anyhow the notifications?"* The answer
is **yes, exactly once, and it is delivery - never interpretation**. This builds that.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it **`backend/`, `ios/` and
`docs/`** plus the one `CLAUDE.md` paragraph quoted verbatim below.
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.**

Use the **`iPhone 17`** simulator for any xcodebuild/xcrun step. No other agent is running.

## The gap, measured - not hypothetical

Production: `POST /v1/extract -> 499` after 33 s. The client vanished mid-request, **the model call
completed and was paid for**, the answer exists server-side in RV.33's `llm_calls` ledger, and the
device will never see it.

RV.38 shipped the inbox **device-local and best-effort**, which is honest but lossy: an answer
arrives only if the app happened to stay alive. That is the hole this closes.

## The three cases get DIFFERENT answers - do not collapse them

- **(a) Reminders: no backend, ever.** They are scheduled locally and fire locally. Routing them
  through a server breaks **hard rule 1** for a feature that never needed the network. Touch
  nothing about them.
- **(b) A late extraction the device never received: build this.** The rest of the brief.
- **(c) Cross-device inbox state** (dismiss on one phone, it clears on the other): that is ordinary
  **sync of a synced entity**, already a named rule-1 exception, and it is **out of scope**. Do not
  drift into it - a delivery mechanism that also reconciles state across devices has quietly become
  a sync surface, and that needs its own decision.

## The shape, decided 2026-09-04 - an opaque per-device OUTBOX, not a ledger read

**The obvious implementation is the one thing that must not happen.** Letting the device read its
answer back from `llm_calls` turns the audit record into a delivery channel, and RV.33's rule-9
amendment - written on 2026-09-03, days old - says the ledger is *"written by the gateway and read
by no endpoint"*. **Do not add a read endpoint over `llm_calls`.**

Instead: when the gateway **cannot deliver** (client gone, 499, timeout), it enqueues the result
into a small **per-device outbox**, which the device drains on next launch.

**Why the outbox is rule-9 clean and the ledger read is not** - and you must preserve this
property, because it is the whole argument:

- the row is **opaque bytes addressed to a device**;
- the server **never reads a field, never queries by meaning**, and offers **no search or stats**;
- it is the same shape as `GET /blobs/{sha256}` - retrieve-what-you-are-entitled-to.

**It is still a third place storing user content, and RV.33's amendment says that needs its own
written decision.** So `CLAUDE.md` rule 9 gains one, in this same commit. **Do not author rule text
yourself** - insert this approved paragraph immediately after the LLM-call-ledger paragraph:

> **The delivery outbox (amended 2026-09-04, product owner).** A result the gateway computed but
> could not hand back - the client vanished mid-request, which production shows as `499` - is
> queued for the device that asked for it and deleted once collected. This is the **third** place
> that stores user content, and it is bounded the same way as the other two: **retention is 30
> days**, it **requires an account**, `DELETE /account` purges it, and **nothing is logged but
> shape**. What keeps it from being a domain server is that the payload is **opaque**: the outbox
> is addressed delivery, like `GET /blobs/{sha256}` - the server never reads a field, never queries
> by meaning, and exposes no search or stats over it. It exists **because** the ledger must stay
> write-only: reading answers back out of `llm_calls` would turn the audit record into a delivery
> channel, and that is explicitly not licensed. It licenses nothing further.

## Bounds - all of these already exist elsewhere, match them rather than inventing

- **Retention 30 days** - the tombstone/undo window, `/import/parse`'s file and the ledger all use
  that one number.
- **Drain-and-ack**: a collected row is **deleted**, never re-delivered forever. Decide and state
  whether the ack is a separate call or implicit in the read, and what happens if the device dies
  between read and ack (at-least-once is acceptable and honest; silently losing it is not).
- **Requires an account** - so does `/extract`.
- **`DELETE /account` purges it**, like every other content store. Extend the existing purge and
  **test it**.
- **Nothing is logged but shape**: counts, ids, outcome codes, durations. Never a payload, never a
  domain value (hard rule 12).

## The nudge is silent APNs

`docs/NOTIFICATIONS.md` already defines silent APNs. The outbox is what finally makes that wake
worth performing. Wire it if it is cheap; if you defer it, **say so plainly** - draining on next
launch is a complete, shippable behaviour on its own, and the bell already exists.

## Hard rule 1 is untouched, and must stay that way

No screen is gated on the outbox, a guest never has one, and an undelivered answer costs a
**suggestion**, never an entry. If your design makes any screen wait on this, it is wrong.

## The client half

`AppInbox` (RV.38) already persists items and renders them. Drain the outbox on launch/foreground
and feed the **same** inbox path - do not build a second inbox. The three actions, the
blank-fields-only merge and the "leave it as it is" default are already correct and already tested;
reuse them rather than duplicating.

## Read before writing

1. **`CLAUDE.md`** - hard rule 9 (both amendments, which you are extending), 1, 11, 12, 14.
2. `docs/API.md` → the LLM gateway section; `docs/SECURITY.md` → the LLM call ledger section (this
   gains a sibling); `docs/NOTIFICATIONS.md`; `docs/SYNC.md` for what "synced entity" means, so you
   can see why case (c) is different.
3. `backend/src/Tankbook.Api/Llm/` (`LlmService`, `LlmCallRepository`, `LlmCallPurgeService`,
   `ExtractEndpoints`), `backend/src/Tankbook.Api/Account/AccountPurgeService.cs`,
   `backend/src/Tankbook.Api/Blobs/` (the addressed-retrieval precedent).
4. `ios/App/Sources/Inbox/AppInbox.swift`, `ios/Sources/TankbookCore/Inbox/GatewayInboxPolicy.swift`.

The next free migration number is **016**.

## Tests

**Backend (L2, real Postgres via Testcontainers - the suite's existing shape), 357 today; must not fall:**
- A call whose delivery fails **enqueues exactly one outbox row**; a call delivered normally
  enqueues **none**. Assert the row COUNT both ways - *"a successful call writes nothing" is the
  half people forget, and without it the outbox silently doubles every answer.*
- Draining returns the payload and **the row is gone afterwards** - assert the second drain returns
  empty, not that the first succeeded.
- **`DELETE /account` purges outbox rows.** Assert they are gone AND that the ledger's own surviving
  fields are unaffected.
- Retention: a row past 30 days is purged; one inside it is not. Both sides of the boundary.
- `Migration016_AppliesAndRollsBack`.

**iOS, 1223 today; must not fall:**
- L1: draining an outbox payload produces the same inbox item shape the in-process path produces -
  one policy, not two.
- L4 only if a surface changed. The bell and card already exist and are tested.

**Vacuous-assertion traps, named:**
- Asserting the drain "succeeded" rather than asserting the row is **gone**.
- Asserting an outbox row exists without asserting the count - a doubled answer passes.
- Testing only the enqueue path. The delete-on-collect is what stops the inbox growing forever.

**Mutation-check and report it**: make the drain leave the row in place, confirm the
second-drain-is-empty test goes red, restore byte-for-byte and confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd backend && dotnet build ; echo "BUILD=$?"
    cd backend && dotnet format --verify-no-changes ; echo "FORMAT=$?"
    cd backend && dotnet test ; echo "TEST=$?"
    cd ios && swift build ; echo "IOSBUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe** - `cmd | tail -2 ; echo $?` reports
`tail`'s status, not the command's. Redirect to a file instead. Run swiftlint from the **repo
root**; from `ios/` its root-relative `excluded:` paths report thousands of phantom violations.
`backend/scripts/dev-up.sh` starts Postgres + MinIO (plain `docker run`, no compose).

Match the process NAME (`pgrep -x ...`). **Never `pgrep -f` or `pkill -f`** on a build/test pattern.

## Screenshots

Probably none - the user-visible surface is RV.38's bell and card, unchanged. If you change one,
shoot it EN and RU, dark, outside any test run. Otherwise say "none applies" rather than
fabricating one. You have no image input; say so.

## Report back

- Exit codes (captured, not piped) and test counts before/after, **both tiers**.
- **The ack semantics you chose** and what happens if the device dies between read and ack.
- Confirmation that **no read endpoint over `llm_calls` was added**, and that the outbox payload is
  opaque to the server.
- Whether silent APNs was wired or deferred - stated plainly either way.
- The mutation result.
- Confirmation that reminders were left entirely alone and that no screen is gated on the outbox.
- Files changed, docs extended (`CLAUDE.md` rule 9, `API.md`, `SECURITY.md`, `NOTIFICATIONS.md`),
  anything unfinished.
