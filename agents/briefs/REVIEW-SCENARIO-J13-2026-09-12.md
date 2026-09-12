# REVIEW-SCENARIO run: J13 - 2026-09-12 (first walk)

- **Scenario:** `J13` - Selling the car (`docs/JOURNEYS.md`)
- **Run id:** REVIEW-SCENARIO-J13-2026-09-12
- **Report path:** `diagnostics/REVIEW-SCENARIO-J13-2026-09-12.md`
- **Context:** Never walked. Every v1 row naming J13 is closed; deferred and N/A: `PJ.37` [v1.1] (PDF dossier), `RV.123`. Related shipped today: `RV.260` (restore from a Tankbook backup - the per-car export now has a reader). The spine: the car's history leaves with the car (export, per-car), the seller keeps nothing they should not and loses nothing they should keep, deletion is a tombstone with the 30-day undo (hard rule 8), and stats recompute for the remaining garage. Walk sell -> export -> archive/delete -> undo -> the other car's Trends.

**A build agent (RV.226) and two journeys-walk agents are working in this checkout. Write ONLY your report and, on IMPLEMENTED, this scenario's status line - re-read `docs/JOURNEYS.md` immediately before that one write.**

---

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except the two writes named
at the end**: your report, and the scenario's status line in `docs/JOURNEYS.md`. **No code, no
tests, no builds, no commits.** A build agent may be working in this checkout - if you write
anything else you corrupt its work.

## What you are checking

**Every promise the journey makes, against the code that keeps it.** The journey text is the
specification; the rows are one team's guess at how to satisfy it. The gap between them is the whole
point of this run.

For each stage, each fallback and each "→" note in the journey's own text:

- **MET** - with a `file:line` citation. **Never MET without one.**
- **PARTIAL** - what exists and what is missing, `file:line` for both.
- **MISSING** - and what you searched for. **This is the finding that matters.** J7's Fallbacks
  sentence promised *"the user renames/splits by hand"* from the day it was written; `PJ.23` shipped
  the rename and nobody noticed the split was never filed until the product owner opened the screen.
- **N/A** - and why: a later phase per `VISION.md`, or a `[v2]` marker.

## The five questions this review exists to answer

1. **Is any promise unowned?** A sentence in the journey with no row and no code. That is the
   `PJ.23` shape and it is the reason this review exists.
2. **Is any row ticked but untrue?** Walk the code, not the row. *"`PJ.n` is ticked but …"* is the
   most valuable line you can write.
3. **Does the story hold as a SEQUENCE?** Walk it end to end as one user doing one thing, not as a
   list of screens. Say at which step a fact stops being carried. Both defects the import walk found
   (`RV.185`, `RV.189`) were sequence defects: every screen was right and the data lost its meaning
   between them.
4. **Can a user REACH every step?** A screen whose only door is `#if DEBUG` passes every test
   (`PJ.4`). `RV.162`'s guard proves a door names a screen; it does not walk the graph.
5. **Does the story hand off cleanly, and does every next step it names EXIST?** A journey that ends
   by promising another one - "then archive the car", "then the reminder fires" - is not finished
   until that handoff exists. This is also where `RV.164`'s fourth audit question lands: `RV.162`'s
   guard and `ErrorRouteGuardTests` prove a screen/route EXISTS, never that the behaviour the copy
   promises does. For every next step a journey or error names, open the code it points at and say
   whether the behaviour is there - `RV.98`'s *"moves to Recently deleted"* named a real screen whose
   car row did not exist, and no route scan could see it.

## Dead ends to hunt while you are here

Three shapes this project produces repeatedly, all invisible to the type checker:

- **A field nothing writes.** `Station.favorite` had a column, a decoder, ten seeds and a reader in
  the ranking ladder, and no writer at all (`PJ.55`). `RV.196`'s guard now catches these **for
  entities `docs/SCHEMA.md` gives a `###` section** - so an entity the schema does not document is
  invisible to it, and is yours.
- **An entity nothing creates.** `RV.163`'s guard is satisfied by an UPDATE-only writer, so an
  entity that can be edited but never made passes it.
- **A doc or comment naming behaviour with no call site.** `TireSetDraft`'s comment promises a
  rename *"must never overwrite"* a field nothing can set.

## Do not re-file what is already filed

**Read `docs/TASKS.md` end to end before proposing anything.** Twice on 2026-09-10 a finding was
filed that an existing row already carried - `RV.195`'s "leftover" was `PJ.23`, PRIORITY since
2026-08-31, and `RV.165` duplicated `RV.110`. Cite a row; do not duplicate it.

## Your verdict, and it is the deliverable

End with **one** of these, stated plainly:

- **IMPLEMENTED** - every promise is MET or reasoned N/A. **Then make your second write**: set the
  scenario's status line in `docs/JOURNEYS.md` to `**Status: implemented <date>** (reviewed by
  REVIEW-SCENARIO, <run id>)`, directly under the journey's heading. Nothing else in that file
  changes.
- **NOT IMPLEMENTED** - with the list of what is missing, as proposed rows. **Do not touch the
  status line.** A story is not finished because its backlog is empty.

**Recommending NOT IMPLEMENTED is the expected outcome of a first run** and costs you nothing. A
review that rubber-stamps is worse than no review: it converts "nobody checked" into "somebody said
it was fine".

## Output

Write your report to **`diagnostics/REVIEW-SCENARIO-<id>-<date>.md`**. Tables, `file:line`, no
narrative. **Never quote a domain value** from a fixture or a log (hard rule 12).

In this order:

- **the verdict**, one line;
- **the ticked rows you found to be untrue**, if any - first, because they are the point;
- **the promise-to-code map** - every stage and fallback, MET / PARTIAL / MISSING / N/A;
- **the sequence trace** - one user doing the whole thing, and where a fact stops being carried;
- **proposed rows** for everything missing, each with its one-line deliverable, the journey stage it
  closes, the user-facing consequence **today**, severity (**bug** / **gap** / **polish**), the check
  that makes it done (L1/L4, naming the suite), and **the scenario id it attaches to** - which is
  this one;
- anything you could not settle, and what would settle it.
