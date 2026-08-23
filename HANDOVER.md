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
- **iOS: 148 tests green. Backend: 134 tests green.** (108 → 148 with P0.12a and the JSONValue Unicode regression suite.)

**What does NOT exist yet: any user interface.** There is no app target, so nothing runs in a simulator. That is deliberate – P0 built a tested `TankbookCore` SwiftPM package (domain, persistence, engines, logging, payload contract) that the SwiftUI app will depend on. Tests run natively on macOS in under a second, with no simulator boot, which is why this phase moved quickly.

On simulators: **iOS 26.5 is installed; iOS 18 is not.** Decided 2026-08-23 – build P1 against 26.5 now, validate and adapt to iOS 18 later. The deployment target stays **18.0**, which makes the compiler reject any post-18 API used without an `@available` guard, so the API half of the risk is covered on every build. The uncovered half is appearance and runtime behaviour, and iOS 26 looks different from iOS 18: **L4 snapshot baselines recorded on 26.5 will need re-recording** once the iOS 18 runtime is fetched (`xcodebuild -downloadPlatform iOS` gets only the *latest*, so iOS 18 needs an explicit fetch, ~8 GB). Budget that as known work. Prefer XCUITest behaviour assertions over pixel snapshots where a check can be written either way – they survive the runtime change.

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
| **P0.12** | Remote config client. **Split into P0.12a/b/c** after three single-run attempts delivered zero files – the task was too large for one agent run. **P0.12a is done** (canonicalization, Ed25519 verification, typed document; 29 tests). **P0.12b and P0.12c remain** – see `docs/TASKS.md` for their per-slice checks |
| **P0.3** | String Catalogs EN/RU + pseudo-localization CI. **Recommend moving to P1** – `TankbookCore` has almost no user-facing strings; they arrive with the UI, so doing this now would gate a build with nothing to localize |

## What to do next

1. **Finish or re-dispatch P0.12** (brief: see "Working with agents" below). Its brick-proof test is part of the P0 exit gate in `docs/PHASES.md`.
2. **Install an iOS simulator runtime** if any UI work follows.
3. **Start P1.1 – the app shell** (`docs/TASKS.md` P1 table): tab roots and navigation per `docs/SCREENMAP.md`, depending on `TankbookCore`. This is what makes the simulator meaningful and shortens every later design loop. Move P0.3 here.
4. Then P1.2–P1.11 in order: Add car → manual fill-up form → Home → Log stream → Edit entry → Recently deleted → duplicate detection → tank level → Trends → car switcher.

Before starting any task, read the doc named in its `CLAUDE.md` map row. The docs are the spec, not documentation-after-the-fact: if a task reveals an uncovered case, extend the owning doc in the same change.

## Working with agents (this session used opencode + DeepSeek)

Builder: `opencode run --auto --thinking -m deepseek/deepseek-v4-flash --title "<id>" "$(cat brief.md)"`.
Verifier: same with `deepseek/deepseek-v4-pro`, given an adversarial brief (look for fudged fixtures, vacuous assertions, fake concurrency, wrong algorithms) and told to report only, never fix.
Architecture or security work goes to **pro**, screen implementation against a fixed artboard goes to **flash**.

### The two flags that matter for unattended runs

- **`--auto`** – auto-approves permissions that are not explicitly denied. **Use it for every background dispatch.** In non-interactive `run` mode opencode cannot prompt, so it *auto-rejects* instead, and **a single rejection kills the whole run**. That is exactly how one P0.12 attempt died: it wrote to `/tmp_gen.swift` (note: the filesystem *root*, not `/tmp`) and the run ended instantly. There is no `permission` block in `~/.config/opencode/config.json`, so nothing is explicitly denied and `--auto` covers everything. It does mean an agent could write anywhere, so the repo-only rule stays in the brief as the real boundary.
- **`--thinking`** – shows the model's reasoning blocks. **Use it.** The most expensive failure of this project was a run that spent its entire budget cross-verifying Ed25519 across languages; with thinking exposed that rabbit hole would have been visible in about three minutes and killable, instead of surfacing only when the run ended with zero files. It also makes the long silent stretches legible: without it, the only evidence a run is alive is accumulating CPU time. Cost is log volume – DeepSeek reasoning is verbose. Use `--format json` instead when the goal is programmatic monitoring (structured events beat grepping for "Wrote file successfully").

