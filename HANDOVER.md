# Tankbook – Session Handover

*Rewritten 2026-08-24; updated the same day when P0.3 landed and the corpus grew.*
* Read this first, then `CLAUDE.md` for the rules and `docs/TASKS.md` for the backlog with live status marks.*

## What this project is

A capture-first car cost log: iOS native (SwiftUI, min iOS 18, reference device iPhone 12) plus a C#/ASP.NET Core + PostgreSQL backend. Scanning receipts, pump displays and fiscal QR codes replaces typing. Local-first: fully usable with no account and with the server unreachable.

Product thesis: `docs/VISION.md`. Market research: `docs/COMPETITORS.md`.

## Does it work? Yes – there is a real app now

Verified by running it, not by assertion:

- **The app runs in the simulator and every P1 screen is built**: Home (garage card, vitals, log stream), Add car, manual fill-up, Edit entry, Recently deleted, duplicate detection, tank level, Trends, car switcher, Vehicle detail.
- **iOS: 318 unit tests, 59 UI tests** executed against a booted iPhone 17 / iOS 26.5 simulator. **Backend: 134 tests.** `swiftlint lint` exits **0** from the repo root.
- **Backend serves real traffic against real Postgres** – `bash backend/scripts/dev-up.sh`, then `dotnet run --project src/Tankbook.Api`: migrations apply, `GET /health` → `{"status":"ok"}`, `GET /v1/config` returns a signed document with no auth, `If-None-Match` → 304.
- **The consumption engine reproduces the D1–D4 golden vectors**, re-checked after every change that touched it.

Screenshots of every screen, EN and RU, are committed in `design/screenshots/`.

## Where the work stands

**P1 is complete; P0 has one task left (P0.12c).** Status marks live in `docs/TASKS.md` (`[x]` = done *and independently re-verified outside the implementing agent*).

| Phase | State |
|---|---|
| **P0** | Done except **P0.12c** (`apiBaseUrl` guardrails: host allowlist, health gate, auto-revert, host-bound `Authorization`). P0.12a/b are done; P0.12c is the last of the three slices and its brick-proof test is part of the P0 exit gate |
| **P1** | **Complete.** P1.1–P1.12 and P0.3 all done, committed and re-verified |
| **P2** | Not started. The OCR corpus blocker is largely lifted (see "The corpus"); the fiscal-enrichment product decision still stands |

### P0.3 is done (2026-08-24)

The gate binary hung because `SourceTokenizer.tokenize` never advanced `index`
past a string literal - the first `"` in any file spun forever. One missing line.
Its own test suite could not have run either: every test feeds string literals
through that path, so they hang rather than fail. That is why "the agent reported
it ran clean" and "the gate hangs" were both true.

Fixed, and the scan widened to `L10n.localize(` (58 previously unchecked call
sites - the dangerous half, since `L10n.localize` feeds `Text(_: String)`, which
does not localise at all). It immediately failed on two live defects: a Home
grouped-receipt count with no catalogue key and no Russian plural forms, and a
device name being routed through the catalogue as if it were copy.

Catalogue: **232 keys, 100% RU**. Gate exits 0 on the tree, 1 on a hardcoded
string. Committed as `c5a1d6d`.

**Its known blind spot bit immediately afterwards** and is worth remembering: a
literal assigned to an inferred-`String` local and passed to `Text(_:)` renders
the English key even when the catalogue has the translation, and a key-membership
check cannot see it. The RU screenshot caught one ("checks as you type" on
Confirm) that the gate, the unit tests and 59 UI tests all missed. Fixed in
`1b20ee4`; the whole app target was swept for others and there were none.

## What to do next

1. **P0.12c** – the last open P0 slice, and the P0 exit gate. No brief written yet.
2. **P2** – the corpus blocker is now substantially lifted (below); the fiscal
   enrichment decision is not.

Done this session: P0.3 (above), all 27 screenshots re-captured from the current
build and opened (`1b20ee4`), and the OCR corpus taken from 1 receipt to 12
(`5976bde`).

## The corpus (largely unblocked, 2026-08-24)

`Spike/ReceiptSpike/fixtures/` now holds **12 receipt photos** (9 brands, 2022-2026,
Russian throughout, two VAT rates, petrol 92/95/100, diesel and LPG), 2 pump
photos, 2 fiscal OFD documents and an e-receipt screenshot - still scored in four
separate classes so none flatters another. Fiscal QR payloads are decoded and
committed beside the images.

**Baseline: 12/30 fields (40.0%), cross-check 5/13.** It was "3/3" over one photo,
which is arithmetic. The drop is the corpus working. Full failure taxonomy in
`fixtures/receipts/README.md`; the three that change design:

