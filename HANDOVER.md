# Tankbook – Session Handover

*Rewritten 2026-08-26, with Phase 3 complete and Phase 4 under way. Read this first, then
`CLAUDE.md` for the rules and `docs/TASKS.md` for the backlog with live status marks.*

## Start here (paste this to open a new session)

> Read `HANDOVER.md`, then `CLAUDE.md`, then `docs/TASKS.md`. You are orchestrating opencode agents
> to build this app. Briefs go in `agents/briefs/<task-id>.md` **before** dispatch; read that
> folder's `README.md` first. Fully qualify the model: `deepseek/deepseek-v4-pro` for
> architecture, algorithms and security, `deepseek/deepseek-v4-flash` for artboard-driven screens,
> `deepseek/deepseek-v4-flash-vision-exp` when an image must be read.
>
> Non-negotiables, all learned the hard way: **verify every agent's work yourself before
> committing** - re-run `swift build`, `swift test`, `xcodebuild test`, `swiftlint` and, for
> backend work, `dotnet build/test/format`, judged by **exit code**, and name the **simulator**
> you ran on. **Mutation-check the load-bearing invariant of every task**: break it, confirm a test
> fails, restore byte-for-byte. **Open every screenshot yourself, EN and RU** - agents have no
> image input. **Measure before you fix** a failing test; instrument an assertion rather than
> guessing at a cause. Never `pgrep -f` for a build. One task = one verified commit.
>
> **Next: P4.5** (the iOS sync client and the S1-S9 scenario suite) - the endpoints and the local
> exactness it needs are already merged. **Read P4.12 first**: the cloud vision model reads pump
> displays the rules parser cannot, and that changes what the gateway is for.

## What this project is

A capture-first car cost log: iOS native (SwiftUI, min iOS 18, reference device iPhone 12) plus
a C#/ASP.NET Core + PostgreSQL backend. Scanning **reduces** typing – it never replaces it, and
typing is a peer entry path (hard rule 15). Local-first: fully usable with no account and with
the server unreachable.

Product thesis: `docs/VISION.md`. Market research: `docs/COMPETITORS.md`.

## Does it work? Yes

Verified by running it, not by assertion:

- Every P1 screen is built, plus the P2 capture surface, the Confirm sheet's scan path, mixed
  receipts and foreign currency, and **all of P3**: service entry (typed and scanned), the parts
  shelf with install linking, tire sets, the reminder lifecycle end to end, and local
  notifications.
- **iOS: 581 unit tests, 115 UI tests** (113 passing; the two failures are the device-specific
  `ConfirmManual` pair below), `swiftlint lint` exit **0**, localization gate exit **0** at 413
  keys / 100% RU. **Backend: 155 tests, `dotnet format` 0.**
- **Backend serves real traffic against real Postgres** – `bash backend/scripts/dev-up.sh`, then
  `dotnet run --project src/Tankbook.Api`.
- The consumption engine reproduces the D1–D4 golden vectors.

68 screenshots, EN and RU, in `design/screenshots/` - every one opened by a human before it was committed.

## Where the work stands

| Phase | State |
|---|---|
| **P0** | **Complete.** P0.12c closed the exit gate |
| **P1** | **Complete** |
| **P2** | **Effectively complete.** P2.1, P2.1b, P2.2, P2.3, P2.5 done; P2.4, P2.6, P2.7 are `[~]` for honest reasons below; **P2.8 is `[cut]`** - the on-device model has no Russian (below) |
| **P3** | **COMPLETE (2026-08-26).** All nine rows ticked. The exit gate is met clause by clause, each on a deliberate failure rather than an assertion - see `docs/PHASES.md` |
| **P4** | **Under way.** `[x]` P4.1 auth (rotation + reuse revocation), `[x]` P4.2 sync push/pull + SCN, `[x]` P4.4 Sign in / Keychain / J11a, `[x]` P4.11 `Date` round-trip. **Next: P4.5** (iOS sync client). P4.3, P4.6-P4.10, P4.12 open |

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

