# Agent briefs

One file per dispatched agent task, named for its task id in `docs/TASKS.md`
(`P1.2.md` briefs task P1.2). **Every brief is written here before dispatch, not in a temp directory** –
these are the record of what an agent was actually asked to do, which is the only way to tell a bad
agent from a bad brief after the fact.

## Why they are kept

Three P0.12 runs produced zero files. The post-mortem was only possible because the brief could be read
back alongside the run log, and it showed the failure was ours twice over: the write fence was a
blacklist (`don't write to /tmp`) that an agent stepped around by writing to `/tmp_gen.swift` at the
filesystem root, and the task was too large to finish in one run. Neither was visible from the code,
because there was no code.

A brief is also the cheapest place to fix a recurring mistake: a fence added here is a mistake that does
not happen again.

## What a brief contains

The pattern these converged on, in order:

1. **Where you may write** – a whitelist (`only inside <repo>`), never a blacklist. A single rejected
   tool call kills an unattended run.
2. **Write code first, explore second** – the dominant failure mode is a run that reads everything and
   writes nothing.
3. **What NOT to explore** – closed questions, named. One run spent its whole budget cross-verifying
   Ed25519 across languages; it is standardised and the real risk was canonicalization.
4. **What already exists** – types, files and signatures the task builds on, so the agent does not
   redesign or duplicate them.
5. **Read before writing** – the specific docs, in order, with the authority for this task marked.
6. **What to build**, then **explicitly out of scope**.
7. **Tests, with current counts** – "`swift test` is 193 and must rise" is checkable; "add tests" is not.
8. **The baseline gate** – build + `swiftlint lint` exit 0, judged by exit code (`CLAUDE.md` rule 13).
9. **Report back** – exact numbers, and *whether tests were actually run* rather than only written.

## Conventions

- **Sized to finish in one run.** P0.12 delivered nothing three times as a single task, then went green
  in two runs once split into a/b/c. Nothing about the prompt changed; the size did.
- **Quote spec copy verbatim** (error strings, tolerances, invariants) rather than paraphrasing – a
  paraphrased error message ships as a paraphrased error message.
- **Name the vacuous-assertion traps** for that task. `#expect(true)`, asserting only that a call did not
  throw, or a "tamper" test that mutates a field the code never reads.
- A brief that turns out to be wrong is **edited and re-dispatched**, keeping the same file. Only a brief
  replaced by a different decomposition gets a `-superseded` suffix, kept for the record.
