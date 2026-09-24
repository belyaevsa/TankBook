# REVIEW-BACKLOG-2026-09-24 - does each open row still make sense?

Read-only except `agents/reviews/BACKLOG-2026-09-24.md`. Repo `/Users/sbelyaev/repos/fuel-counter-ios`.
The owner asked: "evaluate if other tasks in the backlog make sense". Scope: every OPEN row (`[ ]` or
`[~]`) in `docs/TASKS.md` whose id is NOT `PU.*` (the orchestrator reviews those) - RV, AG, PR, PJ, AD,
SH, T; about 88 rows. Read `CLAUDE.md` (hard rules, the version-scope markers: unmarked = v1, `[v2]`,
`[v1.x]`), `HANDOVER.md`, and `docs/TASKS-DONE.md` only to check whether something was already done.

For each row, one verdict with the evidence (file:line in the tree, a commit, or a doc line):
- **KEEP** - still true and still worth doing; say what it is for in one line.
- **DONE** - the tree already does it (name the code or commit); the row should close.
- **STALE** - the premise no longer holds (code moved, a decision changed, a later row superseded it);
  name what changed.
- **DUPLICATE** - another row covers it; name the row.
- **UNCLEAR** - the row cannot be judged as written; say what is missing (no check, no scenario, no
  owner decision).
- **DEFER** - valid but for a later version than its marker says, or blocked on something named.

Verify each DONE/STALE claim against the code, not the row's prose - a row that looks done by its
title is often half done (`docs/DEFECT-PATTERNS.md`). Do not edit `docs/TASKS.md`.

Report: a table (id, title, verdict, one-line evidence), then counts per verdict, then the ten rows
that most need the owner's attention and why. Keep each evidence cell short.
