# Tankbook – Session Handover

*Rewritten 2026-08-27, with Phase 4 COMPLETE and Phase 5 started. Read this first, then
`CLAUDE.md` for the rules and `docs/TASKS.md` for the backlog with live status marks.*

## Start here (paste this to open a new session)

> Read `HANDOVER.md`, then `CLAUDE.md`, then `docs/TASKS.md`. You are orchestrating opencode
> agents to build this app. Every brief goes in `agents/briefs/<task-id>.md` **before** dispatch -
> read that folder's `README.md` first; every fence in those briefs exists because something went
> wrong once.
>
> **Dispatch:** `opencode run --auto --thinking -m <model> --title "<id>" "$(cat
> agents/briefs/<id>.md)"`, from the task's own worktree. **Fully qualify the provider** -
> `deepseek/deepseek-v4-pro` for anything whose invariant is subtle enough that a plausible test
> could be vacuous; `deepseek/deepseek-v4-flash` for implementation against a fixed artboard or a
> well-diagnosed one-line fix; `deepseek/deepseek-v4-flash-vision-exp` when an image must be read.
> A bare model name silently resolves to another provider that returns an instant error.
>
> **Verification is the job, and it is not delegable to the agent's own report.** Re-run
> `swift build`, `swift test`, `xcodebuild test`, `swiftlint` (from the **repo root**) and, for
> backend work, `dotnet build/test/format` - judged by **exit code**, naming the **simulator**.
> `swift build` does not compile `ios/App`; only `xcodebuild` does. Re-run the gates **on the
> merged tree**, not just the branch. Validation itself may go to a `deepseek-v4-pro` validator
> (`agents/briefs/VALIDATE.md`) - read its captured exit codes, not its prose.
>
> **Mutation-check the load-bearing invariant of every task**: break it, confirm a test fails,
> restore byte-for-byte. **Break it in its subtlest form** - a gate consulted but not awaited, a
> filter relaxed rather than removed. This is not ceremony: it found a *vacuous headline test* in
> P4.7 where stripping the payload out of the restore hash left all 15 tests green.
> **Reading a test tells you its claim; only breaking the code tells you its coverage.**
>
> **Open every screenshot yourself, EN and RU** - agents have no image input, and no test asserts
> appearance. Zoom in before judging: a spinner is invisible at thumbnail scale. Read the rendered
> Russian for **grammar**, not just for overflow.
>
> **Measure before you fix.** Instrument an assertion rather than guessing at a cause. **Check
> state, don't read messages** - `git` will report "Already up to date" for a merge you ran in the
> wrong directory. Never `pgrep -f` for a build. One task = one verified commit.
>
> **Next: P6.3** (the gateway client - **read `docs/EXTRACTION.md` first**: measurement
> contradicts its normative 3 s budget, so a hard abort would cancel almost every request), or any
> of the P6 rows filed on 2026-08-27: **P6.7** (the `action` token), **P6.10** (the alpha-capture
> notice), **P6.11**'s surface, **P6.13** (RU clips at Dynamic Type XL). **They are all iOS-UI, so
> run them one at a time** - two UI tasks collide in `Localizable.xcstrings`, which is not
> line-mergeable and where resolving by hunk silently drops keys. A non-UI iOS task parallelises
> with a UI one safely, and `backend/` always does - but note **there is no open backend row left**,
> so parallelism now has to come from non-UI iOS work.
>
> **Also: `docs/TASKS.md` is the file three concurrent agents will conflict in.** Tell every agent
> NOT to tick it; the orchestrator ticks at merge. Resolving that file by side silently un-ticks
> somebody else's task.

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
| **P4** | **COMPLETE (2026-08-27).** All thirteen rows merged: auth, sync push/pull, blobs, sign-in, the iOS sync client with S1-S9, attachments, restore, silent nudges, account lifecycle (server + Settings), the LLM gateway, the `Date` round-trip, and the corpus A/B |
| **P5** | **P5.1, P5.2, P5.3, P5.6, P5.7 done.** Rates service; money end-to-end (feed client, S8 backfill, manual rate, F9 footnote); the RU pass (51-key case-governance audit -> `docs/LOCALIZATION.md`, plural edges at 11/21, the `Text(_: String)` gate extension). Vehicle catalog **server and client both shipped**, and P6.12 gave the wire a `kind` marker so a full pack can express a removal. **Open: P5.4 importers, P5.5 backup UI** |

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

**P2.14 - the `modal` tie-break** is the next real step, because it is the only open item that
makes *other* measurements untrustworthy: the accuracy ratchet and `PumpPhotoGate.measuredHits` are
gates asserted against a live score that can move between runs. It also blocks raising the stale
receipts mark.

After that, two are newly unblocked and independent:

- **P5.2** money end-to-end in the app (P5.1 shipped the rates service). This closes a gap visible
  in shipped UI: P2.5's foreign-currency confirm renders "converts when online" against a feed that
  now exists.
- **P6.3** the gateway client (P4.10 shipped the server). Note its device-side budget is the 3 s
  rule that measurement has already contradicted - **read `EXTRACTION.md` before implementing it**,
  because a hard 3 s abort would cancel almost every request on a mobile link.

**P4.7** (restore) was dispatched at session end and may still be running.

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

## The P4 completion session (2026-08-26/27) - ten tasks, seventeen mutations

Ten merged in one sitting, at most three agents at once, on the lanes that cannot collide.

| Task | Tests | The mutation that proves it |
|---|---|---|
| **P4.3** blobs | 155 -> 169 | relaxing the `account_id` filter kills **two** tests - cross-account `404` and per-account dedupe. Isolation and dedupe are the same predicate |
| **P4.5** sync client | 581 -> 593 | forcing `Vehicle` to record-level LWW kills **only** S9, with 8 issues, alone in a 14-test suite |
| **P4.9a** account | 169 -> 179 | dropping `deleted_at <= @Cutoff` kills only the **survivor** case |
| **P4.8** nudges | 179 -> 190 | removing `id <> @PusherDeviceId`, and removing the throttle predicate, each kill exactly one test |
| **P5.1** rates | 190 -> 202 | disabling carry-forward kills both gap tests; `DO NOTHING` -> `DO UPDATE` kills the append-only test |
| **P4.12** corpus A/B | 593 -> 603 | widening the shared tolerance 0.005 -> 5.0 breaks 8 tests across 4 suites |
| **P4.9b** Settings | 603 -> 607, UI -> 123 | constant flagged-count, and neutered in-flight guard (push count 2, not `isEnabled`) |
| **P4.13** PaddleOCR | 607 -> 619 | negative result; archived with its evidence |
| **P4.10** gateway | 202 -> 211 | disabled size cap, and metering a failed call |
| **P4.6** attachments | 619 -> 627, UI -> 124 | blob gate **consulted but not awaited** - the subtlest break - kills two tests |
| **P4.7** restore | 627 -> 635, UI -> 127 | stripping `payload` from `RestoreHash` left **all 15 tests green** - the headline test was vacuous |
| **P2.14** modal | 627 -> 634 | 20 separate processes return `nil` 20/20; the old code gave two different answers across 40 |

State: **backend 211**, **iOS 642 unit + 127 UI** on `iPhone 17`, `swiftlint` 0 from the repo root,
`dotnet format` 0.

### Three findings that outrank their tasks

- **The gateway must suggest and cross-check, never trust.** P4.12 measured the cloud model far
  ahead of the rules parser everywhere (receipts 84/96 vs 46/96, pump 31/46 vs 1/46) - and its
  failures **silent**: five receipts came back with volume and price swapped, which passes the
  arithmetic cross-check because `a x b == b x a`. It is also **stochastic**: `pump-009` flipped
  between correct and shifted across identical runs.
- **The 3 s device budget is contradicted by measurement.** `API.md` calls it normative; every
  class median exceeds it and pump peaks at 40 s. Self-hosting does not fix it - P4.13's PaddleOCR
  arm was 4.5-8.4 s on CPU. A product decision is owed.
- **The parser is coupled to Vision's line segmentation.** PaddleOCR merges `1,869 EUR/L` into one
  line where Vision emits two, and `loneMarkers` needs the price below its `/L` label. So
  `EXTRACTION.md`'s "interpretation, not recognition" holds **only under Vision-quality
  recognition** - neither confirmed nor falsified, which is sharper than either.

### `FuelExtractor.modal` is non-deterministic - P2.14, and it blocks a gate

`Dictionary(grouping:)` iteration order is not guaranteed, so a tie on both count and
primary-label count resolves to whatever the hash seed left last. The receipt score moves between
29/96 and 30/96 across identical runs. **This is why the stale receipts high-water mark (45/93
recorded, 46/96 live) was deliberately NOT raised**: pinning a gate to a number that is not
reproducible makes CI intermittently red. Fix the tie-break, prove stability, then raise the mark
in the same change.

### A green suite hid a vacuous test, and prose described one that did not exist

P4.7's headline test, `hashMovesWhenAFieldIsDroppedWhereACountWouldNot`, seeded **two**
repositories and compared their hashes - but `seedRichDataset` mints fresh `UUID.v7()` ids per
call, so the two datasets were entirely different records whose hashes differ regardless. The
`volumeL = 0` tamper never influenced the result.

**The mutation is what found it**: stripping `payload` out of `RestoreHash.compute` left **all 15
tests green**. The restore guarantee the task is named for rested on an assertion that could not
fail. The implementation was never wrong; nothing pinned it. Fixed by tampering **one** repository
in place, so ids are identical by construction.