**P4.5 - the iOS sync client** is the next real step: the dirty queue, the pull/merge/push loop,
domain revalidation after merge, **field-level merge for `Vehicle`** (every other entity stays
record-level LWW), and the **L3 scenario suite - one deterministic test per S1-S9**. Everything it
needs is merged: the endpoints (P4.1, P4.2) and the local exactness it leans on (P4.11).

**Read P4.12 before designing P4.10.** A first probe of `deepseek/deepseek-v4-flash-vision-exp`
(4-7 s per image) changes what the gateway is for:

- on **pump displays**, where the rules parser scores **0/30**, it read **9 of 12 fields** exactly,
  including `pump-004` - the fixture where Vision returns a **wrong digit at confidence 1.00**;
- its two failures are the corpus's own documented traps and **both pass an arithmetic
  cross-check**: `pump-005` lost a decimal separator (5.256 / 462.08, a clean factor-of-ten shift)
  and `receipt-035` **swapped** volume and price (`70.44 X 39.000` read as 70.44 L).

So the model is strongest exactly where the parser is blind, and its failure modes are silent. **A
confident swap is worse than a nil** (hard rule 13): the gateway should cross-check or suggest, not
trust. Run the full corpus through it with the existing scorer first - that is P4.12.

Also open, none of it blocking:

1. **P4.3** blobs, **P4.6** attachment sync, **P4.7** restore end-to-end, **P4.8** silent APNs,
   **P4.9** Settings account states, **P4.10** the gateway server.
2. **Google sign-in needs the Google SDK** - the button exists per the artboard and returns a
   next-step error (P4.4 left it deliberately).
3. **The `headlight` cyan question, five instances.** `docs/DESIGN.md` says cyan encodes
   *electric*; the app uses it as the generic interactive colour. One decision, not five.
4. **P2.2b** (money as `Double` in `Extraction/`), **P2.3b** (fuels the car cannot burn),
   **P1.13** (Confirm sheet's odometer ungrouped), **P2.9/P2.10/P2.11** (three-decimal volumes,
   KZT detection, mixed-script OCR). **P2.9 now has two fixtures** and is the best-evidenced of
   them.
5. **Notification tap does not deep-link to Reminders** (P3.6, deliberate).

## What the P3 sessions cost, and what they proved

Twenty-nine commits took P2's follow-ups and the whole of P3. The engineering is in the log; these
are the things that will happen again.

### Measure before you fix

An entry-form reorder took the UI suite to 8 failures. I blamed the tests **three times** - "below
the fold", "the wrong scroll view", "machine load" - each with a plausible fix and no evidence.
**One instrumented assertion disproved all three in fifteen seconds.** Two of the eight were real
defects in the new code:

- the currency fold's `isExpanded` lived in the section's own `@State`, which resets on every
  parent re-render, so the row could be tapped and never opened;
- the collapsed row had no `.contentShape`, and a `.plain` Button's hit area is its **rendered
  content** - the row is a label, a Spacer and a value, so its middle, exactly where a tap lands,
  was empty.

Both shipped a control that renders correctly, reports `isHittable = true`, and does nothing.
Invisible to a screenshot and to a reading of the diff. **Only the suite could catch them, and I
spent three rounds assuming the suite was what was wrong.**

### XCUITest's `isHittable` does not model occlusion

