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
| **RV.146** | flash | 91030 | `bhb12p24j` | `agents/briefs/RV.146.md` |

### Waiting, in order

| # | Task | Model | Brief | Why this position |
|---|---|---|---|---|
| 2 | RV.147 | flash | `agents/briefs/RV.147.md` | `costPerKm` reuses the accumulator RV.145 reshapes, so it goes **after** it - its brief opens by telling the agent to verify RV.145 landed and to stop if it has not |
| 3 | RV.117a **[v1.1]** | flash | `agents/briefs/RV.117a.md` | The valid-interval math in core; boundary assertions make it mechanical. A point release, so it sits behind the v1 rows |
| 4 | RV.117b **[v1.1]** | - | *written after RV.117a lands* | The neighbourhood chart. Its shape depends on what RV.117a returns, so briefing it now would be guessing |
| 5 | PJ.28 **[v1.x]** | flash | `agents/briefs/PJ.28.md` | Owner priority. Half delivered by [RV.62]; only the ATTACHMENT remains, and it is the one row in the v1.1 queue that loses data |
| 6 | PJ.25 **[v1.x]** | flash | `agents/briefs/PJ.25.md` | Owner priority. A navigation row, not a feature one: the shelf is built and tested, it needs a door from the Garage |
| 7 | PJ.19 **[v1.1]** | flash | `agents/briefs/PJ.19.md` | Owner priority. The ranking and the permission-optional location are genuinely unbuilt; the row's "inert label" half is already stale |

### Shipped this session (2026-09-08/09)

| Task | Commit | What it was |
|---|---|---|
| RV.112 | `2efb9e3` | The vitals tile and Trends series stopped reporting a pending month as zero |
| RV.139-INVESTIGATE | `2efb9e3` | Read-only: three of RV.139's four candidates dead on a line each (`diagnostics/RV.139-INVESTIGATE.md`) |
| RV.144 | `5471bac` | An entry edit re-homes to the car's current home currency, and resolves at commit |
| RV.139b | `e92d147` | Observability so the next device log can answer RV.139; the row itself stays open |
| RV.136 | `85ba6d5` | A pull no longer re-dirties a Vehicle that did not change |
| RV.145 | `628d000` | A money figure carries its own currency; symbols everywhere. **RU screenshots re-captured by the orchestrator** |

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
