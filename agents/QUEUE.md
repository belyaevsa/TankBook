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

**Every entry here names its parent scenario** (standing instruction, 2026-09-10) - the journey id
from `docs/JOURNEYS.md`, or `no-scenario:` with a reason. `scripts/scenario-index.py` is the map, and
`--check` fails an open `docs/TASKS.md` row that names none.

**Update this file at BOTH ends of a dispatch**: add the row to *In flight* when it launches, and
REMOVE it when its commit lands. Shipped rows leave this file entirely; `docs/TASKS-DONE.md` and
`docs/TASKS-HISTORY.md` are where they go.

**Reordered 2026-09-11** against `docs/analysis/2026-09-11-process-and-backlog-review.md`. Two
rules changed the order and the shape of what is queued:

- **The seam is the unit of dispatch, not the row.** A brief covers every entry kind, door or
  screen that shares the code it changes, and its L1 asserts the behaviour from each one in the same
  test file (the `RV.201` shape). The agent is **authorised** to fix a sibling in the same run when
  it is the same function or line, and **files** when it is a different decision. 37 of 214 RV rows
  were siblings filed one at a time; that stops here.
- **Walk the scenario before briefing its group.** `REVIEW-SCENARIO.md` runs first, its promise
  list clusters into seams, each seam gets one brief. The after-the-fact review still runs and
  should find nothing.

### In flight

| Task | Scenario | Model | PID | Monitor | Brief |
|---|---|---|---|---|---|
| `RV.220+RV.221+RV.191` | F6b, F6 | flash | 63484 | `bfq…` (session) | `RV.220+RV.221+RV.191.md` - via `scripts/dispatch.sh`, healthy at 21 KB / 60 s |

**Scenarios 1 (J5 + F5) and 2 (F8) IMPLEMENTED; 3 (F6b + F6) in flight.**

**The mechanisation landed 2026-09-11** (`2ca6754`): `agents/briefs/PREAMBLE.md` carries the fences once and
`scripts/dispatch.sh <id> [model]` appends it, launches, checks bytes at 60 s and retries once. The two-bundle
rule is in `CLAUDE.md`. **Every brief in the queue is written** (`f262cb0`).

### The goal is a scenario, one at a time (product owner, 2026-09-11)

*"Set the queue with a goal to complete the defined scenarios / journeys, one after another."*
The unit of work is now a **scenario**, not a row. Each scenario below is worked to its end: its
v1 rows shipped as seam briefs, then `REVIEW-SCENARIO` re-run, then - on IMPLEMENTED - the status
line under its heading. **Nothing from the next scenario is dispatched until the current one has
its verdict.** `scripts/scenario-index.py` is the map; since 2026-09-11 a row deferred to
`[v1.1]`/`[v1.x]`/`[v2]` is listed but does not hold a v1 story open (the review marks it N/A).

**Already implemented:** `F3`, `J5`, `F5`, `F8` (2026-09-11). **Ready for review with no v1 rows open:** `F4`, `F6a`,
`F7`, `J1`* , `J6`, `J9` - walk them next, they cost nothing (*`J1` has `PJ.51`, see scenario 9).

The order is cheapest-to-close first while the seams are fresh, then the core journey, then the
service loop, then the launch blockers that are single rows on otherwise-finished stories.

