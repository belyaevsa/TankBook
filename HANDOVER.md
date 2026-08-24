# Tankbook – Session Handover

*Rewritten 2026-08-24 at the end of the P1 session. Read this first, then `CLAUDE.md` for the rules and `docs/TASKS.md` for the backlog with live status marks.*

## What this project is

A capture-first car cost log: iOS native (SwiftUI, min iOS 18, reference device iPhone 12) plus a C#/ASP.NET Core + PostgreSQL backend. Scanning receipts, pump displays and fiscal QR codes replaces typing. Local-first: fully usable with no account and with the server unreachable.

Product thesis: `docs/VISION.md`. Market research: `docs/COMPETITORS.md`.

## Does it work? Yes – there is a real app now

Verified by running it, not by assertion:

- **The app runs in the simulator and every P1 screen is built**: Home (garage card, vitals, log stream), Add car, manual fill-up, Edit entry, Recently deleted, duplicate detection, tank level, Trends, car switcher, Vehicle detail.
- **iOS: 305+ unit tests, 59 UI tests** executed against a booted iPhone 17 / iOS 26.5 simulator. **Backend: 134 tests.** `swiftlint lint` exits **0** from the repo root.
- **Backend serves real traffic against real Postgres** – `bash backend/scripts/dev-up.sh`, then `dotnet run --project src/Tankbook.Api`: migrations apply, `GET /health` → `{"status":"ok"}`, `GET /v1/config` returns a signed document with no auth, `If-None-Match` → 304.
- **The consumption engine reproduces the D1–D4 golden vectors**, re-checked after every change that touched it.

Screenshots of every screen, EN and RU, are committed in `design/screenshots/`.

## Where the work stands

**P1 is 12 of 13 tasks done.** Status marks live in `docs/TASKS.md` (`[x]` = done *and independently re-verified outside the implementing agent*).

| Phase | State |
|---|---|
| **P0** | Done except **P0.12c** (`apiBaseUrl` guardrails: host allowlist, health gate, auto-revert, host-bound `Authorization`). P0.12a/b are done; P0.12c is the last of the three slices and its brick-proof test is part of the P0 exit gate |
| **P1** | P1.1–P1.12 all done and committed. **P0.3 (localization gate) is IN FLIGHT AND BROKEN – see below** |
| **P2** | Not started. Partly blocked on the OCR corpus (see "The corpus") and on a product decision for fiscal enrichment |

### P0.3 is uncommitted and does not work

An agent built a localization gate as a SwiftPM target (`ios/Sources/LocalizationGate/`, `LocalizationGateTool/`, `Tests/LocalizationGateTests/`, plus a CI step in `.github/workflows/ios.yml` and a `localization-gate` product in `ios/Package.swift`). It also edited `ManualFillUpSections.swift` and `Localizable.xcstrings`, which suggests it found and fixed a real violation.

**The gate binary hangs.** `./ios/.build/debug/localization-gate` never returns, with default paths or explicit `--sources`/`--catalogue`. The agent reported it ran clean; it does not. Nothing is committed.

Next session: either debug the hang (start with `SourceScanner.swift` – a directory walk that follows `.build` or a symlink loop is the obvious suspect) or discard the branch and re-dispatch `agents/briefs/P0.3.md`. **Do not commit it as-is, and do not tick P0.3.**

The catalogue itself is fine and not the deliverable: **220 keys, all 220 with Russian.** What is missing is the gate that stops the next screen hardcoding `Text("Save")`.

## What to do next

1. **Resolve P0.3** (above). That closes P1.
2. **Refresh the screenshots**: `scripts/capture-screenshots.sh`. The Home one-row header (P1.12) staled every Home-based shot – P1.1, P1.4, P1.5, P1.8. The script re-shoots all 27 EN+RU in one run. **Then open them** – it can only prove a file was written.
3. **P0.12c** to close the P0 exit gate.
4. **P2** – see the two blockers below.

