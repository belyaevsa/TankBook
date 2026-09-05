# EVAL – is `deepseek-v4-flash` good enough for Tankbook's agent tasks, or is `deepseek-v4-pro` needed?

**You are an independent evaluator. You are NOT fixing anything.** Produce a verdict backed by
evidence from this repository's actual history. **Do not modify any file. Do not run `git add`,
`git commit`, or any test.** Read only.

## The question

The orchestrator dispatches implementation tasks to `opencode` agents on one of two models:
`deepseek/deepseek-v4-flash` (fast, cheap) or `deepseek/deepseek-v4-pro` (slow, expensive). On
2026-09-05 the product owner set a new policy: **flash by default; diagnose the cause myself first;
escalate to pro only after flash fails or when the work is genuine architecture change.**

**Was that policy right?** Specifically:

1. Did pro-dispatched tasks produce work that flash demonstrably could not have?
2. Did flash-dispatched tasks fail, or need rework, in ways attributable to the model?
3. Is there a task SHAPE that genuinely needs pro, and can you characterise it?
4. Is the "diagnose first, then flash" step doing the real work - i.e. is task difficulty better
   predicted by brief quality than by model?

## The evidence, and where it is

- **`/tmp/dispatch-index.csv`** - `task,model,logbytes` for 44 dispatches. This is the ground truth
  for which model ran which task.
- **`/tmp/agentlogs/<task>.log`** - the full agent transcript for each, including its own reasoning,
  its tool calls, its self-reported exit codes and its final report.
- **`agents/briefs/<task>.md`** - the brief each agent was given. **Read these**: a brief that
  already names the cause to a file and line makes a task mechanical regardless of model, which is
  the policy's central claim.
- **`docs/TASKS.md`** - every task's row. A row marked `[x]` carries the ORCHESTRATOR'S OWN
  verification: captured exit codes, test counts, mutation results, and what was found wrong. This
  is independent of the agent's self-report and is the best outcome signal available.
- **`git log`** - commit messages record what actually landed and what the orchestrator judged.

## How to judge - read this before starting

**Do not score on the agent's self-report.** Agents report their own success. Use the orchestrator's
verification in `docs/TASKS.md` and the commit messages, which repeatedly caught things agents
missed or misreported.

**Look for these specific signals rather than a general impression:**

- **Rework**: did a task come back, get re-dispatched, or need the orchestrator to fix it?
- **Wrong-but-green**: did an agent produce passing tests that did not test the thing? The repo
  calls these "vacuous assertions" and the briefs name them explicitly.
- **Refusals and negatives**: did the agent decline to do something unjustified, or report "I
  checked and there is no bug"? These are QUALITY signals, not failures. Examples to check:
  `RV.56` (declined to resolve receipt-047 and reported a lower number than predicted), `RV.60`
  (concluded there was no bug), `RV.67` (reported a suspected race did not reproduce).
- **Design above the brief**: did the agent produce a better shape than asked? Check `RV.63`
  (`ForAccount`/`ForEmail`), `RV.62` (`ExpensePrefill` with no liters member).
- **Escalations**: did the agent correctly stop and flag a decision above its authority? Check
  `RV.53` (hard rule 9, a fourth content store).
- **Known failures**: `RV.58` shipped a screenshot that was byte-identical to its EN counterpart
  while claiming an RU capture. `RV.52` was interrupted mid-mutation. Judge whether these are
  model-attributable or process-attributable.

**Confounders you must address explicitly, or your verdict is not usable:**

1. **Selection bias.** Pro was chosen for tasks BELIEVED harder. A raw success-rate comparison is
   therefore meaningless. You must control for this - e.g. by comparing tasks of similar brief
   quality and similar diff size across models.
2. **Brief quality improved over time.** Later briefs carry named causes, named vacuous traps and
   named fences; earlier ones do not. Flash was used more heavily LATER. Separate "flash is fine"
   from "late briefs are better".
3. **Verification improved over time too.** The orchestrator caught more later. Absence of a
   recorded defect in an early task may mean it was not looked for.

## Deliverable

A written verdict, in this order:

1. **The answer in one paragraph** - is flash sufficient, and under what conditions.
2. **The evidence table** - task, model, outcome, and the one fact that decides it.
3. **The task shape (if any) that genuinely needs pro** - characterised so it can be applied to a
   future brief before dispatch, not after.
4. **Where you think the current policy is WRONG or risky**, if anywhere. Say so plainly.
5. **What you could not determine from the evidence**, and what would settle it.

**Length: aim for 800-1500 words.** Cite task ids for every claim. If the evidence does not support
a confident verdict, say that - a hedged answer with reasons is more useful than a confident one
that the data does not carry.
