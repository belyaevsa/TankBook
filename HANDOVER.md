# Tankbook – Session Handover

*Rewritten 2026-08-25 at the end of the P2 session. Read this first, then `CLAUDE.md` for the
rules and `docs/TASKS.md` for the backlog with live status marks.*

## What this project is

A capture-first car cost log: iOS native (SwiftUI, min iOS 18, reference device iPhone 12) plus
a C#/ASP.NET Core + PostgreSQL backend. Scanning **reduces** typing – it never replaces it, and
typing is a peer entry path (hard rule 15). Local-first: fully usable with no account and with
the server unreachable.

Product thesis: `docs/VISION.md`. Market research: `docs/COMPETITORS.md`.

## Does it work? Yes

Verified by running it, not by assertion:

- Every P1 screen is built, plus the P2 capture surface, the Confirm sheet's scan path, mixed
  receipts and foreign currency.
- **iOS: 462 unit tests, 88 UI tests**, `swiftlint lint` exit **0** from the repo root,
  localization gate exit **0** at 262 keys / 100% RU. **Backend: 134 tests.**
- **Backend serves real traffic against real Postgres** – `bash backend/scripts/dev-up.sh`, then
  `dotnet run --project src/Tankbook.Api`.
- The consumption engine reproduces the D1–D4 golden vectors.

40 screenshots, EN and RU, in `design/screenshots/`.

## Where the work stands

| Phase | State |
|---|---|
| **P0** | **Complete.** P0.12c closed the exit gate |
| **P1** | **Complete** |
| **P2** | **Effectively complete.** P2.1, P2.1b, P2.2, P2.3, P2.5 done; P2.4, P2.6, P2.7 are `[~]` for honest reasons below; **P2.8 is `[cut]`** - the on-device model has no Russian (below) |

### The three `[~]`s are blocked on facts, not effort

- **P2.4 (mixed receipts)** – detection, the "Also on this receipt" UI and grouped save all
  landed and are tested. Its `>=95% on mixed corpus` gate is **not met and not ticked**, because
  the corpus holds **two** mixed fixtures. A percentage over two fixtures is arithmetic.
  `receipt-025`'s detection by *line structure* (the path that works without a QR) is still
  unasserted – that is the concrete next step.
- **P2.6 (fiscal QR)** – the parser half shipped as an **anchor for OCR**, not a capture path.
  Enrichment is **permanently deferred**: the QR carries only total, timestamp and fiscal ids,
  and the OFD document is keyed on an id not derivable from the QR (verified against two OFDs).
- **P2.7 (pump mode)** – ships **off**, and that is the correct outcome. The gate is enforced by
  a test that was mutation-checked: neutering `PumpPhotoGate.violation` fails it.

## What to do next

1. ~~**P2.8**~~ – **cut on 2026-08-25, and the reason is not "we ran out of time".** The iOS 26.5
   SDK carries `SystemLanguageModel.UnavailableReason.unsupportedLanguageOrLocale` alongside
   `supportedLanguages`, and **Russian is not in the supported set** (nor Kazakh). The corpus is
   32 RU/KZ receipts, so the layer would have been unavailable precisely where the rules parser
   is weakest. Its check – *ships only if it strictly improves on an A/B against the corpus* – is
   unsatisfiable in principle, not merely unmeasured, which is a stronger reason to stop than
   P2.7's 0/30 was. **The EU is not the blocker** (Apple Intelligence landed there in iOS 18.4,
   April 2025); the constraint is language. Full reasoning and the single re-open condition:
   `docs/VISION.md` -> "Why tier 2 was cut". Normalization for Russian receipts is now tier 3's
   job, which raises the cloud gateway's expected volume.
2. **P2.2b** – `FuelExtraction` types money as `Double`; `SCHEMA.md` requires `Decimal`.
   P2.3/P2.5 both convert at their boundary rather than propagate it, so this is contained but
   still wrong at the root.
3. **P2.3b** – the Fuel row offers fuels the car cannot burn (the seed car is
   `[.petrol95, .diesel]`, which no car is).
4. **P2.4b** – wire `FiscalDocumentIdentity` into duplicate detection. Two corpus receipts are
   genuine separate fills, identical to the kopeck, escaping a false merge **by four minutes**.

