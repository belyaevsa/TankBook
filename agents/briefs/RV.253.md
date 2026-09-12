# RV.253 - the Settings quota card is fed only by a DEBUG fixture

**Scenario: F10 · sync conflicts surface after the fact (the quota card); J11.** The last open
v1 row holding F10's review.

`SyncSurfaceState.quotaUsedPercent` is only ever `forcedQuotaPercent` (`AppSync.swift:193,275`),
a DEBUG seed the code says *production never sets*. `SyncSurface.status` maps `>= 95` to
`.quotaFull` (`SyncSurface.swift:111`), so the state can never fire for a real user, and the card
prints a hardcoded `95` (`SettingsView.swift:559`). The transport already classifies the answer -
`RemoteBlobTransport.swift:100,107` turns `blob_quota_exceeded` / 429 into
`BlobSyncError.quotaExceeded` - but the number and the state stop there. The server computes the
percent (`BlobService.QuotaPercent`, `BlobService.cs:242`) and sends it to logs only; the 429
problem+json from `BlobEndpoints.cs:74` carries none.

## Decision - keep the card, feed it from the 429

`docs/ERRORS.md` row 411 already defines this card as a next-step surface with no control (RV.70),
so the card stays and becomes real. Cutting it would leave a real 429 with no surface at all,
which breaks hard rule 7.

## Build

1. **Server**: the `blob_quota_exceeded` 429 body carries `quotaUsedPercent` as an additive
   problem+json extension member (next to `traceId`/`code`), from the same `QuotaPercent`. `API.md`
   documents it as additive under the error envelope; no other 429 changes.
2. **Client transport**: `BlobSyncError.quotaExceeded` carries the percent when the body has one
   (`quotaExceeded(usedPercent: Int?)`); a 429 with no body still classifies.
3. **Sync outcome → surface**: the last sync outcome records `quotaUsedPercent` the way it records
   `offline` / `serverUnavailable` (`AppSync.swift:265-282` reads `lastOutcome`), and
   `quotaUsedPercent: forcedQuotaPercent ?? lastOutcome?.quotaUsedPercent`. A 429 with no percent
   surfaces as `100` - exceeded IS full. **The state clears** when a later blob upload succeeds:
   a card that says "95% full" after the sweep freed space is the next bug.
4. `SettingsView.swift:559` renders the surfaced percent; the `95` literal goes.

**Siblings (`docs/DEFECT-PATTERNS.md`)**: `SyncStateChip` `.quotaFull` (`SyncStateChip.swift:205`)
and the `.quotaCard` route share the state - they come alive with it, confirm they read the same
value. `SettingsTestSeed.swift:275` and `SyncChipTestSeed.swift:26` keep working through the
forced value; do not delete the fixture, it is the screenshot seed.

## Tests

- **L2 backend, FAILS TODAY**: a begin over quota answers 429 whose body carries the percent.
- **L1 client, FAILS TODAY**: a transport answering 429 with `quotaUsedPercent: 97` leaves the
  surface at `.quotaFull` with 97; a 429 with no percent surfaces 100; a subsequent successful
  upload clears it. Use the sync test doubles, not the DEBUG seed - the vacuous trap is a test that
  sets `forcedQuotaPercent`.
- **L4** `SettingsUITests` (or the suite that owns `settingsQuotaCard`): from a **seeded 429
  transport**, not the flag - name the seed you add.

Run the named suites each in its own invocation and report counts. Screenshot only if the card's
rendering changed; the seed already produces the existing `P6`/`RV.70` frames.

## Mutation - named

Drop the `lastOutcome?.quotaUsedPercent` fallback (leave the forced value); the L1s go red, the
seeded screenshot still renders. Verbatim output.

## Docs

`docs/API.md` error envelope (additive member), `docs/ERRORS.md` row 411 (the percent is the
server's, the state clears on the next successful upload), `docs/SYNC.md` blob pipeline if it
names the 429.
