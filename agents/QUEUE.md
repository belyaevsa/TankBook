# Dispatch queue

The order rows go out in, and why. One agent at a time - `opencode`'s session database throws
`database is locked` when two start in the same second, and the mid-run deaths at 250-500 KB of log
are memory pressure. Stagger dispatches; never run two builds in this checkout at once.

**Dispatch line** (`< /dev/null` is not optional - without it `opencode run` blocks on stdin,
writes zero bytes and sits forever, which reads exactly like a wedged provider):

```
nohup opencode run --auto --thinking -m <provider/model> --title "<id>" \
  "$(cat agents/briefs/<id>.md)" > /tmp/agentlogs/<id>.log 2>&1 < /dev/null &
```

Then arm ONE harness-tracked monitor per dispatch, on its PID.

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
