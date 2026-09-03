# RV.34 then RV.33 – model pricing as data, then the LLM call ledger

**Two rows, one dispatch, in this order.** RV.34 (a settings table + a model dictionary) is what
makes RV.33 (a row per LLM call, including its cost) buildable at all: **cost cannot be recorded
per call while pricing exists nowhere.** They also share migration numbering and the same write
path through the gateway, so splitting them across two agents would only produce a conflict.

Build **RV.34 first, completely, green** - then RV.33 on top of it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it **only `backend/` and `docs/`**.
Three other agents are working in `ios/` concurrently - **touch no `ios/` file**.
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.**

The next free migration number is **014** (`013_rate_backfill` landed today).

---

# Part 1 – RV.34: the model choice and its pricing become DATA

Today the model is compiled config and **pricing exists nowhere**. Two tables.

## (a) The settings table – which model serves which kind

**Key it per KIND, not globally.** `/extract` already distinguishes `Kind=receipt` from pump
displays (the `llm.extract` log line carries it), and those are different problems that may want
different models.

## (b) The model dictionary

Model id, vendor, **input price and output price** (they differ for every vendor - and
`LlmExtraction` already separates `PromptTokens` from `CompletionTokens`, so the shape is there),
currency, plus what proves useful: context window, and **whether thinking is supported** - RV.33
needs that flag and `ILlmProvider` has no notion of it today.

## The rules these tables must obey

- **Updated by direct DB write, no admin endpoint** - the same decision already taken for the
  vehicle catalog and reference data this session. Do not add an endpoint.
- **No API keys in either table** (hard rule 11: keys live in the platform secret store, which is
  the entire reason the gateway exists). The dictionary *names* a vendor; it never authenticates to
  one.
- **A missing or unknown setting must not 500.** Fall back to a compiled default and log the
  fallback at **Warning** - otherwise one bad DB row takes cloud extraction down for everyone.
- **Give dictionary entries an effective-from date**, so a price correction is a **new row**, never
  an edit to a historical one.
- **Decide and record the cache policy**, explicitly, in your report and in the code's comments:
  read-per-request costs a query on every extract; cached costs a restart to change a model. The
  catalog's existing pack-state caching is the precedent. Either is defensible; an unstated choice
  is not.
- Moving the model choice out of compiled config is a **`docs/PRACTICES.md` constants-placement
  change** (compiled / remote / user / frozen) and belongs in that doc, in this change.

## RV.34 tests (L2, real Postgres via Testcontainers - the suite's existing shape)

- An **unknown model id falls back** rather than throwing, and the fallback is logged at Warning.
- A **missing settings row** falls back the same way - extraction still works.
- Per-kind resolution actually differs: `receipt` and a pump kind configured to different models
  each resolve to their own.
