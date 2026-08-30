# Task PJ.47 - reconcile the journeys with the ledger

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 24. A DOC TASK - no code.** `docs/JOURNEYS.md` describes behaviour the app does not
have, and in one place contradicts itself.

## Where you may write

```
docs/JOURNEYS.md
docs/ERRORS.md
```

**Nothing else.** No Swift, no tests, no `docs/TASKS.md`, no site, no backend.
**Do not commit.**

## Why this matters more than a doc tidy

`HANDOVER.md` records four separate occasions where a stale sentence in a doc cost real work -
including one where a wrong premise was faithfully copied into an agent brief and implemented. The
rule it draws: **a stale sentence in a doc everyone reads first is more expensive than a bug.** A
bug fails a test; a wrong premise gets built.

## The three phrases, verified present

1. **`JOURNEYS.md:185` says "at today's rate"** - and **line 393 of the same file** says
   *"Never apply today's rate to last month's fill-up silently: a wrong-date rate is worse than no
   rate."* The file contradicts itself. **Hard rule 3** settles it: `rateDate` is the **entry's
   date**, never today. Fix line 185 to match the rule and its own warning.
2. **J2 "auto-detect format, never ask"** - the app **asks**, deliberately: `ERRORS.md:171` and the
   shipped import wizard show a source picker, because a format the picker cannot list is a format
   that does not exist. Reconcile the journey to the declared-source design.
3. **F5's "Fiscal service isn't answering"** - **no lookup is ever attempted.** P2.6's enrichment is
   *permanently* deferred: the QR carries only total, timestamp and fiscal ids, and the OFD document
   is keyed on an id not derivable from the QR (verified against two OFDs). F5 is the **normal**
   path, not a failure. Drop the line.

Also: **`ERRORS.md:121` device attribution -> v2.**

## The footnotes

Add a footnote to each of **P1.1, P2.2/P2.3, P3.4, P4.4, P5.2 and P6.3** naming the PJ task that
closes its overclaim. **Several of those closed today**, so use these rather than guessing:

| Overclaim | Closed by |
|---|---|
| Capture screen exists but no image becomes a prefill | **PJ.1** (done 2026-08-30) |
| Scanned save discards the photo | **PJ.2** (done) |
| Reminders unreachable in a Release build | **PJ.4** (done) |
| A tapped notification goes nowhere | **PJ.5** (done) |
| "Type it" ignores the capture mode | **PJ.6** (done) |
| Rate arrives and nothing backfills | **PJ.8** (done) |
| Welcome root missing, wrong-provider question unreachable | **PJ.3** (done) |
| Odometer caption static | **PJ.14** (done) |
| Empty scan has no live form | **PJ.17** (done) |
| Feedback cannot be sent | **PJ.20** (done; server half **PJ.20a**, open) |
| Export row does nothing | **PJ.36 / PJ.38** (done) |
| Per-source export guide | **PJ.33** (done) |

**Only claim "closed" where the row is ticked `[x]` in `docs/TASKS.md`** - check each one, do not
trust this table alone. Where a row is still open, say so and name it; a footnote that claims a fix
which has not landed is the very defect this task exists to remove.

And add **a one-line pointer at the top of `JOURNEYS.md`** to the reconciliation section, so the
next reader meets it before the prose.

## Explicitly out of scope

Any code, test or fixture · `docs/TASKS.md` · the site · committing · **rewriting journeys that are
accurate** - this is a reconciliation, not an edit pass.

## Checks

This row's check is a **grep**, and it is the whole gate:

```
grep -n "at today's rate"            docs/JOURNEYS.md    # must find NOTHING at :185's claim
grep -n "never ask"                  docs/JOURNEYS.md    # the J2 phrase must be gone
grep -n "isn't answering"            docs/JOURNEYS.md    # F5's line must be gone
```

Run all three and **paste the real output**. Then confirm each footnote names a PJ id, and that
`ERRORS.md:121` is marked v2.

**No `swift build`, no tests** - you changed no code. Say so rather than reporting a stale count.

## What would make this task fail

Deleting a sentence without replacing the guarantee it described. Each of the three phrases exists
because someone meant something by it: line 185 means "the user sees a converted amount", J2 means
"the user is not made to identify a file format", F5 means "the QR path degrades gracefully". Keep
the **intent**, fix the **claim**.

## Report back

The three greps with their real output; every footnote you added and which `docs/TASKS.md` status
you verified for it; anything you found stale that this brief did not name; and anything in this
brief that is wrong.

En-dashes only, never em-dashes.
