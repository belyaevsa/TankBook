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

**Update this file at BOTH ends of a dispatch**: add the row to *In flight* when it launches, and
REMOVE it when its commit lands. A queue that says a shipped row is still running is worse than no
queue - it is the file a fresh session trusts to know what is left. Shipped rows leave this file
entirely; `docs/TASKS-DONE.md` and `docs/TASKS-HISTORY.md` are where they go.

### In flight

| Task | Model | PID | Monitor | Brief |
|---|---|---|---|---|
| **RV.198** `[!]` | flash | 80286 | `bzqqqa6mk` (persistent) | `agents/briefs/RV.198.md` |
| **REVIEW-SERVICE** *(read-only)* | pro | 92830 | `b2j4nvrb1` (persistent) | `agents/briefs/REVIEW-SERVICE-2026-09-10.md` |
| **RV.165** | flash | 47325 | `bapnem413` (persistent) | `agents/briefs/RV.165.md` |

**The only parallel pair this file sanctions is a build agent plus the read-only journeys walk** -
no edits, no builds, no tests, so it cannot collide on files or on the simulator, and `CLAUDE.md`
says so explicitly. Two build agents still collide, and two Swift agents starting in the same second
still hit `database is locked`.

### Waiting, in order

**Nothing is briefed and unshipped except `RV.189`.** The queue is **brief-bound, not agent-bound**:
every other dispatch below needs a brief written first.

**The four shipped guards cover each other's blind spots**, and each was built against a live
failing case rather than a hypothetical. Their blind spots are the argument for `RV.165` and
`RV.172`:

| Guard | Catches | Its stated blind spot | Closing it |
|---|---|---|---|
| `RV.167` money aggregation | a `.reduce` over a `Money`'s home side outside the accumulator | the `.reduce` shape only; a `+=` loop walks past | **`RV.172` CLOSED as a decision** - the grep finds no such site, and widening a guard against a hypothetical is the one thing the sequencing rule forbids |
| `RV.163` entity writers | an entity `SCHEMA.md` names that nothing can create | entity-level; `PJ.55` was the FIELD-level instance it cannot see | **`RV.196`, briefed** - and its instances are LIVE: `Settings.anomalies` and `eagerMediaOnWiFi` are decoder-only |
| `RV.162` screen routes | a screen whose only door is `#if DEBUG` (`PJ.4`'s shape) | proves a door NAMES the screen, does not walk the view graph | **`RV.165`, IN FLIGHT** - four journeys from a cold launch, plus a guard that fails a journey passing a navigation argument |
| `RV.176` screenshot manifest | a committed PNG no capture line produces | proves a line EXISTS, not that it reproduces that frame | **`RV.194`, briefed** - narrow 470 frames to a suspect list by comparing below the status bar |

**One row is committed but deliberately NOT closed.** `RV.181` (`ae775cf`) shipped hardening and a
diagnosis, not a fix: the share seam now records the whole completion tuple, so a share that FAILED
is no longer logged as one the user cancelled. The cause is **not established** and the earlier
"hosted as a sheet root, so no presenter" diagnosis is **withdrawn** - UIKit forwards a presentation
up the parent hierarchy, and *Save to Files completes under both shapes*, which was counter-evidence
in hand and misread. **Verification needs the product owner's physical iPhone 13**; no simulator test
can settle it.


### The product owner's own reports - all resolved

Twelve defects were reported by using the app on 2026-09-09/10. **Eleven shipped**; `RV.181` is
**skipped by the owner** (see *Not queued, and why*) and is the only one left.

**`RV.189` was the last, and it is the row that argues for the method.** Its evidence table named
four links and every one of them held on inspection - the parser read the column, the wire carried
it, the conversion stamped it, the commit materialised the row. The value was dropped **between**
them, in a copy helper no link covered. **Audit each link and you find nothing; trace the value end
to end and you find it in one run.**

### Briefed and ready, in order

Shipped rows have left this table; `docs/TASKS-DONE.md` has them.

| # | Task | Brief | Note |
|---|---|---|---|
| ~~1~~ | ~~**PJ.23**~~ **shipped `fd57e7b`** | `PJ.23.md` | **PRIORITY since 2026-08-31.** Its Expense half shipped as `RV.195` without anyone noticing the row existed; the SERVICE half remains, and `RV.195` is its worked example one entry kind over |
| 2 | **PJ.34** | `PJ.34.md` | **PRIORITY since 2026-08-31**, unblocked by `RV.192`. Bigger than the row says: **no caller passes `attachments:`**, so the receipt-date ranking has never run, and **nothing renders `suggestions` at all** |
| 3 | **PJ.26+PJ.27** | `PJ.26+PJ.27.md` | **PRIORITY since 2026-08-31.** The J7b tire loop. `TireSet.purchaseExpenseId` is `PJ.55`'s dead-field shape a third time |
| 4 | **RV.173** | *needs one* | A mixed receipt whose photo write fails leaves its accepted expenses holding a dangling attachment id. `RV.149`'s deliberately fenced-out half |
| 5 | **RV.171** | *needs one* | Sequenced after `RV.173`, same reason `RV.170` was sequenced after `RV.189` |
| 6 | **RV.194** | `RV.194.md` | `RV.176`'s blind spot. **Slow** - a full 470-frame capture - and its final judgement is the orchestrator's, because an agent cannot see an image |

### Filed 2026-09-10, no brief yet

| Task | Why it is worth a brief |
|---|---|
| **RV.194** | The 138 reconstructed capture lines were never run. A wrong line is worse than none - the check goes green on a line EXISTING, not on it reproducing the frame, which is the failure `RV.176` was filed against. Also: frames caught mid-transition, with a previous screen's header bleeding through |
| **RV.191** | RU: the import picker's dead-end card falls below the fold at the real format count (hard rule 7's next step, found by re-shooting the screenshot honestly) |
| **PJ.58** | A SECOND hardcoded `.eur`, on service line-item costs - outside `RV.185`'s fence and invisible to `RV.167`'s guard |
| **PJ.59** | `RecentlyDeletedView`'s "Overwritten by sync" is still a fixture while `PR.14` is ticked |
| ~~RV.195's leftover~~ | **It was `PJ.23` all along** - PRIORITY since 2026-08-31, briefed now. Filing it as a new finding is the duplication this queue keeps producing; see `RV.110`/`RV.165` |

