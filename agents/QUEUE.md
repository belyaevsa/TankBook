# Dispatch queue

The order rows go out in, and why. One agent at a time - `opencode`'s session database throws
`database is locked` when two start in the same second, and the mid-run deaths at 250-500 KB of log
are memory pressure. Stagger dispatches; never run two builds in this checkout at once.

## A dispatch is TWO commands, and the second one is not optional

**1. Launch the agent with `nohup`** - detached, with its own log. `< /dev/null` is not optional:
without it `opencode run` blocks on stdin, writes zero bytes and sits forever, which reads exactly
like a wedged provider and has cost whole afternoons.

```
nohup opencode run --auto --thinking -m <provider/model> --title "<id>" \
  "$(cat agents/briefs/<id>.md)" > /tmp/agentlogs/<id>.log 2>&1 < /dev/null &
echo "dispatched, pid $!"
```

**2. Arm a HARNESS-TRACKED monitor on that pid** - in Claude Code, the Bash tool with
`run_in_background: true`, so it appears in `/tasks` and fires a completion notification:

```
while kill -0 <pid> 2>/dev/null; do sleep 20; done; echo "<id> (pid <pid>) EXITED"
```

**If the monitor keeps getting killed, use a persistent `Monitor` task instead.** On a
memory-constrained machine the harness reclaims transient background commands: on 2026-09-09 three
monitors in a row were killed ("system is running low on memory") while the agents they watched kept
running. The agent survives that - only the waiter dies - but a dead waiter is a dispatch nobody is
watching. The durable form is a `Monitor` with `persistent: true`, which is not reaped:

```
Monitor(command: 'while kill -0 <pid> 2>/dev/null; do sleep 60; done; echo "<id> EXITED"',
        persistent: true, timeout_ms: 3600000)
```

**Whenever a monitor dies, check the AGENT first** (`kill -0 <pid>`) - it is almost always still
alive - then re-arm rather than re-dispatching.

**The `nohup` in step 1 is correct and the monitor in step 2 must NOT use it.** A `nohup ... &`
waiter is a *log*, not a monitor: it cannot wake the orchestrator, so the dispatch finishes and
nothing says so. `OB.2` completed unnoticed exactly that way, and an unwatched `RV.58` is how a fake
RU screenshot nearly reached a commit.

Three rules that come from things that went wrong:

- **Watch the PID, never a process count.** `pgrep -x opencode` breaks the moment anything else on
  the machine runs opencode - a second session's agents made a monitor announce three exits that
  were not its own. `pgrep -f "title <id>"` is not the fix either: `-f` matches any process whose
  arguments merely contain that text, which is how an agent killed a sibling on 2026-08-24.
- **One monitor per dispatch, never one for several.** A combined waiter hides whichever agent
  finishes first.
- **Arm it immediately after the dispatch, every time, with no exceptions.**

## The queue

**Update this file at BOTH ends of a dispatch**: move the row to *In flight* when it launches, and
to *Shipped* when its commit lands. A queue that says a shipped row is still running is worse than
no queue - it is the file a fresh session trusts to know what is already done.

### In flight

| Task | Model | PID | Monitor | Brief |
|---|---|---|---|---|
| **RV.186+RV.188** `[!]` | flash | 1581 | `bw8e4i9sm` (persistent) | `agents/briefs/RV.186+RV.188.md` |

*(`REVIEW-JOURNEYS-CD` finished; its report is `diagnostics/REVIEW-JOURNEYS-2026-09-10.md` and its
findings are filed as `PJ.58`/`PJ.59` in `docs/TASKS.md`, commit `7676039`.)*

**The journeys walk ran in PARALLEL with a build agent deliberately.** The journeys walk is read-only - no edits, no builds,
no tests - so it cannot collide with a build agent on files or on the simulator, and `CLAUDE.md`
says so explicitly. That is the ONLY parallel pair this file sanctions; two build agents still
collide, and two Swift agents starting in the same second still hit `database is locked`.

### Waiting, in order

**Tiers 1 and 2 are EMPTY - every briefed row shipped 2026-09-09/10.** Ten rows: `RV.166`,
`RV.167`, `RV.149`, `RV.160`, `RV.159`, `PJ.57`, `PJ.56`, `RV.163`, `PJ.55`, `RV.162`. The next
dispatch needs a brief written first; tier 3 below is *decided design*, not briefed.

