# Tankbook – Task History

*The dispatch ledger, split out of `docs/TASKS.md` (2026-09-08) so the backlog can be read without
it. Nothing here is a task: it is the evidence behind the model-routing policy, which itself lives
in `HANDOVER.md` and the agent-routing memory.*

## Dispatch ledger - which model did which task
**Reconstructed 2026-09-05 from the `opencode` transcripts in `/tmp/agentlogs/*.log`**, where each run
records its own model. This is the ground truth behind the flash-vs-pro evaluation, and it is here so
a row's outcome can always be read against the worker that produced it.

**Totals: 24 pro, 20 flash** across the 44 build dispatches of 2026-09-03/05; **every build dispatch since 2026-09-10 ran on flash** (the 2026-09-12 block below: 34 dispatches, 58 rows, pro used only for the read-only scenario and journeys walks - 14 of them that day, not in this ledger). Read it with the selection bias in mind -
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
