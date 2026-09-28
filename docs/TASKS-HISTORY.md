# Tankbook – Task History

*The dispatch ledger, split out of `docs/TASKS.md` (2026-09-08) so the backlog can be read without
it. Nothing here is a task: it is the evidence behind the model-routing policy, which itself lives
in `HANDOVER.md` and the agent-routing memory.*

## Dispatch ledger - which model did which task
**Reconstructed 2026-09-05 from the `opencode` transcripts in `/tmp/agentlogs/*.log`**, where each run
records its own model. This is the ground truth behind the flash-vs-pro evaluation, and it is here so
a row's outcome can always be read against the worker that produced it.

**Totals: 24 pro, 20 flash** across the 44 build dispatches of 2026-09-03/05; **every build dispatch since 2026-09-10 ran on flash** (the 2026-09-12 block below: 34 dispatches, 58 rows, pro used only for the read-only scenario and journeys walks - 14 of them that day, not in this ledger; the 2026-09-13 block: 15 dispatches, 14 rows and two corpus registrations, every walk run by the orchestrator). Read it with the selection bias in mind -
pro was chosen for tasks *believed* harder, so a raw success comparison carries no information; what
the evaluation compared was failure KINDS and above-brief judgement. `flash*` marks the dispatch that
died instantly with `database is locked` and never reached the model (re-dispatched on flash).