The orchestrator had read that test and called it genuine. **Reading a test tells you its claim;
only breaking the code tells you its coverage.** And an agent's report can be articulate, specific
and confidently wrong: this one explained exactly why a count would miss the defect, in a test that
never checked it.

### A `%@` that receives runtime data must not sit inside a case-governed phrase in Russian

`from your %1$@, %2$@` was translated `с вашего %1$@, %2$@`, rendering
**"с вашего телефон Android"**. `с вашего` governs the genitive; `%1$@` receives a
**server-supplied device name** that cannot be declined. No better translation fixes it - the
sentence shape is wrong.

This is the **second** time a Russian agreement error has shipped through a `%@` slot (P1.4's
`"%@ spend"` -> "АВГУСТ РАСХОДЫ" was the first). The existing rule - a full localised phrase per
language, never concatenation - did **not** prevent it, because this *was* a full phrase. The
sharper rule now: **if a `%@` receives runtime data, the surrounding phrase must not govern its
case.** Caught only by reading the rendered Russian; no test can see it.

**P5.3 (2026-08-27) made this systematic**: `docs/LOCALIZATION.md` is now the single authority for
RU phrasing, holding a 51-key case-governance audit, the 11/21 plural edges, the `Text(_: String)`
blind spot (now partly a gate - it caught the Provider/Vendor placeholders), and the `литр` fixture
correction. Four sentence shapes were fixed in the catalogue (the archived-returned banner, the
install-part offer, the wrong-provider question, the removed-on-device attribution), and a
regression test asserts no governing preposition sits before a runtime slot.

### The screenshot set churns on the clock, so it is not a regression baseline

A full re-capture rewrote **71 of 72** files. Masking the top 130 px and pixel-comparing showed
**36 differed only by the status-bar clock** (0-2 pixels of app area out of 3.16 million) and the
other 35 by date fields rendering *today*. Three separate agents hit this independently and
reverted the noise.

So an unchanged app does **not** produce unchanged files, which undercuts the convention's premise.
Fixable by freezing the simulator clock (`simctl status_bar override --time`) and pinning seed
dates. Until then, **compare masked crops rather than committing a churned set** - and know that
`P1.6-edit-entry` is genuinely stale since P4.6 replaced its placeholder with a chip.

### Three ways git will do something correct-looking that is not what you meant

None of these fail a test, and all three produce a tree that looks right.

1. **A `git merge` run from inside a worktree reports "Already up to date".** A `cd` persists across
   lines in one shell call, so the merge targets the branch's own worktree. That message reads
   exactly like success. Check `git merge-base --is-ancestor <branch> HEAD`, not the output.
2. **A `git commit` while a merge is staged silently absorbs it.** Committing an unrelated file
   during a `--no-commit` merge produces the merge commit under the wrong message. Amend rather
   than rewrite; the tree is fine, the record is not.
3. **Resolving a `TASKS.md` conflict by side silently un-ticks a task.** One side had P4.9b ticked,
   the other P4.10; `--ours` or `--theirs` loses one. Same class as `Localizable.xcstrings`, which
   is why sequential iOS dispatch is gated on the previous task being **merged**, not finished.

### An agent's silence means nothing on its own

A wedge check that watches only `xcodebuild` fires a false positive during the **screenshot
capture** phase, which drives `simctl` for ~20 minutes and writes nothing to the agent log. Acting
on it would have killed a healthy agent 82 minutes in, right after its suite passed. Treat **any**
of `xcodebuild`, `simctl`, `swift-frontend`, `xctest`, `swift`, `xcrun` as "busy"; the wedge is
log-flat **and** no child process **and** near-zero CPU.

### Agents pushed back twice, and were right both times

- **P4.10 declined to build the cross-check signal.** My brief said the server *may* report whether
  the three numbers multiply out; it refused, because computing that is the server reading what a
  field **means** (hard rule 9). A "may" that invites a rule violation is a badly written brief.
- **P4.13 could not pass the calibration test I demanded** and said so, with evidence: `receipt-001`
  is Estonian (Latin script) read by a Cyrillic model whose detector merges the price line. My test
  conflated "is the conversion right" with "can this parser consume this reader"; its substitute
  separates them and is stronger.

**Read an agent's refusal before overruling it.** Both were better reasoning than the brief.

## The earlier P4 session (2026-08-26, first half)

Three tasks merged in one sitting, two agents at a time on the two tiers that cannot collide.

| Task | Merged | Tests | The mutation that proves it |
|---|---|---|---|
| **P4.3** blobs | `a075e21` | 155 -> 169 | relaxing the `account_id` filter kills **two** tests - cross-account `404` **and** per-account dedupe. Isolation and dedupe are the same predicate, so a mistake in it cannot hide in one of them |
| **P4.5** sync client | `998c46c` | 581 -> 593 | forcing `Vehicle` to record-level LWW kills **only** S9, with 8 issues, alone in a 14-test suite. The failure shows `tankCapacityL: 60` going to the undo log - the exact silent revert |
| **P4.9a** account lifecycle | `0557078` | 169 -> 179 | dropping `deleted_at <= @Cutoff` kills only the **survivor** case. A purge-only test stays green while the job deletes restorable data |

