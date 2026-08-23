# Tankbook – Verification Strategy

*How every story, endpoint, and function is proven. Law: a story is DONE when its checks below pass in CI (or its named manual check is signed off) – "works on my phone" is not a verification level. Companion to `PHASES.md` (when each suite must exist), `JOURNEYS.md` (the stories), `API.md` (the contract), `SCHEMA.md` (invariants + golden vectors), `ERRORS.md` (the 3-question audit).*

## Verification levels

| Level | Tooling | Proves |
|---|---|---|
| **L1 Unit** | swift-testing / xUnit; pure functions, no I/O | Algorithms match golden vectors |
| **L2 Contract** | Backend integration tests against real Postgres + MinIO (Testcontainers); iOS client tests against a recorded/stub server implementing `API.md` | Both sides implement the same API.md |
| **L3 Scenario** | Multi-client sync simulator: N in-process clients + real backend, scripted interleavings | SYNC.md S1–S8 outcomes, deterministically |
| **L4 UI** | Snapshot tests per screen/state (dark+light, EN+RU, Dynamic Type L) against `design/screens/` intent; XCUITest for flows | Screens match artboards; flows navigate per SCREENMAP.md |
| **L5 Accuracy** | The Spike harness grown into CI: fixture corpus + `expected.csv`, per-locale scoring | OCR/parser gates; regression on every parser change |
| **M Manual** | Checklist per release, named checks only | What automation can't reach (camera feel, haptics, real pumps) |

## Per-story verification (journeys → checks)

| Story | Checks (level) |
|---|---|
| J1 first launch | L4: Welcome→AddVehicle→GuestHome flow; empty-state renders (no N/A tiles). M: time-to-first-entry < 3 min with a real receipt |
| J2 / F6 import | L1: importer round-trip per source format (parse→entities→export→byte-comparable); real My Fuel Manager export reproduces its own lifetime average. L4: partial-import review flow (6-bad-rows fixture) |
| J3 fill-up capture | L5: receipt corpus ≥ target accuracy; cross-check tolerance cases. L4: Confirm happy path, odometer delta shown. M: 5 live fill-ups, median capture-to-save < 15 s |
| J3 mixed receipt | L1: fuel-line-not-grand-total detection on fixture receipts (the ≥95% isolation gate). L4: "Also on this receipt" toggles; grouped save creates FillUp+Expense sharing purchaseGroupId |
| J4 pump photo | L5: pump-display corpus, ships only ≥95% (VISION gate). L1: bare-triple assignment incl. symmetry tie-break |
| J5 fiscal QR | L1: QR payload parser (FNS format fixtures incl. malformed). L2: enrichment fill-blanks-only. L4: F5 degraded save |
| J6 EV charge | L1: kWh stats, tariff cost computation, %→kWh via battery size. L4: charge confirm in headlight accent |
| J7/J7b/J7c service, parts, reminders | L1: lifetime→reminder proposal; shelf link never double-counts (cost/km invariant test); reminder lifecycle state machine (complete→new row anchored at completion; reschedule re-arms; delete vs dismiss). L4: ServiceEntry with date+odometer; ReminderComplete flow into ServiceEntry |
| J8/J9 trends & anomaly | L1: all SCHEMA derived formulas vs golden vectors; anomaly thresholds incl. seasonality fixture; dismiss-with-reason suppression. L4: tile grid, excluded-entry footnote |
| J10 / S8 currency | L1: Money semantics (homeAmount=amount/rate; rateDate=entry date; snapshot immutability; backfill fill-blanks-only; edit clears snapshot). L2: /rates correctness incl. weekend carry-forward. L4: foreign confirm shows rate+source+date |
| J11a/J11 sign-in & restore | L2: session exchange, refresh rotation + reuse-revocation, implicit account creation. L3: pull-from-zero restore equals origin dataset (hash compare). L4: wrong-provider empty-account detection; Restoring shows manifest stats; "sign out" escape |
| J12 (v2) sharing | deferred; S3 out-of-order test stands in |
| J13 export/archive | L1: backup round-trip (export→import→identical entities incl. tombstones); archived cars excluded from active stats |
| F1–F4, F8, F9 failure states | L4: each state renders with its ERRORS.md next-step actions present (snapshot per state). L1: confidence gating logic; pace/order validation matrix (F9a: every check × receipt-date priority) |
| F7 restore failure | L3: server-down mid-restore → partial usable + resume; empty-account honest path |
| F10 / S1–S8 sync conflicts | L3: one scripted test per scenario asserting the documented outcome (S1 LWW+undo entry, S2 single-count until resolved, S3 flag+exclusion, S4 resurrect/tombstone, S5 archived resurrect, S6 invisible retry, S7 queue+batch toast state, S8 identical backfill). The S-matrix IS the test plan |

## Per-endpoint verification (API.md → L2, all also asserting RFC7807 error shapes)

- `POST /auth/session`: valid Apple/Google tokens (test signers), expired/garbage tokens, account auto-creation exactly-once under concurrent first sign-ins, device row upsert.
- `POST /auth/refresh`: rotation; **reuse of rotated token revokes chain** (the theft test).
- `GET /sync/pull`: SCN ordering, pagination stability under concurrent writes, since=0 completeness, 410 on revoked device.
- `POST /sync/push`: baseScn accept/conflict per item; idempotent replay; batch cap; future-clock clamping.
- `POST /blobs/begin|commit`, `GET /blobs/{sha}`: dedupe, caps (25/10 MB), quota 429, commit-verifies-object, presigned GET expiry, **cross-account 404** (the isolation test – mandatory).
- `GET /rates`, `/rates/pack`, `/catalog`: correctness, immutable caching headers, ETag.
- `POST /feedback`: rate limit, size cap, anonymous + authenticated.
- `POST /extract`: quota 402/429 paths, image cap; transient-processing asserted (no persistence side effects).
- `DELETE /account` + devices: 410 propagation, purge-after-grace job.

## Per-function golden suites (L1 – the algorithm core)

1. **Consumption engine**: D1–D4 four-drivers outputs verbatim; edit-cases (volume edit shifts headline, isFull split/merge, date reorder); window floor/extension labels; distance-weighted (not mean-of-per100s) check; conflict-flag exclusion; tank-level adjustment.
2. **Timeline validation**: order/pace matrix, receipt-date priority, save-anyway flagging.
3. **Receipt parser** (exists in Spike): keep green, grow with every OCR bug fixed – each fix adds its fixture.
4. **Money/conversion**: the S8/J10 suite above.
5. **Cross-check + mixed-receipt detection**: tolerance boundaries, line-vs-total.
6. **Importer per format**: round-trips + known-value assertions.
7. **Backup format**: round-trip + schema-version migrator test (v1→v2 fixture from day one, so additive evolution stays honest).

## CI gates (what blocks merge)

All L1 green · L2 green (backend PRs) · L4 snapshots reviewed-or-green · L5 accuracy not below the recorded high-water mark (ratchet, never regress) · SwiftLint/dotnet-format · pseudo-localization build (no hardcoded strings) · the ERRORS.md 3-question audit for any new user-facing message (reviewed in PR description).