| Task | Worker | Date | Log |
|---|---|---|---|
| `RV.10` | **flash** | 2026-09-03 | 436 KB |
| `RV.14` | **pro** | 2026-09-03 | 415 KB |
| `RV.17` | **pro** | 2026-09-03 | 514 KB |
| `RV.18` | **pro** | 2026-09-03 | 293 KB |
| `RV.21` | **flash** | 2026-09-03 | 464 KB |
| `RV.22` | **pro** | 2026-09-03 | 573 KB |
| `RV.23-VALIDATE` | **pro** | 2026-09-03 | 135 KB |
| `RV.24` | **pro** | 2026-09-03 | 436 KB |
| `RV.25` | **flash** | 2026-09-03 | 180 KB |
| `RV.26` | **pro** | 2026-09-03 | 399 KB |
| `RV.28` | **flash** | 2026-09-03 | 401 KB |
| `RV.29` | **flash** | 2026-09-03 | 376 KB |
| `RV.31` | **flash** | 2026-09-03 | 439 KB |
| `RV.32` | **pro** | 2026-09-03 | 425 KB |
| `RV.34-RV.33` | **pro** | 2026-09-03 | 698 KB |
| `RV.35` | **pro** | 2026-09-03 | 312 KB |
| `RV.36` | **pro** | 2026-09-03 | 119 KB |
| `RV.37` | **pro** | 2026-09-03 | 577 KB |
| `RV.38` | **pro** | 2026-09-04 | 809 KB |
| `RV.40-39-41` | **pro** | 2026-09-04 | 457 KB |
| `RV.42` | **pro** | 2026-09-04 | 176 KB |
| `RV.43` | **flash** | 2026-09-04 | 111 KB |
| `RV.43.dblocked` | **flash*** | 2026-09-04 | 0 KB |
| `RV.44` | **pro** | 2026-09-04 | 381 KB |
| `RV.45` | **pro** | 2026-09-04 | 343 KB |
| `RV.47` | **flash** | 2026-09-04 | 488 KB |
| `RV.49` | **pro** | 2026-09-04 | 876 KB |
| `RV.50` | **pro** | 2026-09-04 | 518 KB |
| `RV.52` | **pro** | 2026-09-04 | 414 KB |
| `RV.53` | **flash** | 2026-09-04 | 366 KB |
| `RV.56` | **pro** | 2026-09-04 | 681 KB |
| `RV.57` | **pro** | 2026-09-04 | 478 KB |
| `RV.6` | **flash** | 2026-09-04 | 498 KB |
| `RV.6-INVESTIGATE` | **pro** | 2026-09-04 | 86 KB |
| `RV.61` | **pro** | 2026-09-04 | 400 KB |
| `RV.62` | **flash** | 2026-09-04 | 479 KB |
| `RV.63` | **flash** | 2026-09-04 | 202 KB |
| `OB.2` | **flash** | 2026-09-05 | 595 KB |
| `RV.54` | **flash** | 2026-09-05 | 345 KB |
| `RV.58` | **flash** | 2026-09-05 | 511 KB |
| `RV.60` | **flash** | 2026-09-05 | 171 KB |
| `RV.64` | **flash** | 2026-09-05 | 227 KB |
| `RV.65` | **flash** | 2026-09-05 | 1536 KB |
| `RV.67` | **flash** | 2026-09-05 | 515 KB |
| `RV.68` | **flash** | 2026-09-05 | 596 KB |
| `RV.185+RV.187` | **flash** | 2026-09-10 | 444 KB |
| `RV.186+RV.188` | **flash** | 2026-09-10 | 740 KB |
| `RV.183+RV.184` | **flash** | 2026-09-10 | 392 KB |
| `RV.176+PR.28` | **flash** | 2026-09-10 | 700 KB |
| `RV.212+RV.213+RV.224` | **flash** | 2026-09-12 | 416 KB |
| `RV.214` | **flash** | 2026-09-12 | 420 KB |
| `RV.215` | **flash** | 2026-09-12 | 620 KB |
| `RV.243` | **flash** | 2026-09-12 | 548 KB |
| `RV.244` | **flash** | 2026-09-12 | 76 KB |
| `PJ.61` | **flash** | 2026-09-12 | 300 KB |
| `RV.247` | **flash** | 2026-09-12 | 276 KB |
| `RV.250` | **flash** | 2026-09-12 | 196 KB |
| `RV.155` | **flash** | 2026-09-12 | 316 KB |
| `RV.108` | **flash** | 2026-09-12 | 284 KB |
| `RV.143` | **flash** | 2026-09-12 | 276 KB |
| `PJ.58` | **flash** | 2026-09-12 | 204 KB |
| `RV.158+RV.138` | **flash** | 2026-09-12 | 352 KB |
| `PJ.59` | **flash** | 2026-09-12 | 452 KB |
| `RV.255` | **flash** | 2026-09-12 | 364 KB |
| `RV.253` | **flash** | 2026-09-12 | 520 KB |
| `RV.249` | **flash** | 2026-09-12 | 276 KB |
| `RV.239` | **flash** | 2026-09-12 | 604 KB |
| `RV.259` | **flash** | 2026-09-12 | 400 KB |
| `RV.260` | **flash** | 2026-09-12 | 764 KB |
| `RV.261` | **flash** | 2026-09-12 | 412 KB |
| `RV.226` | **flash** | 2026-09-12 | 276 KB |
| `RV.251+PJ.100+PJ.101+PJ.200` | **flash** | 2026-09-12 | 512 KB |
| `RV.228` | **flash** | 2026-09-12 | 244 KB |
| `RV.241` | **flash** | 2026-09-12 | 204 KB |
| `RV.263` | **flash** | 2026-09-12 | 492 KB |
| `RV.227+RV.235` | **flash** | 2026-09-12 | 736 KB |
| `RV.229` | **flash** | 2026-09-12 | 320 KB |
| `RV.256` | **flash** | 2026-09-12 | 304 KB |
| `RV.257+RV.258` | **flash** | 2026-09-12 | 340 KB |
| `RV.245` | **flash** | 2026-09-12 | 272 KB |
| `RV.264+RV.265` | **flash** | 2026-09-12 | 312 KB |
| `RV.267` | **flash** | 2026-09-12 | 236 KB |
| `RV.269` | **flash** | 2026-09-12 | 308 KB |
| `RV.246` | **flash** | 2026-09-12 | 290 KB |
| `PJ.60` | **flash** | 2026-09-12 | 309 KB |
| `RV.240+RV.268` | **flash** | 2026-09-12 | 513 KB |
| `RV.270` | **flash** | 2026-09-12 | 247 KB |
| `RV.234` | **flash** | 2026-09-12 | 463 KB |
| `RV.248` | **flash** | 2026-09-13 | 435 KB |
| `RV.271` | **flash** | 2026-09-13 | 454 KB |
| `RV.272+RV.273` | **flash** | 2026-09-13 | 595 KB |
| `RV.274` | **flash** | 2026-09-13 | 273 KB |
| `RV.275` | **flash** | 2026-09-13 | 375 KB |
| `RV.277` | **flash** | 2026-09-13 | 471 KB (second run; the first was stopped at 161 KB when the owner widened the scope) |
| `RV.278` | **flash** | 2026-09-13 | 359 KB |
| `RV.276` | **flash** | 2026-09-13 | 615 KB |
| `RV.279` | **flash** | 2026-09-13 | 494 KB |
| `RV.280` | **flash** | 2026-09-13 | 190 KB |
| `PJ.29` | **flash** | 2026-09-13 | 623 KB |
| `PJ.29a` | **flash** | 2026-09-13 | 476 KB |
| `RV.281` | **orchestrator** (catalog edit, no dispatch) | 2026-09-13 | - |
| `CORPUS-2026-09-13` | **flash** | 2026-09-13 | 817 KB |
| `CORPUS-2026-09-13b` | **flash** | 2026-09-13 | 375 KB |
| `RV.282` | **flash** | 2026-09-13 | 454 KB |
| `CORPUS-2026-09-14` | **codex sol** (`gpt-5.6-sol`; flash dead at the banner, opencode DB bloated; the run hit the Codex usage cap at its report) | 2026-09-14 | 5.2 MB |
| `RV.284` | **pro** (flash dead) | 2026-09-14 | 507 KB |
| `RV.285` | **pro** (flash dead) | 2026-09-14 | 193 KB |
| `RV.286` | **flash** (answered the probe again) | 2026-09-15 | 238 KB |
| `RV.181` (file share) | **flash** | 2026-09-15 | 286 KB |