### Standing, unbriefed

`RV.164` (an error names a next step that does not exist), `RV.165` (full-journey scenarios),
`RV.168` (how briefs ask for proof), `RV.169`/`RV.170`/`RV.171`/`RV.172` (the four guards awaiting
their seams), `RV.148`/`RV.155`/`RV.158` (sync and rates), `RV.174` (the baseline gate can be green
on code that does not compile into the app), `RV.182` (the tank pre-fill, decision made, no brief).
**Ten `PJ` rows are marked PRIORITY by the product owner (2026-08-31) and none has been briefed.**

**The recurring journeys walk is due**: it runs every 10 shipped rows or at a phase gate. Eleven
rows shipped since Groups C+D on 2026-09-10.

## The service loop is under review, 2026-09-10

`PJ.23` shipped and the product owner immediately found what it did not do - add and delete a line -
which J7's own Fallbacks sentence has promised since the journey was written (*"the user
renames/splits by hand"*). **Six rows touch this loop and none owns it**: `PJ.23` (shipped),
`RV.198` (in flight), `RV.199`, `PJ.22`, `PJ.26`, `PJ.27`.

Rather than group them by theme - which this file's own rule forbids - `REVIEW-SERVICE` is walking
J7/J7b/J7d/J7c end to end and will come back with **either a grouped dispatch list whose seams are
named, or a reasoned "leave them as they are"**. It also owns a blind spot neither guard can cover:
**`TireSet` has no `###` section in `docs/SCHEMA.md`**, so `RV.163` and `RV.196` cannot see any of
its fields, including the dead `purchaseExpenseId` that `PJ.26` exists to write.

**Do not brief `PJ.22` or dispatch `PJ.26+PJ.27` until that report lands** - they are the two rows
most likely to be regrouped by it.

## Grouping: what ships together, and why (decided 2026-09-10)

**A group is justified by a shared SEAM, never a shared theme** - if two rows would edit the same
file, or one row is how you diagnose the other, they are one dispatch. Otherwise the mutation stops
being a single named claim, which is the part that has been catching real defects. Four groupings
shipped on 2026-09-10 and the rule held every time; two remain:

| Dispatch | Rows | Why grouped |
|---|---|---|
| **Station seam** | `RV.189` - `RV.189.md` - **then** `RV.170` | `RV.189` is an INVESTIGATION (its cause is not established, and the brief records the orchestrator's own WRONG diagnosis so it is not repeated). `RV.170`'s guard needs the seam that row settles, so it cannot be written first |
| **Receipt seam** | `RV.173` **then** `RV.171` | Same shape. `RV.171` already says *"do `RV.149` first, then see what seam it leaves"* - `RV.173` IS that leftover |

**Deliberately NOT grouped**: `RV.187`'s Log-row work with `RV.119`/`RV.134` (`RV.119` is a large
`[v1.1]` redesign); `RV.181`, `RV.182` and `RV.174` stay standalone.

**Check the backlog for the row before filing a finding as new.** Twice on 2026-09-10 a finding was
filed that an existing row already carried: `RV.195`'s "leftover" was `PJ.23`, PRIORITY since
2026-08-31, and `RV.165` duplicated `RV.110`. Both pairs were found by reading the list, not by the
process. **A new row costs nothing to file and something real to discover twice.**

**The ordering that works, proven twice**: build a guard against a seam that has just been settled,
never a hypothetical one. `RV.163` was dispatched after `PJ.55`'s seam for that reason and its
mutation reconstructed `RV.156` exactly; `RV.170` and `RV.171` are sequenced the same way.


### Not queued, and why

- **RV.181** `[!]` - *"I select a destination, but nothing is dispatched."* **SKIPPED by the product
  owner, 2026-09-10.** The row stays OPEN and unfixed; it is simply not being worked. `ae775cf`
  shipped the hardening and, more usefully, the outcome record: a share that fails at its
  destination is now logged as `failed` with its activity type and error code, where before it was
  indistinguishable from a cancel. **So the next report of this is answerable from a diagnostics
  bundle**, which is what makes skipping it cheap now and expensive-to-diagnose never. Nothing here
  is agent work: it does not reproduce on the simulator, and the only remaining evidence is one
  share attempt from a physical device.

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
