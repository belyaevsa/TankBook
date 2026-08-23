# Tankbook – Build Phases

*The work broken into phases, each with a **verifiable exit gate** – a phase is done when its gate checks pass (`TESTING.md` defines how each check runs), not when its code merges. Phases are sequential for the gates, but work inside them parallelizes (iOS and backend tracks are independent until P4 joins them).*

## P0 · Foundations (everything else builds on this) — **in progress**
Scaffold `ios/` (SwiftUI + GRDB, DESIGN.md tokens as `Theme.swift`, String Catalogs EN/RU wired, GRDB migrations for the full SCHEMA.md model) and `backend/` (ASP.NET Core solution, Postgres + MinIO via docker compose-free scripts, Dapper migrations for the server tables). CI for both (build, lint, test, pseudo-localization). P0 also lays the three cross-cutting foundations that are far cheaper to establish before code accumulates than to retrofit: **payload contract** (P0.10), **logging** (P0.11), and **remote config** (P0.12/P0.13).

**Done (verified by re-running tests outside the implementing agent):** P0.1 scaffold · P0.2 tokens · P0.4 persistence · P0.5 domain · P0.6 consumption · P0.7 validation · P0.8 backend scaffold · P0.9 server migrations · P0.10 payload contract · P0.11 logging · P0.13 config server. iOS 108 tests green, backend 134 green.
**Remaining:** P0.12 remote config client – the last item in the gate, since the brick-proof test is its deliverable.
**Moved out of P0:** P0.3 localization now sits at the head of P1, next to the app shell. `TankbookCore` has almost no user-facing strings – they arrive with the app target – so a P0 pseudo-localization gate would guard a build with nothing to localize. The gate below drops it accordingly; P1's gate picks it up.

**Exit gate:** both projects build in CI from clean checkout · consumption engine passes the D1–D4 golden suite + edit-cases inside the iOS target · schema migrations round-trip a seeded database · `Theme.swift` values byte-match DESIGN.md tokens (generated, not copied) · every entity has a registered v1 payload schema and the round-trip preservation test passes · the redaction test passes on both tiers · **the brick-proof config test passes** (an unreachable `apiBaseUrl` auto-reverts to bundled defaults and the app recovers unattended).

## P1 · Local core loop (a usable app, no camera, no server)
Manual entry (ConfirmManual as the form), Home (garage card, log, guest/empty states), Add car + catalog seed pack, **Vehicle detail with editable per-car settings**, car switcher, Edit entry, Recently deleted, Trends tiles, timeline validation with conflict badges, tank-level sheet.
**Exit gate:** TESTING J1, J13-local, F9a, F1-manual-path checks green · **String Catalogs EN/RU wired and the pseudo-localization CI step failing on a deliberately hardcoded string** (P0.3, moved here) · **every value the app suggests is editable after the fact and a user's edit is never overwritten** (hard rule 13; P1.12) · L4 snapshots for every P1 screen in dark+light, EN+RU · a real month of your My Fuel Manager data (hand-entered or imported early) reproduces its known consumption · SCREENMAP back-path audit holds in XCUITest (no dead ends walk).

## P2 · Capture (the hero)
Vision OCR pipeline productionized from the Spike, all confirm variants (standard/foreign/mixed), fiscal QR, Foundation-Models normalization (gated iOS 26+), confidence gating + tap-to-verify crops, pump-photo mode behind the accuracy flag.
**Exit gate:** L5 corpus gates – receipts at the recorded high-water mark, **pump photos ≥95% or the mode stays off** (VISION rule) · mixed-receipt isolation ≥95% · J3/J4/J5 checks green · M-check: 5 live fill-ups, median capture-to-save < 15 s.

## P3 · Service, expenses, reminders
ServiceEntry with invoice split, parts shelf + linking (double-count invariant), tire sets, reminder lifecycle (J7c state machine), local notifications with multi-device cancellation logic (arming rules per NOTIFICATIONS.md; cancellation testable locally before sync exists).
**Exit gate:** J7/J7b/J7c suites green · cost/km never double-counts a linked part (property test) · reminder state machine covers every transition in SCHEMA.md's lifecycle block.

## P4 · Account, sync, blobs (the join point)
Backend auth (session exchange, refresh rotation), sync push/pull with SCN, the iOS sync client (dirty queue, merge, domain revalidation), blob pipeline, Restoring flow, Settings account states, silent APNs nudges, Sign in + J11a wrong-provider detection.
**Exit gate:** all API.md L2 endpoint suites green (incl. cross-account blob 404 and refresh-reuse revocation) · **L3 scenario suite: one deterministic test per S1–S9 asserting the documented outcome** · restore-from-zero hash-equals origin dataset · kill-the-server chaos check: app fully usable, queues drain on recovery (S7).

## P5 · Reference data, currency, localization, importers
/rates service + daily job + CIS source, Money conversion end-to-end, **the server-curated vehicle catalog** (curation tooling + `GET /catalog` deltas + the client updater), RU localization pass with native review, importers for all six formats, backup export/import UI.

Catalog and rates are the same shape – **server-curated packs, versioned, cached on device, server is master on overlap** (`SYNC.md` → Reference data). P1.2 ships only the bundled seed pack; the update channel lands here, once the backend join point (P4) exists.
**Exit gate:** J10/S8 money suite green · rates job survives weekend/holiday fixtures · **catalog delta applies over the seed pack, a corrected figure reaches a device, and a user's overridden value is provably untouched** · **a malformed or older pack is rejected whole and the previous pack still serves** · importer round-trips green **including your real My Fuel Manager export as a fixture** · RU pseudo-localization + real-device check (no clipped DIN numerals in RU).

## P6 · Polish & ship
Anomaly insights, monthly summary, Pro paywall + LLM gateway fallback (F4 quota UX), the six planned screens from SCREENMAP (Garage root, Vehicle detail, Import wizard, Reminder form, Account & devices, Paywall), accessibility audit, App Store assets EN/RU, TestFlight ring.
**Exit gate:** ERRORS.md coverage walk – every catalogued state reachable and snapshot-tested · accessibility floor verified (Dynamic Type XL, VoiceOver labels per DESIGN.md, contrast) · SCREENMAP has zero planned-not-drawn screens left · TestFlight build passes the M-checklist.

## Working agreement

- A phase may start before the previous one's gate closes **only** for work that doesn't depend on it (e.g. P4 backend endpoints during P2).
- Gates never weaken retroactively; accuracy gates ratchet (TESTING.md).
- Each phase ends with a doc reconciliation pass – whatever the build taught goes back into the owning doc (CLAUDE.md rule).