## What the four grouped dispatches of 2026-09-10 cost to verify

All four ran on flash and all four produced work worth shipping. **All four also needed the
orchestrator to catch something the agent's own report said was fine**, which is the evidence behind
the standing rule that a report is not a gate:

| Dispatch | What the report claimed | What checking found |
|---|---|---|
| `RV.185+RV.187` | `swiftlint` exit 0; two screenshots showing the new name field | Lint exited **2** on a file-length ceiling, and **neither frame contained the field**. The pre-filled name was still the exporter's own ("Drivvo") - the half of the owner's report the agent left in place |
| `RV.186+RV.188` | Green, with the session's best mutation | True. But the chart placed its labels by point INDEX, so two of three **overprinted at one corner** - visible only by opening the screenshot, because a UI test finds a label by identifier while it sits underneath another one |
| `RV.183+RV.184` | Green, and the brief's hypothesis was **incomplete** - said so unprompted | Correct on both counts. The real scanned-save path used a second builder the brief did not name; fixing only the named one would have left a real scan blank |
| `RV.176+PR.28` | 198 orphans audited, all given lines | True, but **138 of those lines were never run** - their seeds were inferred. A wrong line is worse than none: the check goes green on a line EXISTING, not on it reproducing the frame. Filed as `RV.194` |

**Three of the four were caught by opening a screenshot**, which no agent can do.

## Rows moved out of `TASKS.md` on 2026-09-27

*The owner asked for the backlog to be cleaned: every closed row (`[x]` done, `[cut]`) moved to `TASKS-DONE.md` under the
section it was filed in (111 rows). This is their ledger. **Worker** is what the row itself records - its `Routing` note is
the plan written when it was filed, not proof of who ran it - except the six the orchestrator closed in this session, which are
known, and the AD rows, which the owner had built in the session rather than dispatched. The closing date is the last dated close marker in the row, blank where it names none.*