## The corpus (P2's real blocker)

`Spike/ReceiptSpike/fixtures/` now holds real material, in four classes that are scored **separately** so none flatters another:

| Folder | Contents | Parser result |
|---|---|---|
| `receipts/` | 1 photo (Circle K, Tallinn, Estonian) | numbers **3/3**, cross-check locks |
| `pump/` | 1 photo, **same fill-up as the receipt** | **0/3** – see below |
| `fiscal/` | 1 OFD PDF + its extracted text + the decoded QR payload | ground truth verified arithmetically |
| `screenshots/` | 1 e-receipt screenshot (same purchase as the PDF) | **3/3**, cross-check locks |

Run: `cd Spike/ReceiptSpike && swift run ReceiptSpike fixtures/receipts` (add `--dump-text` to debug a miss). `expected.csv` lives **beside the images**, machine-read, no comments.

**One image per class is a smoke test, not a gate.** `>=95%` measured over one photo is arithmetic. What unblocks P2 is breadth: brands, countries, languages, glare, angles, crumpled and thermally-faded paper, and mixed receipts (fuel + car wash) that hard rule 4 exists for. Only the user can produce it.

Three findings already paid for by these four files:

- **Pump displays lose the decimal point.** OCR reads `SUMMA 12522` and `1869 HIND/1L`; the separator that makes them `125.22` and `1.869` is not in the recognised text, while `LIITRIT 67.00` came through intact. A pump parser must reconstruct scale – the cross-check does it, since `liters x price = total` admits one placement.
- **Pump surrounds are advertising.** The parser returned `0.700` litres from a sandwich promo (`Wrapper ja jook 0,5-0,7l`) printed beside the display. Receipt-tuned accuracy does not transfer.
- **Grade labels are not the dispensed fuel.** That display shows `miles+ / miles / 95` – every nozzle's label. The fill was **diesel**. Pump extraction should not attempt fuel kind at all.

## Open decisions (product, not implementation)

1. **Fiscal QR enrichment has no route yet.** The QR carries `t/s/fn/i/fp/n` – total, timestamp, fiscal ids – and **nothing else**: no litres, no unit price, no fuel kind. The OFD's document URL is keyed on an opaque `RawId` that is **not derivable from the QR** (verified against a real receipt). So `JOURNEYS.md` J5's "all fields land exact" depends on a lookup that has never been specified; `docs/API.md` has no fiscal endpoint. Options and their real costs are in `Spike/ReceiptSpike/fixtures/fiscal/README.md`. The user's steer: **route it through our backend**, which fits `SECURITY.md` (API keys stay server-side – the same reason the LLM gateway exists). P2.6's QR *parser* half is unblocked and has a real fixture; the enrichment half should not start until this is settled.
2. **iOS 18 validation.** Everything is built and snapshotted on **iOS 26.5**; the deployment target is 18.0 and unchanged. The compiler catches post-18 API use, but appearance and runtime behaviour are unverified on the floor. The iOS 18 runtime needs an explicit fetch (`xcodebuild -downloadPlatform iOS` gets only the latest, ~8 GB) and **L4 baselines recorded on 26.5 will need re-recording**.

## Working with agents (opencode + DeepSeek)

Builder: `opencode run --auto --thinking -m deepseek/deepseek-v4-flash --title "<id>" "$(cat agents/briefs/<id>.md)"`.
Architecture or security work goes to **pro**; screen implementation against a fixed artboard goes to **flash**.

**Both flags matter.** `--auto` because in non-interactive mode opencode cannot prompt, so it *auto-rejects* – and a single rejection kills the whole run. `--thinking` because it makes the long silent stretches legible; without it, accumulating CPU is the only evidence a run is alive.

### Is it working, or is it wedged?

