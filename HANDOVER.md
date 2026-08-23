# Tankbook – Session Handover

*Written 2026-08-23. Read this first in a fresh session, then `CLAUDE.md` for the rules and `docs/TASKS.md` for the backlog with live status marks.*

## What this project is

A capture-first car cost log: iOS native (SwiftUI, min iOS 18, reference device iPhone 12) plus a C#/ASP.NET Core + PostgreSQL backend. Scanning receipts, pump displays and fiscal QR codes replaces typing. Local-first: the app is fully usable with no account and with the server unreachable.

The product thesis and the competitive gap are in `docs/VISION.md`; the market research behind it is in `docs/COMPETITORS.md`.

## Does it work? Yes – within its current scope

Demonstrated by actually running it on 2026-08-23, not by assertion:

- **Backend serves real traffic against real Postgres.** `bash backend/scripts/dev-up.sh` then `dotnet run --project src/Tankbook.Api`: migrations apply, `GET /health` → `{"status":"ok"}`, `GET /v1/config` returns a signed document **with no auth**, and `If-None-Match` returns **304**.
- **Trace correlation works end to end.** A client-supplied `X-Tankbook-Trace` id is echoed in the response header and appears in the server's structured log line. (Note: `/health` logs at DEBUG only by design, so probe `/v1/config` when checking this.)
- **The consumption engine reproduces the golden vectors** – all four driver profiles (D1–D4) and the three edit cases, verified in CI-style runs.
- **iOS: 108 tests green. Backend: 134 tests green.**

**What does NOT exist yet: any user interface.** There is no app target, so nothing runs in a simulator. That is deliberate – P0 built a tested `TankbookCore` SwiftPM package (domain, persistence, engines, logging, payload contract) that the SwiftUI app will depend on. Tests run natively on macOS in under a second, with no simulator boot, which is why this phase moved quickly.

Also note: **no iOS simulator runtime is installed on this machine** (`xcrun simctl list runtimes` is empty). Before any UI work: `xcodebuild -downloadPlatform iOS` (several GB), and ideally an iOS 18 runtime too, since iOS 18 is our floor and testing the floor is the point of declaring one.

## Where the work stands

**Phase 0: 11 of 13 tasks complete.** Status marks live in `docs/TASKS.md` (`[x]` = done *and independently re-verified by re-running the tests outside the implementing agent*).

| Done | |
|---|---|
| P0.1 | iOS scaffold – SwiftPM package, GRDB 7.11.1, SwiftLint with custom hex rules, CI |
| P0.2 | Design tokens – `design/tokens.json` → generated `Theme.generated.swift`, parity test |
| P0.4 | GRDB persistence – 13 tables, Decimal-exact (stored as TEXT), tombstones, repository |
| P0.5 | Domain types – real RFC 9562 UUIDv7, `Money` snapshot semantics, all entities |
| P0.6 | Consumption engine – segments, 90-day/floor-3 headline, distance-weighted |
| P0.7 | Timeline validation – order, pace, cross-check, receipt-date priority |
| P0.8 | Backend scaffold – minimal API, health, options binding, dev scripts (plain `docker run`) |
| P0.9 | Server migrations – 9 tables, migration runner, atomic SCN allocator |
| P0.10 | Payload contract – 11 JSON Schemas + fixtures, iOS codec, server registry + validator + declarative transforms |
| P0.11 | Logging – backend structured JSON + redactor; iOS OSLog, mutation pairs, breadcrumbs |
| P0.13 | Config server – signed documents, ETag/304, publish monotonicity |

| Outstanding | |
|---|---|
| **P0.12** | Remote config client. **In flight at handover** – first attempt produced nothing (burned its run cross-verifying Ed25519 across languages); re-dispatched with that rabbit hole explicitly closed. Check `ios/Sources/TankbookCore/Config/` exists and `swift test` exceeds 108 before trusting it |
| **P0.3** | String Catalogs EN/RU + pseudo-localization CI. **Recommend moving to P1** – `TankbookCore` has almost no user-facing strings; they arrive with the UI, so doing this now would gate a build with nothing to localize |

## What to do next