- **Litres and unit price come back swapped and the cross-check reports PASSED**,
  because `a*b == b*a`. It validates the product, never the assignment. Caught
  only because `pump-002` photographs the same fill as `receipt-007` and labels
  both values. Consumption would be wrong by 2.3x with every check green.
  Disambiguation must come from the `л` marker's position or a price prior.
- **The total-finder grabs VAT, the ОКРУГЛЕНИЕ line, or a mixed receipt's grand
  total instead of the fuel line.** Reading order is the mechanism: right-aligned
  receipts emit *value before label*. `receipt-009` is the hard-rule-4 fixture the
  project lacked - and its bottled water costs 129.00, the same number as the
  fuel's price per litre.
- **ЛУКОЙЛ rounds the fiscal total down to the whole rouble** (`ОКРУГЛЕНИЕ`, also
  printed as "your discount"), VAT computed pre-rounding. So the pump reads
  4334.83 and the receipt 4334.00 for the same fill - both correct, ~1 ₽ apart.
  Duplicate detection must not read that as two fills. Not universal: the 2022
  Кемерово receipt has no rounding line.

Run: `cd Spike/ReceiptSpike && swift run ReceiptSpike fixtures/receipts`
(`--dump-text` to debug a miss). OCR is rarely the problem - Vision reads these at
confidence 1.00 and the parser still misses. **These are parser bugs, not OCR bugs.**

**Open, needs the user:** the four Крым Оил receipts print `цена*количество` with
no unit marker on either operand (`205.00*20`), so both readings give the same
total. `liters`/`unitPrice` are deliberately blank; totals are recorded. Context
says price-first at crisis prices on one southern road trip, but that is an
inference and the gate ratchets against whatever is written down.

## Open decisions (product, not implementation)

1. **Fiscal QR enrichment has no route yet.** The QR carries `t/s/fn/i/fp/n` – total, timestamp, fiscal ids – and **nothing else**: no litres, no unit price, no fuel kind. The OFD's document URL is keyed on an opaque `RawId` that is **not derivable from the QR** (verified against two different OFDs). So `JOURNEYS.md` J5's "all fields land exact" depends on a lookup that has never been specified; `docs/API.md` has no fiscal endpoint. Options and their real costs are in `Spike/ReceiptSpike/fixtures/fiscal/README.md`. The user's steer: **route it through our backend**, which fits `SECURITY.md` (API keys stay server-side – the same reason the LLM gateway exists). P2.6's QR *parser* half is unblocked and has a real fixture; the enrichment half should not start until this is settled.
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

1. **The localization gate cannot see `String`-typed wrappers** – a correct
   catalogue key still renders English through `Text(_: String)`. Only the RU
   screenshot catches this class. Documented in `LocalizationGate.swift`.
2. **Two UI tests are load-sensitive**: `AddVehicleUITests.testConfirmItIsRightIsOneTap` and `testImplausibleOdometerWarnsButNeverBlocksSave` pass in isolation and can fail in the full suite. Root cause is the shared `scrollTo` helper stopping on `isHittable`, which tests an element's **centre** – so it can stop while the bottom edge is still under the keyboard. `HomeUITests.testLastRowClearsTheFloatingTabBar` had the same defect and was fixed by scrolling until the frame clears; the two AddVehicle ones have not been given the same treatment yet.
3. **The API shuts down when Postgres is unreachable** (retries ~4 times then exits). For a product whose story is "the server being down is a non-event", it should start degraded and report unhealthy. Flagged for P4.
4. **`JsonSchema.Net` is pinned to 4.1.8** – the last MIT-licensed release; 5.0+ is a paid licence. A dependency risk to revisit.
5. **Assume ASCII-only blind spots exist** in code written before 2026-08-23. `JSONValue.parse` rejected *every* multi-byte UTF-8 string – a Cyrillic station name could not be decoded at all – and the whole suite stayed green because every payload fixture was ASCII. Fixed, with a test that fails if the corpus ever goes all-ASCII again, but `JSONSchemaValidator.swift` sits in the same directory with no Unicode tests.

## The document set

`CLAUDE.md` is the operating manual and index; its **14 hard rules** are the ones that make things bugs rather than style. Under `docs/`: VISION, COMPETITORS, DESIGN, JOURNEYS, SCREENMAP, ERRORS, LOGGING, SECURITY, CONFIG, NOTIFICATIONS, SCHEMA, SYNC, API, TESTING, PHASES, TASKS. Screens are `.dc.html` artboards in `design/screens/`. Agent briefs are in `agents/briefs/` – read `README.md` there before writing a new one; every fence in those briefs exists because something went wrong once.
