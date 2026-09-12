# RV.261 - J11's "last odometer with its source device" is a v2 field rendering nothing

**Scenario: J11 · new phone (the restore screen's verification stats).** Polish; a doc
reconciliation with one optional render.

`docs/JOURNEYS.md:518` promises *"last odometer with its source device - from your Android phone,
yesterday"*. `docs/SCHEMA.md:24` and `docs/ERRORS.md:366` already mark the source device `[v2]`;
the restore screen shows "Last odometer N km" with neither source nor recency.

## Build

Reconcile the three docs and `RestoreSnapshot`: mark the source-device half `[v2]` in J11's
text. Keep the v1-computable recency if `RestoreSnapshot.lastOdometerDaysAgo` (or equivalent)
exists or is one line to compute from the snapshot's entries: render "N days ago" after the
odometer with no device name, EN + RU as full localised phrases (never composed). If neither
half is honestly v1, strike the clause and say why. One way; say which.

## Tests

If recency is rendered: **L4 `SignInUITests`** (own invocation, count non-zero) asserts the
"N days ago" suffix from a seeded `lastOdometerDaysAgo`; screenshots EN + RU
`design/screenshots/RV.261-restore-stats.png` / `-ru.png`, dark. If only docs change: lint +
compile suffice (CLAUDE.md rule 14).

## Mutation - named

Drop the suffix; the L4 goes red. Verbatim. (Docs-only: no mutation; say so.)
