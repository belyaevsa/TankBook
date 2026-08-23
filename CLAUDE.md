# Tankbook (fuel-counter-ios)

Capture-first car cost log: iOS native (SwiftUI) + C#/ASP.NET Core backend with PostgreSQL. Local-first; scanning (receipts, pump displays, fiscal QR) replaces typing. This file is the index – **read the referenced doc before working in its area; each doc is the single authority for its domain.**

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
| `docs/SCHEMA.md` | Entities, fields, naming (canonical across Swift/C#/SQL), validation invariants, consumption math, backup format, reference data services, import mappings | Any data model, algorithm, or persistence work |
| `docs/SYNC.md` | Sync protocol, conflict scenarios S1–S8, blob pipeline, encryption stance (decided), offline behavior | Any sync, backend-storage, or attachment work |
| `docs/API.md` | The complete HTTP contract: auth, sync, blobs, reference data, feedback, LLM gateway, account | Any endpoint work, client networking; changes here = breaking-change review |
| `design/screens/*.dc.html` + `canvas.json` | The screen mockups (source of truth for pixels); canvas artifact id `208136b7-4861-4b40-9d05-dcf5067ea123` | Building any screen – match these, don't reinvent |
| `docs/TESTING.md` | Verification levels, per-story/endpoint/function check matrix, CI gates | Writing or skipping any test; defining done |
| `docs/PHASES.md` | Build order and each phase's verifiable exit gate | Planning work; deciding what to build next |
| `docs/TASKS.md` | The task backlog: agent-sized tasks with per-task checks; stable IDs for branches/PRs | Picking up any work item; one task = one PR = code + checks |
| `Spike/ReceiptSpike/` | OCR validation harness + parser reference implementation; its README defines the accuracy gate workflow | OCR/parser work; extending vocabularies |

Conflict rule: if two docs disagree, the more specific one wins (API.md over SYNC.md's sketches; SCHEMA.md over prose in VISION.md) – then fix the stale doc in the same change. Keeping the docs reconciled is part of every task's definition of done.

## Hard rules (violations are bugs, not style)

1. **Local-first**: no feature may require the network except cloud-LLM fallback and cross-device sync/restore. No screen is ever sync-gated. (`docs/SYNC.md`)
2. **Stats are derived, never stored**: full-vehicle recompute on any FillUp change. (`docs/SCHEMA.md` – Recalculation on edit)
3. **Money is a pair**: original + home currency with rate snapshot; `rateDate` = entry date, never "today"; snapshots immutable, backfill fill-blanks-only. (`docs/SCHEMA.md`)
4. **Fuel amount ≠ receipt grand total** on mixed receipts. (`docs/SCHEMA.md` CHECK 3)
5. **Palette semantics**: taillight = fuel/primary, headlight = electric, amber = attention only, red only inside system dialogs; accent is meaning, not chrome. All colors from DESIGN.md tokens – no ad-hoc hex in UI code.
6. **Numbers in DIN, UI text in SF Pro**; units typographically subordinate; `tabular-nums` wherever digits align. (`docs/DESIGN.md`)
7. **Every error names its next step** and survives being ignored; monetization appears in no error surface except the car-limit sheet, and never mid-capture. (`docs/ERRORS.md`)
8. **Nothing lost silently**: tombstones + 30-day undo; sync conflicts surface as badges where data lives, never modals at sync time. (`docs/SYNC.md` S1–S8)
9. **Server validates payload *structure*, never domain *meaning***: envelope, size, and the registered JSON Schema are enforced; no endpoint reads what a field means, and there are no domain queries/search/stats endpoints – such needs are client-side computations. Schema evolution is a data change (registry + declarative transforms), not a backend deploy. (`docs/API.md`, `docs/SYNC.md` → Payload contract)
10. **All user-facing strings** go through String Catalogs (EN + RU from day one), traced to the copy glossary once it exists; no hardcoded text. (`docs/VISION.md` localization)
11. **No secrets in the app bundle, ever** – an IPA is a zip. Tokens and `deviceId` live in the Keychain as `AfterFirstUnlockThisDeviceOnly`; the database and attachments use `completeUntilFirstUserAuthentication` file protection (including `-wal`/`-shm`). API keys stay server-side, which is why the LLM gateway exists. (`docs/SECURITY.md`)
12. **Never log domain values.** Ids, counts, codes, durations and field *names* are loggable; amounts, stations, notes, coordinates, payloads, tokens and images are not – at any level, in any build. (`docs/LOGGING.md`)
13. **It builds and it lints – every task, before anything else counts.** No task is done until each tier it touched compiles and its linter exits **0**: iOS `swift build` + `swiftlint lint` **run from the repo root** (root-relative `excluded:` paths), backend `dotnet build` + `dotnet format --verify-no-changes`. Zero lint *errors* is the standard and is re-checked every task; warnings do not block but are not to be added casually. Never silence a violation by loosening the rule – fix the code, or exclude genuinely generated output. Verify by **exit code**, not by skimming output. (`docs/TESTING.md` → the baseline gate)

## Repo layout & commands

```
docs/                    # all 13 spec documents (see map above)
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
- **Every UI task ships a screenshot** (standing instruction, 2026-08-23): capture the screen it produced from a booted simulator and commit it to `design/screenshots/` as `<task-id>-<screen>.png`, in the **dark** theme (the brand's home theme, `docs/DESIGN.md`) unless the task is specifically about light. This is the one check no test performs – XCUITest asserts behaviour and never colour, which is exactly how P1.1 shipped an accent-red tab bar that violated hard rule 5 while its suite stayed green. Compare the shot against the task's `design/screens/*.dc.html` artboard before committing, and **take it outside a test run** – `simctl` and `xcodebuild test` fight over the device.
- Entity/field names exactly as `docs/SCHEMA.md` spells them, in every language.
- When a task touches a journey, screen, error state, or schema shape that the docs don't cover yet: extend the doc in the same change – the docs are the spec, not documentation-after-the-fact.