**The three shipped guards now cover each other's blind spots**, and each was built against a live
failing case rather than a hypothetical:

| Guard | Catches | Its stated blind spot |
|---|---|---|
| `RV.167` money aggregation | a `.reduce` over a `Money`'s home side outside the accumulator | the `.reduce` shape only; a `+=` loop walks past (`RV.172`) |
| `RV.163` entity writers | an entity `SCHEMA.md` names that nothing can create | entity-level; `PJ.55` was the FIELD-level instance it cannot see |
| `RV.162` screen routes | a screen whose only door is `#if DEBUG` (`PJ.4`'s shape) | proves a door NAMES the screen, does not walk the view graph (`RV.165`) |

**Tier 3 - decided design, ready to brief.**

**Tier 3 - decided design, ready to brief.**

| # | Task | Why here |
|---|---|---|
| ~~7~~ | **RV.152** | **Briefed and in flight.** The brief pins the seam (`VehicleDetailView.swift:313-328`) and names the restructuring the row needs: RV.140's re-home runs AFTER `upsertVehicle`, and the question has to precede the write |
| ~~8~~ | **RV.116** | **Briefed and in flight.** The brief settles the split the row's wording blurs: the unsupported column NAMES are per-format reference data in `GET /import/formats`, but the COUNT of rows carrying a value is per-file and can only come from `POST /import/parse`. Backend + iOS |
| ~~9~~ | **RV.161** **[v1.1]** | **Briefed and in flight.** The brief solves the row's hardest part - the ORACLE: ground truth for the new corpus column must not come from the extractor's own output. The fixture FILENAMES are human-written from the images and predate any station extractor, so they are the independent source; the OCR dump cross-checks them |

**`RV.181` is committed (`ae775cf`) and the row is STILL OPEN `[!]`.** What shipped is hardening
and a diagnosis, not a fix: the seam now latches only after UIKit accepts the presentation, and it
records the whole completion tuple so a share that FAILED is no longer logged as one the user
cancelled. The cause of the owner's report is **not established** - the diagnosis this queue and
`docs/TASKS.md` both carried ("hosted as a sheet root, so no presenter") is **withdrawn**: UIKit
forwards a presentation up the parent hierarchy, and *Save to Files completes under both shapes*,
which is counter-evidence that was in hand and misread. **Verification needs the product owner's
physical iPhone 13**; no simulator test can settle it. Next device report is diagnosable from the
diagnostics bundle, which it was not before.

**`RV.185+RV.187` SHIPPED (`9588b20`), both rows ticked.** The agent's own report claimed
`swiftlint` exit 0 and two screenshots showing the new name field; **all three claims were false** -
lint exited 2 on a file-length ceiling, and neither frame contained the field (the preview's card is
below the fold, the mapping gate's field was on the second lane). The pre-filled name was also
`"Drivvo"`, the exporter's name, which is the half of the owner's report the agent left in place.
All fixed by the orchestrator before the commit. **The lesson is the standing one, again: read the
exit code, and open every screenshot.**

**IN FLIGHT - `RV.186+RV.188`. Then, in order: `RV.183+RV.184`, `RV.176+PR.28`, `RV.189` (then
`RV.170`), `RV.173` (then `RV.171`).**

| Task | Brief | Why it outranks the queue |
|---|---|---|
| ~~RV.185~~ **shipped `9588b20`** | `RV.185+RV.187.md` | **An imported car ignores the currency the user just declared, and cannot be named.** `TargetCar.newCar` hardcodes `homeCurrency: .eur`, so a declared KZT reaches the ENTRIES but never the car - and every imported row then needs a KZT->EUR rate for its own date, turning a clean import into a log of rate-pending rows. The name comes from the format's display name (`"Drivvo"`) with no field. **Briefed; dispatch NOW** - `RV.181` is off the bench and this is the next user-reported `[!]` |
| ~~RV.181~~ **committed `ae775cf`, row still `[!]` OPEN** | `RV.181.md` | **No share in the app dispatches anything.** Reported by the product owner 2026-09-10: the sheet opens, a destination is chosen, nothing arrives. `UIActivityViewController` is hosted as the ROOT of a SwiftUI `.sheet` at all five call sites, so the chosen activity has no presenter for its own UI. *Export always free* is a launch commitment and `DELETE /account` points users at export to keep their data - today nothing leaves the app. One shared seam (`ActivityView`), so one row, not five. **`PJ.36`/`PJ.38` screenshot the sheet OPEN and their L4s assert it appears** - the half that already worked, which is how this shipped |

## Grouping: what ships together, and why (decided 2026-09-10)

Fifteen open rows collapse to six dispatches. **A group is justified by a shared SEAM, never a
shared theme** - if two rows would edit the same file, or one row is how you diagnose the other,
they are one dispatch. Otherwise the mutation stops being a single named claim, which is the part
that has been catching real defects.

| Dispatch | Rows | Why grouped |
|---|---|---|
| **Import: what the file carries** | `RV.185` + `RV.187` — `RV.185+RV.187.md` | Both are "the parser drops a column the file has" - the declared currency and the `Вид расхода`/`Вид сервиса` name. One agent reads `DrivvoParser` and the commit path once. RV.187 also has a render half |
| **Timeline conflict** | `RV.186` + `RV.188` — `RV.186+RV.188.md` | `RV.188`'s panel is **how you diagnose** `RV.186`. Fixing the validator without the panel leaves no way to confirm it, which is exactly the position the owner and the orchestrator were both in |
| **Attachment viewer** | `RV.183` + `RV.184` — `RV.183+RV.184.md` | Both edit `AttachmentRecognisedView.swift` - the "Scanned" caption reads the wrong field, and the station row is never stored to render |
| **Screenshot integrity** | `RV.176` + `PR.28` — `RV.176+PR.28.md` | `PR.28` **already specifies RV.176's check**: a `manifest.json` written by the capture script, CI failing a PNG with no entry. RV.176 is the defect, PR.28 the mechanism - building either alone touches the same file twice |
| **Station seam** | `RV.189` — `RV.189.md` — **then** `RV.170` | RV.189 is an INVESTIGATION (its cause is not established); RV.170 is the guard for the seam it settles. `RV.170`'s own row says establish the seam first |
| **Receipt seam** | `RV.173` **then** `RV.171` | Same shape. `RV.171` already says *"do RV.149 first, then see what seam it leaves"* - `RV.173` IS that leftover |

**Deliberately NOT grouped**: `RV.187` with `RV.119`/`RV.134` (Log-row work, but RV.119 is a large
`[v1.1]` redesign); `RV.181`, `RV.182`, `RV.174` stay standalone. **`RV.165`** surfaced in three
separate searches for these seams - it is the row that would have caught most of the owner's
findings, and it is large.

**All five briefs are written** (`agents/briefs/`), each with its cause pinned, its mutation named
and its vacuous traps listed. `RV.189` is deliberately an INVESTIGATION brief: its four-step trace is
the deliverable even if no fix follows, and it records the orchestrator's own wrong diagnosis so it
is not repeated.

**The ordering that works, proven today**: build a guard against a seam that has just been settled,
not a hypothetical one. `RV.163` was dispatched before `PJ.55` for that reason and its mutation
reconstructed `RV.156` exactly.

**Ready to brief - cause pinned, no decision outstanding** (added 2026-09-10, all filed from this
session's own findings):

| Task | Why here |
|---|---|
| **RV.173** | A grouped save whose photo write fails leaves its accepted expenses holding a **dangling** attachment id. `RV.149`'s deliberately fenced-out half; the outcome type it needs already exists |
| **RV.176** | Committed screenshots **no capture line produces** - `RV.150`'s station pair was shot out-of-band. Mechanical (diff the names against the script) and then a check, mirroring the duplicate-frame check `4bbb302` added |
| **RV.175** | About has no screenshot scroll hook, so its lower half cannot be photographed - it cost `RV.159` its XL frame, which was deleted rather than committed |
| **RV.179** | Measure station extraction. **The oracle is the row's whole content** and it is already solved there: the fixture filenames predate any extractor |
| **RV.174** | The baseline gate can be green on code that does not compile into the app. Proposes hard-rule-14 wording - **the owner approves the wording**, the agent does not edit `CLAUDE.md` |

**Tier 4 - needs something first.**

| Task | What it needs |
|---|---|
| **RV.155** | **Re-check before briefing.** It was filed with the 40-second push as its hypothesised cause, and `RV.154` removed that window. It may already be gone - a cheap look at one device log settles it |
| **RV.158** | A query against the deployed service: what date range does `/v1/rates/pack` actually cover, per currency? Product decision follows the answer |
| **RV.164** | Decide what is mechanisable in the ERRORS audit before briefing; a rule that cannot fail is not worth shipping |
| **RV.165** | The journey suite. Large, and `RV.162`/`RV.163` catch a chunk of the same class for a fraction of the cost - do those first |
| **RV.168** | Half-implemented already (`TEMPLATE.md` carries both rules). Its acceptance is **manual**: check the next three briefs actually name their mutation and source their oracles |
| **RV.143** | Overlaps `RV.152`'s territory. Settle the prompt first, then see what is left |
| **RV.169** / **RV.170** / **RV.171** | **Establish the seam before writing the guard.** All three came from `RV.167`'s "which further guards are worth a row" line. Each asks whether the tree HAS one owner today - a guard over a convention guards nothing - so each needs a cheap look first. `RV.171` waits on `RV.149` specifically: do the fix, then see what seam it leaves |
| **RV.172** | Nothing to do unless a non-`reduce` money sum appears. Filed so `RV.167`'s coverage limit is written down rather than remembered |

### Not queued, and why

- **RV.148** - the monthly-summary push summing a partial month. **Deferred by the product owner,
  2026-09-09** (*"with monthly results - we will come to it later"*). Not blocked on a decision that
  is coming; parked deliberately. The row keeps its two candidate answers - suppress while partial,
  or mark the figure in the body - for whenever it is picked up.

- **RV.139** - the instrumentation shipped ([RV.139b], `e92d147`); the next step is ONE device log
  from a build carrying the `rates.refresh` event. That is the product owner's, not an agent's, and
  queueing it would invite a fifth speculative fix.
- **RV.143** - a home-currency change arriving by sync re-homes nothing on the receiving device.
  Overlaps [RV.152]'s territory; decide the prompt first, then see what is left.
- **RV.153's leftovers** - `receipt-055`'s volume still reads 17.56 against a true 77.56. That needs
  P2.9's decimal ladder and was deliberately out of RV.153's scope.

### Shipped this session (2026-09-08/09)

| Task | Commit | What it was |
|---|---|---|
| RV.112 | `2efb9e3` | The vitals tile and Trends series stopped reporting a pending month as zero |
| RV.139-INVESTIGATE | `2efb9e3` | Read-only: three of RV.139's four candidates dead on a line each (`diagnostics/RV.139-INVESTIGATE.md`) |
| RV.144 | `5471bac` | An entry edit re-homes to the car's current home currency, and resolves at commit |
| RV.139b | `e92d147` | Observability so the next device log can answer RV.139; the row itself stays open |
| RV.136 | `85ba6d5` | A pull no longer re-dirties a Vehicle that did not change |
| RV.145 | `628d000` | A money figure carries its own currency; symbols everywhere. **RU screenshots re-captured by the orchestrator** |
| RV.146 | `20034fe` | The currency offer adapts to the car, the history and the region |
| RV.147 | `62d0516` | Cost-per-km declines to report a figure it cannot state; filed RV.148 from its finding |
| RV.117a | `e249a13` | The valid interval in core - the substance half of RV.117 |
| PJ.28 | `8005181` | A scanned expense keeps its receipt; filed RV.149 from its finding |
| PJ.25 | `8d6324e` | The parts shelf has a door from the Garage |
| PJ.19 | `b6ea56d` | The station suggestion is built and never required; filed RV.150 from its finding |
| RV.157 | `7ad268f` | A local write schedules a sync 3 s later; the seam is the DB write signal |
| RV.154 | `16f1a1f` | A push costs 3 DB commands for the batch, not 3 per record |
| RV.156 | `2328757` | A station can be created, from the entry row and the Garage |
| RV.136 (reopened) | `0011cc3` | Vehicle compared at the decoded level - the third arm of the echo loop |
| RV.153 | `974be77` | A computed total no longer beats a printed one - main green again |
| RV.151 | `9760bfe` | The rate lookup derives the cross rate through the pack's base - the owner's 381 pending rows |
| RV.150 | `bc907c3` | A save writes the station fields the ranking reads; the location capture is the owner's decision, bounded |
| RV.117b | `6d833a7` | The conflict neighbourhood, drawn - RV.117 is now complete |
| RV.162 | `5c53a4f` | A screen whose only door is `#if DEBUG` fails the build - `PJ.4`'s shape. **The agent corrected the brief three times**, including a stale doc claim the brief had repeated: the car-limit sheet's "Pro" is not Paywall's live v1 door, `RV.70` removed it too |
| PJ.55 | `c933a3b` | The station ranking's first rung can finally fire. **The strongest mutation of the session**: dropping only the persist call turned red on the RANKING, not the flag - the field had a column, a decoder, ten seeds and a reader for months and rung 1 still never fired |
| RV.177 + RV.178 | `e4766fb` | The currency question became a sheet with a real hierarchy, and **no Cancel** - Save means Save. Its mutation SAMPLES rendered pixels, the first test here that can see "these two look identical" |
| RV.161 | `17f6294` | A scanned receipt keeps its station - **ticked PARTIAL** (the brand/site split is `RV.180`) and **unmeasured**. Its corpus column was self-scored at 46/46 and was reverted whole; `RV.179` measures it against an oracle the extractor cannot see |
| RV.116 | `fe94b0f` | An import says what it is not bringing in |
| RV.163 | `3a72037` | An entity nothing can create fails the build. The mutation removed both `createStation` doors while leaving the table, the decoder, the import writer and ten seeds in place - **RV.156 reconstructed exactly**. Entity-level; `PJ.55` is the field-level instance it cannot see |
| PJ.56 | `c87ca1b` | A group header that withholds a figure says why. **The screenshot caught a pre-existing sibling** - the divider printed "0 entries pending rates" under a complete breakdown, invisible until this row rendered the app's first `.mixed` month |
| PJ.57 | `170bf91` | The excluded-entries footnote carries RV.83's chevron; amber untouched. **The brief's premise was partly wrong and the agent said so** - nothing renders the footnote passively, so that assertion needed a DEBUG seam or it was vacuous |
| RV.159 | `a4dac65` | A sending gate is drawn as a gate, not an optional attachment. **Its agent died mid-run and the orchestrator finished it** - including a compile error three green gates could not see (`RV.174`) |
| RV.149 | `0044e04` | A fill-up's lost receipt photo is reported, not swallowed; one shared sentence, renamed off "expense". **Its screenshots were re-posed by the orchestrator** - the agent's pair showed a correct toast over the empty-garage state, which no user saving a fill-up can be in |
| RV.160 | `16ab0cb` | A terminal outcome collapses the composer into a confirmation panel. The old caption sat **113-133 points under the fold** - measured by the mutation, not asserted |
| RV.141 | `85ba6d5` | The excluded-entries count reaches its entries and says why they are out |
| RV.167 | `62b61d2` | The aggregation-bypass guard: a `.reduce` over a `Money`'s home side outside the accumulator now fails the build, in BOTH source roots. `RV.148` is parked as the one reasoned exception, and landing it must delete the park |
| RV.166 | `378ee65` | A purchase group's header stops summing a rate-pending line as zero - the sixth instance of the shape, and the reason `RV.167` now has only ONE failing case left |
| *(no row)* | `4bbb302` | **Screenshot hygiene, found by reading the capture script.** Ten pairs of capture lines shot the SAME frame under two names (21 of 248 lines), and only one name of each pair was ever re-shot - so the set held ten stale twins, `P1.1-shell-dark` six builds behind its identical `P1.4-home`. Frames are now captured once and copied (`alias_shot`), a post-run md5 pass fails an eleventh pair, `P1.5-log-stream` finally shows a log row instead of a second copy of Home, and `RV.141` got the screenshot its own scroll hook had no capture line for |

**Still open and NOT queued**: `RV.139` itself - the symptom is unfixed and the next step is one
device log from a build carrying the `rates.refresh` event, which is not agent work.

## SKIP_BUILD=1 after a mutation photographs the MUTATED app

2026-09-10, `RV.177`. The orchestrator mutated the sheet, watched the test go red, restored the
source byte-identically, then re-captured with `SKIP_BUILD=1` - which reuses the **already-built**
binary. The frame showed both buttons filled taillight: the defect itself, committed as proof of the
fix. Caught only by opening the image; the file was written and the script reported `ok`.

**`SKIP_BUILD=1` is safe only when nothing has touched the source since the last build.** After a
mutation - or any edit - it is exactly wrong. The script's own header warns that a stale capture is
evidence for the wrong code; this is that warning, from the inside.

## A 100% score on a new class is evidence of circularity, not quality

`RV.161`, 2026-09-10. A fresh extraction class was added to the corpus and scored **46 of 46**. It
was a tautology: the ground truth had been written from the extractor's own output, and because
**the scorer skips an empty cell rather than counting it a miss**, every case the extractor failed
was silently left blank. `receipt-007-lukoil` scored as "no ground truth" while its OCR's first line
reads `"ЛУКОНЛ-СЕВЕРО-ЗАПАДНЕФТЕПРОДУКТ"`.

**When a brief adds a corpus column, it must name the oracle and forbid the obvious one.** The
fixture filenames are the source here - the product owner wrote them from the images before any
extractor existed - and the OCR dump cross-checks them, because it is the extractor's INPUT.

**Two guards caught the orchestrator's own half-fix**, which is why the revert had to be total:
`assertedStation > 0` refuses a column that measures nothing, and `CorpusCompressionTests` keeps a
recorded mark **separate** from `high-water.json`, so reverting one leaves the pair inconsistent.

## Check the COUNT, not the exit code - three times in one session

2026-09-10, all three green with exit 0 and all three worthless:

- `PJ.56`: a combined `xcodebuild` invocation silently dropped a `TankbookTests` filter and reported
  3 tests instead of 8.
- `RV.161`: `-only-testing:TankbookUITests/RV161StationPrefillUITests` matched **nothing** - the file
  declares `extension ConfirmManualUITests`, so the class-name filter found no such suite. Output:
  `Executed 0 tests` … `TEST SUCCEEDED`.
- The orchestrator's own edit removed a test while tidying, and the run went green at 5/5 where 6
  functions existed.

**A filter matching nothing is the default failure, not the exception.** Grep the `@Test`/`func
test` count in the file and compare it to `Executed N tests`; if `Executed` is absent from the
output entirely, that is not a pass either.

## The recurring journeys walk

**It is a standing item on this queue, not an event.** `CLAUDE.md` sets the cadence: **every 10
shipped rows or at a phase gate, whichever comes first**, plus the four event triggers in
`agents/briefs/REVIEW-JOURNEYS.md` (a screen ships; a reader of an entity ships; copy naming a
destination ships; a row ships partially).

**Dispatch it in parallel with whatever build agent is running** - it is read-only, so it costs
nothing but tokens and it is the cheapest tool here. The argument, from the brief's own run
history: it ran **once** between 2026-08-29 and 2026-09-09 while **643 commits** landed, and every
product-reachability gap in `docs/DEFECT-PATTERNS.md` Part 2 was found either by that run or by the
product owner using the app - never by a test, a code review or the type checker.

Each run gets its **own dated brief file** narrowing the recurring one to that run's scope, so the
run history stays honest about what was and was not walked:

| Run | Brief | Scope | Yield |
|---|---|---|---|
| 2026-08-29 | `REVIEW-JOURNEYS.md` (4 agents) | all groups | 66 `PJ` rows |
| 2026-09-09 | `REVIEW-JOURNEYS-2026-09-09.md` | deep on J4 / J7b / money+rates / feedback | `PJ.55` |
| 2026-09-09b | `REVIEW-JOURNEYS-2026-09-09b.md` | **Group A + Group B** - the half the morning run left | `PJ.56`, `PJ.57`; **0 ticked-but-untrue** |
| 2026-09-10 | `REVIEW-JOURNEYS-2026-09-10.md` | **Group C + Group D** - never walked before. C is import/currency/F6/F9, where **six of the owner's ten reported defects live** | *in flight* |

**Next run: whatever the C+D walk does not reach**, and a re-walk of A/B once the owner's current
findings ship.

## What can run in parallel, and what actually limits it (measured 2026-09-10)

**Two agents, and only ONE may touch the simulator.** File-disjointness is not the binding
constraint:

| Limit | Effect |
|---|---|
| **Simulator** | One `iPhone 17`. Two agents running `xcodebuild test` or `simctl` fight and both lose - the capture script refuses a run for this reason |
| **Memory** | Two agents died at 300-500 KB today, and an orchestrator gate run was OOM-killed with ~75 MB free. **This is the real ceiling** |
| **`opencode` DB** | `database is locked` when two start in the same second - stagger, do not serialise |
| **Files** | `RV.185+RV.187` collides with `RV.189` (both import); `RV.187` collides with `RV.186+RV.188` (both render the Excluded-entries list) |

**The safe pair is one build agent + the read-only journeys walk** - no writes, no simulator, no
builds. `RV.176+PR.28` looks like tooling but runs the capture script to prove its manifest, so it
needs the simulator and is **not** a free parallel slot.

## Models available here (checked 2026-09-10)

`deepseek/deepseek-v4-flash` (the default for a pinned-cause row), `deepseek/deepseek-v4-pro` (the
journeys walk and validation), `deepseek/deepseek-v4-flash-vision-exp`, and the
`alibaba-token-plan/*` mirrors including `deepseek-v4-flash-0731` and `deepseek-v4-pro-0813`.
**There is no `v4.1` in this install** - re-check `opencode models` before assuming one, because
flash-at-pro-quality would change the routing rule.

**`-vision-exp` is NOT worth using, and the reason is the one that matters** (product owner, 2026-09-10). The orchestrator can already open a screenshot, so vision buys the agent nothing the process lacks - and giving the agent eyes would let it **grade its own work**. That is exactly the circularity that produced `RV.161`'s fake **46/46**: ground truth written from the thing under test. The value of the orchestrator opening a capture is not that *someone* can see it, it is that a **different party** sees it - one that did not write the code. That independence caught `RV.149`'s toast over an unreachable screen, `PJ.56`'s `0 entries pending rates`, and the orchestrator's own re-capture of a mutated binary. **Keep the screenshot check with the orchestrator; it is a separation of duties, not a capability gap.**

## When an agent dies mid-run, FINISH it - do not re-dispatch by reflex

`RV.159`, 2026-09-10: the agent died at **373 KB** of log (the memory-pressure zone this file
already names) with no report, but its work was **complete on disk** - code, five UI tests, L1
additions, `DESIGN.md` and `ERRORS.md`. Re-dispatching would have redone all of it and risked
colliding with another session that was live in the same checkout.

**Check what is on disk before deciding.** A dead dispatch at ~17 KB with no writes is a wedged
provider - kill and retry the same brief. A dead dispatch at 300 KB+ with a full diff is a task that
needs **finishing and verifying**, which is orchestrator work anyway.

**And run every gate yourself regardless**, because a dying agent stops at whatever gate it had
reached. `RV.159` had not run `xcodebuild` at all, and its code **did not compile into the app** -
while `swift build`, `swiftlint` and all 1826 package tests were green (`RV.174`).

## Standing rules for every dispatch here

- The brief is written to `agents/briefs/<id>.md` **before** dispatch and passed by `cat`, so the
  brief on disk is exactly what the agent received.
- Health-check ~5 minutes in by **log bytes**. Zero bytes is wedged; freshness proves nothing,
  because nothing is written during model inference.
- The orchestrator verifies in its own hands - gates by exit code, and **opens every screenshot**.
  An agent has no image input and cannot see what it produced.
- Agents never commit and never tick `docs/TASKS.md`.
- When a row ships, three files move together: the code commit, the `docs/TASKS.md` tick (the row
  moves to `docs/TASKS-DONE.md`, then `scripts/tasks-index.py` rebuilds the index), and this queue.
  Skipping the third is how the queue goes stale within one session.