**Run `scripts/agent-health.sh <task-id> <logfile>` about five minutes after every dispatch.** Roughly **one dispatch in four came up dead** this session (P1.4, P1.5, P1.12 and one P0.12 attempt) – the process exists, holds no connection, burns no CPU, and never writes a byte. All four recovered on an immediate re-dispatch of the **same** brief, so it is provider flakiness: kill and retry, do not rewrite the brief.

The decisive signal is **log bytes**: a healthy run writes ~17 KB in its first 30 seconds; a wedged one is still at 0 after 25 minutes. Log *freshness* proves nothing – nothing is written during inference. Connection count is corroborating only: a healthy run legitimately holds zero connections for ~4 minutes while waiting on `xcodebuild`.

### Verification is not optional, and agent reports are not evidence

Every `[x]` in `docs/TASKS.md` was re-verified by re-running the checks outside the agent. This caught, among others: two screenshots of an "Entry not found" page reported as the screen; a claimed-green UI suite that had 2 real failures; and a gate reported as passing that hangs (P0.3, above).

**The orchestrator must open every screenshot.** The DeepSeek runs have no image input – they verify by accessibility tree or OCR and cannot see what they produced. Screenshots are the only check that catches colour, truncation and layout; XCUITest asserts behaviour and never appearance.

### What the RU screenshots caught that no test could

Three layout/grammar bugs, in three different tasks:

- `"%@ spend"` translated word-for-word as `"%@ расходы"` rendered **"АВГУСТ РАСХОДЫ"** – word-order nonsense. Composed strings need a full localised phrase per language, never concatenation.
- A `lineLimit(1)` truncating the 30-day countdown.
- `"€143 в этом месяце"` overflowing the car-switcher row where English `"this month"` fits. Shortened to `"за месяц"`.

Russian runs 20–30% longer and **short strings expand worst** (`Fix` → `Исправить` is 3x), which is exactly what overflows tab labels, chips and error-row affordances – and a truncated next step breaks hard rule 7.

## Known open items

1. **P0.3 gate hangs** (above) – blocking P1 completion.
2. **Screenshots are stale** for Home-based screens after the P1.12 header change.
3. **Two UI tests are load-sensitive**: `AddVehicleUITests.testConfirmItIsRightIsOneTap` and `testImplausibleOdometerWarnsButNeverBlocksSave` pass in isolation and can fail in the full suite. Root cause is the shared `scrollTo` helper stopping on `isHittable`, which tests an element's **centre** – so it can stop while the bottom edge is still under the keyboard. `HomeUITests.testLastRowClearsTheFloatingTabBar` had the same defect and was fixed by scrolling until the frame clears; the two AddVehicle ones have not been given the same treatment yet.
4. **The API shuts down when Postgres is unreachable** (retries ~4 times then exits). For a product whose story is "the server being down is a non-event", it should start degraded and report unhealthy. Flagged for P4.
5. **`JsonSchema.Net` is pinned to 4.1.8** – the last MIT-licensed release; 5.0+ is a paid licence. A dependency risk to revisit.
6. **Assume ASCII-only blind spots exist** in code written before 2026-08-23. `JSONValue.parse` rejected *every* multi-byte UTF-8 string – a Cyrillic station name could not be decoded at all – and the whole suite stayed green because every payload fixture was ASCII. Fixed, with a test that fails if the corpus ever goes all-ASCII again, but `JSONSchemaValidator.swift` sits in the same directory with no Unicode tests.

## The document set

`CLAUDE.md` is the operating manual and index; its **14 hard rules** are the ones that make things bugs rather than style. Under `docs/`: VISION, COMPETITORS, DESIGN, JOURNEYS, SCREENMAP, ERRORS, LOGGING, SECURITY, CONFIG, NOTIFICATIONS, SCHEMA, SYNC, API, TESTING, PHASES, TASKS. Screens are `.dc.html` artboards in `design/screens/`. Agent briefs are in `agents/briefs/` – read `README.md` there before writing a new one; every fence in those briefs exists because something went wrong once.