| # | Scenario | v1 rows to close | Briefs (by seam) | Then |
|---|---|---|---|---|
| 1 | ~~**J5 + F5** the fiscal QR~~ | `RV.219` shipped `96d05ae` | - | **DONE 2026-09-11** - both re-walked IMPLEMENTED, two status lines from one line of code |
| 2 | ~~**F8** permissions and hardware said no~~ | `RV.222`, `RV.223` shipped `bb7887a` | - | **DONE 2026-09-11** - re-walked IMPLEMENTED |
| 3 | **F6b + F6** the import review row | `RV.220` (bug, first), `RV.221`, `RV.191` | one - `ImportReviewView`'s row, EN+RU | re-walk both |
| 4 | **F2** scan recognized wrong data | `RV.218` | one - the outlier flag from the one `ConsumptionEngine` | re-walk |
| 5 | **F1, F9a, J3b** - one row each | `RV.164`, `RV.211`, `RV.134` | three small briefs, or one if the seams touch (`RV.164` and `RV.211` are both error-surface rows) | re-walk each |
| 6 | **J3** the five-second fill-up - the core journey | `RV.197`! (guest never sees the fill), `RV.208`! (dangling ids on phones), `RV.204`, `RV.209`, `RV.215`, `RV.216`, `RV.217` | **`RV.197` and `RV.208` first, alone** - they are on users' phones. Then the Inbox card (`RV.216`+`RV.217`), the receipt-persistence decisions (`RV.204`+`RV.209`), the deferred producer (`RV.215`). All five briefed | re-walk `J3` and `J8b` (`RV.181` stays skipped by the owner - the review marks it as such) |
| 7 | **J7 + J7b + J7c + J7d** the service loop | `RV.212`, `RV.213`, `RV.224`, `RV.214`, `PJ.60`, `PJ.61` (+ `RV.205` needs photographs) | the service create door (`RV.212`+`213`+`224`), the save gate (`RV.214`, closing `PJ.50` against `RV.206`), then **decide** `PJ.60`/`PJ.61` with the owner - `PJ.61` after `RV.207` | re-walk all four; `RV.205` is N/A until a non-fuel receipt exists |
| 8 | **J11, J11a, J10, J2, F9, F10** - launch blockers on finished stories | `RV.155`, `RV.108`, `RV.143`, `PJ.58`!, `RV.158`+`RV.138`, `PJ.59` | one brief each except `F9`'s pair | re-walk each |
| 9 | **J1** first launch | `PJ.51` - the listing promises what the build does not ship | the owner's copy decision, then one brief | re-walk; `PJ.42` is N/A |
| 10 | **J4** pump display | `RV.115`, `RV.114`, `RV.179` | `RV.115` is a product call; the other two wait for photographs | walk when the corpus exists |
| 11 | **J8, J13** | `RV.148` (owner-deferred), `RV.181` (owner-skipped) | none - both are the owner's calls | walk and mark N/A with the owner's reason |

**Cross-cutting, before scenario 6**: `RV.174` (the gate can be green on code that does not
compile into the app) and `RV.207` (the field guard's pass-through blind spot). Both are
`no-scenario` and both make every later dispatch safer; `RV.207` gates `PJ.61`.

**Cross-cutting, before the next dispatch at all**: the mechanisation - `agents/briefs/PREAMBLE.md`,
`scripts/dispatch.sh` (launch, log, 60-second byte check, one retry), and the two-bundle rule.

### Hardening and tooling - post-launch by their own markers

`PR.19`, `PR.21`-`PR.26`, `PR.32`, `PR.33`, `PR.36` (all `[v1.0.x]`), `RV.109`, `RV.129`, `RV.130`,
`RV.168`, `RV.169`, `RV.175`, `RV.194` (briefed - slow; when a simulator is idle for an hour),
`RV.203`, `RV.210`, `RV.225`, `T.3`. None blocks a scenario.

### Not queued: deferred v1.1 / v1.x and the v2 agent

Thirty-one rows carry `[v1.1]` or `[v1.x]` and most say *PRIORITY (product owner, 2026-08-31)* or
*DEFERRED* in their own text - they are the point-release plan, not v1 debt. The seventeen `AG` rows,
`PJ.18`, `PJ.46`, `PJ.49`, `PJ.52` and `RV.123` are the v2 agent and its paywall. `SH.1`-`SH.3` are
the owner's own TestFlight and store work.

**Check the backlog for the row before filing a finding as new.** Twice on 2026-09-10 a finding was
filed that an existing row already carried (`PJ.23`, `RV.110`). **A new row costs nothing to file
and something real to discover twice.**

**The ordering that works, proven twice**: build a guard against a seam that has just been settled,
never a hypothetical one (`RV.163` after `PJ.55`, `RV.170` after `RV.189`, `RV.171` after `RV.173`).

### Shipped rows are not in this file

A queue that carries its own history stops being readable as a queue. `docs/TASKS-DONE.md` holds
every closed row with the reasoning that closed it; `docs/TASKS-HISTORY.md` holds which model ran
which dispatch and what verifying each one actually caught.

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
| 2026-09-10 | `REVIEW-JOURNEYS-2026-09-10.md` | **Group C + Group D** - never walked before. C is import/currency/F6/F9, where **six of the owner's ten reported defects live** | `PJ.58`, `PJ.59`; amplified `RV.187` to data loss |

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