### Is it working, or is it wedged?

Log silence means nothing on its own – nothing is written during model inference, and quiet stretches of five-plus minutes are normal. **Judge by CPU time, not log freshness:**

```
ps -o pid,etime,time,stat,%cpu -p <pid>
```

A working run shows `STAT R` with `TIME` climbing. A wedged one shows `S`/`S+`, **no child processes**, and frozen `TIME` – that is what the six-hour hung P0.12 run looked like. A useful second signal is the write count (`grep -c "Wrote file successfully"`).

**Set a no-writes threshold before you dispatch** and act on it: three runs died having read everything and written nothing. Roughly 15 minutes with zero writes means kill it and split the task – that is what turned P0.12 from three empty runs into two clean ones.

**Briefs live in `agents/briefs/<task-id>.md` and are written there before dispatch**, not in a temp directory – see that folder's README for the structure. Read the existing ones before writing a new one; every fence in them is there because something went wrong once.

Lessons that cost real runs – put these in every brief:

- **Never write outside the repo.** State it as a whitelist ("only inside `/Users/sbelyaev/repos/fuel-counter-ios`"), never a blacklist: a brief saying "don't write to `/tmp`" was followed by an agent writing to `/tmp_gen.swift` at the filesystem root, which the blacklist did not cover and which ended the run.
- **Size the task to fit one run.** P0.12 delivered nothing three times as a single task – 11 components and 17 required tests – and then went green in two runs once split into a/b/c slices. Nothing about the prompt changed; the size did.
- **Tell them what NOT to explore.** One agent spent an entire run trying to cross-verify Ed25519 between BouncyCastle and CryptoKit. Ed25519 is standardised; the real cross-language risk was canonicalization.
- **Screenshot every UI task before committing it.** `design/screenshots/<task-id>-<screen>.png`, dark theme, captured from a booted simulator and eyeballed against the task's artboard. No test checks colour: P1.1's suite was 8/8 green while the tab bar was accent-red in violation of hard rule 5, and only the screenshot caught it. Commit the image with the task – it is the record of what actually shipped.
- **Re-run the tests yourself, then commit.** Agent reports are mostly accurate but not evidence. Every `[x]` here was re-verified independently, and since 2026-08-23 each verified task gets its own commit naming the task id (`CLAUDE.md` → Conventions). Verify first, commit second – the commit is the record that verification happened, and it gives the next agent a clean base to diff against. Never commit mid-run.
- **Put the baseline gate in every brief, and re-verify it yourself**: the tier builds and `swiftlint lint` (from the **repo root**) exits 0. `CLAUDE.md` hard rule 13. Agents optimise for the checks you name, so an unnamed gate is an unmet one – and check the **exit code**, since agents reliably report "lint passed" after skimming a screen of warnings.
- **Watch out for stale wrapper shells.** `pgrep -f "opencode run"` matches the wrapper shell of the pgrep itself, so naive wait-loops never exit. Use `pgrep -fa "opencode run -m" | grep -v "zsh -c"`.
- Run iOS and backend agents in parallel (separate tiers), but never two on the same tier – they fight over the build lock.
- **Never drive the simulator by hand while UI tests are running.** `simctl launch` / `simctl io screenshot` and an `xcodebuild test` run both take control of the same device, and the test run fails in a way that looks like a real regression – one such red run cost a genuine debugging detour. Take screenshots before or after, never during.
- **UI tests are slow (~100 s) and not free of flakes.** Judge a red run by re-running it once before believing it, and judge a green one by whether anything else was touching the simulator.

## Decisions already made – do not relitigate

Listed in `CLAUDE.md`, but the ones most likely to be re-questioned:

- **Min iOS 18, not 26.** An earlier draft raised it to 26 for `RecognizeDocumentsRequest`; that was reversed because capability tiering already exists for Apple Intelligence, so one more tier is nearly free – while the higher floor would have cost A12 devices and every non-upgrader. **iPhone 12 is a hard requirement.**
- **The deterministic parser is the quality floor, not a fallback.** Foundation Models needs A17 Pro + 8 GB, which excludes even the iPhone 15/15 Plus. Tier 2 ships only if it strictly beats rules-only.
- **Backend is the sync hub; CloudKit is not used.** One protocol serving iOS now and Android later.
- **TLS + at-rest encryption, no E2E in v1** (signed off) – E2E plus multi-device plus recovery needs user-held keys, the exact UX that loses people their data.
- **GRDB, not SwiftData.** Full SQL control for the custom sync engine.
- **Server validates payload structure, never domain meaning.** Schema evolution is a data change (DB-registered JSON Schemas + declarative transforms), not a deploy.