## The corpus – the most valuable artefact in the repo

`Spike/ReceiptSpike/fixtures/`: **32 receipts, 10 pump photos, 3 e-receipt/app screenshots, 2
fiscal PDFs**, 23 decoded QR payloads. 2018–2026, RU and KZ, RUB/KZT/EUR, two VAT rates, petrol
92/95/98/100, diesel, LPG. Four classes scored separately so none flatters another.

| class | score | note |
|---|---|---|
| receipts | **37/89 (41.6%)** | every miss is a parsing bug, not an OCR one |
| pump | **0/30** | ten devices, six manufacturers. This zero is why P2.7 ships off |
| fiscal | 0/3 | only one of the three rows is an OCR-scorable image |
| screenshots | 6/9 (66.7%) | app screenshots are the easiest input that exists |

Run: `cd Spike/ReceiptSpike && swift run ReceiptSpike fixtures/receipts` (`--dump-text` to debug).
**OCR is not the bottleneck** – Vision reads these at confidence 1.00 and the parser still misses.

### What the corpus proved, that no amount of design discussion would have

- **Nothing about a receipt is predictable from its brand.** Operand order varies *within one
  receipt* (`receipt-031`); the decimal separator varies *by device at one station* (`pump-002`
  vs `pump-007`); rounding behaviour varies *by year within one chain* (`receipt-029` is 2021
  ЛУКОЙЛ with no rounding, the 2026 ones all round); layout varies *within one brand*
  (`receipt-013` vs `-032`). Read what the document says; infer nothing from who printed it.
