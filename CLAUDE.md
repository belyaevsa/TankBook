# Tankbook (fuel-counter-ios)

Capture-first car cost log: iOS native (SwiftUI) + C#/ASP.NET Core backend with PostgreSQL. Local-first; scanning (receipts, pump displays) **reduces** typing - it never replaces it, and **typing is a peer entry path, never a fallback** (hard rule 15). This file is the index – **read the referenced doc before working in its area; each doc is the single authority for its domain.**

**Starting a fresh session? Read `HANDOVER.md` first** – it carries current status, what to do next, and the traps that cost previous runs.

## Document map (authority order)

| Doc | Single authority for | Consult before |
|---|---|---|
| `docs/VISION.md` | Product scope, feature phases (MVP/v1.x/later), positioning, monetization principles, OCR pipeline decision | Adding/cutting any feature; roadmap questions |
| `docs/COMPETITORS.md` | Market context, store-page profiles, what incumbents do/lack | Positioning claims; "does anyone else do X" |
| `docs/DESIGN.md` | Visual language: Night Drive palette tokens, DIN/SF typography, layout & IA rules, motion, accessibility floor | Writing ANY UI code or screen; color/type decisions |
| `docs/JOURNEYS.md` | User journeys (J1–J13) and failure journeys (F1–F10) with success metrics | Implementing any flow; deciding UX behavior |
| `docs/SCREENMAP.md` | Navigation graph, back-path conventions, screen inventory incl. the six planned-not-drawn screens | Adding/wiring any screen; navigation code |
| `docs/ERRORS.md` | Every error/warning per screen + its next step; severity vocabulary; the 3-question audit rule | Writing any error handling or user-facing message |
| `docs/LOGGING.md` | What each tier logs, the three privacy classes, trace correlation, diagnostics export, retention | Adding any log line, error handler, or telemetry |
| `docs/CONFIG.md` | Remote config: the three precedence layers, `apiBaseUrl` guardrails and auto-revert, delivery by poll with push as a hint | Adding a remote flag, changing endpoints, anything that must ship without an App Store release |
| `docs/SECURITY.md` | Threat model, where every secret lives (Keychain classes, file protection, server secret store), transport, enforcement checks | Touching auth, tokens, storage of anything sensitive, or adding a dependency that wants a key |
| `docs/NOTIFICATIONS.md` | Notification delivery (local vs silent APNs), scenario catalog, multi-device cancellation, permission timing | Any notification, background-refresh, or push work |
| `docs/EXTRACTION.md` | The recognition pipeline: image -> OCR -> role assignment -> cross-check -> pre-fill; the four cross-check outcomes; named failure modes with their fixtures; where a trained model does and does not belong | Any OCR, parser, confirm-prefill or capture-accuracy work |
| `docs/SCHEMA.md` | Entities, fields, naming (canonical across Swift/C#/SQL), validation invariants, consumption math, backup format, reference data services, import mappings | Any data model, algorithm, or persistence work |
| `docs/SYNC.md` | Sync protocol, conflict scenarios S1–S8, blob pipeline, encryption stance (decided), offline behavior | Any sync, backend-storage, or attachment work |
| `docs/API.md` | The complete HTTP contract: auth, sync, blobs, reference data, feedback, LLM gateway, account | Any endpoint work, client networking; changes here = breaking-change review |
| `design/screens/*.dc.html` + `canvas.json` (v2 work under `design/screens/v2/`) | The screen mockups (source of truth for pixels); canvas artifact id `208136b7-4861-4b40-9d05-dcf5067ea123` | Building any screen – match these, don't reinvent |
| `docs/AGENT.md` | **[v2]** The Car Agent (Pro): device-hosted agent loop, tool catalogue, `/agent/turn` as the second rule-9 exception, diagnosis safety framing, the Ask tab, the answer gate | Any chat, LLM-over-user-data, assistant or "AI" feature; anything that sends car data to a model |
| `docs/PRACTICES.md` | Mobile+backend integration practices (architecture, network UX, security, debuggability), the constants-placement policy (compiled / remote / user / frozen), and the dated review of the code against them with its task list | Adding a timeout, limit, threshold or any tunable number; networking, auth-refresh, diagnostics or error-envelope work; phase-gate reviews |
| `docs/TESTING.md` | Verification levels, per-story/endpoint/function check matrix, CI gates | Writing or skipping any test; defining done |
| `docs/PHASES.md` | Build order and each phase's verifiable exit gate | Planning work; deciding what to build next |
| `docs/TASKS.md` | The task backlog: agent-sized tasks with per-task checks; stable IDs for branches/PRs | Picking up any work item; one task = one PR = code + checks |
| `Spike/ReceiptSpike/` | OCR validation harness + parser reference implementation; its README defines the accuracy gate workflow | OCR/parser work; extending vocabularies |

## Version scope (convention, 2026-08-29)

Every task, journey, screen and principle in these docs belongs to exactly one version, and the
marker says which. **Unmarked = v1.** The vocabulary:

| Marker | Means | Where the list lives |
|---|---|---|
| **v1** (unmarked) | The launch build: phases P0–P6 and the blocker/required tiers of the launch triage. Everything built as of 2026-08-29 ships in it, including service, reminders and sync – `VISION.md` planned those as v1.x, the build got ahead of the plan | `docs/TASKS.md` → Launch triage, tiers 1–2 |
| **[v1.0.x]** | First patch releases after launch: debuggability, maintenance, doc drift. No user-visible feature | Launch triage, tier 3 row 1 |
| **[v1.1]** / **[v1.x]** | Point releases on the v1 architecture: journey opportunities (→), the other importers, service/parts/reminder depth, EV charging | Launch triage, tier 3 |
| **[v2]** | The Pro tier and what it pays for: the Car Agent (`docs/AGENT.md`), the paywall and tier journeys, family sharing (J12), document wallet. Its own phase (P7 in `PHASES.md`), its own section (AG) in the backlog, its own canvas page and `design/screens/v2/` | `docs/AGENT.md` §11, `docs/TASKS.md` → AG |

Hard rules are v1 unless the rule text carries a marker (rule 9's second exception is `[v2]`).
A doc section, journey heading or task row that applies beyond v1 carries the marker in bold at
its start; a row without one is a v1 commitment. When a v2 item becomes a v1 one (or the
reverse), move the marker and say why in the same change.

Conflict rule: if two docs disagree, the more specific one wins (API.md over SYNC.md's sketches; SCHEMA.md over prose in VISION.md) – then fix the stale doc in the same change. Keeping the docs reconciled is part of every task's definition of done.

## Hard rules (violations are bugs, not style)

1. **Local-first**: no feature may require the network except cloud-LLM fallback, cross-device
   sync/restore, and **third-party import parsing** (amended 2026-08-27, see rule 9). No screen is
   ever sync-gated. The exception is bounded to the parse: **everything else about import is
   local** - the review list, the edits, the commit, and every entry it writes. An offline user
   cannot import a foreign file; they lose nothing else. (`docs/SYNC.md`)
2. **Stats are derived, never stored**: full-vehicle recompute on any FillUp change. (`docs/SCHEMA.md` – Recalculation on edit)
3. **Money is a pair**: original + home currency with rate snapshot; `rateDate` = entry date, never "today"; snapshots immutable, backfill fill-blanks-only. (`docs/SCHEMA.md`)
4. **Fuel amount ≠ receipt grand total** on mixed receipts. (`docs/SCHEMA.md` CHECK 3)
5. **Palette semantics**: taillight = fuel/primary, headlight = electric, amber = attention only, red only inside system dialogs; accent is meaning, not chrome. All colors from DESIGN.md tokens – no ad-hoc hex in UI code.
6. **Numbers in DIN, UI text in SF Pro**; units typographically subordinate; `tabular-nums` wherever digits align. (`docs/DESIGN.md`)
7. **Every error names its next step** and survives being ignored; monetization appears in no error surface except the car-limit sheet, and never mid-capture. (`docs/ERRORS.md`)
8. **Nothing lost silently**: tombstones + 30-day undo; sync conflicts surface as badges where data lives, never modals at sync time. (`docs/SYNC.md` S1–S8)
9. **Server validates payload *structure*, never domain *meaning*** – with **one named exception**:
   envelope, size, and the registered JSON Schema are enforced; no endpoint reads what a field
   means, and there are no domain queries/search/stats endpoints – such needs are client-side
   computations. Schema evolution is a data change (registry + declarative transforms), not a
   backend deploy. (`docs/API.md`, `docs/SYNC.md` → Payload contract)
   **The exception (amended 2026-08-27, product owner): third-party import parsing.** `POST
   /import/parse` reads a foreign file - an MFM CSV, later others - and *interprets* it, because
   one parser serving every client and fixable without an App Store release was judged worth the
   cost. It is deliberately the **narrowest possible** shape, and these five properties are what
   keep it from becoming a general domain server:
   - **Pure function.** It returns *candidate* records and commits nothing. The device reviews,
     edits and writes; the server owns no user data and no account state changes.
   - **Stored, deliberately, and unlike the LLM gateway.** The uploaded file and its parse result
     live in blob storage so the row-by-row review can be resumed and a bad parse can be
     re-examined (product owner, 2026-08-27). This is a **deliberate asymmetry**: `/extract` never
     stores an image, `/import/parse` does store a file. Both are signed off; neither licenses the
     other. **Retention is 30 days**, matching the tombstone/undo window so one number governs "how long
     can I get it back" - a written commitment in `docs/SECURITY.md`, not an implementation detail.
   - **Commits nothing, account or not.** No sign-in required: import must work for a user with no
     account, or the exception would quietly drag rule 1 further than agreed. Stored under the
     device identity when there is no account.
   - **Nothing is logged but shape.** Format name, row counts, error counts. Never a station, a
     note, an amount or a coordinate (hard rule 12).
   - **It does not spread.** This exception licenses import parsing and nothing else. A second
     endpoint that reads domain meaning needs its own decision, written here.
   **[v2] The second exception (decided 2026-08-29, product owner): the Car Agent's `POST
   /agent/turn`** (`docs/AGENT.md` §2.1). Same shape, three differences: it **stores nothing**
   (the device holds the conversation), it **requires an account** because it is Pro-metered
   per turn, and it reads only what the device's own tools returned for that turn. Pure
   function; shape-only logging; it does not spread – no server-side search, stats or memory.
10. **All user-facing strings** go through String Catalogs (EN + RU from day one), traced to the copy glossary once it exists; no hardcoded text. (`docs/VISION.md` localization)
11. **No secrets in the app bundle, ever** – an IPA is a zip. Tokens and `deviceId` live in the Keychain as `AfterFirstUnlockThisDeviceOnly`; the database and attachments use `completeUntilFirstUserAuthentication` file protection (including `-wal`/`-shm`). API keys stay server-side, which is why the LLM gateway exists. (`docs/SECURITY.md`)
12. **Never log domain values.** Ids, counts, codes, durations and field *names* are loggable; amounts, stations, notes, coordinates, payloads, tokens and images are not – at any level, in any build. (`docs/LOGGING.md`)
13. **The app suggests, the user decides.** Every value the app derives for the user – catalog pre-fills (tank capacity, battery size, fuel kinds, powertrain), locale-guessed currency and units, OCR-extracted fields, the "last known" odometer – is a **default input, never a fact**. Each one must be editable **at the moment it is offered and again afterwards** (per-car settings live on the car in the Garage, `docs/DESIGN.md`). Once a user changes one, that value is **theirs permanently**: no catalog update, sync merge, re-scan or later curation may overwrite it (`docs/SYNC.md` → Reference data). A screen that pre-fills a value it will not let the user change is a bug, and so is one that only lets them change it once.
15. **Two doors, always: type it or scan it.** Adding an entry manually and capturing one are
    **peer paths of equal standing**, offered side by side at every entry point - never
    "scan, and type only if scanning failed". A camera-first design punishes the user every
    time the camera cannot deliver, and the corpus says that is often: receipts extract at
    **38.3%**, pump displays at **0%**, Vision misreads a digit at **confidence 1.00**, and a
    fiscal QR is present on only **9 of 16** real receipts and carries just 2 of the 5 fields.
    A capture is therefore a **head start, not an answer**: whatever it produces is a default
    input the user edits (rule 13), so a poor scan degrades to "correct two fields", never to
    "start over". Any screen that makes manual entry harder to reach than capture, or that
    frames it as the failure branch, is a bug.

14. **It builds and it lints – every task, before anything else counts.** No task is done until each tier it touched compiles and its linter exits **0**: iOS `swift build` + `swiftlint lint` **run from the repo root** (root-relative `excluded:` paths), backend `dotnet build` + `dotnet format --verify-no-changes`. Zero lint *errors* is the standard and is re-checked every task; warnings do not block but are not to be added casually. Never silence a violation by loosening the rule – fix the code, or exclude genuinely generated output. Verify by **exit code**, not by skimming output. (`docs/TESTING.md` → the baseline gate)

## Repo layout & commands

```
docs/                    # all 14 spec documents (see map above)
design/screens/          # .dc.html artboards + canvas.json (edit → re-seed canvas per session notes)
Spike/ReceiptSpike/      # Swift package: OCR harness. Build/test:
                         #   cd Spike/ReceiptSpike && swift test
                         #   swift run ReceiptSpike <folder-of-images> [--dump-text]
ios/                     # SwiftPM package TankbookCore – domain, persistence (GRDB), engines.
                         #   cd ios && swift build && swift test
                         #   The SwiftUI app target lands in P1.1 and depends on this package.
backend/                 # ASP.NET Core solution implementing API.md; Postgres + MinIO for local dev
                         #   cd backend && dotnet build && dotnet test
                         #   backend/scripts/dev-up.sh starts Postgres + MinIO (plain docker run, no compose)
design/tokens.json       # machine-readable design system → generates ios/…/Theme.generated.swift
design/screenshots/      # one committed screenshot per UI task – the visual record (Conventions)
agents/briefs/           # one brief per dispatched agent task, written BEFORE dispatch
project.yml              # XcodeGen spec → Tankbook.xcodeproj (generated, gitignored)
                         #   xcodegen generate
                         #   xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
                         #     -destination 'platform=iOS Simulator,name=iPhone 17' build|test
```

Golden test vectors: the four-drivers simulation outputs (D1–D4, in `docs/SCHEMA.md` → consumption; script in scratch history) are the reference values for consumption unit tests, plus the named edit-cases.

## Decisions already made – do not relitigate

Night Drive palette · Home C/Confirm A/Trends B screen set · rolling-90-day/floor-3 consumption model (time-based, not fill-count) · backend as sync hub (no CloudKit) · TLS + at-rest encryption, no E2E in v1 (signed off) · S3-compatible blob storage, provider-agnostic · no account linking in v1 · sign-in IS registration · free tier: multiple cars, export always free, no retroactive limit changes.

**XcodeGen generates the app project** (decided 2026-08-23, when P1.1 needed an app target and SwiftPM proved unable to produce an iOS `.app`). `project.yml` at the repo root is the source of truth; `Tankbook.xcodeproj` is **generated and gitignored, never committed**. Reasons: a readable YAML file can be edited correctly by an agent or a human, whereas `project.pbxproj` is a generated-looking format with cross-referenced UUIDs that both edit unreliably and that conflicts on every merge – and every new screen touches it. Run `xcodegen generate` after changing `project.yml` or adding files; CI does the same before building. Tuist was considered and rejected as heavier than a single-app project needs.

**Develop against the iOS 26.5 simulator now; validate and adapt to iOS 18 later** (decided 2026-08-23). The **deployment target stays 18.0** – that is unchanged and non-negotiable, and it is also the safety net: with a 18.0 target, calling an API newer than iOS 18 without an `@available` guard is a *compile error*, so the compiler catches the API half of this on every build. What it does not catch is **runtime and appearance drift**, and iOS 26 ships a different default look than iOS 18. So: **L4 snapshot baselines recorded on 26.5 are not valid for 18 and will need re-recording** when the iOS 18 runtime is installed. Treat snapshot baselines as runtime-specific artefacts, and do not read a green snapshot suite as evidence the app is correct on the floor. iPhone 12 / iOS 18 remains a hard requirement (`docs/VISION.md`).

No open architecture questions remain – the decided list above plus GRDB (persistence) and silent APNs nudges (notifications) covers everything. New questions get resolved with the user, then recorded here and in the owning doc.

## Conventions

- En-dashes only, never em-dashes, in all prose and UI copy.
- No git worktrees; work in the checkout.
- **Commit after each agent task completes and is independently verified** (standing instruction, 2026-08-23). One task = one commit, message naming the task id. **Verify first, commit second**: the baseline gate (build + `swiftlint lint` exit 0) and the task's own checks must pass in *your* hands, not the agent's report – a commit is the record that verification happened. Never commit while an agent is mid-run: the tree contains half-written files, and the point of the commit is a known-good state. Agents themselves still never commit.
- **The full UI suite runs at PHASE completion, not after every task** (standing instruction,
  2026-08-29). Per task: `swift build` and `swiftlint` continuously, all 873 unit tests (30 s, never
  subsetted), and only the UI suites the task touched via `-only-testing:`. Measured cost of the old
  habit: five full runs in one day, ~2h15m, one genuine defect, two false reds from contention.
  A brief must NAME the suites it expects to run. Check the count is non-zero - a `--filter` matching
  nothing prints "0 tests ... passed". Full details and the trade-off: `docs/TESTING.md`.
- **Validation runs on a `deepseek-v4-pro` agent, not in the orchestrator's own session**
  (standing instruction, 2026-08-24). Dispatch `agents/briefs/VALIDATE.md` with the task id and
  path filled in. Two things do not change: **read the validator's captured exit codes, not its
  prose** - a validator's summary is still an agent report, and the raw `echo $?` output is the
  evidence; and **the orchestrator still opens every screenshot personally**, because agents
  have no image input and cannot see what they produced. Colour, truncation and layout are
  caught by nothing else.
- **Health-check every dispatch ~5 minutes in** (standing instruction, 2026-08-23): `scripts/agent-health.sh <task-id> <logfile>`. Roughly **one dispatch in four comes up dead** – the process exists but holds no network connection, burns almost no CPU and never writes a byte of log, and it stays that way indefinitely (one such run sat for six hours). Both observed cases recovered on an immediate re-dispatch of the **same** brief, so treat it as provider flakiness: kill and retry, do not rewrite the brief. The decisive signal is **log bytes** – a healthy run writes ~17 KB in its first 30 seconds, a wedged one is still at 0 after 25 minutes. Log *freshness* proves nothing on its own: nothing is written during model inference, so multi-minute silences are normal.
- **Every agent brief is written to `agents/briefs/<task-id>.md` before dispatch** (standing instruction, 2026-08-23), never to a temp directory. The brief is the record of what the agent was actually asked to do – without it you cannot tell a bad agent from a bad brief, and every fence in there exists because something went wrong once. See `agents/briefs/README.md` for the structure these converged on.
- **Every UI task ships a screenshot in EN *and* RU** (standing instruction, 2026-08-23): capture from a booted simulator and commit to `design/screenshots/` as `<task-id>-<screen>.png` and `<task-id>-<screen>-ru.png`, in the **dark** theme (the brand's home theme, `docs/DESIGN.md`) unless the task is specifically about light. RU needs no device change: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`. RU is not a formality – Russian runs 20-30% longer than English and **short strings expand worst** (`Fix` → `Исправить` is 3×, `Log` → `Журнал` is 2×), which is exactly what overflows tab labels, chips and the action affordance on an error row. A truncated next step also breaks hard rule 7. The RU pass on P1.4 caught a grammar bug no test could: `"%@ spend"` composed as `"%@ расходы"` rendered "АВГУСТ РАСХОДЫ", word-order nonsense - **composed strings need a full localised phrase per language, never concatenation**. This is the one check no test performs – XCUITest asserts behaviour and never colour, which is exactly how P1.1 shipped an accent-red tab bar that violated hard rule 5 while its suite stayed green. Compare the shot against the task's `design/screens/*.dc.html` artboard before committing, and **take it outside a test run** – `simctl` and `xcodebuild test` fight over the device.
- Entity/field names exactly as `docs/SCHEMA.md` spells them, in every language.
- When a task touches a journey, screen, error state, or schema shape that the docs don't cover yet: extend the doc in the same change – the docs are the spec, not documentation-after-the-fact.
