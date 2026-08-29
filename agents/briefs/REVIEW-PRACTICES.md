# REVIEW-PRACTICES – audit the implementation against docs/PRACTICES.md

*Written 2026-08-29 before dispatch. Four read-only review agents, one per area, run in
parallel. Output feeds `docs/PRACTICES.md` §7 and a task list appended to `docs/TASKS.md`.*

## Shared instructions (every agent)

- Read `docs/PRACTICES.md` sections 1-6 first; your area's table is the checklist. Read the
  companion doc each row cites before judging the code against it.
- Read-only. Do not edit, build or run tests.
- Scope: `ios/Sources/TankbookCore`, `ios/App/Sources`, `backend/src`. Tests are evidence of
  a practice being enforced, so cite them, but do not review test quality.
- For every practice row in your area report exactly one of: **MET** (cite file:line),
  **PARTIAL** (what exists, what is missing, file:line for both), **MISSING** (what you searched
  for and did not find), **N/A** (why). Never report MET without a citation.
- Every PARTIAL/MISSING becomes a proposed task: id `PR.<n>`, one-line deliverable, a concrete
  user- or maintainer-facing consequence of not doing it, and the check that would make it done
  (L1 unit / L2 integration / L4 UI, in `docs/TESTING.md` vocabulary). Severity: **bug** (a hard
  rule is violated or a user loses data/time), **gap** (the doc promises it, the code lacks it),
  **hardening** (good practice, not promised).
- Never quote domain values from fixtures or logs in your report (hard rule 12 applies to
  reports too).
- Keep the report compact: tables, file:line, no narrative.

## Area 1 – Architecture + UX under a network (rows A1-A6, U1-U12)
Focus: the HTTP client(s) and how views consume them; sync engine offline/online transitions;
what happens on 401 mid-request and whether a refresh is serialised; timeouts and retry policy
actually configured on URLSession / HttpClient; whether any view awaits a network call at
launch or before first draw; how conflicts reach the UI; migration safety on the device
(backup before migrate, downgrade handling); idempotency of every mutating endpoint on the
server (keys, upserts, unique constraints).

## Area 2 – Security (rows S1-S13)
Focus: Keychain accessibility classes as written vs `SECURITY.md`; file protection on the DB
and `-wal`/`-shm` and attachments; any string in `ios/` that looks like a key, secret or
non-public URL; ATS/Info.plist exceptions in `project.yml`; token lifetimes and refresh
rotation on the server; revocation on logout; rate limiting and payload size limits per
endpoint; JSON Schema validation before any handler reads a body; presigned URL constraints
(content-type, size, expiry); the 30-day retention job for import files and tombstones;
account deletion completeness (what tables/blobs it touches); anything logged that the
LOGGING.md classes forbid.

## Area 3 – Debuggability (rows D1-D10)
Focus: is `X-Tankbook-Trace` generated per request on the client, echoed on every server log
line and in every error body including the 500 path; error codes vs messages on the wire and
the client's code -> string mapping; does the diagnostics export in `LOGGING.md` §5 exist end
to end (collection, redaction, preview, send); is sync state (last success, pending count, last
error) visible in Settings; which async edges are logged (background task expiry, app kill
mid-write, network change mid-upload, clock skew); silent-failure metrics/events; server slow
query and per-endpoint error logging keyed by app version; a way to load an exported DB into
the simulator.

## Area 4 – Constants placement (section 6)
Input: the inventory table in `docs/PRACTICES.md` §6.1 (filled before dispatch). For each row
judge the tier (C/R/U/F) against the rules in §6 and report: correct / wrong tier / duplicated /
disagrees with a spec doc / magic literal that should be named. Also search for the same
value appearing in `docs/*.md` with a different number. Propose one task per problem, batched
where a single change fixes several (e.g. "name the transport timeouts in one place").
