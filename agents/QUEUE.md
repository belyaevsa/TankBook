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

| # | Task | Model | Brief | Why this model / this position |
|---|---|---|---|---|
| 1 | **RV.144** *(running)* | flash | `agents/briefs/RV.144.md` | Cause pinned to two lines; the owner's live bug |
| 2 | RV.145 | flash | *not yet written* | Cause pinned; carries the symbols-everywhere decision. Before RV.147, which builds on the accumulator it changes |
| 3 | RV.136 | flash | `agents/briefs/RV.136.md` | Mechanism pinned to `RecordMerge.swift:99-107` + `SyncEngine.swift:318-322`; acceptance is an unfakeable push count. **Escalate to pro if flash cannot reproduce the loop** - this is its third occurrence |
| 4 | RV.146 | flash | *not yet written* | Adaptive currency chips. Independent of the money rows; design closed by the RV.115 precedence |
| 5 | RV.147 | flash | *not yet written* | `costPerKm` reuses the accumulator RV.145 reshapes, so it goes after it |
| 6 | RV.117a **[v1.1]** | flash | `agents/briefs/RV.117a.md` | Interval math in core; boundary assertions make it mechanical. Point release, so it sits behind the v1 rows |
| 7 | RV.117b **[v1.1]** | — | *written after RV.117a lands* | The neighbourhood chart. Its shape depends on what RV.117a returns, so briefing it now would be guessing |

## Standing rules for every dispatch here

- The brief is written to `agents/briefs/<id>.md` **before** dispatch and passed by `cat`, so the
  brief on disk is exactly what the agent received.
- Health-check ~5 minutes in by **log bytes**. Zero bytes is wedged; freshness proves nothing,
  because nothing is written during model inference.
- The orchestrator verifies in its own hands - gates by exit code, and **opens every screenshot**.
  An agent has no image input and cannot see what it produced.
- Agents never commit and never tick `docs/TASKS.md`.