- **The cross-check is a consistency check, not a correctness one.** It catches a misread digit
  and picks among discrete candidates (`pump-005`'s four prices). It is blind to a **swapped**
  volume/price pair (`a x b == b x a`) and to **lost decimal separators** (scale-invariant:
  `pump-003` has 12 valid solutions, not one). A swap stores a fill 2.3x wrong with every check
  green.
- **Confidence is not correctness.** `pump-004`: Vision returned a wrong digit at **1.00**. No
  setting of `ocrConfidenceThreshold` can catch that.
- **Region moves price as much as years do.** Yakutsk 2023 is 27% above Кемерово seven months
  earlier. A band keyed on country+period is too coarse – see `docs/SCHEMA.md` → Fuel price
  bands, whose resolution ladder is specified but whose pack is P5.
- **Redundancy rescues receipts and not pumps.** A receipt prints its total three times
  (`receipt-015` survived a `5380.0D` misread); a pump prints each number once.

## Open decisions (product, not implementation)

1. **iOS 18 validation.** Everything is built and screenshotted on **iOS 26.5**; the deployment
   target is 18.0. This session found the concrete cost: the tab bar we had been reviewing in
   every screenshot was **iOS 26's system rendering**, which iOS 18 would never produce. P2.1b
   replaced it with an owned bar, so that specific gap is closed – but L4 baselines recorded on
   26.5 still need re-recording, and the iOS 18 runtime needs an explicit ~8 GB fetch.
2. **The `AddVehicle` pair, correctly diagnosed at last.** `testConfirmItIsRightIsOneTap` and
   `testImplausibleOdometerWarnsButNeverBlocksSave` fail on **iPhone 17 Pro Max in isolation** –
   so they were never "load-sensitive", as previously recorded here. The real failure is
   `typeText` after a successful tap, with the field leaving the accessibility tree. Repro
   command and the evidence are in `AddVehicleUITests.swift`. **Do not fix it with sleeps.**

## Working with agents (opencode)

Builder: `opencode run --auto --thinking -m <model> --title "<id>" "$(cat agents/briefs/<id>.md)"`.

**Fully qualify the provider in `-m`, always: `deepseek/deepseek-v4-pro`, `deepseek/deepseek-v4-flash`.**
A bare `-m deepseek-v4-pro` resolves to the **`alibaba-token-plan`** provider, which spent a
stretch of 2026-08-25 returning an instant `UnknownError: Unexpected server error` on every model
it carries - pro, flash, pinned variants and glm alike, even on a bare "reply PONG" probe. Eight
dispatches died that way and read exactly like the known wedged-run failure, which is the trap:
`agent-health.sh` says EXITED, and EXITED reads like "finished". The tell is the **log size** -
166 bytes, all of it the error JSON. `opencode models` lists the provider prefixes; `deepseek/`
answered normally throughout.
Architecture, security and algorithm work goes to **pro**; screen implementation against a fixed
artboard goes to **flash**. Both flags matter: `--auto` because a single auto-reject kills an
unattended run, `--thinking` because it makes long silent stretches legible.

**Validation runs on a `deepseek-v4-pro` agent, not in the orchestrator's session** – dispatch
`agents/briefs/VALIDATE.md`. Two things never change: read the **captured exit codes**, not the
validator's prose; and **the orchestrator opens every screenshot personally**, because agents
have no image input.

### The three ways process-detection lied this session

All the same mistake – inferring liveness from a string match instead of real pids:

1. **An agent killed a sibling.** P2.3's agent ran `pgrep -f "xcodebuild.*test"` to check the
   device was free. **A brief is part of the process command line**, so it matched P2.1b's
   `opencode` process and killed it 48 minutes in. Its log simply stops mid-edit and
   `agent-health.sh` reports EXITED, which reads exactly like "finished". Use `pgrep -x
   xcodebuild`. Never hand an agent a `pkill -f` pattern.
2. **`pgrep -f "CAPBTN-glm53"` matched the orchestrator's own shell**, reporting finished agents
   as running.
3. **A waiter fired early** when the pid list changed mid-check, producing a false "completed"
   notification. Match by title on real pids: `pgrep -f "opencode run" | xargs ps -o args= -p`.

**With worktrees, give every concurrent agent its own simulator** (`iPhone 17`, `17 Pro`,
`17 Pro Max`, `17e`) or they fight over the device.

### `scripts/capture-screenshots.sh` had two worktree bugs, both silent

It picked the newest `DerivedData/Tankbook-*` anywhere on the machine – routinely **another
checkout's binary** – so you would screenshot a different branch's app and never know. It now
asks xcodebuild for this checkout's own `BUILT_PRODUCTS_DIR`. Its `pgrep -f` guard had bug 1.

### Verification is not optional, and agent reports are not evidence

Caught this session by re-running checks outside the agent: a gate reported passing that hung
forever; a vacuous `#expect(plan.purchaseGroupId == plan.purchaseGroupId)`; a `FuelKind` enum
extension that broke the **app** target while `swift build` stayed green (only `xcodebuild`
compiles `ios/App`); and an agent thrashing for an hour adding `print` statements.

**Mutation-check the load-bearing invariant.** Break it deliberately, confirm a test fails,
restore byte-for-byte. That is what proved the allowlist, the rounding tolerance, the `rateDate`
rule and the pump gate are real rather than vacuously green.

### Screenshots caught five defects no test could

The untranslated `"checks as you type"`; a Russian mode row wrapping onto two lines; the capture
shutter pushed off-centre by a long RU label; a **ghost tab-bar pill** painted over the log
content; and the bar's hairline drawn **across** the capture circle. XCUITest asserts behaviour,
never appearance – and chrome is invisible to it even when the accessibility tree is empty.

**The localization gate's blind spot, now with four instances.** `Text(_: String)` does not
localise, so any expression producing a `String` renders its English key even when the catalogue
has the translation – and the gate cannot see it, because the key *is* present. The shape is
always **runtime data and copy sharing one expression**. The rule and all four instances are
recorded at the top of `L10n.swift`.

## The document set

`CLAUDE.md` is the operating manual and index; its **15 hard rules** are the ones that make
things bugs rather than style. Under `docs/`: VISION, COMPETITORS, DESIGN, JOURNEYS, SCREENMAP,
ERRORS, LOGGING, SECURITY, CONFIG, NOTIFICATIONS, SCHEMA, SYNC, API, TESTING, PHASES, TASKS.
Screens are `.dc.html` artboards in `design/screens/`. Agent briefs are in `agents/briefs/` –
read `README.md` there first; every fence in those briefs exists because something went wrong
once.
