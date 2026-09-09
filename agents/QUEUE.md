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
| **RV.151** | flash | 25440 | `bbix9u1gf` (persistent) | `agents/briefs/RV.151.md` |

### Waiting, in order

**Nothing is dispatched.** Briefs are written at dispatch time, not now - a brief written days
early is a brief written against a tree that has moved.

| # | Task | Model | Brief | Why this position |
|---|---|---|---|---|
| 2 | RV.157 | flash | *at dispatch* | **UNBLOCKED 2026-09-09**: implement the debounced write trigger (option a). The owner waived the battery cost and stated the governing rule - *save locally first, send to the cloud asynchronously* - so the save schedules a cycle and never awaits it |
| 3 | RV.154 | flash | *at dispatch* | Backend-only, no UI. Three DB round trips per record made the owner's import spend ~9 minutes pushing. Fixing it plausibly dissolves RV.155, so it goes first of the two |
| 4 | RV.152 | flash | *at dispatch* | The home-currency prompt. Design fully closed by the owner's two decisions (2026-09-09); [RV.151] shipping unblocked its "convert the log" answer |
| 5 | RV.149 | flash | *at dispatch* | The fill-up receipt photo fails silently - the same silent-loss class [PJ.28] fixed one screen over, reusing the string it added. Small |
| 7 | RV.155 | flash | *at dispatch* | The pull cursor regressed and re-fetched 274 records. Filed with its mechanism as a HYPOTHESIS; run it after RV.154, which may remove the 40-second window the overlap needs |
| 8 | RV.141 | flash | `agents/briefs/RV.141.md` | Brief already on disk from an earlier session - **re-read it against the current tree before dispatch**, several rows have moved since |
| 9 | RV.116 | flash | `agents/briefs/RV.116.md` | Same - brief exists, amended for Drivvo's silently-dropped columns, but predates this session's work |

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
| RV.156 | `2328757` | A station can be created, from the entry row and the Garage |
| RV.136 (reopened) | `0011cc3` | Vehicle compared at the decoded level - the third arm of the echo loop |
| RV.153 | `974be77` | A computed total no longer beats a printed one - main green again |
| RV.151 | `9760bfe` | The rate lookup derives the cross rate through the pack's base - the owner's 381 pending rows |
| RV.150 | `bc907c3` | A save writes the station fields the ranking reads; the location capture is the owner's decision, bounded |
| RV.117b | `6d833a7` | The conflict neighbourhood, drawn - RV.117 is now complete |

**Still open and NOT queued**: `RV.139` itself - the symptom is unfixed and the next step is one
device log from a build carrying the `rates.refresh` event, which is not agent work.

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
