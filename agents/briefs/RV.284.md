# RV.284 - a fill-up flagged `consumption` is rejected by the deployed registry, forever and silently

**Scenarios: F10 · sync conflicts surface after the fact (the badge where data lives), F2 · the
residue (the consumption outlier flag), J11 · new phone (the record that never reaches the
server).** `[!]`. Found 2026-09-14 in the production log: two `fillUp` records
(`01a07a46-8935…`, `01a07a46-8932…`, created 2026-09-07) come back
`rejected · payload_schema_violation · /conflict/kind` on **every** push - 14:17, 18:35, 18:36,
18:57, 18:58, twice a minute while the app is open - and nothing on the device says so.

## The cause, pinned - two halves

**Server half.** `payload_schemas` is seeded ONCE, by migration 002, with
`INSERT … ON CONFLICT (entity_type, schema_version) DO NOTHING`
(`backend/src/Tankbook.Api/Data/PayloadSchemaSeeder.cs:54-58`,
`Migrations/002_payload_contract.up.sql:36-40`). `RV.218` (2026-09-11) added the enum value
`consumption` to `ConflictState.ConflictKind` and regenerated
`docs/schemas/v1/fillUp.schema.json` - **same `schema_version` 1** - so the embedded resource in
every backend built since carries the new enum, but a database that ran 002 before 2026-09-11 keeps
the old row and no later migration touches it. The deployed registry rejects what the app now
emits. `docs/SYNC.md` → "The schema registry lives in the database" says evolution is a data change;
an additive change inside a version has no data change that carries it.

**Client half.** `SyncEngine` treats `.rejected` exactly like a transient failure:
`repository.markDirty` (`ios/Sources/TankbookCore/Sync/SyncEngine.swift:581-582`, and `:652` in
the conflict path), so the row re-pushes on the next trigger, unchanged, forever. No device log
event names a rejection (`LogEvents.swift`: `sync.cycle.*`, `sync.merge`, `sync.queue` - none
carries a rejected count), no badge, no Settings row. `docs/SYNC.md` S7 covers "server
unavailable" (stay dirty, no banner); a **422 is not unavailability** - the same bytes will be
rejected until something changes, and hard rule 8 says nothing is lost silently.

**This brief's diagnosis is a hypothesis - confirm both halves before you change anything**: for
the server, `SELECT json_schema->'$defs'->'conflictState'->'properties'->'kind' FROM
payload_schemas WHERE entity_type='fillUp'` against a database that ran 002 before RV.218 (the
test fixture can reproduce it: apply 002 from an older embedded schema, then the current binary);
for the client, `PayloadCodec` encodes `consumption` (`PayloadCodable.swift:118-125`) and the
`JSONSchemaValidator` on the device passes it because the device's copy of the schema is current.

## Build

**Server**
1. Migration `023_payload_schemas_refresh.up.sql`: the seeder gains a second marker that emits
   `INSERT … ON CONFLICT (entity_type, schema_version) DO UPDATE SET json_schema =
   EXCLUDED.json_schema`, so every deploy's migration set lands the embedded schemas for the
   versions it carries. Idempotent, additive-only within a version (a schema that removed a value
   would need a new version - say so in `SYNC.md`). The `.down.sql` is a no-op with a comment (a
   registry row cannot be un-refreshed to an unknown prior text).
2. `PayloadRegistryTests`: after migrations, every registry row is byte-equal (as parsed JSON) to
   the embedded resource for that entity and version - the test that would have failed on
   2026-09-11.
3. `docs/SYNC.md` "The schema registry lives in the database": add the paragraph - an additive
   change inside a version ships as a refresh migration; the seed is not the only writer.
   `docs/DEVELOPMENT-TIMELINE.md` if the deploy checklist changes.

**Client**
4. A `.rejected` outcome is **terminal for that payload**: mark the row `rejected(code, pointer)`
   in `sync_state` (a new state beside dirty/pushing/synced, `SCHEMA.md` → sync state), stop
   re-pushing it until the record is edited again (an edit re-dirties it; a new app build may emit
   a different payload), and count it in the cycle summary.
5. Surface it where data lives (hard rule 8, F10): the entry row carries the same attention badge a
   conflict does, with the row's own next step - "Could not sync this entry – update the app or edit
   it to retry" (the honest reading: the fix is a newer app or a newer server, never the user's data);
   the Settings sync row counts "N entries could not sync". `docs/ERRORS.md` Settings/sync and Log
   rows; `docs/SYNC.md` S7 gains the 422 sibling.
6. A shape-only device log event `sync.rejected` with entity type, code, pointer and count (hard
   rule 12 - never the payload).

Out of scope: `upgrade_required` (426, already a card); the two production rows themselves - once
023 is deployed their next push is accepted, no data change needed.

## Environment axes

Upgrade (a device holding rejected rows before this build must re-push them once after
installing it - the new state must not strand rows already dirty); offline (no change);
signed-out (no sync, no surface).

## Tests

- **Backend L2, fails today**: a database seeded with an older `fillUp` schema (fixture: the
  pre-RV.218 file, kept under `tests/Fixtures/schemas/`) accepts a `consumption` conflict after 023
  runs; the registry-equals-embedded test.
- **Core L1, fails today**: a push result `.rejected` leaves the row in the new state, the next
  cycle's push batch does not contain it, an edit puts it back; the summary counts it.
- **L4** `SettingsUITests` / `HomeUITests` (signed): the badge and the Settings count render EN +
  RU with the next step; screenshots `RV.284-log-rejected` and `RV.284-settings-rejected`, EN + RU.

## Mutation - named

Restore `markDirty` for `.rejected` in `SyncEngine`; the "next batch does not contain it" L1 goes
red. Verbatim, then restore.

## Vacuous trap

Refreshing the registry and calling it done - the client half is the hard rule 8 violation and
survives any registry fix (the next additive enum will do it again); a badge with no next step;
a state that strands a row after the user edits it.