## Known open items (not blocking P0)

0. **Odometer digits are not thousands-grouped.** `AddVehicle.dc.html` specifies `119&thinsp;486 km`; the app renders `119486`. Found by screenshot-vs-artboard on P1.2, not by any test. The honest fix is format-on-blur (a grouped `TextField` is unpleasant to type into), so it was left out of P1.2 rather than destabilising a verified tree. **Do it in P1.4**, where Home displays the same figure and grouping matters most – and make it a shared formatter, since odometer appears on Home, Log, Edit entry and Trends.

1. **The API shuts down when Postgres is unreachable** (retries ~4 times then exits). For a product whose story is "the server being down is a non-event", it should start degraded and report unhealthy instead. Flagged for P4.
2. **`JsonSchema.Net` is pinned to 4.1.8** – the last MIT-licensed release; 5.0+ moved to a paid licence. Revisit as a dependency risk.
3. **Migration 003 seeds config v1 with an empty signature placeholder**, signed at startup by `ConfigBaselineSeeder`. Confirm the client rejects that transient unsigned state correctly when P0.12 lands.
4. ~~**Cross-language canonicalization parity is untested end to end.**~~ **Closed 2026-08-23.** The C# canonicalizer + BouncyCastle Ed25519 were run over a deliberately awkward document (`1e3`, an integer above 2^53, Cyrillic text, keys out of order, empty object, mixed array); CryptoKit verifies the resulting signature and rejects both tamper cases. Fixture checked in at `ios/Tests/TankbookCoreTests/Fixtures/config/` with its provenance in that directory's `README.md`. **The remaining risk was never the curve – it is rule 5, number source-token preservation.** Do not let another agent re-investigate Ed25519.
5. ~~**iOS CI lint is red.**~~ **Fixed 2026-08-23** – `swiftlint lint` now exits 0, so the CI Lint step passes. It had **13 errors**, and the largest cause was a config bug: `excluded:` listed `.build` and `ios/.build` individually, so `Spike/ReceiptSpike/.build` was linted and SwiftPM's *generated* test runner failed on line length. Now `"**/.build"`. The rest were real: `JSONSchemaValidator.validate` (complexity 31, 110-line body) split into four keyword-family helpers, the schema generator's `required` lists de-duplicated behind `entryCommonRequired`, and the Spike parser's 5-member tuple replaced with a named `Candidate` type. 232 warnings remain and are not gating. **Keep it at zero** – a lint that has been red for a while is a lint nobody reads.

6. **Non-ASCII is a first-class test input now, not an afterthought.** `JSONValue.parse` rejected *every* multi-byte UTF-8 string until 2026-08-23 – a Cyrillic station name could not be decoded at all – and the whole suite stayed green because every payload fixture was ASCII. Fixed, with `JSONValueUnicodeTests.swift` as the regression suite and a test that fails if the fixture corpus ever goes all-ASCII again. `docs/TESTING.md` now requires 2-, 3- and 4-byte UTF-8 in the corpus. **Assume other ASCII-only blind spots exist** in code written before this date.

7. **Nothing is committed to git.** The whole session's work is staged/untracked; `git status` shows modified docs and untracked `ios/`, `backend/`, `docs/schemas/`, `docs/fixtures/`.

## The document set

`CLAUDE.md` is the operating manual and index. Under `docs/`: VISION, COMPETITORS, DESIGN, JOURNEYS, SCREENMAP, ERRORS, LOGGING, SECURITY, CONFIG, NOTIFICATIONS, SCHEMA, SYNC, API, TESTING, PHASES, TASKS. Screens are `.dc.html` artboards in `design/screens/` (canvas artifact `208136b7-4861-4b40-9d05-dcf5067ea123`). The OCR validation harness is `Spike/ReceiptSpike/`.