State now: **backend 179 tests**, **iOS 593 unit + 115 UI** on `iPhone 17`, `swiftlint` 0 from the
repo root, `dotnet format` 0.

### The three rules those mutations encode

- **`DELETE /account` is a TOMBSTONE.** Its correct behaviour is that records **remain** - devices
  learn via `410`, the user keeps their whole log locally. A test asserting only a `204` misses the
  entire guarantee, and a server expecting the client to wipe itself would be the bug.
- **A blob `404` must be refused BEFORE a presigned URL is minted.** One returned then discarded is
  already in the logs and traces.
- **S9 only tests anything if the stale device is OLDER on the field it is not writing.** An
  on-time stale device makes field-level merge and record-level LWW agree, and the test proves
  nothing while staying green.

### A latent CI flake that would have been blamed on whoever was in flight

`RedactionTests` swept rendered log output by substring for values that must never be logged. Two
**Safe-class machine fields are free-running numbers that can spell the needle**: `timestamp`
renders seconds as `SS.mmm`, so `...:42.317Z` contains `"42.3"`; and `DurationMs` is
`TimeSpan.TotalMilliseconds`, so a 9.87-second request renders `9876.5432` and contains
`"9876.54"`. The first one fired during P4.3 verification; on the clock alone `"42.3"` fails
roughly **one run in 600**.

Fixed with `WithoutMachineFields()` (`LoggingTestHelpers`), applied at every log-output sweep, and
pinned by a test built from a hand-written line - because **a flake cannot be caught by the tests
it breaks**. Identifiers (`traceId`, `deviceId`, `accountHash`) are deliberately left in the sweep
so a domain value wrongly routed into one is still caught. Recorded in `docs/LOGGING.md`. The rule:
**fix the sweep, never loosen the assertion and never change the needle** - the next needle has the
same problem.

### Two process notes

- **A merge can silently do nothing.** `cd`-ing into a worktree persists across lines in one shell
  call, so a `git merge` meant for `main` ran inside the branch's own worktree and reported
  *"Already up to date"* - which reads exactly like success. Check
  `git merge-base --is-ancestor <branch> HEAD` rather than believing the message.
- **Gate a dispatch on the machine being free.** P4.9a was held until `xcodebuild` cleared, because
  a backend agent's Docker and `dotnet test` bursts during a UI suite risk a spurious red that then
  costs 18 minutes to disprove. The brief takes the same time to write either way.

### A brief can be over-specified, and that is the orchestrator's error

P4.5's brief demanded `xcodebuild test` rise above 115. It stayed at 115, correctly: the sync
client is core-only, S7 forbids banners and modals, and the passive status row belongs to P4.9b.
Forcing a UI test there would have produced a **vacuous** one, which is worse than none. Accepted
and recorded rather than argued.

## The earlier P4 session, and the one new lesson

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

`Spike/ReceiptSpike/fixtures/`: **35 receipts, 17 pump photos, 8 e-receipt/app screenshots, 2
fiscal PDFs**, plus P4.12/P4.13's committed A/B result files under `vision-ab/`, 23 decoded QR payloads. Two joined today: `receipt-033` (KZ tenge, VAT 16%,
bilingual, a kofd.kz QR, a money-first fill) and `receipt-034` (a B2B contract fill printing
`30.61 X 0.00` - a zero means "not printed", never "free", and it found two real parser bugs).
**The accuracy ratchet was toothless** and is re-baselined: it recorded 29/47 against 45/92
measured, so the parser could have lost 16 fields with CI green. 2018–2026, RU and KZ, RUB/KZT/EUR, two VAT rates, petrol
92/95/98/100, diesel, LPG. Four classes scored separately so none flatters another.

| class | score | note |
|---|---|---|
| receipts | **45/93** | every miss is a parsing bug, not an OCR one |
| pump | **1/46** | seventeen devices, six makes. This near-zero is why P2.7 ships off |
| fiscal | 1/3 | only one of the three rows is an OCR-scorable image |
| screenshots | **7/24** | app screenshots are the easiest input that exists |

**Score these with the TankbookCore ratchet test, NOT `swift run ReceiptSpike`.** The two parsers
disagree - the harness scored the same corpus 0/46 and 11/24 where the ratchet measures 1/46 and
7/24 - and baselining `high-water.json` from the harness makes the ratchet fail instantly. Run
`cd ios && swift test --filter AccuracyRatchet` and read the numbers out of its failure message.

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