An element under a `safeAreaInset` save bar reports itself hittable. "Tapping" it hit the bar and
**saved the entry**, so the failure read as a missing button. Two consequences now encoded in the
test helpers: scroll by **geometry** (clear of the bar's top), and drag the **hittable** scroll
view - `app.scrollViews.firstMatch` is the screen *behind* a presented sheet, and a swipe starting
lower is eaten by the keyboard.

### Two ConfirmManual tests are device-specific, not broken

`testCrossCheckMismatchShowsAmberRefusesLockButSaveAnywayWorks` and
`testReducedMotionLockStillLandsWithoutAnimation` **fail on `iPhone 17 Pro` and pass on
`iPhone 17`**, verified on clean `main` on both. They join the `AddVehicle` pair in the
device-specific family.

The procedural lesson is sharper than the fact: an agent reported them as pre-existing and **I
doubted it**, having just watched that suite pass 19/19 - on a different simulator. My "disproof"
was device-specific evidence. When an agent's claim conflicts with yours, check you ran the same
device before concluding it is wrong.

### Four ways an agent dispatch dies, all reporting EXITED

`agent-health.sh` says `EXITED` for every one; **log size is the first discriminator**.

| Failure | Signature | Response |
|---|---|---|
| Wrong provider prefix | instant `UnknownError`, ~166 bytes | fully qualify `deepseek/...` |
| Provider outage | instant `UnknownError` on every model | wait |
| Wedged/stalled run | silence, socket **ESTABLISHED**, **zero byte delta** | kill, re-dispatch |
| Network unreachable | `Cannot connect to API`, ~139 bytes | check the host, retry |

`lsof` is not enough - a stalled run holds its socket open. The decisive check is
`nettop -P -x -J bytes_in -l 2`: if the counter does not move over 45-60 s, the stream is dead.

**And a silent agent mid-`xcodebuild` is not a stalled one.** The monitor now checks for a running
`xcodebuild` before calling anything wedged. P3.5 and P3.6 each went silent for 17 minutes inside a
full UI suite; killing a healthy agent 40 minutes into its task is the expensive mistake.

### Seeds reset the database more than once per launch (fixed, P3.8)

Five types called `AppStore.resetForTests()` and only three had a gate, **each private to its own
type**, so one launch could reset several times and a later seed wiped an earlier one. It became
reachable the moment P3.3's and P3.4's seeds merged: a capture run rendered the **empty** Home for
`-seedHomeFullHistory` and reported `ok` for all 62 files. The gate is now process-wide. The same
run also proved `capture()` relied on an argument's **absence** to undo `-AppleLanguages "(ru)"`,
so EN captures rendered Russian.

**A capture script proves a file was written, nothing more.** That is now three distinct silent
bugs in it.

### Two agents on adjacent tasks WILL collide

P3.2 and P3.3 each rewrote `ServiceEntryModeRow` for their own half and left the other's chips
unwired - neither could see the other's branch, so taking either side would have shipped a row
that half works. And a conflicted `Localizable.xcstrings` is **not line-mergeable**: merge it
structurally (340 + 345 keys -> 359 union), because resolving it by hunk silently drops keys.

### Design for testability, or the phase gate cannot be met

`AppTabBar`'s padding arithmetic lived in the app target, which the package tests cannot import -
so the double-counted inset was "verified by looking at one device" and survived P1 and P2. P3.7
moved it to `TankbookCore.TabBarMetrics` and the injected-inset tests caught both mutations
immediately. P3.6 was briefed the same way up front: the notification **plan** is a value type in
core and `UNUserNotificationCenter` is an injected adapter, which is the only reason "exactly one
overdue follow-up, never a nag loop" could be proved **as a loop**.

## The P4 session so far, and the one new lesson

Four tasks merged, each mutation-checked on the rule it exists for:

| Task | The mutation that proves it |
|---|---|
| **P4.1** auth | rejecting a reused refresh token **without revoking its chain** fails 3 of 4 rotation tests |
| **P4.2** sync | advancing `nextSince` **one past** the last returned record fails the no-skip test |
| **P4.4** sign-in | bypassing `HostAllowlist` fails the off-allowlist test, which also proves the token was **never fetched** |
| **P4.11** dates | leaving the **writer** on the old epoch, and converting **twice**, each fail their tests |

### A fifth way a dispatch dies: "database is locked"

Launching two agents in the same instant kills one - opencode's own local store cannot take
concurrent starts. **Stagger dispatches by ~a minute.** Like the other four, it reports `EXITED`;
the tell is a tiny log containing that string.

### Two tracks that cannot collide

`ios/` and `backend/` are different toolchains, different test runners and different files, so an
iOS agent and a backend agent run in parallel with no simulator contention and no merge conflicts.
P4.1+P4.11 and P4.2+P4.4 were run that way. **Two agents in the same tier will collide** (P3.2 and
P3.3 both rewrote one view); two agents across tiers do not.

## The corpus – the most valuable artefact in the repo

`Spike/ReceiptSpike/fixtures/`: **35 receipts, 10 pump photos, 3 e-receipt/app screenshots, 2
fiscal PDFs**, 23 decoded QR payloads. Two joined today: `receipt-033` (KZ tenge, VAT 16%,
bilingual, a kofd.kz QR, a money-first fill) and `receipt-034` (a B2B contract fill printing
`30.61 X 0.00` - a zero means "not printed", never "free", and it found two real parser bugs).
**The accuracy ratchet was toothless** and is re-baselined: it recorded 29/47 against 45/92
measured, so the parser could have lost 16 fields with CI green. 2018–2026, RU and KZ, RUB/KZT/EUR, two VAT rates, petrol
92/95/98/100, diesel, LPG. Four classes scored separately so none flatters another.

| class | score | note |
|---|---|---|
| receipts | **45/96 (46.9%)** | every miss is a parsing bug, not an OCR one |
| pump | **0/30** | ten devices, six manufacturers. This zero is why P2.7 ships off |
| fiscal | 0/3 | only one of the three rows is an OCR-scorable image |
| screenshots | 6/9 (66.7%) | app screenshots are the easiest input that exists |

Run: `cd Spike/ReceiptSpike && swift run ReceiptSpike fixtures/receipts` (`--dump-text` to debug).
**OCR is not the bottleneck** – Vision reads these at confidence 1.00 and the parser still misses.

### `receipt-035` proved operand position carries no information

Same corporate fuel card as `receipt-034`, one printing a price and one not (contract pricing). And
the operand order is **reversed** against `receipt-033`: volume first there (`24.690 X 243.00`),
volume second here (`70.44 X 39.000`). Same country, same year, both fuel cards.

What survives the flip is the **decimal count** - three on the volume, two on the price, in both.
That is now the strongest evidence for **P2.9**, and it is the signal the cloud vision model
ignored when it swapped this receipt.

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
2. **The `AddVehicle` pair and the `ConfirmManual` pair are DEVICE-SPECIFIC, not broken.**
   `testConfirmItIsRightIsOneTap` and `testImplausibleOdometerWarnsButNeverBlocksSave`, plus
   `testCrossCheckMismatchShowsAmberRefusesLockButSaveAnywayWorks` and
   `testReducedMotionLockStillLandsWithoutAnimation`, fail on some simulators and pass on others -
   all four passed on `iPhone 17` in a full idle-machine run, and the `ConfirmManual` two
   reproduce on `iPhone 17 Pro` from clean `main`. The shared shape is `typeText` after a
   successful tap, with the field leaving the accessibility tree. **Do not fix it with sleeps**,
   and do not call a suite red or green without naming the device it ran on.

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

### The three ways process-detection lied (P2 session)

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

### The odometer had no thousands separator for the whole of P1

`OdometerFormat` grouped with a **thin space (U+2009)**, and **DIN Alternate Bold has no glyph
for it** - so every odometer in the app rendered `118930` while `OdometerFormatTests` stayed green
asserting the exact `"119\u{2009}486"` string. A string test cannot see a missing glyph. CoreText
settles it: for `DINAlternate-Bold`, `CTFontGetGlyphsForCharacters` is false for U+2009, U+202F,
U+2007 and U+2008, and true for **U+00A0** at an advance of 3.596 at 15 pt (0.24 em - thin-space
proportions, so the artboard is matched rather than compromised with). The separator is now
U+00A0, `ungrouped` strips both, and `separatorHasAGlyphInTheDisplayFont` asserts the display font
can actually draw whatever separator `grouped` produces. Mutation-checked: reverting to U+2009
fails it.

The general lesson, and it is the same one as the ghost tab-bar pill: **a formatter test asserts a
string, and the user reads pixels.** Anything that renders in a non-system font needs a glyph
check, not only a value check.

### `scripts/capture-screenshots.sh` had THREE bugs, all silent

The third, found 2026-08-25: **it never rebuilt.** It resolved this checkout's
`BUILT_PRODUCTS_DIR` and screenshotted whatever binary sat there, so a full 43-shot run taken
right after the separator fix produced 43 confident images of the **previous** build, reporting
`ok` for every file. It now builds first unless `SKIP_BUILD=1`. A stale capture is worse than no
capture: it is evidence for the wrong code.

### The two earlier `capture-screenshots.sh` worktree bugs

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
