# Tankbook – Task History

*The dispatch ledger, split out of `docs/TASKS.md` (2026-09-08) so the backlog can be read without
it. Nothing here is a task: it is the evidence behind the model-routing policy, which itself lives
in `HANDOVER.md` and the agent-routing memory.*

## Dispatch ledger - which model did which task
**Reconstructed 2026-09-05 from the `opencode` transcripts in `/tmp/agentlogs/*.log`**, where each run
records its own model. This is the ground truth behind the flash-vs-pro evaluation, and it is here so
a row's outcome can always be read against the worker that produced it.

**Totals: 24 pro, 20 flash** across 44 build dispatches. Read it with the selection bias in mind -
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