| Task | Status | Closed | Worker |
|---|---|---|---|
| `SH.8` | done |  | routed: the orchestrator |
| `PJ.501` | done | 2026-09-26 | not recorded in the row |
| `PJ.502` | done | 2026-09-26 | not recorded in the row |
| `PJ.504` | done | 2026-09-26 | not recorded in the row |
| `PJ.505` | done |  | not recorded in the row |
| `PJ.506` | done |  | not recorded in the row |
| `DC.1` | done |  | not recorded in the row |
| `RV.179` | done | 2026-09-19 | not recorded in the row |
| `RV.114` | done | 2026-09-19 | not recorded in the row |
| `RV.288` | done | 2026-09-19 | not recorded in the row |
| `RV.292` | done | 2026-09-19 | not recorded in the row |
| `RV.302` | done | 2026-09-23 | not recorded in the row |
| `RV.303` | done | 2026-09-22 | not recorded in the row |
| `RV.301` | done | 2026-09-24 | routed: DeepSeek `v4.1-flash` (the cause is pinned in the row); review Codex `gpt-6-sol` |
| `RV.304` | done |  | not recorded in the row |
| `RV.305` | done |  | not recorded in the row |
| `RV.306` | done | 2026-09-25 | routed: DeepSeek `v4-pro` (mechanical); review Codex `gpt-6-sol` |
| `RV.307` | done |  | not recorded in the row |
| `PU.1` | done | 2026-09-19 | not recorded in the row |
| `PU.2` | done | 2026-09-19 | not recorded in the row |
| `PU.3` | done | 2026-09-19 | not recorded in the row |
| `PU.4` | cut | 2026-09-24 | not recorded in the row |
| `PU.5` | cut | 2026-09-24 | not recorded in the row |
| `PU.7` | done | 2026-09-19 | not recorded in the row |
| `PU.8` | done | 2026-09-19 | not recorded in the row |
| `PU.9` | done | 2026-09-19 | not recorded in the row |
| `PU.10` | done | 2026-09-19 | not recorded in the row |
| `PU.16` | done | 2026-09-19 | not recorded in the row |
| `PU.17` | done | 2026-09-19 | not recorded in the row |
| `PU.18` | done | 2026-09-19 | not recorded in the row |
| `PU.19` | done | 2026-09-21 | not recorded in the row |
| `PU.20` | done | 2026-09-19 | not recorded in the row |
| `PU.27` | done | 2026-09-19 | not recorded in the row |
| `PU.28` | done | 2026-09-19 | not recorded in the row |
| `PU.21` | done | 2026-09-19 | not recorded in the row |
| `PU.22` | done | 2026-09-19 | not recorded in the row |
| `PU.23` | done | 2026-09-19 | not recorded in the row |
| `PU.24` | done | 2026-09-21 | not recorded in the row |
| `PU.29` | done | 2026-09-19 | not recorded in the row |
| `PU.30` | done | 2026-09-20 | not recorded in the row |
| `PU.31` | done | 2026-09-20 | not recorded in the row |
| `PU.33` | done | 2026-09-20 | not recorded in the row |
| `PU.34` | cut | 2026-09-24 | not recorded in the row |
| `PU.35` | done | 2026-09-21 | not recorded in the row |
| `PU.37` | done | 2026-09-21 | not recorded in the row |
| `PU.38` | done | 2026-09-21 | not recorded in the row |
| `PU.39` | done | 2026-09-21 | not recorded in the row |
| `PU.42` | done | 2026-09-22 | not recorded in the row |
| `PU.43` | done |  | not recorded in the row |
| `PU.44` | done |  | not recorded in the row |
| `PU.45` | done |  | not recorded in the row |
| `PU.46` | done |  | not recorded in the row |
| `PU.47` | done |  | not recorded in the row |
| `PU.48` | cut | 2026-09-24 | not recorded in the row |
| `PU.49` | done | 2026-09-26 | not recorded in the row |
| `PU.50` | done |  | not recorded in the row |
| `PU.51` | done |  | not recorded in the row |
| `PU.53` | done | 2026-09-22 | not recorded in the row |
| `PU.54` | cut | 2026-09-24 | not recorded in the row |
| `PU.55` | cut | 2026-09-24 | not recorded in the row |
| `PU.57` | done | 2026-09-22 | not recorded in the row |
| `PU.58` | cut |  | not recorded in the row |
| `PU.60` | done | 2026-09-22 | not recorded in the row |
| `PU.61` | done | 2026-09-27 | orchestrator (Claude, the 2026-09-26/27 session), not dispatched |
| `PU.62` | done | 2026-09-22 | not recorded in the row |
| `PU.63` | done | 2026-09-23 | not recorded in the row |
| `PJ.500` | done | 2026-09-23 | not recorded in the row |
| `PU.64` | done |  | not recorded in the row |
| `PU.65` | cut | 2026-09-24 | not recorded in the row |
| `PU.66` | cut | 2026-09-24 | not recorded in the row |
| `PU.67` | cut | 2026-09-24 | not recorded in the row |
| `PU.68` | done |  | not recorded in the row |
| `PU.78` | done | 2026-09-24 | not recorded in the row |
| `PU.81` | cut | 2026-09-24 | not recorded in the row |
| `PU.79` | done |  | not recorded in the row |
| `PU.80` | done | 2026-09-23 | not recorded in the row |
| `PU.69` | done |  | not recorded in the row |
| `PU.70` | cut | 2026-09-24 | not recorded in the row |
| `PU.71` | cut | 2026-09-24 | not recorded in the row |
| `PU.72` | done | 2026-09-24 | not recorded in the row |
| `PU.73` | done |  | not recorded in the row |
| `PU.74` | done |  | not recorded in the row |
| `PU.76` | done | 2026-09-25 | routed: research note and the spike's review Qwen 3.8 max (the most valuable and vaguest open research - the method ch |
| `PU.82` | done |  | routed: DeepSeek `v4.1-flash` (a data change); review Codex `gpt-6-sol` |
| `PU.83` | done | 2026-09-24 | routed: DeepSeek `v4.1-flash` (tooling); review Codex `gpt-6-sol` |
| `PU.84` | done | 2026-09-26 | routed: a light research note DeepSeek `v4.1-flash` (PU.73's note already measured the ceiling); build by the orchestr |
| `PU.85` | done |  | not recorded in the row |
| `PU.86` | done | 2026-09-25 | not recorded in the row |
| `PU.89` | done | 2026-09-25 | not recorded in the row |
| `PU.93` | done | 2026-09-27 | orchestrator (Claude, the 2026-09-26/27 session), not dispatched |
| `PU.88` | done | 2026-09-25 | not recorded in the row |
| `PU.87` | done | 2026-09-25 | not recorded in the row |
| `PU.6` | done | 2026-09-27 | orchestrator (Claude, the 2026-09-26/27 session), not dispatched |
| `PU.96` | done | 2026-09-27 | orchestrator (Claude, the 2026-09-26/27 session), not dispatched |
| `PU.98` | done | 2026-09-26 | orchestrator (Claude, the 2026-09-26/27 session), not dispatched |
| `PU.99` | done | 2026-09-27 | orchestrator (Claude, the 2026-09-26/27 session), not dispatched |
| `PU.100` | done | 2026-09-27 | routed: the orchestrator |
| `AD.1` | done |  | orchestrator (Claude session; owner 2026-09-24: "don't dispatch this work to opencode, do it by yourself") |
| `AD.3` | done |  | orchestrator (Claude session; owner 2026-09-24: "don't dispatch this work to opencode, do it by yourself") |
| `DC.2` | done |  | not recorded in the row |
| `DC.3` | done |  | not recorded in the row |
| `PU.97` | done |  | not recorded in the row |
| `RV.309` | done |  | not recorded in the row |
| `RV.310` | done |  | not recorded in the row |
| `AD.10` | done |  | orchestrator (Claude session; owner 2026-09-24: "don't dispatch this work to opencode, do it by yourself") |
| `AD.11` | done |  | orchestrator (Claude session; owner 2026-09-24: "don't dispatch this work to opencode, do it by yourself") |
| `AD.13` | done |  | orchestrator (Claude session; owner 2026-09-24: "don't dispatch this work to opencode, do it by yourself") |
| `AD.14` | done |  | orchestrator (Claude session; owner 2026-09-24: "don't dispatch this work to opencode, do it by yourself") |
| `AD.4` | done |  | orchestrator (Claude session; owner 2026-09-24: "don't dispatch this work to opencode, do it by yourself") |
| `AD.5` | done |  | orchestrator (Claude session; owner 2026-09-24: "don't dispatch this work to opencode, do it by yourself") |
| `AD.6` | done |  | orchestrator (Claude session; owner 2026-09-24: "don't dispatch this work to opencode, do it by yourself") |
| `PU.94` | cut | 2026-09-27 | not built; cut by the owner (single-shot only) |
| `PU.106` | done | 2026-09-27 | orchestrator (Claude session), from the Kimi K3 research note `agents/research/KNIFE-EDGE.md` |
| `SH.11` | done | 2026-09-28 | orchestrator (Claude session), not dispatched |
| `SH.12` | done | 2026-09-28 | orchestrator (Claude session), not dispatched |
| `SH.13` | done | 2026-09-28 | orchestrator (Claude session), not dispatched |
| `SH.14` | done | 2026-09-28 | orchestrator (Claude session), not dispatched |
| `RV.318` | done | 2026-09-28 | orchestrator (Claude session), not dispatched |
| `RV.320` | done | 2026-09-28 | orchestrator (Claude session), not dispatched |
| `RV.319` | done | 2026-09-28 | orchestrator (Claude session), not dispatched |
