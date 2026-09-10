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
| **RV.163** | flash | 12703 | `bza0bkxgq` (persistent) | `agents/briefs/RV.163.md` |

**These two run in PARALLEL deliberately.** The journeys walk is read-only - no edits, no builds,
no tests - so it cannot collide with a build agent on files or on the simulator, and `CLAUDE.md`
says so explicitly. That is the ONLY parallel pair this file sanctions; two build agents still
collide, and two Swift agents starting in the same second still hit `database is locked`.

### Waiting, in order

**Every Tier 1 and Tier 2 row below is BRIEFED and ready to dispatch with no further input.**
Each brief is at `agents/briefs/<id>.md`, assembled from `TEMPLATE.md`, with its cause pinned to a
line, its sibling inventory done, its mutation named and its design questions closed. Dispatch them
in this order; the only reason to stop between them is to verify and commit the one before.

**Tier 1 - live defects, causes pinned, small.**

| # | Task | Brief | Why here |
|---|---|---|---|
| 1 | **PJ.55** | `PJ.55.md` | **Unblocked 2026-09-09**: the product owner chose *give `favorite` a writer, in the Garage*. The long-press variant and deleting the rung were both offered and not taken. Ten test seeds write this field, which is why the guard rows below matter |

**Tier 2 - guards that stop the recurrence, cheapest first.**

| # | Task | Brief | Why here |
|---|---|---|---|
| 6 | **RV.163** | `RV.163.md` | "Who creates this entity?" - would have caught `RV.156` and `PJ.55`. Its failing case is `PJ.55`, so **dispatch it BEFORE PJ.55 ships** or the brief must find another; the brief says so |
| 7 | **RV.162** | `RV.162.md` | Screen reachability over `SCREENMAP.md`. **Its first deliverable is not the test**: the planned-not-drawn list is a prose paragraph at `SCREENMAP.md:477` mixing five rows of history, so the marker has to be made machine-readable before a guard is writable at all |

Both follow `RV.167`'s shipped idiom (`MoneyHomeSideSumGuardTests`): a pure function over source
text, a tree walk, and a reasoned allowlist with a stale-entry check. Both briefs say to read it
first, so the third guard does not invent a third way.

**Tier 3 - decided design, ready to brief.**

| # | Task | Why here |
|---|---|---|
| 7 | **RV.152** | The home-currency prompt. Design fully closed by the owner's decisions; `RV.151` unblocked its convert answer |
| 8 | **RV.116** | An import must say what it is NOT bringing in |
| 9 | **RV.161** **[v1.1]** | Extract the station from a scanned receipt. Only worth doing now that `RV.156` gives it somewhere to land |

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

**Next run: Group C + Group D**, which neither run today covered.

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