1. **Finish or re-dispatch P0.12** (brief: see "Working with agents" below). Its brick-proof test is part of the P0 exit gate in `docs/PHASES.md`.
2. **Install an iOS simulator runtime** if any UI work follows.
3. **Start P1.1 – the app shell** (`docs/TASKS.md` P1 table): tab roots and navigation per `docs/SCREENMAP.md`, depending on `TankbookCore`. This is what makes the simulator meaningful and shortens every later design loop. Move P0.3 here.
4. Then P1.2–P1.11 in order: Add car → manual fill-up form → Home → Log stream → Edit entry → Recently deleted → duplicate detection → tank level → Trends → car switcher.

Before starting any task, read the doc named in its `CLAUDE.md` map row. The docs are the spec, not documentation-after-the-fact: if a task reveals an uncovered case, extend the owning doc in the same change.

## Working with agents (this session used opencode + DeepSeek)

Builder: `opencode run -m deepseek/deepseek-v4-flash --title "<id>" "$(cat brief.md)"`.
Verifier: same with `deepseek/deepseek-v4-pro`, given an adversarial brief (look for fudged fixtures, vacuous assertions, fake concurrency, wrong algorithms) and told to report only, never fix.

Lessons that cost real runs – put these in every brief:

- **Never write to `/tmp`** – it is auto-rejected and three agents burned their budgets on it. Tell them to use a path inside the repo and delete it.
- **Tell them what NOT to explore.** One agent spent an entire run trying to cross-verify Ed25519 between BouncyCastle and CryptoKit. Ed25519 is standardised; the real cross-language risk was canonicalization.
- **Re-run the tests yourself.** Agent reports are mostly accurate but not evidence. Every `[x]` here was re-verified independently.
- **Watch out for stale wrapper shells.** `pgrep -f "opencode run"` matches the wrapper shell of the pgrep itself, so naive wait-loops never exit. Use `pgrep -fa "opencode run -m" | grep -v "zsh -c"`.
- Run iOS and backend agents in parallel (separate tiers), but never two on the same tier – they fight over the build lock.

## Decisions already made – do not relitigate

Listed in `CLAUDE.md`, but the ones most likely to be re-questioned:

- **Min iOS 18, not 26.** An earlier draft raised it to 26 for `RecognizeDocumentsRequest`; that was reversed because capability tiering already exists for Apple Intelligence, so one more tier is nearly free – while the higher floor would have cost A12 devices and every non-upgrader. **iPhone 12 is a hard requirement.**
- **The deterministic parser is the quality floor, not a fallback.** Foundation Models needs A17 Pro + 8 GB, which excludes even the iPhone 15/15 Plus. Tier 2 ships only if it strictly beats rules-only.
- **Backend is the sync hub; CloudKit is not used.** One protocol serving iOS now and Android later.
- **TLS + at-rest encryption, no E2E in v1** (signed off) – E2E plus multi-device plus recovery needs user-held keys, the exact UX that loses people their data.
- **GRDB, not SwiftData.** Full SQL control for the custom sync engine.
- **Server validates payload structure, never domain meaning.** Schema evolution is a data change (DB-registered JSON Schemas + declarative transforms), not a deploy.

## Known open items (not blocking P0)

1. **The API shuts down when Postgres is unreachable** (retries ~4 times then exits). For a product whose story is "the server being down is a non-event", it should start degraded and report unhealthy instead. Flagged for P4.
2. **`JsonSchema.Net` is pinned to 4.1.8** – the last MIT-licensed release; 5.0+ moved to a paid licence. Revisit as a dependency risk.
3. **Migration 003 seeds config v1 with an empty signature placeholder**, signed at startup by `ConfigBaselineSeeder`. Confirm the client rejects that transient unsigned state correctly when P0.12 lands.
4. **Cross-language canonicalization parity is untested end to end** – Swift and C# each test their own side. Add a real parity test in P4 when the client first talks to the server.
5. **Nothing is committed to git.** The whole session's work is staged/untracked; `git status` shows modified docs and untracked `ios/`, `backend/`, `docs/schemas/`, `docs/fixtures/`.

## The document set

`CLAUDE.md` is the operating manual and index. Under `docs/`: VISION, COMPETITORS, DESIGN, JOURNEYS, SCREENMAP, ERRORS, LOGGING, SECURITY, CONFIG, NOTIFICATIONS, SCHEMA, SYNC, API, TESTING, PHASES, TASKS. Screens are `.dc.html` artboards in `design/screens/` (canvas artifact `208136b7-4861-4b40-9d05-dcf5067ea123`). The OCR validation harness is `Spike/ReceiptSpike/`.