- `Migration014_AppliesAndRollsBack` (follow `MigrationsTests`' existing pattern).

---

# Part 2 – RV.33: every LLM call is recorded

One row per call to every LLM gate - `/extract` today, `/agent/turn` when v2 lands. The row
carries: **who called, what was called (model + vendor), the outcome, a success/error category,
tokens consumed, whether thinking was enabled and its response, the cost, the prompt sent, the
model's actual response, and references to any attachment we sent.**

## THIS REVERSES A SIGNED-OFF DECISION. The amendment is approved and its text is below.

`CLAUDE.md` rule 9 currently says of `/import/parse`: *"**Stored, deliberately, and unlike the LLM
gateway.** ... This is a **deliberate asymmetry**: `/extract` never stores an image, `/import/parse`
does store a file. Both are signed off; neither licenses the other."* The `[v2]` agent exception
likewise says `/agent/turn` **stores nothing**. **Storing prompts and responses reverses both.**

The product owner made this call on 2026-09-03. **You must land the amendment in the same commit as
the code** - `CLAUDE.md` rule 9, `docs/API.md` and `docs/SECURITY.md` - or the next reader will
treat the table as a bug.

**Do not author rule text yourself.** Insert this approved paragraph into rule 9, after the
`/import/parse` exception's five properties and before the `[v2]` exception, and adjust the
now-stale "never stores an image" sentence in the `/import/parse` bullet to point at it:

> **The LLM call ledger (amended 2026-09-03, product owner).** Every call to an LLM gate is
> recorded: caller, model, vendor, tokens, thinking, outcome, cost, and the prompt and response
> bodies - with the image kept in blob storage and referenced by `sha256`, never in a column. This
> **reverses** the asymmetry recorded above: `/extract` now stores, and so will `/agent/turn`. The
> reason is that an unmetered, unauditable spend path is worse than the storage it avoids - the
> gateway spends real money per call on the user's behalf, and no other record of what was sent,
> what came back, or what it cost exists anywhere. The bounding properties are unchanged and are
> what keep this from spreading: **retention is 30 days**, the same number as the tombstone/undo
> window and `/import/parse`'s file; the ledger is **written by the gateway and read by no
> endpoint** - there is no query, search or stats API over it; and it **licenses nothing else**. A
> third place that stores user content needs its own decision, written here.

## The shape, decided

- **The prompt for `/extract` IS the receipt image** - measured **774 KB** on the wire. It does not
  belong in a table column. **Store the rendition in blob storage and reference it by `sha256` from
  the row** (product owner, 2026-09-03). `blob.begin` already logs a `Sha256`, so the precedent
  exists, and this reference *is* the "references to any attachment we sent" that was asked for.
- **Retention is 30 days**, matching `/import/parse` and the tombstone/undo window, so one number
  governs "how long can I get it back". `docs/SECURITY.md` calls that a written commitment - write
  this one down there too.
- **`DELETE /account` purges the CONTENT and keeps the REFERENCES** (product owner): the stored
  rendition blob and the prompt/response/thinking bodies go; **the row survives** carrying
  timestamps, model, vendor, tokens, cost, outcome and the `sha256` - so the spend ledger stays
  intact while nothing of the user's receipt remains.
- **`accountId` stays on the surviving row** (product owner, 2026-09-03 - asked and answered
  explicitly). Per-account cost history survives deletion. **Record this in `docs/SECURITY.md`'s
  privacy classes** as the deliberate choice it is, and note alongside it that `sha256` is
  content-addressed, so an identical image uploaded again dedupes to the same hash - a weak
  re-identification path, worth the sentence rather than a redesign.

## The invariant RV.34 exists to serve

**PRICES CHANGE, SO THE CALL ROW MUST SNAPSHOT THE PRICE IT PAID.** This is hard rule 3's own logic
- *a rate snapshot on the entry, immutable, never recomputed* - applied to a second kind of money.
If the row merely points at the dictionary, a vendor price rise **silently rewrites the cost of
every historical call** and the ledger stops being a record of what was spent. Snapshot the unit
prices onto the row.

## What is already in hand vs what is not

- **Nearly free**: `LlmExtraction` carries `Model`, `PromptTokens`, `CompletionTokens`;
  `LlmRepository.IncrementUsageAsync` already meters `TotalTokens`. Model, vendor, tokens, outcome,
  duration and caller follow from what the gateway already knows.
- **Not there**: **thinking is neither requested nor captured by `ILlmProvider` today** - that is a
  seam change, and RV.34's dictionary carries the "supports thinking" flag it needs.

## RV.33 tests (L2)

- A **successful** call writes exactly one row with **every** field populated - assert the values,
  not that a row exists.
- A **failed** call writes one too, with its error category. *A table that only records successes
  cannot answer the question it exists for.*
- **Deletion**: `DELETE /account` removes the blob and the bodies **while the row and its ledger
  fields survive**. *Asserting only that the row is still there passes against a deletion that
  purged nothing* - assert the bodies are gone AND the cost/tokens/model/`sha256` remain.
- **The snapshot invariant**: record a call, then change the dictionary price, then re-read the row
  - **the recorded cost is unchanged**. Mutation-check this one specifically.
- `Migration01N_AppliesAndRollsBack`.

**Vacuous-assertion traps, named:**
- Asserting a row count of 1 without asserting the row's contents.
- Asserting cost `> 0`. This session already shipped a rate bug straight past `rate > 0` - a RUB
  rate of `1008287` instead of `100.8287` sailed through it. **Pin the arithmetic**: known token
  counts × known prices = an exact expected cost.
- Asserting the blob "was deleted" by checking a flag rather than that the fetch now misses.

## Hard rule 12 still governs the LOGS

The table stores content **by this explicit amendment**; the **logs do not change**. Format names,
counts, ids, durations, model ids and outcome codes are loggable. A prompt, a response body, a
station, an amount or an image is not - **at any level, in any build**.

## The baseline gate (CLAUDE.md rule 14)

    cd backend && dotnet build ; echo "BUILD=$?"
    cd backend && dotnet format --verify-no-changes ; echo "FORMAT=$?"
    cd backend && dotnet test ; echo "TEST=$?"

**Judge by the exit code you echoed.** `backend/scripts/dev-up.sh` starts Postgres + MinIO for local
dev (plain `docker run`, no compose - the user's standing rule). **347 tests today; must not fall.**

Match the process NAME (`pgrep -x ...`). **Never `pgrep -f` or `pkill -f`** on a build/test pattern
- an agent's brief is part of its command line, and that pattern killed a sibling agent on
2026-08-24.

## Report back

- Exit codes and test counts before/after, for **both** parts.
- **The exact cost arithmetic your test pins** (tokens × prices = expected), quoted.
- **The cache policy you chose** for the model/settings lookup, and why.
- **How thinking is threaded** through `ILlmProvider`, or why it is deferred - named plainly, not
  silently skipped.
- The mutation result for the price-snapshot invariant.
- Confirmation that the `CLAUDE.md` rule-9 amendment, `docs/API.md` and `docs/SECURITY.md` all moved
  in this change, and that `accountId`'s survival is written into SECURITY.md's privacy classes.
- No `ios/` file touched. No admin endpoint added. No key in either table.
- Anything unfinished, named plainly.
